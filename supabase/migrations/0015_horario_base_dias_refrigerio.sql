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
