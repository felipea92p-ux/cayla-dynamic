-- ============================================================================
-- 0055_faltas_en30_ventana_movil.sql — en_30 pasa a ser VENTANA MÓVIL real
-- ============================================================================
-- Supersede el contador `en_30` de 0054. Antes miraba una sola ventana fija:
-- los últimos 30 días CONTADOS DESDE HOY (`fecha >= current_date - 30`). Eso NO
-- es una ventana móvil: un pico de 6 faltas en un periodo de 30 días que terminó
-- hace 40 días quedaba invisible (lo suelta el contador de 30 y el de 180 tiene
-- umbral 15, no 6), pintando VERDE a alguien con una causal documentable del
-- art. 25-h. Como los datos arrancan el 01/01/2026 (~200 días), ese pico ya pudo
-- existir y envejecer.
--
-- Ahora `en_30` = MÁXIMO de faltas injustificadas sobre CUALQUIER ventana de 30
-- días calendario dentro del lookback de 180 días. La ventana óptima siempre se
-- puede anclar a TERMINAR en un día-falta (mover el borde derecho sobre días sin
-- falta nunca suma y puede perder faltas por la izquierda), así que por cada
-- día-falta `d` contamos faltas en [d-29, d] y tomamos el máximo. Con <30 faltas
-- por persona el auto-join es trivial; no hace falta índice.
--
-- `en_180` NO cambia: 180 es justo el tamaño del lookback completo, ahí la
-- ventana fija-que-termina-hoy y la móvil coinciden. Todo lo demás (cascada
-- turno→horario, exclusiones, `consecutivas`, umbrales, filtro ámbar/rojo)
-- queda idéntico a 0054.

create or replace function fn_faltas_resumen()
returns table (persona_id uuid, nombre text, sede text, consecutivas int, en_30 int, en_180 int, nivel text)
language sql stable security definer set search_path = public
as $$
  with rango as (select greatest(current_date - 180, date '2026-01-01') as ini, current_date - 1 as fin),
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
        when exists (select 1 from vacaciones v where v.persona_id = ev.pid and ev.fecha between v.fecha_inicio and v.fecha_fin)
          or exists (select 1 from justificaciones_asistencia ju where ju.persona_id = ev.pid and ju.fecha = ev.fecha) then 'just'
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
$$;

grant execute on function fn_faltas_resumen() to authenticated;
