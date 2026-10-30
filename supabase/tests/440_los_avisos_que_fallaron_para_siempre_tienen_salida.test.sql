-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 440_los_avisos_que_fallaron_para_siempre_tienen_salida.test.sql — la 0548
-- ============================================================================
-- QUÉ DEFIENDE ESTE ARCHIVO
--   Que un aviso que el despacho ya no va a enviar solo —sea porque agotó sus
--   tres intentos (definitiva) o porque le pasaron los 7 días sin salir
--   (caducada)— tenga salida, y que la salida sea la correcta:
--     · lo que sigue siendo cierto y le alcanza la ventana del despacho de
--       MAÑANA VUELVE a la cola (reencolar);
--     · un contrato o unas vacaciones que siguen siendo ciertos pero ya
--       pasaron la ventana VUELVEN con otra semana (ventana renovada): no se
--       pueden volver a generar y descartarlos le quita a DO el aviso;
--     · lo que ya no es cierto, o es de otro tipo y ya pasó la ventana, SE
--       CIERRA con su motivo, quién y cuándo (descartar) — y NUNCA se marca
--       'enviado', que sería mentirle a la auditoría;
--     · tras resolver, la tarjeta queda en 0 definitivas y 0 caducadas: lo que
--       el botón resuelve es exactamente lo que la tarjeta cuenta;
--     · la vista previa (p_ejecutar = false) no escribe nada y cuenta lo
--       mismo que luego se ejecuta;
--     · solo DO puede, y una ejecución segunda no encuentra nada;
--     · fn_alertas_devolver_intento solo toca filas 'fallido', no baja de 0 y
--       no la puede llamar un navegador.
--
--   Si esto se pone rojo por el lado de «vigencia», el riesgo es silencioso:
--   o se reenvían a una líder de equipo avisos de cosas ya resueltas, o se
--   descartan avisos buenos sin que nadie lo vea.
--
-- LA TRAMPA QUE ESTA PRUEBA SIEMBRA A PROPÓSITO
--   En los avisos de vencimiento `alertas.persona_id` es el DESTINATARIO (una
--   persona de DO, sin contrato a plazo) y la persona del contrato va en
--   `payload->>'persona_id'`. El aviso F de abajo tiene destinatario DO y
--   sujeto Carla (contrato vigente): si la vigencia mirara la columna en vez
--   del payload, lo descartaría — y lo mismo haría con todos los buenos.
--
-- CÓMO SE EVITAN LOS FALSOS ROJOS DE ESTA CASA
--   · `alertas` es compartida y la función cuenta TOTALES; una fila de seed
--     ajena movería los números. Se vacía `alertas` DENTRO de la transacción
--     (el rollback del final la devuelve).
--   · Nada ordena por una columna now() sin desempate, y los tiempos de las
--     filas son todos explícitos (now() - intervalo): dentro de una
--     transacción now() vale lo mismo para todas, así que un empate de
--     tiempos nunca decide un resultado.
--   · Las personas inactivas llevan `fecha_cese` (personas_cese_coherente,
--     0086), el marcaje anulado lleva quién y por qué (chk_anulacion_completa,
--     0081) y la liquidada lleva la MISMA `fecha_cese` que su fila de
--     liquidacion_pagada (fn_persona_liquidada, desde la 0499).
-- ============================================================================
begin;
select plan(94);

-- La prueba cuenta los totales de una función global: arranca sin filas
-- ajenas. Todo esto se deshace con el rollback.
delete from alertas;

-- ── Fixtures ────────────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-000000440001', 'ZZ440', 'Sede de avisos fallidos', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, email, estado, fecha_ingreso, fecha_fin_contrato) values
  -- DO: puede resolver. SIN contrato a plazo (es el destinatario).
  ('00000000-0000-0000-0000-000000440011', 'DO', 'Lab440', '00000000-0000-0000-0000-000000440001', 'admin', 'x',
   '00000000-0000-0000-0000-0000004400a1', 'do440@cayla.test', 'activo', '2024-01-01', null),
  -- Líder de equipo de la sede: NO puede resolver.
  ('00000000-0000-0000-0000-000000440012', 'Lider', 'Lab440', '00000000-0000-0000-0000-000000440001', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000004400a2', 'lider440@cayla.test', 'activo', '2024-01-01', null),
  -- Integrante: NO puede resolver.
  ('00000000-0000-0000-0000-000000440013', 'Integrante', 'Lab440', '00000000-0000-0000-0000-000000440001', 'integrante', 'x',
   '00000000-0000-0000-0000-0000004400a3', null, 'activo', '2024-01-01', null);

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, fecha_fin_contrato, estado, fecha_cese) values
  -- Ina: protagonista de los auto-cierres.
  ('00000000-0000-0000-0000-000000440020', 'Ina', 'AutoCierre440', '00000000-0000-0000-0000-000000440001', 'x', '2024-01-01', null, 'activo', null),
  -- Lía: igual, pero ya cobró su liquidación (cesó hace 30 días, igual que su fila de liquidacion_pagada).
  ('00000000-0000-0000-0000-000000440021', 'Lia', 'Liquidada440', '00000000-0000-0000-0000-000000440001', 'x', '2024-01-01', null, 'inactivo', fn_hoy_lima() - 30),
  -- Carla: contrato a plazo que vence en 12 días, activa.
  ('00000000-0000-0000-0000-000000440030', 'Carla', 'Contrato440', '00000000-0000-0000-0000-000000440001', 'x', fn_hoy_lima() - 20, fn_hoy_lima() + 12, 'activo', null),
  -- Pedro: tuvo contrato por vencer pero ya cesó.
  ('00000000-0000-0000-0000-000000440031', 'Pedro', 'Cesado440', '00000000-0000-0000-0000-000000440001', 'x', fn_hoy_lima() - 20, fn_hoy_lima() + 12, 'inactivo', fn_hoy_lima() - 1),
  -- Vera: dos récords de vacaciones sin gozar, uno ya vencido (30 meses de antigüedad).
  ('00000000-0000-0000-0000-000000440040', 'Vera', 'Vacaciones440', '00000000-0000-0000-0000-000000440001', 'x', (fn_hoy_lima() - interval '30 months')::date, null, 'activo', null),
  -- Vero: igual que Vera, pero ya cesó.
  ('00000000-0000-0000-0000-000000440041', 'Vero', 'Cesada440', '00000000-0000-0000-0000-000000440001', 'x', (fn_hoy_lima() - interval '30 months')::date, null, 'inactivo', fn_hoy_lima() - 1),
  -- Nico: ingresó hace 20 días, no tiene récords por vencer (ya gozó todo lo que debía: no hay nada).
  ('00000000-0000-0000-0000-000000440042', 'Nico', 'Nuevo440', '00000000-0000-0000-0000-000000440001', 'x', fn_hoy_lima() - 20, null, 'activo', null);

-- Marcajes: una salida inventada por el auto-cierre por cada aviso de auto-cierre.
--   a01 → pendiente_revision, viva (vigente)          a02 → ya revisada
--   a03 → pendiente_revision pero anulada             a04 → viva, pero de Lía (liquidada)
--   a05 → viva (aviso viejo)
insert into marcajes (id, client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen, estado_revision, anulada_at, anulada_por, anulada_motivo) values
  ('00000000-0000-0000-0000-000000440a01', '00000000-0000-0000-0000-000000440b01', '00000000-0000-0000-0000-000000440020', '00000000-0000-0000-0000-000000440001', 'salida_final', timestamptz '2026-10-20 22:00:00-05', 'auto_cierre', 'pendiente_revision', null, null, null),
  ('00000000-0000-0000-0000-000000440a02', '00000000-0000-0000-0000-000000440b02', '00000000-0000-0000-0000-000000440020', '00000000-0000-0000-0000-000000440001', 'salida_final', timestamptz '2026-10-19 22:00:00-05', 'auto_cierre', 'revisada', null, null, null),
  ('00000000-0000-0000-0000-000000440a03', '00000000-0000-0000-0000-000000440b03', '00000000-0000-0000-0000-000000440020', '00000000-0000-0000-0000-000000440001', 'salida_final', timestamptz '2026-10-18 22:00:00-05', 'auto_cierre', 'pendiente_revision', timestamptz '2026-10-19 09:00:00-05', '00000000-0000-0000-0000-000000440011', 'anulada por error'),
  ('00000000-0000-0000-0000-000000440a04', '00000000-0000-0000-0000-000000440b04', '00000000-0000-0000-0000-000000440021', '00000000-0000-0000-0000-000000440001', 'salida_final', timestamptz '2026-10-17 22:00:00-05', 'auto_cierre', 'pendiente_revision', null, null, null),
  ('00000000-0000-0000-0000-000000440a05', '00000000-0000-0000-0000-000000440b05', '00000000-0000-0000-0000-000000440020', '00000000-0000-0000-0000-000000440001', 'salida_final', timestamptz '2026-10-16 22:00:00-05', 'auto_cierre', 'pendiente_revision', null, null, null);

-- Lía ya cobró su liquidación.
insert into liquidacion_pagada (persona_id, version, congelada_por, persona, fecha_cese, total, detalle) values
  ('00000000-0000-0000-0000-000000440021', 1, '00000000-0000-0000-0000-000000440011', 'Lia Liquidada440', fn_hoy_lima() - 30, 100, '{}'::jsonb);
set session_replication_role = origin;

-- Para que exista un «antes» y un «después» del despacho en esta base (como en
-- la 288): lo que se creó antes es backlog, y nada de lo de abajo lo es salvo
-- el aviso 147 (creado hace 30 días, antes de que existiera el despacho).
update migraciones_aplicadas set aplicada_at = now() - interval '20 days' where numero = 354;

-- ── Los avisos ──────────────────────────────────────────────────────────────
-- Sufijo = letra del caso en el encabezado de este archivo. Todos 'fallido' con
-- intentos 3 y la nota «Resend 403», salvo donde se diga. Creados hace 2 días
-- (dentro de la ventana) salvo los marcados «viejo» (hace 10 días).
--
-- DOS de los tipos de fecha del payload se arman con el mismo cálculo que usa
-- el generador (fn_vacaciones_saldo_interno), para que `vence_el` sea el real.
insert into alertas (id, persona_id, tipo, canal, payload, estado, intentos, nota_fallo, procesando_desde, created_at) values
  -- AUTO-CIERRE ------------------------------------------------------------
  -- A · vigente → REENCOLAR
  ('00000000-0000-0000-0000-000000440101', '00000000-0000-0000-0000-000000440020', 'auto_cierre', 'push',
   jsonb_build_object('fecha', '2026-10-20', 'ts_cierre', timestamptz '2026-10-20 22:00:00-05'), 'fallido', 3, 'Resend 403', null, now() - interval '2 days'),
  -- B · la salida ya fue revisada → ya_no_vigente
  ('00000000-0000-0000-0000-000000440102', '00000000-0000-0000-0000-000000440020', 'auto_cierre', 'push',
   jsonb_build_object('fecha', '2026-10-19', 'ts_cierre', timestamptz '2026-10-19 22:00:00-05'), 'fallido', 3, 'Resend 403', null, now() - interval '2 days'),
  -- C · la salida fue anulada → ya_no_vigente
  ('00000000-0000-0000-0000-000000440103', '00000000-0000-0000-0000-000000440020', 'auto_cierre', 'push',
   jsonb_build_object('fecha', '2026-10-18', 'ts_cierre', timestamptz '2026-10-18 22:00:00-05'), 'fallido', 3, 'Resend 403', null, now() - interval '2 days'),
  -- D · la persona ya está liquidada → ya_no_vigente
  ('00000000-0000-0000-0000-000000440104', '00000000-0000-0000-0000-000000440021', 'auto_cierre', 'push',
   jsonb_build_object('fecha', '2026-10-17', 'ts_cierre', timestamptz '2026-10-17 22:00:00-05'), 'fallido', 3, 'Resend 403', null, now() - interval '2 days'),
  -- E · vigente pero VIEJO, y es de un tipo cuyo hecho sigue a la vista en su pantalla
  --     → fuera_de_ventana (y la nota dice que sigue vigente)
  ('00000000-0000-0000-0000-000000440105', '00000000-0000-0000-0000-000000440020', 'auto_cierre', 'push',
   jsonb_build_object('fecha', '2026-10-16', 'ts_cierre', timestamptz '2026-10-16 22:00:00-05'), 'fallido', 3, 'Resend 403', null, now() - interval '10 days'),
  -- Q · viejo Y ya revisado → ya_no_vigente (no vigente manda sobre la ventana)
  ('00000000-0000-0000-0000-000000440106', '00000000-0000-0000-0000-000000440020', 'auto_cierre', 'push',
   jsonb_build_object('fecha', '2026-10-19', 'ts_cierre', timestamptz '2026-10-19 22:00:00-05'), 'fallido', 3, 'Resend 403', null, now() - interval '10 days'),
  -- CONTRATO (destinatario = DO, sujeto = payload) -------------------------
  -- F · LA TRAMPA: destinatario DO (sin contrato a plazo), sujeto Carla vigente → REENCOLAR
  ('00000000-0000-0000-0000-000000440111', '00000000-0000-0000-0000-000000440011', 'contrato_por_vencer', 'email',
   jsonb_build_object('persona_id', '00000000-0000-0000-0000-000000440030', 'fecha_fin_contrato', fn_hoy_lima() + 12, 'dias_restantes', 12),
   'fallido', 3, 'Resend 403', null, now() - interval '2 days'),
  -- G · el contrato se renovó: la fecha del aviso ya no es la de Carla → ya_no_vigente
  ('00000000-0000-0000-0000-000000440112', '00000000-0000-0000-0000-000000440011', 'contrato_por_vencer', 'email',
   jsonb_build_object('persona_id', '00000000-0000-0000-0000-000000440030', 'fecha_fin_contrato', fn_hoy_lima() + 5, 'dias_restantes', 5),
   'fallido', 3, 'Resend 403', null, now() - interval '2 days'),
  -- H · el sujeto ya cesó (y sin nota anterior) → ya_no_vigente
  ('00000000-0000-0000-0000-000000440113', '00000000-0000-0000-0000-000000440011', 'contrato_por_vencer', 'email',
   jsonb_build_object('persona_id', '00000000-0000-0000-0000-000000440031', 'fecha_fin_contrato', fn_hoy_lima() + 12, 'dias_restantes', 12),
   'fallido', 3, null, null, now() - interval '2 days'),
  -- P · vigente pero VIEJO → REENCOLAR CON VENTANA RENOVADA (no se puede regenerar y el hecho sigue cierto)
  ('00000000-0000-0000-0000-000000440114', '00000000-0000-0000-0000-000000440011', 'contrato_por_vencer', 'email',
   jsonb_build_object('persona_id', '00000000-0000-0000-0000-000000440030', 'fecha_fin_contrato', fn_hoy_lima() + 12, 'dias_restantes', 12),
   'fallido', 3, 'Resend 403', null, now() - interval '10 days'),
  -- S2 · vigente, de 6 días y 20 horas: hoy cabe, mañana no → REENCOLAR CON VENTANA RENOVADA
  ('00000000-0000-0000-0000-000000440115', '00000000-0000-0000-0000-000000440011', 'contrato_por_vencer', 'email',
   jsonb_build_object('persona_id', '00000000-0000-0000-0000-000000440030', 'fecha_fin_contrato', fn_hoy_lima() + 12, 'dias_restantes', 12),
   'fallido', 3, 'Resend 403', null, now() - interval '6 days 20 hours'),
  -- VACACIONES (destinatario = DO, sujeto = payload) -----------------------
  -- I · Vera: récord vencido sin gozar, vence_el real → REENCOLAR
  ('00000000-0000-0000-0000-000000440121', '00000000-0000-0000-0000-000000440011', 'vacaciones_por_vencer', 'email',
   jsonb_build_object('persona_id', '00000000-0000-0000-0000-000000440040',
                      'vence_el', (fn_vacaciones_saldo_interno('00000000-0000-0000-0000-000000440040', fn_hoy_lima()) ->> 'vence_el')),
   'fallido', 3, 'Resend 403', null, now() - interval '2 days'),
  -- J · Vero ya cesó → ya_no_vigente
  ('00000000-0000-0000-0000-000000440122', '00000000-0000-0000-0000-000000440011', 'vacaciones_por_vencer', 'email',
   jsonb_build_object('persona_id', '00000000-0000-0000-0000-000000440041',
                      'vence_el', (fn_vacaciones_saldo_interno('00000000-0000-0000-0000-000000440041', fn_hoy_lima()) ->> 'vence_el')),
   'fallido', 3, 'Resend 403', null, now() - interval '2 days'),
  -- K · Nico no tiene récords sin gozar → ya_no_vigente
  ('00000000-0000-0000-0000-000000440123', '00000000-0000-0000-0000-000000440011', 'vacaciones_por_vencer', 'email',
   jsonb_build_object('persona_id', '00000000-0000-0000-0000-000000440042', 'vence_el', (fn_hoy_lima() + 30)::text),
   'fallido', 3, 'Resend 403', null, now() - interval '2 days'),
  -- R · Vera, pero el aviso decía OTRO vence_el (ya pasó a otro récord) → ya_no_vigente
  ('00000000-0000-0000-0000-000000440124', '00000000-0000-0000-0000-000000440011', 'vacaciones_por_vencer', 'email',
   jsonb_build_object('persona_id', '00000000-0000-0000-0000-000000440040', 'vence_el', (fn_hoy_lima() - 400)::text),
   'fallido', 3, 'Resend 403', null, now() - interval '2 days'),
  -- P2 · Vera, vence_el real, aviso VIEJO → REENCOLAR CON VENTANA RENOVADA
  ('00000000-0000-0000-0000-000000440125', '00000000-0000-0000-0000-000000440011', 'vacaciones_por_vencer', 'email',
   jsonb_build_object('persona_id', '00000000-0000-0000-0000-000000440040',
                      'vence_el', (fn_vacaciones_saldo_interno('00000000-0000-0000-0000-000000440040', fn_hoy_lima()) ->> 'vence_el')),
   'fallido', 3, 'Resend 403', null, now() - interval '10 days'),
  -- TIPO SIN REGLA PROPIA: vigente solo por ventana -------------------------
  -- L1 · fresco → REENCOLAR        L2 · viejo → fuera_de_ventana
  ('00000000-0000-0000-0000-000000440131', '00000000-0000-0000-0000-000000440020', 'tardanza', 'push', '{}'::jsonb, 'fallido', 3, 'Resend 403', null, now() - interval '2 days'),
  ('00000000-0000-0000-0000-000000440132', '00000000-0000-0000-0000-000000440020', 'tardanza', 'push', '{}'::jsonb, 'fallido', 3, 'Resend 403', null, now() - interval '10 days'),
  -- N · murió en su tercer intento hace 3 horas ('procesando' atascada) → REENCOLAR, y suelta la reserva
  ('00000000-0000-0000-0000-000000440133', '00000000-0000-0000-0000-000000440020', 'tardanza', 'push', '{}'::jsonb, 'procesando', 3, 'Resend 403', now() - interval '3 hours', now() - interval '2 days'),
  -- M · EN VUELO ahora mismo (hace 10 min) → no se toca, aunque cuente como definitiva en el resumen
  ('00000000-0000-0000-0000-000000440134', '00000000-0000-0000-0000-000000440020', 'tardanza', 'push', '{}'::jsonb, 'procesando', 3, 'motivo M', now() - interval '10 minutes', now() - interval '2 days'),
  -- S1 · 6 días y 20 horas: hoy cabe en la ventana, pero el despacho de mañana ya no la
  --      alcanza → fuera_de_ventana (no se reencola para morir como fantasma)
  ('00000000-0000-0000-0000-000000440135', '00000000-0000-0000-0000-000000440020', 'tardanza', 'push', '{}'::jsonb, 'fallido', 3, 'Resend 403', null, now() - interval '6 days 20 hours'),
  -- S3 · 5 días y 20 horas: el despacho de mañana todavía la alcanza → REENCOLAR
  ('00000000-0000-0000-0000-000000440136', '00000000-0000-0000-0000-000000440020', 'tardanza', 'push', '{}'::jsonb, 'fallido', 3, 'Resend 403', null, now() - interval '5 days 20 hours'),
  -- NO DEFINITIVAS NI CADUCADAS: no se tocan --------------------------------
  ('00000000-0000-0000-0000-000000440141', '00000000-0000-0000-0000-000000440020', 'tardanza', 'push', '{}'::jsonb, 'fallido', 2, 'intento 2', null, now() - interval '2 days'),
  ('00000000-0000-0000-0000-000000440142', '00000000-0000-0000-0000-000000440020', 'tardanza', 'push', '{}'::jsonb, 'pendiente', 0, null, null, now() - interval '1 day'),
  -- CADUCADAS (sin salir, más de 7 días, intentos que le quedaban, desde que existe el despacho)
  -- Cad1 · tipo sin regla propia → fuera_de_ventana (y sube a intentos 3)
  ('00000000-0000-0000-0000-000000440144', '00000000-0000-0000-0000-000000440020', 'tardanza', 'push', '{}'::jsonb, 'pendiente', 0, null, null, now() - interval '9 days'),
  -- Cad2 · contrato vigente → REENCOLAR CON VENTANA RENOVADA
  ('00000000-0000-0000-0000-000000440145', '00000000-0000-0000-0000-000000440011', 'contrato_por_vencer', 'email',
   jsonb_build_object('persona_id', '00000000-0000-0000-0000-000000440030', 'fecha_fin_contrato', fn_hoy_lima() + 12, 'dias_restantes', 12),
   'pendiente', 0, null, null, now() - interval '9 days'),
  -- Cad3 · auto-cierre cuya salida YA se revisó (fallido con 1 intento) → ya_no_vigente (y sube a intentos 3)
  ('00000000-0000-0000-0000-000000440146', '00000000-0000-0000-0000-000000440020', 'auto_cierre', 'push',
   jsonb_build_object('fecha', '2026-10-19', 'ts_cierre', timestamptz '2026-10-19 22:00:00-05'), 'fallido', 1, 'Resend 403', null, now() - interval '9 days'),
  -- Cad4 · BACKLOG: creada hace 30 días, antes de que existiera el despacho → no es caducada, no se toca
  ('00000000-0000-0000-0000-000000440147', '00000000-0000-0000-0000-000000440020', 'tardanza', 'push', '{}'::jsonb, 'pendiente', 0, null, null, now() - interval '30 days'),
  -- Cad6 · caducada pero EN VUELO ahora mismo → no se toca
  ('00000000-0000-0000-0000-000000440149', '00000000-0000-0000-0000-000000440020', 'tardanza', 'push', '{}'::jsonb, 'procesando', 1, 'motivo Cad6', now() - interval '10 minutes', now() - interval '9 days');

-- Cad5 · una vieja que SÍ salió: enviada, no es caducada ni nada.
insert into alertas (id, persona_id, tipo, canal, payload, estado, intentos, enviado_at, created_at) values
  ('00000000-0000-0000-0000-000000440143', '00000000-0000-0000-0000-000000440020', 'tardanza', 'push', '{}'::jsonb, 'enviado', 1, now() - interval '1 day', now() - interval '1 day'),
  ('00000000-0000-0000-0000-000000440148', '00000000-0000-0000-0000-000000440020', 'tardanza', 'push', '{}'::jsonb, 'enviado', 1, now() - interval '11 days', now() - interval '12 days');

-- Foto del estado de las filas que NO deben moverse nunca.
create temporary table foto_intocables as
select id, estado, intentos, nota_fallo, procesando_desde, created_at
  from alertas
 where id in ('00000000-0000-0000-0000-000000440134', '00000000-0000-0000-0000-000000440141',
              '00000000-0000-0000-0000-000000440142', '00000000-0000-0000-0000-000000440143',
              '00000000-0000-0000-0000-000000440147', '00000000-0000-0000-0000-000000440148',
              '00000000-0000-0000-0000-000000440149');

-- Foto de cuándo se crearon y qué payload traían (para comprobar la ventana renovada).
create temporary table foto_fecha as
select id, created_at, payload from alertas;

-- ── 1 · El check ────────────────────────────────────────────────────────────
select lives_ok(
  $$ insert into alertas (id, persona_id, tipo, canal, estado)
     values ('00000000-0000-0000-0000-000000440199', '00000000-0000-0000-0000-000000440020', 'tardanza', 'push', 'descartada') $$,
  '1 · el check de estado acepta ''descartada'''
);
select throws_ok(
  $$ insert into alertas (persona_id, tipo, canal, estado)
     values ('00000000-0000-0000-0000-000000440020', 'tardanza', 'push', 'cancelada') $$,
  '23514',
  null,
  '1 · y sigue rechazando cualquier otro valor'
);
select lives_ok(
  $$ update alertas set estado = 'procesando', procesando_desde = now() where id = '00000000-0000-0000-0000-000000440199';
     update alertas set estado = 'enviado' where id = '00000000-0000-0000-0000-000000440199';
     update alertas set estado = 'fallido' where id = '00000000-0000-0000-0000-000000440199';
     update alertas set estado = 'pendiente' where id = '00000000-0000-0000-0000-000000440199' $$,
  '1 · y los cuatro estados de siempre siguen valiendo'
);
delete from alertas where id = '00000000-0000-0000-0000-000000440199';

-- ── 2 · Permisos ────────────────────────────────────────────────────────────
select ok(
  has_function_privilege('authenticated', 'fn_alertas_resolver_fallidas(boolean)', 'execute')
  and not has_function_privilege('anon', 'fn_alertas_resolver_fallidas(boolean)', 'execute'),
  '2 · la resolución la puede llamar una sesión autenticada y nunca anon'
);
select ok(
  not has_function_privilege('authenticated', 'fn_alerta_sigue_vigente(text, uuid, jsonb)', 'execute')
  and not has_function_privilege('anon', 'fn_alerta_sigue_vigente(text, uuid, jsonb)', 'execute'),
  '2 · y el ayudante de vigencia es interno: ni authenticated ni anon'
);
select ok(
  not has_function_privilege('authenticated', 'fn_alerta_sin_salida(text, int, timestamptz, timestamptz, timestamptz)', 'execute')
  and not has_function_privilege('anon', 'fn_alerta_sin_salida(text, int, timestamptz, timestamptz, timestamptz)', 'execute'),
  '2 · y el de «sin salida» también: ni authenticated ni anon'
);
select ok(
  not has_function_privilege('authenticated', 'fn_alertas_devolver_intento(uuid)', 'execute')
  and not has_function_privilege('anon', 'fn_alertas_devolver_intento(uuid)', 'execute'),
  '2 · y devolver el intento es solo de la ruta con la llave de servicio: ni authenticated ni anon'
);

create temporary table foto_antes as
select md5(string_agg(id::text || estado || intentos::text || coalesce(nota_fallo, '') || coalesce(procesando_desde::text, '') || created_at::text || payload::text, ',' order by id)) as huella
  from alertas;

-- Integrante
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004400a3', true);
select throws_ok($$ select fn_alertas_resolver_fallidas() $$,
  'Solo Desarrollo Organizacional puede resolver los avisos que fallaron.',
  '2 · un integrante no puede ni mirar');
select throws_ok($$ select fn_alertas_resolver_fallidas(true) $$,
  'Solo Desarrollo Organizacional puede resolver los avisos que fallaron.',
  '2 · ni ejecutar');
-- Líder de equipo de la sede
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004400a2', true);
select throws_ok($$ select fn_alertas_resolver_fallidas() $$,
  'Solo Desarrollo Organizacional puede resolver los avisos que fallaron.',
  '2 · la líder de equipo de una sede tampoco: la tarjeta Sistema es de DO');
select throws_ok($$ select fn_alertas_resolver_fallidas(true) $$,
  'Solo Desarrollo Organizacional puede resolver los avisos que fallaron.',
  '2 · ni ejecutar');
-- Identidad sin fila en personas (rol null): el caso de la terminal de una sede
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004400ff', true);
select throws_ok($$ select fn_alertas_resolver_fallidas(true) $$,
  'Solo Desarrollo Organizacional puede resolver los avisos que fallaron.',
  '2 · una identidad sin fila en personas (rol null) NO pasa: el null no cuenta como autorizado');
-- Sin sesión
select set_config('request.jwt.claim.sub', '', true);
select throws_ok($$ select fn_alertas_resolver_fallidas(true) $$,
  'Solo Desarrollo Organizacional puede resolver los avisos que fallaron.',
  '2 · sin sesión tampoco');

select is(
  (select md5(string_agg(id::text || estado || intentos::text || coalesce(nota_fallo, '') || coalesce(procesando_desde::text, '') || created_at::text || payload::text, ',' order by id)) from alertas),
  (select huella from foto_antes),
  '2 · y ninguno de los intentos denegados escribió nada'
);

-- A partir de acá, DO.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004400a1', true);

create temporary table resumen_antes as select fn_alertas_despacho_resumen() as r;

-- ── 3 · Vigencia, el ayudante solo ──────────────────────────────────────────
select is(fn_alerta_sigue_vigente('contrato_por_vencer', '00000000-0000-0000-0000-000000440011',
    jsonb_build_object('persona_id', '00000000-0000-0000-0000-000000440030', 'fecha_fin_contrato', fn_hoy_lima() + 12)),
  true, '3 · contrato: lo que importa es la persona del PAYLOAD, no el destinatario de la columna');
select is(fn_alerta_sigue_vigente('contrato_por_vencer', '00000000-0000-0000-0000-000000440030',
    jsonb_build_object('persona_id', '00000000-0000-0000-0000-000000440011', 'fecha_fin_contrato', fn_hoy_lima() + 12)),
  false, '3 · y a la inversa: el destinatario con la fecha de otra persona NO es vigente (el DO no tiene contrato a plazo)');
select is(fn_alerta_sigue_vigente('contrato_por_vencer', null,
    jsonb_build_object('persona_id', '00000000-0000-0000-0000-000000440030', 'fecha_fin_contrato', fn_hoy_lima() - 1)),
  false, '3 · contrato: lo ya vencido no es «por vencer»');
select is(fn_alerta_sigue_vigente('contrato_por_vencer', null, '{"persona_id":"no-es-un-uuid","fecha_fin_contrato":"2026-01-01"}'::jsonb),
  false, '3 · un uuid ilegible en el payload no revienta: se contesta «no vigente»');
select is(fn_alerta_sigue_vigente('auto_cierre', '00000000-0000-0000-0000-000000440020', '{"ts_cierre":"ayer"}'::jsonb),
  false, '3 · una fecha ilegible tampoco');
select is(fn_alerta_sigue_vigente('auto_cierre', '00000000-0000-0000-0000-000000440020', '{"fecha":"2026-10-20"}'::jsonb),
  false, '3 · un auto-cierre sin ts_cierre no se puede comprobar: no vigente');
select is(fn_alerta_sigue_vigente('digest_diario', null, '{}'::jsonb),
  true, '3 · un tipo sin regla propia sigue vigente (solo la ventana lo decide)');

-- ── 3b · «Sin salida»: definitivas y caducadas, y nada más ──────────────────
select is(fn_alerta_sin_salida('fallido', 3, null, null, now() - interval '2 days'), true,
  '3b · una definitiva (fallido, 3 intentos) no tiene salida');
select is(fn_alerta_sin_salida('procesando', 3, now() - interval '3 hours', null, now() - interval '2 days'), true,
  '3b · una ''procesando'' atascada con 3 intentos también');
select is(fn_alerta_sin_salida('procesando', 3, now() - interval '10 minutes', null, now() - interval '2 days'), false,
  '3b · pero si está en vuelo ahora mismo no se toca');
select is(fn_alerta_sin_salida('pendiente', 0, null, null, now() - interval '9 days'), true,
  '3b · una caducada (pendiente, más de 7 días, creada desde el despacho) no tiene salida');
select is(fn_alerta_sin_salida('procesando', 1, now() - interval '10 minutes', null, now() - interval '9 days'), false,
  '3b · una caducada en vuelo tampoco se toca');
select is(fn_alerta_sin_salida('pendiente', 0, null, null, now() - interval '30 days'), false,
  '3b · lo creado ANTES del despacho es backlog: no es caducada');
select is(fn_alerta_sin_salida('fallido', 2, null, null, now() - interval '2 days'), false,
  '3b · una fallida con intentos que le quedan y dentro de la ventana la reintenta el despacho solo');
select is(fn_alerta_sin_salida('pendiente', 0, null, now() - interval '1 day', now() - interval '9 days'), false,
  '3b · y una vieja que SÍ salió (enviado_at) no es caducada');
select is(fn_alerta_sin_salida('descartada', 3, null, null, now() - interval '9 days'), false,
  '3b · ni una descartada: ya está resuelta');

-- ── 4 · Vista previa: no escribe y cuenta bien ──────────────────────────────
create temporary table vista as select fn_alertas_resolver_fallidas() as r;

select is((select r ->> 'ejecutado' from vista), 'false', '4 · la vista previa dice ejecutado = false');
select is((select r from vista), (select fn_alertas_resolver_fallidas(false)),
  '4 · y p_ejecutar = false explícito da lo mismo que el valor por defecto');
select is((select r from vista), (select fn_alertas_resolver_fallidas(null)),
  '4 · un null cuenta como «solo mirar», nunca como ejecutar');
select is(
  (select md5(string_agg(id::text || estado || intentos::text || coalesce(nota_fallo, '') || coalesce(procesando_desde::text, '') || created_at::text || payload::text, ',' order by id)) from alertas),
  (select huella from foto_antes),
  '4 · y no escribió ni una columna de ninguna fila');
select is((select (r -> 'reencolar' ->> 'total')::int from vista), 10,
  '4 · reencolar 10: A, F, I, L1, N y S3 en ventana; P, P2, S2 y la caducada Cad2 con ventana renovada');
select is((select r -> 'reencolar' -> 'por_tipo' from vista),
  '{"auto_cierre": 1, "contrato_por_vencer": 4, "vacaciones_por_vencer": 2, "tardanza": 3}'::jsonb,
  '4 · por tipo: LOS TRES con regla propia llegan a reencolar (la trampa de la persona equivocada no los descarta)');
select is((select (r -> 'reencolar' ->> 'ventana_renovada')::int from vista), 4,
  '4 · de ellos, 4 con ventana renovada: contratos y vacaciones vigentes que ya pasaron la ventana (P, P2, S2, Cad2)');
select is((select (r -> 'descartar' ->> 'total')::int from vista), 14,
  '4 · descartar 14: 10 que ya no valen y 4 que salieron de la ventana');
select is((select r -> 'descartar' -> 'por_motivo' from vista),
  '{"fuera_de_ventana": 4, "ya_no_vigente": 10}'::jsonb,
  '4 · por motivo: fuera_de_ventana 4 (E, L2, S1, Cad1) y ya_no_vigente 10 (B, C, D, Q, G, H, J, K, R, Cad3)');
select is((select array_agg(k order by k) from vista, jsonb_object_keys(r -> 'reencolar') k),
  array['por_tipo', 'total', 'ventana_renovada'],
  '4 · la forma de «reencolar» trae sus tres claves (la pantalla vieja sigue entendiendo total y por_tipo)');

-- ── 5 · Ejecutar ────────────────────────────────────────────────────────────
create temporary table hecho as select fn_alertas_resolver_fallidas(true) as r;

select is((select r ->> 'ejecutado' from hecho), 'true', '5 · ejecutar dice ejecutado = true');
select is((select (r - 'ejecutado') from hecho), (select (r - 'ejecutado') from vista),
  '5 · y hace EXACTAMENTE lo que la vista previa había anunciado (mismos números, mismos tipos, mismos motivos)');
select is(
  (select array_agg(k order by k) from hecho, jsonb_object_keys(r) k),
  array['descartar', 'ejecutado', 'reencolar'],
  '5 · la forma devuelta tiene las tres claves que consume la pantalla');

-- Reencoladas
select is(
  (select count(*)::int from alertas
    where id in ('00000000-0000-0000-0000-000000440101', '00000000-0000-0000-0000-000000440111', '00000000-0000-0000-0000-000000440121',
                 '00000000-0000-0000-0000-000000440131', '00000000-0000-0000-0000-000000440133', '00000000-0000-0000-0000-000000440136',
                 '00000000-0000-0000-0000-000000440114', '00000000-0000-0000-0000-000000440125', '00000000-0000-0000-0000-000000440115',
                 '00000000-0000-0000-0000-000000440145')
      and estado = 'pendiente' and intentos = 0 and procesando_desde is null),
  10, '5 · las 10 reencoladas quedan ''pendiente'', con intentos 0 y la reserva suelta');
select is(
  (select nota_fallo from alertas where id = '00000000-0000-0000-0000-000000440101'),
  'reencolada por DO Lab440 el ' || fn_hoy_lima()::text || ' · Resend 403',
  '5 · la reencolada deja quién y cuándo, y CONSERVA la nota del fallo anterior como rastro');
select is(
  (select nota_fallo from alertas where id = '00000000-0000-0000-0000-000000440114'),
  'reencolada con ventana renovada por DO Lab440 el ' || fn_hoy_lima()::text || ' · Resend 403',
  '5 · y si fue con ventana renovada, la nota lo dice');
select is(
  (select nota_fallo from alertas where id = '00000000-0000-0000-0000-000000440145'),
  'reencolada con ventana renovada por DO Lab440 el ' || fn_hoy_lima()::text,
  '5 · sin nota anterior no queda un « · » colgando');
select is(
  (select count(*)::int from alertas where id = '00000000-0000-0000-0000-000000440111' and persona_id = '00000000-0000-0000-0000-000000440011'),
  1, '5 · el aviso de contrato sigue dirigido a DO (la trampa: se reencola, no se descarta ni se reasigna)');
select is(
  (select count(*)::int from alertas where estado = 'enviado'),
  2, '5 · nada se marcó ''enviado'': solo siguen ''enviado'' las dos que ya lo estaban antes (143 y 148)');

-- Ventana: las que cabían NO cambian de fecha; las que no, la renuevan sin perder la original
select is(
  (select count(*)::int from foto_fecha f join alertas a using (id)
    where a.id in ('00000000-0000-0000-0000-000000440101', '00000000-0000-0000-0000-000000440111', '00000000-0000-0000-0000-000000440121',
                   '00000000-0000-0000-0000-000000440131', '00000000-0000-0000-0000-000000440133', '00000000-0000-0000-0000-000000440136')
      and a.created_at = f.created_at and a.payload = f.payload),
  6, '5 · las 6 que cabían en la ventana conservan su fecha de creación y su payload tal cual');
select is(
  (select count(*)::int from foto_fecha f join alertas a using (id)
    where a.id in ('00000000-0000-0000-0000-000000440114', '00000000-0000-0000-0000-000000440125',
                   '00000000-0000-0000-0000-000000440115', '00000000-0000-0000-0000-000000440145')
      and a.created_at = now()
      and (a.payload ->> 'creada_originalmente')::timestamptz = f.created_at
      and (a.payload - 'creada_originalmente') = f.payload),
  4, '5 · las 4 con ventana renovada nacen de nuevo hoy, guardan la fecha original en el payload y no pierden nada más');
select is(
  (select count(*)::int from alertas
    where id in ('00000000-0000-0000-0000-000000440114', '00000000-0000-0000-0000-000000440125',
                 '00000000-0000-0000-0000-000000440115', '00000000-0000-0000-0000-000000440145')
      and fn_alerta_despachable(estado, intentos, procesando_desde, created_at)),
  4, '5 · y esas 4 quedan despachables (no hay fantasmas que la tarjeta cuente y nadie pueda resolver)');
select is(
  (select count(*)::int from alertas
    where estado = 'pendiente' and intentos = 0
      and fn_alerta_despachable(estado, intentos, procesando_desde, created_at - interval '1 day')
      and id in ('00000000-0000-0000-0000-000000440101', '00000000-0000-0000-0000-000000440111', '00000000-0000-0000-0000-000000440121',
                 '00000000-0000-0000-0000-000000440131', '00000000-0000-0000-0000-000000440133', '00000000-0000-0000-0000-000000440136',
                 '00000000-0000-0000-0000-000000440114', '00000000-0000-0000-0000-000000440125', '00000000-0000-0000-0000-000000440115',
                 '00000000-0000-0000-0000-000000440145')),
  10, '5 · y las 10 siguen siendo despachables MAÑANA, cuando corra el cron (la de 5 d 20 h incluida)');

-- Descartadas
select is(
  (select count(*)::int from alertas where estado = 'descartada'), 14,
  '5 · las 14 descartadas quedan ''descartada''');
select is(
  (select count(*)::int from alertas where estado = 'descartada' and intentos >= 3), 14,
  '5 · y todas con intentos >= 3 (con menos, las caducadas volverían a contar como caducadas)');
select is(
  (select array_agg(intentos order by id) from alertas where id in ('00000000-0000-0000-0000-000000440144', '00000000-0000-0000-0000-000000440146')),
  array[3, 3],
  '5 · las caducadas descartadas SUBEN a intentos 3 (venían con 0 y con 1)');
select is(
  (select count(*)::int from alertas where estado = 'descartada' and (enviado_at is not null or procesando_desde is not null)), 0,
  '5 · ninguna descartada parece enviada ni reservada');
select is((select nota_fallo from alertas where id = '00000000-0000-0000-0000-000000440102'),
  'descartada: el hecho ya no está vigente · por DO Lab440 el ' || fn_hoy_lima()::text || ' · Resend 403',
  '5 · la nota dice el motivo, quién y cuándo, y conserva el fallo anterior');
select is((select nota_fallo from alertas where id = '00000000-0000-0000-0000-000000440113'),
  'descartada: el hecho ya no está vigente · por DO Lab440 el ' || fn_hoy_lima()::text,
  '5 · sin nota anterior no queda un « · » colgando');
select is((select nota_fallo from alertas where id = '00000000-0000-0000-0000-000000440105'),
  'descartada: fuera de la ventana de despacho, pero el hecho sigue vigente · por DO Lab440 el ' || fn_hoy_lima()::text || ' · Resend 403',
  '5 · fuera de ventana y todavía vigente: la nota lo dice, para que DO decida si avisa a mano');
select is((select nota_fallo from alertas where id = '00000000-0000-0000-0000-000000440106'),
  'descartada: el hecho ya no está vigente · por DO Lab440 el ' || fn_hoy_lima()::text || ' · Resend 403',
  '5 · vieja Y ya resuelta: manda «ya no está vigente» (no se dice que sigue vigente)');

-- Cada caso terminó donde debía
select is(
  (select string_agg(right(id::text, 3), ',' order by id) from alertas
    where estado = 'descartada' and nota_fallo like 'descartada: el hecho ya no está vigente%'),
  '102,103,104,106,112,113,122,123,124,146',
  '5 · ya no vigentes: B (revisada), C (anulada), D (liquidada), Q (vieja y revisada), G (contrato renovado), H y J (cesados), K (sin récords), R (otro vence_el) y Cad3 (caducada ya revisada)');
select is(
  (select string_agg(right(id::text, 3), ',' order by id) from alertas
    where estado = 'descartada' and nota_fallo like 'descartada: fuera de la ventana%'),
  '105,132,135,144',
  '5 · fuera de ventana: E (auto-cierre vigente viejo), L2, S1 (6 d 20 h) y la caducada Cad1');

-- Las que no se podían tocar
select is(
  (select count(*)::int from foto_intocables f join alertas a using (id)
    where a.estado is not distinct from f.estado and a.intentos is not distinct from f.intentos
      and a.nota_fallo is not distinct from f.nota_fallo and a.procesando_desde is not distinct from f.procesando_desde
      and a.created_at is not distinct from f.created_at),
  7, '5 · las dos en vuelo (M y Cad6), la de intentos 2, la pendiente, la enviada, la enviada vieja y la del backlog NO se movieron');

-- ── 6 · El resumen: lo que el botón resuelve es lo que la tarjeta cuenta ────
select is(
  (select (r ->> 'fallidas_definitivas')::int from resumen_antes), 22,
  '6 · ANTES: 21 definitivas resolubles + la que está en vuelo, que el resumen también cuenta');
select is(
  (fn_alertas_despacho_resumen() ->> 'fallidas_definitivas')::int, 1,
  '6 · DESPUÉS: queda solo la que está en vuelo — las descartadas y las reencoladas salieron de «fallidas definitivas»');
select is(
  (select (r ->> 'caducadas')::int from resumen_antes), 4,
  '6 · caducadas ANTES: Cad1, Cad2, Cad3 y la que está en vuelo (la del backlog no cuenta)');
select is(
  (fn_alertas_despacho_resumen() ->> 'caducadas')::int, 1,
  '6 · caducadas DESPUÉS: solo la que está en vuelo — las caducadas SE RESUELVEN, ya no son un callejón sin salida');
select is(
  fn_alertas_despacho_resumen() -> 'motivos_definitivos', '["motivo M"]'::jsonb,
  '6 · y el motivo del fallo que ya no existe deja de mostrarse en la tarjeta');
select is(
  (select array_agg(k order by k) from jsonb_object_keys(fn_alertas_despacho_resumen()) k),
  (select array_agg(k order by k) from resumen_antes, jsonb_object_keys(r) k),
  '6 · el resumen conserva TODAS sus claves');
select is(
  (fn_alertas_despacho_resumen() ->> 'despachables')::int,
  (select (r ->> 'despachables')::int from resumen_antes) + 10,
  '6 · y las 10 reencoladas pasan a ser despachables (antes: la de intentos 2 y la pendiente fresca)');

-- ── 7 · Reencolada es despachable; descartada no ────────────────────────────
select is(
  (select fn_alerta_despachable(estado, intentos, procesando_desde, created_at)
     from alertas where id = '00000000-0000-0000-0000-000000440101'),
  true, '7 · una reencolada vuelve a ser despachable');
select is(
  (select count(*)::int from alertas
    where estado = 'descartada' and fn_alerta_despachable(estado, intentos, procesando_desde, created_at)), 0,
  '7 · y ninguna descartada es despachable');
select is(
  (select fn_alertas_reservar('00000000-0000-0000-0000-000000440105')), false,
  '7 · reservar una descartada devuelve false: el despacho no la toma');
select is(
  (select count(*)::int from fn_alertas_email_pendientes()
    where alerta_id in ('00000000-0000-0000-0000-000000440101', '00000000-0000-0000-0000-000000440111', '00000000-0000-0000-0000-000000440121',
                        '00000000-0000-0000-0000-000000440131', '00000000-0000-0000-0000-000000440133', '00000000-0000-0000-0000-000000440136',
                        '00000000-0000-0000-0000-000000440114', '00000000-0000-0000-0000-000000440125', '00000000-0000-0000-0000-000000440115',
                        '00000000-0000-0000-0000-000000440145')),
  10, '7 · y las 10 reencoladas aparecen en la lista de correos por enviar, incluidas las de ventana renovada');
select is(
  (select count(*)::int from fn_alertas_email_pendientes() p join alertas a on a.id = p.alerta_id where a.estado = 'descartada'), 0,
  '7 · y ninguna descartada aparece ahí');

-- ── 8 · Idempotencia ────────────────────────────────────────────────────────
create temporary table huella_1 as
select md5(string_agg(id::text || estado || intentos::text || coalesce(nota_fallo, '') || coalesce(procesando_desde::text, '') || created_at::text || payload::text, ',' order by id)) as h
  from alertas;

select is(
  (select fn_alertas_resolver_fallidas(true)),
  '{"ejecutado": true,
    "reencolar": {"total": 0, "por_tipo": {}, "ventana_renovada": 0},
    "descartar": {"total": 0, "por_motivo": {"fuera_de_ventana": 0, "ya_no_vigente": 0}}}'::jsonb,
  '8 · una segunda ejecución encuentra 0 y devuelve la forma completa (por_tipo vacío, por_motivo con sus dos claves)');
select is(
  (select md5(string_agg(id::text || estado || intentos::text || coalesce(nota_fallo, '') || coalesce(procesando_desde::text, '') || created_at::text || payload::text, ',' order by id)) from alertas),
  (select h from huella_1),
  '8 · y no tocó nada');

-- ── 9 · Renovar dos veces no pierde la fecha de origen ──────────────────────
-- El canal siguió caído: la reencolada (114) vuelve a agotar sus tres intentos
-- y a pasar de 7 días (OJO: 9 días y no 10, para que la fecha de esta vuelta
-- sea DISTINTA de la original y la prueba pueda ver cuál de las dos se guardó).
-- DO la vuelve a resolver.
update alertas
   set estado = 'fallido', intentos = 3, created_at = now() - interval '9 days'
 where id = '00000000-0000-0000-0000-000000440114';
select is(
  (select (fn_alertas_resolver_fallidas(true) -> 'reencolar' ->> 'ventana_renovada')::int), 1,
  '9 · la segunda resolución la renueva otra vez');
select is(
  (select (payload ->> 'creada_originalmente')::timestamptz from alertas where id = '00000000-0000-0000-0000-000000440114'),
  (select created_at from foto_fecha where id = '00000000-0000-0000-0000-000000440114'),
  '9 · y creada_originalmente sigue siendo la PRIMERA fecha, no la de la renovación anterior');
select is(
  (select count(*)::int from alertas where id = '00000000-0000-0000-0000-000000440114' and created_at = now() and estado = 'pendiente' and intentos = 0),
  1, '9 · y vuelve a la cola con otra semana');

-- ── 10 · La renovada sale de verdad ─────────────────────────────────────────
select is(
  (select fn_alertas_reservar('00000000-0000-0000-0000-000000440114')), true,
  '10 · el despacho puede reservar una de ventana renovada');
select is(
  (select estado || '/' || intentos::text from alertas where id = '00000000-0000-0000-0000-000000440114'),
  'procesando/1', '10 · y le suma su primer intento del ciclo nuevo');
-- Una definitiva que NO se debe poder reservar sigue sin poderse hasta que se resuelva
select is(
  (select fn_alertas_reservar('00000000-0000-0000-0000-000000440132')), false,
  '10 · una descartada de las viejas sigue sin poderse reservar');
select lives_ok(
  $$ select fn_marcar_alerta_resultado('00000000-0000-0000-0000-000000440114', true) $$,
  '10 · y al salir queda ''enviado'' como cualquier otra');

-- ── 11 · Resueltas las en vuelo, la tarjeta queda en cero ───────────────────
select lives_ok(
  $$ select fn_marcar_alerta_resultado('00000000-0000-0000-0000-000000440134', true);
     select fn_marcar_alerta_resultado('00000000-0000-0000-0000-000000440149', true) $$,
  '11 · las dos que estaban en vuelo terminan (el despacho de ahora mismo les puso su resultado)');
select is(
  (fn_alertas_despacho_resumen() ->> 'fallidas_definitivas')::int, 0,
  '11 · y la tarjeta queda con 0 fallidas definitivas');
select is(
  (fn_alertas_despacho_resumen() ->> 'caducadas')::int, 0,
  '11 · y con 0 caducadas: el botón resolvió exactamente lo que la tarjeta contaba');
select is(
  fn_alertas_despacho_resumen() -> 'motivos_definitivos', '[]'::jsonb,
  '11 · y sin motivos que mostrar');

-- ── 12 · Devolver el intento ────────────────────────────────────────────────
insert into alertas (id, persona_id, tipo, canal, payload, estado, intentos, enviado_at, created_at) values
  ('00000000-0000-0000-0000-000000440151', '00000000-0000-0000-0000-000000440020', 'tardanza', 'push', '{}'::jsonb, 'fallido',    3, null, now() - interval '1 day'),
  ('00000000-0000-0000-0000-000000440152', '00000000-0000-0000-0000-000000440020', 'tardanza', 'push', '{}'::jsonb, 'fallido',    0, null, now() - interval '1 day'),
  ('00000000-0000-0000-0000-000000440153', '00000000-0000-0000-0000-000000440020', 'tardanza', 'push', '{}'::jsonb, 'enviado',    2, now(), now() - interval '1 day'),
  ('00000000-0000-0000-0000-000000440154', '00000000-0000-0000-0000-000000440020', 'tardanza', 'push', '{}'::jsonb, 'pendiente',  2, null, now() - interval '1 day'),
  ('00000000-0000-0000-0000-000000440155', '00000000-0000-0000-0000-000000440020', 'tardanza', 'push', '{}'::jsonb, 'descartada', 3, null, now() - interval '1 day'),
  ('00000000-0000-0000-0000-000000440156', '00000000-0000-0000-0000-000000440020', 'tardanza', 'push', '{}'::jsonb, 'fallido',    2, null, now() - interval '1 day');
update alertas set estado = 'procesando', procesando_desde = now() where id = '00000000-0000-0000-0000-000000440156';

select lives_ok(
  $$ select fn_alertas_devolver_intento(id)
       from alertas
      where id in ('00000000-0000-0000-0000-000000440151', '00000000-0000-0000-0000-000000440152', '00000000-0000-0000-0000-000000440153',
                   '00000000-0000-0000-0000-000000440154', '00000000-0000-0000-0000-000000440155', '00000000-0000-0000-0000-000000440156') $$,
  '12 · devolver el intento de cada una no falla');
select is(
  (select intentos from alertas where id = '00000000-0000-0000-0000-000000440151'), 2,
  '12 · una ''fallido'' con 3 intentos pasa a 2: deja de ser definitiva y el despacho la reintenta');
select is(
  (select intentos from alertas where id = '00000000-0000-0000-0000-000000440152'), 0,
  '12 · nunca baja de 0');
select is(
  (select array_agg(intentos order by id) from alertas
    where id in ('00000000-0000-0000-0000-000000440153', '00000000-0000-0000-0000-000000440154',
                 '00000000-0000-0000-0000-000000440155', '00000000-0000-0000-0000-000000440156')),
  array[2, 2, 3, 2],
  '12 · y solo toca filas ''fallido'': la enviada, la pendiente, la descartada y la que está en vuelo quedan igual');
select is(
  (select fn_alertas_despacho_resumen() ->> 'fallidas_definitivas')::int, 0,
  '12 · y la que bajó a 2 ya no cuenta como definitiva');

select * from finish();
rollback;
