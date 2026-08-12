-- ============================================================================
-- 172_el_terminal_puede_preguntar_la_hora.test.sql
-- ============================================================================
-- Lo que fija la 0230: que el terminal pueda comparar su reloj con el del
-- servidor, porque `marcajes.timestamp_marca` —el dato del que cuelga a qué día
-- se paga, si hubo tardanza y cuántas horas se trabajaron— lo pone el navegador
-- de la Mac mini con su propio reloj, y hasta el 2026-08-12 nadie lo verificaba.
--
-- LAS TRES COSAS QUE DEFIENDE, y las tres se rompen distinto:
--
--   · Que responda. Sin esto no hay medición y el aviso nunca aparece.
--   · Que el TERMINAL pueda ejecutarla. Es la mitad que se pierde sola: un
--     `drop function` se lleva los GRANT, y este repositorio ya vivió dos días
--     con el semáforo disciplinario ciego por exactamente eso (0189 → 0204).
--   · Que `anon` NO pueda. Arreglar un permiso abriéndolo de más es peor que
--     el defecto.
--
-- POR QUÉ NO SE PRUEBA EL DESFASE EN SÍ
--   Porque no hay desfase que medir: pgTAP corre dentro del mismo Postgres, así
--   que el «reloj del cliente» y el del servidor son el mismo. La estimación
--   —descontar la ida y vuelta— vive en el navegador y se fija en
--   `tests/reloj-servidor.test.ts`. Cada mitad se prueba donde vive.
-- ============================================================================
begin;
select plan(6);

-- ── 1-2 · Existe y contesta ────────────────────────────────────────────────
select has_function(
  'public', 'fn_ahora_servidor', ARRAY[]::text[],
  'fn_ahora_servidor existe — sin ella el terminal no tiene con qué comparar');

select ok(
  fn_ahora_servidor() is not null,
  'Y contesta una hora, no null');

-- ── 3 · Es la MISMA hora con la que se sellan las marcas ──────────────────
-- `now()` y no `clock_timestamp()`: el instante de la transacción es el que usa
-- `server_received_at`. Si divergieran, el desfase se estaría midiendo contra un
-- reloj distinto del que sella los marcajes, y el número no significaría nada.
select ok(
  fn_ahora_servidor() = now(),
  'Devuelve el instante de la transacción, el mismo con el que se sella server_received_at');

-- ── 4-5 · Los permisos, que son la mitad que se pierde sola ───────────────
select ok(
  has_function_privilege('authenticated', 'public.fn_ahora_servidor()'::regprocedure, 'EXECUTE'),
  'El terminal puede preguntar la hora — si no, el aviso del reloj no aparece nunca');

select ok(
  not has_function_privilege('anon', 'public.fn_ahora_servidor()'::regprocedure, 'EXECUTE'),
  'anon NO puede: nada nace abierto desde la 0076');

-- ── 6 · No lee nada, y por eso se puede conceder sin miedo ────────────────
-- Es lo que justifica el grant: si mañana alguien le añade una consulta a una
-- tabla, este permiso deja de ser inocuo y hay que volver a pensarlo.
select is(
  (select count(*)::int from pg_proc p
     where p.proname = 'fn_ahora_servidor'
       and (p.prosrc ilike '%from %' or p.prosecdef)),
  0,
  'No lee ninguna tabla ni es SECURITY DEFINER: por eso concederla no revela nada');

select * from finish();
rollback;
