-- ============================================================================
-- 90_espejo_de_la_maquina_de_estados.test.sql
-- ============================================================================
-- "Qué marca toca ahora" se decide en DOS sitios:
--
--   · en el navegador, con determinarSiguienteAccion (packages/shared) — es lo
--     que dibuja los botones del terminal;
--   · en la base, con fn_siguiente_tipo_esperado — es lo que ACEPTA o RECHAZA
--     la marca cuando llega.
--
-- Si divergen, el terminal ofrece un botón que el servidor va a rechazar, y la
-- persona se queda delante de la pantalla sin poder marcar. Pasó el 26-07-2026:
-- la 0082 enseñó a la versión SQL a ignorar las marcas anuladas y la del
-- navegador se quedó contándolas, así que con una entrada anulada el terminal
-- seguía creyendo a esa persona dentro.
--
-- ESTE ARCHIVO ES EL ESPEJO de tests/asistencia.test.ts: los mismos ocho casos,
-- con los mismos nombres, en el mismo orden. Si tocas uno, toca el otro. Que
-- fallen por separado es la señal de que las dos lógicas se separaron.
--
-- Equivalencia entre lo que devuelve cada una:
--   {modo:'unico', tipo:X}      ↔  X
--   {modo:'elegir_salida'}      ↔  null con la jornada ABIERTA (hay que elegir)
--   {modo:'cerrado'}            ↔  null con la jornada CERRADA (no hay acción)
-- Por eso los dos últimos casos se comprueban además con el estado del día:
-- en SQL los dos devuelven null y solo el estado los distingue.
-- ============================================================================
begin;
select plan(10);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000e5', 'ZZESP', 'Sede de laboratorio', true);

-- Admin con sesión: la hace falta el último caso, que anula una marca.
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-0000000000e0', 'EspejoAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-0000000000e5', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000ee00');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ee00', true);

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash) values
  ('00000000-0000-0000-0000-0000000000e1', 'EspejoA', 'Laboratorio', '00000000-0000-0000-0000-0000000000e5', 'test-hash'),
  ('00000000-0000-0000-0000-0000000000e2', 'EspejoB', 'Laboratorio', '00000000-0000-0000-0000-0000000000e5', 'test-hash'),
  ('00000000-0000-0000-0000-0000000000e3', 'EspejoC', 'Laboratorio', '00000000-0000-0000-0000-0000000000e5', 'test-hash'),
  ('00000000-0000-0000-0000-0000000000e4', 'EspejoD', 'Laboratorio', '00000000-0000-0000-0000-0000000000e5', 'test-hash'),
  ('00000000-0000-0000-0000-0000000000e6', 'EspejoE', 'Laboratorio', '00000000-0000-0000-0000-0000000000e5', 'test-hash'),
  ('00000000-0000-0000-0000-0000000000e7', 'EspejoF', 'Laboratorio', '00000000-0000-0000-0000-0000000000e5', 'test-hash'),
  ('00000000-0000-0000-0000-0000000000e8', 'EspejoG', 'Laboratorio', '00000000-0000-0000-0000-0000000000e5', 'test-hash'),
  ('00000000-0000-0000-0000-0000000000e9', 'EspejoH', 'Laboratorio', '00000000-0000-0000-0000-0000000000e5', 'test-hash');

-- 1 · sin ningún marcaje, lo único posible es ENTRAR
select is(fn_siguiente_tipo_esperado('00000000-0000-0000-0000-0000000000e1', '2026-07-23')::text,
          'entrada', 'sin ningún marcaje, lo único posible es ENTRAR');

-- 2 · con la entrada marcada y nada más, toca ELEGIR cómo sale
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000e5', 'entrada', '2026-07-23T09:00:00-05:00');
select is(fn_siguiente_tipo_esperado('00000000-0000-0000-0000-0000000000e2', '2026-07-23')::text,
          null::text, 'con la entrada marcada y nada más, toca ELEGIR cómo sale (null = elegir)');

-- 3 · si salió a almorzar, lo ÚNICO posible es su retorno
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000000e5', 'entrada',         '2026-07-23T09:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000000e5', 'salida_almuerzo', '2026-07-23T13:00:00-05:00');
select is(fn_siguiente_tipo_esperado('00000000-0000-0000-0000-0000000000e3', '2026-07-23')::text,
          'retorno_almuerzo', 'si salió a almorzar, lo ÚNICO posible es su retorno (sin ambigüedad)');

-- 4 · cada tipo de salida exige SU retorno (médico → retorno médico)
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000e4', '00000000-0000-0000-0000-0000000000e5', 'entrada',       '2026-07-23T09:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000e4', '00000000-0000-0000-0000-0000000000e5', 'salida_medico', '2026-07-23T11:00:00-05:00');
select is(fn_siguiente_tipo_esperado('00000000-0000-0000-0000-0000000000e4', '2026-07-23')::text,
          'retorno_medico', 'cada tipo de salida exige SU retorno correspondiente (médico → retorno médico)');

-- 5 · tras volver del almuerzo, vuelve a poder elegir cómo sale
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000e6', '00000000-0000-0000-0000-0000000000e5', 'entrada',          '2026-07-23T09:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000e6', '00000000-0000-0000-0000-0000000000e5', 'salida_almuerzo',  '2026-07-23T13:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000e6', '00000000-0000-0000-0000-0000000000e5', 'retorno_almuerzo', '2026-07-23T14:00:00-05:00');
select is(fn_siguiente_tipo_esperado('00000000-0000-0000-0000-0000000000e6', '2026-07-23')::text,
          null::text, 'tras volver del almuerzo, vuelve a poder elegir cómo sale');

-- 6 · con la salida final marcada, el día queda CERRADO
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000e7', '00000000-0000-0000-0000-0000000000e5', 'entrada',      '2026-07-23T09:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000e7', '00000000-0000-0000-0000-0000000000e5', 'salida_final', '2026-07-23T18:00:00-05:00');
select is(fn_siguiente_tipo_esperado('00000000-0000-0000-0000-0000000000e7', '2026-07-23')::text,
          null::text, 'con la salida final marcada, el día queda CERRADO');
select is((select estado::text from jornadas where persona_id='00000000-0000-0000-0000-0000000000e7' and fecha='2026-07-23'),
          'cerrada', '...y se distingue de "elegir" porque la jornada está cerrada');

-- 7 · no se confunde si los marcajes llegan DESORDENADOS
-- La cola offline puede insertarlos en cualquier orden: la respuesta es la misma.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000e8', '00000000-0000-0000-0000-0000000000e5', 'salida_almuerzo', '2026-07-23T13:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000e8', '00000000-0000-0000-0000-0000000000e5', 'entrada',         '2026-07-23T09:00:00-05:00');
select is(fn_siguiente_tipo_esperado('00000000-0000-0000-0000-0000000000e8', '2026-07-23')::text,
          'retorno_almuerzo', 'no se confunde si los marcajes llegan DESORDENADOS (los ordena por hora)');

-- 8 · la salida final manda aunque haya una salida temporal previa
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000e9', '00000000-0000-0000-0000-0000000000e5', 'entrada',          '2026-07-23T09:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000e9', '00000000-0000-0000-0000-0000000000e5', 'salida_almuerzo',  '2026-07-23T13:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000e9', '00000000-0000-0000-0000-0000000000e5', 'retorno_almuerzo', '2026-07-23T14:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000e9', '00000000-0000-0000-0000-0000000000e5', 'salida_final',     '2026-07-23T18:00:00-05:00');
select is(fn_siguiente_tipo_esperado('00000000-0000-0000-0000-0000000000e9', '2026-07-23')::text,
          null::text, 'la salida final manda aunque haya una salida temporal previa');

-- 9 · EL CASO QUE SE ROMPIÓ EL 26-07: con la entrada anulada, vuelve a tocar entrar.
-- No está en el archivo de vitest porque allí las anuladas se filtran ANTES, en la
-- consulta de estado-dia.ts. Se deja aquí para que quede fijado en algún sitio.
select fn_anular_marcaje(
  (select id from marcajes where persona_id='00000000-0000-0000-0000-0000000000e2' and tipo='entrada' limit 1),
  'Se marcó a la persona equivocada');
select is(fn_siguiente_tipo_esperado('00000000-0000-0000-0000-0000000000e2', '2026-07-23')::text,
          'entrada', 'con la entrada ANULADA, vuelve a tocar entrar — el terminal no la deja fuera');

select * from finish();
rollback;
