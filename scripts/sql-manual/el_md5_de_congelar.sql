-- ############################################################################
-- ####  EL MD5 DE PARTIDA DE fn_planilla_congelar  — SOLO LEE              ####
-- ############################################################################
--
-- Para qué. La 0284 reescribe `fn_planilla_congelar`: le inserta una
-- declaración y un bloque sobre el cuerpo vivo, sin tocar el resto. Antes de
-- pegarla hay que comprobar que producción tiene el cuerpo del que se partió —
-- si tiene otro, pegar la 0284 revertiría en silencio lo que ese otro trajera.
--
-- ⚠ SE CORRE ANTES DE PEGAR LA 0284, NO DESPUÉS. Una vez pegada, el md5 de
-- partida deja de existir y no hay forma de recuperarlo.
--
-- Es la misma consulta que imprime `./scripts/donde-vive.sh fn_planilla_congelar`.
-- Vive acá para poder pegarla sin copiarla del terminal.
--
-- ── CÓMO SE LEE LO QUE DEVUELVA ─────────────────────────────────────────────
--
-- Los tres desenlaces, contra lo medido en el Postgres local el 2026-08-23:
--
--   · tal_cual = 1692771a95d4fe46d1d01d7005b37728
--     → producción idéntica al repositorio. Se sigue.
--
--   · sin_comentarios = 63364f40980570e732b03374d04428cc, y tal_cual distinto
--     → MISMO CÓDIGO; producción perdió los comentarios al pegarse, que le pasa
--       a la mitad de las funciones. Se sigue, pero la cabecera de la 0284 tiene
--       que declarar el md5 de PRODUCCIÓN, no el de la Mac.
--
--   · ninguno de los dos coincide
--     → PARAR. Producción tiene otra versión. Antes de proponer explicaciones,
--       medir dónde está la diferencia: `caracteres` contra los 10 639 de acá,
--       y un `substring` del principio del cuerpo.
--
-- ES UNA SOLA CONSULTA porque el SQL Editor solo muestra el último select.
-- ############################################################################

select md5(p.prosrc)                                   as tal_cual,
       md5(array_to_string(array(
         select regexp_replace(l, '[[:space:]]*--.*$', '')
         from unnest(string_to_array(p.prosrc, chr(10))) as l
         where btrim(l) not like '--%'
       ), chr(10)))                                    as sin_comentarios,
       length(p.prosrc)                                as caracteres
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname = 'fn_planilla_congelar';
