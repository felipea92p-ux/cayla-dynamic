-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 298_una_persona_cesada_deja_de_colarse_por_el_or_suelto.test.sql — la 0376
-- ============================================================================
-- Antes de la 0376, una persona CESADA (rol distinto de supervisor_sede,
-- sesión de Auth todavía viva) colaba el guard de fn_vacaciones_saldo y de
-- fn_marca_apartada_resolver: desde la 0374, fn_rol_actual() de un cesado da
-- NULL, y «not(null and true)» también da NULL — un «if null then raise»
-- nunca dispara. Esta prueba fija que ahora SÍ dispara, y que nadie que ya
-- estaba autorizado legítimamente perdió su acceso.
-- ============================================================================
begin;
select plan(6);

insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-000000009901', 'ZZCE1', 'Sede cesados uno', true, 'tienda');

set session_replication_role = replica;
insert into personas
  (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado, fecha_cese) values
  -- La víctima: activa, cualquiera puede ver su propio saldo o el de su
  -- encargada — es a ella a quien un excolega cesado no debería poder leer.
  ('00000000-0000-0000-0000-000000009902', 'CeVictima', 'Lab',
   '00000000-0000-0000-0000-000000009901', 'integrante', 'x',
   '00000000-0000-0000-0000-000000009912', '2024-01-01', 'activo', null),
  -- La cesada: mismo sede que la víctima, rol NO supervisor_sede — antes de
  -- la 0374 esto bloqueaba solo (rol real ≠ supervisor_sede → FALSE). Su
  -- sesión de Auth sigue viva, y fn_cesar_persona nunca borra sede_base_id.
  ('00000000-0000-0000-0000-000000009903', 'CeCesada', 'Lab',
   '00000000-0000-0000-0000-000000009901', 'integrante', 'x',
   '00000000-0000-0000-0000-000000009913', '2023-01-01', 'inactivo', '2026-08-01'),
  -- Control: la encargada LEGÍTIMA de la misma sede — su acceso no debe
  -- perderse con este cambio.
  ('00000000-0000-0000-0000-000000009904', 'CeEncargada', 'Lab',
   '00000000-0000-0000-0000-000000009901', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-000000009914', '2022-01-01', 'activo', null);
set session_replication_role = origin;

-- ── El mecanismo, en una sola línea: el rol de la cesada ya es NULL ───────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000009913', true);
select is(
  (select fn_rol_actual()), null,
  'MECANISMO · desde la 0374, fn_rol_actual() de una persona cesada es NULL — no su rol real'
);

-- ── fn_vacaciones_saldo: la cesada ya NO puede leer a su excolega ─────────
select throws_like($$
  select fn_vacaciones_saldo('00000000-0000-0000-0000-000000009902', null) $$,
  '%saldo de vacaciones de otra persona%',
  'SALDO · una persona cesada, con sesión viva, ya no puede leer el saldo de un excolega de su antigua sede'
);

-- ── fn_marca_apartada_resolver: tampoco puede resolver una de su excolega ─
select set_config('request.jwt.claim.sub', '', true);
select fn_marca_apartada_reportar(
  '00000000-0000-0000-0000-00000000ce01'::uuid,
  '00000000-0000-0000-0000-000000009902'::uuid,
  'entrada'::tipo_marca, '2026-08-20 08:00:00-05'::timestamptz,
  null, 'rechazada seis veces');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000009913', true);
select throws_like($$
  select fn_marca_apartada_resolver(
    (select id from marcas_apartadas where client_uuid = '00000000-0000-0000-0000-00000000ce01'),
    'improcedente', 'no debería poder resolver esto') $$,
  '%otra sede%',
  'APARTADA · una persona cesada tampoco puede resolver una marca apartada de un excolega'
);

-- ── Y la marca sigue sin resolver: el intento bloqueado no tocó nada ──────
select is(
  (select resuelta_at from marcas_apartadas where client_uuid = '00000000-0000-0000-0000-00000000ce01'),
  null,
  'APARTADA · el intento bloqueado no dejó la marca a medio resolver'
);

-- ── Control: la encargada LEGÍTIMA de la sede conserva su acceso ─────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000009914', true);
select lives_ok($$
  select fn_vacaciones_saldo('00000000-0000-0000-0000-000000009902', null) $$,
  'CONTROL · la encargada activa de la misma sede sigue pudiendo ver el saldo — el arreglo no le quitó nada'
);

select lives_ok($$
  select fn_marca_apartada_resolver(
    (select id from marcas_apartadas where client_uuid = '00000000-0000-0000-0000-00000000ce01'),
    'improcedente', 'la encargada sí puede resolverla') $$,
  'CONTROL · y sigue pudiendo resolver una marca apartada de su sede'
);

select * from finish();
rollback;
