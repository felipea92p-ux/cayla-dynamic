-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 290_el_pin_nace_en_el_servidor.test.sql
-- ============================================================================
-- Cubre la 0364 (hallazgo 22 de la auditoría del 2026-09-03/04). «Nuevo PIN»
-- en Equipo hasheaba en el navegador y escribía `personas.pin_hash` por REST
-- directo; lo único que lo frenaba era la RLS. Ahora hay UNA puerta,
-- `fn_regenerar_pin`, y un candado que cierra la escritura directa.
--
-- Lo que este archivo defiende, y que se rompe por separado:
--
--   1. La puerta funciona: devuelve 4 dígitos, el hash guardado es bcrypt
--      (`$2a$10$…`, el formato que bcryptjs compara en el terminal) y ese hash
--      RECONOCE el PIN devuelto. Si el hash no reconociera el PIN, nadie lo
--      notaría al pegar la migración: se notaría cuando una integrante no
--      pudiera marcar.
--   2. La puerta pasa el candado desde una sesión `authenticated` — que es
--      como llega por PostgREST. Es la mitad que un `security definer` mal
--      declarado rompería en silencio.
--   3. Solo admin o líder la abren: lider_do sí, supervisor_sede NO (la RLS
--      que se espeja distingue exactamente esos dos, y el encabezado de la
--      0364 promete no ampliar), una integrante no; una persona inactiva no
--      recibe PIN; y sin sesión (`anon`) ni siquiera se puede llamar.
--   4. El UPDATE directo a `pin_hash` como `authenticated` se bloquea AUNQUE
--      la RLS lo deje pasar (la sesión es de admin a propósito: es el trigger
--      el que corta, no la política).
--   5. Y editar cualquier OTRA columna por ese mismo camino sigue funcionando:
--      el candado es `of pin_hash`, no un candado sobre la fila.
--
-- OJO CON EL `session_replication_role`: el fixture se monta en `replica`
-- para saltar el candado del rol; si no se devuelve a
-- `origin` antes de probar, TODOS los triggers quedan apagados, incluido el
-- que esta prueba defiende — un falso negativo que parece «no hay bug».
-- ============================================================================
begin;
select plan(15);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000290000', 'ZZ290', 'Sede de laboratorio', true);

-- Las cuentas existen de verdad en auth.users: la FK `personas_auth_user_id_fkey`
-- se vuelve a comprobar en cada UPDATE de la fila, y el RPC hace uno.
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000002900a1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'admin-290@prueba.local', 'x', now(), now(), now()),
  ('00000000-0000-0000-0000-0000002900a2', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'integrante-290@prueba.local', 'x', now(), now(), now()),
  ('00000000-0000-0000-0000-0000002900a3', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'lider-290@prueba.local', 'x', now(), now(), now()),
  ('00000000-0000-0000-0000-0000002900a4', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'encargada-290@prueba.local', 'x', now(), now(), now());

-- `replica` solo para saltar el candado del rol (0296) al sembrar una admin.
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, estado, fecha_cese) values
  ('00000000-0000-0000-0000-000000290001', 'Admin',      'Laboratorio', '00000000-0000-0000-0000-000000290000',
   'admin',      'x', '00000000-0000-0000-0000-0000002900a1', 'activo',   null),
  ('00000000-0000-0000-0000-000000290002', 'Integrante', 'Laboratorio', '00000000-0000-0000-0000-000000290000',
   'integrante', 'x', '00000000-0000-0000-0000-0000002900a2', 'activo',   null),
  ('00000000-0000-0000-0000-000000290003', 'Cesada',     'Laboratorio', '00000000-0000-0000-0000-000000290000',
   'integrante', 'x', null,                                   'inactivo', '2026-06-30'),
  ('00000000-0000-0000-0000-000000290004', 'Lider',      'Laboratorio', '00000000-0000-0000-0000-000000290000',
   'lider_do',   'x', '00000000-0000-0000-0000-0000002900a3', 'activo',   null),
  ('00000000-0000-0000-0000-000000290005', 'Encargada',  'Laboratorio', '00000000-0000-0000-0000-000000290000',
   'supervisor_sede', 'x', '00000000-0000-0000-0000-0000002900a4', 'activo', null);
set session_replication_role = origin;

-- ── 1 · La puerta, con sesión de admin ──────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000002900a1', true);

create temp table pin_290 as
  select fn_regenerar_pin('00000000-0000-0000-0000-000000290002') as pin;

select matches(
  (select pin from pin_290),
  '^[0-9]{4}$',
  'PUERTA · fn_regenerar_pin devuelve exactamente cuatro dígitos');

select isnt(
  (select pin_hash from personas where id = '00000000-0000-0000-0000-000000290002'),
  'x',
  'PUERTA · el hash guardado cambió');

select alike(
  (select pin_hash from personas where id = '00000000-0000-0000-0000-000000290002'),
  '$2a$10$%',
  'FORMATO · el hash es bcrypt con factor 10 — el mismo que compara bcryptjs en el terminal');

select is(
  (select extensions.crypt(p.pin, x.pin_hash)
     from pin_290 p, personas x
    where x.id = '00000000-0000-0000-0000-000000290002'),
  (select pin_hash from personas where id = '00000000-0000-0000-0000-000000290002'),
  'RECONOCE · crypt(pin, hash) = hash: el PIN devuelto abre el hash guardado');

-- ── 2 · La puerta pasa el candado como `authenticated` ──────────────────────
-- Así llega de verdad por PostgREST. Dentro de la función `current_user` es
-- su dueña (postgres), y por eso el trigger la deja escribir.
set local role authenticated;
select lives_ok(
  $$ select fn_regenerar_pin('00000000-0000-0000-0000-000000290002') $$,
  'PUERTA · desde una sesión authenticated (como llega por PostgREST) el RPC pasa el candado');

-- ── 4 · El navegador ya no escribe pin_hash, ni con sesión de admin ────────
-- La RLS `personas_update_admin_lider` deja pasar a esta sesión: lo que corta
-- es el trigger. Esa distinción es la que esta prueba defiende.
select throws_ok(
  $$ update personas set pin_hash = 'x'
      where id = '00000000-0000-0000-0000-000000290002' $$,
  'El PIN no se escribe desde el navegador: usa fn_regenerar_pin.',
  'CANDADO · el update directo a pin_hash como authenticated se bloquea');

select alike(
  (select pin_hash from personas where id = '00000000-0000-0000-0000-000000290002'),
  '$2a$10$%',
  'CANDADO · y el hash guardado sigue siendo el bcrypt de la puerta');

-- ── 5 · Editar otra columna por el mismo camino sigue funcionando ───────────
select lives_ok(
  $$ update personas set nombres = 'Integrante Renombrada'
      where id = '00000000-0000-0000-0000-000000290002' $$,
  'SIGUE · editar nombres como authenticated no lo frena el candado');

select is(
  (select nombres from personas where id = '00000000-0000-0000-0000-000000290002'),
  'Integrante Renombrada',
  'SIGUE · y el cambio de nombres quedó guardado');

-- ── 3 · Quién NO abre la puerta ─────────────────────────────────────────────
select throws_ok(
  $$ select fn_regenerar_pin('00000000-0000-0000-0000-000000290003') $$,
  'Esa persona está inactiva: no necesita PIN. Si vuelve al equipo, reactívala primero.',
  'INACTIVA · a quien ya cesó no se le regenera PIN');

select throws_ok(
  $$ select fn_regenerar_pin('00000000-0000-0000-0000-000000290fff') $$,
  'No existe ninguna persona con ese id.',
  'INEXISTENTE · un id que no es de nadie se rechaza con un mensaje claro');
reset role;

-- Una integrante con sesión, sin rol de panel.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000002900a2', true);
set local role authenticated;
select throws_ok(
  $$ select fn_regenerar_pin('00000000-0000-0000-0000-000000290001') $$,
  'Solo un administrador o líder puede regenerar un PIN.',
  'PERMISO · una integrante no puede regenerar el PIN de nadie (ni el de la admin)');
reset role;

-- Una líder de DO sí abre la puerta: es la otra mitad de `fn_es_admin_o_lider`.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000002900a3', true);
set local role authenticated;
select matches(
  fn_regenerar_pin('00000000-0000-0000-0000-000000290002'),
  '^[0-9]{4}$',
  'PERMISO · una líder de DO sí regenera el PIN: es la otra mitad de fn_es_admin_o_lider');
reset role;

-- Una encargada de sede (`supervisor_sede`) NO: la RLS que se espeja nunca la
-- dejó escribir pin_hash, y esta migración cambia la puerta, no quién pasa.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000002900a4', true);
set local role authenticated;
select throws_ok(
  $$ select fn_regenerar_pin('00000000-0000-0000-0000-000000290002') $$,
  'Solo un administrador o líder puede regenerar un PIN.',
  'PERMISO · una encargada de sede no regenera PIN: la puerta no se amplió a supervisor_sede');
reset role;

-- Sin sesión: ni siquiera se puede llamar (revoke from anon).
set local role anon;
select throws_ok(
  $$ select fn_regenerar_pin('00000000-0000-0000-0000-000000290002') $$,
  '42501',
  null,
  'ANON · sin sesión la función ni se ejecuta');
reset role;

select * from finish();
rollback;
