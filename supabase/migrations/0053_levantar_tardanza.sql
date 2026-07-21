-- ============================================================================
-- 0053_levantar_tardanza.sql — Levantar (justificar) una tardanza por fuerza mayor
-- ============================================================================
-- Felipe: poder "levantar" una tardanza SIN cambiar la hora real. La persona sí
-- llegó tarde (consta su hora), pero por fuerza mayor se le perdona: deja de
-- contar en el patrón disciplinario Y cuenta como puntual para el bono. Es la
-- hermana de justificar una falta: no borra el hecho, registra el motivo.
--
-- Decisiones (2026-07-21): perdón total (patrón + bono) · se levanta en
-- Correcciones · en el registro la tardanza queda TACHADA con su motivo (la hora
-- y los minutos reales NO se tocan; solo dejan de contar).

create table if not exists tardanzas_justificadas (
  id           uuid primary key default gen_random_uuid(),
  persona_id   uuid not null references personas(id),
  fecha        date not null,
  motivo       text not null check (motivo in ('fuerza_mayor','salud','transporte','otro')),
  observacion  text,
  creado_por   uuid not null references personas(id),
  creado_at    timestamptz not null default now(),
  unique (persona_id, fecha)
);
create index if not exists idx_tardanza_justif on tardanzas_justificadas (persona_id, fecha);

alter table tardanzas_justificadas enable row level security;
drop policy if exists tardj_select_admin_lider on tardanzas_justificadas;
create policy tardj_select_admin_lider on tardanzas_justificadas
  for select to authenticated using (fn_es_admin_o_lider());
drop policy if exists tardj_select_supervisor on tardanzas_justificadas;
create policy tardj_select_supervisor on tardanzas_justificadas
  for select to authenticated using (
    fn_rol_actual() = 'supervisor_sede'
    and persona_id in (select id from personas where sede_base_id = fn_sede_actual_persona()));
drop policy if exists tardj_select_propia on tardanzas_justificadas;
create policy tardj_select_propia on tardanzas_justificadas
  for select to authenticated using (persona_id = fn_persona_actual_id());

create or replace function fn_levantar_tardanza(
  p_persona_id uuid, p_fecha date, p_motivo text, p_observacion text default null)
returns void language plpgsql security definer set search_path = public as $L$
declare v_editor uuid;
begin
  v_editor := fn_verificar_corrector(p_persona_id);
  if p_motivo is null or p_motivo not in ('fuerza_mayor','salud','transporte','otro') then
    raise exception 'Motivo inválido.';
  end if;
  if p_motivo = 'otro' and (p_observacion is null or length(trim(p_observacion)) < 3) then
    raise exception 'Para el motivo "otro" la observación es obligatoria.';
  end if;
  insert into tardanzas_justificadas (persona_id, fecha, motivo, observacion, creado_por)
  values (p_persona_id, p_fecha, p_motivo, nullif(trim(coalesce(p_observacion,'')),''), v_editor)
  on conflict (persona_id, fecha)
  do update set motivo = excluded.motivo, observacion = excluded.observacion,
                creado_por = excluded.creado_por, creado_at = now();
end;
$L$;

create or replace function fn_quitar_levantamiento(p_persona_id uuid, p_fecha date)
returns void language plpgsql security definer set search_path = public as $L$
begin
  perform fn_verificar_corrector(p_persona_id);
  delete from tardanzas_justificadas where persona_id = p_persona_id and fecha = p_fecha;
end;
$L$;

grant execute on function fn_levantar_tardanza(uuid, date, text, text) to authenticated;
grant execute on function fn_quitar_levantamiento(uuid, date) to authenticated;

-- Parche al bono: una tardanza levantada cuenta como 0 (puntual). Solo cambia el
-- comportamiento de días con levantamiento; sin ninguno, es idéntico a antes.
create or replace function fn_calcular_bono_puntualidad(p_periodo_id uuid)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_estado text; v_ini date; v_fin date; v_dias_periodo int;
  v_cfg jsonb; v_monto numeric; v_asistencia_min numeric;
  v_poblacion int; v_puntuales int;
  v_personas jsonb;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede calcular el bono de puntualidad.';
  end if;

  select estado, fecha_ini, fecha_fin into v_estado, v_ini, v_fin
  from periodos_planilla where id = p_periodo_id;
  if not found then raise exception 'Periodo inexistente.'; end if;
  if v_estado = 'pagado' then
    raise exception 'Este periodo ya está PAGADO: reábrelo para modificarlo.';
  end if;
  -- Mientras el periodo sigue corriendo, el 51% se mide contra los días que
  -- YA PASARON, no contra el periodo completo — si no, nadie podría llegar al
  -- umbral hasta el último día, aunque tenga asistencia perfecta hasta hoy.
  -- ¡OJO zona horaria! current_date usa UTC (el servidor de Supabase), NO Lima
  -- (UTC-5) — después de las 7pm hora Lima, UTC ya cree que es el día
  -- siguiente y cuenta un día de más. Se usa la fecha real de Lima.
  v_dias_periodo := least(v_fin, (now() at time zone 'America/Lima')::date) - v_ini + 1;

  select valor into v_cfg from configuracion where clave = 'bono_puntualidad';
  if v_cfg is null then
    v_cfg := '{"monto": 60, "asistencia_minima": 0.51}'::jsonb;
  end if;
  v_monto := coalesce((v_cfg->>'monto')::numeric, 0);
  v_asistencia_min := coalesce((v_cfg->>'asistencia_minima')::numeric, 0.51);

  -- Un día "cuenta" solo si minutos_tarde no es NULL — fn_recalcular_jornada ya
  -- lo deja NULL cuando no hubo hora esperada con qué comparar (sin turno/
  -- horario vigente para esa fecha, o día de descanso trabajado). Los días sin
  -- medir se ignoran por completo: no entran en dias_medidos ni en tarde_total.
  with dias_trabajo as (
    -- Tardanza LEVANTADA (fuerza mayor) cuenta como 0 (puntual) para el bono.
    select j.persona_id,
           case when exists (select 1 from tardanzas_justificadas tj
                             where tj.persona_id = j.persona_id and tj.fecha = j.fecha)
                then 0 else j.minutos_tarde end as minutos_tarde
    from jornadas j
    where j.fecha between v_ini and v_fin and j.horas_trabajadas > 0
  ),
  por_persona as (
    select persona_id,
           count(*) filter (where minutos_tarde is not null) as dias_medidos,
           sum(minutos_tarde) filter (where minutos_tarde is not null) as tarde_total
    from dias_trabajo
    group by persona_id
  )
  select count(*), count(*) filter (
    where coalesce(tarde_total, 0) = 0
      and dias_medidos::numeric / v_dias_periodo >= v_asistencia_min
  )
  into v_poblacion, v_puntuales
  from por_persona;

  -- recalculable sin duplicar: borra solo las filas AUTO-generadas de este periodo
  delete from movimientos_planilla
  where periodo_id = p_periodo_id
    and concepto = 'Bono puntualidad'
    and creado_por is null;

  if v_monto > 0 and v_puntuales > 0 then
    with dias_trabajo as (
      -- Tardanza LEVANTADA (fuerza mayor) cuenta como 0 (puntual) para el bono.
      select j.persona_id,
             case when exists (select 1 from tardanzas_justificadas tj
                               where tj.persona_id = j.persona_id and tj.fecha = j.fecha)
                  then 0 else j.minutos_tarde end as minutos_tarde
      from jornadas j
      where j.fecha between v_ini and v_fin and j.horas_trabajadas > 0
    ),
    por_persona as (
      select persona_id,
             count(*) filter (where minutos_tarde is not null) as dias_medidos,
             sum(minutos_tarde) filter (where minutos_tarde is not null) as tarde_total
      from dias_trabajo
      group by persona_id
    )
    insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto, creado_por)
    select p_periodo_id, pp.persona_id, 'bono', 'Bono puntualidad', v_monto, null
    from por_persona pp
    where coalesce(pp.tarde_total, 0) = 0
      and pp.dias_medidos::numeric / v_dias_periodo >= v_asistencia_min;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'persona_id', pe.id, 'nombre', pe.nombres || ' ' || pe.apellidos
         ) order by pe.nombres), '[]'::jsonb)
    into v_personas
  from movimientos_planilla m
  join personas pe on pe.id = m.persona_id
  where m.periodo_id = p_periodo_id and m.concepto = 'Bono puntualidad' and m.creado_por is null;

  return jsonb_build_object(
    'poblacion', v_poblacion,
    'puntuales', v_puntuales,
    'monto_por_persona', v_monto,
    'personas', v_personas
  );
end;
$$;
