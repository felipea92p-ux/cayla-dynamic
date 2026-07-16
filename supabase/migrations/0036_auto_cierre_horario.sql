-- ============================================================================
-- fn_auto_cierre — usa el modelo de horario vigente (turnos + horario_por_dia)
-- ----------------------------------------------------------------------------
-- Hallazgo (auditoría 2026-07-15, docs/revision-2026-07-15/parches/03-*):
-- fn_auto_cierre (cron cada 15 min) resolvía la "hora de salida programada"
-- leyendo directo `horarios_asignados.hora_salida` — el modelo de ANTES de
-- que el sistema ganara `turnos` por día y `horario_por_dia` (jsonb, distinto
-- por día de semana). fn_recalcular_jornada ya usa la cascada correcta
-- (turno del día → horario_por_dia → legacy) desde 0017_salida_temprana_extra.sql
-- — fn_auto_cierre nunca se actualizó para usar el mismo criterio.
--
-- Escenario concreto: alguien con horario base 16:00 pero un TURNO especial
-- hoy que sale a las 22:00 (cubre un cierre nocturno) — fn_auto_cierre
-- calculaba el corte contra las 16:00 + margen, cerrando la jornada
-- sintéticamente en pleno turno real y corrompiendo horas_trabajadas.
--
-- Único cambio real vs. 0007_auto_cierre.sql: el `left join lateral` que
-- resuelve `h.hora_salida` ahora sigue la misma cascada de 3 pasos que usa
-- fn_recalcular_jornada. El resto de la función (margen de horas, inserción
-- del marcaje sintético, alerta) queda idéntico. No hace falta re-crear el
-- cron ni la tabla configuracion — solo se reemplaza el cuerpo de la función,
-- el job programado sigue apuntando al mismo nombre.
-- ============================================================================

create or replace function fn_auto_cierre()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_horas int;
  v_hoy_lima date := (now() at time zone 'America/Lima')::date;
  v_candidata record;
  v_ts_cierre timestamptz;
  v_cerradas int := 0;
begin
  select (valor #>> '{}')::int into v_horas from configuracion where clave = 'auto_cierre_horas';
  v_horas := coalesce(v_horas, 3);

  for v_candidata in
    select
      j.id as jornada_id,
      j.persona_id,
      j.fecha,
      j.sede_id,
      h.hora_salida
    from jornadas j
    -- cascada turno del día → horario_por_dia → legacy, igual que
    -- fn_recalcular_jornada, en vez de leer horarios_asignados.hora_salida directo
    left join lateral (
      select case
        when t.fecha is not null and t.es_descanso then null
        when t.fecha is not null then t.hora_salida
        when ha.horario_por_dia is not null
          then (ha.horario_por_dia -> extract(dow from j.fecha)::int::text ->> 's')::time
        else ha.hora_salida
      end as hora_salida
      from (select 1) uno
      left join turnos t on t.persona_id = j.persona_id and t.fecha = j.fecha
      left join lateral (
        select horario_por_dia, hora_salida
        from horarios_asignados
        where persona_id = j.persona_id
          and vigente_desde <= j.fecha
          and (vigente_hasta is null or vigente_hasta >= j.fecha)
        order by vigente_desde desc limit 1
      ) ha on true
    ) h on true
    where j.estado in ('abierta', 'en_pausa')
      and (
        (h.hora_salida is not null
          and now() >= ((j.fecha + h.hora_salida) at time zone 'America/Lima') + make_interval(hours => v_horas))
        or (h.hora_salida is null and j.fecha < v_hoy_lima)
      )
  loop
    if v_candidata.hora_salida is not null then
      v_ts_cierre := (v_candidata.fecha + v_candidata.hora_salida) at time zone 'America/Lima';
    else
      select max(timestamp_marca) into v_ts_cierre
      from marcajes
      where persona_id = v_candidata.persona_id
        and (timestamp_marca at time zone 'America/Lima')::date = v_candidata.fecha;
    end if;

    if v_ts_cierre is null then
      continue;
    end if;

    insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen, estado_revision)
    values (gen_random_uuid(), v_candidata.persona_id, v_candidata.sede_id, 'salida_final', v_ts_cierre, 'auto_cierre', 'pendiente_revision');

    insert into alertas (persona_id, tipo, canal, payload)
    values (
      v_candidata.persona_id,
      'auto_cierre',
      'push',
      jsonb_build_object('fecha', v_candidata.fecha, 'jornada_id', v_candidata.jornada_id, 'ts_cierre', v_ts_cierre)
    );

    v_cerradas := v_cerradas + 1;
  end loop;

  return v_cerradas;
end;
$$;
