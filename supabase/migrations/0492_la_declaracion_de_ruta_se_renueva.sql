-- ============================================================================
-- 0492 — La declaración de ruta se renueva: si quedó incompleta, o al año
-- ============================================================================
--
-- QUÉ PROMETE
--
--   Una declaración de ruta vigente queda «por renovar» en dos casos, y
--   entonces la persona puede volver a firmarla sola desde Info, sin pedir
--   una revisión:
--
--     · INCOMPLETA — se firmó digitalmente sin el costo del pasaje. Son las
--       firmadas entre la 0425 (2026-09-12, que quitó el pasaje y el taxi) y
--       la 0489 (que los devolvió). Medido en producción el 2026-09-28: 6
--       declaraciones digitales vigentes, las 6 sin pasaje, ninguna con él.
--       Las de papel escaneado NO entran: ese formato siempre tuvo los cinco
--       puntos.
--     · VENCIDA — pasaron 12 meses desde que se firmó. Cada una vence en su
--       propia fecha, no todas en enero: así Desarrollo Organizacional no
--       recibe treinta pendientes el mismo día.
--
--   Decidido el 2026-09-28 (opciones A y B de esa conversación). La
--   renovación MENSUAL se descartó: la ley no pide volver a declarar cada
--   mes, el punto 5 ya obliga a avisar si cambia el domicilio o la ruta, y
--   un papel que se firma cada mes por rutina se firma sin leer.
--
--   El criterio vive en UNA función, `fn_ruta_por_renovar`, que usan el
--   tablero (para avisar) y el candado de la firma (para dejar pasar). Si
--   vivieran en dos sitios, un día el tablero diría «renueva» y la firma
--   diría «ya tienes una vigente».
--
-- QUÉ NO HACE, A PROPÓSITO — Y ES LO MÁS IMPORTANTE
--
--   NO TOCA CUÁNTO SE PAGA. La planilla (`fn_planilla_calcular_nucleo`, 0491)
--   paga la movilidad en S/ 0.00 cuando no hay NINGUNA declaración firmada
--   antes del cierre, y esa pregunta no mira si está completa ni si venció.
--   Esta migración no la cambia: una declaración por renovar SIGUE
--   sosteniendo el pago hasta que se vuelva a firmar. Cortarle la movilidad a
--   quien no renovó a tiempo sería una sanción que el sistema aplica solo, y
--   «Dynamic avisa, nunca sanciona solo». Si algún día se decide que una
--   declaración vencida deja de sostener el pago, es otra migración, sobre
--   la planilla, y con el contador.
--
--   No cambia `estado` del tablero (sigue siendo sin_ruta / se_nego / ok):
--   agrega una columna aparte, `ruta_por_renovar`. Las pantallas y la
--   Bandeja que ya leen `estado` siguen contestando lo mismo; las que
--   quieren el aviso nuevo leen la columna nueva.
--
--   No toca lo firmado: nada se anula ni se reescribe. Renovar es firmar una
--   declaración nueva, que pasa a ser la vigente por el desempate de siempre
--   (fecha_firma, created_at, id).
--
-- QUÉ ASUME
--
--   · `fn_documentos_tablero` vigente es la de la 0491 — confirmado con
--     `./scripts/donde-vive.sh` el 2026-09-28. En producción, ese día, la 0491
--     todavía NO estaba pegada: su md5 era 21ddd1180f96c4db4b3ff343579d064e
--     (3764 caracteres), que es exactamente el cuerpo de la 0491 sin su única
--     línea nueva (`and not p.cuenta_de_servicio`, 113 caracteres). O sea: la
--     0491 partió de lo mismo que hay en producción. LA 0491 SE PEGA ANTES
--     QUE ESTA; si se pegara esta primero, la 0491 la pisaría al reescribir
--     el tablero.
--   · `fn_confirmar_mi_declaracion_ruta` vigente es la de la 0489, pegada en
--     producción el 2026-09-28 (comprobación de la 0489 entera en true).
--
-- CÓMO SE REVIERTE
--
--   -- Tablero: drop + recrear con el cuerpo de la 0491 (sin ruta_por_renovar).
--   -- Confirmar: create or replace con el cuerpo de la 0489.
--   drop function if exists fn_ruta_por_renovar(date, timestamptz, numeric, boolean);
--   Ninguna fila de datos se toca.
-- ============================================================================


-- ── A · El criterio, en un solo sitio ──────────────────────────────────────
-- null = al día. Recibe las piezas y no un id para que el tablero la pueda
-- llamar fila por fila sin volver a leer la tabla.
create or replace function fn_ruta_por_renovar(
  p_fecha_firma        date,
  p_firma_digital_at   timestamptz,
  p_costo_pasaje       numeric,
  p_es_negativa        boolean
)
returns text
language sql
stable
set search_path = public
as $$
  select case
    -- Una negativa no se «renueva»: ya tiene su propio estado (se_nego), y
    -- quien se negó puede firmar cuando quiera.
    when p_fecha_firma is null or coalesce(p_es_negativa, false) then null
    -- Firma digital sin pasaje: la versión corta de la 0425/0426. El papel
    -- escaneado no tiene firma digital, y el papel siempre traía el pasaje.
    when p_firma_digital_at is not null and p_costo_pasaje is null then 'incompleta'
    when p_fecha_firma + interval '12 months' <= fn_hoy_lima() then 'vencida'
  end;
$$;

comment on function fn_ruta_por_renovar(date, timestamptz, numeric, boolean) is
  'Si una declaración de ruta está por renovar: ''incompleta'' (firma digital '
  'sin pasaje, 0425–0489), ''vencida'' (12 meses desde la firma) o null. La usan '
  'fn_documentos_tablero y el candado de fn_confirmar_mi_declaracion_ruta (0492). '
  'NO la usa la planilla: por renovar no deja de sostener el pago.';

-- Solo la llaman funciones del propio esquema; ningún cliente la necesita.
revoke all on function fn_ruta_por_renovar(date, timestamptz, numeric, boolean) from public, anon, authenticated;


-- ── B · fn_documentos_tablero: gana `ruta_por_renovar` ─────────────────────
-- `returns table` con una columna más: hace falta `drop` antes de `create`.
-- Cuerpo de la 0491, con los cambios marcados.
drop function if exists fn_documentos_tablero(boolean);

create function fn_documentos_tablero(p_solo_mi_fila boolean default false)
returns table (
  persona_id uuid, persona text, sede text, fecha_ingreso date,
  ruta_id uuid, ruta_firmada_el date, ruta_monto numeric, ruta_negativa boolean,
  ruta_desfasada boolean, ruta_firma_persona_confirmada_at timestamptz,
  ruta_tarifa_vigente numeric,
  bono_id uuid, bono_anio integer, bono_firmada_el date, bono_mes integer, bono_estado text,
  estado text,
  ruta_por_renovar text   -- CAMBIO 0492
)
language sql
stable
security definer
set search_path = public
as $function$
  with hoy as (
    select fn_hoy_lima()                             as dia,
           extract(year  from fn_hoy_lima())::int    as anio,
           extract(month from fn_hoy_lima())::int    as mes,
           (date_trunc('month', fn_hoy_lima()) + interval '1 month - 1 day')::date
                                                     as fin_de_mes,
           coalesce(
             (select min(vigente_desde) from parametros_laborales
               where clave = 'bono_onomastico' and valor > 0),
             '1900-01-01'::date)                     as bono_desde
  ),
  ruta as (
    select distinct on (d.persona_id)
           d.persona_id, d.id, d.fecha_firma, d.monto_declarado, d.es_negativa,
           d.firma_persona_confirmada_at,
           d.ruta_costo_pasaje   -- CAMBIO 0492
    from documentos_firmados d
    where d.tipo = 'ruta' and d.anulado_at is null
    order by d.persona_id, d.fecha_firma desc, d.created_at desc, d.id desc
  ),
  bono as (
    select distinct on (d.persona_id)
           d.persona_id, d.id, d.anio, d.fecha_firma
    from documentos_firmados d, hoy
    where d.tipo = 'bono' and d.anulado_at is null and not d.es_negativa
      and d.anio = hoy.anio
    order by d.persona_id, d.fecha_firma desc, d.created_at desc, d.id desc
  )
  select
    p.id,
    p.nombres || ' ' || p.apellidos,
    coalesce(s.codigo, '?'),
    p.fecha_ingreso,
    r.id, r.fecha_firma, r.monto_declarado, coalesce(r.es_negativa, false),
    (r.monto_declarado is not null
      and tar.valor is not null
      and r.monto_declarado <> tar.valor),
    r.firma_persona_confirmada_at,
    tar.valor,
    b.id, b.anio, b.fecha_firma,
    dp.mes_nacimiento,
    case
      when b.id is not null            then 'ok'
      when dp.mes_nacimiento is null   then 'sin_fecha'
      when make_date(hoy.anio, dp.mes_nacimiento, 1)
             < date_trunc('month', hoy.bono_desde)::date then 'no_aplica'
      when make_date(hoy.anio, dp.mes_nacimiento, 1)
             < date_trunc('month', p.fecha_ingreso)::date then 'no_aplica'
      when dp.mes_nacimiento = hoy.mes then 'este_mes'
      when dp.mes_nacimiento <  hoy.mes then 'vencido'
      else                                  'proximo'
    end,
    case
      when r.id is null                    then 'sin_ruta'
      when coalesce(r.es_negativa, false)  then 'se_nego'
      else 'ok'
    end,
    -- ⇩⇩⇩ CAMBIO 0492 ⇩⇩⇩ El mismo criterio que usa el candado de la firma.
    fn_ruta_por_renovar(r.fecha_firma, r.firma_persona_confirmada_at,
                        r.ruta_costo_pasaje, r.es_negativa)
  from personas p
  cross join hoy
  left join sedes s on s.id = p.sede_base_id
  left join ruta r on r.persona_id = p.id
  left join bono b on b.persona_id = p.id
  left join lateral (
    select extract(month from d.fecha_nacimiento)::int as mes_nacimiento
    from datos_personales d
    where d.persona_id = p.id and d.fecha_nacimiento is not null
  ) dp on true
  left join lateral (
    select pl.valor
    from parametros_laborales pl
    where pl.clave = 'movilidad_diaria'
      and pl.vigente_desde <= hoy.dia
      and (pl.vigente_hasta is null or pl.vigente_hasta >= hoy.dia)
      and (pl.sede_codigo = s.codigo or pl.sede_codigo is null)
    order by (pl.sede_codigo is null), pl.vigente_desde desc
    limit 1
  ) tar on true
  where p.estado = 'activo'
    and not p.cuenta_de_servicio   -- CAMBIO 0491: una cuenta de servicio (estación de retail) no es una persona
    -- ⇩⇩⇩ CAMBIO 0424 ⇩⇩⇩ Antes: `and p.en_planilla`. Ver el encabezado de
    -- esta migración — es la línea que dejaba a Benjamin, Fernanda y Daniel
    -- fuera del tablero aunque ya pudieran cobrar movilidad desde la 0397.
    and fn_persona_le_corresponde_movilidad(p.id)
    and (p.id = fn_persona_actual_id()
         or (not coalesce(p_solo_mi_fila, false) and fn_es_admin_o_lider() is true))
    and p.id is distinct from (
      select (c.valor->>'persona_id')::uuid
      from configuracion c
      where c.clave = 'firmante_empresa'
    )
    and (p.fecha_fin_contrato is null or p.fecha_fin_contrato > hoy.fin_de_mes)
  order by (r.id is not null), p.apellidos;
$function$;

grant execute on function fn_documentos_tablero(boolean) to authenticated;
revoke execute on function fn_documentos_tablero(boolean) from public, anon;


-- ── C · El candado deja pasar una declaración por renovar ───────────────────
-- Cuerpo de la 0489; mismo nombre y mismos 7 parámetros, así que alcanza con
-- `create or replace` y no queda ninguna sobrecarga.
create or replace function fn_confirmar_mi_declaracion_ruta(
  p_distrito         text,
  p_provincia        text,
  p_medios_ida       integer,
  p_medios_vuelta    integer,
  p_costo_pasaje     numeric default null,
  p_costo_taxi       numeric default null,
  p_frecuencia_taxi  integer default null
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
  v_gasto_diario  numeric;
  v_usa_taxi      boolean;
  v_por_renovar   text;   -- CAMBIO 0492
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

  -- ⇩⇩⇩ CAMBIO 0489 ⇩⇩⇩ El pasaje y el taxi vuelven (ver encabezado). Cero
  -- es un pasaje válido: quien va caminando declara 0 medios y S/ 0.00.
  if p_costo_pasaje is null or p_costo_pasaje < 0 or p_costo_pasaje > 1000 then
    raise exception 'Indica el costo de cada pasaje (S/ 0 si no usas transporte).';
  end if;

  -- Taxi: opcional. Sin costo y sin veces = no usa taxi. Si declara uno de
  -- los dos, tiene que declarar el otro — un «S/ 8 por viaje» sin cuántas
  -- veces, o al revés, no le dice nada a quien lo lea.
  v_usa_taxi := coalesce(p_costo_taxi, 0) > 0 or coalesce(p_frecuencia_taxi, 0) > 0;
  if v_usa_taxi then
    if p_costo_taxi is null or p_costo_taxi <= 0 or p_costo_taxi > 1000 then
      raise exception 'Indica cuánto te cuesta cada viaje en taxi u otro medio particular.';
    end if;
    if p_frecuencia_taxi is null or p_frecuencia_taxi < 1 or p_frecuencia_taxi > 7 then
      raise exception 'Indica cuántas veces por semana usas taxi u otro medio particular (entre 1 y 7).';
    end if;
  end if;

  v_gasto_diario := round((p_medios_ida + p_medios_vuelta) * p_costo_pasaje, 2);
  -- ⇧⇧⇧ FIN CAMBIO 0489 ⇧⇧⇧

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

  -- Candado (0425). ⇩⇩⇩ CAMBIO 0492 ⇩⇩⇩ Ahora también deja pasar una
  -- declaración «por renovar» (incompleta o vencida), con el mismo criterio
  -- que el tablero usa para avisar: `fn_ruta_por_renovar`.
  select d.es_negativa, d.monto_declarado,
         fn_ruta_por_renovar(d.fecha_firma, d.firma_persona_confirmada_at,
                             d.ruta_costo_pasaje, d.es_negativa)
    into v_es_negativa, v_monto_anterior, v_por_renovar
    from documentos_firmados d
   where d.persona_id = v_yo and d.tipo = 'ruta' and d.anulado_at is null
   order by d.fecha_firma desc, d.created_at desc, d.id desc
   limit 1;

  if v_es_negativa is not true and v_monto_anterior is not null and v_monto_anterior = v_tarifa
     and v_por_renovar is null then
    raise exception 'Ya tienes una declaración de ruta firmada y vigente. Si algo cambió, pide una revisión en vez de volver a firmar.';
  end if;
  -- ⇧⇧⇧ FIN CAMBIO 0492 ⇧⇧⇧

  -- ⇩⇩⇩ CAMBIO 0489 ⇩⇩⇩ El texto legal vuelve a decir el pasaje y el taxi,
  -- con la redacción de la 0424, y conserva el cierre de la tarifa de la 0429.
  v_declarada :=
    'Reside en el distrito de ' || trim(p_distrito) || ', provincia de ' || trim(p_provincia) || '. '
    || 'Para llegar a su centro de labores utiliza ' || p_medios_ida || ' medio(s) de transporte por tramo, '
    || 'y de regreso ' || p_medios_vuelta || '. '
    || 'El costo de cada pasaje es de S/ ' || to_char(p_costo_pasaje, 'FM999999990.00')
    || ', con un gasto diario habitual de ida y vuelta de S/ ' || to_char(v_gasto_diario, 'FM999999990.00') || '. '
    || case when v_usa_taxi
         then 'Según el horario de su turno, en ocasiones utiliza taxi u otro medio particular, cuyo costo por viaje '
              || 'asciende aproximadamente a S/ ' || to_char(p_costo_taxi, 'FM999999990.00')
              || ', alrededor de ' || p_frecuencia_taxi || ' vez(veces) por semana. '
         else 'No reporta uso ocasional de taxi u otro medio particular. '
       end
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

  -- Las piezas se guardan aparte (0429), ahora también el pasaje y el taxi.
  insert into documentos_firmados (
    alcance, persona_id, tipo, fecha_firma, ruta_declarada, monto_declarado,
    registrado_por, firma_persona, firma_persona_confirmada_at,
    firma_persona_ip, firma_persona_user_agent,
    ruta_distrito, ruta_provincia, ruta_medios_ida, ruta_medios_vuelta,
    ruta_costo_pasaje, ruta_gasto_diario, ruta_costo_taxi, ruta_frecuencia_taxi
  ) values (
    'individual', v_yo, 'ruta', fn_hoy_lima(), v_declarada, v_tarifa,
    v_yo, v_imagen, now(), v_ip, v_ua,
    trim(p_distrito), trim(p_provincia), p_medios_ida, p_medios_vuelta,
    p_costo_pasaje, v_gasto_diario,
    case when v_usa_taxi then p_costo_taxi end,
    case when v_usa_taxi then p_frecuencia_taxi end
  )
  returning id into v_id;
  -- ⇧⇧⇧ FIN CAMBIO 0489 ⇧⇧⇧

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (v_yo, 'documento_firmado', null, 'ruta · firmado digitalmente el ' || fn_hoy_lima()::text, v_yo,
     'Firma digital de la declaración de ruta (0423), reemplaza el escaneo físico.');

  return v_id;
end;
$$;


insert into migraciones_aplicadas (numero, nombre)
values (492, 'la_declaracion_de_ruta_se_renueva')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';


-- ── Comprobación de que la pegada llegó entera ──────────────────────────────
-- Todo en true y `versiones_de_confirmar` en 1. Si `tablero_conserva_0491`
-- sale false, se pegó esta ANTES que la 0491: pega la 0491 y después esta otra
-- vez. `renovar_hoy` es cuántas declaraciones quedan por renovar al pegar
-- (se esperan las 6 incompletas medidas el 2026-09-28, o menos si alguien ya
-- volvió a firmar).
select
  (select count(*) from pg_proc where proname = 'fn_ruta_por_renovar') = 1
    as criterio_puesto,
  (select pg_get_function_result(oid) like '%ruta_por_renovar%' from pg_proc
     where proname = 'fn_documentos_tablero')
    as tablero_avisa,
  (select prosrc like '%cuenta_de_servicio%' from pg_proc
     where proname = 'fn_documentos_tablero')
    as tablero_conserva_0491,
  (select prosrc like '%CAMBIO 0492%' from pg_proc
     where proname = 'fn_confirmar_mi_declaracion_ruta' and pronargs = 7)
    as candado_deja_renovar,
  (select numero = 492 and nombre = 'la_declaracion_de_ruta_se_renueva'
     from migraciones_aplicadas where numero = 492)
    as registro_es_el_mio,
  (select count(*) from pg_proc where proname = 'fn_confirmar_mi_declaracion_ruta')
    as versiones_de_confirmar,
  (select count(*) from (
     select distinct on (d.persona_id) d.*
       from documentos_firmados d
      where d.tipo = 'ruta' and d.anulado_at is null
      order by d.persona_id, d.fecha_firma desc, d.created_at desc, d.id desc) v
    where fn_ruta_por_renovar(v.fecha_firma, v.firma_persona_confirmada_at,
                              v.ruta_costo_pasaje, v.es_negativa) is not null)
    as renovar_hoy;
