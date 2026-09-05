-- ============================================================================
-- 221_el_kiosco_no_ve_sueldos.test.sql
-- ============================================================================
-- Defiende la 0285. El terminal de marcaje es una Mac mini a pantalla completa,
-- a la vista de todo el equipo y sin PIN — decisión tomada y correcta. Lo que
-- no puede ser es que además su token alcance el padrón con sueldos.
--
-- Y no era un fallo de la policy: RLS filtra FILAS, no COLUMNAS. La policy
-- acotaba bien a la sede, y no podía hacer lo otro. Por eso la respuesta es una
-- vista con cinco columnas y no una policy mejor: no existe una policy mejor.
--
-- LAS DOS MITADES. Se prueba que el sueldo y el DNI NO estén, y —la que se
-- olvida— que el terminal SIGA VIENDO lo que necesita para marcar. Una vista
-- que no deja ver nada es una sede que no puede fichar.
--
-- Y LAS TRES QUE NO SE PUEDEN PERDER AL CAMBIAR DE SUPERFICIE, porque son las
-- que la policy de la 0008 ya garantizaba: el aislamiento entre sedes, la
-- excepción de `visible_todas_sedes`, y que un terminal DESACTIVADO no vea a
-- nadie (la 0202 obliga a desactivarlo antes de borrar su cuenta).
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000022100', 'ZZ221', 'Sede del kiosco',  true),
  ('00000000-0000-0000-0000-000000022200', 'ZZ222', 'Sede de al lado',  true);

set session_replication_role = replica;
insert into terminales (id, sede_id, nombre_dispositivo, activo, auth_user_id) values
  ('00000000-0000-0000-0000-00000002210e', '00000000-0000-0000-0000-000000022100',
   'Mac mini de la sede',   true,  '00000000-0000-0000-0000-00000002210f'),
  ('00000000-0000-0000-0000-00000002220e', '00000000-0000-0000-0000-000000022200',
   'Mac mini de al lado',   true,  '00000000-0000-0000-0000-00000002220f'),
  ('00000000-0000-0000-0000-00000002230e', '00000000-0000-0000-0000-000000022100',
   'Mac mini jubilada',     false, '00000000-0000-0000-0000-00000002230f');

-- Datos INVENTADOS: ni un DNI ni un sueldo real entra en una prueba.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso,
                      documento, sueldo_base_legal, cobra_movilidad, tipo_vinculo,
                      estado, visible_todas_sedes, auth_user_id) values
  ('00000000-0000-0000-0000-000000022101', 'DeLaSede',  'Kiosco221',
   '00000000-0000-0000-0000-000000022100', 'x', '2024-01-01', '00000000', 1130.00,
   true, 'planilla', 'activo', false, '00000000-0000-0000-0000-0000000221af'),
  ('00000000-0000-0000-0000-000000022102', 'DeAlLado',  'Kiosco221',
   '00000000-0000-0000-0000-000000022200', 'x', '2024-01-01', '00000001', 1130.00,
   true, 'planilla', 'activo', false, null),
  ('00000000-0000-0000-0000-000000022103', 'Volante',   'Kiosco221',
   '00000000-0000-0000-0000-000000022200', 'x', '2024-01-01', '00000002', 1130.00,
   true, 'planilla', 'activo', true,  null),
  ('00000000-0000-0000-0000-000000022105', 'Sobrante', 'Kiosco221',
   '00000000-0000-0000-0000-000000022200', 'x', '2024-01-01', '00000004', 1130.00,
   true, 'planilla', 'activo', false, null);

-- Quien ya cesó va aparte: `personas_cese_coherente` exige que el estado
-- inactivo y la fecha de cese entren en la MISMA fila, no en dos pasos.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso,
                      documento, sueldo_base_legal, cobra_movilidad, tipo_vinculo,
                      estado, visible_todas_sedes, auth_user_id,
                      fecha_cese, motivo_cese)
values ('00000000-0000-0000-0000-000000022104', 'YaNoEsta', 'Kiosco221',
        '00000000-0000-0000-0000-000000022100', 'x', '2024-01-01', '00000003', 1130.00,
        true, 'planilla', 'inactivo', false, null, '2025-01-01', 'renuncia');
set session_replication_role = origin;


-- ── 1-2 · Lo que la vista NO puede tener ────────────────────────────────────
select is_empty(
  $$ select column_name from information_schema.columns
      where table_name = 'terminal_roster'
        and column_name in ('documento', 'sueldo_base_legal', 'email',
                            'regimen_pension', 'fecha_ingreso', 'fecha_cese') $$,
  'NADA SENSIBLE · la vista no tiene DNI, ni sueldo, ni correo, ni régimen de pensión');

-- SEIS desde la 0383, que adoptó `foto_url`. El conteo es el guardián
-- SECUNDARIO: el que de verdad protege es el `is_empty` de arriba, que nombra
-- las columnas peligrosas una por una y sigue intacto. Subir este número al
-- adoptar una columna benigna no afloja esa garantía; lo que la aflojaría es
-- quitar aquél.
--
-- Ojo si vuelve a subir: un conteo no distingue una foto de un sueldo. Antes de
-- cambiarlo, comprueba que la columna nueva esté en la lista de `NADA SENSIBLE`
-- si lo es, o que de verdad haga falta para pintar la lista si no lo es.
select ok(
  (select count(*) from information_schema.columns
    where table_name = 'terminal_roster') = 6,
  'SEIS COLUMNAS · las que hacen falta para pintar la lista y ni una más');

-- La sexta era `pin_hash`, y se fue con la 0375: el terminal dejó de pedir PIN,
-- así que descargarle a cada Mac mini el hash de toda su sede era regalar un
-- dato que ya no compara nadie.
select is_empty(
  $$ select 1 from information_schema.columns
      where table_name = 'terminal_roster' and column_name = 'pin_hash' $$,
  'SIN EL HASH · el kiosco ya no descarga el pin_hash de nadie');


-- ── 3-4 · Lo que el terminal SÍ tiene que poder hacer ───────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000002210f', true);
set role authenticated;

select ok(
  (select count(*) from terminal_roster) > 0,
  'PUEDE MARCAR · el terminal sigue viendo a su gente; una vista vacía es una sede sin fichar');

select is(
  (select sede_codigo from terminal_roster
    where nombres = 'DeLaSede' limit 1),
  'ZZ221',
  'TRAE LA SEDE · el nombre de la sede viaja, que es lo que la pantalla pinta arriba');


-- ── 5-6 · El aislamiento que la policy de la 0008 ya daba ───────────────────
select is_empty(
  $$ select 1 from terminal_roster where nombres = 'DeAlLado' $$,
  'OTRA SEDE · el kiosco de una sede no ve a quien es de otra');

select isnt_empty(
  $$ select 1 from terminal_roster where nombres = 'Volante' $$,
  'VISIBLE EN TODAS · quien rota entre sedes sí aparece, como en la 0008');


-- ── 7 · Quien ya no está tampoco aparece ────────────────────────────────────
select is_empty(
  $$ select 1 from terminal_roster where nombres = 'YaNoEsta' $$,
  'INACTIVA · quien cesó no sale en la lista del terminal');


-- ── 8 · Y quien no es un terminal no ve NADA ────────────────────────────────
-- Es lo único que hace segura a esta vista: no el grant —lo tiene toda sesión
-- autenticada— sino `fn_sede_actual_terminal()`, que da null a quien no es un
-- terminal activo. Sin esto, cualquier integrante con cuenta leería el padrón.
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000221af', true);
set role authenticated;

select is(
  (select count(*)::int from terminal_roster),
  0,
  'NO ES UN TERMINAL · una integrante con cuenta no ve ni una fila, aunque tenga el grant');

reset role;
select * from finish();
rollback;
