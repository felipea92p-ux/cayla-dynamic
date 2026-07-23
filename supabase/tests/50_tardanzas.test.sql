-- ============================================================================
-- 50_tardanzas.test.sql — Blindaje de la detección de tardanzas
-- ============================================================================
-- Esta es la lógica que alimenta el semáforo disciplinario y los memos. Un error
-- acá no cuesta plata: cuesta una INJUSTICIA (un memo mal disparado en el legajo
-- de una persona, o una tardanza real que nadie ve). Reglas que fija la prueba
-- (fn_tardanzas_resumen, def final mig 0067 con fecha de corte):
--   · Con 2 tardanzas en el mes aparece como AVISO; con 3 o más, AMONESTACIÓN.
--   · Con 1 sola, no aparece (no se molesta a nadie por una).
--   · Una tardanza JUSTIFICADA no cuenta.
--   · NO SANCIONAR DOS VECES: las tardanzas ya cubiertas por un memo firmado no
--     se vuelven a alertar.
--   · Quien cobra sueldo fijo no se mide (no se le controla asistencia).
--
-- Gracias a la mig 0067 le pasamos una fecha de corte fija (2026-07-23) → la
-- prueba es determinista sin importar qué día corra el CI. Exige sesión de admin,
-- que simulamos igual que en la reversa. Todo en begin/rollback.
-- ============================================================================
begin;
select plan(8);

-- ── Semilla ────────────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000ff', 'ZZTEST', 'Sede de laboratorio', true);

-- Persona admin + sesión simulada (salta la FK a auth.users con replica)
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, rol, auth_user_id)
values ('00000000-0000-0000-0000-0000000000aa', 'AdminPrueba', 'Laboratorio',
        '00000000-0000-0000-0000-0000000000ff', 'test-hash', 'admin',
        '00000000-0000-0000-0000-0000000000ab');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000ab', true);

-- Personas de laboratorio (activas, en planilla, sin sueldo fijo por defecto)
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, sueldo_fijo) values
  ('00000000-0000-0000-0000-0000000000ca', 'PruebaTA', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash', '2020-01-01', false),
  ('00000000-0000-0000-0000-0000000000cb', 'PruebaTB', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash', '2020-01-01', false),
  ('00000000-0000-0000-0000-0000000000cc', 'PruebaTC', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash', '2020-01-01', false),
  ('00000000-0000-0000-0000-0000000000cd', 'PruebaTD', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash', '2020-01-01', false),
  ('00000000-0000-0000-0000-0000000000ce', 'PruebaTE', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash', '2020-01-01', false),
  ('00000000-0000-0000-0000-0000000000cf', 'PruebaTF', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash', '2020-01-01', true);

-- Tardanzas (minutos_tarde > 0) en julio 2026. TA: 3 días; TB: 2; TC: 1;
-- TD: 3 (las justificaremos); TE: 3 (ya cubiertas por un memo); TF: 3 (sueldo fijo).
insert into jornadas (persona_id, fecha, minutos_tarde) values
  ('00000000-0000-0000-0000-0000000000ca', '2026-07-01', 10),
  ('00000000-0000-0000-0000-0000000000ca', '2026-07-02', 10),
  ('00000000-0000-0000-0000-0000000000ca', '2026-07-03', 10),
  ('00000000-0000-0000-0000-0000000000cb', '2026-07-01', 10),
  ('00000000-0000-0000-0000-0000000000cb', '2026-07-02', 10),
  ('00000000-0000-0000-0000-0000000000cc', '2026-07-01', 10),
  ('00000000-0000-0000-0000-0000000000cd', '2026-07-01', 10),
  ('00000000-0000-0000-0000-0000000000cd', '2026-07-02', 10),
  ('00000000-0000-0000-0000-0000000000cd', '2026-07-03', 10),
  ('00000000-0000-0000-0000-0000000000ce', '2026-07-01', 10),
  ('00000000-0000-0000-0000-0000000000ce', '2026-07-02', 10),
  ('00000000-0000-0000-0000-0000000000ce', '2026-07-03', 10),
  ('00000000-0000-0000-0000-0000000000cf', '2026-07-01', 10),
  ('00000000-0000-0000-0000-0000000000cf', '2026-07-02', 10),
  ('00000000-0000-0000-0000-0000000000cf', '2026-07-03', 10);

-- TD: sus 3 tardanzas están JUSTIFICADAS
insert into tardanzas_justificadas (persona_id, fecha, motivo, creado_por) values
  ('00000000-0000-0000-0000-0000000000cd', '2026-07-01', 'salud', '00000000-0000-0000-0000-0000000000aa'),
  ('00000000-0000-0000-0000-0000000000cd', '2026-07-02', 'salud', '00000000-0000-0000-0000-0000000000aa'),
  ('00000000-0000-0000-0000-0000000000cd', '2026-07-03', 'salud', '00000000-0000-0000-0000-0000000000aa');

-- TE: ya tiene un memo de tardanza FIRMADO que cubre hasta el 03/07 → esas
-- tardanzas no deben volver a alertar (non bis in idem).
insert into expediente_disciplinario (persona_id, tipo_causal, nivel, estado, periodo_hasta, firmante_id, firmado_at, correlativo, creado_por)
values ('00000000-0000-0000-0000-0000000000ce', 'tardanza', 'amonestacion', 'firmado', '2026-07-03',
        '00000000-0000-0000-0000-0000000000aa', now(), 'TEST-TARD-001', '00000000-0000-0000-0000-0000000000aa');

-- Resultado, con fecha de corte fija
create temp table _tard as
  select * from fn_tardanzas_resumen('2026-07-23'::date);

-- ── Umbral: 3 tardanzas → amonestación ──────────────────────────────────────
select is(
  (select tardanzas_mes from _tard where persona_id = '00000000-0000-0000-0000-0000000000ca'),
  3, 'TA: 3 tardanzas en el mes se cuentan como 3');
select is(
  (select umbral from _tard where persona_id = '00000000-0000-0000-0000-0000000000ca'),
  'amonestacion', 'TA: 3 tardanzas llegan a amonestación');

-- ── Umbral: 2 tardanzas → aviso ─────────────────────────────────────────────
select is(
  (select tardanzas_mes from _tard where persona_id = '00000000-0000-0000-0000-0000000000cb'),
  2, 'TB: 2 tardanzas en el mes se cuentan como 2');
select is(
  (select umbral from _tard where persona_id = '00000000-0000-0000-0000-0000000000cb'),
  'aviso', 'TB: 2 tardanzas se quedan en aviso (aún no amonestación)');

-- ── Con 1 sola no se molesta a nadie ────────────────────────────────────────
select is(
  (select count(*)::int from _tard where persona_id = '00000000-0000-0000-0000-0000000000cc'),
  0, 'TC: con 1 sola tardanza no aparece en la alerta');

-- ── Una tardanza justificada no cuenta ──────────────────────────────────────
select is(
  (select count(*)::int from _tard where persona_id = '00000000-0000-0000-0000-0000000000cd'),
  0, 'TD: 3 tardanzas justificadas → no aparece (justificar las descuenta)');

-- ── No sancionar dos veces ──────────────────────────────────────────────────
select is(
  (select count(*)::int from _tard where persona_id = '00000000-0000-0000-0000-0000000000ce'),
  0, 'TE: tardanzas ya cubiertas por un memo firmado no se vuelven a alertar');

-- ── Sueldo fijo no se mide ──────────────────────────────────────────────────
select is(
  (select count(*)::int from _tard where persona_id = '00000000-0000-0000-0000-0000000000cf'),
  0, 'TF: quien cobra sueldo fijo no aparece en el control de tardanzas');

select * from finish();
rollback;
