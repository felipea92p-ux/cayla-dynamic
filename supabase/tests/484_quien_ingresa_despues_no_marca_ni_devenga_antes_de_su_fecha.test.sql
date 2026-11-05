-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 484_quien_ingresa_despues_no_marca_ni_devenga_antes_de_su_fecha.test.sql — 0594
-- ============================================================================
-- Defiende que se pueda registrar un ingreso FUTURO sin que nadie marque ni
-- cobre antes de su fecha, y sin tocar la historia de quien ya ingresó.
--
-- Las fechas se calculan desde `fn_hoy_lima()` y no están escritas: una prueba
-- con fecha fija se pudre el día que esa fecha deja de ser futura.
--
-- Qué fija, en orden de importancia:
--   · Quien ingresa mañana no puede marcar hoy (el disparador), y el mismo día
--     de su ingreso ya sí.
--   · A quien YA ingresó no se le reescribe la historia: una marca anterior a su
--     ingreso sigue entrando, como siempre. (El control del disparador.)
--   · No se puede mover el ingreso a una fecha futura si ya hay horas marcadas
--     antes de ella; a una fecha pasada sí, como antes.
--   · El terminal no ofrece a quien todavía no ingresó, y lo ofrece cuando llega.
--   · Las subvenciones no cuentan a quien aún no ingresó (antes salían negativas).
-- ============================================================================
begin;
select plan(16);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000484001', 'ZZ484', 'Sede de laboratorio 484', true);

set session_replication_role = replica;
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000484a01', 'admin-484@local'),
  ('00000000-0000-0000-0000-000000484a02', 'terminal-484@local'),
  ('00000000-0000-0000-0000-000000484a03', 'practicante-484@local');
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000484b01', 'Admin484', 'Lab', '00000000-0000-0000-0000-000000484001', 'admin', 'x',
   '00000000-0000-0000-0000-000000484a01', fn_hoy_lima() - 400);
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  -- Se le pondrá el ingreso de mañana. No tiene horas.
  ('00000000-0000-0000-0000-000000484b02', 'FuturoSolo',     'Lab', '00000000-0000-0000-0000-000000484001', 'x', fn_hoy_lima() - 30, 'planilla'),
  -- Tiene una jornada con horas hace 3 días: su ingreso no puede pasar a mañana.
  ('00000000-0000-0000-0000-000000484b03', 'ConHoras',       'Lab', '00000000-0000-0000-0000-000000484001', 'x', fn_hoy_lima() - 30, 'planilla'),
  -- Ya ingresó (hace 10 días). La historia anterior a su ingreso no se toca.
  ('00000000-0000-0000-0000-000000484b04', 'YaIngreso',      'Lab', '00000000-0000-0000-0000-000000484001', 'x', fn_hoy_lima() - 10, 'planilla'),
  -- Ingresa HOY: desde hoy ya marca.
  ('00000000-0000-0000-0000-000000484b05', 'IngresaHoy',     'Lab', '00000000-0000-0000-0000-000000484001', 'x', fn_hoy_lima(),      'planilla'),
  -- Para el roster: uno que ya ingresó y uno que ingresa mañana (los dos en la sede del terminal).
  ('00000000-0000-0000-0000-000000484b06', 'RosterYa',       'Lab', '00000000-0000-0000-0000-000000484001', 'x', fn_hoy_lima() - 5,  'planilla'),
  ('00000000-0000-0000-0000-000000484b07', 'RosterManana',   'Lab', '00000000-0000-0000-0000-000000484001', 'x', fn_hoy_lima() + 1,  'planilla');
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo) values
  -- Practicantes: uno que ingresa en 10 días (hasta hoy, nada devengado) y uno que ya lleva 100 días.
  ('00000000-0000-0000-0000-000000484b08', 'PractFuturo', 'Lab', '00000000-0000-0000-0000-000000484001', 'x',
   '00000000-0000-0000-0000-000000484a03', fn_hoy_lima() + 10, 'practicante'),
  ('00000000-0000-0000-0000-000000484b09', 'PractYa',     'Lab', '00000000-0000-0000-0000-000000484001', 'x',
   null, fn_hoy_lima() - 100, 'practicante');
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde) values
  ('00000000-0000-0000-0000-000000484b08', 'colibri', 1130, fn_hoy_lima() - 400),
  ('00000000-0000-0000-0000-000000484b09', 'colibri', 1130, fn_hoy_lima() - 400);
insert into jornadas (persona_id, fecha, sede_id, horas_trabajadas, estado, entrada_ts, salida_final_ts) values
  ('00000000-0000-0000-0000-000000484b03', fn_hoy_lima() - 3, '00000000-0000-0000-0000-000000484001', 6, 'cerrada',
   ((fn_hoy_lima() - 3)::text || ' 09:00-05')::timestamptz, ((fn_hoy_lima() - 3)::text || ' 15:00-05')::timestamptz);
insert into terminales (id, sede_id, nombre_dispositivo, activo, auth_user_id)
values ('00000000-0000-0000-0000-000000484e01', '00000000-0000-0000-0000-000000484001', 'Mac mini 484', true,
        '00000000-0000-0000-0000-000000484a02');
set session_replication_role = origin;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000484a01', true);

-- ── 1-2 · Quien ingresa mañana se puede registrar hoy ──────────────────────
select lives_ok(
  $$ select fn_set_fecha_ingreso('00000000-0000-0000-0000-000000484b02', fn_hoy_lima() + 1) $$,
  'PERMITIDO · registrar hoy que alguien ingresa mañana (antes: «no puede ser futura»)');
select is(
  (select fecha_ingreso from personas where id = '00000000-0000-0000-0000-000000484b02'),
  fn_hoy_lima() + 1,
  'GUARDADO · la fecha quedó como la pidió quien la registró');

-- ── 3 · Solo el tope contra el error de tipeo ──────────────────────────────
select throws_ok(
  $$ select fn_set_fecha_ingreso('00000000-0000-0000-0000-000000484b02', fn_hoy_lima() + 400) $$,
  'La fecha de ingreso está a más de un año de hoy. Revisa el año.',
  'BLOQUEADO · a más de un año de hoy es un error de tipeo, no un ingreso');

-- ── 4-5 · Con horas ya marcadas, no hay ingreso futuro; uno pasado sí ──────
select throws_ok(
  $$ select fn_set_fecha_ingreso('00000000-0000-0000-0000-000000484b03', fn_hoy_lima() + 1) $$,
  'Esta persona ya tiene horas marcadas antes del ' || to_char(fn_hoy_lima() + 1, 'DD/MM/YYYY')
    || '. Su ingreso no puede ser posterior a su primera jornada.',
  'BLOQUEADO · quien ya trabajó no «ingresa» mañana: esas horas se seguirían pagando desde antes');
select lives_ok(
  $$ select fn_set_fecha_ingreso('00000000-0000-0000-0000-000000484b03', fn_hoy_lima() - 5) $$,
  'CONTROL · mover el ingreso a una fecha pasada se comporta como siempre (el candado nuevo solo mira ingresos futuros)');

-- ── 6 · Quien ingresa mañana no puede marcar hoy ───────────────────────────
select throws_ok(
  $$ insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca)
     values (gen_random_uuid(), '00000000-0000-0000-0000-000000484b02', '00000000-0000-0000-0000-000000484001', 'entrada', now()) $$,
  'No se puede registrar una marca del ' || to_char(fn_hoy_lima(), 'DD/MM/YYYY')
    || ': esa persona ingresa el ' || to_char(fn_hoy_lima() + 1, 'DD/MM/YYYY') || '.',
  'BLOQUEADO · una marca anterior al ingreso no entra, venga por donde venga');

-- ── 7 · El mismo día de su ingreso ya marca ────────────────────────────────
select lives_ok(
  $$ insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca)
     values (gen_random_uuid(), '00000000-0000-0000-0000-000000484b05', '00000000-0000-0000-0000-000000484001', 'entrada', now()) $$,
  'PERMITIDO · el día de su ingreso la persona ya marca');

-- ── 8 · CONTROL: a quien ya ingresó no se le reescribe la historia ─────────
-- YaIngreso entró hace 10 días y se le carga una marca de hace 20: DO corrige así
-- cada día cuando un ingreso quedó mal puesto. El disparador no puede frenarlo.
select lives_ok(
  $$ insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca)
     values (gen_random_uuid(), '00000000-0000-0000-0000-000000484b04', '00000000-0000-0000-0000-000000484001', 'entrada',
             ((fn_hoy_lima() - 20)::text || ' 09:00-05')::timestamptz) $$,
  'CONTROL · una marca anterior al ingreso de quien YA ingresó sigue entrando: la historia no se reescribe');

-- ── 9-11 · El terminal ──────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000484a02', true);
set role authenticated;
select is_empty(
  $$ select 1 from terminal_roster where nombres = 'RosterManana' $$,
  'TERMINAL · quien ingresa mañana no aparece hoy en el roster de marcaje');
select is(
  (select count(*)::int from terminal_roster where nombres = 'RosterYa'),
  1,
  'CONTROL · quien ya ingresó sigue apareciendo');
reset role;

-- El mismo, cuando su fecha llega, aparece: la exclusión venía de la fecha y de nada más.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000484a01', true);
select fn_set_fecha_ingreso('00000000-0000-0000-0000-000000484b07', fn_hoy_lima());
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000484a02', true);
set role authenticated;
select is(
  (select count(*)::int from terminal_roster where nombres = 'RosterManana'),
  1,
  'CONTROL · el mismo, con ingreso de hoy, sí aparece: la exclusión venía solo de su fecha');
reset role;

-- ── 12-14 · Las subvenciones de practicante ─────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000484a01', true);
select is(
  (select count(*)::int
     from jsonb_array_elements(fn_subvenciones_practicante(fn_hoy_lima()) -> 'personas') e
    where e ->> 'persona_id' = '00000000-0000-0000-0000-000000484b08'),
  0,
  'SUBVENCIONES · quien ingresa en 10 días no devenga nada (antes: salía en negativo)');
select is(
  (select count(*)::int
     from jsonb_array_elements(fn_subvenciones_practicante(fn_hoy_lima()) -> 'personas') e
    where e ->> 'persona_id' = '00000000-0000-0000-0000-000000484b09'),
  1,
  'CONTROL · el practicante que ya lleva 100 días sí está');
select is(
  (select count(*)::int
     from jsonb_array_elements(fn_subvenciones_practicante(fn_hoy_lima()) -> 'personas') e
    where (e ->> 'media_sub_saldo')::numeric < 0 or (e ->> 'descanso_saldo')::numeric < 0),
  0,
  'NINGÚN NEGATIVO · ninguna fila sale con saldo menor que cero');

-- ── 15 · «Mis subvenciones»: la propia practicante que aún no ingresó ──────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000484a03', true);
select is(
  (select count(*)::int from fn_mis_subvenciones_practicante()),
  0,
  'MIS SUBVENCIONES · la practicante que todavía no ingresó no ve un devengado negativo: no ve nada');

-- ── 16 · El registro es el de esta migración, no otra con su número ────────
select is(
  (select nombre from migraciones_aplicadas where numero = 594),
  'quien_ingresa_despues_no_marca_ni_devenga_antes_de_su_fecha',
  'REGISTRO · el 594 es esta migración');

select * from finish();
rollback;
