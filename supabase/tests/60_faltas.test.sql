-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 60_faltas.test.sql — Blindaje de la detección de faltas (ausencias)
-- ============================================================================
-- La función más compleja del sistema: define qué día "le tocaba" a la persona
-- (cruzando horario asignado y turnos), y solo esos días cuentan. Un día
-- programado sin marca es una falta; con marca es presencia; con justificación o
-- vacaciones no cuenta. Luego clasifica: verde / ámbar / rojo. Reglas que fija la
-- prueba (fn_faltas_resumen, def final mig 0067 con fecha de corte):
--   · Días consecutivos de falta: 3 → ámbar, 4 o más → rojo.
--   · Por debajo de los umbrales → verde → no aparece en la alerta.
--   · Un día con MARCA de entrada es presencia, no falta.
--   · Un día JUSTIFICADO no es falta.
--   · Un día SIN horario asignado no puede ser falta (no le tocaba).
--
-- Con la mig 0067 le pasamos fecha de corte fija (2026-07-23) → determinista. La
-- función mira hasta AYER (fin = corte − 1), por eso las faltas van del 19 al 22.
-- Exige sesión de admin (mismo truco). Todo en begin/rollback.
-- ============================================================================
begin;
select plan(9);

-- ── Semilla ────────────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000ff', 'ZZTEST', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, rol, auth_user_id)
values ('00000000-0000-0000-0000-0000000000aa', 'AdminPrueba', 'Laboratorio',
        '00000000-0000-0000-0000-0000000000ff', 'test-hash', 'admin',
        '00000000-0000-0000-0000-0000000000ab');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000ab', true);

-- Sin feriados en la ventana, para que no alteren qué días "le tocaba"
delete from feriados where fecha between '2026-07-19' and '2026-07-22';

-- Personas de laboratorio. La fecha de ingreso define cuántos días caen en la
-- ventana [ingreso, 22/07]; con horario de todos los días, cada uno es programado.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso) values
  ('00000000-0000-0000-0000-0000000000da', 'PruebaFA', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash', '2026-07-19'), -- 4 días
  ('00000000-0000-0000-0000-0000000000db', 'PruebaFB', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash', '2026-07-20'), -- 3 días
  ('00000000-0000-0000-0000-0000000000dc', 'PruebaFC', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash', '2026-07-21'), -- 2 días
  ('00000000-0000-0000-0000-0000000000dd', 'PruebaFD', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash', '2026-07-19'), -- marca todo
  ('00000000-0000-0000-0000-0000000000de', 'PruebaFE', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash', '2026-07-19'), -- justifica todo
  ('00000000-0000-0000-0000-0000000000df', 'PruebaFF', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash', '2026-07-19'); -- sin horario

-- Horario de TODOS los días (0=dom … 6=sáb) para FA..FE. FF a propósito no tiene.
insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables) values
  ('00000000-0000-0000-0000-0000000000da', '2026-07-01', '09:00', '18:00', '{0,1,2,3,4,5,6}'),
  ('00000000-0000-0000-0000-0000000000db', '2026-07-01', '09:00', '18:00', '{0,1,2,3,4,5,6}'),
  ('00000000-0000-0000-0000-0000000000dc', '2026-07-01', '09:00', '18:00', '{0,1,2,3,4,5,6}'),
  ('00000000-0000-0000-0000-0000000000dd', '2026-07-01', '09:00', '18:00', '{0,1,2,3,4,5,6}'),
  ('00000000-0000-0000-0000-0000000000de', '2026-07-01', '09:00', '18:00', '{0,1,2,3,4,5,6}');

-- FD: marca entrada los 4 días → presencia, no falta
insert into jornadas (persona_id, fecha, entrada_ts) values
  ('00000000-0000-0000-0000-0000000000dd', '2026-07-19', '2026-07-19 09:00:00+00'),
  ('00000000-0000-0000-0000-0000000000dd', '2026-07-20', '2026-07-20 09:00:00+00'),
  ('00000000-0000-0000-0000-0000000000dd', '2026-07-21', '2026-07-21 09:00:00+00'),
  ('00000000-0000-0000-0000-0000000000dd', '2026-07-22', '2026-07-22 09:00:00+00');

-- FE: justifica los 4 días → no cuentan como falta
insert into justificaciones_asistencia (persona_id, fecha, motivo, creado_por) values
  ('00000000-0000-0000-0000-0000000000de', '2026-07-19', 'permiso_concedido', '00000000-0000-0000-0000-0000000000aa'),
  ('00000000-0000-0000-0000-0000000000de', '2026-07-20', 'permiso_concedido', '00000000-0000-0000-0000-0000000000aa'),
  ('00000000-0000-0000-0000-0000000000de', '2026-07-21', 'permiso_concedido', '00000000-0000-0000-0000-0000000000aa'),
  ('00000000-0000-0000-0000-0000000000de', '2026-07-22', 'permiso_concedido', '00000000-0000-0000-0000-0000000000aa');

create temp table _falt as
  select * from fn_faltas_resumen('2026-07-23'::date);

-- ── 4 faltas consecutivas → rojo ────────────────────────────────────────────
select is(
  (select consecutivas from _falt where persona_id = '00000000-0000-0000-0000-0000000000da'),
  4, 'FA: 4 días programados sin marca = 4 faltas consecutivas');
select is(
  (select nivel from _falt where persona_id = '00000000-0000-0000-0000-0000000000da'),
  'rojo', 'FA: 4 faltas consecutivas pintan rojo');
select is(
  (select en_180 from _falt where persona_id = '00000000-0000-0000-0000-0000000000da'),
  4, 'FA: el acumulado de faltas es 4');

-- ── 3 faltas consecutivas → ámbar ───────────────────────────────────────────
select is(
  (select consecutivas from _falt where persona_id = '00000000-0000-0000-0000-0000000000db'),
  3, 'FB: 3 días programados sin marca = 3 faltas consecutivas');
select is(
  (select nivel from _falt where persona_id = '00000000-0000-0000-0000-0000000000db'),
  'ambar', 'FB: 3 faltas consecutivas pintan ámbar (aún no rojo)');

-- ── Por debajo del umbral → verde → no aparece ──────────────────────────────
select is(
  (select count(*)::int from _falt where persona_id = '00000000-0000-0000-0000-0000000000dc'),
  0, 'FC: con 2 faltas no llega a ningún umbral → no aparece en la alerta');

-- ── Marca = presencia, no falta ─────────────────────────────────────────────
select is(
  (select count(*)::int from _falt where persona_id = '00000000-0000-0000-0000-0000000000dd'),
  0, 'FD: marcar entrada los 4 días es presencia → no aparece');

-- ── Justificado no es falta ─────────────────────────────────────────────────
select is(
  (select count(*)::int from _falt where persona_id = '00000000-0000-0000-0000-0000000000de'),
  0, 'FE: los 4 días justificados no cuentan como falta → no aparece');

-- ── Sin horario no hay falta (no le tocaba) ─────────────────────────────────
select is(
  (select count(*)::int from _falt where persona_id = '00000000-0000-0000-0000-0000000000df'),
  0, 'FF: sin horario asignado, la ausencia no es falta → no aparece');

select * from finish();
rollback;
