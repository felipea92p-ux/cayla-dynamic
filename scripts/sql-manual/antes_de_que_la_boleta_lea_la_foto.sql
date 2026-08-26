-- ############################################################################
-- ####  ANTES DE QUE LA BOLETA LEA LA FOTO — SOLO LEE, NO ESCRIBE NADA    ####
-- ############################################################################
--
-- Se corre ANTES de escribir la migración que hace que un mes ya pagado se
-- reimprima desde `planilla_pagada_detalle` en vez de recalcularse.
--
-- Responde las tres cosas que hacen falta para escribirla bien. Va todo en un
-- solo `select` porque el SQL Editor solo corre el último.
--
-- ── 1 · DE QUÉ VERSIÓN PARTIMOS ────────────────────────────────────────────
--
-- La regla de la casa: el md5 de partida se le pide a PRODUCCIÓN, no se copia
-- del local. `fn_proyeccion_periodo` es corta y su cuerpo no lleva comentarios,
-- así que los dos md5 tienen que dar lo mismo.
--
--   md5_tal_cual = fad72eefc30b5b2de9dd81460cf87dd9
--     → producción está igual que esta Mac. Escribo sobre eso.
--
--   distinto
--     → PARAR. Producción tiene otra versión y hay que mirarla antes de
--       escribir nada encima.
--
-- ── 2 · CUÁNTOS MESES PUEDEN LEERSE ────────────────────────────────────────
--
--   pagados_sin_foto > 0
--     → esos meses son anteriores al registro congelado y NO tienen de dónde
--       leer. Ahí la boleta no puede decir la verdad, y lo honesto es que avise
--       en vez de dar un recálculo disfrazado de original. Si es 0, el arreglo
--       cubre todo lo pagado y ese aviso no le sale a nadie.
--
-- ── 3 · LA TRAMPA DE LAS VERSIONES ─────────────────────────────────────────
--
-- La foto es de solo-agregar y su `version` es del PERIODO entero, no de la
-- persona (fn_planilla_congelar, 0201). Así que un repago crea una versión
-- nueva y deja vivas las viejas.
--
-- `fn_liquidacion` ya dejó escrito por qué eso importa: quien ya no sale en el
-- recálculo —una cesada sin jornadas dentro del rango— tiene su fila pagada en
-- una versión ANTERIOR. Tomar el `max(version)` del periodo la haría
-- desaparecer de la boleta.
--
--   personas_que_perderia_el_max_del_periodo > 0
--     → confirmado: hay que tomar la última versión DE CADA PERSONA, no la del
--       periodo. La migración se escribe así de todas formas, por lo que dice
--       fn_liquidacion; este número solo dice si hoy ya muerde.
-- ############################################################################

select
  (select md5(p.prosrc)
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_proyeccion_periodo')      as md5_tal_cual,

  (select md5(array_to_string(array(
            select regexp_replace(l, '[[:space:]]*--.*$', '')
              from unnest(string_to_array(p.prosrc, chr(10))) as l
             where btrim(l) not like '--%'
          ), chr(10)))
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_proyeccion_periodo')      as md5_sin_comentarios,

  (select length(p.prosrc)
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_proyeccion_periodo')      as caracteres,

  (select count(*) from periodos_planilla where estado = 'pagado')           as periodos_pagados,

  (select count(*) from periodos_planilla pp
    where pp.estado = 'pagado'
      and exists (select 1 from planilla_pagada_detalle d
                   where d.periodo_id = pp.id))                              as pagados_con_foto,

  (select count(*) from periodos_planilla pp
    where pp.estado = 'pagado'
      and not exists (select 1 from planilla_pagada_detalle d
                       where d.periodo_id = pp.id))                          as pagados_sin_foto,

  (select count(*) from planilla_pagada_detalle)                             as filas_congeladas,

  -- Cuántas personas se perderían si se tomara el max(version) del PERIODO en
  -- vez de la última de cada persona.
  (select count(*)
     from (select d.periodo_id, d.persona_id, max(d.version) as suya
             from planilla_pagada_detalle d group by 1, 2) x
     join (select periodo_id, max(version) as del_periodo
             from planilla_pagada_detalle group by 1) m
       on m.periodo_id = x.periodo_id
    where x.suya < m.del_periodo)                    as personas_que_perderia_el_max_del_periodo;
