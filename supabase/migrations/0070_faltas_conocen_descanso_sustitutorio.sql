-- ============================================================================
-- 0070 — Faltas: el día de descanso sustitutorio no es una inasistencia
-- ----------------------------------------------------------------------------
-- Cierra el hueco que la 0069 dejó señalado a propósito.
--
-- EL PROBLEMA: la 0069 permite compensar un feriado laborado con un día libre,
-- pero el módulo de disciplina no se enteró. Ese día la persona NO marca —
-- porque tiene permiso de no venir — y `fn_faltas` lo veía como "le tocaba y no
-- marcó" = inasistencia injustificada. Peor: `fn_faltas_resumen` lo sumaba al
-- conteo que dispara el semáforo ámbar/rojo y el memo disciplinario.
-- O sea: podíamos sancionar a alguien por tomarse el descanso que le dimos.
--
-- LA REGLA: el día compensatorio se trata EXACTAMENTE como las vacaciones —
-- justificado, con su motivo visible. No se oculta del listado: quien revisa
-- Incidencias debe ver que ese día la persona no vino Y por qué. Es la misma
-- decisión conceptual que ya tomaste con vacaciones, no una nueva.
--
-- ⚠️ POR QUÉ 'PENDIENTE' TAMBIÉN CUENTA COMO JUSTIFICADO (y en la planilla no):
--   · Para la PLANILLA solo vale OTORGADO: sin acta firmada no se toca el dinero.
--   · Para las FALTAS vale PENDIENTE y OTORGADO: lo que importa aquí es si la
--     ausencia estaba AUTORIZADA, y registrarla ya es autorización de un
--     admin/líder. Exigir el acta firmada antes de dejar de acusar a la persona
--     invertiría la carga: la sancionaríamos por una demora administrativa que
--     no es suya. El riesgo #1 de este módulo es el falso positivo (así lo dice
--     el encabezado de 0051) y esta es justo esa clase de falso positivo.
--   · NO_OTORGADO no justifica nada: si el descanso no se dio y la persona no
--     vino igual, eso sí es una inasistencia real.
--
-- Reversible: restaurar fn_faltas desde 0051 y fn_faltas_resumen desde 0067.
-- ============================================================================

-- ── fn_faltas (de 0051) — mismo cuerpo, con el descanso sustitutorio añadido ──
create or replace function fn_faltas(p_desde date, p_hasta date)
returns table (persona_id uuid, nombre text, sede text, fecha date, justificada boolean, motivo text)
language sql stable security definer set search_path = public
as $$
  with rango as (
    -- solo desde 2026 (antes no hay marcaje diario) y hasta AYER (hoy sigue en curso)
    select greatest(p_desde, date '2026-01-01') as ini, least(p_hasta, current_date - 1) as fin
  ),
  medibles as (
    select pe.id, pe.nombres || ' ' || pe.apellidos as nombre, s.codigo as sede,
           pe.sede_base_id, greatest((select ini from rango), pe.fecha_ingreso) as desde_persona
    from personas pe
    join sedes s on s.id = pe.sede_base_id
    where pe.estado = 'activo' and pe.en_planilla = true and pe.sueldo_fijo = false
      and (fn_es_admin_o_lider()
           or (fn_rol_actual() = 'supervisor_sede' and pe.sede_base_id = fn_sede_actual_persona()))
  ),
  dias as (
    select m.id as persona_id, m.nombre, m.sede, gs::date as fecha
    from medibles m
    cross join lateral generate_series(m.desde_persona, (select fin from rango), interval '1 day') gs
  ),
  evaluado as (
    select d.persona_id, d.nombre, d.sede, d.fecha,
           (t.persona_id is not null) as hay_turno,
           coalesce(t.es_descanso, false) as turno_descanso,
           tr.horario_por_dia, tr.dias_laborables
    from dias d
    left join turnos t on t.persona_id = d.persona_id and t.fecha = d.fecha
    left join lateral (
      select h.horario_por_dia, h.dias_laborables
      from horarios_asignados h
      where h.persona_id = d.persona_id and h.vigente_desde <= d.fecha
        and (h.vigente_hasta is null or h.vigente_hasta >= d.fecha)
      order by h.vigente_desde desc limit 1
    ) tr on true
  ),
  tocaba as (
    select e.*,
      case
        when e.hay_turno then not e.turno_descanso                       -- el turno del día manda
        when e.horario_por_dia is not null then (e.horario_por_dia ? (extract(dow from e.fecha)::int::text))
        when e.dias_laborables is not null then (extract(dow from e.fecha)::int = any(e.dias_laborables))
        else false
      end as trabaja
    from evaluado e
  )
  select tb.persona_id, tb.nombre, tb.sede, tb.fecha,
    (v.persona_id is not null or ju.motivo is not null or ds.persona_id is not null) as justificada,
    coalesce(
      ju.motivo,
      case when v.persona_id is not null then 'vacaciones' end,
      case when ds.persona_id is not null then 'descanso_sustitutorio' end
    ) as motivo
  from tocaba tb
  left join lateral (
    select 1 as persona_id from jornadas j
    where j.persona_id = tb.persona_id and j.fecha = tb.fecha and j.entrada_ts is not null limit 1
  ) presente on true
  left join lateral (
    select 1 as persona_id from vacaciones vc
    where vc.persona_id = tb.persona_id and tb.fecha between vc.fecha_inicio and vc.fecha_fin limit 1
  ) v on true
  left join justificaciones_asistencia ju on ju.persona_id = tb.persona_id and ju.fecha = tb.fecha
  -- ⇩ CAMBIO 0070: día compensatorio por feriado laborado = ausencia autorizada
  left join lateral (
    select 1 as persona_id from feriados_descanso_sustitutorio d
    where d.persona_id = tb.persona_id
      and d.fecha_descanso_sustitutorio = tb.fecha
      and d.estado in ('PENDIENTE', 'OTORGADO') limit 1
  ) ds on true
  left join lateral (
    select 1 as es from feriados f where f.fecha = tb.fecha limit 1
  ) fer on true
  where tb.trabaja
    and presente.persona_id is null                       -- no marcó = ausente
    and not (fer.es is not null and not tb.hay_turno)     -- feriado sin turno explícito: no cuenta
  order by tb.fecha desc, tb.nombre;
$$;

grant execute on function fn_faltas(date, date) to authenticated;

-- ── fn_faltas_resumen (de 0067) — mismo cuerpo, el día compensatorio es 'just' ──
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
          or exists (select 1 from justificaciones_asistencia ju where ju.persona_id = ev.pid and ju.fecha = ev.fecha)
          -- ⇩ CAMBIO 0070: el día compensatorio no suma al conteo disciplinario
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
$$;

grant execute on function fn_faltas_resumen(date) to authenticated;

notify pgrst, 'reload schema';
