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
