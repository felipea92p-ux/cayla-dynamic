-- ============================================================================
-- 0448 — La negativa pide motivo y el reemplazo de archivo queda auditado
-- ============================================================================
--
-- QUÉ PROMETE
--
--   Dos huecos de trazabilidad de `fn_documento_registrar`, encontrados en la
--   auditoría UX/funcional de admin/documentacion (2026-09-14), se cierran:
--
--   1. Registrar que alguien «se negó a firmar» (`p_es_negativa = true`) ya
--      exige un motivo de al menos 3 caracteres en `p_nota`. Antes era
--      opcional: quedaba quién y cuándo, pero podía no quedar ningún porqué
--      para una acción con peso legal (afecta si la persona cobra movilidad
--      ese periodo; el propio encabezado de la 0157 cita la RTF
--      05449-4-2007 y el Exp. 1038-2019 como el riesgo real detrás de esto).
--
--   2. Enlazar o reemplazar el archivo de un documento ya existente
--      (`p_id is not null` — lo que la pantalla llama «Subir firmada» /
--      «Subir otra» / «Reemplazar») ahora deja un registro en
--      `correcciones_auditoria`: quién lo hizo, cuándo, y el `storage_path`
--      anterior contra el nuevo. Antes esa rama hacía el `update` y volvía
--      sin dejar ningún rastro — se podía sobrescribir en silencio el papel
--      que sostiene un pago de movilidad, sin saber quién lo cambió ni cuál
--      era el archivo anterior.
--
-- QUÉ NO HACE, A PROPÓSITO
--
--   No agrega un CHECK de tabla que exija motivo en toda fila con
--   `es_negativa = true`. Un CHECK nuevo se aplica retroactivamente a las
--   filas que YA existen en producción, y esta migración no tiene forma de
--   saber si alguna negativa histórica quedó sin nota — pegarlo así podría
--   romper `supabase db reset` el día que alguien reconstruya el esquema
--   desde cero contra un volcado con esas filas. La exigencia se pone en la
--   ÚNICA puerta de escritura (`fn_documento_registrar`; la tabla no tiene
--   policy de INSERT para `authenticated`, así que no hay otro camino), que
--   cubre toda negativa nueva sin tocar el historial.
--
--   No bloquea el reemplazo cuando ya había un archivo (no obliga a Anular +
--   volver a subir). Cierra el hueco de auditoría del camino que ya existe,
--   no cambia el flujo de uso — eso fue una alternativa evaluada con Felipe
--   y descartada por agregar fricción a un caso hoy común (reemplazar un
--   escaneo borroso) sin que se haya pedido ese cambio de comportamiento.
--
-- QUÉ ASUME
--
--   `fn_documento_registrar` vigente es la 0424 (confirmado el 2026-09-14
--   con `./scripts/donde-vive.sh fn_documento_registrar`, y el cuerpo
--   comprobado además contra el Postgres local por psql directo:
--   `length(prosrc) = 4901`, sin diferencia con el texto de la 0424). La
--   firma no cambia (mismos 10 parámetros, mismo orden, mismo tipo de
--   retorno) — sigue siendo `create or replace`, no hace falta `drop`.
--
--   `correcciones_auditoria.motivo` ya es `not null` con
--   `check (length(trim(motivo)) >= 3)` desde la 0001 — el insert nuevo de
--   la rama de enlazar archivo se apoya en esa garantía existente, no
--   agrega una propia.
--
-- CÓMO SE REVIERTE
--
--   Pegar de nuevo el cuerpo de la 0424 tal cual está en el repositorio
--   (`create or replace function fn_documento_registrar(...)`, sin las dos
--   validaciones de esta migración) — no hay columnas ni constraints nuevos
--   que deshacer, solo lógica dentro de la función.
--
-- ============================================================================

create or replace function fn_documento_registrar(
  p_tipo            text,
  p_fecha_firma     date,
  p_persona_id      uuid    default null,
  p_ruta_declarada  text    default null,
  p_monto_declarado numeric default null,
  p_anio            integer default null,
  p_es_negativa     boolean default false,
  p_nota            text    default null,
  p_storage_path    text    default null,
  p_id              uuid    default null   -- no nulo = enlazar el archivo recién subido
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id           uuid;
  v_alcance      text;
  v_yo           uuid := fn_persona_actual_id();
  -- ⇩⇩⇩ CAMBIO 0448 ⇩⇩⇩ para auditar la rama de enlazar archivo.
  v_persona_doc  uuid;
  v_tipo_doc     text;
  v_archivo_ant  text;
  -- ⇧⇧⇧ CAMBIO 0448 ⇧⇧⇧
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional registra documentos firmados.';
  end if;

  if p_tipo not in ('ruta', 'politica', 'bono') then
    raise exception 'Tipo de documento inválido: «%».', p_tipo;
  end if;

  -- El alcance no se recibe: se deduce del tipo, que es lo único que puede
  -- decidirlo. Recibirlo abriría la puerta a una ruta declarada «de empresa».
  v_alcance := case when p_tipo = 'politica' then 'empresa' else 'individual' end;

  if p_fecha_firma is null then
    raise exception 'Falta la fecha en que se firmó el documento.';
  end if;
  if p_fecha_firma > fn_hoy_lima() then
    raise exception 'La fecha de firma no puede ser futura.';
  end if;

  -- Enlazar el archivo a una fila que ya existe.
  if p_id is not null then
    -- ⇩⇩⇩ CAMBIO 0448 ⇩⇩⇩ Antes este bloque actualizaba y volvía sin dejar
    -- ningún rastro de quién reemplazó el archivo ni de cuál era el
    -- anterior. `select ... for update` bloquea la fila y captura el
    -- `storage_path` de ANTES, en el mismo momento en que se decide el
    -- cambio — no después, que es cuando ya se perdió.
    select persona_id, tipo, storage_path
      into v_persona_doc, v_tipo_doc, v_archivo_ant
      from documentos_firmados
     where id = p_id and anulado_at is null
     for update;
    if not found then raise exception 'Ese documento no existe o está anulado.'; end if;

    update documentos_firmados
       set storage_path = coalesce(p_storage_path, storage_path)
     where id = p_id;

    insert into correcciones_auditoria
      (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values
      (coalesce(v_persona_doc, v_yo),
       'documento_archivo_reemplazado',
       coalesce(v_archivo_ant, '(sin archivo)'),
       coalesce(p_storage_path, v_archivo_ant, '(sin archivo)'),
       v_yo,
       v_tipo_doc || ' · se reemplazó el archivo firmado');
    -- ⇧⇧⇧ CAMBIO 0448 ⇧⇧⇧

    return p_id;
  end if;

  -- ⇩⇩⇩ CAMBIO 0448 ⇩⇩⇩ Una negativa sin motivo quedaba con quién y cuándo,
  -- pero sin ningún porqué — ver «QUÉ PROMETE» arriba.
  if coalesce(p_es_negativa, false) and
     (p_nota is null or length(trim(p_nota)) < 3) then
    raise exception 'Para registrar que se negó a firmar hace falta anotar el motivo (mínimo 3 caracteres).';
  end if;
  -- ⇧⇧⇧ CAMBIO 0448 ⇧⇧⇧

  if v_alcance = 'individual' then
    if p_persona_id is null then
      raise exception 'Falta de quién es el documento.';
    end if;
    if not exists (select 1 from personas where id = p_persona_id and estado = 'activo') then
      raise exception 'Esa persona no existe o no está activa.';
    end if;
    -- La ruta admite a quien es practicante (0397/0424); el bono se queda
    -- exactamente como estaba, con `en_planilla` a secas.
    if p_tipo = 'ruta' and not fn_persona_le_corresponde_movilidad(p_persona_id) then
      raise exception 'Esa persona no está en planilla ni es practicante: no le corresponde declarar su ruta.';
    end if;
    if p_tipo = 'bono' and not exists (
      select 1 from personas where id = p_persona_id and en_planilla
    ) then
      raise exception 'Esa persona no está en planilla: no le corresponde ese documento.';
    end if;
  elsif p_persona_id is not null then
    raise exception 'La política de movilidad la emite CAYLA: no se atribuye a una persona.';
  end if;

  if p_tipo = 'bono' and p_anio is null then
    raise exception 'Falta de qué año es la constancia del bono.';
  end if;

  -- ── REEMPLAZAR ES REEMPLAZAR (0211) ──────────────────────────────────
  -- Una política nueva anula la anterior. Ver 0211/0424 para la historia
  -- completa de por qué esto tiene que pasar antes del insert.
  if p_tipo = 'politica' and p_id is null then
    update documentos_firmados
       set anulado_at = now(),
           anulado_por = v_yo,
           anulado_motivo = 'Reemplazada por la política firmada el ' ||
                            to_char(p_fecha_firma, 'DD/MM/YYYY')
     where tipo = 'politica' and anulado_at is null;
  end if;
  insert into documentos_firmados (
    alcance, persona_id, tipo, storage_path, fecha_firma,
    ruta_declarada, monto_declarado, anio, es_negativa, nota, registrado_por
  ) values (
    v_alcance, p_persona_id, p_tipo, p_storage_path, p_fecha_firma,
    nullif(trim(coalesce(p_ruta_declarada, '')), ''),
    case when p_es_negativa then null else p_monto_declarado end,
    p_anio, coalesce(p_es_negativa, false),
    nullif(trim(coalesce(p_nota, '')), ''), v_yo
  )
  returning id into v_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (coalesce(p_persona_id, v_yo),
     case when p_es_negativa then 'documento_negativa' else 'documento_firmado' end,
     null,
     p_tipo || ' · firmado el ' || p_fecha_firma::text,
     v_yo,
     case when p_es_negativa
          then 'Se registró la negativa a firmar'
          else 'Alta de documento firmado' end);

  return v_id;
end;
$$;

grant execute on function fn_documento_registrar(text,date,uuid,text,numeric,integer,boolean,text,text,uuid)
  to authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (448, 'la_negativa_pide_motivo_y_el_reemplazo_queda_auditado')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select prosrc like '%CAMBIO 0448%' as candado_presente
  from pg_proc where proname = 'fn_documento_registrar';
