-- ============================================================================
-- 0091 — La hora de Lima en todo el sistema, de una vez
-- ----------------------------------------------------------------------------
-- PROMETE: que ninguna función del sistema vuelva a preguntar «¿qué día es hoy?»
--   en la zona horaria equivocada.
--
-- EL DEFECTO, y por qué esta es la CUARTA vez. El servidor de Supabase corre en
--   UTC. `current_date` desnudo resuelve en UTC, así que entre las 19:00 y la
--   medianoche de Lima el sistema ya cree que es mañana. Eso ya se arregló en la
--   0034, en la 0035 y en la 0079 — cada vez en la función que había dado el
--   problema, y cada vez volvió a entrar por otra puerta. Hoy quedaban NUEVE
--   funciones con el mismo fallo:
--
--     fn_faltas_resumen          Su ventana es "hasta ayer", justamente para no
--                                acusar a nadie por el día en curso. Con la hora
--                                de UTC, ese "ayer" es HOY: cada tarde el
--                                semáforo disciplinario cuenta un día que aún no
--                                termina y cuya justificación probablemente se
--                                cargue mañana. Y contradice a fn_faltas, que la
--                                MISMA migración 0079 sí arregló doce líneas más
--                                arriba.
--     fn_falta_contadores        Igual: los contadores que disparan el umbral
--                                legal de despido (4 consecutivas / 6 en 30 d /
--                                16 en 180 d).
--     fn_expediente_generar_*    La ventana de hechos del memo, y la fecha de
--                                inicio de una suspensión.
--     fn_tardanzas_resumen       El mes en curso del tablero de tardanzas.
--     fn_provisiones             El "as of" por defecto: cada tarde calcula las
--                                provisiones de un día que no ha pasado.
--     fn_vacaciones_resumen      Lo mismo con el saldo de vacaciones.
--     fn_set_fecha_ingreso       Rechaza fechas "futuras" que no lo son.
--     fn_expediente_correlativo  El año del correlativo. La noche del 31 de
--                                diciembre emitiría memos numerados del año
--                                siguiente.
--
-- POR QUÉ ESTA VEZ NO VUELVE. Arreglar los nueve usos y confiar en que nadie
--   escriba el décimo es lo que falló las tres veces anteriores. Aquí:
--     1. Se crea fn_hoy_lima(), un solo sitio donde vive la respuesta.
--     2. Las nueve funciones pasan a usarla.
--     3. La prueba 92 recorre pg_proc y FALLA si alguna función del sistema
--        vuelve a usar `current_date` desnudo. El CI la corre en cada push.
--   El error deja de depender de que alguien se acuerde.
--
-- NO CAMBIA NINGÚN NÚMERO durante el día. Solo entre las 19:00 y la medianoche
--   de Lima, que es justo cuando estaba mal.
--
-- CÓMO SE REVIERTE: restaurar las nueve desde sus migraciones de origen.
-- ============================================================================

-- ── El único sitio donde se responde "¿qué día es hoy?" ─────────────────────
create or replace function fn_hoy_lima()
returns date language sql stable set search_path = public as $fn$
  select (now() at time zone 'America/Lima')::date;
$fn$;
comment on function fn_hoy_lima() is
  'El día de HOY en Lima. Usar SIEMPRE en vez de current_date: el servidor corre en UTC y a partir de las 19:00 hora peruana current_date ya devuelve mañana. La prueba 92 falla si alguna función usa current_date desnudo.';
grant execute on function fn_hoy_lima() to authenticated;
revoke execute on function fn_hoy_lima() from public, anon;

-- ── fn_faltas_resumen ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_faltas_resumen(p_as_of date DEFAULT NULL::date)
 RETURNS TABLE(persona_id uuid, nombre text, sede text, consecutivas integer, en_30 integer, en_180 integer, nivel text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with rango as (select greatest(coalesce(p_as_of, fn_hoy_lima()) - 180, date '2026-01-01') as ini, coalesce(p_as_of, fn_hoy_lima()) - 1 as fin),
  medibles as (
    select pe.id, pe.nombres || ' ' || pe.apellidos as nombre, s.codigo as sede,
           greatest((select ini from rango), pe.fecha_ingreso) as desde
    from personas pe join sedes s on s.id = pe.sede_base_id
    where pe.estado = 'activo' and pe.en_planilla = true and pe.sueldo_fijo = false
      and (fn_es_admin_o_lider()
           or (fn_rol_actual() = 'supervisor_sede' and pe.sede_base_id = fn_sede_actual_persona()))
  ),
  dias as (
    select m.id as pid, gs::date as fecha
    from medibles m cross join lateral generate_series(m.desde, (select fin from rango), interval '1 day') gs
  ),
  ev as (
    select d.pid, d.fecha,
      (t.persona_id is not null) as hay_turno, coalesce(t.es_descanso, false) as turno_desc,
      tr.horario_por_dia as hpd, tr.dias_laborables as dl
    from dias d
    left join turnos t on t.persona_id = d.pid and t.fecha = d.fecha
    left join lateral (
      select h.horario_por_dia, h.dias_laborables from horarios_asignados h
      where h.persona_id = d.pid and h.vigente_desde <= d.fecha and (h.vigente_hasta is null or h.vigente_hasta >= d.fecha)
      order by h.vigente_desde desc limit 1
    ) tr on true
  ),
  -- solo días PROGRAMADOS (le tocaba; feriado sin turno no cuenta), con su estado
  sched as (
    select ev.pid, ev.fecha,
      case
        when exists (select 1 from jornadas j where j.persona_id = ev.pid and j.fecha = ev.fecha and j.entrada_ts is not null) then 'presente'
        -- ⇩ CAMBIO 0079: cumplir la sanción no alimenta la sanción siguiente
        when fn_dia_suspendido(ev.pid, ev.fecha) then 'just'
        when exists (select 1 from vacaciones v where v.persona_id = ev.pid and ev.fecha between v.fecha_inicio and v.fecha_fin)
          or exists (select 1 from justificaciones_asistencia ju where ju.persona_id = ev.pid and ju.fecha = ev.fecha)
          or exists (select 1 from feriados_descanso_sustitutorio d
                     where d.persona_id = ev.pid and d.fecha_descanso_sustitutorio = ev.fecha
                       and d.estado in ('PENDIENTE', 'OTORGADO')) then 'just'
        else 'falta'
      end as estado
    from ev
    where (case when ev.hay_turno then not ev.turno_desc
                when ev.hpd is not null then (ev.hpd ? (extract(dow from ev.fecha)::int::text))
                when ev.dl is not null then (extract(dow from ev.fecha)::int = any(ev.dl))
                else false end)
      and not (exists (select 1 from feriados f where f.fecha = ev.fecha) and not ev.hay_turno)
  ),
  rn as (
    select pid, estado, row_number() over (partition by pid order by fecha desc) as rk from sched
  ),
  consec as (
    -- racha reciente de faltas: hasta el primer día no-falta desde el más reciente
    select pid, (coalesce(min(rk) filter (where estado <> 'falta'), max(rk) + 1) - 1) as consecutivas
    from rn group by pid
  ),
  faltas_dias as (
    select pid, fecha from sched where estado = 'falta'
  ),
  -- VENTANA MÓVIL: por cada día-falta, faltas en [d-29, d]; se queda el máximo
  c30 as (
    select pid, max(cnt) as n
    from (
      select a.pid, a.fecha, count(*) as cnt
      from faltas_dias a
      join faltas_dias b on b.pid = a.pid and b.fecha between a.fecha - 29 and a.fecha
      group by a.pid, a.fecha
    ) w
    group by pid
  ),
  c180 as (select pid, count(*) as n from sched where estado = 'falta' group by pid)
  select m.id, m.nombre, m.sede,
    coalesce(cc.consecutivas, 0)::int, coalesce(c30.n, 0)::int, coalesce(c180.n, 0)::int,
    case
      when coalesce(cc.consecutivas,0) > 3 or coalesce(c30.n,0) > 5 or coalesce(c180.n,0) > 15 then 'rojo'
      when coalesce(cc.consecutivas,0) = 3 or coalesce(c30.n,0) >= 4 or coalesce(c180.n,0) >= 12 then 'ambar'
      else 'verde'
    end as nivel
  from medibles m
  left join consec cc on cc.pid = m.id
  left join c30  on c30.pid  = m.id
  left join c180 on c180.pid = m.id
  where coalesce(cc.consecutivas,0) >= 3 or coalesce(c30.n,0) >= 4 or coalesce(c180.n,0) >= 12
  order by (case when coalesce(cc.consecutivas,0) > 3 or coalesce(c30.n,0) > 5 or coalesce(c180.n,0) > 15 then 1 else 2 end), m.nombre;
$function$;

-- ── fn_falta_contadores ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_falta_contadores(p_persona_id uuid, p_desde date)
 RETURNS TABLE(consecutivas integer, en_30 integer, en_180 integer, fechas date[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with rango as (
    select greatest(p_desde, coalesce((select fecha_ingreso from personas where id = p_persona_id), date '2026-01-01'), date '2026-01-01') as ini,
           fn_hoy_lima() - 1 as fin
  ),
  dias as (
    select gs::date as fecha
    from generate_series((select ini from rango), (select fin from rango), interval '1 day') gs
  ),
  ev as (
    select d.fecha, (t.persona_id is not null) as hay_turno, coalesce(t.es_descanso, false) as turno_desc,
           tr.horario_por_dia as hpd, tr.dias_laborables as dl
    from dias d
    left join turnos t on t.persona_id = p_persona_id and t.fecha = d.fecha
    left join lateral (
      select h.horario_por_dia, h.dias_laborables from horarios_asignados h
      where h.persona_id = p_persona_id and h.vigente_desde <= d.fecha and (h.vigente_hasta is null or h.vigente_hasta >= d.fecha)
      order by h.vigente_desde desc limit 1
    ) tr on true
  ),
  sched as (
    select ev.fecha,
      case
        when exists (select 1 from jornadas j where j.persona_id = p_persona_id and j.fecha = ev.fecha and j.entrada_ts is not null) then 'presente'
        when exists (select 1 from vacaciones v where v.persona_id = p_persona_id and ev.fecha between v.fecha_inicio and v.fecha_fin)
          or exists (select 1 from justificaciones_asistencia ju where ju.persona_id = p_persona_id and ju.fecha = ev.fecha) then 'just'
        else 'falta'
      end as estado
    from ev
    where (case when ev.hay_turno then not ev.turno_desc
                when ev.hpd is not null then (ev.hpd ? (extract(dow from ev.fecha)::int::text))
                when ev.dl is not null then (extract(dow from ev.fecha)::int = any(ev.dl))
                else false end)
      and not (exists (select 1 from feriados f where f.fecha = ev.fecha) and not ev.hay_turno)
  ),
  fd as (select fecha from sched where estado = 'falta'),
  c30 as (select coalesce(max(cnt),0) as n from (
    select a.fecha, count(*) as cnt from fd a join fd b on b.fecha between a.fecha - 29 and a.fecha group by a.fecha) w),
  rn as (select estado, row_number() over (order by fecha desc) as rk from sched)
  select
    (coalesce((select min(rk) from rn where estado <> 'falta'), (select coalesce(max(rk),0) from rn) + 1) - 1)::int,
    (select n from c30)::int,
    (select count(*) from fd)::int,
    (select array_agg(fecha order by fecha) from fd);
$function$;

-- ── fn_tardanzas_resumen ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_tardanzas_resumen(p_as_of date DEFAULT NULL::date)
 RETURNS TABLE(persona_id uuid, nombre text, sede text, tardanzas_mes integer, umbral text, ultima_fecha date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with medibles as (
    select pe.id, pe.nombres || ' ' || pe.apellidos as nombre, s.codigo as sede,
      -- Corte: el periodo del último memo de tardanza YA firmado/entregado, vigente
      -- 12 meses. Las tardanzas de esa fecha o antes NO se vuelven a alertar.
      (select e.periodo_hasta
       from expediente_disciplinario e
       where e.persona_id = pe.id and e.tipo_causal = 'tardanza'
         and e.estado in ('firmado', 'entregado')
         and e.firmado_at >= now() - interval '12 months'
       order by e.firmado_at desc
       limit 1) as corte
    from personas pe join sedes s on s.id = pe.sede_base_id
    where pe.estado = 'activo' and pe.en_planilla = true and pe.sueldo_fijo = false
      and (fn_es_admin_o_lider()
           or (fn_rol_actual() = 'supervisor_sede' and pe.sede_base_id = fn_sede_actual_persona()))
  ),
  conteo as (
    select m.id as pid, count(distinct j.fecha) as n, max(j.fecha) as ult
    from medibles m
    join jornadas j on j.persona_id = m.id
      and j.fecha >= date_trunc('month', coalesce(p_as_of, fn_hoy_lima()))::date
      and j.fecha <= coalesce(p_as_of, fn_hoy_lima())
      and (m.corte is null or j.fecha > m.corte)   -- no cuenta lo ya sancionado
      and j.minutos_tarde is not null and j.minutos_tarde > 0
      and not exists (
        select 1 from tardanzas_justificadas tj
        where tj.persona_id = m.id and tj.fecha = j.fecha)
    group by m.id
  )
  select m.id, m.nombre, m.sede, c.n::int,
    case when c.n >= 3 then 'amonestacion' else 'aviso' end as umbral,
    c.ult
  from medibles m join conteo c on c.pid = m.id
  where c.n >= 2
  order by c.n desc, m.nombre;
$function$;

-- ── fn_expediente_generar_falta ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_expediente_generar_falta(p_persona_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_prev     record; v_has_prev boolean := false; v_vigente boolean := false;
  v_cutoff   date := date '2000-01-01';
  v_full     record; v_new record;
  v_nivel    text; v_hechos jsonb; v_desde date; v_hasta date;
  v_id       uuid;
begin
  if not fn_expediente_puede_actuar(p_persona_id, 'amonestacion') then
    raise exception 'Sin permiso para generar sanciones de falta para esta persona.';
  end if;
  if exists (select 1 from expediente_disciplinario
             where persona_id = p_persona_id and tipo_causal = 'falta' and estado = 'borrador') then
    raise exception 'Ya hay un borrador de falta pendiente para esta persona; revísalo o anúlalo antes de generar otro.';
  end if;

  select id, nivel, periodo_hasta, firmado_at into v_prev
  from expediente_disciplinario
  where persona_id = p_persona_id and tipo_causal = 'falta' and estado in ('firmado','entregado')
  order by firmado_at desc limit 1;
  v_has_prev := found;
  if v_has_prev then
    v_vigente := v_prev.firmado_at >= now() - interval '12 months';
    if v_vigente and v_prev.periodo_hasta is not null then v_cutoff := v_prev.periodo_hasta; end if;
  end if;

  -- art. 25-h sobre TODO el histórico (hayan sido o no sancionadas)
  select * into v_full from fn_falta_contadores(p_persona_id, fn_hoy_lima() - 180);

  if coalesce(v_full.consecutivas,0) >= 4 or coalesce(v_full.en_30,0) >= 6 or coalesce(v_full.en_180,0) >= 16 then
    v_nivel  := 'imputacion';
    v_hechos := (select jsonb_agg(jsonb_build_object('fecha', f) order by f) from unnest(v_full.fechas) as f);
    v_desde  := (select min(f) from unnest(v_full.fechas) as f);
    v_hasta  := (select max(f) from unnest(v_full.fechas) as f);
  else
    -- escalación sobre faltas NUEVAS (non bis in idem)
    select * into v_new from fn_falta_contadores(p_persona_id, v_cutoff + 1);
    if coalesce(v_new.en_180,0) < 1 then
      raise exception 'No corresponde: sin faltas injustificadas nuevas.';
    end if;
    if v_vigente and v_prev.nivel = 'imputacion' then
      raise exception 'Ya hay una imputación vigente; el despido se genera tras evaluar los descargos (paso manual de Gerencia).';
    elsif v_vigente and v_prev.nivel = 'suspension' then
      v_nivel := 'imputacion';                              -- reincidencia sobre suspensión
    elsif v_vigente and v_prev.nivel = 'amonestacion' then
      v_nivel := 'suspension';                              -- reincidencia sobre amonestación
    else
      v_nivel := 'amonestacion';                            -- 1ª falta injustificada
    end if;
    v_hechos := (select jsonb_agg(jsonb_build_object('fecha', f) order by f) from unnest(v_new.fechas) as f);
    v_desde  := (select min(f) from unnest(v_new.fechas) as f);
    v_hasta  := (select max(f) from unnest(v_new.fechas) as f);
  end if;

  v_id := fn_expediente_crear_borrador(
    p_persona_id, 'falta', v_nivel, v_hechos, v_desde, v_hasta,
    case when v_has_prev then v_prev.id else null end,
    case when v_nivel = 'suspension' then 1 else null end,
    case when v_nivel = 'suspension' then fn_hoy_lima() + 1 else null end,
    case when v_nivel = 'suspension' then fn_hoy_lima() + 1 else null end,
    null);
  return v_id;
end;
$function$;

-- ── fn_expediente_generar_tardanza ────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_expediente_generar_tardanza(p_persona_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_prev      record;
  v_has_prev  boolean := false;
  v_vigente   boolean := false;
  v_cutoff    date := date '2000-01-01';
  v_nivel     text;
  v_n         int;
  v_hechos    jsonb;
  v_desde     date;
  v_hasta     date;
  v_id        uuid;
begin
  if not fn_expediente_puede_actuar(p_persona_id, 'amonestacion') then
    raise exception 'Sin permiso para generar sanciones de tardanza para esta persona.';
  end if;

  if exists (select 1 from expediente_disciplinario
             where persona_id = p_persona_id and tipo_causal = 'tardanza' and estado = 'borrador') then
    raise exception 'Ya hay un borrador de tardanza pendiente para esta persona; revísalo o anúlalo antes de generar otro.';
  end if;

  -- último documento de tardanza firmado (o entregado)
  select id, nivel, periodo_hasta, firmado_at into v_prev
  from expediente_disciplinario
  where persona_id = p_persona_id and tipo_causal = 'tardanza' and estado in ('firmado','entregado')
  order by firmado_at desc limit 1;
  v_has_prev := found;

  if v_has_prev then
    v_vigente := v_prev.firmado_at >= now() - interval '12 months';
    if v_vigente and v_prev.periodo_hasta is not null then v_cutoff := v_prev.periodo_hasta; end if;
  end if;

  -- tardanzas del MES en curso, POSTERIORES al cutoff, no levantadas (non bis in idem)
  select jsonb_agg(jsonb_build_object('fecha', fecha, 'minutos', minutos_tarde) order by fecha),
         count(*), min(fecha), max(fecha)
    into v_hechos, v_n, v_desde, v_hasta
  from (
    select j.fecha, j.minutos_tarde
    from jornadas j
    where j.persona_id = p_persona_id
      and j.fecha >= greatest(date_trunc('month', fn_hoy_lima())::date, v_cutoff + 1)
      and j.fecha <= fn_hoy_lima()
      and j.minutos_tarde is not null and j.minutos_tarde > 0
      and not exists (select 1 from tardanzas_justificadas tj
                      where tj.persona_id = p_persona_id and tj.fecha = j.fecha)
  ) t;
  v_n := coalesce(v_n, 0);

  -- decidir el nivel según el historial (RIT art. 7 b/c/d)
  if v_vigente and v_prev.nivel = 'imputacion' then
    raise exception 'Ya hay una imputación de cargos vigente; el despido se genera tras evaluar los descargos (paso manual de Gerencia).';
  elsif v_vigente and v_prev.nivel = 'suspension' then
    if v_n < 1 then raise exception 'No corresponde: no hay tardanzas nuevas tras la suspensión.'; end if;
    v_nivel := 'imputacion';                                    -- umbral d
  elsif v_vigente and v_prev.nivel = 'amonestacion' then
    if v_n < 2 then raise exception 'Aún no corresponde suspensión: necesita 2 tardanzas nuevas tras la amonestación (lleva %).', v_n; end if;
    v_nivel := 'suspension';                                    -- umbral c
  else
    if v_n < 3 then raise exception 'Aún no corresponde amonestación: necesita 3 tardanzas en el mes (lleva %).', v_n; end if;
    v_nivel := 'amonestacion';                                  -- umbral b
  end if;

  v_id := fn_expediente_crear_borrador(
    p_persona_id, 'tardanza', v_nivel, v_hechos, v_desde, v_hasta,
    case when v_has_prev then v_prev.id else null end,
    -- suspensión: default 1 día al día siguiente, EDITABLE antes de firmar
    case when v_nivel = 'suspension' then 1 else null end,
    case when v_nivel = 'suspension' then fn_hoy_lima() + 1 else null end,
    case when v_nivel = 'suspension' then fn_hoy_lima() + 1 else null end,
    null);

  return v_id;
end;
$function$;

-- ── fn_expediente_correlativo ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_expediente_correlativo(p_prefijo text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_anio int := extract(year from fn_hoy_lima())::int; v_n int;
begin
  insert into expediente_correlativo_seq (anio, prefijo, ultimo)
  values (v_anio, p_prefijo, 1)
  on conflict (anio, prefijo) do update set ultimo = expediente_correlativo_seq.ultimo + 1
  returning ultimo into v_n;
  -- ej. 'T-02/0007-2026-CAYLA'
  return p_prefijo || '/' || lpad(v_n::text, 4, '0') || '-' || v_anio || '-CAYLA';
end;
$function$;

-- ── fn_provisiones ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_provisiones(p_as_of date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_as_of date; v_y int;
  v_prov jsonb; v_f_grati numeric; v_f_cts numeric; v_f_vac numeric;
  g1_ini date; g1_fin date; g1_pago date;
  g2_ini date; g2_fin date; g2_pago date;
  c1_ini date; c1_fin date; c1_pago date;
  c2_ini date; c2_fin date; c2_pago date;
  v_prox_fecha date; v_prox_tipo text; v_prox_ref text;
  v_out jsonb;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o lider puede ver las provisiones.';
  end if;
  v_as_of := coalesce(p_as_of, fn_hoy_lima());
  v_y := extract(year from v_as_of)::int;

  select valor into v_prov from configuracion where clave = 'planilla_provisiones';
  if v_prov is null then
    v_prov := '{"gratificacion":0.08333,"cts":0.04167,"vacaciones":0.04167}'::jsonb;
  end if;
  v_f_grati := coalesce((v_prov->>'gratificacion')::numeric, 0);
  v_f_cts   := coalesce((v_prov->>'cts')::numeric, 0);
  v_f_vac   := coalesce((v_prov->>'vacaciones')::numeric, 0);

  -- Ventanas del ano (periodos legales)
  g1_ini := make_date(v_y,1,1);    g1_fin := make_date(v_y,6,30);  g1_pago := make_date(v_y,7,15);
  g2_ini := make_date(v_y,7,1);    g2_fin := make_date(v_y,12,31); g2_pago := make_date(v_y,12,15);
  c1_ini := make_date(v_y-1,11,1); c1_fin := make_date(v_y,4,30);  c1_pago := make_date(v_y,5,15);
  c2_ini := make_date(v_y,5,1);    c2_fin := make_date(v_y,10,31); c2_pago := make_date(v_y,11,15);

  -- Proximo desembolso: la fecha de pago mas cercana que aun no pasa.
  -- Incluye tambien las ventanas del ANO SIGUIENTE: entre el 16 y el 31 de dic,
  -- tras el ultimo pago del ano (grati_s2, 15-dic), el proximo desembolso cae en
  -- el ano v_y+1 (CTS may). Sin estas filas, 'proximo' quedaria NULL esas dos
  -- semanas de cada diciembre.
  select fecha, tipo, ref into v_prox_fecha, v_prox_tipo, v_prox_ref
  from (values
    (c1_pago, 'CTS',           'cts_may'),
    (g1_pago, 'Gratificacion', 'grati_s1'),
    (c2_pago, 'CTS',           'cts_nov'),
    (g2_pago, 'Gratificacion', 'grati_s2'),
    (make_date(v_y+1, 5,15), 'CTS',           'cts_may'),
    (make_date(v_y+1, 7,15), 'Gratificacion', 'grati_s1'),
    (make_date(v_y+1,11,15), 'CTS',           'cts_nov'),
    (make_date(v_y+1,12,15), 'Gratificacion', 'grati_s2')
  ) t(fecha, tipo, ref)
  where fecha >= v_as_of
  order by fecha
  limit 1;

  with base as (
    -- 1) Sueldo regular ganado por HORAS (base mensual correcta). Excluye a quien
    --    cobra sueldo fijo: ese va por la rama 2, para no contar dos veces.
    select j.persona_id, j.fecha,
           j.horas_trabajadas * tt.salario
             / (6.5 * extract(day from (date_trunc('month', j.fecha) + interval '1 month - 1 day'))::numeric) as pago_dia
    from jornadas j
    join personas pp on pp.id = j.persona_id and not pp.sueldo_fijo
    join lateral (
      select a.salario_mensual_soles as salario
      from asignaciones_salario a
      where a.persona_id = j.persona_id
        and j.fecha >= a.vigente_desde
        and (a.vigente_hasta is null or j.fecha <= a.vigente_hasta)
      order by a.vigente_desde desc limit 1
    ) tt on true
    where j.horas_trabajadas is not null and j.horas_trabajadas > 0

    union all

    -- 2) SUELDO FIJO: provisiona su salario completo cada mes, marque o no. Se
    --    genera un aporte diario = salario / días del mes para cada día de
    --    calendario desde su ingreso; al sumar un mes entero da el salario, y en
    --    los bordes prorratea por días. Mismo criterio que ya usa planilla.
    select p.id as persona_id, gs::date as fecha,
           sal.salario
             / extract(day from (date_trunc('month', gs) + interval '1 month - 1 day'))::numeric as pago_dia
    from personas p
    cross join lateral generate_series(p.fecha_ingreso::timestamp, v_as_of::timestamp, interval '1 day') gs
    join lateral (
      select a.salario_mensual_soles as salario
      from asignaciones_salario a
      where a.persona_id = p.id
        and gs::date >= a.vigente_desde
        and (a.vigente_hasta is null or gs::date <= a.vigente_hasta)
      order by a.vigente_desde desc limit 1
    ) sal on true
    where p.sueldo_fijo
  )
  select coalesce(jsonb_agg(sub.fila order by sub.nombre), '[]'::jsonb) into v_out
  from (
    select (p.nombres || ' ' || p.apellidos) as nombre,
      jsonb_build_object(
        'persona_id', p.id,
        'nombre', p.nombres || ' ' || p.apellidos,
        'sede', s.codigo,
        'fecha_ingreso', p.fecha_ingreso,
        'grati_s1', round(v_f_grati * coalesce(g1.pago,0), 2),
        'grati_s2', round(v_f_grati * coalesce(g2.pago,0), 2),
        'grati_total', round(v_f_grati * (coalesce(g1.pago,0) + coalesce(g2.pago,0)), 2),
        'cts_may', round(v_f_cts * coalesce(cm.pago,0), 2),
        'cts_nov', round(v_f_cts * coalesce(cn.pago,0), 2),
        'cts_total', round(v_f_cts * (coalesce(cm.pago,0) + coalesce(cn.pago,0)), 2),
        'vac', round(v_f_vac * coalesce(vv.pago,0), 2),
        'vac_dias', round(15.0 * (v_as_of - va.aniv_ini)::numeric / 365.0, 1),
        'proximo_aniversario', va.aniv_next,
        'gran_total', round(
          v_f_grati * (coalesce(g1.pago,0) + coalesce(g2.pago,0))
          + v_f_cts * (coalesce(cm.pago,0) + coalesce(cn.pago,0))
          + v_f_vac * coalesce(vv.pago,0), 2)
      ) as fila
    from personas p
    join sedes s on s.id = p.sede_base_id
    cross join lateral (
      select (p.fecha_ingreso + make_interval(years => extract(year from age(v_as_of, p.fecha_ingreso))::int))::date as aniv_ini,
             (p.fecha_ingreso + make_interval(years => extract(year from age(v_as_of, p.fecha_ingreso))::int + 1))::date as aniv_next
    ) va
    left join lateral (select sum(b.pago_dia) as pago from base b where b.persona_id=p.id and b.fecha between greatest(g1_ini,p.fecha_ingreso) and least(v_as_of,g1_fin)) g1 on true
    left join lateral (select sum(b.pago_dia) as pago from base b where b.persona_id=p.id and b.fecha between greatest(g2_ini,p.fecha_ingreso) and least(v_as_of,g2_fin)) g2 on true
    left join lateral (select sum(b.pago_dia) as pago from base b where b.persona_id=p.id and b.fecha between greatest(c1_ini,p.fecha_ingreso) and least(v_as_of,c1_fin)) cm on true
    left join lateral (select sum(b.pago_dia) as pago from base b where b.persona_id=p.id and b.fecha between greatest(c2_ini,p.fecha_ingreso) and least(v_as_of,c2_fin)) cn on true
    left join lateral (select sum(b.pago_dia) as pago from base b where b.persona_id=p.id and b.fecha between va.aniv_ini and v_as_of) vv on true
    where p.estado = 'activo'
  ) sub;

  return jsonb_build_object(
    'as_of', v_as_of,
    'factores', v_prov,
    'proximo', jsonb_build_object('fecha', v_prox_fecha, 'tipo', v_prox_tipo, 'ref', v_prox_ref),
    'grati_s1_pago', g1_pago, 'grati_s2_pago', g2_pago,
    'cts_may_pago', c1_pago, 'cts_nov_pago', c2_pago,
    'grati_s1_periodo', 'ene-jun', 'grati_s2_periodo', 'jul-dic',
    'cts_may_periodo', 'nov-abr', 'cts_nov_periodo', 'may-oct',
    'personas', v_out
  );
end;
$function$;

-- ── fn_vacaciones_resumen ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_vacaciones_resumen(p_as_of date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_as_of date;
  v_out jsonb;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver el resumen de vacaciones.';
  end if;
  v_as_of := coalesce(p_as_of, fn_hoy_lima());

  select coalesce(jsonb_agg(s.fila order by s.nombre), '[]'::jsonb) into v_out
  from (
    select
      (p.nombres || ' ' || p.apellidos) as nombre,
      jsonb_build_object(
        'persona_id',          p.id,
        'nombre',              p.nombres || ' ' || p.apellidos,
        'fecha_ingreso',       p.fecha_ingreso,
        'aniversario_ini',     av.aniv_ini,
        'aniversario_next',    av.aniv_next,
        'dias_transcurridos',  gd.dias_transcurridos,
        'dias_ganados',        gd.dias_ganados,
        'dias_tomados',        gd.dias_tomados,
        'dias_saldo',          round(gd.dias_ganados - gd.dias_tomados, 1),
        'dias_con_marca',      coalesce(hm.dias_con_marca, 0),
        'horas_marcadas',      round(coalesce(hm.horas, 0), 2),
        'feriados_en_periodo', coalesce(fe.n, 0),
        'horas_feriados',      round(gd.horas_feriados, 2),
        'horas_base',          round(gd.base_horas, 2),
        'factor',              gd.factor,
        'salario',             sal.salario,
        -- Lo que le toca por sus días PENDIENTES. Topado en 0: no hay pago negativo.
        'monto_estimado',      case when sal.salario is not null
                                 then round(greatest(0,
                                        (sal.salario / 2) * gd.factor
                                        * (gd.dias_ganados - gd.dias_tomados) / 15.0
                                      ), 2)
                                 else null end
      ) as fila
    from personas p
    -- aniversario (solo informativo: el saldo ya NO depende de esta ventana)
    join lateral (
      select (p.fecha_ingreso + make_interval(years => extract(year from age(v_as_of, p.fecha_ingreso))::int))::date as aniv_ini,
             (p.fecha_ingreso + make_interval(years => extract(year from age(v_as_of, p.fecha_ingreso))::int + 1))::date as aniv_next
    ) av on true
    -- horas marcadas en el AÑO EN CURSO (desde su último aniversario): es la
    -- referencia del ritmo de trabajo con que se paga el descanso.
    left join lateral (
      select sum(j.horas_trabajadas) as horas,
             count(*) filter (where j.horas_trabajadas > 0) as dias_con_marca
      from jornadas j
      where j.persona_id = p.id
        and j.fecha between av.aniv_ini and v_as_of
        and j.horas_trabajadas is not null and j.horas_trabajadas > 0
    ) hm on true
    left join lateral (
      select count(*) as n
      from feriados f
      where f.fecha between av.aniv_ini and v_as_of
        and not exists (
          select 1 from jornadas j2
          where j2.persona_id = p.id and j2.fecha = f.fecha
            and j2.horas_trabajadas is not null and j2.horas_trabajadas > 0
        )
    ) fe on true
    -- Días tomados en TODA su historia (no recortado a la ventana del aniversario):
    -- ésta es la corrección de fondo respecto de 0043.
    left join lateral (
      select coalesce(sum(
               greatest(0, (least(v.fecha_fin, v_as_of) - v.fecha_inicio) + 1)
             ), 0)::numeric as dias
      from vacaciones v
      where v.persona_id = p.id and v.fecha_inicio <= v_as_of
    ) vt on true
    -- días tomados dentro del año en curso: solo para descontarlos de la BASE de
    -- horas (esos días no se le pueden exigir trabajados)
    left join lateral (
      select coalesce(sum(
               greatest(0, (least(v.fecha_fin, v_as_of) - greatest(v.fecha_inicio, av.aniv_ini)) + 1)
             ), 0)::numeric as dias
      from vacaciones v
      where v.persona_id = p.id
        and v.fecha_inicio <= v_as_of and v.fecha_fin >= av.aniv_ini
    ) vv on true
    left join lateral (
      select a.salario_mensual_soles as salario
      from asignaciones_salario a
      where a.persona_id = p.id
        and a.vigente_desde <= v_as_of
        and (a.vigente_hasta is null or a.vigente_hasta >= v_as_of)
      order by a.vigente_desde desc limit 1
    ) sal on true
    join lateral (
      select
        (v_as_of - av.aniv_ini) as dias_transcurridos,
        -- ACUMULADO desde el ingreso, sin tope: 2 años de servicio = 30 días
        round(15.0 * greatest(0, (v_as_of - p.fecha_ingreso))::numeric / 365.0, 1) as dias_ganados,
        vt.dias as dias_tomados,
        (45.0 * greatest(0, (v_as_of - av.aniv_ini) - vv.dias)::numeric / 7.0) as base_horas,
        coalesce(
          coalesce(fe.n, 0)::numeric
            * coalesce(hm.horas, 0) / nullif(coalesce(hm.dias_con_marca, 0), 0)
        , 0) as horas_feriados
    ) g0 on true
    join lateral (
      select g0.dias_transcurridos, g0.dias_ganados, g0.dias_tomados,
             g0.base_horas, g0.horas_feriados,
             case when p.sueldo_fijo then 1.0
                  when g0.base_horas > 0
                    then round((coalesce(hm.horas, 0) + g0.horas_feriados) / g0.base_horas, 4)
                  else 0 end as factor
    ) gd on true
    where p.estado = 'activo' and p.fecha_ingreso is not null
  ) s;

  return coalesce(v_out, '[]'::jsonb);
end;
$function$;

-- ── fn_set_fecha_ingreso ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_set_fecha_ingreso(p_persona_id uuid, p_fecha date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede cambiar la fecha de ingreso.';
  end if;
  if p_fecha is null then raise exception 'La fecha de ingreso es obligatoria.'; end if;
  if p_fecha > fn_hoy_lima() then raise exception 'La fecha de ingreso no puede ser futura.'; end if;
  if exists (
    select 1 from periodos_planilla pp
    join jornadas j on j.fecha between pp.fecha_ini and pp.fecha_fin
    where pp.estado = 'pagado' and j.persona_id = p_persona_id and j.horas_trabajadas is not null
  ) then
    raise exception 'Esta persona ya tiene un periodo PAGADO con jornadas trabajadas: cambiar su fecha de ingreso podría alterar los feriados de esa planilla. Reabre el periodo primero.';
  end if;
  update personas set fecha_ingreso = p_fecha where id = p_persona_id;
  if not found then raise exception 'Persona inválida.'; end if;
end;
$function$;

insert into migraciones_aplicadas (numero, nombre)
values (91, 'la_hora_de_lima_en_todo_el_sistema')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
