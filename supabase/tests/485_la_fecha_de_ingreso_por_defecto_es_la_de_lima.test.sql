-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 485_la_fecha_de_ingreso_por_defecto_es_la_de_lima.test.sql — 0595
-- ============================================================================
-- Defiende que dar de alta a alguien sin fecha de ingreso lo deje en HOY EN
-- LIMA, aunque la base corra en otra zona horaria (en producción es UTC, y de
-- 19:00 a 23:59 de Lima `current_date` ya es mañana).
--
-- Dos comprobaciones, porque una sola dependería de la hora a la que corre:
--   · el catálogo: el default nombra `fn_hoy_lima` (determinista, siempre);
--   · el comportamiento: con la sesión en una zona muy adelantada a Lima, la
--     persona sin fecha queda con `fn_hoy_lima()` y no con la fecha de esa zona.
-- ============================================================================
begin;
select plan(3);

select ok(
  (select pg_get_expr(d.adbin, d.adrelid) like '%fn_hoy_lima%'
     from pg_attrdef d
     join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
    where d.adrelid = 'public.personas'::regclass and a.attname = 'fecha_ingreso'),
  'el default de fecha_ingreso usa fn_hoy_lima()'
);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000485001', 'ZZ485', 'Sede de laboratorio 485', true);

set local timezone = 'Pacific/Kiritimati';  -- UTC+14: su fecha casi siempre va un día por delante de Lima

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash)
values ('00000000-0000-0000-0000-000000485b01', 'Alta485', 'Lab',
        '00000000-0000-0000-0000-000000485001', 'x');

select is(
  (select fecha_ingreso from personas where id = '00000000-0000-0000-0000-000000485b01'),
  fn_hoy_lima(),
  'sin fecha, el alta queda con la de hoy en Lima, no con la de la zona de la base'
);

select ok(
  (select fecha_ingreso <= fn_hoy_lima() from personas where id = '00000000-0000-0000-0000-000000485b01'),
  'y por tanto nunca queda como ingreso futuro (que impediría marcar)'
);

select * from finish();
rollback;
