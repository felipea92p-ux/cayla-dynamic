-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 486_la_fecha_de_ingreso_por_defecto_es_el_dia_de_lima.test.sql — 0596
-- ============================================================================
-- Defiende que una persona dada de alta sin fecha de ingreso quede con el día
-- de hoy EN LIMA, no el del servidor.
--
-- `current_date` usa la zona horaria de la SESIÓN; `fn_hoy_lima()` no. Para que
-- la prueba no dependa de la hora a la que corre, se fuerza una zona 14 horas
-- adelante de UTC: ahí `current_date` difiere del día de Lima a cualquier hora,
-- así que con el default viejo esta prueba falla siempre, no solo de noche.
-- ============================================================================
begin;
select plan(2);

set local timezone = 'Pacific/Kiritimati';

select isnt(current_date, fn_hoy_lima(),
  'control: con esta zona, current_date NO coincide con el día de Lima (si coincidiera, la prueba no probaría nada)');

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000486000', 'ZZ486', 'Sede de laboratorio 486', true);

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash)
values ('00000000-0000-0000-0000-000000486001', 'Alta', 'Sin fecha', '00000000-0000-0000-0000-000000486000', 'x');

select is(
  (select fecha_ingreso from personas where id = '00000000-0000-0000-0000-000000486001'),
  fn_hoy_lima(),
  'una persona creada sin fecha de ingreso queda con el día de hoy en Lima');

select * from finish();
rollback;
