-- ############################################################################
-- ####  SOLO LEE. Una fila. Instantáneo.                                   ####
-- ############################################################################
--
-- en_que_version_esta_la_planilla.sql
--
-- ¿En qué versión está `fn_planilla_calcular` en producción, y llegó entera?
--
-- CUÁNDO SE CORRE
--   Antes de pegar CUALQUIER migración que reescriba esta función. Su encabezado
--   siempre dice de qué cuerpo parte; esto dice de qué cuerpo se parte de verdad.
--
-- POR QUÉ NO BASTA CON MIRAR `migraciones_aplicadas`
--   Una fila ahí dice que alguien la anotó, no que su contenido esté en la base.
--   Este repositorio ya pagó esa diferencia dos veces: con la 0089, cuyo
--   contenido nunca llegó, y el 2026-08-08 con la 0185, que llegó con los
--   acentos partidos y estuvo horas corriendo así.
--
-- POR QUÉ IMPORTA MÁS EN ESTA FUNCIÓN QUE EN NINGUNA
--   Porque cada migración que la toca reescribe el CUERPO ENTERO. Pegar una
--   fuera de orden no da error: arrastra la función hacia atrás y revierte en
--   silencio todo lo que se hizo entre medias. `fn_planilla_calcular` tiene hoy
--   más de veinte versiones repartidas y decide lo que cobra cada persona.
--
-- LAS DOS COLUMNAS DICEN COSAS DISTINTAS
--   `veredicto`            en qué versión está, y si se puede seguir.
--                          ⚠️ Este catálogo se escribe A MANO y por eso envejece:
--                          nació el 2026-08-08 sin conocer la 0192 ni la 0193,
--                          que ya estaban en el repositorio. Cuando diga «SIN
--                          CATALOGAR», lo más probable no es que pase algo raro:
--                          es que hay una migración nueva y falta añadirla aquí.
--                          Los md5 se sacan con el generador de este archivo.
--   `tiene_acentos_rotos`  si el texto llegó estropeado. Puede estar en la
--                          versión correcta Y rota: el md5 lo distingue, pero
--                          esta columna lo dice sin depender de ninguna lista.
-- ############################################################################

select
  md5(prosrc) as huella,

  case md5(prosrc)
    when '449cc75cc4d097096fd87cdbd13b68f1' then '✓  0193 limpia — al día con el repositorio'
    when '684634d24dd1a28ace4e99f1fd174ad6' then '⚠  se quedó en la 0192 — falta pegar la 0193'
    when 'ba9dfd2726ea59b86b43fc057c210ece' then '⚠  se quedó en la 0187 — faltan la 0192 y la 0193'
    when 'f81bcf49a3a20337365b06f5a850d53e' then '⚠  se quedó en la 0186 — falta pegar la 0187'
    when '187cb5c3b5389f507fc77a18f8af846c' then '⚠  se quedó en la 0185 — faltan la 0186 y la 0187'
    when '93e96e37e05799121485e5721de3dc06' then '⚠  se quedó en la 0177 — faltan tres'
    -- Las mismas versiones, pero con el texto estropeado en el camino.
    when 'c6c75c8a3f12c6aeaf1cb9ac19a7044a' then '✗  0193 CON LOS ACENTOS ROTOS — vuelve a pegarla'
    when 'f588806871f74189de370355dfb22767' then '✗  0192 CON LOS ACENTOS ROTOS'
    when '9ea5860ccb48d497209051de551e8ab3' then '✗  0187 CON LOS ACENTOS ROTOS'
    when '1654991224bc19095b32468683c5a8e4' then '✗  0186 CON LOS ACENTOS ROTOS'
    when '244e9cf3de7412d7603c036040669a1b' then '✗  0185 CON LOS ACENTOS ROTOS'
    when '17e05875aa7d862e6e9310b124e81f7e' then '✗  0177 CON LOS ACENTOS ROTOS'
    else '⚠  md5 SIN CATALOGAR — parar y avisar antes de pegar nada encima'
  end as veredicto,

  -- Este no depende del catálogo de arriba: busca el signo «√», que en
  -- castellano no aparece nunca dentro de un mensaje. Si el catálogo se queda
  -- viejo, esta columna sigue diciendo la verdad.
  (prosrc like '%' || chr(8730) || '%') as tiene_acentos_rotos,

  length(prosrc) as caracteres

from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'fn_planilla_calcular';
