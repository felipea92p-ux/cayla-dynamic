-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 85_el_tope_de_educacion.test.sql — El techo de educación por rango (mig 0132)
-- ============================================================================
-- La escala de educación por rango (90 · 180 · … · 480) es un TECHO, no un monto
-- a pagar. Lo que se blinda acá:
--   · un monto por encima del techo del rango se rechaza, aunque el comprobante
--     lo sostenga — el comprobante y el techo son dos filtros distintos;
--   · un monto dentro del techo pasa;
--   · el candado de la 0120 sigue vivo: sin comprobante que lo sostenga, no entra
--     ni un monto pequeño;
--   · quien no tiene rango vigente no queda bloqueado (el techo falla abierto a
--     propósito: es política, no integridad).
-- ============================================================================
begin;
select plan(6);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000ff', 'ZZTEST', 'Sede de laboratorio', true);

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash) values
  ('00000000-0000-0000-0000-0000000ed001', 'PruebaEdA', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash'),
  ('00000000-0000-0000-0000-0000000ed002', 'PruebaEdB', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash'),
  ('00000000-0000-0000-0000-0000000ed003', 'PruebaEdC', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash');

-- A y B son 'cayla' (techo 180). C queda a propósito SIN rango.
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde) values
  ('00000000-0000-0000-0000-0000000ed001', 'cayla', 1185.00, '2026-01-01'),
  ('00000000-0000-0000-0000-0000000ed002', 'cayla', 1185.00, '2026-01-01');

-- ── Dentro del techo: pasa ──────────────────────────────────────────────────
-- 180 es exactamente el techo de cayla, y 240 × 75% = 180 lo sostiene.
select lives_ok(
  $$ insert into asignaciones_educacion
       (persona_id, monto, institucion, costo_declarado, vigente_desde)
     values ('00000000-0000-0000-0000-0000000ed001', 180.00, 'Instituto de laboratorio', 240.00, '2026-08-01') $$,
  'Un monto igual al techo del rango, con comprobante que lo sostiene, entra');

-- ── Por encima del techo: se rechaza aunque el comprobante alcance ───────────
-- 400 × 75% = 300, así que el candado del comprobante NO lo frenaría; lo frena
-- el techo del rango (180).
select throws_like(
  $$ insert into asignaciones_educacion
       (persona_id, monto, institucion, costo_declarado, vigente_desde)
     values ('00000000-0000-0000-0000-0000000ed002', 300.00, 'Instituto caro', 400.00, '2026-08-01') $$,
  '%tope del rango%',
  'Un monto sobre el techo del rango se rechaza aunque el comprobante lo sostenga');

-- ── El candado de la 0120 sigue vivo ────────────────────────────────────────
-- 100 está bajo el techo de cayla (180), pero 100 × 75% = 75 < 100: sin sustento.
-- '23514' es check_violation: se exige el código exacto y no un texto libre,
-- porque throws_ok con tres argumentos toma el tercero como MENSAJE esperado y
-- no como descripción — la prueba pasaría por la razón equivocada.
select throws_ok(
  $$ insert into asignaciones_educacion
       (persona_id, monto, institucion, costo_declarado, vigente_desde)
     values ('00000000-0000-0000-0000-0000000ed002', 100.00, 'Instituto barato', 100.00, '2026-08-01') $$,
  '23514',
  null,
  'Sin comprobante que lo sostenga no entra, aunque esté bajo el techo');

-- ── Sin rango vigente, el techo no bloquea (falla abierto) ──────────────────
select lives_ok(
  $$ insert into asignaciones_educacion
       (persona_id, monto, institucion, costo_declarado, vigente_desde)
     values ('00000000-0000-0000-0000-0000000ed003', 500.00, 'Universidad', 1000.00, '2026-08-01') $$,
  'Quien no tiene rango vigente no queda bloqueado por el techo');

-- ── Los seis rangos tienen techo cargado ────────────────────────────────────
-- Eran siete hasta la 0140, que retiró 'caylo': dos categorías con la misma
-- banda separadas solo por género es exactamente lo que la Ley 30709 vino a
-- corregir, y Cayla pasó a ser categoría única y neutra.
select is(
  (select count(*)::int from topes_educacion_rango),
  6, 'Los seis rangos tienen su techo de educación cargado');

select is(
  (select count(*)::int from topes_educacion_rango where rango = 'caylo'),
  0, 'Caylo ya no está en el catálogo de topes');

select * from finish();
rollback;
