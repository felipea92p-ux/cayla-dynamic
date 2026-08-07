-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 135_el_cese_tiene_candado.test.sql — que nadie se lleve el `for update`
-- ============================================================================
-- La 0174 le puso a `fn_cesar_persona` un candado de fila: lee la persona con
-- `select … for update` para que dos ceses simultáneos de la misma persona no
-- pasen los dos. Sin él, `personas.fecha_cese` puede terminar con una fecha y
-- sus tramos de salario y horario cerrados con otra — y como de `fecha_cese`
-- viven la gratificación, la CTS y las vacaciones truncas, la liquidación sale
-- sobre un día en que su salario ya no estaba vigente. No falla nada: se ve
-- igual que un cálculo bueno.
--
-- POR QUÉ HACE FALTA ESTA PRUEBA. Un candado es una línea fácil de perder. Este
-- repo tiene la lección aprendida: `fn_planilla_calcular` acumuló 23 versiones
-- repartidas en migraciones distintas, y el 2026-08-05 casi entra a producción
-- una copia de la 0017 creyéndola la última —64 migraciones atrás— que habría
-- revertido en silencio toda la lógica de marcas anuladas. Quien reescriba
-- `fn_cesar_persona` mañana va a copiar el cuerpo de algún lado, y si copia de
-- la 0086 se lleva el candado por delante sin enterarse. Entonces esta prueba se
-- pone roja, que es justo el momento en que sirve.
--
-- LO QUE ESTA PRUEBA NO PUEDE VER. No comprueba que el candado FUNCIONE: para
-- eso hacen falta dos sesiones a la vez, y pgTAP corre en una sola. Eso se
-- verificó empíricamente el 2026-08-06 lanzando dos `fn_cesar_persona` en
-- paralelo sobre la misma persona (con la 0086: las dos pasaban y dejaban
-- fecha_cese 30/06 contra tramos cerrados el 20/07; con la 0174: la segunda
-- rebota con «Esa persona ya está inactiva»). Lo que esta prueba cuida es que
-- esa línea siga estando.
-- ============================================================================
begin;
select plan(3);

-- ── 1 · El candado está en la definición viva ───────────────────────────────
-- Se mira `pg_get_functiondef`, o sea lo que Postgres tiene cargado ahora, no lo
-- que dice un archivo del repositorio. Un archivo puede estar sin aplicar.
select matches(
  pg_get_functiondef('fn_cesar_persona(uuid, date, text, text)'::regprocedure),
  'from personas where id = p_persona_id for update',
  'fn_cesar_persona lee la persona con `for update` — sin eso, dos ceses simultáneos pasan los dos');

-- ── 2 · Y el candado se toma ANTES de mirar el estado ───────────────────────
-- Un `for update` puesto después de la comprobación no sirve de nada: la carrera
-- ocurre justo en ese hueco. Se exige el orden, no solo la presencia.
--
-- Los dos `> 0` no sobran: `position` devuelve 0 cuando no encuentra el texto, y
-- sin ellos «0 < loQueSea» daría verde precisamente en el caso en que la línea
-- desapareció. Una prueba que pasa cuando lo que vigila ya no está es peor que
-- no tenerla.
select ok(
  position('for update' in pg_get_functiondef('fn_cesar_persona(uuid, date, text, text)'::regprocedure)) > 0
  and position('v_p.estado <> ''activo''' in pg_get_functiondef('fn_cesar_persona(uuid, date, text, text)'::regprocedure)) > 0
  and position('for update' in pg_get_functiondef('fn_cesar_persona(uuid, date, text, text)'::regprocedure))
    < position('v_p.estado <> ''activo''' in pg_get_functiondef('fn_cesar_persona(uuid, date, text, text)'::regprocedure)),
  'el `for update` va antes de comprobar el estado — si va después, la carrera sigue abierta');

-- ── 3 · La función sigue siendo la que decide el cese ───────────────────────
-- El candado protege a esta función de sí misma; no protege a la tabla. Si
-- alguien vuelve a cesar con un `update personas set estado = ''inactivo''`
-- suelto, el candado no lo ve. Al menos que la función siga existiendo con su
-- firma, que es lo que la pantalla llama.
select has_function(
  'public', 'fn_cesar_persona', array['uuid','date','text','text'],
  'fn_cesar_persona sigue siendo el único camino con reglas para dar de baja');

select * from finish();
rollback;
