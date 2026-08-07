-- ############################################################################
-- ####  SOLO LEE. Devuelve UNA fila. Se corre en 2 segundos.               ####
-- ############################################################################
--
-- huella_del_esquema.sql — ¿producción y el repositorio dicen lo mismo?
--
-- LAS DOS VECES QUE ESTO YA FALLÓ, Y LO QUE SE APRENDIÓ
--
--   PRIMERA. `comparar_funciones.sql` llevaba las huellas del repositorio
--   DENTRO del archivo. Se generaron a las 12:31, entraron nueve migraciones,
--   y a las 18:00 el archivo reportaba 25 funciones distintas que no lo eran.
--   Arreglo: sacar las huellas del archivo. Este archivo solo CALCULA.
--
--   SEGUNDA, el mismo día. La huella del repositorio se calculó a las 10:28 y
--   se mandó por escrito. A las 10:55 y a las 11:14 entraron cinco migraciones
--   más. Cuando la comparación se hizo, el número escrito ya no valía. La
--   caducidad no estaba en el archivo: se había mudado al mensaje.
--
--   De ahí salen las dos reglas que este archivo aplica:
--     · ninguna huella del repositorio viaja escrita, en ningún soporte;
--     · la fila dice HASTA QUÉ MIGRACIÓN llegó esta base, y sin ese dato la
--       comparación no se hace. Dos esquemas de generaciones distintas no
--       tienen por qué coincidir, y compararlos solo produce sustos falsos.
--
-- LO QUE SE SABE QUE VIVE SOLO EN PRODUCCIÓN
--   Otra sesión aplicó a mano dos funciones y dos columnas que nunca llegaron
--   al repositorio. Se apartan aquí por su nombre y se listan en
--   `solo_en_produccion`, para que la comparación mida lo que comparten las
--   dos bases y no se ahogue en algo ya conocido. Que la lista salga con esos
--   cuatro nombres y ni uno más es, en sí, media respuesta.
--   (Traerlas al repositorio es la tarea #12.)
--
-- CÓMO SE LEE LA FILA
--   n_funciones / n_candados / n_columnas iguales a los del laboratorio Y las
--   tres huellas iguales  →  producción y el repositorio son la misma cosa.
--   Cualquier huella distinta con el mismo conteo  →  hay código cambiado a
--   mano en producción, y ahí sí toca bajar al detalle.
-- ############################################################################

with esquema as (
  -- Cada objeto se reduce a «nombre = huella de su contenido». El nombre viaja
  -- aparte para poder apartar los conocidos sin tocar la huella de los demás.
  select 'fn' as k,
         p.proname as nombre,
         p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')='
           || md5(p.prosrc) as f
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname like 'fn\_%'

  union all

  select 'can',
         c.relname || '.' || con.conname,
         c.relname || '.' || con.conname || '=' || md5(pg_get_constraintdef(con.oid))
  from pg_constraint con
  join pg_class c on c.oid = con.conrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and con.contype in ('x','u','c','p','f')

  union all

  select 'col',
         c.relname || '.' || a.attname,
         c.relname || '.' || a.attname || '=' ||
         md5(format_type(a.atttypid, a.atttypmod) || '|' || a.attnotnull::text || '|' ||
             coalesce(pg_get_expr(d.adbin, d.adrelid), ''))
  from pg_attribute a
  join pg_class c on c.oid = a.attrelid
  join pg_namespace n on n.oid = c.relnamespace
  left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
  where n.nspname = 'public' and c.relkind = 'r'
    and a.attnum > 0 and not a.attisdropped
),
marcado as (
  select k, nombre, f,
         (k = 'fn'  and nombre in ('fn_set_devenga_beneficios', 'fn_resellar_dia'))
      or (k = 'col' and nombre in ('personas.devenga_beneficios', 'personas.devenga_hasta'))
         as aparte
  from esquema
)
select
  -- Sin esto la comparación no se hace: fija la generación del esquema.
  (select max(numero) from migraciones_aplicadas) as hasta_migracion,
  (select count(*)   from migraciones_aplicadas) as filas_registro,

  md5(string_agg(f, '|' order by f) filter (where k = 'fn'  and not aparte)) as funciones,
  md5(string_agg(f, '|' order by f) filter (where k = 'can'))                as candados,
  md5(string_agg(f, '|' order by f) filter (where k = 'col' and not aparte)) as columnas,

  count(*) filter (where k = 'fn'  and not aparte) as n_funciones,
  count(*) filter (where k = 'can')                as n_candados,
  count(*) filter (where k = 'col' and not aparte) as n_columnas,

  coalesce(string_agg(nombre, ' · ' order by nombre) filter (where aparte), 'ninguno')
    as solo_en_produccion
from marcado;
