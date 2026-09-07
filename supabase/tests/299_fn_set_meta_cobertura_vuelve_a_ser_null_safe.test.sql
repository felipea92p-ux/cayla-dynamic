-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 299_fn_set_meta_cobertura_vuelve_a_ser_null_safe.test.sql — la 0379
-- ============================================================================
-- Antes de la 0379, una persona CESADA (sesión de Auth todavía viva) colaba
-- el guard de fn_set_meta_cobertura: desde la 0374, fn_rol_actual() de un
-- cesado da NULL, y «NULL not in (...)» también da NULL — un «if null then
-- raise» nunca dispara. Esta prueba fija que ahora SÍ dispara, y que quien
-- ya estaba autorizado legítimamente (admin, líder DO) no pierde acceso.
-- ============================================================================
begin;
select plan(4);

insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-000000009801', 'ZZMC1', 'Sede meta cobertura', true, 'tienda');

set session_replication_role = replica;
insert into personas
  (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado, fecha_cese) values
  -- La cesada: sesión de Auth viva, fn_rol_actual() ya es NULL desde la 0374.
  ('00000000-0000-0000-0000-000000009802', 'MetaCesada', 'Lab',
   '00000000-0000-0000-0000-000000009801', 'integrante', 'x',
   '00000000-0000-0000-0000-000000009812', '2023-01-01', 'inactivo', '2026-08-01'),
  -- Control: un admin legítimo, activo — su acceso no debe perderse.
  ('00000000-0000-0000-0000-000000009803', 'MetaAdmin', 'Lab',
   '00000000-0000-0000-0000-000000009801', 'admin', 'x',
   '00000000-0000-0000-0000-000000009813', '2022-01-01', 'activo', null),
  -- Control: una integrante activa sin permiso — su rechazo no debe cambiar.
  ('00000000-0000-0000-0000-000000009804', 'MetaIntegrante', 'Lab',
   '00000000-0000-0000-0000-000000009801', 'integrante', 'x',
   '00000000-0000-0000-0000-000000009814', '2022-01-01', 'activo', null);
set session_replication_role = origin;

-- ── El mecanismo: el rol de la cesada ya es NULL ──────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000009812', true);
select is(
  (select fn_rol_actual()), null,
  'MECANISMO · desde la 0374, fn_rol_actual() de una persona cesada es NULL — no su rol real'
);

-- ── Una persona cesada ya NO puede definir la meta de cobertura ──────────
select throws_like($$
  select fn_set_meta_cobertura('00000000-0000-0000-0000-000000009801', 1, 20) $$,
  '%Solo un administrador%',
  'META · una persona cesada, con sesión viva, ya no puede definir la meta de cobertura'
);

-- ── Control: una integrante activa sin permiso sigue bloqueada ──────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000009814', true);
select throws_like($$
  select fn_set_meta_cobertura('00000000-0000-0000-0000-000000009801', 1, 20) $$,
  '%Solo un administrador%',
  'CONTROL · una integrante activa sin permiso sigue bloqueada'
);

-- ── Control: el admin legítimo conserva su acceso ────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000009813', true);
select lives_ok(
  $$ select fn_set_meta_cobertura('00000000-0000-0000-0000-000000009801', 1, 20) $$,
  'CONTROL · un admin activo conserva su acceso para definir la meta de cobertura'
);

select * from finish();
rollback;
