-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 250_ninguna_funcion_le_responde_a_quien_no_inicio_sesion.test.sql
-- ============================================================================
-- LA VERSIÓN GENERAL DE UNA REGLA QUE HASTA HOY SE VIGILABA DE A UNA.
--
-- El repo ya comprueba que `anon` no pueda ejecutar DOS funciones concretas
-- (pruebas 159 y 185). Esta las generaliza a las 258: **ninguna `fn_*`
-- llamable por la API puede responderle a quien no inició sesión.**
--
-- ── POR QUÉ SE ESCRIBE HOY ─────────────────────────────────────────────────
--
-- El 2026-08-26 a las 20:00 el CI de `main` se puso rojo en esas dos, en un
-- commit que solo tocaba un `.md`. La causa no era código: el workflow instala
-- el CLI de Supabase con `version: latest` y esa corrida se trajo una imagen
-- nueva —de `supabase/postgres:17.6.1.159` a `17.6.1.165`—.
--
-- Y lo que destapó no es un falso positivo. La protección de esta casa es una
-- sola línea de la 0076:
--
--     alter default privileges revoke execute on functions from public;
--
-- que aplica SOLO a las funciones creadas por el rol que la ejecutó. En la base
-- conviven dos reglas por defecto para funciones de `public`:
--
--     postgres        → {postgres, service_role}                    anon fuera
--     supabase_admin  → {postgres, anon, authenticated, service_role} anon DENTRO
--
-- O sea: la puerta está cerrada **mientras las migraciones las aplique
-- `postgres`**. Si cambia quién las aplica, las funciones nuevas nacen abiertas
-- y nada falla — solo se abren.
--
-- ── ESTA PRUEBA ES, ANTES QUE NADA, UN INSTRUMENTO DE MEDICIÓN ─────────────
--
-- Los `diag()` de abajo imprimen el diagnóstico completo **pase o falle**: las
-- reglas por defecto vigentes, quién es el dueño de las funciones, y cuáles
-- responden a `anon`. En el Postgres local sale limpia; corriéndola en el CI
-- contra la imagen nueva, esos mismos `diag()` dicen exactamente qué cambió.
--
-- Producción está bien hoy: sus 258 funciones ya tienen el permiso grabado sin
-- `anon` — comprobado el 2026-08-26 en el SQL Editor. Esto vigila el mañana.
-- ============================================================================
begin;
select plan(3);

-- ── El diagnóstico, se cumpla o no ─────────────────────────────────────────
select diag('── reglas por defecto para FUNCIONES en public ──');
select diag('   ' || defaclrole::regrole::text || '  →  ' || defaclacl::text)
from pg_default_acl
where defaclnamespace = 'public'::regnamespace and defaclobjtype = 'f';

select diag('── dueños de las fn_* ──');
select diag('   ' || pg_get_userbyid(proowner) || ': ' || count(*)::text || ' funciones')
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname like 'fn\_%'
group by proowner;

select diag('── cuantas responden a anon ──');
select diag('   ' || count(*)::text || ' de ' ||
            (select count(*)::text from pg_proc p2 join pg_namespace n2 on n2.oid = p2.pronamespace
              where n2.nspname = 'public' and p2.proname like 'fn\_%'
                and p2.prorettype <> 'trigger'::regtype))
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname like 'fn\_%'
  and p.prorettype <> 'trigger'::regtype
  and has_function_privilege('anon', p.oid, 'EXECUTE');

-- ── 1 · LA REGLA ───────────────────────────────────────────────────────────
-- `is_empty` para que, cuando falle, pgTAP imprima QUÉ funciones se abrieron,
-- de quién son y con qué permisos. Un conteo obligaría a ir a buscarlas.
--
-- Las de trigger se excluyen: no se pueden llamar por la API, así que su
-- permiso no abre ninguna puerta y solo haría ruido. Un guardián con ruido se
-- desactiva a la semana.
select is_empty(
  $anon$ select p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as funcion,
                pg_get_userbyid(p.proowner) as dueno,
                p.prosecdef as security_definer,
                coalesce(array_to_string(p.proacl, ' '), '(sin ACL: PUBLIC puede)') as permisos
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname = 'public' and p.proname like 'fn\_%'
            and p.prorettype <> 'trigger'::regtype
            and has_function_privilege('anon', p.oid, 'EXECUTE')
          order by 1 $anon$,
  'ninguna funcion del panel le responde a quien NO inicio sesion');

-- ── 2 · Y que la medición no pase por estar vacía ──────────────────────────
-- La de arriba pasaría igual si no hubiera ninguna `fn_*`, o si el patrón
-- dejara de encontrarlas. Es la misma trampa que el `is_empty` sobre una tabla
-- vacía: verde sin haber comprobado nada.
select cmp_ok(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname like 'fn\_%'
      and p.prorettype <> 'trigger'::regtype),
  '>',
  200,
  'y hay mas de 200 funciones fn_* que revisar: la medicion no paso por estar vacia'
);

-- ── 3 · LA PUERTA DE MAÑANA (0315) ─────────────────────────────────────────
-- La comprobación 1 mira las funciones que YA existen. Ésta mira la regla que
-- decide cómo nacen las siguientes, y es la que de verdad cierra el caso:
-- mientras `anon` esté en los privilegios por defecto de `postgres` para
-- funciones de `public`, la próxima migración que se pegue crearía funciones
-- abiertas — sin fallar, sin avisar, y sin que la comprobación 1 lo viera hasta
-- la corrida siguiente.
--
-- Es exactamente lo que la imagen `supabase/postgres:17.6.1.165` trajo el
-- 2026-08-26, y lo que la 0076 no podía frenar: ella revoca de PUBLIC, y esto
-- es una concesión explícita a `anon`. Son dos cosas distintas.
--
-- `supabase_admin` tiene su propia regla, que también concede `anon`, y no se
-- comprueba a propósito: no crea funciones de la casa —las 276 son de
-- `postgres`, medido— y cambiarla exigiría ser miembro de ese rol.
select is_empty(
  $defacl$ select defaclrole::regrole::text as rol_creador,
                  array_to_string(defaclacl, ' ') as regla
             from pg_default_acl
            where defaclnamespace = 'public'::regnamespace
              and defaclobjtype = 'f'
              and defaclrole = 'postgres'::regrole
              and array_to_string(defaclacl, ' ') like '%anon=%' $defacl$,
  'la regla por defecto de postgres no le da EXECUTE a anon sobre funciones nuevas'
);

select * from finish();
rollback;
