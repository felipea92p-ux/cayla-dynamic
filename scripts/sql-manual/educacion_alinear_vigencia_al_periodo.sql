-- ============================================================================
-- educacion_alinear_vigencia_al_periodo.sql
-- ============================================================================
-- El parche de datos del 2026-08-12: adelantar `vigente_desde` al primer día del
-- periodo abierto, para las asignaciones que empiezan después de que el periodo
-- ya arrancó. Con la regla vieja («vigente al iniciar»), esas asignaciones
-- pagaban S/0 sin que la boleta lo dijera.
--
-- ⚠️ ESTO NO HACE FALTA SI YA SE PEGÓ LA 0233.
--   La 0233 arregla la REGLA: paga por el día de referencia, así que una
--   asignación que empieza el 1 ya cobra el periodo que abrió el 29. Este script
--   es la otra salida — la de tocar el dato en vez de la regla— y solo tiene
--   sentido si se decide NO aplicar la 0233. Correr los dos no rompe nada, pero
--   el segundo no cambia ningún monto.
--
-- LO QUE CUESTA, Y POR ESO NO ES LA VÍA RECOMENDADA
--   1 · Miente sobre el dato. `vigente_desde` dice cuándo empezó el ciclo, y la
--       pantalla lo muestra. Ponerle el 29 de julio a una matrícula del 1 de
--       agosto deja escrito un hecho falso para que un filtro pase.
--   2 · Hay que acordarse cada mes. El mes que a alguien se le pase, esa persona
--       vuelve a cobrar S/0 y la boleta lo va a seguir escondiendo.
--   3 · Puede chocar con el candado del techo (0149). Si la persona tenía un
--       ciclo anterior que terminó dentro de esos días, adelantar la fecha crea
--       un solape que antes no existía y la suma de los dos puede pasarse del
--       techo del rango. El UPDATE fallaría con el mensaje de la 0149 — no es un
--       error del script, es el candado haciendo su trabajo. Ahí toca decidir a
--       mano, o pegar la 0233 y olvidarse.
--
-- CÓMO SE REVIERTE
--   No hay vuelta atrás automática: el valor viejo no se guarda en ningún lado.
--   Por eso el paso 1 IMPRIME lo que va a cambiar. Guardar esa salida antes de
--   correr el paso 2.
-- ============================================================================

-- ── 1 · Qué se va a tocar. Correr esto SOLO, mirar, y recién después el paso 2.
select p.nombres || ' ' || p.apellidos as persona,
       ae.institucion,
       ae.monto,
       ae.vigente_desde  as tiene,
       per.fecha_ini     as pasaria_a_tener,
       ae.vigente_hasta,
       (ae.comprobante_url is not null) as con_papel
  from asignaciones_educacion ae
  join personas p on p.id = ae.persona_id
  join periodos_planilla per
    on per.estado = 'abierto'
   and ae.vigente_desde >  per.fecha_ini      -- empieza con el periodo ya abierto
   and ae.vigente_desde <= per.fecha_fin      -- pero dentro de él
   and ae.vigente_hasta >= per.fecha_ini
 order by p.apellidos, ae.institucion;


-- ── 2 · El cambio. Descomentar para correr.
-- begin;
--
-- update asignaciones_educacion ae
--    set vigente_desde = per.fecha_ini
--   from periodos_planilla per
--  where per.estado = 'abierto'
--    and ae.vigente_desde >  per.fecha_ini
--    and ae.vigente_desde <= per.fecha_fin
--    and ae.vigente_hasta >= per.fecha_ini;
--
-- -- Comprobar acá que el número de filas es el que imprimió el paso 1.
-- -- Si cuadra: commit. Si no: rollback y mirar qué pasó.
-- commit;
