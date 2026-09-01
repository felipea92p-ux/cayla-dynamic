-- ############################################################################
-- ####  SOLO LEE. Va en el SQL Editor de RETAIL, no en el de Dynamic.      ####
-- ############################################################################
--
-- 03-donde-quedaron-los-activos.sql
--
-- ── QUÉ PASÓ ────────────────────────────────────────────────────────────────
--
-- La pantalla `cayla-retail.vercel.app/finanzas/activos` dice «No hay activos
-- registrados en esta unidad» para LIM. Los activos de Lima se habían cargado.
-- Sospecha de Felipe: se perdieron en la mudanza.
--
-- ── POR QUÉ NO SE RECARGAN Y YA ─────────────────────────────────────────────
--
-- Porque «la pantalla no los muestra» y «no existen» son dos cosas distintas, y
-- la segunda es la menos probable. Después de mover datos, lo habitual es que
-- las filas sigan ahí colgadas de una unidad cuyo id cambió: la fila existe, el
-- filtro de LIM no la encuentra, la pantalla se ve vacía. Si se recargan a mano
-- sin mirar, quedan por duplicado y la depreciación se cuenta dos veces sobre
-- el mismo equipo.
--
-- Primero se mira. Después se decide.
--
-- ── QUÉ HACE ────────────────────────────────────────────────────────────────
--
-- No hace falta saber cómo se llama la tabla. Devuelve dos cosas a la vez:
--
--   1. Toda tabla cuyo NOMBRE suene a activos (activo, equipo, bien,
--      patrimonio, inventario, depreciación), con sus columnas, su total de
--      filas y hasta 50 filas de contenido — aunque esté vacía. Si la tabla
--      existe y tiene 0 filas, eso ya es la respuesta: se borraron de verdad.
--      Y si tiene filas de otras sedes, sus columnas nos dicen exactamente qué
--      forma tiene que tener la carga de Trujillo y Arequipa.
--
--   2. Toda tabla —se llame como se llame— que CONTENGA palabras que solo
--      pueden venir de un inventario: JBL, MacBook, Mac Mini, Lenovo, Xiaomi,
--      iPhone, Canon EOS, depreciación. Busca dentro de la fila entera
--      convertida a texto, así que los encuentra igual si quedaron en otra
--      tabla, dentro de un `jsonb` o pegados en un documento.
--
-- Entre las dos, la salida distingue los tres casos posibles: están y la
-- pantalla no los ve · están en otro sitio · no están.
--
-- ── SI RESULTA QUE NO ESTÁN ─────────────────────────────────────────────────
--
-- Entonces la pregunta pasa a ser de respaldos, y esa tiene reloj: la ventana
-- de recuperación de Supabase (backups diarios / point-in-time) es corta y
-- corre desde el día de la mudanza. Conviene mirarlo el mismo día, no la
-- semana siguiente. Recargar a mano es el último recurso, no el primero.
--
-- ⚠ La salida lleva números de serie y valores de compra: no se commitea.
-- ############################################################################

-- Mira TODOS los esquemas de negocio, no solo `public`. Es lo que hace falta
-- después de la unificación: las 22 tablas de retail viven ahora en el cajón
-- `retail` de la base de Dynamic, así que una consulta que solo mire `public`
-- responde «no hay nada» y suena a que se borraron.
with tablas as (
  select n.nspname as esquema, c.relname as tabla
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where c.relkind = 'r'          -- solo tablas de verdad, ni vistas ni índices
    and n.nspname not in ('pg_catalog', 'information_schema', 'auth', 'storage',
                          'extensions', 'graphql', 'graphql_public', 'realtime',
                          'vault', 'net', 'cron', 'pgbouncer', 'supabase_functions',
                          'supabase_migrations', 'pgsodium', 'pgsodium_masks')
),
-- El filtro va con `~` (expresión regular) y NO con `similar to`: ahí el guion
-- bajo es un comodín de un carácter y la salida vendría llena de ruido.
huella as (
  select esquema, tabla,
         -- `\m` es principio de palabra: sin eso, «bien» casa dentro de
         -- «derechohabientes» y la salida trae tablas que no tienen nada que ver.
         tabla ~ '(activo|asset|equipo|\mbien|patrimonio|inventario|depreciac)' as por_el_nombre,
         (xpath('/row/n/text()',
                query_to_xml(
                  format($q$select count(*) as n from %I.%I t
                           where lower(t::text) ~ '(jbl|macbook|mac ?mini|lenovo|legion|xiaomi|redmi|iphone|canon eos|deprecia)'$q$,
                         esquema, tabla),
                  false, true, '')))[1]::text::bigint as coincidencias,
         (xpath('/row/n/text()',
                query_to_xml(format('select count(*) as n from %I.%I t', esquema, tabla),
                             false, true, '')))[1]::text::bigint as filas_totales
  from tablas
)
select
  h.esquema || '.' || h.tabla as tabla,
  case when h.por_el_nombre and h.coincidencias = 0 and h.filas_totales = 0
         then '⚠ la tabla existe y está VACÍA'
       when h.por_el_nombre and h.coincidencias = 0
         then 'tabla de activos, con filas, pero ninguna es de estos equipos'
       else 'contiene equipos del inventario' end                       as lectura,
  h.filas_totales,
  h.coincidencias,
  (select string_agg(column_name || ' ' || data_type, ', ' order by ordinal_position)
     from information_schema.columns
    where table_schema = h.esquema and table_name = h.tabla)            as columnas,
  -- De las tablas que se llaman como activos se vuelca TODO (hasta 50 filas):
  -- ahí es donde se ve si las de Lima siguen ahí bajo otra unidad. De las
  -- demás, solo las filas que casaron, para que una tabla grande con una
  -- coincidencia suelta no tape la salida.
  (xpath('/row/j/text()',
         query_to_xml(
           format($q$select json_agg(x)::text as j from (
                       select * from %I.%I t
                        where %s
                        limit 50) x$q$,
                  h.esquema, h.tabla,
                  case when h.por_el_nombre then 'true'
                       else $f$lower(t::text) ~ '(jbl|macbook|mac ?mini|lenovo|legion|xiaomi|redmi|iphone|canon eos|deprecia)'$f$
                  end),
           false, true, '')))[1]::text                                  as filas
from huella h
where h.por_el_nombre or h.coincidencias > 0
order by h.por_el_nombre desc, h.coincidencias desc, h.tabla;


-- ############################################################################
-- SEGUNDA CONSULTA — ¿qué MÁS se quedó atrás?  (correr después de la primera)
-- ----------------------------------------------------------------------------
-- Los once pasos de la unificación crean las 22 tablas de retail vacías y no
-- copian ni una fila. Si eso fue todo lo que pasó, los activos no son el único
-- hueco: el inventario, las ventas, los proveedores y la caja estarían igual.
--
-- Esta consulta cuenta las filas de cada tabla del cajón `retail`. Se lee de un
-- vistazo: si casi todas están en 0, no se perdió una pantalla — se perdió la
-- mudanza entera, y eso se atiende antes que cualquier carga nueva. Si solo
-- `activos_fijos` está vacía, entonces los datos sí viajaron por otro camino y
-- lo único que faltó fue esta tabla.
-- ############################################################################

select c.relname as tabla,
       (xpath('/row/n/text()',
              query_to_xml(format('select count(*) as n from retail.%I t', c.relname),
                           false, true, '')))[1]::text::bigint as filas
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'retail' and c.relkind = 'r'
order by filas, c.relname;
