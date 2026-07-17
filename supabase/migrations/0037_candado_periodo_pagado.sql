-- ============================================================================
-- Candado de "periodo ya PAGADO" — extendido a 9 funciones que no lo tenían
-- ----------------------------------------------------------------------------
-- Hallazgo (auditoría 2026-07-15, docs/revision-2026-07-15/B-rpc-consistencia.md):
-- fn_set_feriado / fn_agregar_movimiento / fn_set_objetivos ya bloquean escribir
-- sobre un periodo con periodos_planilla.estado = 'pagado' (0026, 0025, 0032).
-- El mismo candado faltaba en 9 funciones más que también pueden alterar los
-- números de una planilla ya cerrada y pagada.
--
-- Decisiones de Felipe (2026-07-16):
--   · Correcciones de marcaje, turnos y horario: se bloquea si la fecha
--     puntual afectada cae dentro de un periodo ya pagado — mismo criterio
--     que fn_set_feriado.
--   · Salario y horario semanal (ambos versionados desde una fecha en
--     adelante, "lo anterior queda igual, desde el cambio cambia"): se
--     bloquea si existe un periodo pagado que TERMINE en o después de la
--     fecha de vigencia — porque el cambio afecta todo lo posterior a esa
--     fecha, no solo un día puntual, y fn_set_horario_semanal encima
--     recalcula jornadas ya guardadas desde esa fecha.
--   · Fecha de ingreso: se bloquea solo si la persona YA tiene jornadas
--     trabajadas dentro de un periodo pagado (afecta qué feriados le
--     corresponden) — acotado a la persona, no a "cualquier periodo pagado
--     del sistema", para no congelar el campo para todo el equipo.
--   · "Con hijos" (asignación familiar): a propósito SIN candado — es una
--     bandera sin fecha; bloquearla mientras exista cualquier periodo pagado
--     la congelaría para siempre desde el primer mes que se pagó planilla.
--     El riesgo real solo aparece si se reabre un periodo viejo para
--     recalcularlo, momento en que conviene revisar el valor a mano.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) fn_corregir_marcaje — bloquea si la fecha vieja O la nueva caen en un
--    periodo pagado (por si el corrector intenta "mover" un marcaje hacia
--    afuera del periodo pagado, igual queda protegido por el lado viejo).
-- ----------------------------------------------------------------------------
create or replace function fn_corregir_marcaje(p_marcaje_id uuid, p_nuevo_ts timestamptz, p_motivo text)
returns marcajes
language plpgsql security definer set search_path = public
as $$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la corrección es obligatorio.';
  end if;
  select * into v_ant from marcajes where id = p_marcaje_id;
  if not found then raise exception 'Marcaje no encontrado.'; end if;

  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado'
      and (
        (v_ant.timestamp_marca at time zone 'America/Lima')::date between fecha_ini and fecha_fin
        or (p_nuevo_ts at time zone 'America/Lima')::date between fecha_ini and fecha_fin
      )
  ) then
    raise exception 'Ese marcaje cae en un periodo ya PAGADO: corregirlo alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  v_corr := fn_verificar_corrector(v_ant.persona_id);

  update marcajes set timestamp_marca = p_nuevo_ts, estado_revision = 'revisada'
  where id = p_marcaje_id returning * into v_nuevo;

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (p_marcaje_id, v_ant.persona_id, 'timestamp_marca', v_ant.timestamp_marca::text, p_nuevo_ts::text, v_corr, trim(p_motivo));

  return v_nuevo;
end;
$$;

-- ----------------------------------------------------------------------------
-- 2) fn_agregar_marcaje
-- ----------------------------------------------------------------------------
create or replace function fn_agregar_marcaje(
  p_persona_id uuid, p_tipo tipo_marca, p_ts timestamptz, p_motivo text, p_motivo_otro text default null
)
returns marcajes
language plpgsql security definer set search_path = public
as $$
declare v_sede uuid; v_nuevo marcajes; v_corr uuid;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la corrección es obligatorio.';
  end if;

  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado' and (p_ts at time zone 'America/Lima')::date between fecha_ini and fecha_fin
  ) then
    raise exception 'Esa fecha cae en un periodo ya PAGADO: agregar un marcaje ahí alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  v_corr := fn_verificar_corrector(p_persona_id);

  select sede_base_id into v_sede from personas where id = p_persona_id;
  if v_sede is null then raise exception 'Persona no encontrada.'; end if;

  insert into marcajes (client_uuid, persona_id, sede_id, tipo, motivo_otro, timestamp_marca, origen, estado_revision)
  values (gen_random_uuid(), p_persona_id, v_sede, p_tipo, p_motivo_otro, p_ts, 'admin_correccion', 'revisada')
  returning * into v_nuevo;

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (v_nuevo.id, p_persona_id, 'marcaje_agregado', null, p_tipo::text || ' @ ' || p_ts::text, v_corr, trim(p_motivo));

  return v_nuevo;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3) fn_eliminar_marcaje
-- ----------------------------------------------------------------------------
create or replace function fn_eliminar_marcaje(p_marcaje_id uuid, p_motivo text)
returns void
language plpgsql security definer set search_path = public
as $$
declare v_ant marcajes; v_corr uuid;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la corrección es obligatorio.';
  end if;
  select * into v_ant from marcajes where id = p_marcaje_id;
  if not found then raise exception 'Marcaje no encontrado.'; end if;

  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado' and (v_ant.timestamp_marca at time zone 'America/Lima')::date between fecha_ini and fecha_fin
  ) then
    raise exception 'Ese marcaje cae en un periodo ya PAGADO: eliminarlo alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  v_corr := fn_verificar_corrector(v_ant.persona_id);

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (null, v_ant.persona_id, 'marcaje_eliminado', v_ant.tipo::text || ' @ ' || v_ant.timestamp_marca::text, null, v_corr, trim(p_motivo));

  delete from marcajes where id = p_marcaje_id;
end;
$$;

-- ----------------------------------------------------------------------------
-- 4) fn_set_turno
-- ----------------------------------------------------------------------------
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
  if exists (
    select 1 from periodos_planilla where estado = 'pagado' and p_fecha between fecha_ini and fecha_fin
  ) then
    raise exception 'Esa fecha cae en un periodo ya PAGADO: cambiar el turno alteraría una planilla ya pagada. Reabre el periodo primero.';
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

-- ----------------------------------------------------------------------------
-- 5) fn_set_descanso
-- ----------------------------------------------------------------------------
create or replace function fn_set_descanso(p_persona_id uuid, p_fecha date)
returns void
language plpgsql security definer set search_path = public
as $$
declare v_editor uuid;
begin
  v_editor := fn_verificar_corrector(p_persona_id);
  if exists (
    select 1 from periodos_planilla where estado = 'pagado' and p_fecha between fecha_ini and fecha_fin
  ) then
    raise exception 'Esa fecha cae en un periodo ya PAGADO: marcar descanso ahí alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;
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

-- ----------------------------------------------------------------------------
-- 6) fn_quitar_turno
-- ----------------------------------------------------------------------------
create or replace function fn_quitar_turno(p_persona_id uuid, p_fecha date)
returns void
language plpgsql security definer set search_path = public
as $$
declare v_editor uuid;
begin
  v_editor := fn_verificar_corrector(p_persona_id);
  if exists (
    select 1 from periodos_planilla where estado = 'pagado' and p_fecha between fecha_ini and fecha_fin
  ) then
    raise exception 'Esa fecha cae en un periodo ya PAGADO: quitar el turno alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;
  delete from turnos where persona_id = p_persona_id and fecha = p_fecha;
  perform fn_recalcular_jornada(p_persona_id, p_fecha);
end;
$$;

-- ----------------------------------------------------------------------------
-- 7) fn_set_horario_semanal — recalcula jornadas desde p_vigente_desde en
--    adelante, así que el candado va sobre CUALQUIER periodo pagado que
--    termine en o después de esa fecha (no solo el que la contiene).
-- ----------------------------------------------------------------------------
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

  if exists (
    select 1 from periodos_planilla where estado = 'pagado' and fecha_fin >= p_vigente_desde
  ) then
    raise exception 'Ese horario tocaría un periodo ya PAGADO (recalcula las jornadas desde esa fecha en adelante). Reabre el periodo primero.';
  end if;

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

-- ----------------------------------------------------------------------------
-- 8) fn_set_salario — mismo criterio que horario semanal: el candado va sobre
--    cualquier periodo pagado que termine en o después de p_vigente_desde.
-- ----------------------------------------------------------------------------
create or replace function fn_set_salario(
  p_persona_id uuid,
  p_rango text,
  p_salario numeric,
  p_vigente_desde date,
  p_nota text default null
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_yo uuid;
begin
  -- "is not true": fn_es_admin_o_lider() devuelve NULL para identidades autenticadas
  -- sin fila en personas (terminales) — "if not NULL" NO lanza (falla abierto).
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede asignar salarios.';
  end if;
  v_yo := fn_persona_actual_id();

  if p_persona_id is null or not exists (select 1 from personas where id = p_persona_id) then
    raise exception 'Persona inválida.';
  end if;
  if p_rango is null or p_rango not in ('colibri','cayla','caylo','support','aurora','oraculo','archicaylo') then
    raise exception 'Rango inválido: %', coalesce(p_rango, '(vacío)');
  end if;
  if p_salario is null or p_salario <= 0 then
    raise exception 'El salario debe ser mayor a 0.';
  end if;
  if p_vigente_desde is null then
    raise exception 'La fecha de vigencia es obligatoria.';
  end if;
  if exists (
    select 1 from periodos_planilla where estado = 'pagado' and fecha_fin >= p_vigente_desde
  ) then
    raise exception 'Ese cambio de salario tocaría un periodo ya PAGADO. Reabre el periodo primero si de verdad hace falta.';
  end if;

  -- serializar cambios concurrentes por persona: dos llamadas simultáneas chocarían
  -- contra el índice único de tramo abierto (unique_violation); con el lock, la
  -- segunda espera y aplica limpio.
  perform pg_advisory_xact_lock(hashtext('salario:' || p_persona_id::text));

  -- versionado: borra tramos que arrancan en/después de la fecha y recorta CUALQUIER
  -- tramo previo (abierto o cerrado) que se extienda hasta la nueva vigencia — así un
  -- cambio retro-fechado dentro de un tramo ya cerrado no deja tramos solapados.
  delete from asignaciones_salario
    where persona_id = p_persona_id and vigente_desde >= p_vigente_desde;
  update asignaciones_salario set vigente_hasta = p_vigente_desde - 1
    where persona_id = p_persona_id
      and vigente_desde < p_vigente_desde
      and (vigente_hasta is null or vigente_hasta >= p_vigente_desde);

  insert into asignaciones_salario
    (persona_id, rango, salario_mensual_soles, vigente_desde, vigente_hasta, asignado_por, nota)
  values
    (p_persona_id, p_rango, p_salario, p_vigente_desde, null, v_yo, nullif(trim(p_nota), ''));
end;
$$;

-- ----------------------------------------------------------------------------
-- 9) fn_set_fecha_ingreso — acotado a la propia persona: bloquea solo si ELLA
--    ya tiene jornadas trabajadas dentro de un periodo pagado (afecta qué
--    feriados le corresponden en ese periodo). No mira periodos pagados de
--    otras personas, para no congelar el campo para todo el equipo.
-- ----------------------------------------------------------------------------
create or replace function fn_set_fecha_ingreso(p_persona_id uuid, p_fecha date)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede cambiar la fecha de ingreso.';
  end if;
  if p_fecha is null then raise exception 'La fecha de ingreso es obligatoria.'; end if;
  if p_fecha > current_date then raise exception 'La fecha de ingreso no puede ser futura.'; end if;
  if exists (
    select 1 from periodos_planilla pp
    join jornadas j on j.fecha between pp.fecha_ini and pp.fecha_fin
    where pp.estado = 'pagado' and j.persona_id = p_persona_id and j.horas_trabajadas is not null
  ) then
    raise exception 'Esta persona ya tiene un periodo PAGADO con jornadas trabajadas: cambiar su fecha de ingreso podría alterar los feriados de esa planilla. Reabre el periodo primero.';
  end if;
  update personas set fecha_ingreso = p_fecha where id = p_persona_id;
  if not found then raise exception 'Persona inválida.'; end if;
end;
$$;

notify pgrst, 'reload schema';
