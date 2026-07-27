-- ============================================================================
-- 20_planilla_conceptos.test.sql — Blindaje de provisiones y bono por objetivos
-- ============================================================================
-- Segunda tanda del blindaje del dinero. Verifica dos conceptos que se suman
-- (o se reservan) además del sueldo base:
--   · PROVISIONES (gratificación, CTS, vacaciones): lo que la empresa RESERVA
--     cada mes = (pago base + feriados) × su factor. No se paga al colaborador
--     ahora; se acumula. Aquí fijamos factores redondos (10% / 5% / 5%) dentro
--     de la prueba para verificar la MULTIPLICACIÓN, sin depender de cuál sea el
--     factor real del régimen (ese es una decisión de configuración, no de esta
--     fórmula).
--   · BONO POR OBJETIVOS: quien cumple todos sus objetivos del mes cobra 21% de
--     su sueldo; entre 60% y 99%, cobra 12.6%; por debajo de 60%, nada; por
--     debajo de 30% además queda marcado como bajo desempeño.
--
-- Como siempre: personas de laboratorio, números redondos, begin/rollback (no
-- toca datos reales). fn_planilla_calcular no exige permiso, se invoca directo.
-- ============================================================================
begin;
select plan(11);

-- ── Semilla ────────────────────────────────────────────────────────────────
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


-- Factores de provisión redondos, solo para esta prueba (se revierte con todo)
insert into configuracion (clave, valor)
values ('planilla_provisiones', '{"gratificacion":0.10,"cts":0.05,"vacaciones":0.05}'::jsonb)
on conflict (clave) do update set valor = excluded.valor;

-- Junio 2026 sin feriados, para que el pago base salga limpio
delete from feriados where fecha between '2026-06-01' and '2026-06-30';

-- P: provisiones. Sueldo 2000, asiste todo junio → pago base exacto 2000.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000000a1', 'PruebaP', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash', '2020-01-01');
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-0000000000a1', 'cayla', 2000.00, '2020-01-01');
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-0000000000a1', d::date, 6.5, 'cerrada'
from generate_series('2026-06-01'::date, '2026-06-30'::date, interval '1 day') d;

-- G/H/I/J: bono por objetivos. Sueldo 1000 (para que 21%=210 y 12.6%=126 salgan
-- redondos). No necesitan marcar: el bono se calcula sobre el sueldo de referencia.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso) values
  ('00000000-0000-0000-0000-0000000000a2', 'PruebaG', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash', '2020-01-01'),
  ('00000000-0000-0000-0000-0000000000a3', 'PruebaH', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash', '2020-01-01'),
  ('00000000-0000-0000-0000-0000000000a4', 'PruebaI', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash', '2020-01-01'),
  ('00000000-0000-0000-0000-0000000000a5', 'PruebaJ', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash', '2020-01-01');
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde) values
  ('00000000-0000-0000-0000-0000000000a2', 'cayla', 1000.00, '2020-01-01'),
  ('00000000-0000-0000-0000-0000000000a3', 'cayla', 1000.00, '2020-01-01'),
  ('00000000-0000-0000-0000-0000000000a4', 'cayla', 1000.00, '2020-01-01'),
  ('00000000-0000-0000-0000-0000000000a5', 'cayla', 1000.00, '2020-01-01');
-- Objetivos de junio 2026: G=10/10 (100%), H=6/10 (60%), I=5/10 (50%), J=2/10 (20%)
insert into objetivos_mensuales (persona_id, anio, mes, cumplidos, total) values
  ('00000000-0000-0000-0000-0000000000a2', 2026, 6, 10, 10),
  ('00000000-0000-0000-0000-0000000000a3', 2026, 6, 6, 10),
  ('00000000-0000-0000-0000-0000000000a4', 2026, 6, 5, 10),
  ('00000000-0000-0000-0000-0000000000a5', 2026, 6, 2, 10);

create temp table _junio as
  select value as fila
  from jsonb_array_elements(fn_planilla_calcular('2026-06-01'::date, '2026-06-30'::date) -> 'filas');

-- ── PROVISIONES (persona P: base 2000, factores 10%/5%/5%) ──────────────────
select is(
  (select (fila->>'provision_gratificacion')::numeric from _junio where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000000a1'),
  200.00::numeric, 'Provisión de gratificación = 10% del pago base (2000 → 200)');
select is(
  (select (fila->>'provision_cts')::numeric from _junio where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000000a1'),
  100.00::numeric, 'Provisión de CTS = 5% del pago base (2000 → 100)');
select is(
  (select (fila->>'provision_vacaciones')::numeric from _junio where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000000a1'),
  100.00::numeric, 'Provisión de vacaciones = 5% del pago base (2000 → 100)');
select is(
  (select (fila->>'provision_total')::numeric from _junio where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000000a1'),
  400.00::numeric, 'Provisión total = suma de las tres (200+100+100 = 400)');

-- ── BONO POR OBJETIVOS ──────────────────────────────────────────────────────
select is(
  (select (fila->>'monto_plus')::numeric from _junio where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000000a2'),
  210.00::numeric, 'G: cumplir el 100% de objetivos paga 21% del sueldo (1000 → 210)');
select is(
  (select (fila->>'monto_plus')::numeric from _junio where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000000a3'),
  126.00::numeric, 'H: cumplir 60% paga 12.6% del sueldo (1000 → 126)');
select is(
  (select (fila->>'monto_plus')::numeric from _junio where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000000a4'),
  0::numeric, 'I: por debajo del 60% (50%) el bono es cero');
select is(
  (select (fila->>'monto_plus')::numeric from _junio where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000000a5'),
  0::numeric, 'J: con 20% de objetivos tampoco hay bono');

-- ── Bandera de bajo desempeño (por debajo del 30%) ──────────────────────────
select is(
  (select (fila->>'bajo_desempeno')::boolean from _junio where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000000a5'),
  true, 'J: cumplir solo el 20% lo marca como bajo desempeño');
select is(
  (select (fila->>'bajo_desempeno')::boolean from _junio where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000000a2'),
  false, 'G: cumplir el 100% no es bajo desempeño');

-- El bono efectivamente llega al total del periodo
select is(
  (select (fila->>'total')::numeric from _junio where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000000a2'),
  210.00::numeric, 'G: sin sueldo base marcado, su total es el puro bono (210)');

select * from finish();
rollback;
