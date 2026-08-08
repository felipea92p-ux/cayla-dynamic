-- ############################################################################
-- ####  SOLO LEE. Una fila. La salida es larga: mándala entera.            ####
-- ############################################################################
--
-- rescatar_lo_que_solo_vive_en_produccion.sql
--
-- ⚠ LEE ESTO ANTES DE ESCRIBIR UNA MIGRACIÓN QUE TOQUE ALGUNA DE ESTAS CINCO.
--
-- ── QUÉ ES ESTO, EN CRISTIANO ───────────────────────────────────────────────
--
-- Este proyecto tiene una regla: TODO lo que corre en producción tiene que
-- existir también como archivo en el repositorio. Los archivos son el plano; la
-- base es el edificio. Si el plano está completo, el edificio se puede volver a
-- levantar; si falta una habitación en el plano, esa habitación existe hasta el
-- día que alguien reconstruya desde los planos — y entonces desaparece.
--
-- Hay cosas en producción que NO están en ningún archivo. Se aplicaron a mano en
-- otra sesión y el archivo nunca se guardó. Corren todos los días, deciden
-- marcajes y sueldos, ninguna prueba las toca y nadie las ha leído nunca.
--
-- Rescatarlas es: pedirle a producción su código exacto, guardarlo como una
-- migración normal con su encabezado y su porqué, y aplicarla —es idempotente,
-- no cambia nada— para que a partir de ahí el plano y el edificio coincidan.
--
-- ── LO QUE FALTA HOY, 2026-08-08 ────────────────────────────────────────────
--
-- Eran nueve funciones y dos columnas. La 0188 rescató cuatro —fn_resellar_dia,
-- fn_agregar_marcaje, fn_corregir_marcaje y fn_eliminar_marcaje—, así que queda:
--
--   CUATRO funciones con MÁS código en producción que en el repositorio. Con
--   cuántos caracteres de más, medido el 2026-08-08:
--
--       fn_set_sueldo_base_legal/2   +562
--       fn_quitar_rendimiento/3      +358
--       fn_set_rendimiento/5         +235
--       fn_set_meta_cobertura/3       +11
--
--     Ese «más» es código que alguien escribió, que funciona, y que el
--     repositorio no conoce. Copiar encima la versión del repositorio —que es lo
--     correcto en cualquier otro caso— lo borraría sin dar ningún error.
--
--   UNA función y DOS columnas que no existen en el repositorio en absoluto:
--
--       fn_set_devenga_beneficios
--       personas.devenga_beneficios
--       personas.devenga_hasta
--
--     Estas tres son EL BOTÓN POR PERSONA que decide quién devenga CTS,
--     gratificación y vacaciones. Es el trabajo que Felipe dio por perdido
--     —«en otra sesión arreglé esto pero se perdió»—: no se perdió, lleva
--     semanas corriendo en producción y en ningún otro sitio.
--
--     Si desapareciera, Catherine —que cobra por honorarios— volvería a acumular
--     CTS y vacaciones, y a Carlos le volverían las vacaciones que se decidió no
--     darle. O sea: no es un problema de orden, es plata mal provisionada.
--
-- ── POR QUÉ ESTE AVISO VIVE AQUÍ Y NO EN UNA NOTA ───────────────────────────
--
-- Porque el riesgo no es olvidarlo: es que alguien escriba de buena fe un
-- `create or replace` sobre una de las cinco, copiando el cuerpo del repositorio
-- —lo correcto en cualquier otro caso— y borre en silencio código que nadie ha
-- leído. `donde-vive.sh` no puede avisar: mira los archivos, y el problema es
-- justamente lo que no está en ningún archivo.
--
-- ── CÓMO SE USA ─────────────────────────────────────────────────────────────
--   1. Pégalo en el SQL Editor de producción y manda la fila entera.
--   2. Del otro lado se escribe una migración por cada pieza, con su encabezado
--      y su prueba, y se aplica —idempotente, no mueve un céntimo.
--   3. Solo entonces se puede tocar cualquiera de las cinco sin riesgo.
--
--   ORDEN IMPORTANTE: rescatar primero, arreglar después. Nunca al revés.
-- ############################################################################

select
  -- Las cinco funciones, con su firma completa, su `security definer` y su
  -- `search_path`: todo lo que hace falta para reconstruirlas idénticas.
  (select string_agg(pg_get_functiondef(p.oid),
                     E'\n\n-- ============================================================\n\n'
                     order by p.proname, p.pronargs)
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and ((p.proname || '/' || p.pronargs) in (
             'fn_set_sueldo_base_legal/2', 'fn_quitar_rendimiento/3',
             'fn_set_rendimiento/5', 'fn_set_meta_cobertura/3')
           or p.proname = 'fn_set_devenga_beneficios'))
    as las_cinco_funciones,

  -- Las dos columnas: tipo, si admite vacío y su valor por defecto.
  (select coalesce(string_agg(
            a.attname || ' ' || format_type(a.atttypid, a.atttypmod)
            || case when a.attnotnull then ' not null' else '' end
            || coalesce(' default ' || pg_get_expr(d.adbin, d.adrelid), ''),
            E'\n' order by a.attname), 'NINGUNA — ya no están')
     from pg_attribute a
     join pg_class c on c.oid = a.attrelid
     join pg_namespace n on n.oid = c.relnamespace
     left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
    where n.nspname = 'public' and c.relname = 'personas'
      and a.attname in ('devenga_beneficios', 'devenga_hasta'))
    as las_dos_columnas,

  -- Y el dato que dice si el rescate sigue haciendo falta o ya lo hizo otro.
  -- Si alguna de las cinco no aparece acá, es que no existe en producción y hay
  -- que averiguar por qué antes de escribir nada.
  (select string_agg(p.proname || '/' || p.pronargs, ' ' order by p.proname)
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and (p.proname in ('fn_set_sueldo_base_legal', 'fn_quitar_rendimiento',
                         'fn_set_rendimiento', 'fn_set_meta_cobertura',
                         'fn_set_devenga_beneficios')))
    as las_que_existen;

-- ── POR QUÉ ESTA CONSULTA NO CUENTA A CUÁNTAS PERSONAS AFECTA ───────────────
-- La primera versión terminaba con
--     (select count(*) from personas where devenga_beneficios is not null)
-- para decir cuánta gente tiene el interruptor puesto. Se quitó: si esa columna
-- NO existiera, Postgres no devuelve esa celda vacía — falla la consulta ENTERA
-- al analizarla, y las otras tres columnas, que son el rescate, no se ven.
--
-- Una herramienta de diagnóstico no puede depender de que la cosa que va a
-- diagnosticar exista. `las_dos_columnas` ya dice si están o no, y eso se
-- responde desde el catálogo del sistema, que siempre se puede consultar.
-- El conteo se pide después, cuando la columna ya esté en el repositorio.
