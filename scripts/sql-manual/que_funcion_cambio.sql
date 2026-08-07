-- ############################################################################
-- ####  SOLO LEE. Devuelve UNA fila. Se corre en 2 segundos.               ####
-- ############################################################################
--
-- que_funcion_cambio.sql — el segundo nivel de `huella_del_esquema.sql`
--
-- CUÁNDO SE USA. Solo cuando la huella del esquema dice que las funciones
-- difieren PERO el conteo coincide. Eso descarta que falte o sobre código, y
-- deja una sola explicación: algún cuerpo de función no dice lo mismo en los
-- dos lados. Este archivo dice cuál.
--
-- POR QUÉ MANDA LAS 199 DE UNA VEZ, Y NO LAS SOSPECHOSAS
--   Porque «las sospechosas» exige una lista escrita a mano, y una lista
--   escrita a mano es exactamente lo que hizo perder el 2026-08-06. Los tres
--   archivos que este reemplaza —comparar_funciones, comparar_solo_funciones,
--   huellas_produccion— llevaban dentro huellas o nombres de un momento
--   anterior. El primero acusó a 25 funciones y ninguna lo era; el tercero
--   llevaba escritos los nombres de esas 25 acusadas, así que heredaba la
--   mentira y la daba por buena.
--
--   Las 199 caben en 6.500 caracteres. No hay ninguna razón para elegir.
--
-- POR QUÉ LA HUELLA VA CORTADA A 8 CARACTERES
--   Para que quepa. Dos funciones distintas tendrían que coincidir en esos 8
--   para engañarnos: con 199 comparaciones, una posibilidad entre veinte
--   millones. La huella completa se pide después, y solo de la que salga.
--
-- POR QUÉ `/n` DETRÁS DEL NOMBRE
--   Tres funciones de este sistema existen con más de una firma. El nombre
--   solo no las distingue y el orden entre ellas quedaría al azar, que es como
--   se fabrica una diferencia que no existe. El número de argumentos las separa.
--
-- LAS DOS APARTADAS son las que viven solo en producción (tarea #12). Se
-- excluyen igual que en `huella_del_esquema.sql`, para que las dos medidas
-- hablen del mismo conjunto.
-- ############################################################################

select
  -- El sello de generación. Si no coincide con el del laboratorio, no se
  -- compara: dos esquemas distintos no tienen por qué decir lo mismo.
  (select max(numero) from migraciones_aplicadas) as hasta_migracion,
  count(*) as n_funciones,
  string_agg(p.proname || '/' || p.pronargs || ':' || left(md5(p.prosrc), 8), ' '
             order by p.proname, p.pronargs) as huellas
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname like 'fn\_%'
  and p.proname not in ('fn_set_devenga_beneficios', 'fn_resellar_dia');
