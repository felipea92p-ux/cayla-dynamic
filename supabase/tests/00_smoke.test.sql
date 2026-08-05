-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- Prueba de humo: NO valida cálculos todavía. Solo confirma que la tubería
-- funciona — que las migraciones aplicaron y las piezas clave de la planilla
-- existen. Cuando esto pase en verde, encima montamos las pruebas de cálculo.
begin;
select plan(4);

select has_table('public', 'periodos_planilla', 'existe la tabla periodos_planilla');
select has_table('public', 'movimientos_planilla', 'existe la tabla movimientos_planilla');
select has_function('public', 'fn_proyeccion_periodo', 'existe fn_proyeccion_periodo (el cálculo)');
select has_function('public', 'fn_revertir_pago', 'existe fn_revertir_pago (red de seguridad)');

select * from finish();
rollback;
