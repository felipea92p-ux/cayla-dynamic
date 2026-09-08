-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 304 — La lista de días por revisar dice POR QUÉ está cada día ahí (mig. 0384)
-- ============================================================================
-- EL CASO REAL que obligó a esto (producción, 2026-09-06). La pantalla de
-- Correcciones anunciaba «1 día quedó con una secuencia imposible · Carlos
-- Espejo · 2026-09-05». Ese día era `Entrada 10:26 → Salida final 14:18`: una
-- secuencia perfectamente posible. Lo único pendiente era confirmar la hora que
-- puso el auto-cierre — otra cosa completamente distinta.
--
-- Pasaba porque `estado_revision = 'pendiente_revision'` la escriben tres cosas
-- que no se parecen en nada (la 0068 al sellar un día roto, la 0089 al inventar
-- una hora de salida, la 0207 con una marca que cae en periodo pagado) y la
-- lista leía la columna sin preguntar cuál de las tres fue.
--
-- Lo que se defiende aquí es que el motivo se calcule EN VIVO y no se herede del
-- sello guardado: un sello dice que el día estuvo roto alguna vez, no que lo
-- siga estando. Esa lección ya la pagó la 0084 con el día de Estefany del 17/07.
-- ============================================================================
begin;
select plan(8);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000003fc', 'ZZ384', 'Sede de laboratorio 384', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id) values
  ('00000000-0000-0000-0000-0000000003d0', 'Admin384', 'Laboratorio', '00000000-0000-0000-0000-0000000003fc', 'admin', 'test-hash', '00000000-0000-0000-0000-0000000003e0');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash) values
  ('00000000-0000-0000-0000-0000000003d1', 'Aroto',   'Laboratorio', '00000000-0000-0000-0000-0000000003fc', 'test-hash'),
  ('00000000-0000-0000-0000-0000000003d2', 'Bcierre', 'Laboratorio', '00000000-0000-0000-0000-0000000003fc', 'test-hash'),
  ('00000000-0000-0000-0000-0000000003d3', 'Csello',  'Laboratorio', '00000000-0000-0000-0000-0000000003fc', 'test-hash');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000003e0', true);

-- ── A · Un día DE VERDAD imposible ──────────────────────────────────────────
-- Dos "salida a almuerzo" seguidas sin retorno entre medio. Se insertan ya
-- selladas porque lo que se prueba es la CLASIFICACIÓN, no quién puso el sello.
insert into marcajes (id, client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen, estado_revision) values
  ('00000000-0000-0000-0384-00000000000a', gen_random_uuid(), '00000000-0000-0000-0000-0000000003d1', '00000000-0000-0000-0000-0000000003fc', 'entrada',         '2026-07-20T09:00:00-05:00', 'terminal', 'pendiente_revision'),
  ('00000000-0000-0000-0384-00000000000b', gen_random_uuid(), '00000000-0000-0000-0000-0000000003d1', '00000000-0000-0000-0000-0000000003fc', 'salida_almuerzo', '2026-07-20T13:00:00-05:00', 'terminal', 'pendiente_revision'),
  ('00000000-0000-0000-0384-00000000000c', gen_random_uuid(), '00000000-0000-0000-0000-0000000003d1', '00000000-0000-0000-0000-0000000003fc', 'salida_almuerzo', '2026-07-20T17:00:00-05:00', 'terminal', 'pendiente_revision');

-- ── B · EL CASO DE LA CAPTURA: el día cuadra, falta confirmar el auto-cierre ─
-- La entrada queda 'normal' a propósito: el día entero NO está sellado, solo la
-- marca que inventó el robot. Es exactamente lo que se veía en producción.
insert into marcajes (id, client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen, estado_revision) values
  ('00000000-0000-0000-0384-000000000014', gen_random_uuid(), '00000000-0000-0000-0000-0000000003d2', '00000000-0000-0000-0000-0000000003fc', 'entrada',      '2026-07-21T10:26:00-05:00', 'terminal',    'normal'),
  ('00000000-0000-0000-0384-000000000015', gen_random_uuid(), '00000000-0000-0000-0000-0000000003d2', '00000000-0000-0000-0000-0000000003fc', 'salida_final', '2026-07-21T14:18:00-05:00', 'auto_cierre', 'pendiente_revision');

-- ── C · El residuo: el día cuadra, no hay auto-cierre, y el sello sigue puesto ─
-- Pasa cuando la marca que ARREGLA el día llega por el terminal:
-- fn_registrar_marcaje sella el día que queda roto (0366) y nunca lo desella.
insert into marcajes (id, client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen, estado_revision) values
  ('00000000-0000-0000-0384-00000000001e', gen_random_uuid(), '00000000-0000-0000-0000-0000000003d3', '00000000-0000-0000-0000-0000000003fc', 'entrada',      '2026-07-22T09:00:00-05:00', 'terminal', 'pendiente_revision'),
  ('00000000-0000-0000-0384-00000000001f', gen_random_uuid(), '00000000-0000-0000-0000-0000000003d3', '00000000-0000-0000-0000-0000000003fc', 'salida_final', '2026-07-22T18:00:00-05:00', 'terminal', 'pendiente_revision');


-- ── Lo que se defiende ──────────────────────────────────────────────────────

-- El corazón del defecto: el día de la captura NO era incoherente. Si esta
-- aserción se pusiera roja, el resto de la prueba no significaría nada.
select is((select fn_dia_incoherente('00000000-0000-0000-0000-0000000003d2', '2026-07-21')),
          false,
          'CAPTURA · el día del auto-cierre cuadra: Entrada → Salida final es posible');

select is((select motivo from fn_dias_por_revisar(100)
            where persona_id = '00000000-0000-0000-0000-0000000003d2'),
          'auto_cierre_sin_confirmar',
          'CAPTURA · y por eso NO se anuncia como secuencia imposible, sino como lo que es');

select is((select marcas from fn_dias_por_revisar(100)
            where persona_id = '00000000-0000-0000-0000-0000000003d2'),
          1,
          'CAPTURA · solo la marca del robot está sellada; el día entero no lo está');

select is((select motivo from fn_dias_por_revisar(100)
            where persona_id = '00000000-0000-0000-0000-0000000003d1'),
          'secuencia_imposible',
          'ROTO · dos salidas a almuerzo seguidas sí son una secuencia imposible');

select is((select motivo from fn_dias_por_revisar(100)
            where persona_id = '00000000-0000-0000-0000-0000000003d3'),
          'sello_sin_levantar',
          'RESIDUO · día que ya cuadra y se quedó con el sello puesto: se etiqueta, no se disfraza');

-- La lista no esconde a nadie. Es la promesa que la 0321 defendió con la 110 y
-- que esta migración no puede romper: distinguir no es filtrar.
select is((select count(*)::int from fn_dias_por_revisar(100)
            where sede = 'ZZ384'),
          3,
          'NADIE SE PIERDE · los tres días siguen en la lista, cada uno con su motivo');

-- Prioridad: si el día sigue roto, eso manda sobre cualquier otra cosa.
-- Confirmar una hora dentro de un día imposible no significa nada.
insert into marcajes (id, client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen, estado_revision) values
  ('00000000-0000-0000-0384-00000000000d', gen_random_uuid(), '00000000-0000-0000-0000-0000000003d1', '00000000-0000-0000-0000-0000000003fc', 'salida_final', '2026-07-20T22:00:00-05:00', 'auto_cierre', 'pendiente_revision');

select is((select motivo from fn_dias_por_revisar(100)
            where persona_id = '00000000-0000-0000-0000-0000000003d1'),
          'secuencia_imposible',
          'PRIORIDAD · un día roto que ADEMÁS tiene auto-cierre sigue anunciándose como roto');

-- Y el motivo se pregunta en vivo: en cuanto el día cuadra, deja de decir
-- "imposible" — aunque el sello guardado en las marcas no se haya movido.
-- Se anulan LAS DOS salidas a almuerzo, no una. Con una sola el día sigue
-- imposible: quedaría un almuerzo del que nunca se volvió y, detrás, una salida
-- final — que estando "fuera" tampoco es el retorno que toca. Lo que deja el día
-- limpio es `Entrada → Salida final`, que es la secuencia de la captura.
select fn_anular_marcaje('00000000-0000-0000-0384-00000000000c', 'La segunda salida a almuerzo sobraba');
select fn_anular_marcaje('00000000-0000-0000-0384-00000000000b', 'Ese almuerzo nunca ocurrió: no volvió a marcar');

select is((select motivo from fn_dias_por_revisar(100)
            where persona_id = '00000000-0000-0000-0000-0000000003d1'),
          'auto_cierre_sin_confirmar',
          'EN VIVO · arreglado el día, el motivo cambia solo: el sello es una foto, no una sentencia');

select * from finish();
rollback;
