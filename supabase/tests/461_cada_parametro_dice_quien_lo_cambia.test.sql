-- ============================================================================
-- 461_cada_parametro_dice_quien_lo_cambia.test.sql
-- ============================================================================
-- Migración 0571. Cada parámetro del catálogo dice en `roles_cambia` quién puede
-- cambiarlo, y `fn_parametro_cambiar` lo respeta.
--
-- LO QUE DEFIENDE, EN ESTE ORDEN:
--   1. los cuatro parámetros de hoy se comportan igual que antes: los operativos
--      siguen siendo de admin y DO, el normativo de la dirección;
--   2. un parámetro NUEVO nace solo para la dirección ({admin});
--   3. DO NO cambia uno que es solo de la dirección, aunque entre a la pantalla;
--      la dirección sí;
--   4. abrirlo a DO es un cambio de datos: DO ya puede, sin tocar ningún código;
--   5. el catálogo rechaza roles inventados, una lista vacía y un normativo
--      abierto a DO (los dos CHECK);
--   6. `fn_parametros_listar` entrega `roles_cambia` y `puede_cambiar` según
--      QUIEN pregunta.
-- Va con `fn_rol_actual()::text`: el rol es un enum y compararlo con un texto sin
-- cast falla con «operator does not exist» (la primera pasada de la migración).
-- ============================================================================
begin;
select plan(16);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000461001', 'ZZ461', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000046101c', 'do-461@local'),
  ('00000000-0000-0000-0000-00000046101d', 'admin-461@local');
insert into personas (id, nombres, apellidos, sede_base_id, rol, estado, pin_hash, auth_user_id, fecha_ingreso, fecha_cese, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000461013', 'Lider',     'DO',    '00000000-0000-0000-0000-000000461001',
   'lider_do', 'activo', 'x', '00000000-0000-0000-0000-00000046101c', '2024-01-01', null, 'planilla'),
  ('00000000-0000-0000-0000-000000461014', 'Direccion', 'Admin', '00000000-0000-0000-0000-000000461001',
   'admin',    'activo', 'x', '00000000-0000-0000-0000-00000046101d', '2024-01-01', null, 'planilla');
set session_replication_role = origin;

-- ── 1 · Los de hoy no cambian ───────────────────────────────────────────────
select is((select roles_cambia from parametros_catalogo where parametro = 'prueba_dias'),
          array['admin', 'lider_do']::text[], 'Los días de prueba siguen siendo de admin y DO');
select is((select roles_cambia from parametros_catalogo where parametro = 'descanso_medico_tope_essalud'),
          array['admin']::text[], 'El tope normativo sigue siendo solo de la dirección');

-- ── 2 · Un parámetro nuevo nace solo para la dirección ──────────────────────
insert into parametros_catalogo
  (parametro, nombre, descripcion, unidad, clase, tipo_valor, valor_min, valor_max, valor_defecto, almacen_clave, editable)
values ('zz_plata_461', 'Plata de laboratorio', 'Solo para esta prueba.', 'horas', 'plata', 'entero', 1, 40, 30, 'zz_plata_461', true);
select is((select roles_cambia from parametros_catalogo where parametro = 'zz_plata_461'),
          array['admin']::text[], 'Un parámetro nuevo nace {admin}');

-- ── 3 · DO no lo cambia; la dirección sí ────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000046101c', true);
set role authenticated;
select throws_ok(
  $$ select fn_parametro_cambiar('zz_plata_461', 20, 'DO intenta tocar un parámetro solo de la dirección') $$,
  'Tu rol no puede cambiar «Plata de laboratorio». Pueden: admin.',
  'DO NO cambia un parámetro que es solo de la dirección');
reset role;
select is((select count(*)::int from configuracion where clave = 'zz_plata_461'), 0,
          'Y no quedó ninguna fila escrita');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000046101d', true);
set role authenticated;
select lives_ok(
  $$ select fn_parametro_cambiar('zz_plata_461', 20, 'La dirección sí puede, con su motivo') $$,
  'La dirección sí lo cambia');
reset role;
select is((select valor from configuracion where clave = 'zz_plata_461'), '20'::jsonb, 'Y quedó el valor nuevo');

-- ── 4 · Abrirlo a DO es un cambio de datos ──────────────────────────────────
update parametros_catalogo set roles_cambia = array['admin', 'lider_do'] where parametro = 'zz_plata_461';
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000046101c', true);
set role authenticated;
select lives_ok(
  $$ select fn_parametro_cambiar('zz_plata_461', 25, 'Ahora DO también puede') $$,
  'Con roles_cambia = {admin, lider_do}, DO cambia el parámetro sin tocar código');
reset role;

-- ── 5 · El catálogo ataja lo imposible ──────────────────────────────────────
select throws_ok(
  $$ update parametros_catalogo set roles_cambia = array['supervisor_sede'] where parametro = 'zz_plata_461' $$,
  '23514', null, 'Un rol que no entra a Parámetros se rechaza');
select throws_ok(
  $$ update parametros_catalogo set roles_cambia = array[]::text[] where parametro = 'zz_plata_461' $$,
  '23514', null, 'Una lista vacía se rechaza: nadie podría cambiarlo');
select throws_ok(
  $$ update parametros_catalogo set roles_cambia = array['admin', 'lider_do'] where parametro = 'descanso_medico_tope_essalud' $$,
  '23514', null, 'Un parámetro normativo no se abre a DO');

-- ── 6 · La lista dice quién puede ───────────────────────────────────────────
update parametros_catalogo set roles_cambia = array['admin'] where parametro = 'zz_plata_461';

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000046101c', true);
set role authenticated;
select is((select puede_cambiar from fn_parametros_listar() where parametro = 'zz_plata_461'), false,
          'Para DO, el parámetro solo de la dirección sale puede_cambiar = false');
select is((select puede_cambiar from fn_parametros_listar() where parametro = 'prueba_dias'), true,
          'Para DO, los días de prueba salen puede_cambiar = true');
select is((select puede_cambiar from fn_parametros_listar() where parametro = 'descanso_medico_tope_essalud'), false,
          'Lo normativo no editable sale false para todos');
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000046101d', true);
set role authenticated;
select is((select puede_cambiar from fn_parametros_listar() where parametro = 'zz_plata_461'), true,
          'Para la dirección, el parámetro solo de la dirección sale puede_cambiar = true');
select is((select roles_cambia from fn_parametros_listar() where parametro = 'zz_plata_461'),
          array['admin']::text[], 'La lista entrega los roles de cada parámetro');
reset role;

select * from finish();
rollback;
