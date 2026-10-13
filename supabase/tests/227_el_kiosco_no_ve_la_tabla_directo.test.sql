-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 227_el_kiosco_no_ve_la_tabla_directo.test.sql
-- ============================================================================
-- Defiende la 0291. La prueba 221 ya defiende `terminal_roster` —la vista con
-- seis columnas que el terminal SÍ debe ver— pero nunca preguntó por la tabla
-- de abajo. Y ahí seguía viva `personas_select_terminal_roster` (la 0008):
-- RLS filtra filas, no columnas, así que esa policy dejaba leer la FILA
-- entera con un `select * from personas` — documento y sueldo_base_legal
-- incluidos — aunque la pantalla del terminal nunca pidiera esas columnas.
--
-- Medido antes de escribir esta prueba, en el Postgres local: con la policy
-- vieja puesta, una sesión de terminal leía documento='87654321' y
-- sueldo_base_legal=1130.00 de una persona de su sede. Con la 0291 aplicada,
-- la misma consulta da cero filas.
--
-- Esta prueba fija las DOS mitades: que la tabla quede cerrada, y que la
-- vista —lo único que el terminal necesita para marcar— siga abierta. Cerrar
-- la fuga y romper el marcaje serían el mismo error visto desde el otro lado.
-- ============================================================================
begin;
select plan(4);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000022700', 'ZZ227', 'Sede del kiosco', true);

set session_replication_role = replica;
insert into terminales (id, sede_id, nombre_dispositivo, activo, auth_user_id) values
  ('00000000-0000-0000-0000-00000002270e', '00000000-0000-0000-0000-000000022700',
   'Mac mini de la sede', true, '00000000-0000-0000-0000-00000002270f');

-- Datos INVENTADOS: ni un DNI ni un sueldo real entra en una prueba.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso,
                      documento, tipo_documento, sueldo_base_legal, tipo_vinculo, estado, auth_user_id)
values ('00000000-0000-0000-0000-000000022701', 'DeLaSede', 'Kiosco227',
        '00000000-0000-0000-0000-000000022700', 'x', '2024-01-01',
        '99999999', 'dni', 1130.00, 'planilla', 'activo', null);
set session_replication_role = origin;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000002270f', true);
set role authenticated;

-- ── 1 · LA FUGA QUE ESTO CIERRA ──────────────────────────────────────────────
select is(
  (select count(*)::int from personas),
  0,
  'TABLA CERRADA · una sesión de terminal ya no lee ni una fila de personas directo');

-- ── 2 · Ni pidiendo la columna sensible por su nombre ───────────────────────
select is_empty(
  $$ select documento from personas where documento = '99999999' $$,
  'NI EL DNI · pedir la columna por su nombre tampoco la trae');

-- ── 3 · Lo que de verdad importa: sigue pudiendo marcar ─────────────────────
select ok(
  (select count(*) from terminal_roster) > 0,
  'SIGUE MARCANDO · la vista terminal_roster no dependía de la policy que se quitó');

-- ── 4 · Y las otras tres políticas de personas quedan intactas ──────────────
select is(
  (select count(*)::int from pg_policies where tablename = 'personas' and cmd = 'SELECT'),
  3,
  'LAS OTRAS TRES SIGUEN · admin_lider, supervisor y propia no se tocaron');

reset role;
select * from finish();
rollback;
