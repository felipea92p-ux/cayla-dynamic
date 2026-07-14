-- ============================================================
-- Dynamic — horario base POR DÍA + refrigerio por día (0016)
-- Pegar TODO en Supabase → SQL Editor → Run. Es idempotente.
-- (0014 y 0015 ya están aplicadas; esto es lo único nuevo.)
-- ============================================================

-- ============================================================================
-- Horario base POR DÍA de la semana
-- ----------------------------------------------------------------------------
-- Antes horarios_asignados guardaba UNA sola hora de entrada/salida para todos los
-- días laborables. Ahora guarda `horario_por_dia` (jsonb):
--     {"1":{"e":"08:00","s":"16:00"}, "2":{"e":"14:00","s":"21:00"}, ...}
-- La clave es el día de la semana 0=domingo … 6=sábado; un día AUSENTE = descanso.
-- Se conservan hora_entrada/hora_salida/dias_laborables como RESUMEN (compat con
-- reportes viejos), pero la fuente de verdad de la tardanza pasa a ser horario_por_dia.
-- Versionado igual que antes (vigente_desde/vigente_hasta): cambiar el horario cierra
-- el tramo anterior y abre uno nuevo, sin tocar tardanzas pasadas.
-- ============================================================================

alter table horarios_asignados add column if not exists horario_por_dia jsonb;

-- Backfill: convertir cada horario existente (una hora + dias_laborables) al formato por día.
update horarios_asignados
set horario_por_dia = (
  select jsonb_object_agg(
    d::text,
    jsonb_build_object('e', to_char(hora_entrada, 'HH24:MI'), 's', to_char(hora_salida, 'HH24:MI'))
  )
  from unnest(dias_laborables) d
)
where horario_por_dia is null
  and dias_laborables is not null
  and array_length(dias_laborables, 1) is not null;

-- ---------------------------------------------------------------------------
-- fn_set_horario_semanal: guarda el horario base por día (jsonb) versionado.
-- p_horario = {"1":{"e":"08:00","s":"16:00","r":60}, ...} donde r = minutos de
-- refrigerio de ese día (0 = sin refrigerio). Reutiliza fn_verificar_corrector
-- (anti-fraude: nadie fija su propio horario). Mantiene las columnas resumen
-- válidas (almuerzo_min/max = min/max del refrigerio por día).
-- ---------------------------------------------------------------------------
create or replace function fn_set_horario_semanal(
  p_persona_id uuid,
  p_vigente_desde date,
  p_horario jsonb
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_editor uuid; r record;
  k text; v jsonb;
  v_dias int[]; v_min_entrada time; v_max_salida time;
  v_refri_min int; v_refri_max int;
begin
  v_editor := fn_verificar_corrector(p_persona_id); -- valida permiso o lanza excepción

  if p_horario is null or jsonb_typeof(p_horario) <> 'object'
     or (select count(*) from jsonb_object_keys(p_horario)) = 0 then
    raise exception 'Debe trabajar al menos un día a la semana.';
  end if;
  -- validar claves (0-6) y que cada día tenga hora de entrada
  for k, v in select * from jsonb_each(p_horario) loop
    if k !~ '^[0-6]$' then raise exception 'Día de la semana inválido: %', k; end if;
    if coalesce(v->>'e', '') = '' then raise exception 'Falta la hora de entrada del día %.', k; end if;
  end loop;

  -- resumen para columnas legacy: min entrada / max salida / días / refrigerio (min-max por día).
  -- nullif protege el casteo si 's' llegara vacío (cae a la hora de entrada).
  select array_agg((t.k)::int order by (t.k)::int),
         min((t.v->>'e')::time),
         max(coalesce(nullif(t.v->>'s', '')::time, (t.v->>'e')::time)),
         min(coalesce((t.v->>'r')::int, 0)),
         max(coalesce((t.v->>'r')::int, 0))
    into v_dias, v_min_entrada, v_max_salida, v_refri_min, v_refri_max
  from jsonb_each(p_horario) as t(k, v);

  -- reemplazar tramos que empiezan en/después de la fecha, cerrar el anterior
  delete from horarios_asignados where persona_id = p_persona_id and vigente_desde >= p_vigente_desde;
  update horarios_asignados set vigente_hasta = p_vigente_desde - 1
    where persona_id = p_persona_id and vigente_hasta is null and vigente_desde < p_vigente_desde;

  insert into horarios_asignados (
    persona_id, vigente_desde, vigente_hasta, hora_entrada, hora_salida,
    almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horario_por_dia
  )
  values (
    p_persona_id, p_vigente_desde, null, v_min_entrada, coalesce(v_max_salida, v_min_entrada),
    v_refri_min, v_refri_max, v_dias, p_horario
  );

  -- recalcular tardanzas desde la fecha de vigencia
  for r in select fecha from jornadas where persona_id = p_persona_id and fecha >= p_vigente_desde loop
    perform fn_recalcular_jornada(p_persona_id, r.fecha);
  end loop;
end;
$$;

grant execute on function fn_set_horario_semanal(uuid, date, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- fn_recalcular_jornada v5: la hora esperada sale del horario POR DÍA.
-- Prioridad: turno del día (descanso => no se mide) → horario base del día de la
-- semana (jsonb; día ausente => descanso, no se mide) → hora única legacy → nada.
-- ---------------------------------------------------------------------------
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
  v_hpd jsonb;
  v_hora_legacy time;
  v_dow text;
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

  -- hora de entrada programada
  v_dow := extract(dow from p_fecha)::int::text; -- 0=domingo … 6=sábado
  select hora_entrada, es_descanso into v_hora_entrada_prog, v_es_descanso
  from turnos where persona_id = p_persona_id and fecha = p_fecha;
  if not found then
    select horario_por_dia, hora_entrada into v_hpd, v_hora_legacy
    from horarios_asignados
    where persona_id = p_persona_id and vigente_desde <= p_fecha
      and (vigente_hasta is null or vigente_hasta >= p_fecha)
    order by vigente_desde desc limit 1;
    if found then
      if v_hpd is not null then
        v_hora_entrada_prog := (v_hpd -> v_dow ->> 'e')::time; -- null si ese día es descanso
      else
        v_hora_entrada_prog := v_hora_legacy; -- tramo legacy sin jsonb
      end if;
    else
      v_hora_entrada_prog := null;
    end if;
  elsif v_es_descanso then
    v_hora_entrada_prog := null; -- descanso del turno: no se mide tardanza
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
