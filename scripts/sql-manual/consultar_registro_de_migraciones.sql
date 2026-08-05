-- ============================================================================
-- consultar_registro_de_migraciones.sql — el repo y el registro, cara a cara
-- ============================================================================
-- Solo LEE. Se puede correr en producción sin riesgo.
--
-- Responde las DOS preguntas de una vez, porque cada una sola engaña:
--
--   FALTA ANOTAR   el archivo está en supabase/migrations y no tiene fila.
--                  Es lo que pasó con la 0146 el 2026-08-05.
--
--   SOBRA LA FILA  hay fila y no hay archivo. Puede ser algo aplicado a
--                  producción que nunca llegó al repo —lo peor que puede
--                  pasar— o una migración que vive fuera de git por datos
--                  personales, como la 0031 y la 0033.
--
-- LO QUE ESTA CONSULTA NO PRUEBA. Una fila dice que alguien la anotó, no que
-- su contenido esté en la base. Para eso está comparar_funciones.sql. Este
-- repositorio ya pagó esa diferencia: la 0089 figuraba aplicada y su contenido
-- nunca había llegado.
--
-- La lista de números se regenera desde el repo con:
--   ls -1 supabase/migrations | sed -E 's/^0*([0-9]+)_.*/\1/' | sort -n | tr '\n' ,
-- Al 2026-08-05: 156 archivos, de la 0001 a la 0161.
-- ============================================================================

with archivos(numero) as (select unnest(array[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,32,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100,101,102,103,104,105,106,107,109,110,111,112,113,114,115,116,117,118,119,120,121,122,123,124,125,126,127,128,129,130,131,132,134,135,136,137,138,140,141,142,143,144,145,146,147,148,149,150,151,152,153,154,155,156,157,158,159,160,161]))

select 'FALTA ANOTAR'  as que, a.numero, null::text as nombre
  from archivos a
 where a.numero not in (select numero from migraciones_aplicadas)

union all

select 'SOBRA LA FILA' as que, m.numero, m.nombre
  from migraciones_aplicadas m
 where m.numero not in (select numero from archivos)

order by 1, 2;
