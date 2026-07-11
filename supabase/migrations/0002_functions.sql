-- CAYLA Dynamic — lógica de negocio: máquina de estados de marcaje + jornadas derivadas.
-- Debe reflejar exactamente packages/shared/src/attendance-state-machine.ts.

-- ============================================================================
-- fn_siguiente_tipo_esperado: replica determinarSiguienteAccion() del lado servidor.
-- Devuelve el único tipo válido, o NULL cuando la persona debe elegir entre
-- varios tipos de salida (salida_final/almuerzo/personal/tramite/medico/otro).
-- ============================================================================

create or replace function fn_siguiente_tipo_esperado(p_persona_id uuid, p_fecha date)
returns tipo_marca
language plpgsql
stable
as $$
declare
  v_ultimo record;
  v_tiene_entrada boolean;
  v_tiene_salida_final boolean;
  v_pares jsonb := '{
    "salida_almuerzo": "retorno_almuerzo",
    "salida_personal": "retorno_personal",
    "salida_tramite": "retorno_tramite",
    "salida_medico": "retorno_medico",
    "salida_otro": "retorno_otro"
  }'::jsonb;
begin
  select exists(
    select 1 from marcajes
    where persona_id = p_persona_id
      and tipo = 'entrada'
      and (timestamp_marca at time zone 'America/Lima')::date = p_fecha
  ) into v_tiene_entrada;

  if not v_tiene_entrada then
    return 'entrada';
  end if;

  select exists(
    select 1 from marcajes
    where persona_id = p_persona_id
      and tipo = 'salida_final'
      and (timestamp_marca at time zone 'America/Lima')::date = p_fecha
  ) into v_tiene_salida_final;

  if v_tiene_salida_final then
    return null; -- jornada cerrada, ninguna acción válida
  end if;

  select tipo, timestamp_marca into v_ultimo
  from marcajes
  where persona_id = p_persona_id
    and (timestamp_marca at time zone 'America/Lima')::date = p_fecha
  order by timestamp_marca desc
  limit 1;

  if v_pares ? v_ultimo.tipo::text then
    return (v_pares ->> v_ultimo.tipo::text)::tipo_marca;
  end if;

  return null; -- debe elegir tipo de salida — ambigüedad legítima, no se resuelve aquí
end;
$$;

-- ============================================================================
-- fn_recalcular_jornada: recompone jornadas a partir del log crudo de marcajes
-- de un persona/día. Se llama desde el trigger de marcajes tras cada insert/update.
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
  v_horario horarios_asignados%rowtype;
  v_minutos_tarde int;
  v_horas_trabajadas numeric(6,2);
  v_estado estado_jornada;
  v_hora_entrada_esperada timestamptz;
begin
  for v_marcaje in
    select * from marcajes
    where persona_id = p_persona_id
      and (timestamp_marca at time zone 'America/Lima')::date = p_fecha
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

  -- horario vigente para esa fecha, para calcular minutos_tarde
  select * into v_horario
  from horarios_asignados
  where persona_id = p_persona_id
    and vigente_desde <= p_fecha
    and (vigente_hasta is null or vigente_hasta >= p_fecha)
  order by vigente_desde desc
  limit 1;

  v_minutos_tarde := null;
  if v_entrada_ts is not null and found then
    v_hora_entrada_esperada := (p_fecha + v_horario.hora_entrada) at time zone 'America/Lima';
    v_minutos_tarde := greatest(0, round(extract(epoch from (v_entrada_ts - v_hora_entrada_esperada)) / 60)::int);
  end if;

  v_horas_trabajadas := null;
  if v_entrada_ts is not null and v_salida_final_ts is not null then
    v_horas_trabajadas := round(
      extract(epoch from ((v_salida_final_ts - v_entrada_ts) - v_total_ausencia)) / 3600.0,
      2
    );
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

create or replace function fn_trg_marcajes_recalcular_jornada()
returns trigger
language plpgsql
as $$
begin
  perform fn_recalcular_jornada(new.persona_id, (new.timestamp_marca at time zone 'America/Lima')::date);
  return new;
end;
$$;

create trigger trg_marcajes_recalcular_jornada
  after insert or update on marcajes
  for each row execute function fn_trg_marcajes_recalcular_jornada();

-- ============================================================================
-- fn_registrar_marcaje: ÚNICO camino de escritura hacia marcajes. Nunca insertar
-- directo desde el cliente. security definer para poder resolver terminales/personas
-- sin exponer esas tablas en escritura vía RLS directa.
-- ============================================================================

create or replace function fn_registrar_marcaje(
  p_persona_id uuid,
  p_tipo tipo_marca,
  p_timestamp_cliente timestamptz,
  p_client_uuid uuid,
  p_origen origen_marca default 'terminal',
  p_terminal_id uuid default null,
  p_sede_id uuid default null,
  p_motivo_otro text default null
)
returns marcajes
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sede_id uuid;
  v_marcaje marcajes;
  v_existente marcajes;
  v_fecha date;
  v_esperado tipo_marca;
  v_caller_rol rol_usuario;
  v_terminal_auth uuid;
begin
  -- Idempotencia: reintentos offline con el mismo client_uuid no duplican.
  select * into v_existente from marcajes where client_uuid = p_client_uuid;
  if found then
    return v_existente;
  end if;

  if p_origen = 'terminal' then
    if p_terminal_id is null then
      raise exception 'p_terminal_id es obligatorio cuando origen = terminal';
    end if;
    select sede_id, auth_user_id into v_sede_id, v_terminal_auth
    from terminales where id = p_terminal_id and activo;
    if v_sede_id is null then
      raise exception 'terminal % no encontrado o inactivo', p_terminal_id;
    end if;
    if auth.uid() is not null and v_terminal_auth is not null and auth.uid() <> v_terminal_auth then
      raise exception 'el terminal autenticado no coincide con p_terminal_id';
    end if;
  else
    if p_sede_id is null then
      raise exception 'p_sede_id es obligatorio cuando origen != terminal';
    end if;
    select rol into v_caller_rol from personas where auth_user_id = auth.uid();
    if v_caller_rol is null or v_caller_rol not in ('admin', 'lider_do', 'supervisor_sede') then
      raise exception 'no autorizado para registrar marcajes con origen %', p_origen;
    end if;
    if v_caller_rol = 'supervisor_sede' then
      if not exists (
        select 1 from personas
        where auth_user_id = auth.uid() and sede_base_id = p_sede_id
      ) then
        raise exception 'un supervisor_sede solo puede corregir marcajes de su propia sede';
      end if;
    end if;
    v_sede_id := p_sede_id;
  end if;

  if p_tipo = 'salida_otro' and (p_motivo_otro is null or length(trim(p_motivo_otro)) < 3) then
    raise exception 'motivo_otro es obligatorio para salida_otro';
  end if;

  v_fecha := (p_timestamp_cliente at time zone 'America/Lima')::date;

  if p_origen = 'terminal' then
    v_esperado := fn_siguiente_tipo_esperado(p_persona_id, v_fecha);
    if v_esperado is not null and v_esperado <> p_tipo then
      raise exception 'tipo % no válido en el estado actual (se esperaba %)', p_tipo, v_esperado;
    end if;
    if v_esperado is null and p_tipo not in (
      'salida_final', 'salida_almuerzo', 'salida_personal', 'salida_tramite', 'salida_medico', 'salida_otro'
    ) then
      raise exception 'tipo % no válido: la jornada ya está cerrada o requiere elegir un tipo de salida', p_tipo;
    end if;
  end if;

  -- Reconciliación: una salida_final real que llega después de un auto-cierre
  -- sintético del mismo día reemplaza el registro sintético, no lo duplica.
  if p_tipo = 'salida_final' then
    select * into v_existente
    from marcajes
    where persona_id = p_persona_id
      and tipo = 'salida_final'
      and origen = 'auto_cierre'
      and (timestamp_marca at time zone 'America/Lima')::date = v_fecha;

    if found then
      update marcajes set
        timestamp_marca = p_timestamp_cliente,
        origen = p_origen,
        estado_revision = 'normal',
        client_uuid = p_client_uuid,
        terminal_id = p_terminal_id,
        server_received_at = now()
      where id = v_existente.id
      returning * into v_marcaje;

      return v_marcaje;
    end if;
  end if;

  insert into marcajes (
    client_uuid, persona_id, sede_id, terminal_id, tipo, motivo_otro, timestamp_marca, origen
  ) values (
    p_client_uuid, p_persona_id, v_sede_id, p_terminal_id, p_tipo, p_motivo_otro, p_timestamp_cliente, p_origen
  )
  returning * into v_marcaje;

  return v_marcaje;
end;
$$;

grant execute on function fn_registrar_marcaje to authenticated;
grant execute on function fn_siguiente_tipo_esperado to authenticated;
