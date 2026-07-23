-- ============================================================================
-- 0067 — Tardanzas y faltas aceptan una fecha de corte opcional (p_as_of)
-- ----------------------------------------------------------------------------
-- POR QUÉ: fn_tardanzas_resumen y fn_faltas_resumen miraban "hoy" (current_date)
-- directamente. Eso las hacía imposibles de probar con rigor (una prueba no puede
-- fingir que es otro día) y no permitía revisar el estado disciplinario de un mes
-- pasado. Ahora ambas reciben una fecha de corte OPCIONAL.
--
-- BEHAVIOR-PRESERVING: p_as_of por defecto es null → coalesce(p_as_of, current_date)
-- → cuando no se pasa nada, se comporta EXACTAMENTE igual que antes. El frontend
-- las llama con rpc(..., {}) (sin argumentos) y sigue resolviendo a esta versión.
--
-- CÓMO SE HIZO (para confiar): los cuerpos son idénticos a 0064 (tardanzas) y 0055
-- (faltas); el ÚNICO cambio es reemplazar `current_date` por `coalesce(p_as_of,
-- current_date)` en los puntos donde se define la ventana de fechas. La vigencia
-- de 12 meses del memo (tardanzas) sigue anclada a now() a propósito: es "¿el memo
-- sigue vigente hoy?", no parte de la ventana de hechos.
--
-- REVERSIBLE: soltar estas dos funciones y restaurar las de 0064 y 0055.
-- ============================================================================

-- Se suelta la versión de 0 argumentos para que rpc(..., {}) no quede ambiguo
-- entre dos firmas. La nueva, con argumento por defecto, la reemplaza.
drop function if exists fn_tardanzas_resumen();
create or replace function fn_tardanzas_resumen(p_as_of date default null)
returns table (persona_id uuid, nombre text, sede text, tardanzas_mes int, umbral text, ultima_fecha date)
language sql stable security definer set search_path = public
as $$
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
      and j.fecha >= date_trunc('month', coalesce(p_as_of, current_date))::date
      and j.fecha <= coalesce(p_as_of, current_date)
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
$$;
grant execute on function fn_tardanzas_resumen(date) to authenticated;

drop function if exists fn_faltas_resumen();
create or replace function fn_faltas_resumen(p_as_of date default null)
returns table (persona_id uuid, nombre text, sede text, consecutivas int, en_30 int, en_180 int, nivel text)
language sql stable security definer set search_path = public
as $$
  with rango as (select greatest(coalesce(p_as_of, current_date) - 180, date '2026-01-01') as ini, coalesce(p_as_of, current_date) - 1 as fin),
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
grant execute on function fn_faltas_resumen(date) to authenticated;

notify pgrst, 'reload schema';
