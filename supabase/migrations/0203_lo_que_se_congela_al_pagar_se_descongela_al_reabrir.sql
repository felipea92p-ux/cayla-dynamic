-- ============================================================================
-- 0203_lo_que_se_congela_al_pagar_se_descongela_al_reabrir.sql
-- ============================================================================
-- QUÉ PROMETE
--
--   1. Que reabrir un periodo con `fn_revertir_pago` vuelva a calcular las
--      jornadas de ese periodo, para que el número que se corrige salga de lo
--      que de verdad pasó y no de lo que había quedado congelado.
--   2. Que el auto-cierre nocturno no invente una salida dentro de un mes ya
--      pagado.
--   3. Que la pregunta «¿esta fecha cae en un periodo pagado?» tenga UN nombre
--      —`fn_fecha_en_periodo_pagado`— en vez de repetirse escrita a mano.
--
-- QUÉ ASUME
--
--   · Que `periodos_planilla` tiene `estado`, `fecha_ini` y `fecha_fin`, y que
--     'pagado' significa que esa planilla ya se depositó (0025, sin cambios).
--   · Que dos periodos no se solapan — lo garantiza el constraint
--     `periodos_sin_solape`. De ahí que reabrir UNO baste para que las fechas
--     de ese tramo dejen de estar cubiertas por un periodo pagado.
--   · Que `fn_recalcular_jornada` recompone la jornada de un día a partir de
--     sus marcajes, y que lleva dentro el candado de periodo pagado desde la
--     0138 (hoy vive en la 0191, líneas 124-130).
--
-- POR QUÉ EXISTE — EL AGUJERO ES EL REVERSO DEL CANDADO
--
--   El sistema protege bien una planilla pagada. `fn_recalcular_jornada` sale
--   en silencio si la fecha cae en un periodo pagado; `fn_planilla_calcular`
--   suma `jornadas`, no `marcajes`; y la 0096 guarda una foto inmutable del
--   desglose. Tres capas, y las tres funcionan.
--
--   Lo que NO existía es la operación contraria. Mientras el periodo está
--   pagado entran marcas de verdad —la cola offline del terminal que sincroniza
--   tarde, una corrección de un admin— y la jornada de ese día NO se recalcula,
--   a propósito. Después alguien reabre el periodo, justamente para corregir
--   algo:
--
--       fn_revertir_pago  →  escribe la reversa con su motivo
--                         →  pone el periodo en 'abierto'
--                         →  y no recalculaba ni una jornada
--
--   Así que se corregía sobre las cifras viejas, que ignoran todo lo que llegó
--   mientras el periodo estuvo cerrado. Y es el único punto del sistema donde
--   un número equivocado tiene TODA la apariencia de estar verificado: el
--   detector de la 0096 compara la foto contra un recálculo que lee esas mismas
--   jornadas congeladas, los dos coinciden, y la pantalla dice «sin
--   diferencias». No hay ninguna otra señal.
--
--   No existía ninguna función de «recalcular el periodo»: a
--   `fn_recalcular_jornada` solo la llaman los triggers de `marcajes` y las
--   funciones de horario, siempre de un día y una persona.
--
-- ⚠ LA TRAMPA QUE ESTA MIGRACIÓN ESQUIVA, Y QUE NO SE VE LEYENDO EL CÓDIGO
--
--   `fn_recalcular_jornada` BORRA la jornada si ese día no le quedan marcajes.
--   Es correcto — es lo que promete — pero convierte un recálculo del periodo
--   entero en una operación destructiva, porque la 0045 cargó **1.427 jornadas
--   de 2025 SIN un solo marcaje**: la historia diaria de siete personas,
--   verificada al centésimo contra el CSV de origen, que es la que sostiene las
--   gratificaciones y la CTS de los periodos pasados. Reabrir un periodo de
--   2025 las habría borrado en silencio, dentro de la misma transacción que
--   dice estar arreglando algo.
--
--   Por eso el bucle recorre los días que TIENEN marcajes, no las filas de
--   `jornadas`. Un día sin ninguna marca es historia cargada a mano y no se
--   toca. Lo defiende la prueba 158.
--
--   Y se recorren también los días cuyos marcajes están todos anulados (no se
--   filtra por `anulada_at`): ese día sí tuvo marcas, así que su jornada es
--   derivada y le toca actualizarse — que es justo el caso en que hay que
--   borrarla.
--
-- QUÉ NO HACE, Y NO ES UN OLVIDO
--
--   No le pone candado a `fn_registrar_marcaje`. Se evaluó y se descartó el
--   2026-08-10: por esa puerta no se mueve dinero (la jornada no se recalcula y
--   la foto no se toca), y cerrarla obliga a copiar entera la función con más
--   versiones del sistema. Queda anotado en `hallazgos-abiertos.md`, con su
--   medición, en vez de arrastrarlo aquí.
--
--   Tampoco reescribe las ocho funciones que llevan la condición de periodo
--   pagado copiada a mano (fn_set_feriado, fn_quitar_feriado, fn_set_turno,
--   fn_quitar_turno, fn_set_horario_semanal, fn_set_descanso, fn_set_salario,
--   fn_agregar_movimiento y compañía). El helper nace para que las próximas la
--   usen; migrar las que ya funcionan significa copiar ocho cuerpos, y ese es
--   exactamente el movimiento que la 0185 dejó claro que sale caro.
--
-- CÓMO SE REVIERTE
--
--   Volviendo a aplicar `fn_revertir_pago` con el cuerpo de la 0066 y
--   `fn_auto_cierre` con el de la 0095. El helper puede quedarse: no lo usa
--   nadie más. Revertir esto significa aceptar que reabrir un periodo devuelva
--   las cifras de antes de reabrirlo.
--
-- CÓMO SE COMPRUEBA QUE QUEDÓ BIEN
--   La consulta del final devuelve una fila con tres `true`.
-- ============================================================================


-- ── 1 · La pregunta, dicha una sola vez ─────────────────────────────────────
-- La condición estaba escrita a mano en nueve sitios. La lección es de la 0192,
-- que hizo lo mismo con la base imponible: mientras vive copiada, cada copia
-- puede envejecer sola y nadie se entera hasta que dos dicen cosas distintas.
--
-- `exists` nunca devuelve null, así que esta función tampoco. Aun así, quien la
-- use la compara con `is not true` — la forma obligatoria de la casa, porque el
-- día que alguien le agregue una condición sobre un UUID el null vuelve solo.
create or replace function fn_fecha_en_periodo_pagado(p_fecha date)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from periodos_planilla
    where estado = 'pagado'
      and p_fecha between fecha_ini and fecha_fin
  );
$$;

comment on function fn_fecha_en_periodo_pagado(date) is
  '¿Esta fecha cae dentro de un periodo de planilla ya pagado? La pregunta que decide si un dato de ese día se puede tocar. Nació en la 0203 para dejar de estar copiada a mano en nueve funciones.';

grant execute on function fn_fecha_en_periodo_pagado(date) to authenticated;
revoke execute on function fn_fecha_en_periodo_pagado(date) from public, anon;


-- ── 2 · El descongelador ────────────────────────────────────────────────────
-- Cuerpo de la 0066 (la vigente, confirmado con donde-vive.sh) más el bucle del
-- final. Todo lo de arriba está intacto: quién puede, el motivo obligatorio, la
-- fila en `reversas_pago` y el cambio de estado.
create or replace function fn_revertir_pago(p_periodo_id uuid, p_motivo text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_estado text; v_pagado_at timestamptz;
  v_ini date; v_fin date;
  v_dia record; v_dias int := 0;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede revertir un pago.';
  end if;
  if p_motivo is null or length(trim(p_motivo)) < 4 then
    raise exception 'El motivo de la reapertura es obligatorio (mínimo 4 caracteres).';
  end if;
  select estado, pagado_at, fecha_ini, fecha_fin
    into v_estado, v_pagado_at, v_ini, v_fin
  from periodos_planilla where id = p_periodo_id;
  if not found then raise exception 'Periodo inexistente.'; end if;
  if v_estado <> 'pagado' then
    raise exception 'Ese periodo no está pagado (estado actual: %).', v_estado;
  end if;
  insert into reversas_pago (periodo_id, revertido_por, motivo, pagado_at_previo)
    values (p_periodo_id, fn_persona_actual_id(), trim(p_motivo), v_pagado_at);
  update periodos_planilla set estado = 'abierto', pagado_at = null where id = p_periodo_id;

  -- ── Y ahora sí, se descongela ─────────────────────────────────────────────
  -- EL ORDEN IMPORTA Y NO ES CASUAL: el update de arriba tiene que estar hecho
  -- antes de llegar aquí. `fn_recalcular_jornada` lee el estado del periodo en
  -- cada llamada, así que si se recalculara antes saldría en silencio por su
  -- propio candado y este bucle no haría absolutamente nada — sin fallar, sin
  -- avisar, y con toda la pinta de estar funcionando.
  --
  -- SOLO DÍAS CON MARCAJES. Un día sin ninguna marca es historia cargada a mano
  -- (la 0045 tiene 1.427 así, todo 2025 de siete personas) y recalcularlo la
  -- borraría, porque fn_recalcular_jornada elimina la jornada de un día que se
  -- quedó sin marcas. Las personas nunca se borran y su historial tampoco.
  --
  -- Sin filtrar por `anulada_at`: un día cuyas marcas se anularon todas SÍ tuvo
  -- marcas, su jornada es derivada, y le toca desaparecer.
  for v_dia in
    select distinct m.persona_id,
           (m.timestamp_marca at time zone 'America/Lima')::date as fecha
    from marcajes m
    where (m.timestamp_marca at time zone 'America/Lima')::date between v_ini and v_fin
  loop
    perform fn_recalcular_jornada(v_dia.persona_id, v_dia.fecha);
    v_dias := v_dias + 1;
  end loop;

  raise notice 'Periodo reabierto: % jornadas recalculadas entre % y %.', v_dias, v_ini, v_fin;
end;
$$;

grant execute on function fn_revertir_pago(uuid, text) to authenticated;
revoke execute on function fn_revertir_pago(uuid, text) from public, anon;


-- ── 3 · El auto-cierre no entra a un mes pagado ─────────────────────────────
-- Cuerpo de la 0095 (la vigente) copiado con script, no a mano, y comprobado
-- byte a byte: solo cambia el bloque de comentario y la condición del cursor.
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
      -- 0203 · Un día de un mes ya PAGADO no se auto-cierra. Este cron corre de
      -- madrugada, sin que nadie lo pulse: inventarle una salida a un día ya
      -- pagado es escribir en un mes cerrado sin nadie mirando. Y encima no
      -- serviría de nada — fn_recalcular_jornada tampoco lo recalcularía (candado
      -- de la 0138, hoy en la 0191): quedaría una marca sintética que no cambia
      -- ninguna cifra y una alerta que nadie puede atender. La jornada se queda
      -- abierta y visible en Correcciones, que es donde una persona decide.
      and fn_fecha_en_periodo_pagado(j.fecha) is not true
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


-- Se re-declaran los permisos: desde la 0076 nada nace abierto, y una función
-- reemplazada sin su grant se manifiesta como «permission denied for function».
grant execute on function fn_auto_cierre() to authenticated;
revoke execute on function fn_auto_cierre() from public, anon;

notify pgrst, 'reload schema';

insert into migraciones_aplicadas (numero, nombre)
values (203, 'lo_que_se_congela_al_pagar_se_descongela_al_reabrir')
on conflict (numero) do nothing;


-- ── Comprobación de que la pegada llegó entera ──────────────────────────────
-- Tres `true`. Si alguno sale false, esa parte no se aplicó.
--
-- Aquí sí se mira el texto de la función, y es correcto: esto no comprueba que
-- la promesa se cumpla —eso es trabajo de la prueba 158, que llama a las
-- funciones de verdad— sino que lo que hay en producción es lo que se pegó.
-- Sin este paso, media migración aplicada se lee igual que una entera.
select
  fn_fecha_en_periodo_pagado(current_date) is not null
    as helper_responde,
  (select prosrc like '%fn_fecha_en_periodo_pagado%'
     from pg_proc where proname = 'fn_auto_cierre')
    as auto_cierre_salta_lo_pagado,
  (select prosrc like '%fn_recalcular_jornada%'
     from pg_proc where proname = 'fn_revertir_pago')
    as revertir_pago_descongela;
