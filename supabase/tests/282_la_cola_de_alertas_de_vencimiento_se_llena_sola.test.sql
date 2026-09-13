-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 282_la_cola_de_alertas_de_vencimiento_se_llena_sola.test.sql — la 0356 de punta a punta
-- ============================================================================
-- Lo que hay que proteger acá no es que se pueda insertar una fila: es que
-- (a) funciona SIN SESIÓN — la forma real en que la va a llamar pg_cron, no
-- como la llamaría una pantalla —, (b) solo alerta a quien está DENTRO de la
-- ventana de 30 días, ni antes ni a quien ya venció, (c) alerta a cada
-- admin/líder DO activo con correo y a nadie más (ni a quien no tiene
-- correo, ni a la encargada de sede), y (d) es idempotente: correrla dos
-- veces no duplica la misma alerta.
-- ============================================================================
begin;
select plan(8);

insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-000000009301', 'ZZAL2', 'Sede alertas dos', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, email, fecha_fin_contrato) values
  -- DO con correo: debe recibir la alerta.
  ('00000000-0000-0000-0000-000000009401', 'AlaAdmin', 'Lab', '00000000-0000-0000-0000-000000009301', 'admin', 'x',
   '00000000-0000-0000-0000-000000009501', '2023-01-01', 'admin@cayla.test', null),
  -- DO sin correo: no hay a dónde mandarle nada.
  ('00000000-0000-0000-0000-000000009402', 'AlaLider', 'Lab', '00000000-0000-0000-0000-000000009301', 'lider_do', 'x',
   '00000000-0000-0000-0000-000000009502', '2023-01-01', null, null),
  -- Encargada de sede: opera el día a día, pero esto ya lo ve en vivo en Ausencias.
  ('00000000-0000-0000-0000-000000009403', 'AlaEncargada', 'Lab', '00000000-0000-0000-0000-000000009301', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-000000009503', '2023-01-01', 'encargada@cayla.test', null),
  -- Contrato dentro de la ventana de 30 días: debe alertar.
  ('00000000-0000-0000-0000-000000009404', 'AlaPorVencer', 'Lab', '00000000-0000-0000-0000-000000009301', 'integrante', 'x',
   '00000000-0000-0000-0000-000000009504', '2023-01-01', null, (fn_hoy_lima() + 10)),
  -- Contrato lejos de la ventana: no debe alertar todavía.
  ('00000000-0000-0000-0000-000000009405', 'AlaLejos', 'Lab', '00000000-0000-0000-0000-000000009301', 'integrante', 'x',
   '00000000-0000-0000-0000-000000009505', '2023-01-01', null, (fn_hoy_lima() + 90)),
  -- Contrato ya vencido: "por vencer" no es "ya venció" — eso se ve directo en el Dashboard.
  ('00000000-0000-0000-0000-000000009406', 'AlaVencido', 'Lab', '00000000-0000-0000-0000-000000009301', 'integrante', 'x',
   '00000000-0000-0000-0000-000000009506', '2023-01-01', null, (fn_hoy_lima() - 5));
set session_replication_role = origin;

-- ── Sin ninguna sesión abierta: exactamente como la llama pg_cron ──────────
select is(fn_es_admin_o_lider(), false, 'de fondo: sin sesión, fn_es_admin_o_lider() da false (no null)');
select is(fn_persona_actual_id(), null, 'de fondo: sin sesión, no hay persona actual');

select lives_ok(
  $$ select fn_generar_alertas_vencimiento() $$,
  'genera alertas sin ninguna sesión abierta — la forma real en que la llama pg_cron'
);

select is(
  (select count(*)::int from alertas where tipo = 'contrato_por_vencer'),
  1,
  'una sola alerta: ni la lejana ni la vencida generaron fila'
);

select is(
  (select payload ->> 'persona' from alertas where tipo = 'contrato_por_vencer'),
  'AlaPorVencer Lab',
  'y es exactamente la persona dentro de la ventana de 30 días'
);

select is(
  (select persona_id from alertas where tipo = 'contrato_por_vencer'),
  '00000000-0000-0000-0000-000000009401'::uuid,
  'la alerta queda a nombre del admin con correo — no del líder sin correo ni de la encargada'
);

-- ── Idempotente: correrla de nuevo no duplica ────────────────────────────
select lives_ok(
  $$ select fn_generar_alertas_vencimiento() $$,
  'se puede correr una segunda vez sin fallar'
);

select is(
  (select count(*)::int from alertas where tipo = 'contrato_por_vencer'),
  1,
  'y sigue habiendo una sola fila: el mismo hecho no se vuelve a encolar'
);

select * from finish();
rollback;
