-- ============================================================================
-- 0363 — fn_provisiones recupera su grant (arregla un daño de la 0338)
-- ----------------------------------------------------------------------------
-- PROMETE: que `authenticated` pueda volver a ejecutar fn_provisiones(date,
--   date), sin tocar una sola línea de su cuerpo ni de su lógica de negocio.
--
-- ASUME: 0338 (que causó esto) y el resto hasta la 0362.
--
-- QUÉ PASÓ. La 0338 le agregó un parámetro nuevo a fn_provisiones —pasó de
--   `fn_provisiones(date)` a `fn_provisiones(date, date)`— y como Postgres no
--   reemplaza en el sitio cuando cambia la lista de parámetros, la migración
--   hizo `DROP FUNCTION fn_provisiones(date)` seguido de un `CREATE OR REPLACE`
--   con la firma nueva. Eso crea un objeto de función distinto, con su propio
--   ACL desde cero — y esta base, desde la 0076
--   (`alter default privileges revoke execute on functions from public`), ya
--   NO regala EXECUTE a nadie por defecto. Toda función nueva necesita su
--   propio `grant execute ... to authenticated` explícito, y la 0338 nunca lo
--   escribió: sus dos GRANT anteriores (0029, 0035) quedaron colgados de la
--   firma vieja, que el propio DROP se llevó por delante.
--
--   El resultado: cualquier sesión —incluida la del panel— que llama
--   `supabase.rpc("fn_provisiones")` recibe «permission denied for function
--   fn_provisiones», el error de ACL de Postgres, ANTES de que el cuerpo de
--   la función llegue a ejecutarse. No es un bug de la pantalla de
--   Provisiones ni de su guard interno: la función nunca llegó a correr.
--
--   Comprobado contra el Postgres local (que ya tiene aplicadas todas las
--   migraciones hasta la 0362):
--     has_function_privilege('authenticated', 'fn_provisiones(date,date)', 'EXECUTE') = false
--     has_function_privilege('anon',          'fn_provisiones(date,date)', 'EXECUTE') = false
--
-- POR QUÉ SOLO UN GRANT Y NADA MÁS. La función ya está bien: su guard interno
--   y su lógica no cambian. Lo único que faltó fue la línea de permisos que
--   toda migración anterior que tocó esta función sí llevaba (0029, 0030,
--   0035). No hace falta reescribir el cuerpo para no arriesgar re-side su
--   md5 de producción por una razón que no es esta.
--
-- CÓMO SE REVIERTE: `revoke execute on function fn_provisiones(date, date)
--   from authenticated;` — vuelve exactamente al estado roto de la 0338, así
--   que en la práctica esto no se revierte, se corrige hacia adelante.
-- ============================================================================

grant execute on function fn_provisiones(date, date) to authenticated;
revoke execute on function fn_provisiones(date, date) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (363, 'fn_provisiones_recupera_su_grant')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select has_function_privilege('authenticated', 'fn_provisiones(date,date)', 'EXECUTE') as authenticated_ya_puede;
