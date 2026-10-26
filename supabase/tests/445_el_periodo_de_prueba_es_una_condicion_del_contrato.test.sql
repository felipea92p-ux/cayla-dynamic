-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 445_el_periodo_de_prueba_es_una_condicion_del_contrato.test.sql — la 0553
-- ============================================================================
-- Defiende lo que la 0553 le promete a «Parámetros»:
--   1. El periodo de prueba se MUESTRA y no se cambia: fila normativa, sin
--      botón, y la base rechaza un valor que no sea 3 por CUALQUIER camino —la
--      puerta, el UPDATE directo y el SQL Editor—. Un número mostrado que
--      alguien pudiera mover sin que el sistema lo use sería un dato sin dueño.
--   2. «Días de prueba antes del contrato» ya no es editable: ni por la puerta
--      ni existe como fila editable. La maquinaria vieja (0536) sigue leyendo su
--      clave, así que `fn_prueba_dias_plazo()` no se rompe.
--   3. El aviso de feriado es un parámetro operativo 1–30 que lee Turnos, y su
--      función entrega lo que diga la tabla y cae en el 15 si falta la fila.
--   4. Quién puede llamarla: con login sí, sin login no.
--
-- No prueba la rama «el parámetro viejo ya tenía historial»: la migración la
-- resuelve con un `if` dentro de su bloque `do` y se midió a mano contra una
-- base con historial (ver el PR).
-- ============================================================================
begin;
select plan(19);

-- ── Fixture: una dirección y un líder de DO ─────────────────────────────────
insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000044501', 'ZZ445', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000004451c', 'do-445@local'),
  ('00000000-0000-0000-0000-00000004451d', 'admin-445@local');
insert into personas (id, nombres, apellidos, sede_base_id, rol, estado, pin_hash, auth_user_id, fecha_ingreso, fecha_cese, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000044513', 'Lider',     'DO',    '00000000-0000-0000-0000-000000044501',
   'lider_do', 'activo', 'x', '00000000-0000-0000-0000-00000004451c', '2024-01-01', null, 'planilla'),
  ('00000000-0000-0000-0000-000000044514', 'Direccion', 'Admin', '00000000-0000-0000-0000-000000044501',
   'admin',    'activo', 'x', '00000000-0000-0000-0000-00000004451d', '2024-01-01', null, 'planilla');
set session_replication_role = origin;

-- ── 1 · El periodo de prueba se muestra y no se cambia ──────────────────────
select is(
  (select clase || ' · ' || editable::text || ' · ' || valor_min || '-' || valor_max || ' · ' || valor_defecto || ' ' || unidad
     from parametros_catalogo where parametro = 'periodo_prueba_meses'),
  'normativo · false · 3-3 · 3 meses',
  'El periodo de prueba es una fila normativa, fija, de 3 meses');

select ok(
  (select base like '%art. 10%' or base like '%Art. 10%' from parametros_catalogo where parametro = 'periodo_prueba_meses'),
  'Y dice de dónde sale: el artículo 10 del D.S. 003-97-TR');

select is((select valor from configuracion where clave = 'periodo_prueba_meses'), '3'::jsonb,
  'Su clave existe y vale 3');

-- La puerta: ni DO ni la dirección lo cambian.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004451c', true);
set role authenticated;
select throws_ok(
  $$ select fn_parametro_cambiar('periodo_prueba_meses', 6, 'Queremos seis meses') $$,
  '«Periodo de prueba» lo fija una norma. Base: Art. 10 del D.S. 003-97-TR (migración 0553). No se cambia desde Parámetros.',
  'DO NO cambia el periodo de prueba: lo fija una norma');
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004451d', true);
set role authenticated;
select throws_ok(
  $$ select fn_parametro_cambiar('periodo_prueba_meses', 6, 'Queremos seis meses') $$,
  '«Periodo de prueba» lo fija una norma. Base: Art. 10 del D.S. 003-97-TR (migración 0553). No se cambia desde Parámetros.',
  'Ni la dirección lo cambia desde Parámetros');

-- El UPDATE armado a mano desde el navegador.
select throws_ok(
  $$ update configuracion set valor = '6'::jsonb where clave = 'periodo_prueba_meses' $$,
  'Este valor se cambia desde Parámetros, no con una escritura directa a la tabla.',
  'BLOQUEADO · un UPDATE directo desde el navegador al periodo de prueba');
reset role;

-- El SQL Editor: el candado deja pasar al dueño de la base, pero los LÍMITES valen igual (3 a 3).
select throws_ok(
  $$ update configuracion set valor = '6'::jsonb where clave = 'periodo_prueba_meses' $$,
  '«Periodo de prueba» va de 3 a 3 meses (llegó 6).',
  'BLOQUEADO · también en el SQL Editor: el periodo de prueba no puede ser distinto de 3');
select is((select valor from configuracion where clave = 'periodo_prueba_meses'), '3'::jsonb,
  'Y el 3 sigue siendo 3');
select is((select count(*)::int from parametros_historial where parametro = 'periodo_prueba_meses'), 0,
  'Los rechazos no dejaron historial');

-- ── 2 · Los días de prueba ya no se editan ──────────────────────────────────
select is(
  (select count(*)::int from parametros_catalogo where parametro = 'prueba_dias' and editable),
  0, 'No queda ningún parámetro «días de prueba» editable');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004451c', true);
set role authenticated;
select throws_ok(
  $$ select fn_parametro_cambiar('prueba_dias', 5, 'Probando con cinco') $$,
  'No existe el parámetro «prueba_dias».',
  'Ya no se puede cambiar por la puerta: no existe como parámetro');
reset role;

-- La maquinaria vieja (0536) sigue leyendo su clave: nada se rompe mientras quede alguien «prueba».
select is(fn_prueba_dias_plazo(), 3, 'fn_prueba_dias_plazo() sigue devolviendo 3 para la maquinaria vieja');

-- ── 3 · El aviso de feriado ─────────────────────────────────────────────────
select is(
  (select clase || ' · ' || editable::text || ' · ' || valor_min || '-' || valor_max || ' · ' || valor_defecto || ' ' || unidad
     from parametros_catalogo where parametro = 'feriado_aviso_antiguedad_dias'),
  'operativo · true · 1-30 · 15 días',
  'El aviso de feriado es un parámetro operativo de 1 a 30 días, con 15 de partida');

select is(fn_feriado_aviso_dias(), 15, 'La función entrega 15 hoy');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004451c', true);
set role authenticated;
select lives_ok(
  $$ select fn_parametro_cambiar('feriado_aviso_antiguedad_dias', 7, 'Con una semana alcanza para saber si se queda') $$,
  'DO cambia el aviso de 15 a 7 días');
reset role;
select is(fn_feriado_aviso_dias(), 7, 'Y la función ya devuelve 7: Turnos lo recibe sin cambiar de pantalla');

delete from configuracion where clave = 'feriado_aviso_antiguedad_dias';
select is(fn_feriado_aviso_dias(), 15, 'Sin la fila, la función cae en el 15 de partida');

-- ── 4 · Quién puede llamarla ────────────────────────────────────────────────
set role authenticated;
select lives_ok($$ select fn_feriado_aviso_dias() $$, 'Con login se puede llamar (Turnos la lee desde el navegador)');
reset role;
set role anon;
select throws_ok($$ select fn_feriado_aviso_dias() $$, '42501', null, 'Sin login no');
reset role;

select * from finish();
rollback;
