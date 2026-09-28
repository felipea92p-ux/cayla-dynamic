-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. Se corre:
--   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/.
-- ============================================================================
-- 387_la_declaracion_de_ruta_vuelve_a_preguntar_pasaje_y_taxi.test.sql — 0489
-- ============================================================================
-- La 0489 devuelve a la declaración digital los puntos 3 y 4 del papel: el
-- costo del pasaje (con el gasto diario calculado) y el taxi ocasional.
-- Lo que se defiende acá:
--
--   1. QUE NO TOQUE CUÁNTO SE PAGA. Lo que la persona declara del pasaje es
--      descriptivo: `monto_declarado` sigue siendo la tarifa de la sede
--      (0142), por más que el gasto declarado sea más alto o más bajo. Es la
--      razón por la que la 0425 los había quitado, y la única que importa.
--   2. QUE EL GASTO DIARIO NO SE PUEDA CONTRADECIR: sale de
--      (ida + vuelta) × pasaje, no de lo que alguien escriba.
--   3. QUE EL TAXI SEA OPCIONAL PERO NO A MEDIAS: sin taxi queda en null; con
--      un costo sin veces por semana (o al revés), se rechaza.
--   4. QUE NO QUEDE UNA SOBRECARGA de 4 parámetros viva: si conviviera, una
--      llamada con 4 argumentos respondería «function … is not unique».
-- ============================================================================
begin;
select plan(13);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, tipo_vinculo, auth_user_id) values
  -- En la sede REAL de Trujillo, para que la tarifa salga de
  -- parametros_laborales de verdad (S/ 10.00), igual que en la 334.
  ('00000000-0000-0000-0000-000000387001', 'Prueba', 'ConTaxi',
   (select id from sedes where codigo = 'TRU'), 'integrante', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000387011'),
  ('00000000-0000-0000-0000-000000387002', 'Prueba', 'SinTaxi',
   (select id from sedes where codigo = 'TRU'), 'integrante', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000387012');
set session_replication_role = origin;

insert into firmas_escaneadas (persona_id, imagen, tipo) values
  ('00000000-0000-0000-0000-000000387001', 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==', 'imagen'),
  ('00000000-0000-0000-0000-000000387002', 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==', 'imagen');

-- ── 1 · Una sola versión de la función ──────────────────────────────────────
select is(
  (select count(*)::int from pg_proc where proname = 'fn_confirmar_mi_declaracion_ruta'),
  1,
  'UNA SOLA · no quedó viva la firma de 4 parámetros junto a la de 7 (sería «is not unique»)');

-- ── 2 · Lo que se rechaza ──────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000387011', true);

select throws_ok(
  $$ select fn_confirmar_mi_declaracion_ruta('Trujillo','Trujillo',1,1) $$,
  'P0001', 'Indica el costo de cada pasaje (S/ 0 si no usas transporte).',
  'PASAJE OBLIGATORIO · la llamada de la pantalla vieja (4 argumentos) recibe un mensaje que se entiende');

select throws_ok(
  $$ select fn_confirmar_mi_declaracion_ruta('Trujillo','Trujillo',1,1,-1) $$,
  'P0001', 'Indica el costo de cada pasaje (S/ 0 si no usas transporte).',
  'PASAJE · un costo negativo no es un costo');

select throws_ok(
  $$ select fn_confirmar_mi_declaracion_ruta('Trujillo','Trujillo',1,1,2.50,8,null) $$,
  'P0001', 'Indica cuántas veces por semana usas taxi u otro medio particular (entre 1 y 7).',
  'TAXI A MEDIAS · un costo sin veces por semana no dice nada');

select throws_ok(
  $$ select fn_confirmar_mi_declaracion_ruta('Trujillo','Trujillo',1,1,2.50,null,2) $$,
  'P0001', 'Indica cuánto te cuesta cada viaje en taxi u otro medio particular.',
  'TAXI A MEDIAS · veces por semana sin costo, tampoco');

select throws_ok(
  $$ select fn_confirmar_mi_declaracion_ruta('Trujillo','Trujillo',1,1,2.50,8,9) $$,
  'P0001', 'Indica cuántas veces por semana usas taxi u otro medio particular (entre 1 y 7).',
  'TAXI · una semana no tiene más de 7 días');

-- ── 3 · Con taxi: el caso del papel del 10/08 (1 y 1, S/ 2.50, taxi S/ 8 una vez) ─
select lives_ok(
  $$ select fn_confirmar_mi_declaracion_ruta('Trujillo','Trujillo',1,1,2.50,8,1) $$,
  'OK · con pasaje y taxi, la declaración se firma');

select is(
  (select ruta_costo_pasaje || '/' || ruta_gasto_diario || '/' || ruta_costo_taxi || '/' || ruta_frecuencia_taxi
     from documentos_firmados
    where persona_id = '00000000-0000-0000-0000-000000387001' and tipo = 'ruta'),
  '2.50/5.00/8.00/1',
  'COLUMNAS · pasaje, gasto diario (1+1)×2.50 = 5.00, taxi y veces quedan aparte del párrafo');

select is(
  (select monto_declarado from documentos_firmados
    where persona_id = '00000000-0000-0000-0000-000000387001' and tipo = 'ruta'),
  10.00::numeric,
  'MONTO · sigue siendo la tarifa de TRU (S/ 10.00), no el gasto declarado (S/ 5.00) — nada de esto entra a la planilla');

select ok(
  (select ruta_declarada like '%S/ 2.50%' and ruta_declarada like '%S/ 5.00%'
      and ruta_declarada like '%S/ 8.00%' and ruta_declarada like '%S/ 10.00%'
     from documentos_firmados
    where persona_id = '00000000-0000-0000-0000-000000387001' and tipo = 'ruta'),
  'TEXTO · el párrafo legal dice el pasaje, el gasto, el taxi y la asignación');

select is(
  (select ruta_costo_pasaje::text from fn_documentos_listar('00000000-0000-0000-0000-000000387001')
    where tipo = 'ruta' and vigente),
  '2.50',
  'LISTAR · fn_documentos_listar devuelve las columnas nuevas, para que la pantalla arme los puntos 3 y 4');

-- ── 4 · Sin taxi: queda en null, no en cero ────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000387012', true);

-- Cero en los dos es «no uso taxi», igual que dejarlos en blanco.
select lives_ok(
  $$ select fn_confirmar_mi_declaracion_ruta('La Esperanza','Trujillo',2,1,1.50,0,0) $$,
  'OK · sin taxi también se firma');

select is(
  (select ruta_gasto_diario || '/' || coalesce(ruta_costo_taxi::text, 'null') || '/'
          || coalesce(ruta_frecuencia_taxi::text, 'null')
     from documentos_firmados
    where persona_id = '00000000-0000-0000-0000-000000387002' and tipo = 'ruta'),
  '4.50/null/null',
  'SIN TAXI · gasto (2+1)×1.50 = 4.50, y el taxi queda en null — la pantalla dice «no utilizo taxi»');

select * from finish();
rollback;
