-- ============================================================================
-- QUITAR la 0087 — las funciones de truncas tienen errores de cálculo
-- ----------------------------------------------------------------------------
-- POR QUÉ. La 0087 llegó a producción sin haber pasado sus pruebas. Al correrlas
-- (26/07/2026, Postgres 17 con la cadena completa) fallaron dos de los seis
-- casos, y en la peor dirección posible:
--
--   cese 20/09/2026, sueldo S/1,450   → debía dar S/263.42 · dio S/1,053.67
--   cese 20/12 con la grati ya cobrada → debía dar S/0.00   · dio S/1,448.80
--
-- La causa: fn_grati_trunca cuenta los meses del "semestre del cese" cuando lo
-- correcto es contar los de TODO SEMESTRE AÚN NO COBRADO. El encabezado de la
-- migración explicaba bien la regla; el código de abajo hacía otra cosa.
--
-- NADIE COBRÓ MAL. Estas funciones solo calculan: no escriben, no pagan y no
-- modifican ningún dato. Además la pantalla de liquidación todavía no existe,
-- así que nada las llamaba. Se retiran para que nadie las use por error
-- mientras se corrigen.
--
-- QUÉ NO TOCA: ni una fila de datos. Solo elimina cinco funciones de cálculo
-- que ninguna otra parte del sistema usa (se verificó: ninguna función, vista
-- ni pantalla las llama).
--
-- QUÉ PASA CON EL REGISTRO: se borra la fila 87 para que `migraciones_aplicadas`
-- diga la verdad. Va a aparecer como hueco hasta que entre la versión corregida
-- — y eso es exactamente lo que debe verse.
--
-- Idempotente: se puede pegar dos veces sin problema.
-- ============================================================================

begin;

drop function if exists fn_grati_trunca(uuid, date);
drop function if exists fn_cts_trunca(uuid, date);
drop function if exists fn_vacaciones_truncas(uuid, date);
drop function if exists fn_remuneracion_computable(uuid, date);
drop function if exists fn_meses_y_dias(date, date);

delete from migraciones_aplicadas where numero = 87;

-- La clave de configuración se deja: no hace nada por sí sola y la versión
-- corregida la va a necesitar igual.

commit;

-- ── Comprobación: las cuatro filas deben decir 0 ────────────────────────────
select 'fn_grati_trunca'       as funcion, count(*) as quedan from pg_proc where proname = 'fn_grati_trunca'
union all
select 'fn_cts_trunca',        count(*) from pg_proc where proname = 'fn_cts_trunca'
union all
select 'fn_vacaciones_truncas', count(*) from pg_proc where proname = 'fn_vacaciones_truncas'
union all
select 'fn_remuneracion_computable', count(*) from pg_proc where proname = 'fn_remuneracion_computable'
union all
select 'registro tiene la 87',  count(*) from migraciones_aplicadas where numero = 87;
