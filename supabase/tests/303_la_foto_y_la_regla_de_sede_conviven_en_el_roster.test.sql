-- ============================================================================
-- 303_la_foto_y_la_regla_de_sede_conviven_en_el_roster.test.sql
-- ============================================================================
-- Defiende la reconciliación de la 0382: que la foto de perfil (0381) y la
-- delegación de la regla de sede convivan en la misma vista, en vez de que la
-- más reciente se lleve a la otra por delante — que es justo lo que pasó, en
-- las dos direcciones, cuando las dos migraciones se escribieron el mismo día
-- en ramas distintas sin saber una de la otra (ver la cabecera de la 0382).
--
-- La 302 ya prueba la estructura de la delegación por mutación; esta prueba no
-- lo repite. Se enfoca en el comportamiento conjunto: una sola consulta al
-- roster tiene que traer la foto de quien la subió Y seguir respetando el
-- aislamiento de sede — si la reconciliación hubiera vuelto a copiar la
-- condición a mano en vez de llamar a la función, esto seguiría en verde
-- (la copia dice lo mismo hoy); lo que de verdad prueba que se usó
-- `fn_persona_marca_en_sede` es la 302.
-- ============================================================================
begin;
select plan(4);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000030300', 'ZZ303A', 'Sede de laboratorio 303A', true),
  ('00000000-0000-0000-0000-000000030301', 'ZZ303B', 'Sede de laboratorio 303B', true);

set session_replication_role = replica;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash,
                      fecha_ingreso, estado, foto_url) values
  -- De la sede del terminal, CON foto: la reconciliación no puede perderla.
  ('00000000-0000-0000-0000-000000030310', 'ConFoto', 'Trescientos3',
   '00000000-0000-0000-0000-000000030300', 'x', '2024-01-01', 'activo',
   'perfil/00000000-0000-0000-0000-000000030310/1.jpg'),
  -- De la sede del terminal, SIN foto: null, no un string vacío ni un error.
  ('00000000-0000-0000-0000-000000030311', 'SinFoto', 'Trescientos3',
   '00000000-0000-0000-0000-000000030300', 'x', '2024-01-01', 'activo', null);

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash,
                      fecha_ingreso, estado, foto_url) values
  -- De OTRA sede, con foto: la delegación de la 0382 sigue mandando — la foto
  -- no es un camino nuevo para saltarse el aislamiento de sede.
  ('00000000-0000-0000-0000-000000030312', 'DeOtraSede', 'Trescientos3',
   '00000000-0000-0000-0000-000000030301', 'x', '2024-01-01', 'activo',
   'perfil/00000000-0000-0000-0000-000000030312/1.jpg');

insert into terminales (id, sede_id, nombre_dispositivo, activo, auth_user_id)
values ('00000000-0000-0000-0000-00000003030e', '00000000-0000-0000-0000-000000030300',
        'Mac mini 303', true, '00000000-0000-0000-0000-00000003030f');

set session_replication_role = origin;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000003030f', true);
set role authenticated;

select is(
  (select foto_url from terminal_roster where nombres = 'ConFoto' limit 1),
  'perfil/00000000-0000-0000-0000-000000030310/1.jpg',
  'FOTO · la reconciliación no perdió la foto de quien la subió');

select is(
  (select foto_url from terminal_roster where nombres = 'SinFoto' limit 1),
  null,
  'SIN FOTO · sigue viajando null, nunca un valor inventado');

select is_empty(
  $$ select 1 from terminal_roster where nombres = 'DeOtraSede' $$,
  'AISLAMIENTO · quien es de otra sede no aparece, tenga foto o no');

select is(
  (select count(*)::int from terminal_roster
    where id::text like '00000000-0000-0000-0000-0000000303%'),
  2,
  'CONTEO · exactamente las dos personas de la sede del terminal, ni una más');

reset role;
select * from finish();
rollback;
