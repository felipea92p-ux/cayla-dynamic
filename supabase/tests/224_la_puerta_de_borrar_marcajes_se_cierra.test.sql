-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 224_la_puerta_de_borrar_marcajes_se_cierra.test.sql
-- ============================================================================
-- La 0081 dejó escrita la regla: las marcas se ANULAN, no se borran. Un marcaje
-- es el hecho del que cuelga todo —la jornada es derivada y la planilla se
-- calcula de ahí—, así que borrar uno destruye la prueba de lo que pasó.
--
-- Pero `fn_eliminar_marcaje` hace un `delete` de verdad, y la 0009 le había
-- dado `grant execute … to authenticated` que nadie revocó nunca: cualquier
-- sesión del panel podía borrar un marcaje por REST sin pasar por ninguna
-- pantalla. Medido antes de la 0288: cero llamadas desde `apps/` y `packages/`.
--
-- Esta prueba fija los permisos, no el comportamiento: lo que hay que impedir
-- es que el camino automático vuelva a abrirse. El día que alguien le devuelva
-- el grant, esto se pone rojo.
-- ============================================================================
begin;
select plan(4);

select ok(
  not has_function_privilege('authenticated', 'fn_eliminar_marcaje(uuid, text)', 'execute'),
  'Una sesión del navegador NO puede borrar un marcaje');

select ok(
  has_function_privilege('authenticated', 'fn_anular_marcaje(uuid, text)', 'execute'),
  'Pero sí puede ANULARLO: la puerta buena de la 0081 sigue abierta');

select ok(
  has_function_privilege('authenticated', 'fn_reactivar_marcaje(uuid, text)', 'execute'),
  'Y puede deshacer esa anulación, o anular sería un camino sin vuelta');

-- El caso legítimo y raro —un marcaje que nunca debió existir— se atiende a
-- mano desde el SQL Editor, donde la sesión es `postgres`. Que ESE camino siga
-- abierto es parte del diseño: lo que se cierra es el automático.
select ok(
  has_function_privilege('postgres', 'fn_eliminar_marcaje(uuid, text)', 'execute'),
  'A mano desde el SQL Editor sigue siendo posible: se cierra el camino automático, no el deliberado');

select * from finish();
rollback;
