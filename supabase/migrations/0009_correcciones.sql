-- Corrección de marcajes desde el panel — SOLO administradores (Carlos y Felipe).
-- Toda corrección queda auditada en correcciones_auditoria (quién, qué, cuándo, por qué).
-- El motivo es obligatorio. Los supervisores NO pueden corregir horas.

-- ============================================================================
-- fn_recalcular_jornada v2: si ya no quedan marcajes ese día, borra la jornada
-- (caso: el admin eliminó el último marcaje del día). Resto idéntico.
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
  v_n_marcajes int;
begin
  select count(*) into v_n_marcajes
  from marcajes
  where persona_id = p_persona_id
    and (timestamp_marca at time zone 'America/Lima')::date = p_fecha;

  if v_n_marcajes = 0 then
    delete from jornadas where persona_id = p_persona_id and fecha = p_fecha;
    return;
  end if;

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
      extract(epoch from ((v_salida_final_ts - v_entrada_ts) - v_total_ausencia)) / 3600.0, 2);
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

-- Recalcular también al BORRAR un marcaje (el trigger original solo cubría insert/update).
create or replace function fn_trg_marcajes_delete_recalcular()
returns trigger language plpgsql as $$
begin
  perform fn_recalcular_jornada(old.persona_id, (old.timestamp_marca at time zone 'America/Lima')::date);
  return old;
end;
$$;

drop trigger if exists trg_marcajes_delete_recalcular on marcajes;
create trigger trg_marcajes_delete_recalcular
  after delete on marcajes
  for each row execute function fn_trg_marcajes_delete_recalcular();

-- ============================================================================
-- Solo admins pueden editar marcajes: quitar los UPDATE directos por RLS.
-- Toda corrección pasa por las funciones auditadas de abajo.
-- ============================================================================

drop policy if exists marcajes_update_admin_lider on marcajes;
drop policy if exists marcajes_update_supervisor on marcajes;

-- Al eliminar un marcaje, sus filas de auditoría deben CONSERVARSE (con sus
-- detalles en texto); solo se desvincula el id. Antes la FK bloqueaba el borrado
-- de cualquier marcaje que hubiera sido corregido alguna vez.
alter table correcciones_auditoria drop constraint if exists correcciones_auditoria_marcaje_id_fkey;
alter table correcciones_auditoria add constraint correcciones_auditoria_marcaje_id_fkey
  foreign key (marcaje_id) references marcajes(id) on delete set null;

-- La cola de espejo a Sheets sí puede descartarse si el marcaje se borra.
alter table google_sheets_sync_queue drop constraint if exists google_sheets_sync_queue_marcaje_id_fkey;
alter table google_sheets_sync_queue add constraint google_sheets_sync_queue_marcaje_id_fkey
  foreign key (marcaje_id) references marcajes(id) on delete cascade;

-- ============================================================================
-- Helper: exige rol admin, o lanza excepción
-- ============================================================================

create or replace function fn_exigir_admin()
returns uuid
language plpgsql stable security definer set search_path = public
as $$
declare v_id uuid; v_rol rol_usuario;
begin
  select id, rol into v_id, v_rol from personas where auth_user_id = auth.uid();
  if v_rol is null or v_rol <> 'admin' then
    raise exception 'Solo un administrador puede corregir marcajes.';
  end if;
  return v_id;
end;
$$;

-- ============================================================================
-- fn_corregir_marcaje: cambia la hora de un marcaje existente + auditoría
-- ============================================================================

create or replace function fn_corregir_marcaje(p_marcaje_id uuid, p_nuevo_ts timestamptz, p_motivo text)
returns marcajes
language plpgsql security definer set search_path = public
as $$
declare
  v_admin uuid := fn_exigir_admin();
  v_ant marcajes;
  v_nuevo marcajes;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la corrección es obligatorio.';
  end if;

  select * into v_ant from marcajes where id = p_marcaje_id;
  if not found then raise exception 'Marcaje no encontrado.'; end if;

  update marcajes set
    timestamp_marca = p_nuevo_ts,
    estado_revision = 'revisada'
  where id = p_marcaje_id
  returning * into v_nuevo;

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (p_marcaje_id, v_ant.persona_id, 'timestamp_marca',
          v_ant.timestamp_marca::text, p_nuevo_ts::text, v_admin, trim(p_motivo));

  return v_nuevo;
end;
$$;

-- ============================================================================
-- fn_agregar_marcaje: crea un marcaje faltante (ej. olvidó marcar entrada) + auditoría
-- ============================================================================

create or replace function fn_agregar_marcaje(
  p_persona_id uuid, p_tipo tipo_marca, p_ts timestamptz, p_motivo text, p_motivo_otro text default null
)
returns marcajes
language plpgsql security definer set search_path = public
as $$
declare
  v_admin uuid := fn_exigir_admin();
  v_sede uuid;
  v_nuevo marcajes;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la corrección es obligatorio.';
  end if;

  -- sede: la sede base de la persona (correcciones manuales no vienen de un terminal)
  select sede_base_id into v_sede from personas where id = p_persona_id;
  if v_sede is null then raise exception 'Persona no encontrada.'; end if;

  insert into marcajes (client_uuid, persona_id, sede_id, tipo, motivo_otro, timestamp_marca, origen, estado_revision)
  values (gen_random_uuid(), p_persona_id, v_sede, p_tipo, p_motivo_otro, p_ts, 'admin_correccion', 'revisada')
  returning * into v_nuevo;

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (v_nuevo.id, p_persona_id, 'marcaje_agregado', null,
          p_tipo::text || ' @ ' || p_ts::text, v_admin, trim(p_motivo));

  return v_nuevo;
end;
$$;

-- ============================================================================
-- fn_eliminar_marcaje: borra un marcaje (ej. doble marcado) + auditoría
-- ============================================================================

create or replace function fn_eliminar_marcaje(p_marcaje_id uuid, p_motivo text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_admin uuid := fn_exigir_admin();
  v_ant marcajes;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la corrección es obligatorio.';
  end if;

  select * into v_ant from marcajes where id = p_marcaje_id;
  if not found then raise exception 'Marcaje no encontrado.'; end if;

  -- auditar ANTES de borrar; marcaje_id queda null (el marcaje dejará de existir)
  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (null, v_ant.persona_id, 'marcaje_eliminado',
          v_ant.tipo::text || ' @ ' || v_ant.timestamp_marca::text, null, v_admin, trim(p_motivo));

  delete from marcajes where id = p_marcaje_id;
end;
$$;

grant execute on function fn_corregir_marcaje to authenticated;
grant execute on function fn_agregar_marcaje to authenticated;
grant execute on function fn_eliminar_marcaje to authenticated;
