-- ============================================================================
-- 0315 · QUE `anon` NO PUEDA EJECUTAR NADA, DICHO A MANO Y NO POR DEFECTO
-- ============================================================================
--
-- QUÉ PROMETE
--   Que ninguna función de la casa (`fn_*`) le responda a quien NO ha iniciado
--   sesión — y que siga siendo así aunque Supabase cambie sus privilegios por
--   defecto sin avisar.
--
-- ⚠️ ESTO NO ARREGLA UN AGUJERO ABIERTO. Producción está cerrada HOY: se midió
--    el 2026-08-26 en el SQL Editor y devolvió **0 de 258** funciones
--    ejecutables por `anon`. Esta migración no le quita a nadie un permiso que
--    esté usando: escribe de forma permanente lo que ya es cierto.
--
-- ── DE DÓNDE SALE ───────────────────────────────────────────────────────────
--
-- El 2026-08-26 a las 20:00 el CI se puso rojo en dos pruebas de permisos, en
-- un commit que solo tocaba un `.md`. La causa no era código: el workflow
-- instala el CLI de Supabase con `version: latest`, y esa corrida se trajo una
-- imagen nueva — de `supabase/postgres:17.6.1.159` a `17.6.1.165`. Comparadas
-- las dos corridas, es la única diferencia.
--
-- Se empujó una prueba (la 250) solo para MEDIR qué había cambiado, con
-- `diag()` que imprimen el diagnóstico pase o falle. El CI contestó:
--
--     reglas por defecto para FUNCIONES en public
--        supabase_admin  →  {postgres, anon, authenticated, service_role}
--        postgres        →  {postgres, anon, authenticated, service_role}
--     dueños: postgres, 276 funciones
--     responden a anon: 105 de 258
--
--   Contra local y producción, que dan **0 de 258**.
--
-- ── EL MECANISMO, Y POR QUÉ LA 0076 NO BASTABA ─────────────────────────────
--
-- La protección de esta casa era una línea de la 0076:
--
--     alter default privileges revoke execute on functions from public;
--
-- Eso quita el permiso que PostgreSQL le da a **PUBLIC** por defecto. Pero la
-- imagen nueva no usa PUBLIC: trae una regla que le concede EXECUTE a **`anon`
-- explícitamente**. Y revocar de PUBLIC no quita una concesión explícita a otro
-- rol — son dos cosas distintas. Por eso la 0076 seguía corriendo sin error y
-- ya no protegía: no falló, dejó de tener razón.
--
-- La primera hipótesis fue que la imagen cambiaba QUIÉN crea las funciones. Era
-- falsa y el propio diagnóstico la descartó: el dueño sigue siendo `postgres`,
-- con sus 276 funciones. Queda escrito para que nadie la persiga otra vez.
--
-- ── POR QUÉ SOLO `fn_*` ─────────────────────────────────────────────────────
--
-- En `public` hay 188 funciones que no se llaman así, y `anon` puede ejecutar
-- las 188 — también en producción. Se comprobó qué son: **las 188 pertenecen a
-- la extensión `btree_gist`**, ninguna es de la casa. O sea que `fn_*` no es una
-- convención cómoda: es la frontera exacta entre lo propio y lo del motor.
--
-- ── QUÉ HACE, EN DOS MITADES ────────────────────────────────────────────────
--
--   1) Cierra la puerta de MAÑANA: quita `anon` (y PUBLIC) de los privilegios
--      por defecto para funciones nuevas en `public`. Sin esto, la siguiente
--      migración que pegues crearía funciones abiertas el día que la plataforma
--      cambie como cambió la imagen.
--   2) Cierra la de HOY: revoca `execute` de `anon` y PUBLIC sobre cada `fn_*`
--      que ya existe. En producción no cambia nada —ya están cerradas— pero deja
--      el permiso escrito en la ACL en vez de depender de una regla ambiental.
--
--   NO toca `authenticated` ni `service_role`. Los guards de dentro de cada
--   función (`if fn_es_admin_o_lider() is not true then raise`) siguen siendo
--   quienes deciden qué puede hacer una persona con sesión; esto solo cierra la
--   puerta a quien no tiene ninguna.
--
-- ── EL BUCLE VA CON RED, COMO EL DE LA 0076 ────────────────────────────────
--
-- Cada revoke va en su propio `begin … exception`, y lo que no se pueda tocar se
-- reporta al final por nombre. Sin eso, una sola función de otro dueño tumbaría
-- el DO entero y la base quedaría igual que antes, sin ninguna pista de por qué.
-- Es preferible cerrar 257 y saber cuál falta, a no cerrar ninguna.
--
-- QUÉ ASUME
--   Que las migraciones las aplica `postgres` — medido: es el dueño de las 276.
--   `supabase_admin` tiene su propia regla por defecto que también concede
--   `anon`, y no se toca: no crea funciones de la casa, y cambiarla exige ser
--   miembro de ese rol.
--
-- CÓMO SE REVIERTE
--   `alter default privileges in schema public grant execute on functions to anon;`
--   y `grant execute on function <cada una> to anon`. No hay datos que deshacer.
-- ============================================================================

-- ── 1 · La puerta de mañana ─────────────────────────────────────────────────
alter default privileges in schema public revoke execute on functions from anon;
alter default privileges in schema public revoke execute on functions from public;

-- ── 2 · La puerta de hoy ────────────────────────────────────────────────────
do $cierre$
declare
  r         record;
  n         int := 0;
  omitidas  text[] := '{}';
  s         text;
begin
  for r in
    select p.oid::regprocedure::text as sig
    from pg_proc p
    join pg_namespace nsp on nsp.oid = p.pronamespace
    where nsp.nspname = 'public'
      and p.proname like 'fn\_%'
      and p.prorettype <> 'trigger'::regtype
    order by 1
  loop
    begin
      execute format('revoke execute on function %s from anon', r.sig);
      execute format('revoke execute on function %s from public', r.sig);
      n := n + 1;
    exception when others then
      omitidas := array_append(omitidas, r.sig || '  (' || sqlerrm || ')');
    end;
  end loop;

  raise notice '0315 · funciones fn_* con anon revocado explicitamente: %', n;
  if array_length(omitidas, 1) > 0 then
    raise warning '0315 · NO se pudieron cerrar % funcion(es). Revisar a mano:',
                  array_length(omitidas, 1);
    foreach s in array omitidas loop
      raise warning '  · %', s;
    end loop;
  end if;
end $cierre$;

insert into migraciones_aplicadas (numero, nombre)
values (315, '0315_anon_deja_de_depender_de_una_regla_por_defecto')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── COMPROBACIÓN ────────────────────────────────────────────────────────────
-- Un solo select, porque el SQL Editor de Supabase corre nada más el último.
-- Tiene que decir «0315 · OK». Si dice ATENCION, algo no entró: no sigas.
select
  case when (select count(*) from migraciones_aplicadas where numero = 315) = 1
        and (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname like 'fn\_%'
                and p.prorettype <> 'trigger'::regtype
                and has_function_privilege('anon', p.oid, 'EXECUTE')) = 0
        and not exists (select 1 from pg_default_acl
                         where defaclnamespace = 'public'::regnamespace
                           and defaclobjtype = 'f'
                           and defaclrole = 'postgres'::regrole
                           and array_to_string(defaclacl, ' ') like '%anon=%')
       then '0315 · OK — ninguna fn_* responde a anon, ni las de hoy ni las de mañana'
       else '0315 · ATENCION — revisa antes de seguir'
  end as resultado,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname like 'fn\_%'
      and p.prorettype <> 'trigger'::regtype)                        as funciones_revisadas,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname like 'fn\_%'
      and p.prorettype <> 'trigger'::regtype
      and has_function_privilege('anon', p.oid, 'EXECUTE'))          as siguen_abiertas_a_anon,
  (select coalesce(array_to_string(defaclacl, '  '), '(sin regla)')
     from pg_default_acl
    where defaclnamespace = 'public'::regnamespace and defaclobjtype = 'f'
      and defaclrole = 'postgres'::regrole)                          as regla_por_defecto_de_postgres;
