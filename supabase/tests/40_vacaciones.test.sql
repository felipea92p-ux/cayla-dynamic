-- ============================================================================
-- 40_vacaciones.test.sql — Blindaje del cálculo de vacaciones
-- ============================================================================
-- Vacaciones es dinero + una fórmula legal de acumulación. Reglas que fija esta
-- prueba (fn_vacaciones_resumen, definición final en mig 0047):
--   · ACUMULACIÓN: se ganan 15 días por año de servicio, SIN TOPE, desde el
--     ingreso (2 años = 30 días, 3 años = 45 días).
--   · SALDO: días ganados − días ya tomados.
--   · PAGO ESTIMADO de los días pendientes = medio sueldo × factor × (saldo/15),
--     donde el factor es el ritmo de trabajo (para sueldo fijo, factor = 1).
--   · NUNCA se paga negativo: si alguien tomó más de lo que ganó, el pago es 0.
--
-- fn_vacaciones_resumen SÍ exige sesión de admin (como la reversa), así que la
-- simulamos igual: session_replication_role salta la FK a auth.users para crear
-- la persona admin, y set_config define auth.uid(). Fecha de corte fija
-- (2026-07-23) para que la acumulación no dependa del día en que corra el CI.
-- Todo en begin/rollback: no toca datos reales.
-- ============================================================================
begin;
select plan(6);

-- ── Semilla ────────────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000ff', 'ZZTEST', 'Sede de laboratorio', true);

-- Persona admin para la sesión (salta la FK a auth.users con replica)
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, rol, auth_user_id)
values ('00000000-0000-0000-0000-0000000000aa', 'AdminPrueba', 'Laboratorio',
        '00000000-0000-0000-0000-0000000000ff', 'test-hash', 'admin',
        '00000000-0000-0000-0000-0000000000ab');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000ab', true);

-- VA: ingresó hace EXACTAMENTE 2 años, sueldo fijo 3000, tomó 10 días.
--     → gana 30, saldo 20, factor 1, pago = 1500 × 20/15 = 2000.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, sueldo_fijo)
values ('00000000-0000-0000-0000-0000000000ba', 'PruebaVA', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash', '2024-07-23', true);
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-0000000000ba', 'cayla', 3000.00, '2024-07-23');
insert into vacaciones (persona_id, fecha_inicio, fecha_fin, creado_por)
values ('00000000-0000-0000-0000-0000000000ba', '2026-01-01', '2026-01-10', '00000000-0000-0000-0000-0000000000aa');

-- VE: ingresó hace 3 años, sin vacaciones tomadas → gana 45 (acumula sin tope).
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, sueldo_fijo)
values ('00000000-0000-0000-0000-0000000000be', 'PruebaVE', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash', '2023-07-23', true);
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-0000000000be', 'cayla', 3000.00, '2023-07-23');

-- VD: ingresó hace 1 año (gana 15) pero tomó 20 → saldo negativo → pago 0.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, sueldo_fijo)
values ('00000000-0000-0000-0000-0000000000bd', 'PruebaVD', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash', '2025-07-23', true);
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-0000000000bd', 'cayla', 2000.00, '2025-07-23');
insert into vacaciones (persona_id, fecha_inicio, fecha_fin, creado_por)
values ('00000000-0000-0000-0000-0000000000bd', '2026-01-01', '2026-01-20', '00000000-0000-0000-0000-0000000000aa');

create temp table _vac as
  select value as fila
  from jsonb_array_elements(fn_vacaciones_resumen('2026-07-23'::date));

-- ── Acumulación (15 días/año, sin tope) ─────────────────────────────────────
select is(
  (select (fila->>'dias_ganados')::numeric from _vac where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000000ba'),
  30.0::numeric, 'VA: 2 años de servicio dan 30 días de vacaciones');
select is(
  (select (fila->>'dias_ganados')::numeric from _vac where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000000be'),
  45.0::numeric, 'VE: 3 años dan 45 días (se acumula sin tope)');

-- ── Saldo = ganados − tomados ───────────────────────────────────────────────
select is(
  (select (fila->>'dias_saldo')::numeric from _vac where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000000ba'),
  20.0::numeric, 'VA: ganó 30 y tomó 10 → le quedan 20 de saldo');

-- ── Factor de sueldo fijo = 1 ───────────────────────────────────────────────
select is(
  (select (fila->>'factor')::numeric from _vac where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000000ba'),
  1.0::numeric, 'VA: con sueldo fijo, el factor de ritmo de trabajo es 1');

-- ── Pago estimado = medio sueldo × factor × saldo/15 ────────────────────────
select is(
  (select (fila->>'monto_estimado')::numeric from _vac where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000000ba'),
  2000.00::numeric, 'VA: pago de vacaciones = 1500 × 20/15 = 2000');

-- ── Nunca se paga negativo ──────────────────────────────────────────────────
select is(
  (select (fila->>'monto_estimado')::numeric from _vac where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000000bd'),
  0::numeric, 'VD: tomó más de lo que ganó → el pago se topa en 0, nunca negativo');

select * from finish();
rollback;
