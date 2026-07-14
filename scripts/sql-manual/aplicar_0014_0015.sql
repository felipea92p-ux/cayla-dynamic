-- ============================================================
-- Dynamic — aplicar turnos+cobertura (0014) y horario base (0015)
-- Pegar TODO esto en Supabase → SQL Editor → Run. Es idempotente.
-- ============================================================

-- ============================================================================
-- Planificador de turnos + cobertura por sede
-- ----------------------------------------------------------------------------
-- Hasta ahora los turnos por día (tabla `turnos`) solo se llenaban por importación
-- desde la hoja. Esto agrega:
--   1) Editar turnos y días de descanso por persona/día desde el panel.
--   2) Meta de cobertura por sede y día de la semana (cuántas personas se necesitan),
--      para ver si una sede está cubierta / sobran / faltan.
-- Los turnos escritos desde el panel recalculan la jornada de ese día (tardanza).
-- Permiso de escritura: reutiliza fn_verificar_corrector (admin/lider = cualquiera;
-- encargada = su sede, NUNCA su propia hora — la hora de entrada del turno es contra
-- la que se mide su tardanza, así que dejarla editarse a sí misma sería un hueco).
-- ============================================================================

-- --- turnos: soportar día de descanso -------------------------------------
alter table turnos add column if not exists es_descanso boolean not null default false;
alter table turnos alter column hora_entrada drop not null;
alter table turnos drop constraint if exists turnos_entrada_o_descanso;
alter table turnos add constraint turnos_entrada_o_descanso
  check (es_descanso or hora_entrada is not null);

-- --- meta de cobertura por sede × día de semana ---------------------------
-- dia_semana: 0=domingo … 6=sábado (igual que horarios_asignados.dias_laborables)
create table if not exists metas_cobertura (
  sede_id uuid not null references sedes(id),
  dia_semana int not null check (dia_semana between 0 and 6),
  meta int not null default 0 check (meta >= 0),
  updated_at timestamptz not null default now(),
  primary key (sede_id, dia_semana)
);

alter table metas_cobertura enable row level security;

drop policy if exists metas_select_admin on metas_cobertura;
create policy metas_select_admin on metas_cobertura
  for select to authenticated using (fn_es_admin_o_lider());

drop policy if exists metas_select_supervisor on metas_cobertura;
create policy metas_select_supervisor on metas_cobertura
  for select to authenticated
  using (fn_rol_actual() = 'supervisor_sede' and sede_id = fn_sede_actual_persona());

-- --- funciones de escritura -----------------------------------------------

-- Asignar / cambiar el turno de una persona en un día concreto.
create or replace function fn_set_turno(
  p_persona_id uuid,
  p_fecha date,
  p_hora_entrada time,
  p_hora_salida time
)
returns void
language plpgsql security definer set search_path = public
as $$
declare v_editor uuid;
begin
  v_editor := fn_verificar_corrector(p_persona_id); -- valida permiso o lanza excepción
  if p_hora_entrada is null then
    raise exception 'La hora de entrada del turno es obligatoria.';
  end if;
  insert into turnos (persona_id, fecha, hora_entrada, hora_salida, es_descanso, origen)
  values (p_persona_id, p_fecha, p_hora_entrada, p_hora_salida, false, 'panel')
  on conflict (persona_id, fecha) do update set
    hora_entrada = excluded.hora_entrada,
    hora_salida = excluded.hora_salida,
    es_descanso = false,
    origen = 'panel';
  perform fn_recalcular_jornada(p_persona_id, p_fecha);
end;
$$;

-- Marcar un día como descanso (libre) para una persona.
create or replace function fn_set_descanso(p_persona_id uuid, p_fecha date)
returns void
language plpgsql security definer set search_path = public
as $$
declare v_editor uuid;
begin
  v_editor := fn_verificar_corrector(p_persona_id);
  insert into turnos (persona_id, fecha, hora_entrada, hora_salida, es_descanso, origen)
  values (p_persona_id, p_fecha, null, null, true, 'panel')
  on conflict (persona_id, fecha) do update set
    hora_entrada = null,
    hora_salida = null,
    es_descanso = true,
    origen = 'panel';
  perform fn_recalcular_jornada(p_persona_id, p_fecha);
end;
$$;

-- Quitar el turno de un día (vuelve al horario del periodo por defecto).
create or replace function fn_quitar_turno(p_persona_id uuid, p_fecha date)
returns void
language plpgsql security definer set search_path = public
as $$
declare v_editor uuid;
begin
  v_editor := fn_verificar_corrector(p_persona_id);
  delete from turnos where persona_id = p_persona_id and fecha = p_fecha;
  perform fn_recalcular_jornada(p_persona_id, p_fecha);
end;
$$;

-- Definir la meta de cobertura de una sede para un día de la semana. Solo admin/lider.
create or replace function fn_set_meta_cobertura(p_sede_id uuid, p_dia_semana int, p_meta int)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if fn_rol_actual() not in ('admin', 'lider_do') then
    raise exception 'Solo un administrador puede definir la meta de cobertura.';
  end if;
  if p_dia_semana < 0 or p_dia_semana > 6 then raise exception 'Día de la semana inválido.'; end if;
  if p_meta < 0 then raise exception 'La meta no puede ser negativa.'; end if;
  insert into metas_cobertura (sede_id, dia_semana, meta, updated_at)
  values (p_sede_id, p_dia_semana, p_meta, now())
  on conflict (sede_id, dia_semana) do update set meta = excluded.meta, updated_at = now();
end;
$$;

grant execute on function fn_set_turno(uuid, date, time, time) to authenticated;
grant execute on function fn_set_descanso(uuid, date) to authenticated;
grant execute on function fn_quitar_turno(uuid, date) to authenticated;
grant execute on function fn_set_meta_cobertura(uuid, int, int) to authenticated;

-- ============================================================================
-- fn_recalcular_jornada v4: consciente del descanso.
-- Antes decidía el fallback al horario del periodo con `if hora_entrada is null`,
-- lo que NO distinguía "no hay turno" de "hay turno pero es descanso" (hora_entrada
-- NULL). Resultado: un día de descanso donde la persona igual marcaba calculaba una
-- tardanza espuria contra el horario del periodo. Ahora: si EXISTE fila de turno se
-- respeta (descanso => no se mide tardanza); solo si NO existe fila se cae al horario.
-- El resto es idéntico a la v3 (0013).
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
  v_es_descanso boolean := false;
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

  -- hora de entrada programada: el turno del día manda. Si el turno es descanso, no se
  -- mide tardanza. Solo cuando NO hay fila de turno se cae al horario del periodo.
  select hora_entrada, es_descanso into v_hora_entrada_prog, v_es_descanso
  from turnos where persona_id = p_persona_id and fecha = p_fecha;
  if not found then
    select hora_entrada into v_hora_entrada_prog
    from horarios_asignados
    where persona_id = p_persona_id and vigente_desde <= p_fecha
      and (vigente_hasta is null or vigente_hasta >= p_fecha)
    order by vigente_desde desc limit 1;
  elsif v_es_descanso then
    v_hora_entrada_prog := null; -- descanso: no hay hora esperada, no se calcula tardanza
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


-- ============================================================================
-- Horario base ampliado: día(s) de descanso + refrigerio editables desde el panel
-- ----------------------------------------------------------------------------
-- Antes fn_set_horario solo fijaba entrada/salida. Ahora también fija:
--   - dias_laborables (qué días trabaja; los que NO están = día de descanso fijo)
--   - refrigerio (almuerzo min/max)
-- Esto deja registrar "entra 8:00, descansa domingo" por persona, y eso alimenta
-- la grilla de turnos (celdas por defecto) y la cobertura por día.
-- dias_laborables: 0=domingo … 6=sábado.
-- ============================================================================

drop function if exists fn_set_horario(uuid, time, time, date, int, int);

create or replace function fn_set_horario(
  p_persona_id uuid,
  p_hora_entrada time,
  p_hora_salida time,
  p_vigente_desde date,
  p_almuerzo_min int default 45,
  p_almuerzo_max int default 75,
  p_dias_laborables int[] default '{1,2,3,4,5,6}'
)
returns void
language plpgsql security definer set search_path = public
as $$
declare v_editor uuid; r record;
begin
  v_editor := fn_verificar_corrector(p_persona_id); -- valida permiso o lanza excepción

  if p_hora_entrada is null or p_hora_salida is null then
    raise exception 'Hora de entrada y salida son obligatorias.';
  end if;
  if p_dias_laborables is null or array_length(p_dias_laborables, 1) is null then
    raise exception 'Debe trabajar al menos un día a la semana.';
  end if;
  if exists (select 1 from unnest(p_dias_laborables) d where d < 0 or d > 6) then
    raise exception 'Día de la semana inválido (usa 0=domingo … 6=sábado).';
  end if;
  if p_almuerzo_min > p_almuerzo_max then
    raise exception 'El refrigerio mínimo no puede ser mayor que el máximo.';
  end if;

  -- quitar cualquier tramo que empiece en o después de la nueva fecha (se reemplaza)
  delete from horarios_asignados
  where persona_id = p_persona_id and vigente_desde >= p_vigente_desde;

  -- cerrar el tramo vigente anterior (el que quedó abierto y empieza antes)
  update horarios_asignados
  set vigente_hasta = p_vigente_desde - 1
  where persona_id = p_persona_id and vigente_hasta is null and vigente_desde < p_vigente_desde;

  -- insertar el nuevo tramo vigente
  insert into horarios_asignados (
    persona_id, vigente_desde, vigente_hasta, hora_entrada, hora_salida,
    almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables
  )
  values (
    p_persona_id, p_vigente_desde, null, p_hora_entrada, p_hora_salida,
    p_almuerzo_min, p_almuerzo_max, p_dias_laborables
  );

  -- recalcular jornadas desde la fecha de vigencia (tardanzas nuevas)
  for r in select fecha from jornadas where persona_id = p_persona_id and fecha >= p_vigente_desde loop
    perform fn_recalcular_jornada(p_persona_id, r.fecha);
  end loop;
end;
$$;

grant execute on function fn_set_horario(uuid, time, time, date, int, int, int[]) to authenticated;
