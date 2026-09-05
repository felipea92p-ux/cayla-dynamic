-- ============================================================================
-- 0204_un_drop_se_lleva_el_permiso_y_la_pantalla_se_calla.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que el semáforo de tardanzas vuelva a verse, y que se pueda volver a
--   guardar una ficha de datos personales. Dos pantallas que llevan días
--   calladas en producción.
--
-- QUÉ ASUME
--   Nada. Son dos GRANT. No toca ni una tabla, ni un cuerpo de función, ni un
--   dato. Es la migración más pequeña de este repositorio y arregla dos caídas.
--
-- ── QUÉ PASÓ, MEDIDO ────────────────────────────────────────────────────────
--
-- **Un `drop function` se lleva por delante los GRANT.** Es lo que hace la
-- 0189 antes de recrear `fn_tardanzas_resumen` —obligada, porque la función
-- devuelve TABLE y Postgres no deja añadirle una columna con `create or
-- replace`— y después no vuelve a otorgar nada. El último `grant execute` sobre
-- esa función en todo el repositorio es de la **0067**.
--
-- Y este proyecto REVOCA el EXECUTE que Postgres da a PUBLIC por defecto, así
-- que no hubo nada que lo rescatara. El ACL quedó así:
--
--     fn_tardanzas_resumen   postgres=X/postgres · service_role=X/postgres
--     fn_faltas_resumen      postgres=X/postgres · authenticated=X/postgres · …
--                                                  ↑ esta sí lo tiene
--
-- CÓMO SE VE DESDE FUERA, y por qué nadie lo notó: `authenticated` no puede
-- ejecutarla, PostgREST devuelve error, y `admin/disciplina/page.tsx` NO miraba
-- el error de esa llamada — imprimía «Nadie con tardanzas relevantes este mes»,
-- la misma frase que cuando de verdad no hay nadie. Un falso negativo mudo en
-- la única pantalla cuyo trabajo es no dejar pasar a nadie. El Dashboard y la
-- Hoja de sede leen la misma función y llevaban igual de ciegos.
--
-- LA SEGUNDA, encontrada barriendo las 122 funciones que el panel llama por
-- `rpc()`: la 0198 añadió `p_cuspp` a `fn_set_datos_personales` con un
-- `create or replace`. Un parámetro nuevo NO reemplaza: **crea otra función**.
-- Quedaron dos sobrecargas, la de 18 argumentos con su permiso y la de 19 sin
-- él, y el panel manda `p_cuspp` — así que PostgREST elige justo la que no
-- puede ejecutar. Guardar una ficha falla desde entonces.
--
-- ── LO QUE ESTA MIGRACIÓN NO HACE ───────────────────────────────────────────
--
-- No suelta la sobrecarga huérfana de 18 argumentos de fn_set_datos_personales.
-- Con el GRANT puesto, el panel resuelve a la de 19 y la vieja queda muerta
-- pero inofensiva. Soltarla es correcto y conviene hacerlo, pero es un cambio
-- de esquema y esta migración quiere ser lo más pequeña posible: se está
-- pegando para levantar dos pantallas caídas.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--   revoke execute on function public.fn_tardanzas_resumen(date) from authenticated;
--   revoke execute on function public.fn_set_datos_personales(…) from authenticated;
--   Revertir significa volver a dejar el semáforo disciplinario ciego.
--
-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
--   La consulta del final. Las dos filas tienen que decir SÍ.
-- ============================================================================

grant execute on function public.fn_tardanzas_resumen(date) to authenticated;

-- La de 19 argumentos: la que el panel elige porque manda `p_cuspp`.
grant execute on function public.fn_set_datos_personales(
  uuid, text, date, text, text, text, text, text, text, boolean,
  text, text, text, text, text, text, boolean, text, text
) to authenticated;

-- ── El registro, y que la API recargue el esquema ───────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (204, 'un_drop_se_lleva_el_permiso_y_la_pantalla_se_calla')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra la última consulta.
--
-- Las cuatro que sostienen las dos pantallas caídas. Las cuatro tienen que
-- decir SÍ.
--
-- La comprobación es NOMINAL y no un barrido, a propósito. Un barrido por
-- `prosecdef` recoge triggers, funciones de CHECK y auxiliares internas que no
-- necesitan este permiso —catorce falsos positivos, medidos— y un freno que
-- chilla siempre acaba desactivado. El barrido de verdad, contra la lista real
-- de funciones que el panel llama por `rpc()`, vive aparte en
-- `scripts/sql-manual/quien_puede_ejecutar_el_semaforo.sql`.
select
  f.nombre                                                as funcion,
  case when has_function_privilege('authenticated', f.oid, 'EXECUTE')
       then 'SÍ' else '⚠ NO — sigue caída' end            as puede_authenticated,
  coalesce(array_to_string(p.proacl, ' · '), '(sin ACL)') as acl_actual
from (values
  ('fn_tardanzas_resumen',     'public.fn_tardanzas_resumen(date)'::regprocedure),
  ('fn_faltas_resumen',        'public.fn_faltas_resumen(date)'::regprocedure),
  ('fn_set_datos_personales',  'public.fn_set_datos_personales(uuid,text,date,text,text,text,text,text,text,boolean,text,text,text,text,text,text,boolean,text,text)'::regprocedure),
  ('fn_es_admin_o_lider',      'public.fn_es_admin_o_lider()'::regprocedure)
) as f(nombre, oid)
join pg_proc p on p.oid = f.oid
order by 2, 1;
