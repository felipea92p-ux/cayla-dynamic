-- Editor de horarios desde el panel. Los turnos cambian cada ~15 días y rotan,
-- así que admin/encargadas actualizan la hora de entrada por persona con fecha
-- de vigencia. Versiona: el horario anterior se conserva (para no recalcular
-- tardanzas viejas) y el nuevo aplica desde la fecha indicada.
-- Permiso: admin/lider = cualquiera; supervisor_sede = su sede, menos su propia
-- asistencia y menos admins (reutiliza fn_verificar_corrector).

create or replace function fn_set_horario(
  p_persona_id uuid,
  p_hora_entrada time,
  p_hora_salida time,
  p_vigente_desde date,
  p_almuerzo_min int default 45,
  p_almuerzo_max int default 75
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

  -- quitar cualquier tramo que empiece en o después de la nueva fecha (se reemplaza)
  delete from horarios_asignados
  where persona_id = p_persona_id and vigente_desde >= p_vigente_desde;

  -- cerrar el tramo vigente anterior (el que quedó abierto y empieza antes)
  update horarios_asignados
  set vigente_hasta = p_vigente_desde - 1
  where persona_id = p_persona_id and vigente_hasta is null and vigente_desde < p_vigente_desde;

  -- insertar el nuevo tramo vigente
  insert into horarios_asignados (persona_id, vigente_desde, vigente_hasta, hora_entrada, hora_salida, almuerzo_min_minutos, almuerzo_max_minutos)
  values (p_persona_id, p_vigente_desde, null, p_hora_entrada, p_hora_salida, p_almuerzo_min, p_almuerzo_max);

  -- recalcular jornadas desde la fecha de vigencia (tardanzas nuevas)
  for r in select fecha from jornadas where persona_id = p_persona_id and fecha >= p_vigente_desde loop
    perform fn_recalcular_jornada(p_persona_id, r.fecha);
  end loop;
end;
$$;

-- Quitar el horario de una persona (deja de calcular tardanzas desde una fecha).
create or replace function fn_quitar_horario(p_persona_id uuid, p_desde date)
returns void
language plpgsql security definer set search_path = public
as $$
declare v_editor uuid; r record;
begin
  v_editor := fn_verificar_corrector(p_persona_id);
  delete from horarios_asignados where persona_id = p_persona_id and vigente_desde >= p_desde;
  update horarios_asignados set vigente_hasta = p_desde - 1
  where persona_id = p_persona_id and vigente_hasta is null and vigente_desde < p_desde;
  for r in select fecha from jornadas where persona_id = p_persona_id and fecha >= p_desde loop
    perform fn_recalcular_jornada(p_persona_id, r.fecha);
  end loop;
end;
$$;

grant execute on function fn_set_horario to authenticated;
grant execute on function fn_quitar_horario to authenticated;

-- Los editores necesitan LEER horarios de su ámbito para mostrarlos. Ya existen
-- policies de select para admin/lider, supervisor (su sede) y propia. OK.
