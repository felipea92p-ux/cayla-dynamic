-- ============================================================================
-- quien_puede_ejecutar_el_semaforo.sql
-- ============================================================================
-- QUÉ RESPONDE
--   Si el rol `authenticated` —el que usa el panel cuando alguien está con su
--   sesión abierta— puede EJECUTAR las funciones del semáforo disciplinario.
--
-- QUÉ NO HACE
--   No escribe nada. Solo lee.
--
-- ── POR QUÉ SE MIRA ESTO ────────────────────────────────────────────────────
--
-- Ya está medido que el cuerpo de fn_tardanzas_resumen devuelve a la persona
-- contra los datos de producción, y que su md5 es el de la 0189. Lo que falla
-- está entre la función y la pantalla.
--
-- Y hay un sospechoso con nombre: **un `drop function` se lleva por delante los
-- GRANT**. La 0189 hace
--
--     drop function if exists public.fn_tardanzas_resumen(date);
--     CREATE OR REPLACE FUNCTION public.fn_tardanzas_resumen(...)
--
-- y no vuelve a otorgar nada. El último `grant execute` sobre esta función en
-- todo el repositorio es de la **0067**, ocho migraciones antes de que existiera
-- este patrón de drop-and-create. La 0200 hereda el mismo defecto.
--
-- Postgres otorga EXECUTE a PUBLIC por defecto al crear una función, así que
-- esto PUEDE no romper nada — depende de si el proyecto revocó ese default.
-- Por eso se mide en vez de suponerlo.
--
-- ── CÓMO SE LEE ─────────────────────────────────────────────────────────────
--   `authenticated` tiene que decir SÍ en las tres funciones del semáforo y en
--   las cuatro auxiliares. Un solo NO explica la lista vacía: PostgREST
--   devuelve error, y la pantalla lo esconde detrás de «Nadie».
--
--   `anon` debería decir NO en las que tocan datos de personas. Si dice SÍ, eso
--   es otro problema distinto y más grave, y conviene saberlo igual.
-- ============================================================================

select
  p.proname                                        as funcion,
  pg_get_function_identity_arguments(p.oid)        as argumentos,
  pg_get_userbyid(p.proowner)                      as duenio,
  case when has_function_privilege('authenticated', p.oid, 'EXECUTE')
       then 'SÍ' else '⚠ NO — aquí está el problema' end as puede_authenticated,
  case when has_function_privilege('anon', p.oid, 'EXECUTE')
       then '⚠ sí' else 'no' end                   as puede_anon,
  -- Los ACL crudos, por si el privilegio viene heredado de PUBLIC y no de un
  -- grant explícito: `=X/postgres` es PUBLIC, `authenticated=X/postgres` es
  -- el grant nominal. No es lo mismo el día que alguien revoque PUBLIC.
  coalesce(array_to_string(p.proacl, ' · '), '(sin ACL: EXECUTE a PUBLIC por defecto)') as acl
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    -- las del semáforo
    'fn_tardanzas_resumen', 'fn_faltas_resumen', 'fn_tardanza_es_medible',
    -- las que la puerta llama por dentro: si falta una, la función revienta
    'fn_es_admin_o_lider', 'fn_rol_actual', 'fn_sede_actual_persona', 'fn_hoy_lima'
  )
order by
  case when has_function_privilege('authenticated', p.oid, 'EXECUTE') then 2 else 1 end,
  p.proname;
