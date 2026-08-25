-- ############################################################################
-- ####  ¿PRODUCCIÓN TIENE LA MISMA fn_crear_persona QUE ESTA MAC?         ####
-- ############################################################################
--
-- Se pide ANTES de escribir la migración que la corrige, no después — es la
-- regla que costó la 0276 (2026-08-20): copiar de una versión que no es la
-- vigente en producción revierte en silencio todo lo que se arregló entre
-- medias.
--
-- POR QUÉ HACE FALTA. `fn_crear_persona` acepta cualquiera de los cuatro
-- roles —incluido 'admin'— al crear una persona NUEVA, sin ningún control de
-- escalafón: un lider_do podría crear una cuenta nueva directamente como
-- Admin. Es la misma vulnerabilidad que la 0295/0296 ya cerraron para
-- cambiar el rol de alguien que YA existe, por la puerta de crear a alguien
-- que no existía. El arreglo toca `CREATE OR REPLACE FUNCTION` sobre una
-- función existente, así que necesita partir del cuerpo exacto de
-- producción.
--
-- EL MD5 LOCAL, de donde-vive.sh (0022_areas_catalogo.sql, la vigente):
--   b74c3530652abb56c9bc97101e4512d0
--
-- CÓMO SE LEE LO QUE DEVUELVA
--   · tal_cual coincide con el de arriba → producción está igual. Sigue.
--   · sin_comentarios coincide, tal_cual no → producción perdió los
--     comentarios al pegarse (le pasa a casi la mitad de las funciones,
--     medido 2026-08-18). Sigue, pero la migración declara el md5 de
--     PRODUCCIÓN, no éste.
--   · ninguno coincide → PARA. Hay una versión en producción que este
--     repositorio no conoce. No copiar el cuerpo de la 0022 sin decírmelo.
-- ############################################################################

select md5(p.prosrc)                                   as tal_cual,
       md5(array_to_string(array(
         select regexp_replace(l, '[[:space:]]*--.*$', '')
         from unnest(string_to_array(p.prosrc, chr(10))) as l
         where btrim(l) not like '--%'
       ), chr(10)))                                    as sin_comentarios,
       length(p.prosrc)                                as caracteres
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'fn_crear_persona';
