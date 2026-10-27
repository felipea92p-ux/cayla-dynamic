-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 444_los_parametros_tienen_puerta_y_dejan_rastro.test.sql — la 0552
-- ============================================================================
-- Defiende la 0552: los números del sistema que se cambian desde «Parámetros».
-- Cuatro cosas, y las cuatro hacen falta:
--   1. QUIÉN: DO cambia lo operativo; la líder de equipo y la integrante, ni
--      ven ni cambian; lo normativo es solo de la dirección; lo que fija una
--      norma no lo cambia nadie desde acá.
--   2. QUÉ: el mínimo, el máximo, «entero» y el motivo se exigen —por la
--      puerta Y por el SQL Editor—; un cambio que no cambia nada no ensucia.
--   3. EL RASTRO: cada cambio deja quién, cuándo, de qué a qué y por qué; el
--      cambio hecho a mano se ve como tal; el historial no se toca.
--   4. EL CANDADO: un UPDATE directo desde el navegador a una clave con
--      parámetros se rechaza, y una clave SIN parámetros (Apariencia) sigue
--      escribiéndose como siempre — un freno que también detiene eso rompería
--      una pantalla que hoy funciona.
--
-- Y lo que prueba que el número ya no está clavado: `fn_prueba_dias_plazo()`
-- sigue lo que diga `configuracion.prueba_dias`, y `fn_pruebas_abiertas()` (la
-- que usa el panel) lo recibe como columna.
--
-- OJO CON EL `session_replication_role`: el fixture se monta con `= replica` y
-- se devuelve a `origin` ANTES de cualquier ataque. Si no, se apagan en
-- silencio todos los triggers de la sesión, incluido el que esta prueba defiende.
-- ============================================================================
begin;
select plan(55);

-- ── Fixture: cuatro roles y una persona de prueba ───────────────────────────
insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000044301', 'ZZ444', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000004431a', 'integrante-443@local'),
  ('00000000-0000-0000-0000-00000004431b', 'lider-equipo-443@local'),
  ('00000000-0000-0000-0000-00000004431c', 'do-443@local'),
  ('00000000-0000-0000-0000-00000004431d', 'admin-443@local');
insert into personas (id, nombres, apellidos, sede_base_id, rol, estado, pin_hash, auth_user_id, fecha_ingreso, fecha_cese, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000044311', 'Integrante', 'Comun',  '00000000-0000-0000-0000-000000044301',
   'integrante',      'activo', 'x', '00000000-0000-0000-0000-00000004431a', '2024-01-01', null, 'planilla'),
  ('00000000-0000-0000-0000-000000044312', 'Lider',      'Equipo', '00000000-0000-0000-0000-000000044301',
   'supervisor_sede', 'activo', 'x', '00000000-0000-0000-0000-00000004431b', '2024-01-01', null, 'planilla'),
  ('00000000-0000-0000-0000-000000044313', 'Lider',      'DO',     '00000000-0000-0000-0000-000000044301',
   'lider_do',        'activo', 'x', '00000000-0000-0000-0000-00000004431c', '2024-01-01', null, 'planilla'),
  ('00000000-0000-0000-0000-000000044314', 'Direccion',  'Admin',  '00000000-0000-0000-0000-000000044301',
   'admin',           'activo', 'x', '00000000-0000-0000-0000-00000004431d', '2024-01-01', null, 'planilla'),
  ('00000000-0000-0000-0000-000000044315', 'Persona',    'Prueba', '00000000-0000-0000-0000-000000044301',
   'integrante',      'activo', 'x', null, current_date, null, 'prueba');
set session_replication_role = origin;

-- ── 0 · Lo instalado ────────────────────────────────────────────────────────
select is(
  (select array_agg(parametro order by orden) from parametros_catalogo),
  array['prueba_dias', 'auto_cierre_horas', 'descanso_medico_avisar_desde', 'descanso_medico_tope_essalud']::text[],
  'El catálogo trae los cuatro parámetros de la primera rebanada, en su orden');

select is(
  (select count(*)::int from pg_trigger
    where tgname = 'trg_parametros_guardar_cambio' and tgrelid = 'configuracion'::regclass and tgenabled = 'O'),
  1, 'El candado existe en configuracion y está activo');

-- Si alguien lo marcara SECURITY DEFINER, current_user valdría siempre `postgres`
-- y no frenaría nada, sin dar ningún error: la falla más callada posible.
select is(
  (select prosecdef from pg_proc where proname = 'fn_parametros_guardar_cambio' and pronamespace = 'public'::regnamespace),
  false, 'El candado NO es SECURITY DEFINER (si lo fuera, current_user sería siempre postgres y dejaría pasar todo)');

select is(fn_prueba_dias_plazo(), 3, 'Los días de prueba arrancan en 3, los de siempre');

-- El 3 del final de la función (el que se usa si falta la fila) y el valor de
-- partida del catálogo son dos copias del mismo número: tienen que coincidir.
delete from configuracion where clave = 'prueba_dias';
select is(
  fn_prueba_dias_plazo(),
  (select valor_defecto::int from parametros_catalogo where parametro = 'prueba_dias'),
  'Sin la fila, la función cae en el valor de partida del catálogo (el 3 de antes)');

-- Pedir el valor que YA rige (aquí, el de partida, porque no hay fila) es un cambio vacío:
-- no escribe nada, ni siquiera crea la fila. Un «cambio» que no cambia no deja huella.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004431c', true);
set role authenticated;
select lives_ok(
  $$ select fn_parametro_cambiar('prueba_dias', 3, 'Pedir lo que ya rige no escribe nada') $$,
  'Pedir el valor que ya rige no falla');
reset role;
select is((select count(*)::int from configuracion where clave = 'prueba_dias'), 0,
  'Y tampoco crea la fila: un cambio vacío no escribe');
select is((select count(*)::int from parametros_historial), 0, 'Ni una fila de historial');
insert into configuracion (clave, valor) values ('prueba_dias', '3'::jsonb);

-- ── 1 · Quién ve y quién cambia ─────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004431a', true);
set role authenticated;

select throws_ok(
  $$ select * from fn_parametros_listar() $$,
  'Solo la dirección o Desarrollo Organizacional puede ver los parámetros.',
  'LA INTEGRANTE no ve la lista de parámetros');
select throws_ok(
  $$ select fn_parametro_cambiar('prueba_dias', 5, 'Probando con cinco') $$,
  'Solo la dirección o Desarrollo Organizacional puede cambiar parámetros.',
  'LA INTEGRANTE no cambia parámetros');
select throws_ok(
  $$ select * from fn_parametros_historial() $$,
  'Solo la dirección o Desarrollo Organizacional puede ver el historial de parámetros.',
  'LA INTEGRANTE no ve el historial');

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004431b', true);
set role authenticated;

select throws_ok(
  $$ select fn_parametro_cambiar('prueba_dias', 5, 'Probando con cinco') $$,
  'Solo la dirección o Desarrollo Organizacional puede cambiar parámetros.',
  'LA LÍDER DE EQUIPO no cambia parámetros: ni siquiera una operativa');
select throws_ok(
  $$ select * from fn_parametros_listar() $$,
  'Solo la dirección o Desarrollo Organizacional puede ver los parámetros.',
  'LA LÍDER DE EQUIPO no ve la lista de parámetros');

reset role;
select is((select count(*)::int from parametros_historial), 0,
  'Nada de lo anterior dejó rastro: los rechazos no escriben historial');

-- ── 2 · DO opera lo operativo y deja su rastro ──────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004431c', true);
set role authenticated;

select lives_ok(
  $$ select fn_parametro_cambiar('prueba_dias', 5, 'Probamos con cinco días a ver cuántas personas cumplen') $$,
  'DO cambia los días de prueba de 3 a 5');

reset role;
select is(fn_prueba_dias_plazo(), 5, 'La función de los días de prueba ya devuelve 5');
select is((select valor from configuracion where clave = 'prueba_dias'), '5'::jsonb,
  'Se guardó un 5 limpio (no 5.0): lo que otras funciones castean con ::int');
select is(
  (select valor_anterior || ' → ' || valor_nuevo || ' · ' || origen || ' · ' || (cambiado_por = '00000000-0000-0000-0000-000000044313')::text || ' · ' || motivo
     from parametros_historial where parametro = 'prueba_dias'),
  '3 → 5 · pantalla · true · Probamos con cinco días a ver cuántas personas cumplen',
  'El historial dice de qué a qué, por la pantalla, QUIÉN (la de DO) y POR QUÉ');
select is(coalesce(nullif(current_setting('cayla.parametro_actor', true), ''), 'vacío'), 'vacío',
  'El autor no queda pegado a la transacción: lo que siga a mano no hereda su nombre');

-- La función que usa el panel (fn_pruebas_abiertas) recibe el plazo nuevo como columna.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004431c', true);
set role authenticated;
select is(
  (select dias_plazo from fn_pruebas_abiertas() where persona_id = '00000000-0000-0000-0000-000000044315'),
  5, 'El panel de pruebas recibe el plazo nuevo (5) como columna, sin cambiar ninguna pantalla');

-- Un cambio que no cambia nada no ensucia el historial.
select lives_ok(
  $$ select fn_parametro_cambiar('prueba_dias', 5, 'Lo mismo otra vez, a ver qué pasa') $$,
  'Cambiar a lo que ya vale no falla');
reset role;
select is((select count(*)::int from parametros_historial where parametro = 'prueba_dias'), 1,
  'Y no suma una fila al historial: sin ruido');

-- Un campo dentro de un objeto: se cambia ese, y el vecino queda como estaba.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004431c', true);
set role authenticated;
select lives_ok(
  $$ select fn_parametro_cambiar('descanso_medico_avisar_desde', 12, 'Avisar con más margen antes de los 20') $$,
  'DO cambia desde cuántos días de descanso médico se avisa');
select lives_ok(
  $$ select fn_parametro_cambiar('auto_cierre_horas', 4, 'Los cierres de la tarde se están adelantando') $$,
  'DO cambia las horas del auto-cierre');
reset role;
select is((select valor from configuracion where clave = 'descanso_medico_aviso_dias'),
  '{"avisar_desde": 12, "umbral_essalud": 20}'::jsonb,
  'Se movió avisar_desde y el tope de 20 del RIT quedó intacto');
select is((select valor from configuracion where clave = 'auto_cierre_horas'), '4'::jsonb,
  'El auto-cierre quedó en 4, como número (lo lee fn_auto_cierre con ::int)');

-- ── 3 · Los límites y el motivo ─────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004431c', true);
set role authenticated;

select throws_ok(
  $$ select fn_parametro_cambiar('prueba_dias', 0, 'Cero días no tiene sentido') $$,
  '«Días de preselección antes del contrato» va de 1 a 15 días.',
  'Por debajo del mínimo: rechazado, y dice el rango');
select throws_ok(
  $$ select fn_parametro_cambiar('prueba_dias', 30, 'Un dedo de más en la tecla') $$,
  '«Días de preselección antes del contrato» va de 1 a 15 días.',
  'Por encima del máximo (el 30 en vez del 3): rechazado');
select throws_ok(
  $$ select fn_parametro_cambiar('prueba_dias', 2.5, 'Dos días y medio') $$,
  '«Días de preselección antes del contrato» tiene que ser un número entero.',
  'Un decimal en un parámetro entero: rechazado');
select throws_ok(
  $$ select fn_parametro_cambiar('prueba_dias', null, 'Sin valor') $$,
  'Falta el valor nuevo.',
  'Sin valor: rechazado');
select throws_ok(
  $$ select fn_parametro_cambiar('prueba_dias', 4, 'ab') $$,
  'Escribe el motivo del cambio: es lo que explica el número dentro de un año.',
  'Un motivo de dos letras no es un motivo');
select throws_ok(
  $$ select fn_parametro_cambiar('no_existe', 4, 'Parámetro que no existe') $$,
  'No existe el parámetro «no_existe».',
  'Un parámetro que no está en el catálogo: rechazado');

reset role;
select is((select valor from configuracion where clave = 'prueba_dias'), '5'::jsonb,
  'Ningún rechazo movió el valor');

-- ── 4 · Lo que fija una norma no se cambia desde acá, ni la dirección ───────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004431d', true);
set role authenticated;
select throws_ok(
  $$ select fn_parametro_cambiar('descanso_medico_tope_essalud', 30, 'Subimos el tope a treinta') $$,
  '«Días de descanso médico a cargo de CAYLA en el año» lo fija una norma. Base: RIT art. 31 f) (migración 0254). No se cambia desde Parámetros.',
  'El tope de 20 días del RIT: ni la dirección lo cambia desde Parámetros');
reset role;
select is(
  (select valor from configuracion where clave = 'descanso_medico_aviso_dias'),
  '{"avisar_desde": 12, "umbral_essalud": 20}'::jsonb,
  'El tope de 20 sigue en 20: es lo que usa la planilla para decidir qué días paga CAYLA');

-- ── 5 · Lo normativo editable es solo de la dirección ───────────────────────
-- Una fila de laboratorio: hoy no hay ningún normativo editable (la escalera
-- disciplinaria entra después, atada a una versión del RIT).
insert into parametros_catalogo
  (parametro, nombre, descripcion, unidad, clase, tipo_valor, valor_min, valor_max, valor_defecto, almacen_clave, editable)
values ('zz_normativo_444', 'Normativo de laboratorio', 'Solo para esta prueba.', 'veces', 'normativo', 'entero', 1, 9, 5, 'zz_normativo_444', true);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004431c', true);
set role authenticated;
select throws_ok(
  $$ select fn_parametro_cambiar('zz_normativo_444', 7, 'DO intenta tocar lo normativo') $$,
  'Solo la dirección puede cambiar un parámetro normativo.',
  'DO NO cambia un parámetro normativo (decisión: solo la dirección)');
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004431d', true);
set role authenticated;
select lives_ok(
  $$ select fn_parametro_cambiar('zz_normativo_444', 7, 'La dirección sí puede, con su motivo') $$,
  'La dirección sí cambia un parámetro normativo editable');
reset role;
select is((select valor from configuracion where clave = 'zz_normativo_444'), '7'::jsonb,
  'Y si la fila no existía, la puerta la creó con el valor nuevo');

-- ── 6 · El candado: nada de escrituras directas ─────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004431c', true);
set role authenticated;

select throws_ok(
  $$ update configuracion set valor = '9'::jsonb where clave = 'prueba_dias' $$,
  'Este valor se cambia desde Parámetros, no con una escritura directa a la tabla.',
  'BLOQUEADO · un UPDATE directo de DO sobre los días de prueba (el PATCH armado a mano)');
select throws_ok(
  $$ delete from configuracion where clave = 'auto_cierre_horas' $$,
  'Este valor se cambia desde Parámetros, no con una escritura directa a la tabla.',
  'BLOQUEADO · borrar la fila (volvería al valor de partida sin dejar rastro)');
select throws_ok(
  $$ insert into configuracion (clave, valor) values ('descanso_medico_aviso_dias', '{"avisar_desde": 1, "umbral_essalud": 1}'::jsonb) $$,
  'Este valor se cambia desde Parámetros, no con una escritura directa a la tabla.',
  'BLOQUEADO · un INSERT directo sobre una clave del catálogo');

-- Y lo que no es un parámetro se escribe como siempre.
select lives_ok(
  $$ update configuracion set valor = '"oscuro"'::jsonb where clave = 'apariencia_tema' $$,
  'PERMITIDO · Apariencia sigue escribiendo su clave directo: no está en el catálogo');
reset role;
select is((select valor from configuracion where clave = 'apariencia_tema'), '"oscuro"'::jsonb,
  'Y el cambio de Apariencia quedó escrito: el candado no se llevó puesto lo que ya funcionaba');

-- La llave de servicio tampoco escribe directo: solo pasan las funciones definer.
set role service_role;
select throws_ok(
  $$ update configuracion set valor = '9'::jsonb where clave = 'prueba_dias' $$,
  'Este valor se cambia desde Parámetros, no con una escritura directa a la tabla.',
  'BLOQUEADO · service_role tampoco escribe directo (decisión escrita en la 0552)');
reset role;

-- ── 7 · A mano en el SQL Editor: se deja ver y se acota ─────────────────────
update configuracion set valor = '8'::jsonb where clave = 'prueba_dias';
select is(
  (select valor_anterior || ' → ' || valor_nuevo || ' · ' || origen || ' · ' || coalesce(cambiado_por::text, 'sin autor') || ' · ' || motivo
     from parametros_historial where parametro = 'prueba_dias' order by cambiado_at desc, id desc limit 1),
  '5 → 8 · base · sin autor · Cambio hecho directamente en la base de datos, sin motivo escrito.',
  'Un cambio a mano queda en el historial como «base», sin autor y diciendo que no tiene motivo');
select throws_ok(
  $$ update configuracion set valor = '99'::jsonb where clave = 'prueba_dias' $$,
  '«Días de preselección antes del contrato» va de 1 a 15 días (llegó 99).',
  'El máximo también ataja al SQL Editor: el 99 por el 9 no entra');
select throws_ok(
  $$ update configuracion set valor = '3.5'::jsonb where clave = 'prueba_dias' $$,
  '«Días de preselección antes del contrato» tiene que ser un número entero (llegó 3.5).',
  'Y un decimal tampoco');

-- ── 8 · El historial no se toca ─────────────────────────────────────────────
select throws_ok(
  $$ update parametros_historial set motivo = 'reescribir la historia' $$,
  'El historial de parámetros no se edita ni se borra: volver atrás es un cambio nuevo con el valor anterior.',
  'El historial no se edita, ni siquiera como postgres');
select throws_ok(
  $$ delete from parametros_historial $$,
  'El historial de parámetros no se edita ni se borra: volver atrás es un cambio nuevo con el valor anterior.',
  'Ni se borra');

-- ── 9 · Cómo se lee ─────────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004431c', true);
set role authenticated;

select is(
  (select ultimo_cambio_por || ' · ' || ultimo_origen || ' · ' || valor_actual::text
     from fn_parametros_listar() where parametro = 'descanso_medico_avisar_desde'),
  'Lider DO · pantalla · 12',
  'La lista dice el valor de hoy y quién fue el último en cambiarlo');
select is(
  (select ultimo_origen || ' · ' || coalesce(ultimo_cambio_por, 'nadie')
     from fn_parametros_listar() where parametro = 'prueba_dias'),
  'base · nadie',
  'Y para el cambio a mano dice «base» y «nadie»: se ve que no pasó por la pantalla');
select is(
  (select cambiado_por from fn_parametros_historial('descanso_medico_avisar_desde')),
  'Lider DO',
  'El historial trae el nombre de quien cambió, no un id');
select is(
  (select count(*)::int from fn_parametros_historial('prueba_dias', 1)),
  1, 'El límite del historial se respeta');

-- Nadie lee las tablas directo: el historial por la función, y punto.
select throws_ok(
  $$ select * from parametros_historial $$,
  '42501', null,
  'El historial no se lee directo desde el navegador: solo por la función con guardia');
select lives_ok(
  $$ select * from parametros_catalogo $$,
  'El catálogo sí es legible con login (no tiene nada sensible, y el candado de invocador tiene que poder leerlo)');
reset role;

select * from finish();
rollback;
