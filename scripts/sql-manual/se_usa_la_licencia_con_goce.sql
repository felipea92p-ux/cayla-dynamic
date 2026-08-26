-- ============================================================================
-- ¿SE USA `licencia_con_goce`, Y DE QUÉ VERSIÓN DE LA BOLETA PARTIMOS?
-- ============================================================================
-- Solo LEE. Se pega entero en el SQL Editor de Supabase.
--
-- Responde las dos preguntas que hacen falta antes de tocar la boleta:
--
--   1 · ¿Alguien tiene una licencia con goce registrada? Si la hay dentro de un
--       periodo YA PAGADO, entonces a esa persona se le pagó de menos y esto
--       deja de ser un riesgo latente para ser plata que hay que devolver.
--
--   2 · El md5 de partida de `fn_planilla_calcular`, que la regla de la casa
--       exige pedir a producción ANTES de escribir la migración.
--
-- Va TODO en un solo `select` a propósito: el SQL Editor solo corre el último.
--
-- CÓMO SE LEE LA FILA QUE DEVUELVE
--
--   md5_tal_cual = 4688bf0101891f347f05cf96c0db9e68  (96 354 chars aprox.)
--     → producción está idéntica a esta Mac. Seguimos.
--
--   md5_sin_comentarios = 5585aa09f32b3d72534514477e7e43e6, y el otro distinto
--     → MISMO CÓDIGO, sin los comentarios (le pasa a la mitad de las funciones
--       de producción). Seguimos, pero la migración declara el md5 de PRODUCCIÓN.
--
--   ninguno de los dos coincide
--     → PARAR. Producción tiene otra versión de la boleta y hay que mirarla
--       antes de escribir nada encima.
--
--   licencias_total = 0
--     → nadie la ha usado nunca: el defecto es real pero no ha costado plata.
--
--   licencias_en_periodo_pagado > 0
--     → a alguien se le pagó de menos. `personas_afectadas` dice a cuántas.
-- ============================================================================

select
  -- 1 · de qué versión de la boleta partimos
  (select md5(p.prosrc)
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_planilla_calcular')   as md5_tal_cual,

  (select md5(array_to_string(array(
            select regexp_replace(l, '[[:space:]]*--.*$', '')
              from unnest(string_to_array(p.prosrc, chr(10))) as l
             where btrim(l) not like '--%'
          ), chr(10)))
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_planilla_calcular')   as md5_sin_comentarios,

  (select length(p.prosrc)
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_planilla_calcular')   as caracteres,

  -- 2 · ¿se usa, y le costó plata a alguien?
  (select count(*) from ausencias
    where tipo = 'licencia_con_goce' and anulada_at is null)             as licencias_total,

  (select count(*) from ausencias
    where tipo = 'licencia_con_goce' and anulada_at is null
      and aprobada_at is not null)                                       as licencias_firmadas,

  (select count(distinct a.persona_id)
     from ausencias a
     join periodos_planilla pp
       on pp.estado = 'pagado'
      and a.fecha_inicio <= pp.fecha_fin
      and a.fecha_fin    >= pp.fecha_ini
    where a.tipo = 'licencia_con_goce' and a.anulada_at is null)         as personas_afectadas,

  (select count(*)
     from ausencias a
     join periodos_planilla pp
       on pp.estado = 'pagado'
      and a.fecha_inicio <= pp.fecha_fin
      and a.fecha_fin    >= pp.fecha_ini
    where a.tipo = 'licencia_con_goce' and a.anulada_at is null)         as licencias_en_periodo_pagado,

  (select min(a.fecha_inicio) from ausencias a
    where a.tipo = 'licencia_con_goce' and a.anulada_at is null)         as primera,

  (select max(a.fecha_fin) from ausencias a
    where a.tipo = 'licencia_con_goce' and a.anulada_at is null)         as ultima;
