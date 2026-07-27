-- ============================================================================
-- 0095 — Ni horas negativas, ni reabrir un pago sin que quede por qué
-- ----------------------------------------------------------------------------
-- PROMETE:
--   1. Que una jornada no pueda tener horas negativas — ni por el auto-cierre
--      ni por ningún otro camino.
--   2. Que reabrir un periodo pagado deje siempre quién, cuándo y por qué.
--
-- ASUME: 0066 (fn_revertir_pago), 0089 y 0094.
--
-- ── 1 · HORAS NEGATIVAS ─────────────────────────────────────────────────────
-- fn_auto_cierre estampaba la salida sintética en «fecha + hora de salida
-- programada» sin mirar las marcas reales del día. Si la persona entró DESPUÉS
-- de su hora programada de salida —turno cambiado, evento nocturno, cierre de
-- inventario— y olvidó marcar su salida, el auto-cierre ponía la salida ANTES de
-- la entrada. fn_recalcular_jornada resta sin piso, así que guardaba un número
-- negativo, y fn_planilla_calcular lo suma tal cual: el día trabajado le RESTABA
-- horas del mes a quien sí lo trabajó.
--
-- Se cierra por los dos lados: la hora inventada nunca puede ser anterior a una
-- marca real, y un CHECK en `jornadas` hace imposible el estado. Un número
-- negativo de horas no es algo que se valide en el código: es algo que no debe
-- poder existir.
--
-- ── 2 · REABRIR SIN MOTIVO ──────────────────────────────────────────────────
-- La 0066 se escribió justamente para esto: «reabrir toca DINERO: debe quedar
-- QUIÉN lo reabrió, CUÁNDO y POR QUÉ». Creó fn_revertir_pago, que exige motivo y
-- escribe en `reversas_pago`. Pero dejó la puerta vieja abierta:
-- fn_periodo_pagado(id, false) seguía reabriendo sin pedir nada y sin escribir
-- una sola fila de auditoría. La pantalla usa la puerta buena; PostgREST expone
-- la otra a cualquier sesión de admin o líder.
--
-- Y reabrir no es cosmético: es lo que levanta TODOS los candados que impiden
-- anular, corregir o agregar marcajes de ese periodo. Se podía reabrir, mover
-- marcas, volver a pagar, y no quedar rastro de la reapertura.
--
-- Ahora fn_periodo_pagado solo marca pagado. Reabrir es fn_revertir_pago, que
-- pide motivo. La firma no cambia, para no romper la llamada de la pantalla.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_auto_cierre()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      -- La salida inventada NUNCA puede caer antes de una marca real. Si la
      -- persona entró después de su hora programada de salida (turno cambiado,
      -- evento nocturno, cierre de inventario) el auto-cierre ponía la salida
      -- ANTES de la entrada, y fn_recalcular_jornada restaba sin ningún piso:
      -- horas NEGATIVAS que fn_planilla_calcular suma tal cual. El día trabajado
      -- le RESTABA horas del mes a quien sí lo trabajó.
      v_ts_cierre := greatest(
        (v_candidata.fecha + v_candidata.hora_salida) at time zone 'America/Lima',
        (select max(m.timestamp_marca) from marcajes m
          where m.persona_id = v_candidata.persona_id
            and (m.timestamp_marca at time zone 'America/Lima')::date = v_candidata.fecha
            and m.anulada_at is null));
    else
      select max(timestamp_marca) into v_ts_cierre
      from marcajes
      where persona_id = v_candidata.persona_id
        and (timestamp_marca at time zone 'America/Lima')::date = v_candidata.fecha
        and anulada_at is null;
    end if;

    if v_ts_cierre is null then
      continue;
    end if;

    -- Nunca poner una segunda salida final donde ya hay una viva.
    -- El caso: se anula la salida_final de un día y la jornada vuelve a estado
    -- 'abierta', que es justo lo que este bucle recoge — así que por la noche el
    -- cron le inventaba otra. Y si después alguien reactivaba la original, el día
    -- acababa con DOS salidas finales y el recálculo se quedaba con la última por
    -- hora, con desempate arbitrario cuando coinciden.
    if exists (
      select 1 from marcajes
      where persona_id = v_candidata.persona_id
        and tipo = 'salida_final'
        and (timestamp_marca at time zone 'America/Lima')::date = v_candidata.fecha
        and anulada_at is null
    ) then
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
$function$;

-- ── El estado imposible, imposible en el esquema ─────────────────────────────
-- Se limpia antes cualquier fila que ya lo tenga: si existe alguna, es de un día
-- que el auto-cierre cerró al revés, y su valor real hay que recalcularlo.
update jornadas set horas_trabajadas = null where horas_trabajadas < 0;

alter table jornadas drop constraint if exists chk_horas_no_negativas;
alter table jornadas add constraint chk_horas_no_negativas
  check (horas_trabajadas is null or horas_trabajadas >= 0);

comment on constraint chk_horas_no_negativas on jornadas is
  'Un día no puede restar horas. Nació de la 0095: el auto-cierre podía estampar la salida antes de la entrada y el resultado se sumaba a la planilla.';


-- ── Reabrir un pago solo por la puerta que pide motivo ───────────────────────
create or replace function fn_periodo_pagado(p_periodo_id uuid, p_pagado boolean)
returns void language plpgsql security definer set search_path = public as $fn$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede marcar un pago.';
  end if;

  if coalesce(p_pagado, false) is not true then
    raise exception 'Para reabrir un pago usa Revertir pago: la regla del sistema es que quede el motivo, quién lo hizo y cuándo. Reabrir levanta los candados que protegen los marcajes de ese periodo.';
  end if;

  update periodos_planilla
     set estado = 'pagado', pagado_at = now()
   where id = p_periodo_id;
  if not found then raise exception 'Periodo inexistente.'; end if;
end;
$fn$;
grant execute on function fn_periodo_pagado(uuid, boolean) to authenticated;
revoke execute on function fn_periodo_pagado(uuid, boolean) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (95, 'ni_horas_negativas_ni_reabrir_sin_motivo')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
