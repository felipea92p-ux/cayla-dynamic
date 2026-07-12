-- Turnos rotativos día por día (TRU rota el turno cada día; el dato exacto está
-- en las hojas de horario por persona). La tardanza usa, en orden de prioridad:
--   1) el turno del día (turnos)  →  2) el horario del periodo (horarios_asignados)  →  3) nada.
-- Además se descarta como "no medible" cualquier tardanza > 180 min (casi seguro
-- un cambio de turno no registrado, no una llegada tarde real).

create table turnos (
  id uuid primary key default gen_random_uuid(),
  persona_id uuid not null references personas(id),
  fecha date not null,
  hora_entrada time not null,
  hora_salida time,
  origen text not null default 'import',
  unique (persona_id, fecha)
);

create index idx_turnos_persona_fecha on turnos(persona_id, fecha);

alter table turnos enable row level security;

create policy turnos_select_admin_lider on turnos
  for select to authenticated using (fn_es_admin_o_lider());
create policy turnos_select_supervisor on turnos
  for select to authenticated
  using (fn_rol_actual() = 'supervisor_sede' and persona_id in (select id from personas where sede_base_id = fn_sede_actual_persona()));
create policy turnos_select_propia on turnos
  for select to authenticated using (persona_id = fn_persona_actual_id());
create policy turnos_select_terminal on turnos
  for select to authenticated using (persona_id in (select id from personas where sede_base_id = fn_sede_actual_terminal()));

-- ============================================================================
-- fn_recalcular_jornada v3: tardanza contra turno del día si existe, si no contra
-- el horario del periodo. Cap de 180 min. Resto idéntico a la versión anterior.
-- ============================================================================

create or replace function fn_recalcular_jornada(p_persona_id uuid, p_fecha date)
returns void
language plpgsql
as $$
declare
  v_marcaje record;
  v_entrada_ts timestamptz;
  v_salida_final_ts timestamptz;
  v_salida_final_origen origen_marca;
  v_salida_final_revision estado_revision;
  v_ausencia_inicio timestamptz;
  v_total_ausencia interval := interval '0';
  v_abierta_temporal boolean := false;
  v_sede_id uuid;
  v_hora_entrada_prog time;
  v_minutos_tarde int;
  v_horas_trabajadas numeric(6,2);
  v_estado estado_jornada;
  v_hora_entrada_esperada timestamptz;
  v_n_marcajes int;
begin
  select count(*) into v_n_marcajes
  from marcajes
  where persona_id = p_persona_id and (timestamp_marca at time zone 'America/Lima')::date = p_fecha;

  if v_n_marcajes = 0 then
    delete from jornadas where persona_id = p_persona_id and fecha = p_fecha;
    return;
  end if;

  for v_marcaje in
    select * from marcajes
    where persona_id = p_persona_id and (timestamp_marca at time zone 'America/Lima')::date = p_fecha
    order by timestamp_marca asc
  loop
    v_sede_id := coalesce(v_sede_id, v_marcaje.sede_id);
    if v_marcaje.tipo = 'entrada' then
      v_entrada_ts := coalesce(v_entrada_ts, v_marcaje.timestamp_marca);
    elsif v_marcaje.tipo = 'salida_final' then
      v_salida_final_ts := v_marcaje.timestamp_marca;
      v_salida_final_origen := v_marcaje.origen;
      v_salida_final_revision := v_marcaje.estado_revision;
    elsif v_marcaje.tipo::text like 'salida\_%' escape '\' then
      v_ausencia_inicio := v_marcaje.timestamp_marca;
      v_abierta_temporal := true;
    elsif v_marcaje.tipo::text like 'retorno\_%' escape '\' then
      if v_abierta_temporal and v_ausencia_inicio is not null then
        v_total_ausencia := v_total_ausencia + (v_marcaje.timestamp_marca - v_ausencia_inicio);
      end if;
      v_abierta_temporal := false;
      v_ausencia_inicio := null;
    end if;
  end loop;

  -- hora de entrada programada: turno del día tiene prioridad, luego horario del periodo
  select hora_entrada into v_hora_entrada_prog from turnos where persona_id = p_persona_id and fecha = p_fecha;
  if v_hora_entrada_prog is null then
    select hora_entrada into v_hora_entrada_prog
    from horarios_asignados
    where persona_id = p_persona_id and vigente_desde <= p_fecha
      and (vigente_hasta is null or vigente_hasta >= p_fecha)
    order by vigente_desde desc limit 1;
  end if;

  v_minutos_tarde := null;
  if v_entrada_ts is not null and v_hora_entrada_prog is not null then
    v_hora_entrada_esperada := (p_fecha + v_hora_entrada_prog) at time zone 'America/Lima';
    v_minutos_tarde := greatest(0, round(extract(epoch from (v_entrada_ts - v_hora_entrada_esperada)) / 60)::int);
    if v_minutos_tarde > 180 then v_minutos_tarde := null; end if; -- implausible: turno distinto, no medible
  end if;

  v_horas_trabajadas := null;
  if v_entrada_ts is not null and v_salida_final_ts is not null then
    v_horas_trabajadas := round(extract(epoch from ((v_salida_final_ts - v_entrada_ts) - v_total_ausencia)) / 3600.0, 2);
  end if;

  if v_salida_final_ts is not null then
    if v_salida_final_origen = 'auto_cierre' and v_salida_final_revision = 'pendiente_revision' then
      v_estado := 'auto_cerrada_pendiente';
    elsif v_salida_final_origen = 'auto_cierre' and v_salida_final_revision = 'revisada' then
      v_estado := 'revisada';
    else
      v_estado := 'cerrada';
    end if;
  elsif v_abierta_temporal then
    v_estado := 'en_pausa';
  else
    v_estado := 'abierta';
  end if;

  insert into jornadas (
    persona_id, fecha, sede_id, entrada_ts, salida_final_ts,
    minutos_tarde, horas_trabajadas, estado, tiene_salida_no_retornada, updated_at
  ) values (
    p_persona_id, p_fecha, v_sede_id, v_entrada_ts, v_salida_final_ts,
    v_minutos_tarde, v_horas_trabajadas, v_estado, v_abierta_temporal, now()
  )
  on conflict (persona_id, fecha) do update set
    sede_id = excluded.sede_id,
    entrada_ts = excluded.entrada_ts,
    salida_final_ts = excluded.salida_final_ts,
    minutos_tarde = excluded.minutos_tarde,
    horas_trabajadas = excluded.horas_trabajadas,
    estado = excluded.estado,
    tiene_salida_no_retornada = excluded.tiene_salida_no_retornada,
    updated_at = now();
end;
$$;
