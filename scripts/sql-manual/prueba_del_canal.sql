-- ############################################################################
-- ####  SOLO LEE. No toca nada. Cinco segundos.                            ####
-- ############################################################################
--
-- prueba_del_canal.sql — ¿este camino de pegado rompe los acentos?
--
-- PARA QUÉ SIRVE
--   Se pega ANTES de pegar algo importante, por la MISMA ruta por la que vayas a
--   pegarlo (mismo copiar, misma app, misma ventana). Si dice que el canal está
--   sano, lo que pegues después llegará entero. Si dice que no, no pegues nada
--   por ahí.
--
-- POR QUÉ HACE FALTA
--   El 2026-08-08 se midió que `fn_planilla_calcular` —la función que decide lo
--   que cobra cada persona— corría en producción con los acentos partidos en
--   dos: «l√≠der» donde debía decir «líder». Es texto UTF-8 leído como Mac OS
--   Roman, y entró ese mismo día al pegar la 0185.
--
--   Ese día se pegaron cinco migraciones. Cuatro llegaron intactas y una no. O
--   sea que el daño no depende de la migración: depende del CAMINO por el que el
--   texto llegó al SQL Editor. La lógica no cambia —solo se rompen los mensajes
--   que lee una persona— pero es la clase de cosa que se descubre un año después
--   y sin saber cuándo empezó.
--
-- ── CÓMO FUNCIONA, QUE ES LO ÚNICO INTERESANTE ──────────────────────────────
--
-- La consulta compara dos «líder»:
--
--   · uno ESCRITO con su acento, que viaja contigo por el camino que se prueba;
--   · otro CONSTRUIDO con `chr(237)`, que es el número del carácter «í».
--
-- Un número no se puede estropear al copiar: 237 es 237 en cualquier
-- codificación. Así que el segundo llega siempre intacto y sirve de patrón. Si
-- el primero le sigue siendo igual al llegar, el camino no tocó nada.
--
-- Es la misma idea que `huella_del_esquema.sql`: no confiar en un dato guardado,
-- sino comparar contra algo que se calcula en el momento y no puede caducar.
-- ############################################################################

select
  case when 'líder' = 'l' || chr(237) || 'der'
       then '✓  CANAL SANO — lo que pegues por aquí llega entero'
       else '✗  CANAL ROTO — los acentos se están estropeando. NO pegues por aquí'
  end as veredicto,

  -- Lo que de verdad llegó, para verlo con los ojos. Si el canal está roto se
  -- lee «l√≠der» y no hace falta creerle a nadie.
  'líder' as lo_que_llego,

  -- Y el patrón, armado con números. Este siempre dice «líder».
  'l' || chr(237) || 'der' as como_deberia_leerse,

  -- Un segundo par, con otros dos acentos y una eñe, por si el daño solo
  -- afectara a algunos caracteres.
  case when 'asignación mañana' = 'asignaci' || chr(243) || 'n ma' || chr(241) || 'ana'
       then 'ó y ñ también llegan bien'
       else 'ó o ñ también se rompen'
  end as segunda_comprobacion;
