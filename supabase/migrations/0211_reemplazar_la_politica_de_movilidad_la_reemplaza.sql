-- ============================================================================
-- 0211_reemplazar_la_politica_de_movilidad_la_reemplaza.sql
-- ============================================================================
-- QUÉ PROMETE
--
--   1. Que subir una política de movilidad nueva ANULE la anterior, con motivo,
--      autor y hora — y que la pantalla muestre la nueva.
--   2. Que si en producción ya hay más de una política viva, quede una sola: la
--      última registrada. Las demás anuladas, ninguna borrada.
--   3. Que la consulta que elige «la política vigente» no dependa nunca más de
--      un empate resuelto al azar.
--
-- QUÉ ASUME
--
--   · `documentos_firmados` con `tipo`, `anulado_at`, `anulado_por`,
--     `anulado_motivo` y `created_at` (0157, sin cambios desde entonces).
--   · Que `fn_documento_registrar` es la única puerta para registrar un papel
--     firmado, y que su versión vigente es la de la 0161.
--
-- POR QUÉ EXISTE — «REEMPLAZAR» NO REEMPLAZABA
--
--   Reportado desde producción: se pulsa Reemplazar, se sube el escaneo nuevo, y
--   la pantalla sigue diciendo «Política de movilidad firmada el 29 de julio de
--   2026» con el papel viejo detrás del botón Ver.
--
--   Son dos defectos que se suman:
--
--     · `fn_documento_registrar` insertaba una SEGUNDA fila y dejaba las dos
--       vivas. No anulaba nada.
--     · `fn_documentos_estado_politica` elegía con
--       `order by fecha_firma desc limit 1`, SIN desempate.
--
--   Reproducido contra el Postgres local: dos políticas con fecha 2026-07-29, la
--   consulta devolvió la primera. El archivo nuevo estaba guardado y era
--   inalcanzable desde la pantalla.
--
--   Y no es un caso raro: es EL caso. La política tiene que conservar la fecha
--   del papel —anterior al primer pago de movilidad, que es exactamente lo que
--   la hace válida; ver el aviso de «firmada después del primer pago»—, así que
--   TODO reemplazo legítimo empata en `fecha_firma`.
--
-- POR QUÉ SE ANULA Y NO SE BORRA
--
--   Decisión de Felipe, 2026-08-11. Una política anulada sigue diciendo cuál
--   regía cuando se pagó la movilidad de cada mes, y ese rastro es lo que
--   sostiene los pagos ya hechos si alguien los discute. Borrarla dejaría la
--   lista más limpia y el expediente más pobre — es la misma regla por la que
--   una persona nunca se borra y un marcaje se anula en vez de desaparecer.
--
-- CÓMO SE REVIERTE
--
--   Volviendo a aplicar los cuerpos de la 0161 (`fn_documento_registrar`) y de
--   la 0157 (`fn_documentos_estado_politica`). Las anulaciones que esta
--   migración haya escrito se pueden deshacer una a una poniendo `anulado_at`,
--   `anulado_por` y `anulado_motivo` en null — quedan identificadas por su
--   motivo, que empieza por «Reemplazada por» o «0211 ·».
--
-- CÓMO SE COMPRUEBA QUE QUEDÓ BIEN
--   La consulta del final devuelve una fila con `politicas_vivas = 1` (o 0 si
--   todavía no se ha subido ninguna) y los dos `true`.
-- ============================================================================


-- ── 1 · Lo que ya está mal en producción, arreglado sin perder nada ─────────
-- Deja viva la ÚLTIMA registrada y anula las anteriores. Se mira `created_at`
-- —cuándo se registró— y no `fecha_firma`, que es la del papel y está empatada.
--
-- Idempotente: si solo hay una viva, no toca nada. Se pega a mano y una mano
-- hace doble clic.
do $mig$
declare v_vivas int; v_anuladas int;
begin
  select count(*) into v_vivas
  from documentos_firmados where tipo = 'politica' and anulado_at is null;

  if v_vivas <= 1 then
    raise notice '0211 · políticas vivas: % — no hay nada que ordenar.', v_vivas;
    return;
  end if;

  with sobrantes as (
    select id from documentos_firmados
    where tipo = 'politica' and anulado_at is null
    order by created_at desc
    offset 1
  )
  update documentos_firmados d
     set anulado_at = now(),
         anulado_por = (select id from personas where rol = 'admin' and estado = 'activo'
                        order by fecha_ingreso limit 1),
         anulado_motivo = '0211 · quedó reemplazada por una versión posterior. Se anula, no se borra: sigue siendo el historial de qué política regía cuando se pagó cada mes.'
   from sobrantes s
  where d.id = s.id;

  get diagnostics v_anuladas = row_count;
  raise notice '0211 · políticas vivas antes: % · anuladas ahora: % · queda 1.', v_vivas, v_anuladas;
end
$mig$;


-- ── 2 · Registrar una política anula la anterior ───────────────────────────
-- Cuerpo de la 0161 (la vigente, confirmada con donde-vive.sh) copiado con
-- script y comprobado: 0 líneas eliminadas, solo el bloque nuevo.
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
  v_id      uuid;
  v_alcance text;
  v_yo      uuid := fn_persona_actual_id();
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
    update documentos_firmados
       set storage_path = coalesce(p_storage_path, storage_path)
     where id = p_id and anulado_at is null;
    if not found then raise exception 'Ese documento no existe o está anulado.'; end if;
    return p_id;
  end if;

  if v_alcance = 'individual' then
    if p_persona_id is null then
      raise exception 'Falta de quién es el documento.';
    end if;
    if not exists (select 1 from personas where id = p_persona_id and estado = 'activo') then
      raise exception 'Esa persona no existe o no está activa.';
    end if;
    -- CAMBIO 0161: antes decía `p_tipo = 'ruta'`. Los dos documentos individuales
    -- son beneficios de trabajador: un locador no cobra movilidad (0117) ni recibe
    -- asignación por onomástico — se le paga su recibo. Pedirle cualquiera de los
    -- dos es pedirle un papel que no sostiene ningún pago suyo.
    if not exists (
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
  -- Una política nueva anula la anterior. Antes no lo hacia: insertaba una
  -- SEGUNDA fila y dejaba las dos vivas, y como fn_documentos_estado_politica
  -- elegía con `order by fecha_firma desc limit 1` SIN desempate, la pantalla
  -- se quedaba mostrando la vieja. Reproducido: dos políticas del 29/07/2026
  -- y la consulta devolvía la primera.
  --
  -- Y no es un caso raro, es EL caso: la política tiene que conservar su fecha
  -- —anterior al primer pago de movilidad, que es todo su valor legal—, así que
  -- todo reemplazo legítimo empata en fecha_firma.
  --
  -- Se ANULA, no se borra: queda con su motivo, su autor y su hora, y sigue
  -- siendo el historial de qué política regía cuando se pago cada mes. Esa
  -- traza es lo que sostiene los pagos ya hechos ante una inspección.
  --
  -- Solo la política. Las rutas y los bonos son de una persona y su reemplazo
  -- no tiene por qué anular el de otra; el bono ya lleva su índice único por año.
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


-- ── 3 · Y la consulta deja de depender de un empate ────────────────────────
create or replace function fn_documentos_estado_politica()
returns table (
  id            uuid,
  cargada       boolean,
  fecha_firma   date,
  primer_pago   date,
  llego_tarde   boolean,
  storage_path  text
)
language sql
stable
security definer
set search_path = public
as $$
  with pol as (
    select d.id, d.fecha_firma, d.storage_path
    from documentos_firmados d
    where d.tipo = 'politica' and d.anulado_at is null
    -- 0211 · DESEMPATE POR created_at. Sin él, dos políticas con la misma
    -- fecha_firma —el caso NORMAL, porque la política conserva la fecha del
    -- papel— dejaban a Postgres elegir cualquiera, y elegía la vieja: el
    -- reemplazo se guardaba y la pantalla seguía enseñando el anterior.
    -- Con la anulación automática de fn_documento_registrar esto no debería
    -- llegar a hacer falta; está por lo que ya haya en producción de antes.
    order by d.fecha_firma desc, d.created_at desc
    limit 1
  ),
  -- Cuándo empezó a pagarse movilidad: la primera tarifa mayor que cero.
  inicio as (
    select min(vigente_desde) as desde
    from parametros_laborales
    where clave = 'movilidad_diaria' and valor > 0
  )
  select
    pol.id,
    pol.id is not null,
    pol.fecha_firma,
    inicio.desde,
    (pol.fecha_firma is not null and inicio.desde is not null
       and pol.fecha_firma > inicio.desde),
    pol.storage_path
  from inicio
  left join pol on true;
$$;

grant execute on function fn_documento_registrar(text,date,uuid,text,numeric,integer,boolean,text,text,uuid) to authenticated;
grant execute on function fn_documentos_estado_politica() to authenticated;

notify pgrst, 'reload schema';

insert into migraciones_aplicadas (numero, nombre)
values (211, 'reemplazar_la_politica_de_movilidad_la_reemplaza')
on conflict (numero) do nothing;


-- ── Comprobación de que la pegada llegó entera ──────────────────────────────
-- Una fila: una sola política viva (o ninguna, si aún no se subió) y los dos
-- cambios presentes en el texto de las funciones.
select
  (select count(*) from documentos_firmados
    where tipo = 'politica' and anulado_at is null)          as politicas_vivas,
  (select prosrc like '%Reemplazada por la pol%'
     from pg_proc where proname = 'fn_documento_registrar')  as registrar_anula_la_anterior,
  (select prosrc like '%created_at desc%'
     from pg_proc where proname = 'fn_documentos_estado_politica') as la_consulta_desempata;
