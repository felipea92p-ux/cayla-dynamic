-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 288_la_cola_de_alertas_se_reserva_reintenta_y_avisa.test.sql — la 0362
-- ============================================================================
-- Lo que hay que proteger acá son los tres hallazgos de la auditoría del
-- 2026-09-03/04 sobre el despacho de avisos por correo:
--   · 16 — dos ejecuciones no pueden quedarse con la misma fila: la segunda
--     reserva devuelve false;
--   · 17 — la reserva se marca ANTES de enviar, así que una fila 'procesando'
--     fresca no la toma nadie más, y una atascada más de una hora (la
--     ejecución murió) sí se vuelve a despachar;
--   · 18 — un fallo vuelve a la cola hasta el tercer intento, y al tercero
--     deja de aparecer y el resumen lo cuenta; la ventana es de 7 días, no 2.
-- Y que el resumen que lee la Bandeja cuenta cada fila UNA sola vez, no
-- cuenta el backlog de agosto que la 0354 dejó fuera a propósito (revisión
-- del 2026-09-04), y es de DO: un integrante no lo ve.
-- ============================================================================
begin;
select plan(34);

insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-000000288001', 'ZZ288', 'Sede cola de alertas', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, email, estado, fecha_ingreso) values
  -- DO: puede leer el resumen.
  ('00000000-0000-0000-0000-000000288011', 'CoAdmin', 'Lab', '00000000-0000-0000-0000-000000288001', 'admin', 'x',
   '00000000-0000-0000-0000-0000002880a1', 'coadmin@cayla.test', 'activo', '2024-01-01'),
  -- Encargada de la sede: destinataria de los avisos de auto-cierre.
  ('00000000-0000-0000-0000-000000288012', 'CoEncargada', 'Lab', '00000000-0000-0000-0000-000000288001', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000002880a2', 'coencargada@cayla.test', 'activo', '2024-01-01'),
  -- Integrante sin permiso: protagonista de los avisos y quien NO ve el resumen.
  ('00000000-0000-0000-0000-000000288013', 'CoIntegrante', 'Lab', '00000000-0000-0000-0000-000000288001', 'integrante', 'x',
   '00000000-0000-0000-0000-0000002880a3', null, 'activo', '2024-01-01');
set session_replication_role = origin;

-- Sesión de DO para todo lo que sigue, salvo la última prueba.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000002880a1', true);

-- ── 1 · El check acepta 'procesando' ────────────────────────────────────────
select lives_ok(
  $$ insert into alertas (id, persona_id, tipo, canal, payload, estado, procesando_desde, intentos)
     values ('00000000-0000-0000-0000-000000288101', '00000000-0000-0000-0000-000000288013', 'auto_cierre', 'push',
             '{"fecha":"2026-09-03"}', 'procesando', now(), 1) $$,
  '1 · el check de estado acepta ''procesando'''
);

-- ── 2 · Una pendiente aparece con intentos 0 y estado_previo pendiente ──────
insert into alertas (id, persona_id, tipo, canal, payload, created_at) values
  ('00000000-0000-0000-0000-000000288102', '00000000-0000-0000-0000-000000288013', 'auto_cierre', 'push',
   '{"fecha":"2026-09-03"}', now() - interval '1 hour');

select is(
  (select intentos from fn_alertas_email_pendientes() where alerta_id = '00000000-0000-0000-0000-000000288102'),
  0,
  '2 · una alerta pendiente aparece en la lista con intentos 0'
);
select is(
  (select estado_previo from fn_alertas_email_pendientes() where alerta_id = '00000000-0000-0000-0000-000000288102'),
  'pendiente',
  '2 · y con estado_previo ''pendiente'''
);
select is(
  (select destinatarios from fn_alertas_email_pendientes() where alerta_id = '00000000-0000-0000-0000-000000288102'),
  array['coencargada@cayla.test'],
  '2 · la Rama 1 sigue resolviendo a la encargada de la sede (nada de la 0359 se perdió)'
);

-- ── 3 · Reservar → true, y la fila queda 'procesando' con intentos 1 ────────
select is(
  fn_alertas_reservar('00000000-0000-0000-0000-000000288102'),
  true,
  '3 · la primera reserva devuelve true'
);
select is(
  (select estado from alertas where id = '00000000-0000-0000-0000-000000288102'),
  'procesando',
  '3 · y la fila queda en ''procesando'''
);
select is(
  (select intentos from alertas where id = '00000000-0000-0000-0000-000000288102'),
  1,
  '3 · con intentos = 1'
);
select isnt(
  (select procesando_desde from alertas where id = '00000000-0000-0000-0000-000000288102'),
  null,
  '3 · y procesando_desde marcado'
);

-- ── 4 · Segunda reserva inmediata → false (hallazgo 16) ─────────────────────
select is(
  fn_alertas_reservar('00000000-0000-0000-0000-000000288102'),
  false,
  '4 · una segunda reserva de la misma fila devuelve false — otra ejecución ya la tiene'
);
select is(
  (select intentos from alertas where id = '00000000-0000-0000-0000-000000288102'),
  1,
  '4 · y no sumó un intento'
);

-- ── 5 · Un fallo vuelve a la cola (hallazgo 18) ─────────────────────────────
select lives_ok(
  $$ select fn_marcar_alerta_resultado('00000000-0000-0000-0000-000000288102', false, 'intento 1: Resend respondió 502') $$,
  '5 · marcar un fallo no revienta'
);
select is(
  (select estado || '/' || intentos::text from alertas where id = '00000000-0000-0000-0000-000000288102'),
  'fallido/1',
  '5 · queda ''fallido'' con intentos 1 (marcar no cuenta intentos, reservar sí)'
);
select is(
  (select estado_previo from fn_alertas_email_pendientes() where alerta_id = '00000000-0000-0000-0000-000000288102'),
  'fallido',
  '5 · y VUELVE a aparecer en la lista, con estado_previo ''fallido'''
);

-- ── 6 · Al tercer fallo ya no aparece y el resumen la cuenta ────────────────
do $$ begin
  perform fn_alertas_reservar('00000000-0000-0000-0000-000000288102');
  perform fn_marcar_alerta_resultado('00000000-0000-0000-0000-000000288102', false, 'intento 2: Resend respondió 502');
  perform fn_alertas_reservar('00000000-0000-0000-0000-000000288102');
  perform fn_marcar_alerta_resultado('00000000-0000-0000-0000-000000288102', false, 'intento 3: Resend respondió 502');
end $$;

select is(
  (select intentos from alertas where id = '00000000-0000-0000-0000-000000288102'),
  3,
  '6 · tras tres reservas, intentos = 3'
);
select is(
  (select count(*)::int from fn_alertas_email_pendientes() where alerta_id = '00000000-0000-0000-0000-000000288102'),
  0,
  '6 · y ya no aparece en la lista: tres fallos es definitivo'
);
select is(
  fn_alertas_reservar('00000000-0000-0000-0000-000000288102'),
  false,
  '6 · ni se deja reservar'
);
select is(
  (fn_alertas_despacho_resumen() ->> 'fallidas_definitivas')::int,
  1,
  '6 · el resumen la cuenta en fallidas_definitivas'
);

-- ── 7 · Una 'procesando' atascada se reintenta; una fresca, no ──────────────
insert into alertas (id, persona_id, tipo, canal, payload, estado, procesando_desde, intentos, created_at) values
  ('00000000-0000-0000-0000-000000288103', '00000000-0000-0000-0000-000000288013', 'auto_cierre', 'push',
   '{"fecha":"2026-09-03"}', 'procesando', now() - interval '2 hours', 1, now() - interval '3 hours');

select is(
  (select estado_previo from fn_alertas_email_pendientes() where alerta_id = '00000000-0000-0000-0000-000000288103'),
  'procesando',
  '7 · una ''procesando'' de hace 2 horas aparece en la lista (la ejecución que la tomó murió)'
);
select is(
  (fn_alertas_despacho_resumen() ->> 'atascadas')::int,
  1,
  '7 · y el resumen la cuenta como atascada'
);
select is(
  fn_alertas_reservar('00000000-0000-0000-0000-000000288103'),
  true,
  '7 · y se puede reservar de nuevo'
);
-- La 288101 es la 'procesando' fresca del paso 1.
select is(
  (select count(*)::int from fn_alertas_email_pendientes() where alerta_id = '00000000-0000-0000-0000-000000288101'),
  0,
  '7 · una ''procesando'' fresca NO aparece: alguien la está mandando ahora mismo'
);

-- ── 8 · Ventana de 7 días: 5 días sí, 8 días no ─────────────────────────────
insert into alertas (id, persona_id, tipo, canal, payload, created_at) values
  ('00000000-0000-0000-0000-000000288104', '00000000-0000-0000-0000-000000288013', 'auto_cierre', 'push',
   '{"fecha":"2026-08-30"}', now() - interval '5 days'),
  ('00000000-0000-0000-0000-000000288105', '00000000-0000-0000-0000-000000288013', 'auto_cierre', 'push',
   '{"fecha":"2026-08-27"}', now() - interval '8 days');

select is(
  (select count(*)::int from fn_alertas_email_pendientes() where alerta_id = '00000000-0000-0000-0000-000000288104'),
  1,
  '8 · una alerta de hace 5 días aparece — el fin de semana sin cron ya no descarta el viernes'
);
select is(
  (select count(*)::int from fn_alertas_email_pendientes() where alerta_id = '00000000-0000-0000-0000-000000288105'),
  0,
  '8 · una de hace 8 días no aparece: es historia, no aviso'
);

-- ── 9 · Éxito → 'enviado' con enviado_at ────────────────────────────────────
do $$ begin
  perform fn_alertas_reservar('00000000-0000-0000-0000-000000288104');
  perform fn_marcar_alerta_resultado('00000000-0000-0000-0000-000000288104', true, null);
end $$;
select is(
  (select estado || '/' || (enviado_at is not null)::text || '/' || (procesando_desde is null)::text
     from alertas where id = '00000000-0000-0000-0000-000000288104'),
  'enviado/true/true',
  '9 · un envío exitoso deja ''enviado'', enviado_at marcado y la reserva suelta'
);

-- ── 10 · Cada fila cae en UNA categoría, y el backlog de agosto no cuenta ───
-- En esta base la 0354 se aplicó hoy (db reset). Se la retrocede 20 días
-- dentro de la transacción para que exista un "antes" y un "después" del
-- despacho: lo creado antes es el backlog que la 0354 dejó fuera a
-- propósito, y NO caducó — nunca fue candidato.
update migraciones_aplicadas set aplicada_at = now() - interval '20 days' where numero = 354;

insert into alertas (id, persona_id, tipo, canal, payload, estado, intentos, created_at) values
  -- backlog de agosto: pendiente de hace 34 días, anterior al despacho
  ('00000000-0000-0000-0000-000000288106', '00000000-0000-0000-0000-000000288013', 'auto_cierre', 'push',
   '{"fecha":"2026-08-01"}', 'pendiente', 0, now() - interval '34 days'),
  -- definitiva vieja: tres fallos y más de 7 días — cuenta UNA vez
  ('00000000-0000-0000-0000-000000288107', '00000000-0000-0000-0000-000000288013', 'auto_cierre', 'push',
   '{"fecha":"2026-08-25"}', 'fallido', 3, now() - interval '10 days'),
  -- una pendiente fresca, para que despachables no sea 0 por casualidad
  ('00000000-0000-0000-0000-000000288109', '00000000-0000-0000-0000-000000288013', 'auto_cierre', 'push',
   '{"fecha":"2026-09-04"}', 'pendiente', 0, now());
-- murió en su tercer intento: 'procesando' atascada con intentos 3
insert into alertas (id, persona_id, tipo, canal, payload, estado, intentos, procesando_desde, created_at) values
  ('00000000-0000-0000-0000-000000288108', '00000000-0000-0000-0000-000000288013', 'auto_cierre', 'push',
   '{"fecha":"2026-09-04"}', 'procesando', 3, now() - interval '2 hours', now() - interval '3 hours');

-- En este punto: 288102 fallido/3 (paso 6), 288105 pendiente de 8 días (paso 8),
-- 288104 enviada (paso 9), 288103 reservada fresca (paso 7), 288101 fresca (paso 1).
select is(
  (fn_alertas_despacho_resumen() ->> 'fallidas_definitivas')::int,
  3,
  '10 · definitivas: la de tres fallos, la vieja de tres fallos y la que murió en su tercer intento'
);
select is(
  (fn_alertas_despacho_resumen() ->> 'caducadas')::int,
  1,
  '10 · caducadas: solo la de 8 días — la de agosto es anterior al despacho y la definitiva vieja ya está contada'
);
select is(
  (fn_alertas_despacho_resumen() ->> 'atascadas')::int,
  0,
  '10 · la que murió en su tercer intento NO es atascada: nadie la va a retomar'
);
select is(
  (select count(*)::int from fn_alertas_email_pendientes() where alerta_id = '00000000-0000-0000-0000-000000288108'),
  0,
  '10 · y tampoco aparece en la lista del despacho'
);
select is(
  (fn_alertas_despacho_resumen() ->> 'despachables')::int,
  1,
  '10 · despachables: solo la pendiente fresca'
);
select isnt(
  (fn_alertas_despacho_resumen() ->> 'ultimo_envio_at'),
  null,
  '10 · ultimo_envio_at trae la fecha del envío del paso 9'
);
select is(
  fn_alertas_despacho_resumen() -> 'motivos_definitivos',
  '["intento 3: Resend respondió 502"]'::jsonb,
  '10 · motivos_definitivos dice POR QUÉ falló la definitiva (las sin nota no aportan)'
);

-- ── 11 · La Rama 2 (contrato/vacaciones) también devuelve intentos y estado ──
insert into alertas (id, persona_id, tipo, canal, payload, estado, intentos, created_at) values
  ('00000000-0000-0000-0000-000000288110', '00000000-0000-0000-0000-000000288011', 'contrato_por_vencer', 'push',
   '{"persona":"CoIntegrante Lab","sede":"ZZ288","dias_restantes":10}', 'fallido', 2, now() - interval '1 day');
select is(
  (select intentos::text || '/' || estado_previo || '/' || destinatarios[1]
     from fn_alertas_email_pendientes() where alerta_id = '00000000-0000-0000-0000-000000288110'),
  '2/fallido/coadmin@cayla.test',
  '11 · un contrato por vencer fallido dos veces vuelve con intentos 2, estado_previo fallido y su destinatario DO'
);

-- ── 12 · Un procesando_desde nulo no vuelve invisible la fila ───────────────
select is(
  fn_alerta_despachable('procesando', 1, null, now()),
  true,
  '12 · ''procesando'' sin procesando_desde (solo por edición a mano) cuenta como atascada desde siempre'
);

-- ── 13 · El resumen es de DO ────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000002880a3', true);
select throws_ok(
  $$ select fn_alertas_despacho_resumen() $$,
  'Solo Desarrollo Organizacional puede ver el estado del despacho de avisos.',
  '13 · un integrante no puede leer el resumen del despacho'
);

select * from finish();
rollback;
