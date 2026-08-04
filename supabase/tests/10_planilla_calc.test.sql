-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 10_planilla_calc.test.sql — Blindaje del CÁLCULO de la planilla
-- ============================================================================
-- Esto ya no es prueba de humo: verifica que fn_planilla_calcular reparte el
-- dinero exactamente según las reglas que decidimos. Si algún día alguien toca
-- la fórmula y rompe una regla, esta prueba se pone ROJA antes de llegar a un
-- pago real.
--
-- CÓMO FUNCIONA (para confiar en ella):
--   · Sembramos personas de laboratorio con ids fijos y números redondos, para
--     poder calcular a mano el resultado esperado y compararlo.
--   · Todo ocurre dentro de begin/rollback: al terminar NO queda nada en la base.
--     No toca a nadie real. Borra feriados del periodo solo dentro de esa burbuja.
--   · fn_planilla_calcular NO exige permiso de admin (el cálculo es puro), por eso
--     se puede invocar directo aquí.
--
-- ESCENARIO (junio 2026: 30 días → base = 6.5 h × 30 = 195 h; sueldo 1950 →
-- la hora vale 1950/195 = S/10 exactos, para que las cuentas den redondas):
--   A · asiste TODOS los días completos, sin hijos   → cobra el sueldo íntegro
--   B · igual que A pero CON hijos                    → + asignación familiar
--   C · SUELDO FIJO y no marca ni un día              → cobra completo igual
--   D · asiste solo la mitad del mes                  → cobra medio sueldo
-- (julio 2026: 31 días → base = 201.5 h; un feriado el 10 de julio):
--   E · ingresó DESPUÉS del feriado                   → ese feriado no le toca
--   F · ya trabajaba antes del feriado                → ese feriado sí le paga
-- ============================================================================
begin;
select plan(12);

-- ── Semilla determinista ───────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000ff', 'ZZTEST', 'Sede de laboratorio', true);

-- Sesión de admin: desde la 0090, fn_planilla_calcular exige serlo. El guard vive
-- dentro de la función porque el `revoke` que la protegía se deshizo solo cuando
-- un barrido de permisos concedió en masa (ver 0090).
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-00000000ad01', 'AdminPlanilla', 'Laboratorio',
        '00000000-0000-0000-0000-0000000000ff', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000ad09');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ad09', true);


-- Personas (pin_hash es obligatorio; el resto toma sus valores por defecto)
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, estado, fecha_ingreso, con_hijos, sueldo_fijo) values
  ('00000000-0000-0000-0000-00000000000a', 'PruebaA', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash', 'activo', '2020-01-01', false, false),
  ('00000000-0000-0000-0000-00000000000b', 'PruebaB', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash', 'activo', '2020-01-01', true,  false),
  ('00000000-0000-0000-0000-00000000000c', 'PruebaC', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash', 'activo', '2020-01-01', false, true),
  ('00000000-0000-0000-0000-00000000000d', 'PruebaD', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash', 'activo', '2020-01-01', false, false),
  ('00000000-0000-0000-0000-00000000000e', 'PruebaE', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash', 'activo', '2026-07-20', false, false),
  ('00000000-0000-0000-0000-00000000000f', 'PruebaF', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash', 'activo', '2020-01-01', false, false);

-- Todas ganan el mismo sueldo de referencia (1950) para que la hora valga S/10
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde) values
  ('00000000-0000-0000-0000-00000000000a', 'cayla', 1950.00, '2020-01-01'),
  ('00000000-0000-0000-0000-00000000000b', 'cayla', 1950.00, '2020-01-01'),
  ('00000000-0000-0000-0000-00000000000c', 'cayla', 1950.00, '2020-01-01'),
  ('00000000-0000-0000-0000-00000000000d', 'cayla', 1950.00, '2020-01-01'),
  ('00000000-0000-0000-0000-00000000000e', 'cayla', 1950.00, '2020-01-01'),
  ('00000000-0000-0000-0000-00000000000f', 'cayla', 1950.00, '2020-01-01');

-- A y B: asisten los 30 días de junio, 6.5 h → 195 h = base completa
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select p, d::date, 6.5, 'cerrada'
from (values ('00000000-0000-0000-0000-00000000000a'::uuid),
             ('00000000-0000-0000-0000-00000000000b'::uuid)) v(p),
     generate_series('2026-06-01'::date, '2026-06-30'::date, interval '1 day') d;

-- C: sueldo fijo, a propósito NO se le registra ninguna jornada.

-- D: solo la primera quincena de junio (15 días × 6.5 h = 97.5 h = media base)
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-00000000000d', d::date, 6.5, 'cerrada'
from generate_series('2026-06-01'::date, '2026-06-15'::date, interval '1 day') d;

-- E: ingresó el 20/jul, trabaja del 20 al 31 de julio
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-00000000000e', d::date, 6.5, 'cerrada'
from generate_series('2026-07-20'::date, '2026-07-31'::date, interval '1 day') d;

-- F: trabaja todo julio MENOS el 10 (descansa el feriado)
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-00000000000f', d::date, 6.5, 'cerrada'
from generate_series('2026-07-01'::date, '2026-07-31'::date, interval '1 day') d
where d::date <> '2026-07-10';

-- Feriados: dejamos junio SIN feriados (para que A–D cobren limpio) y julio con
-- exactamente uno, el 10. Se borra dentro de la burbuja; no afecta datos reales.
delete from feriados where fecha between '2026-06-01' and '2026-07-31';
insert into feriados (fecha, nombre) values ('2026-07-10', 'Feriado de laboratorio');

-- ── Resultados del cálculo, una sola vez por periodo ───────────────────────
create temp table _junio as
  select value as fila
  from jsonb_array_elements(fn_planilla_calcular('2026-06-01'::date, '2026-06-30'::date) -> 'filas');
create temp table _julio as
  select value as fila
  from jsonb_array_elements(fn_planilla_calcular('2026-07-01'::date, '2026-07-31'::date) -> 'filas');

-- ── JUNIO ──────────────────────────────────────────────────────────────────

-- 1) Asistir la base completa paga el sueldo íntegro
select is(
  (select (fila->>'pago_base')::numeric from _junio where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000000a'),
  1950.00::numeric,
  'A: trabajar la base completa (195 h) paga el sueldo íntegro (1950)');

-- 2) Sin hijos, sin asignación familiar
select is(
  (select (fila->>'asignacion_familiar')::numeric from _junio where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000000a'),
  0::numeric,
  'A: sin hijos no cobra asignación familiar');

-- 3) Sin otros conceptos, el total es exactamente el pago base
select is(
  (select (fila->>'total')::numeric from _junio where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000000a'),
  1950.00::numeric,
  'A: sin feriados ni bonos, el total es el puro pago base');

-- 4) Con hijos, exactamente S/113 (asignación familiar de ley)
select is(
  (select (fila->>'asignacion_familiar')::numeric from _junio where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000000b'),
  113.00::numeric,
  'B: con hijos cobra la asignación familiar de ley (S/113)');

-- 5) La asignación familiar se suma al total
select is(
  (select (fila->>'total')::numeric from _junio where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000000b'),
  2063.00::numeric,
  'B: 1950 de sueldo + 113 de asignación = 2063');

-- 6) Sueldo fijo: cobra completo aunque no haya marcado ni un día (regla Catherine)
select is(
  (select (fila->>'pago_base')::numeric from _junio where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000000c'),
  1950.00::numeric,
  'C: sueldo fijo cobra el mes completo aunque no marque asistencia');

-- 7) Media asistencia paga medio sueldo (proporcionalidad por horas)
select is(
  (select (fila->>'pago_base')::numeric from _junio where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000000d'),
  975.00::numeric,
  'D: asistir la mitad del mes (97.5 h) paga medio sueldo (975)');

-- 8) Identidad contable: el total es la suma exacta de sus partes
select is(
  (select (fila->>'total')::numeric from _junio where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000000a'),
  (select (fila->>'pago_base')::numeric + (fila->>'monto_feriados')::numeric + (fila->>'monto_plus')::numeric
        + (fila->>'asignacion_familiar')::numeric + (fila->>'bonos')::numeric - (fila->>'descuentos')::numeric
   from _junio where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000000a'),
  'Identidad contable: total = base + feriados + plus + asignación + bonos − descuentos');

-- ── JULIO: la regla del feriado según la fecha de ingreso ───────────────────

-- 9) A quien ingresó DESPUÉS del feriado, ese feriado le aparece como "no corresponde"
select is(
  (select (fila->>'feriados_no_corresponde')::int from _julio where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000000e'),
  1,
  'E: un feriado anterior a su ingreso se marca como "no corresponde"');

-- 10) ...y no le suma nada de dinero
select is(
  (select (fila->>'monto_feriados')::numeric from _julio where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000000e'),
  0::numeric,
  'E: ese feriado anterior al ingreso no le paga nada');

-- 11) A quien ya trabajaba antes del feriado, sí le corresponde
select is(
  (select (fila->>'feriados_no_corresponde')::int from _julio where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000000f'),
  0,
  'F: quien ya trabajaba antes del feriado no tiene feriados "no corresponde"');

-- 12) ...y ese feriado sí le paga (proporcional a lo trabajado, positivo)
select cmp_ok(
  (select (fila->>'monto_feriados')::numeric from _julio where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000000f'),
  '>', 0::numeric,
  'F: el feriado que sí le corresponde le paga un monto positivo');

select * from finish();
rollback;
