-- ============================================================================
-- 0051_faltas_deteccion.sql — Fase 1 de faltas: justificaciones + detección
-- ============================================================================
-- Detecta INASISTENCIAS (le tocaba trabajar y no marcó) para que salgan en
-- Incidencias y escalen al conteo legal. Nada se materializa ni se sanciona:
-- este archivo solo crea (1) la tabla de justificaciones, (2) las funciones para
-- justificar, y (3) fn_faltas que COMPUTA las faltas de un rango. La UI y los
-- contadores van en fases siguientes.
--
-- ⚠️ El riesgo # 1 es el falso positivo (acusar de falta a quien no debía). Por
-- eso fn_faltas aplica las 7 condiciones acordadas y SE DEBE PROBAR su salida
-- contra datos reales ANTES de conectarla a ninguna pantalla.
--
-- Decisiones (2026-07-21): feriado no cuenta salvo turno explícito · cualquier
-- marca = presente · solo desde 2026-01-01 · se listan justificadas e
-- injustificadas · justifica admin/líder y encargada de su sede · observación
-- obligatoria solo en 'otro' · se puede justificar cualquier fecha (incl. futura).

-- ── 1) Tabla de justificaciones ──────────────────────────────────────────────
create table if not exists justificaciones_asistencia (
  id           uuid primary key default gen_random_uuid(),
  persona_id   uuid not null references personas(id),
  fecha        date not null,
  motivo       text not null check (motivo in ('permiso_concedido','cumpleanos','estudios','descanso_medico','otro')),
  observacion  text,
  creado_por   uuid not null references personas(id),
  creado_at    timestamptz not null default now(),
  unique (persona_id, fecha)  -- un día se justifica una sola vez
);
create index if not exists idx_justif_persona on justificaciones_asistencia (persona_id, fecha);

alter table justificaciones_asistencia enable row level security;
drop policy if exists justif_select_admin_lider on justificaciones_asistencia;
create policy justif_select_admin_lider on justificaciones_asistencia
  for select to authenticated using (fn_es_admin_o_lider());
drop policy if exists justif_select_supervisor on justificaciones_asistencia;
create policy justif_select_supervisor on justificaciones_asistencia
  for select to authenticated using (
    fn_rol_actual() = 'supervisor_sede'
    and persona_id in (select id from personas where sede_base_id = fn_sede_actual_persona())
  );
drop policy if exists justif_select_propia on justificaciones_asistencia;
create policy justif_select_propia on justificaciones_asistencia
  for select to authenticated using (persona_id = fn_persona_actual_id());

-- ── 2) Registrar / quitar una justificación ─────────────────────────────────
-- Reusa fn_verificar_corrector: admin/líder sobre cualquiera, encargada solo su
-- sede, nadie sobre sí mismo ni sobre un admin (mismo permiso que corregir).
create or replace function fn_set_justificacion(
  p_persona_id uuid, p_fecha date, p_motivo text, p_observacion text default null
)
returns void
language plpgsql security definer set search_path = public
as $$
declare v_editor uuid;
begin
  v_editor := fn_verificar_corrector(p_persona_id); -- valida permiso o lanza
  if p_motivo is null or p_motivo not in ('permiso_concedido','cumpleanos','estudios','descanso_medico','otro') then
    raise exception 'Motivo inválido.';
  end if;
  if p_motivo = 'otro' and (p_observacion is null or length(trim(p_observacion)) < 3) then
    raise exception 'Para el motivo "otro" la observación es obligatoria.';
  end if;
  insert into justificaciones_asistencia (persona_id, fecha, motivo, observacion, creado_por)
  values (p_persona_id, p_fecha, p_motivo, nullif(trim(coalesce(p_observacion,'')),''), v_editor)
  on conflict (persona_id, fecha)
  do update set motivo = excluded.motivo, observacion = excluded.observacion,
                creado_por = excluded.creado_por, creado_at = now();
end;
$$;

create or replace function fn_quitar_justificacion(p_persona_id uuid, p_fecha date)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  perform fn_verificar_corrector(p_persona_id); -- valida permiso o lanza
  delete from justificaciones_asistencia where persona_id = p_persona_id and fecha = p_fecha;
end;
$$;

grant execute on function fn_set_justificacion(uuid, date, text, text) to authenticated;
grant execute on function fn_quitar_justificacion(uuid, date) to authenticated;

-- ── 3) Detección: faltas de un rango, por persona/día ────────────────────────
-- Devuelve TODOS los días en que le tocaba y no marcó, con `justificada` y su
-- motivo (vacaciones cuenta como justificada). La UI decide cómo pintarlas.
-- Solo devuelve filas al rol que corresponde (admin/líder todo; encargada su
-- sede; cualquier otro rol, vacío).
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
    (v.persona_id is not null or ju.motivo is not null) as justificada,
    coalesce(ju.motivo, case when v.persona_id is not null then 'vacaciones' end) as motivo
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
    select 1 as es from feriados f where f.fecha = tb.fecha limit 1
  ) fer on true
  where tb.trabaja
    and presente.persona_id is null                       -- no marcó = ausente
    and not (fer.es is not null and not tb.hay_turno)     -- feriado sin turno explícito: no cuenta
  order by tb.fecha desc, tb.nombre;
$$;

grant execute on function fn_faltas(date, date) to authenticated;

-- ── Verificación (¡mírala bien!) ─────────────────────────────────────────────
-- Faltas de los últimos 30 días, por persona. Revisa que NO haya falsos
-- positivos: si alguien que claramente trabaja normal aparece con muchas
-- "injustificadas", algo está mal y hay que ajustar ANTES de conectar la UI.
select nombre, sede,
       count(*) filter (where not justificada) as injustificadas,
       count(*) filter (where justificada)     as justificadas,
       max(fecha) as ultima_falta
from fn_faltas(current_date - 30, current_date)
group by nombre, sede
order by injustificadas desc nulls last, nombre;

