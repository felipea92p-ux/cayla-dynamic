-- ============================================================================
-- 0429 — La declaración de ruta guarda sus datos por separado
-- ============================================================================
--
-- QUÉ PROMETE
--
--   El «Ver» de una firma digital (0428) mostraba `ruta_declarada` tal cual
--   —un párrafo corrido— y Felipe pidió que se vea como el papel de siempre:
--   la lista numerada (distrito/provincia, medios de transporte, la
--   declaración de veracidad) y, aparte, el párrafo del monto en su propio
--   bloque. Reconstruir esa lista desde el párrafo habría significado
--   parsear un texto libre para adivinar dónde empieza el distrito y dónde
--   termina — fràgil, y esta migración es ya la CUARTA vez en el mismo día
--   que el texto de esta declaración cambia de forma. Un parser que adivina
--   contra un formato que lleva un día entero cambiando se rompe la próxima
--   vez que cambie, en silencio.
--
--   La solución es la de siempre cuando un dato vive adentro de un texto:
--   se guarda aparte. `documentos_firmados` gana cuatro columnas —
--   `ruta_distrito`, `ruta_provincia`, `ruta_medios_ida`, `ruta_medios_vuelta`
--   — que `fn_confirmar_mi_declaracion_ruta` llena AL MISMO TIEMPO que
--   compone `ruta_declarada`. La pantalla de autoservicio y el «Ver» de
--   admin pasan a mostrar la MISMA lista numerada, armada de las MISMAS
--   columnas — no dos intentos por separado de decir lo mismo.
--
-- QUÉ NO HACE, A PROPÓSITO
--
--   No toca `ruta_declarada`. Sigue siendo el texto legal que se firmó, y
--   sigue siendo lo único que importa para lo ya firmado: estas cuatro
--   columnas son nuevas, así que todo lo firmado ANTES de esta migración las
--   tiene en `null` — su «Ver» sigue mostrando el párrafo tal cual (ver el
--   frontend), porque ese es el texto real que esa persona firmó y no hay
--   forma honesta de reconstruir columnas que no existían cuando firmó.
--
--   No agrega columnas para el costo del pasaje ni el taxi: esas preguntas
--   ya se quitaron (0425, 0426) y no vuelven.
--
--   No cambia el candado ni el criterio de «vigente» (0425): siguen mirando
--   `es_negativa` y `monto_declarado`, nunca estas columnas nuevas.
--
-- QUÉ ASUME
--
--   `fn_confirmar_mi_declaracion_ruta` vigente es la 0426 (4 parámetros) y
--   `fn_documentos_listar` vigente es la 0423 — confirmado el 2026-09-12 con
--   `./scripts/donde-vive.sh`.
--
-- CÓMO SE REVIERTE
--
--   drop function if exists fn_documentos_listar(uuid);
--   -- recrear fn_documentos_listar con el cuerpo de la 0423 (sin las cuatro
--   -- columnas nuevas).
--   -- fn_confirmar_mi_declaracion_ruta puede recrearse con el cuerpo de la
--   -- 0426 (create or replace, misma firma).
--   alter table documentos_firmados
--     drop column if exists ruta_distrito,
--     drop column if exists ruta_provincia,
--     drop column if exists ruta_medios_ida,
--     drop column if exists ruta_medios_vuelta;
-- ============================================================================

alter table documentos_firmados
  add column if not exists ruta_distrito text,
  add column if not exists ruta_provincia text,
  add column if not exists ruta_medios_ida integer,
  add column if not exists ruta_medios_vuelta integer;

comment on column documentos_firmados.ruta_distrito is
  'Solo para tipo=ruta, y solo desde la 0429. Antes de esta migración el dato '
  'vivía únicamente adentro de ruta_declarada — null acá es "firmada antes de '
  'la 0429", no un dato faltante.';


-- ── fn_confirmar_mi_declaracion_ruta: misma firma, guarda también las piezas ──
create or replace function fn_confirmar_mi_declaracion_ruta(
  p_distrito         text,
  p_provincia        text,
  p_medios_ida       integer,
  p_medios_vuelta    integer
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yo            uuid := fn_persona_actual_id();
  v_imagen        text;
  v_sede_codigo   text;
  v_tarifa        numeric;
  v_declarada     text;
  v_id            uuid;
  v_ip            text;
  v_ua            text;
  v_es_negativa   boolean;
  v_monto_anterior numeric;
begin
  if v_yo is null then
    raise exception 'No se encontró tu persona.';
  end if;

  if not exists (select 1 from personas where id = v_yo and estado = 'activo')
     or not fn_persona_le_corresponde_movilidad(v_yo) then
    raise exception 'No estás en planilla ni eres practicante: no te corresponde declarar tu ruta.';
  end if;

  if p_distrito is null or length(trim(p_distrito)) = 0 then
    raise exception 'Falta el distrito donde resides.';
  end if;
  if p_provincia is null or length(trim(p_provincia)) = 0 then
    raise exception 'Falta la provincia donde resides.';
  end if;
  if p_medios_ida is null or p_medios_ida < 0 or p_medios_ida > 10 then
    raise exception 'Indica cuántos medios de transporte usas de ida (entre 0 y 10).';
  end if;
  if p_medios_vuelta is null or p_medios_vuelta < 0 or p_medios_vuelta > 10 then
    raise exception 'Indica cuántos medios de transporte usas de vuelta (entre 0 y 10).';
  end if;

  select imagen into v_imagen from firmas_escaneadas where persona_id = v_yo;
  if v_imagen is null then
    raise exception 'Todavía no configuraste tu firma. Ve a la pestaña «Firma» antes de confirmar.';
  end if;

  select s.codigo into v_sede_codigo
    from personas p join sedes s on s.id = p.sede_base_id
   where p.id = v_yo;

  select pl.valor into v_tarifa
    from parametros_laborales pl
   where pl.clave = 'movilidad_diaria'
     and pl.vigente_desde <= fn_hoy_lima()
     and (pl.vigente_hasta is null or pl.vigente_hasta >= fn_hoy_lima())
     and (pl.sede_codigo = v_sede_codigo or pl.sede_codigo is null)
   order by (pl.sede_codigo is null), pl.vigente_desde desc
   limit 1;

  if v_tarifa is null then
    raise exception 'Tu sede todavía no tiene una tarifa de movilidad vigente. Avisa a Desarrollo Organizacional antes de firmar.';
  end if;

  -- Candado (0425), sin cambios de criterio.
  select d.es_negativa, d.monto_declarado into v_es_negativa, v_monto_anterior
    from documentos_firmados d
   where d.persona_id = v_yo and d.tipo = 'ruta' and d.anulado_at is null
   order by d.fecha_firma desc, d.created_at desc, d.id desc
   limit 1;

  if v_es_negativa is not true and v_monto_anterior is not null and v_monto_anterior = v_tarifa then
    raise exception 'Ya tienes una declaración de ruta firmada y vigente. Si algo cambió, pide una revisión en vez de volver a firmar.';
  end if;

  v_declarada :=
    'Reside en el distrito de ' || trim(p_distrito) || ', provincia de ' || trim(p_provincia) || '. '
    || 'Para llegar a su centro de labores utiliza ' || p_medios_ida || ' medio(s) de transporte por tramo, '
    || 'y de regreso ' || p_medios_vuelta || '. '
    || 'CAYLA le otorga una asignación de movilidad de S/ ' || to_char(v_tarifa, 'FM999999990.00')
    || ' por día efectivamente asistido, conforme a la tarifa vigente para su sede.';

  begin
    v_ip := nullif(split_part(
      coalesce(nullif(current_setting('request.headers', true), ''), '{}')::json ->> 'x-forwarded-for',
      ',', 1), '');
    v_ua := coalesce(nullif(current_setting('request.headers', true), ''), '{}')::json ->> 'user-agent';
  exception when others then
    v_ip := null;
    v_ua := null;
  end;

  -- ⇩⇩⇩ CAMBIO 0429 ⇩⇩⇩ Las mismas piezas que arman `v_declarada`, guardadas
  -- aparte para que el «Ver» las pueda mostrar como lista sin tener que
  -- volver a leerlas del texto.
  insert into documentos_firmados (
    alcance, persona_id, tipo, fecha_firma, ruta_declarada, monto_declarado,
    registrado_por, firma_persona, firma_persona_confirmada_at,
    firma_persona_ip, firma_persona_user_agent,
    ruta_distrito, ruta_provincia, ruta_medios_ida, ruta_medios_vuelta
  ) values (
    'individual', v_yo, 'ruta', fn_hoy_lima(), v_declarada, v_tarifa,
    v_yo, v_imagen, now(), v_ip, v_ua,
    trim(p_distrito), trim(p_provincia), p_medios_ida, p_medios_vuelta
  )
  returning id into v_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (v_yo, 'documento_firmado', null, 'ruta · firmado digitalmente el ' || fn_hoy_lima()::text, v_yo,
     'Firma digital de la declaración de ruta (0423), reemplaza el escaneo físico.');

  return v_id;
end;
$$;

grant execute on function
  fn_confirmar_mi_declaracion_ruta(text,text,integer,integer)
  to authenticated;
revoke execute on function
  fn_confirmar_mi_declaracion_ruta(text,text,integer,integer)
  from public, anon;


-- ── fn_documentos_listar: gana las cuatro columnas nuevas ──────────────────
-- `returns table` con una columna más: hace falta `drop` antes de `create`,
-- mismo motivo que ya documentaron la 0161 y otras de esta familia.
drop function if exists fn_documentos_listar(uuid);

create function fn_documentos_listar(p_persona_id uuid default null)
returns table (
  id uuid, alcance text, persona_id uuid, persona text, tipo text,
  fecha_firma date, ruta_declarada text, monto_declarado numeric, anio integer,
  es_negativa boolean, storage_path text, nota text, registrado_por text,
  anulado_at timestamptz, anulado_motivo text, vigente boolean, firma_persona text,
  ruta_distrito text, ruta_provincia text, ruta_medios_ida integer, ruta_medios_vuelta integer
)
language sql
stable
security definer
set search_path = public
as $$
  select
    d.id, d.alcance, d.persona_id,
    coalesce(p.nombres || ' ' || p.apellidos, 'CAYLA'),
    d.tipo, d.fecha_firma, d.ruta_declarada, d.monto_declarado, d.anio,
    d.es_negativa, d.storage_path, d.nota,
    reg.nombres || ' ' || reg.apellidos,
    d.anulado_at, d.anulado_motivo,
    (d.anulado_at is null and d.id = (
       select d2.id from documentos_firmados d2
        where d2.tipo = d.tipo and d2.anulado_at is null
          and d2.persona_id is not distinct from d.persona_id
        order by d2.fecha_firma desc, d2.created_at desc, d2.id desc limit 1)),
    d.firma_persona,
    -- ⇩⇩⇩ CAMBIO 0429 ⇩⇩⇩
    d.ruta_distrito, d.ruta_provincia, d.ruta_medios_ida, d.ruta_medios_vuelta
  from documentos_firmados d
  left join personas p on p.id = d.persona_id
  left join personas reg on reg.id = d.registrado_por
  where (fn_es_admin_o_lider() is true or d.persona_id = fn_persona_actual_id())
    and (p_persona_id is null or d.persona_id = p_persona_id)
  order by d.fecha_firma desc, d.created_at desc;
$$;

grant execute on function fn_documentos_listar(uuid) to authenticated;
revoke execute on function fn_documentos_listar(uuid) from public, anon;


insert into migraciones_aplicadas (numero, nombre)
values (429, 'la_declaracion_de_ruta_guarda_sus_datos_por_separado')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';


-- ── Comprobación de que la pegada llegó entera ──────────────────────────────
select
  (select count(*) from information_schema.columns
     where table_name = 'documentos_firmados' and column_name = 'ruta_distrito') = 1
    as columnas_puestas,
  (select prosrc like '%CAMBIO 0429%' from pg_proc
     where proname = 'fn_confirmar_mi_declaracion_ruta' and pronargs = 4)
    as confirmar_guarda_piezas,
  (select count(*) from pg_proc where proname = 'fn_documentos_listar'
     and pg_get_function_result(oid) like '%ruta_medios_vuelta%')
    as listar_devuelve_piezas;
