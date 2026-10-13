-- ============================================================================
-- 0518 — El bono de cumpleaños también es para quien es practicante
-- ============================================================================
--
-- QUÉ PROMETE
--
--   Que quien es practicante (`tipo_vinculo = 'practicante'`) vea, pida y
--   firme su bono de cumpleaños igual que quien está en planilla: desde el
--   primer día del mes de su cumpleaños, desde su Info, con su firma digital,
--   y que el bono entre a su boleta como a cualquiera (0479, sin cambios).
--   Y que Desarrollo Organizacional (DO) pueda registrarle el cargo en papel.
--
--   Decidido por Cayla el 2026-10-13: «Todos deberían verlo».
--
-- EL DEFECTO, VISTO EN VIVO
--
--   Daniel Ruiz es practicante (0424 lo midió en producción) y cumple en
--   octubre. El 2026-10-13 no tenía nada en su Info ni en su Bandeja, mientras
--   DO sí lo veía en la suya como «Bono de cumpleaños sin constancia firmada».
--   Reproducido en el Postgres local con un perfil igual (practicante, cumple
--   en octubre) contra un control en planilla:
--
--     fn_documentos_tablero  (lo que ve DO)        → este_mes
--     fn_mi_bono_cumpleanos  (lo que ve él)        → no_aplica
--     fn_mi_bono_cumpleanos  (control en planilla) → este_mes, S/ 180
--
--   Dos funciones contestando distinto sobre la misma persona. La 0478 ya lo
--   había dejado anotado como pendiente en `docs/estado.md`; quedaba por
--   decidir hacia qué lado se cerraba. Esta migración lo cierra hacia el lado
--   del tablero: el tablero ya tenía razón con la regla nueva, y no se toca.
--
-- DECIDÍ:     una función nueva, `fn_persona_le_corresponde_bono_cumpleanos`,
--             que dice UNA vez a quién le toca el bono, y que la lean las dos
--             puertas que hoy preguntaban `en_planilla` a secas:
--             `fn_mi_bono_cumpleanos` (Info, Bandeja mía, /mio/cumpleanos y la
--             firma, que la usa de puerta) y `fn_documento_registrar` (el cargo
--             en papel de DO).
-- DESCARTÉ:   reusar `fn_persona_le_corresponde_movilidad`, que hoy contesta
--             exactamente lo mismo. Es lo que produjo este defecto: el bono
--             vivía colgado de una pregunta de movilidad (el tablero de
--             documentos), y cuando la movilidad cambió (0424) el bono cambió a
--             medias. Son dos beneficios con dos fundamentos distintos; el día
--             que uno cambie, el otro no tiene que enterarse.
--             Y descarté cambiar `en_planilla`: es columna generada y significa
--             «se le mide asistencia y disciplina» en todo el sistema (0085).
-- SE ROMPE SI: alguien pasa a una practicante a planilla A MITAD DE AÑO
--             después de cobrar su bono: no se paga dos veces (el índice
--             único de 0157 es por persona y año, no por vínculo), así que eso
--             está cubierto. Lo que sí rompería: crear un tipo de vínculo nuevo
--             (p. ej. «locación» con otro nombre) que deba tener bono, sin
--             agregarlo aquí — se quedaría en `no_aplica` en silencio, igual que
--             Daniel. Por eso la lista vive en UNA función.
--
-- LO QUE SE COMPROBÓ ANTES DE ENTREGAR (dentro de BEGIN … ROLLBACK)
--
--   Con la practicante simulada: `fn_mi_bono_cumpleanos` → este_mes con su
--   monto; la firma crea la constancia y la línea `bono` en su boleta; y la
--   planilla de su periodo suma el bono a lo que cobra. Ver la prueba pgTAP
--   que acompaña a esta migración.
--
-- QUÉ NO HACE, A PROPÓSITO
--
--   · No toca `fn_documentos_tablero`: ya listaba a quien es practicante desde
--     la 0424 y ya le calculaba `bono_estado`. Con esta regla, lo que decía
--     era verdad. (Sigue colgado de `fn_persona_le_corresponde_movilidad` para
--     decidir a quién lista; hoy es el mismo conjunto. Si las dos reglas se
--     separan algún día, ahí está el lugar a mirar.)
--   · No toca `fn_confirmar_mi_bono_cumpleanos`: su puerta ya es
--     `fn_mi_bono_cumpleanos`, así que hereda el cambio sin reescribirse.
--   · No toca la planilla: la línea `bono` de `movimientos_planilla` ya la suma
--     para cualquier vínculo (0479).
--   · No abre el bono a un locador por RxH: no hubo pedido, y no es parte del
--     equipo con contrato de CAYLA.
--
-- QUÉ ASUME (md5 de PARTIDA — pedirlos a PRODUCCIÓN antes de pegar)
--
--   fn_mi_bono_cumpleanos   vigente: 0479 · local 6a9d7307f6fa7e4446da67117012736f
--                                         (sin comentarios 983554cf53130f082aeb06f5f34224e5)
--   fn_documento_registrar  vigente: 0448 · local 5909cada98bc2f879fd8f30dffeaffbe
--                                         (sin comentarios 47307a097a4fd667babdb721e5dbaf0e)
--
-- CONCURRENCIA
--
--   Nada nuevo: dos firmas a la vez las sigue frenando el índice único
--   `idx_documentos_bono_uno_por_anio` (0157), sea cual sea el vínculo.
--
-- CÓMO SE REVIERTE
--
--   Volver a pegar `fn_mi_bono_cumpleanos` de la 0479 y `fn_documento_registrar`
--   de la 0448, y después:
--     drop function if exists fn_persona_le_corresponde_bono_cumpleanos(uuid);
--   Las constancias que ya hayan firmado practicantes NO se anulan al revertir:
--   son plata que se pagó o se debe.
-- ============================================================================


-- ── A · Un solo lugar para «¿le toca el bono de cumpleaños?» ───────────────
create or replace function fn_persona_le_corresponde_bono_cumpleanos(p_persona_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select en_planilla or tipo_vinculo = 'practicante' from personas where id = p_persona_id),
    false
  );
$$;

comment on function fn_persona_le_corresponde_bono_cumpleanos(uuid) is
  'A quién le toca el bono de cumpleaños: en planilla, o practicante (0518, '
  'decidido por Cayla el 2026-10-13). La leen fn_mi_bono_cumpleanos y '
  'fn_documento_registrar. Separada de fn_persona_le_corresponde_movilidad a '
  'propósito: hoy contestan igual, pero son dos beneficios distintos.';

-- Solo la llaman funciones del propio esquema.
revoke all on function fn_persona_le_corresponde_bono_cumpleanos(uuid) from public, anon, authenticated;


-- ── B · Lo que ve la persona: cuerpo de la 0479, un cambio (CAMBIO 0518) ───
create or replace function fn_mi_bono_cumpleanos()
returns table (
  estado         text,
  mes_cumpleanos integer,
  anio           integer,
  monto          numeric,
  documento_id   uuid,
  pedido_el      date,
  entregado_el   date,
  via            text,
  periodo_fin    date
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  -- CAMBIO 0479 (marcador: la comprobación del bloque 0 reconoce esta versión)
  -- CAMBIO 0518 (marcador: la comprobación del final reconoce esta versión)
  v_yo   uuid := fn_persona_actual_id();
  v_mes  integer;
  v_doc  documentos_firmados%rowtype;
  v_tab  record;
  v_fin  date;
begin
  if v_yo is null then
    return;
  end if;

  select extract(month from d.fecha_nacimiento)::int into v_mes
    from datos_personales d
   where d.persona_id = v_yo and d.fecha_nacimiento is not null;

  -- 1 · Un pedido sin pagar manda sobre todo lo demás (de cualquier año: una
  --     deuda vieja no se tapa con una nueva). «Sin pagar» quiere decir: DO no
  --     confirmó una transferencia Y tampoco está en una boleta cuyo periodo ya
  --     se pagó. Con la boleta pagada la constancia sale de acá y cae al
  --     tablero, que la ve vigente y dice «entregado».
  select d.* into v_doc
    from documentos_firmados d
   where d.persona_id = v_yo and d.tipo = 'bono'
     and d.anulado_at is null and not d.es_negativa
     and d.firma_persona_confirmada_at is not null
     and d.entrega_confirmada_el is null
     and not exists (
           select 1
             from movimientos_planilla m
             join periodos_planilla pp on pp.id = m.periodo_id
            where m.id = d.movimiento_id
              and fn_fecha_en_periodo_pagado(pp.fecha_ini, d.persona_id))
   order by d.anio desc, d.fecha_firma desc, d.created_at desc, d.id desc
   limit 1;
  if found then
    if v_doc.movimiento_id is null then
      return query select 'pedido'::text, v_mes, v_doc.anio, v_doc.monto_declarado,
                          v_doc.id, v_doc.fecha_firma, null::date, 'transferencia'::text, null::date;
    else
      select pp.fecha_fin into v_fin
        from movimientos_planilla m
        join periodos_planilla pp on pp.id = m.periodo_id
       where m.id = v_doc.movimiento_id;
      return query select 'en_boleta'::text, v_mes, v_doc.anio, v_doc.monto_declarado,
                          v_doc.id, v_doc.fecha_firma, null::date, 'boleta'::text, v_fin;
    end if;
    return;
  end if;

  -- 2 · Lo que dice el tablero de SU fila. `true` es obligatorio: sin él, una
  --     persona de DO recibiría la fila de cualquier compañera (ver 0423).
  select t.bono_estado, t.bono_id into v_tab
    from fn_documentos_tablero(true) t
   limit 1;

  -- ⇩⇩⇩ CAMBIO 0518 ⇩⇩⇩ Antes: `p.en_planilla` a secas, que dejaba fuera a
  -- quien es practicante. Ahora pregunta a la función que decide el bono.
  if not found
     or fn_persona_le_corresponde_bono_cumpleanos(v_yo) is not true then
  -- ⇧⇧⇧ CAMBIO 0518 ⇧⇧⇧
    return query select 'no_aplica'::text, v_mes, extract(year from fn_hoy_lima())::int,
                        null::numeric, null::uuid, null::date, null::date, null::text, null::date;
    return;
  end if;

  -- 3 · Ya se entregó este año, por el camino que fuera.
  if v_tab.bono_estado = 'ok' then
    select d.* into v_doc from documentos_firmados d where d.id = v_tab.bono_id;

    if v_doc.movimiento_id is not null then
      -- Pagado con la planilla: si el periodo no estuviera pagado, el paso 1 lo
      -- habría devuelto como `en_boleta`. No hay día exacto que decir, solo el
      -- periodo (ver «NO SE INVENTA UNA FECHA DE PAGO»).
      select pp.fecha_fin into v_fin
        from movimientos_planilla m
        join periodos_planilla pp on pp.id = m.periodo_id
       where m.id = v_doc.movimiento_id;
      return query select 'entregado'::text, v_mes, v_doc.anio, v_doc.monto_declarado, v_doc.id,
                          v_doc.fecha_firma, null::date, 'boleta'::text, v_fin;
    else
      -- Transferencia confirmada por DO, o cargo en papel (su fecha_firma ya es
      -- la de entrega: la escribe quien recibe, el día que recibe).
      return query select 'entregado'::text, v_mes, v_doc.anio, v_doc.monto_declarado, v_doc.id,
                          case when v_doc.firma_persona_confirmada_at is not null then v_doc.fecha_firma end,
                          coalesce(v_doc.entrega_confirmada_el, v_doc.fecha_firma),
                          case when v_doc.firma_persona_confirmada_at is not null
                               then 'transferencia' else 'papel' end,
                          null::date;
    end if;
    return;
  end if;

  -- 4 · Todavía no hay constancia: el estado del tablero, con el monto que
  --     rige hoy — se muestra ANTES de pedir, nunca se firma a ciegas (0477).
  return query select v_tab.bono_estado::text, v_mes, extract(year from fn_hoy_lima())::int,
                      fn_bono_monto_vigente(), null::uuid, null::date, null::date, null::text, null::date;
end;
$$;

grant execute on function fn_mi_bono_cumpleanos() to authenticated;
revoke execute on function fn_mi_bono_cumpleanos() from public, anon;


-- ── C · El cargo en papel de DO: cuerpo de la 0448, un cambio (CAMBIO 0518) ─
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
    -- La ruta admite a quien es practicante (0397/0424).
    if p_tipo = 'ruta' and not fn_persona_le_corresponde_movilidad(p_persona_id) then
      raise exception 'Esa persona no está en planilla ni es practicante: no le corresponde declarar su ruta.';
    end if;
    -- ⇩⇩⇩ CAMBIO 0518 ⇩⇩⇩ El bono también (antes: `en_planilla` a secas). Es
    -- la misma pregunta que se hace `fn_mi_bono_cumpleanos`: el cargo en papel
    -- y la firma desde Info no pueden contestar distinto sobre la misma persona.
    if p_tipo = 'bono' and fn_persona_le_corresponde_bono_cumpleanos(p_persona_id) is not true then
      raise exception 'Esa persona no está en planilla ni es practicante: no le corresponde ese documento.';
    end if;
    -- ⇧⇧⇧ CAMBIO 0518 ⇧⇧⇧
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
values (518, 'el_bono_de_cumpleanos_tambien_es_para_practicantes')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from pg_proc where proname = 'fn_persona_le_corresponde_bono_cumpleanos') = 1 as tiene_regla,
  (select position('CAMBIO 0518' in prosrc) > 0 from pg_proc where proname = 'fn_mi_bono_cumpleanos')  as mi_bono_al_dia,
  (select position('CAMBIO 0518' in prosrc) > 0 from pg_proc where proname = 'fn_documento_registrar') as registrar_al_dia,
  (select count(*) from pg_proc where proname in ('fn_mi_bono_cumpleanos', 'fn_documento_registrar')) = 2 as sin_sobrecargas,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 518) as registro;
