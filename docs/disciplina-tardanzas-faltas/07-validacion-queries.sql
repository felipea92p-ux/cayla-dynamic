-- ============================================================================
-- 07 — Consultas de VALIDACIÓN (correr en el SQL Editor de Supabase y pegar)
-- ============================================================================
-- Por qué estas y NO `select * from fn_faltas_resumen();`:
-- las funciones fn_*_resumen filtran por el ROL del usuario logueado (auth.uid()).
-- En el SQL Editor no hay usuario logueado → auth.uid() es NULL → las funciones
-- devuelven VACÍO aunque haya faltas. Estas consultas reproducen el MISMO cálculo
-- SIN el filtro de rol, así que sí devuelven números reales. Solo lectura.
--
-- Aplicar antes: 0055 (no hace falta para estas queries, pero sí para que la
-- función real quede corregida). Estas queries no dependen de ninguna migración
-- nueva salvo que exista tardanzas_justificadas (mig 0053, ya aplicada).

-- ── QUERY 1 — FALTAS: contadores + fechas exactas (para verificar a mano) ─────
with rango as (select greatest(current_date - 180, date '2026-01-01') as ini, current_date - 1 as fin),
medibles as (
  select pe.id, pe.nombres || ' ' || pe.apellidos as nombre, s.codigo as sede,
         greatest((select ini from rango), pe.fecha_ingreso) as desde
  from personas pe join sedes s on s.id = pe.sede_base_id
  where pe.estado = 'activo' and pe.en_planilla = true and pe.sueldo_fijo = false
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
faltas_dias as (select pid, fecha from sched where estado = 'falta'),
c30 as (
  select pid, max(cnt) as n from (
    select a.pid, a.fecha, count(*) as cnt
    from faltas_dias a join faltas_dias b on b.pid = a.pid and b.fecha between a.fecha - 29 and a.fecha
    group by a.pid, a.fecha) w group by pid
),
c180 as (select pid, count(*) as n from faltas_dias group by pid),
rn as (select pid, estado, row_number() over (partition by pid order by fecha desc) as rk from sched),
consec as (select pid, (coalesce(min(rk) filter (where estado <> 'falta'), max(rk)+1) - 1) as consecutivas from rn group by pid)
select m.nombre, m.sede,
  coalesce(cc.consecutivas,0) as consecutivas,
  coalesce(c30.n,0)          as en_30_movil,
  coalesce(c180.n,0)         as en_180,
  (select array_agg(fecha order by fecha) from faltas_dias fd where fd.pid = m.id) as fechas_falta
from medibles m
left join consec cc on cc.pid = m.id
left join c30 on c30.pid = m.id
left join c180 on c180.pid = m.id
order by coalesce(c180.n,0) desc, m.nombre;


-- ── QUERY 2 — TARDANZAS del mes en curso + fechas ────────────────────────────
with medibles as (
  select pe.id, pe.nombres || ' ' || pe.apellidos as nombre, s.codigo as sede
  from personas pe join sedes s on s.id = pe.sede_base_id
  where pe.estado = 'activo' and pe.en_planilla = true and pe.sueldo_fijo = false
)
select m.nombre, m.sede,
  count(distinct j.fecha) as tardanzas_mes,
  array_agg(distinct j.fecha order by j.fecha) as fechas_tardanza
from medibles m
join jornadas j on j.persona_id = m.id
  and j.fecha >= date_trunc('month', current_date)::date and j.fecha <= current_date
  and j.minutos_tarde is not null and j.minutos_tarde > 0
  and not exists (select 1 from tardanzas_justificadas tj where tj.persona_id = m.id and tj.fecha = j.fecha)
group by m.nombre, m.sede
order by tardanzas_mes desc, m.nombre;
