-- ############################################################################
-- ####  ¿PRODUCCIÓN TIENE LA MISMA fn_crear_persona QUE ESTA MAC?         ####
-- ############################################################################
--
-- Se pide ANTES de escribir la migración que la reescribe, no después — es la
-- regla que costó la 0276 (2026-08-20): copiar de una versión que no es la
-- vigente en producción revierte en silencio todo lo que se arregló entre
-- medias.
--
-- LA VERSIÓN VIGENTE EN EL REPOSITORIO es la de la 0300 (el escalafón al crear a
-- alguien; confirmada en producción el 2026-08-25). La 0506 la reescribe para
-- agregarle el aviso de parecidos, y cambia su firma de 7 a 8 argumentos.
--
-- EL MD5 LOCAL de la 0300, de donde-vive.sh:
--   tal_cual:        143a698ae6f6907298430324c7ff623d   (2050 caracteres)
--   sin_comentarios: 8ed9099437a0dc93ecd1fd70560169e7
-- (Hasta esta fecha el archivo decía b74c3530…, que es el cuerpo de la 0022, el
-- de ANTES de la 0300: comparar contra ese daba «no coincide» con producción
-- perfectamente sana.)
--
-- CÓMO SE LEE LO QUE DEVUELVA
--   · tal_cual coincide con el de arriba → producción está igual. Sigue.
--   · sin_comentarios coincide, tal_cual no → producción perdió los
--     comentarios al pegarse (le pasa a casi la mitad de las funciones,
--     medido 2026-08-18). Sigue, pero la migración declara el md5 de
--     PRODUCCIÓN, no éste.
--   · retornos = número de líneas de la función, y tal_cual no coincide → es el
--     `\r` de pegar desde Windows (0401): benigno, la función se comporta igual.
--   · ninguno coincide y retornos = 0 → PARA. Hay una versión en producción que
--     este repositorio no conoce. No copiar el cuerpo de la 0300 sin decírmelo.
--   · versiones distinto de 1 → PARA. Ya hay dos firmas de fn_crear_persona
--     (alguien pegó una migración parecida a la 0506): la llamada de siete
--     argumentos estaría ambigua y la pantalla de Equipo no podría dar de alta.
-- ############################################################################

select md5(p.prosrc)                                   as tal_cual,
       md5(array_to_string(array(
         select regexp_replace(l, '[[:space:]]*--.*$', '')
         from unnest(string_to_array(p.prosrc, chr(10))) as l
         where btrim(l) not like '--%'
       ), chr(10)))                                    as sin_comentarios,
       length(p.prosrc)                                as caracteres,
       length(p.prosrc) - length(replace(p.prosrc, chr(13), '')) as retornos,
       (select count(*) from pg_proc q join pg_namespace m on m.oid = q.pronamespace
         where m.nspname = 'public' and q.proname = 'fn_crear_persona') as versiones
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'fn_crear_persona'
 order by p.oid desc
 limit 1;
