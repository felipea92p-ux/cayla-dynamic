-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 406_el_dni_no_va_en_el_nombre.test.sql — 0512
-- ============================================================================
-- Defiende la 0512. El 2026-10-06 una integrante apareció en todas las listas
-- con su DNI pegado al apellido corto: se tecleó a mano en el alta. El candado
-- `personas_nombre_sin_documento` lo hace imposible por cualquier puerta.
--
-- Los nombres y números de abajo son inventados: no se sube a git un DNI real.
-- ============================================================================
begin;
select plan(8);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000040600', 'ZZ406', 'Sede de laboratorio 406', true);
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000040601', 'Prueba', 'Cuatrocientos', '00000000-0000-0000-0000-000000040600',
   'integrante', 'x', '2024-01-01');

select ok(
  (select convalidated from pg_constraint
    where conname = 'personas_nombre_sin_documento' and conrelid = 'public.personas'::regclass),
  'el candado existe y está validado');

-- ── Lo que se niega ──────────────────────────────────────────────────────────
select throws_ok(
  $$ update personas set apellidos = 'Cuatrocientos 12345678'
      where id = '00000000-0000-0000-0000-000000040601' $$,
  '23514', null,
  'BLOQUEADO · un DNI de 8 dígitos pegado al apellido');
select throws_ok(
  $$ update personas set nombres = '12345678 Prueba'
      where id = '00000000-0000-0000-0000-000000040601' $$,
  '23514', null,
  'BLOQUEADO · también en el nombre, y también al principio');
select throws_ok(
  $$ update personas set apellidos = 'Cuatrocientos 001234567'
      where id = '00000000-0000-0000-0000-000000040601' $$,
  '23514', null,
  'BLOQUEADO · un carné de extranjería (9 dígitos)');
select throws_ok(
  $$ insert into personas (nombres, apellidos, sede_base_id, rol, pin_hash)
     values ('Otra', 'Persona 87654321', '00000000-0000-0000-0000-000000040600', 'integrante', 'x') $$,
  '23514', null,
  'BLOQUEADO · y en un alta nueva, no solo al editar');

-- ── Lo que sigue pasando ─────────────────────────────────────────────────────
select lives_ok(
  $$ update personas set apellidos = 'Cuatrocientos-Ñúñez'
      where id = '00000000-0000-0000-0000-000000040601' $$,
  'PASA · un apellido compuesto, con guion y tildes');
select lives_ok(
  $$ update personas set nombres = 'ESTACIÓN — Caja 2', apellidos = '(no es persona)'
      where id = '00000000-0000-0000-0000-000000040601' $$,
  'PASA · una estación de retail con un número corto: la regla es 6+ dígitos, no «ningún dígito»');
select lives_ok(
  $$ update personas set apellidos = 'Cuatrocientos 12345'
      where id = '00000000-0000-0000-0000-000000040601' $$,
  'PASA · cinco dígitos no son un documento (el borde de la regla, fijado a propósito)');

select * from finish();
rollback;
