-- ############################################################################
-- ####  SOLO LEE. Devuelve UNA fila. La salida es larga (~12.000 caracteres) ####
-- ############################################################################
--
-- rescatar_lo_que_solo_vive_en_produccion.sql
--
-- ⚠ LEE ESTO ANTES DE ESCRIBIR UNA MIGRACIÓN QUE TOQUE ALGUNA DE ESTAS NUEVE.
--
-- QUÉ PROBLEMA DOCUMENTA
--   El 2026-08-07 se comparó el esquema de producción contra el del repositorio,
--   función por función. Nueve funciones y dos columnas de producción NO EXISTEN
--   EN NINGÚN ARCHIVO de este repositorio. Corren todos los días, deciden
--   marcajes y sueldos, ninguna prueba las toca, y si mañana hubiera que
--   reconstruir la base se pierden sin que nadie sepa qué decían.
--
--   Siete de ellas tienen MÁS código en producción que en el repositorio. Con
--   cuántos caracteres de más, medido:
--
--       fn_agregar_marcaje/5         +664
--       fn_set_sueldo_base_legal/2   +562
--       fn_quitar_rendimiento/3      +358
--       fn_corregir_marcaje/3        +260
--       fn_set_rendimiento/5         +235
--       fn_eliminar_marcaje/2         +92
--       fn_set_meta_cobertura/3       +11
--
--   Y dos existen SOLO en producción, sin equivalente aquí:
--
--       fn_resellar_dia
--       fn_set_devenga_beneficios    ← con personas.devenga_beneficios y
--                                      personas.devenga_hasta
--
--   Estas dos últimas son el botón por persona que decide quién devenga CTS,
--   gratificación y vacaciones. Es el trabajo que Felipe dio por perdido («en
--   otra sesión arreglé esto pero se perdió»): no se perdió, está corriendo en
--   producción y en ningún otro sitio.
--
-- POR QUÉ ESTE ARCHIVO ESTÁ AQUÍ Y NO EN UNA NOTA
--   Porque el riesgo no es olvidarlo: es que alguien escriba de buena fe un
--   `create or replace` sobre una de las nueve —copiando el cuerpo del
--   repositorio, que es lo correcto en cualquier otro caso— y borre en silencio
--   código que nadie ha leído nunca. `donde-vive.sh` no avisa de esto: mira los
--   archivos, y el problema es justamente lo que no está en ningún archivo.
--
--   Así que el aviso vive donde se va a tropezar con él, y trae la herramienta
--   para arreglarlo en la misma pieza.
--
-- CÓMO SE USA
--   1. Pégalo en el SQL Editor de producción y manda la fila entera.
--   2. Del otro lado se escribe una migración por cada cuerpo rescatado, con su
--      encabezado y su prueba, y se aplica —idempotente— para que el
--      repositorio y producción digan por fin lo mismo.
--   3. Solo entonces se puede tocar cualquiera de las nueve sin riesgo.
--
--   ORDEN IMPORTANTE: rescatar primero, arreglar después. Nunca al revés.
-- ############################################################################

select
  -- Las nueve, con su firma completa, su `security definer` y su `search_path`.
  (select string_agg(pg_get_functiondef(p.oid),
                     E'\n\n-- ============================================================\n\n'
                     order by p.proname, p.pronargs)
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and (p.proname || '/' || p.pronargs) in (
            'fn_agregar_marcaje/5', 'fn_corregir_marcaje/3', 'fn_eliminar_marcaje/2',
            'fn_set_rendimiento/5', 'fn_quitar_rendimiento/3',
            'fn_set_sueldo_base_legal/2', 'fn_set_meta_cobertura/3')
       or p.proname in ('fn_resellar_dia', 'fn_set_devenga_beneficios'))
    as las_nueve,

  -- Y las dos columnas: tipo, si admite vacío y su valor por defecto.
  (select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod)
                     || case when a.attnotnull then ' not null' else '' end
                     || coalesce(' default ' || pg_get_expr(d.adbin, d.adrelid), ''),
                     E'\n' order by a.attname)
     from pg_attribute a
     join pg_class c on c.oid = a.attrelid
     join pg_namespace n on n.oid = c.relnamespace
     left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
    where n.nspname = 'public' and c.relname = 'personas'
      and a.attname in ('devenga_beneficios', 'devenga_hasta'))
    as las_dos_columnas;
