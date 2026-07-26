-- ============================================================================
-- 0079 — Cumplir una suspensión no es faltar
-- ----------------------------------------------------------------------------
-- PROMETE: que los días en que una persona está cumpliendo una suspensión sin
--   goce de haber queden registrados como ausencia AUTORIZADA (visibles, con
--   su motivo), y no sumen al conteo disciplinario que empuja al despido.
-- ASUME: la suspensión vive en expediente_disciplinario con estado 'firmado' u
--   'entregado' y su rango en suspension_desde…suspension_hasta (mig. 0056).
--
-- EL DEFECTO. La detección de faltas (última versión en 0070) excluye del
-- conteo: vacaciones, justificaciones, descanso sustitutorio y feriados sin
-- turno. No excluye las suspensiones. Y una suspensión es justamente un día
-- que la persona TENÍA programado trabajar y en el que, por orden de la
-- empresa, no vino y no marcó. Es decir: cumple los cuatro requisitos de
-- "falta injustificada" y se cuenta como tal.
--
-- LA CONSECUENCIA, EN CONCRETO. Suspendes a alguien tres días. El sistema
-- registra tres faltas injustificadas. El umbral legal del art. 25-h del
-- D.S. 003-97-TR se configura con más de cinco en treinta días: dos
-- suspensiones cortas en un mes y el semáforo se pone rojo, el sistema arma el
-- expediente y señala "posible causal". La sanción que ya se cumplió se
-- convierte en la prueba para la siguiente. Eso es sancionar dos veces el
-- mismo hecho, y no se sostiene ante una inspección ni ante un juez.
--
-- ESTA REGLA YA EXISTÍA EN EL SISTEMA, A MEDIAS. La 0064 corrigió exactamente
-- esto para las tardanzas ("non bis in idem": una tardanza ya amonestada no
-- vuelve a contar). Faltas nació sin esa mitad. No se está inventando un
-- criterio: se está terminando de aplicar el que ya tomaste.
--
-- DECISIÓN (Felipe, 26/07/2026): el día se ve, con su motivo 'suspension',
-- pero no cuenta. Se descartó ocultarlo, porque el legajo tiene que poder
-- mostrar que la sanción se cumplió; y se descartó justificarlo a mano,
-- porque depende de que nadie olvide un paso y el olvido escala solo.
--
-- POR QUÉ NO SE MATERIALIZA. Igual que las faltas y las tardanzas, el día
-- suspendido no se escribe en ninguna tabla: se computa. Si se guardara,
-- anular un expediente dejaría filas mintiendo.
--
-- SOLO CUENTAN LOS DOCUMENTOS VIVOS ('firmado','entregado'). Un borrador aún
-- no sanciona a nadie, y uno anulado dejó de hacerlo: en ambos casos el día
-- vuelve a ser una ausencia común, que es lo correcto.
--
-- Reversible: restaurar fn_faltas y fn_faltas_resumen de la 0070.
-- ============================================================================

-- ── ¿Esta persona estaba cumpliendo suspensión este día? ────────────────────
-- Se extrae a una función propia para que las dos consultas de faltas usen
-- LA MISMA definición. Si divergieran, el detalle diría una cosa y el semáforo
-- otra sobre la misma persona — que es como nacen los errores que nadie cree.
create or replace function fn_dia_suspendido(p_persona_id uuid, p_fecha date)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from expediente_disciplinario e
    where e.persona_id = p_persona_id
      and e.estado in ('firmado', 'entregado')
      and e.suspension_desde is not null
      and p_fecha between e.suspension_desde and e.suspension_hasta
  );
$$;
grant  execute on function fn_dia_suspendido(uuid, date) to authenticated;
revoke execute on function fn_dia_suspendido(uuid, date) from public, anon;


-- ── El detalle día por día ──────────────────────────────────────────────────
-- Cuerpo idéntico al de la 0070 salvo el nuevo left join `sus` y su aparición
-- en `justificada` y `motivo`.
create or replace function fn_faltas(p_desde date, p_hasta date)
returns table (persona_id uuid, nombre text, sede text, fecha date, justificada boolean, motivo text)
language sql stable security definer set search_path = public
as $$
  with medibles as (
    select pe.id, pe.nombres || ' ' || pe.apellidos as nombre, s.codigo as sede, pe.fecha_ingreso
    from personas pe join sedes s on s.id = pe.sede_base_id
    where pe.estado = 'activo' and pe.en_planilla = true and pe.sueldo_fijo = false
      and (fn_es_admin_o_lider()
           or (fn_rol_actual() = 'supervisor_sede' and pe.sede_base_id = fn_sede_actual_persona()))
  ),
  dias as (
    select m.id as persona_id, m.nombre, m.sede, gs::date as fecha
    from medibles m
    cross join lateral generate_series(
      greatest(p_desde, m.fecha_ingreso),
      least(p_hasta, (now() at time zone 'America/Lima')::date - 1),
      interval '1 day') gs
  ),
  evaluado as (
    select d.*,
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
    (v.persona_id is not null or ju.motivo is not null or ds.persona_id is not null
     or sus.es is not null) as justificada,
    coalesce(
      -- La suspensión manda sobre cualquier otro motivo: es un hecho de la
      -- empresa, no una situación de la persona.
      case when sus.es is not null then 'suspension' end,
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
  left join lateral (
    select 1 as persona_id from feriados_descanso_sustitutorio d
    where d.persona_id = tb.persona_id
      and d.fecha_descanso_sustitutorio = tb.fecha
      and d.estado in ('PENDIENTE', 'OTORGADO') limit 1
  ) ds on true
  -- ⇩ CAMBIO 0079: el día que se cumple una sanción no es una falta
  left join lateral (
    select 1 as es where fn_dia_suspendido(tb.persona_id, tb.fecha)
  ) sus on true
  left join lateral (
    select 1 as es from feriados f where f.fecha = tb.fecha limit 1
  ) fer on true
  where tb.trabaja
    and presente.persona_id is null                       -- no marcó = ausente
    and not (fer.es is not null and not tb.hay_turno)     -- feriado sin turno explícito: no cuenta
  order by tb.fecha desc, tb.nombre;
$$;

grant  execute on function fn_faltas(date, date) to authenticated;
revoke execute on function fn_faltas(date, date) from public, anon;


-- ── El semáforo legal ───────────────────────────────────────────────────────
-- Cuerpo idéntico al de la 0070 salvo la rama nueva en `sched`. Este es el que
-- de verdad importa: es el que dispara "posible causal — revisar".
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
$$;

grant  execute on function fn_faltas_resumen(date) to authenticated;
revoke execute on function fn_faltas_resumen(date) from public, anon;

insert into migraciones_aplicadas (numero, nombre) values (79, 'suspension_no_es_falta')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
