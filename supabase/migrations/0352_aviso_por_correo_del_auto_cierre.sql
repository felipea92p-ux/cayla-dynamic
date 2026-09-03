-- ============================================================================
-- 0352 — El aviso de auto-cierre por fin sale de la base
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE: cuando fn_auto_cierre inventa una salida_final porque nadie
-- marcó, la persona Y la encargada de su sede reciben un correo esa misma
-- tarde/madrugada — no al mes siguiente en Incidencias.
--
-- QUÉ ENCONTRAMOS ANTES DE ESCRIBIR ESTO: `alertas` y `push_tokens` existen
-- desde la 0001. fn_auto_cierre YA inserta en `alertas` cada vez que cierra
-- un día — lleva haciéndolo desde la 0007. Pero insertaba con
-- `canal = 'push'`, que apunta a `push_tokens.expo_push_token`: infraestructura
-- para una app móvil en Expo que nunca se construyó (`apps/` solo tiene
-- `web`). Esas filas se generaban, quedaban en `estado = 'pendiente'` para
-- siempre, y nadie las leía — ni falla ni avisa, simplemente no pasa nada.
-- Y el destinatario tampoco era el correcto: la propia persona, nunca su
-- encargada.
--
-- Esta migración NO crea el problema de detección —ya estaba resuelto desde
-- hace más de 300 migraciones— resuelve el envío, que faltaba.
--
-- QUÉ ASUME:
--   · `personas.email` (columna de la 0006) está poblado para las personas
--     que importa avisar. Si no lo está, el correo de esa persona se omite
--     y el de su encargada (si la tiene) sigue saliendo — Vogels: todo falla,
--     todo el tiempo, y un correo sin destinatario no debe tumbar el resto
--     de la cola. Eso lo decide el código de app/api/enviar-alertas, no esta
--     migración.
--   · Hay como máximo un puñado de auto-cierres por noche (30 personas, 4
--     sedes) — un correo por evento no se vuelve spam a este volumen. Si
--     algún día lo fuera, la salida es agrupar en un resumen diario, no
--     acá.
--
-- POR QUÉ ESTA FORMA (cron dentro de Postgres, no Vercel Cron): este repo ya
-- tiene el patrón — fn_auto_cierre corre cada 15 min vía `cron.schedule`
-- desde la 0007. Un segundo cron que drena la cola de `alertas` cada 15 min
-- reutiliza exactamente esa idea, y no depende de qué plan de Vercel tenga
-- el proyecto (Vercel Cron restringe la frecuencia según el plan; pg_cron
-- corre dentro de Supabase y no tiene ese límite).
--
-- EL SECRETO NO VIAJA EN EL REPO. El cron llama a un endpoint HTTP
-- (app/api/enviar-alertas) autenticado con un token compartido, igual que
-- ESPEJO_TOKEN protege /api/espejo. Ese token vive en Supabase Vault, no en
-- este archivo — hay que crearlo A MANO en el SQL Editor ANTES de pegar esta
-- migración:
--
--   select vault.create_secret('<el mismo valor que pongas en Vercel como ALERTAS_CRON_TOKEN>', 'alertas_cron_token');
--
-- Si el secreto no existe, `net.http_post` manda un Authorization vacío y el
-- endpoint responde 401 — no falla en silencio, pero tampoco entrega nada
-- hasta que el secreto esté puesto.
--
-- SE REVIERTE: `select cron.unschedule('enviar-alertas-pendientes');`,
-- volver `fn_auto_cierre` a insertar `canal = 'push'` sin `sede_id` en el
-- payload (o dejar las dos formas conviviendo — el endpoint solo procesa
-- `canal = 'email'`, así que revertir el canal alcanza para apagarlo).
--
-- md5 de partida (Postgres LOCAL, no producción) — fn_auto_cierre: 646000ab8d22f110c0ee019be319f2b1
-- Vuelve a pedirle el md5 a producción con donde-vive.sh justo antes de
-- pegar, no al principio de la sesión.
-- ============================================================================

-- ── 1 · fn_auto_cierre: canal = 'email', y el payload lleva sede_id ─────────
-- Cambian DOS cosas y nada más — cada línea de la 0203 sigue intacta:
--   · 'push' → 'email': el canal que sí se va a entregar.
--   · se agrega 'sede_id' al payload: app/api/enviar-alertas lo necesita
--     para encontrar a la encargada sin adivinar la sede de otra tabla.
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
      and fn_fecha_en_periodo_pagado(j.fecha, j.persona_id) is not true
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

    -- ⇩⇩⇩ CAMBIO 0352 ⇩⇩⇩ 'push' → 'email' (el canal que de verdad se entrega,
    -- ver encabezado) y se agrega 'sede_id' al payload.
    insert into alertas (persona_id, tipo, canal, payload)
    values (
      v_candidata.persona_id,
      'auto_cierre',
      'email',
      jsonb_build_object(
        'fecha', v_candidata.fecha,
        'jornada_id', v_candidata.jornada_id,
        'ts_cierre', v_ts_cierre,
        'sede_id', v_candidata.sede_id
      )
    );

    v_cerradas := v_cerradas + 1;
  end loop;

  return v_cerradas;
end;
$function$;

grant execute on function fn_auto_cierre() to authenticated;
revoke execute on function fn_auto_cierre() from public, anon;

-- ── 2 · El cron que drena la cola ────────────────────────────────────────────
-- Cada 15 min, igual que fn_auto_cierre — no hace falta más seguido: nadie
-- necesita enterarse en el segundo exacto, y preguntar más rápido solo suma
-- tráfico. `net.http_post` es asíncrono (encola la petición y sigue) así que
-- esto nunca bloquea al cron ni a quien esté usando la base en ese momento.
select cron.schedule(
  'enviar-alertas-pendientes',
  '*/15 * * * *',
  $$
  select net.http_post(
    url := 'https://cayla-dynamic.vercel.app/api/enviar-alertas',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || coalesce(
        (select decrypted_secret from vault.decrypted_secrets where name = 'alertas_cron_token'),
        ''
      ),
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  );
  $$
);
