-- ############################################################################
-- ####  SOLO LEE. Devuelve UNA fila. Se corre en 2 segundos.               ####
-- ############################################################################
--
-- huella_del_esquema.sql — ¿producción y el repositorio dicen lo mismo?
--
-- POR QUÉ ASÍ, Y NO COMO ANTES
--   `comparar_funciones.sql` lleva las huellas del repositorio DENTRO del
--   archivo. Eso lo hace caducar: se generan a las 12:31, entran nueve
--   migraciones, y a las 18:00 reporta diferencias que no existen. Pasó hoy, con
--   25 funciones. Un comparador que miente se deja de leer.
--
--   Este archivo no lleva ninguna huella dentro. Solo CALCULA la de producción.
--   La del repositorio se calcula en el mismo momento, del otro lado. Las dos
--   nacen y mueren en el mismo minuto: no hay tiempo para que caduquen.
--
-- CÓMO SE USA
--   1. Pégalo y córrelo.  2. Manda la fila que salga.
--   Si las cuatro huellas coinciden con las del laboratorio, producción y el
--   repositorio son la misma cosa. Si alguna no, ahí se mira en detalle.
-- ############################################################################

select
  -- Cada una resume una parte del esquema. Se separan para que una diferencia
  -- diga DÓNDE mirar en vez de solo «algo cambió».
  md5(string_agg(t.f, '|' order by t.f) filter (where t.k = 'fn'))  as funciones,
  md5(string_agg(t.f, '|' order by t.f) filter (where t.k = 'can')) as candados,
  md5(string_agg(t.f, '|' order by t.f) filter (where t.k = 'col')) as columnas,
  count(*) filter (where t.k = 'fn')  as n_funciones,
  count(*) filter (where t.k = 'can') as n_candados,
  count(*) filter (where t.k = 'col') as n_columnas
from (
  select 'fn' as k,
         p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')=' || md5(p.prosrc) as f
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname like 'fn\_%'

  union all

  select 'can',
         c.relname || '.' || con.conname || '=' || md5(pg_get_constraintdef(con.oid))
  from pg_constraint con
  join pg_class c on c.oid = con.conrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and con.contype in ('x','u','c','p','f')

  union all

  select 'col',
         c.relname || '.' || a.attname || '=' ||
         md5(format_type(a.atttypid, a.atttypmod) || '|' || a.attnotnull::text || '|' ||
             coalesce(pg_get_expr(d.adbin, d.adrelid), ''))
  from pg_attribute a
  join pg_class c on c.oid = a.attrelid
  join pg_namespace n on n.oid = c.relnamespace
  left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
  where n.nspname = 'public' and c.relkind = 'r'
    and a.attnum > 0 and not a.attisdropped
) t;
