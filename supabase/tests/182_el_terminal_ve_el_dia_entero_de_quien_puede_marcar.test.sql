-- ============================================================================
-- 182_el_terminal_ve_el_dia_entero_de_quien_puede_marcar.test.sql
-- ============================================================================
-- Defiende la 0241. Reproducido contra el Postgres local ANTES de escribir la
-- migración, con las dos policies como estaban:
--
--     el terminal de AQP ve en su roster    → 1   (la ofrece para marcar)
--     el terminal de AQP ve de sus marcas   → 0   (cree que no marcó nada hoy)
--     lo que espera fn_registrar_marcaje    → «elige un tipo de SALIDA»
--     y al mandar la Entrada que ofreció    → RECHAZADA
--
-- El roster (0008) incluye a quien viaja entre sedes; la lectura de marcajes
-- (0003) solo dejaba ver las de la sede del terminal. Con el día a medias, el
-- navegador ofrece «Entrada», el servidor —que cuenta el día entero— la rechaza,
-- la cola reintenta seis veces y APARTA la marca. Asistencia real que no llega
-- a la planilla y que solo existe en el IndexedDB de esa Mac.
--
-- LAS DOS MITADES, porque esto es un permiso y un permiso se rompe en las dos
-- direcciones: que el terminal VEA lo que necesita para no equivocarse, y que
-- eso no le abra las marcas a nadie más. El `is not null` de la policy es lo
-- único que separa «el terminal de AQP» de «cualquier sesión con login».
--
-- CAMBIO 0291 · las aserciones de roster (antes 1 y 3) leían `personas`
-- directo, porque cuando se escribió esta prueba ESE era el camino real del
-- terminal. La 0285 lo movió a la vista `terminal_roster`, y la 0291 cerró el
-- camino viejo por completo — así que hoy `select from personas` como
-- terminal da SIEMPRE cero filas, sea quien sea. Seguir comprobando eso haría
-- que la prueba "pasara" sin que el roster de verdad funcione. Se actualizan
-- para leer de `terminal_roster`, que es lo que la pantalla usa hoy.
-- ============================================================================
begin;
select plan(7);

set session_replication_role = replica;

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000018200', 'ZZ182A', 'Sede de laboratorio A', true),
  ('00000000-0000-0000-0000-000000018201', 'ZZ182B', 'Sede de laboratorio B', true);

-- La que viaja entre sedes: base en A, con el flag de la 0008 puesto.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, estado, visible_todas_sedes)
values ('00000000-0000-0000-0000-000000018202', 'Viajera', 'Laboratorio',
        '00000000-0000-0000-0000-000000018200', 'x', '2024-01-01', 'activo', true);

-- Y una que no viaja: base en A, sin el flag. No sale en el roster de B.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, estado, visible_todas_sedes)
values ('00000000-0000-0000-0000-000000018203', 'Quieta', 'Laboratorio',
        '00000000-0000-0000-0000-000000018200', 'x', '2024-01-01', 'activo', false);

insert into terminales (id, sede_id, nombre_dispositivo, activo, auth_user_id) values
  ('00000000-0000-0000-0000-00000001820a', '00000000-0000-0000-0000-000000018200',
   'Mac mini de la sede A', true, '00000000-0000-0000-0000-00000001820e'),
  ('00000000-0000-0000-0000-00000001820b', '00000000-0000-0000-0000-000000018201',
   'Mac mini de la sede B', true, '00000000-0000-0000-0000-00000001820f');

-- La viajera entra por la mañana en la SEDE A. Después se planta frente al
-- terminal de la SEDE B, que es donde empezaba el problema.
insert into marcajes (client_uuid, persona_id, sede_id, terminal_id, tipo, timestamp_marca, origen)
values (gen_random_uuid(), '00000000-0000-0000-0000-000000018202',
        '00000000-0000-0000-0000-000000018200', '00000000-0000-0000-0000-00000001820a',
        'entrada', ((now() at time zone 'America/Lima')::date + time '09:00') at time zone 'America/Lima',
        'terminal');

-- Y la que no viaja también entra en A, para comprobar que B no la ve.
insert into marcajes (client_uuid, persona_id, sede_id, terminal_id, tipo, timestamp_marca, origen)
values (gen_random_uuid(), '00000000-0000-0000-0000-000000018203',
        '00000000-0000-0000-0000-000000018200', '00000000-0000-0000-0000-00000001820a',
        'entrada', ((now() at time zone 'America/Lima')::date + time '09:05') at time zone 'America/Lima',
        'terminal');

set session_replication_role = origin;

-- ── 1 · El terminal de B, en carne y hueso ──────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000001820f', true);
set local role authenticated;

select is(
  (select count(*)::int from terminal_roster where id = '00000000-0000-0000-0000-000000018202'),
  1,
  'ROSTER · el terminal de B ofrece a la viajera, aunque su sede base sea A');

select is(
  (select count(*)::int from marcajes where persona_id = '00000000-0000-0000-0000-000000018202'),
  1,
  'DÍA ENTERO · y ahora SÍ ve la entrada que ella marcó en A — era el 0 que rompía todo');

-- La otra mitad del permiso: lo que se abrió no se abrió de más.
select is(
  (select count(*)::int from terminal_roster where id = '00000000-0000-0000-0000-000000018203'),
  0,
  'LÍMITE · a la que no viaja no la ofrece: no está en su roster');

select is(
  (select count(*)::int from marcajes where persona_id = '00000000-0000-0000-0000-000000018203'),
  0,
  'LÍMITE · y tampoco ve sus marcas, aunque lleven la sede de al lado');

reset role;

-- ── 2 · El terminal y el servidor por fin dicen lo mismo ────────────────────
-- Con el día a medias el navegador ofrecía «Entrada» y esto la rechazaba:
-- «tipo entrada no válido: la jornada ya está cerrada o requiere elegir un tipo
-- de salida». Viendo el día entero, `determinarSiguienteAccion` ofrece salidas
-- —que es lo que esta función espera— y la marca entra.
select is(
  fn_siguiente_tipo_esperado('00000000-0000-0000-0000-000000018202',
                             (now() at time zone 'America/Lima')::date),
  null::tipo_marca,
  'ACUERDO · el servidor espera que elija una SALIDA, no una entrada');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000001820f', true);
select lives_ok(
  $$ select fn_registrar_marcaje(
       '00000000-0000-0000-0000-000000018202', 'salida_final',
       ((now() at time zone 'America/Lima')::date + time '18:00') at time zone 'America/Lima',
       gen_random_uuid(), 'terminal', '00000000-0000-0000-0000-00000001820b') $$,
  'ACUERDO · y su salida en la sede B entra sin pelea');

-- ── 3 · El freno que separa un terminal de cualquiera con login ─────────────
-- Sin el `fn_sede_actual_terminal() is not null`, la condición del roster daría
-- TRUE por su cuenta para una sesión sin terminal y esta policy le abriría las
-- marcas de quien viaja entre sedes a cualquiera. Es el null de la 0078 y la
-- 0202, por tercera vez.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000182ff', true);
set local role authenticated;
select is(
  (select count(*)::int from marcajes where persona_id = '00000000-0000-0000-0000-000000018202'),
  0,
  'FRENO · una sesión con login que NO es terminal no ve ninguna de esas marcas');
reset role;

select * from finish();
rollback;
