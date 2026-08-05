-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 70_marcajes_fuera_de_orden.test.sql — Blindaje del detector de días imposibles
-- ============================================================================
-- fn_dia_incoherente (mig. 0068) es el cerebro nuevo: ordena la jornada por hora
-- y responde "¿esta secuencia es posible?". De su respuesta depende que un día
-- roto se SELLE y aparezca en Correcciones, en vez de quedarse mal en silencio.
--
-- Se prueba con casos reales, incluido el que destapó el bug el 23/07/2026:
-- una persona con DOS "salida a almuerzo" seguidas, causado por una marca que
-- llegó tarde desde la cola sin conexión.
--
-- OJO con el equilibrio que se prueba aquí: debe decir "roto" cuando de verdad
-- lo está, y "sano" cuando no. Una alarma que suena de más es tan inútil como
-- la que no suena.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000ff', 'ZZTEST', 'Sede de laboratorio', true);

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash) values
  ('00000000-0000-0000-0000-0000000000e1', 'PruebaMA', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash'),
  ('00000000-0000-0000-0000-0000000000e2', 'PruebaMB', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash'),
  ('00000000-0000-0000-0000-0000000000e3', 'PruebaMC', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash'),
  ('00000000-0000-0000-0000-0000000000e4', 'PruebaMD', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash'),
  ('00000000-0000-0000-0000-0000000000e5', 'PruebaME', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash'),
  ('00000000-0000-0000-0000-0000000000e6', 'PruebaMF', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash'),
  ('00000000-0000-0000-0000-0000000000e7', 'PruebaMG', 'Laboratorio', '00000000-0000-0000-0000-0000000000ff', 'test-hash');

-- MA · jornada perfecta: entra, almuerza, vuelve, se va.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  ('00000000-0000-0000-0001-000000000001', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000ff', 'entrada',          '2026-07-23T09:00:00-05:00'),
  ('00000000-0000-0000-0001-000000000002', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000ff', 'salida_almuerzo',  '2026-07-23T13:00:00-05:00'),
  ('00000000-0000-0000-0001-000000000003', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000ff', 'retorno_almuerzo', '2026-07-23T14:00:00-05:00'),
  ('00000000-0000-0000-0001-000000000004', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000ff', 'salida_final',     '2026-07-23T18:00:00-05:00');

-- MB · EL CASO REAL: dos "salida a almuerzo" seguidas (marca que llegó tarde).
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  ('00000000-0000-0000-0001-000000000011', '00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000ff', 'entrada',          '2026-07-23T12:18:00-05:00'),
  ('00000000-0000-0000-0001-000000000012', '00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000ff', 'salida_almuerzo',  '2026-07-23T14:11:00-05:00'),
  ('00000000-0000-0000-0001-000000000013', '00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000ff', 'salida_almuerzo',  '2026-07-23T18:01:00-05:00'),
  ('00000000-0000-0000-0001-000000000014', '00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000ff', 'retorno_almuerzo', '2026-07-23T18:02:00-05:00');

-- MC · algo ocurre DESPUÉS de la salida final.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  ('00000000-0000-0000-0001-000000000021', '00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000000ff', 'entrada',      '2026-07-23T09:00:00-05:00'),
  ('00000000-0000-0000-0001-000000000022', '00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000000ff', 'salida_final', '2026-07-23T18:00:00-05:00'),
  ('00000000-0000-0000-0001-000000000023', '00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000000ff', 'entrada',      '2026-07-23T19:00:00-05:00');

-- MD · un retorno sin su salida.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  ('00000000-0000-0000-0001-000000000031', '00000000-0000-0000-0000-0000000000e4', '00000000-0000-0000-0000-0000000000ff', 'entrada',          '2026-07-23T09:00:00-05:00'),
  ('00000000-0000-0000-0001-000000000032', '00000000-0000-0000-0000-0000000000e4', '00000000-0000-0000-0000-0000000000ff', 'retorno_almuerzo', '2026-07-23T14:00:00-05:00');

-- ME · el día empieza sin entrada.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  ('00000000-0000-0000-0001-000000000041', '00000000-0000-0000-0000-0000000000e5', '00000000-0000-0000-0000-0000000000ff', 'salida_almuerzo', '2026-07-23T13:00:00-05:00');

-- MF · sin marcas (día vacío). MG · solo entrada, sigue adentro.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  ('00000000-0000-0000-0001-000000000051', '00000000-0000-0000-0000-0000000000e7', '00000000-0000-0000-0000-0000000000ff', 'entrada', '2026-07-23T09:00:00-05:00');

-- ── Días SANOS: no deben dar falsa alarma ───────────────────────────────────
select is(
  fn_dia_incoherente('00000000-0000-0000-0000-0000000000e1', '2026-07-23'),
  false, 'MA: jornada completa y ordenada = sana');

select is(
  fn_dia_incoherente('00000000-0000-0000-0000-0000000000e6', '2026-07-23'),
  false, 'MF: un día sin ninguna marca no es un día roto');

select is(
  fn_dia_incoherente('00000000-0000-0000-0000-0000000000e7', '2026-07-23'),
  false, 'MG: solo entrada (sigue adentro) es un día sano, no roto');

-- ── Días IMPOSIBLES: tienen que detectarse ──────────────────────────────────
select is(
  fn_dia_incoherente('00000000-0000-0000-0000-0000000000e2', '2026-07-23'),
  true, 'MB (caso real): dos salidas a almuerzo seguidas se detecta como roto');

select is(
  fn_dia_incoherente('00000000-0000-0000-0000-0000000000e3', '2026-07-23'),
  true, 'MC: una marca después de la salida final se detecta como roto');

select is(
  fn_dia_incoherente('00000000-0000-0000-0000-0000000000e4', '2026-07-23'),
  true, 'MD: un retorno sin su salida previa se detecta como roto');

select is(
  fn_dia_incoherente('00000000-0000-0000-0000-0000000000e5', '2026-07-23'),
  true, 'ME: un día que no empieza por entrada se detecta como roto');

select * from finish();
rollback;
