-- ############################################################################
-- ####  SOLO LEE. Devuelve UNA fila. Instantáneo.                          ####
-- ############################################################################
--
-- quien_perdio_el_candado_de_pagado.sql
--
-- QUÉ PREGUNTA
--   1. ¿Qué funciones de producción dejan cambiar algo dentro de un periodo de
--      planilla YA PAGADO?
--   2. Y de las seis sospechosas, ¿qué dicen exactamente por dentro?
--
-- POR QUÉ LAS DOS COSAS JUNTAS, Y NO SOLO LA PRIMERA
--   La primera versión de este archivo devolvía un sí/no. Con eso alcanzaba
--   para saber si el candado falta, pero no para arreglarlo sin riesgo: el
--   arreglo consiste en sobrescribir esas funciones con la versión del
--   repositorio, y sobrescribir a ciegas es cómo se pierde código que solo
--   existía en producción. Hoy ya sabemos que eso pasa aquí: hay siete
--   funciones con MÁS código en producción que en el repositorio, y ninguna
--   está en ningún archivo.
--
--   Así que antes de pisar, se mira. Las seis suman 4.300 caracteres: caben.
--
-- QUÉ ES EL CANDADO. Un bloque de 289 caracteres que dice, en cristiano: «esta
-- fecha cae en un periodo que ya se pagó; cambiarla alteraría una planilla
-- pagada; reabre el periodo primero». Sin él, cambiar un feriado, un turno, un
-- horario o un descanso de una fecha ya pagada NO da error: la jornada se
-- recalcula, las horas del mes cambian, y la planilla que se pagó deja de
-- cuadrar con lo que el sistema dice hoy. Sin un solo aviso.
--
-- POR QUÉ SE SOSPECHA. Comparando tamaños, seis funciones de producción son más
-- cortas que las del repositorio en 289, 289, 280, 277, 276 y 272 caracteres —
-- el bloque, con el texto propio de cada una. Encaja demasiado bien para ser
-- casualidad, y un tamaño sigue sin ser una prueba. El texto sí lo es.
--
-- CÓMO SE LEE
--   `sin_candado`   las que deberían tenerlo y no lo tienen. Si sale
--                   «ninguna», la sospecha era falsa y el tema se cierra.
--   `las_seis`      su código completo, para escribir el arreglo sabiendo qué
--                   se sobrescribe.
-- ############################################################################

with deberian(firma) as (
  -- Las 19 que el repositorio protege HOY. No es una lista de sospechosas: es
  -- la lista completa, para que la comparación diga también si sobra alguna.
  select unnest(array[
    'fn_agregar_marcaje/5','fn_anular_marcaje/2','fn_confirmar_auto_cierre/2',
    'fn_corregir_marca/4','fn_corregir_marcaje/3','fn_educacion_cerrar/3',
    'fn_educacion_registrar/11','fn_eliminar_marcaje/2',
    'fn_otorgar_descanso_sustitutorio/5','fn_quitar_descanso_sustitutorio/1',
    'fn_quitar_feriado/1','fn_quitar_turno/2','fn_reabrir_dia/2',
    'fn_reactivar_marcaje/2','fn_set_descanso/2','fn_set_feriado/2',
    'fn_set_horario_semanal/3','fn_set_salario/5','fn_set_turno/4'])
),
aqui as (
  select p.oid,
         p.proname || '/' || p.pronargs as firma,
         (p.prosrc like '%periodo ya PAGADO%') as tiene
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
)
select
  coalesce((select string_agg(d.firma, ' ' order by d.firma)
              from deberian d
              left join aqui a on a.firma = d.firma
             where coalesce(a.tiene, false) is false), 'ninguna — todo en orden')
    as sin_candado,

  (select count(*) from aqui a where a.tiene) as cuantas_lo_tienen,

  -- El código completo de las seis. `pg_get_functiondef` trae también si son
  -- `security definer` y con qué `search_path`, que es parte de lo que puede
  -- diferir y no se ve mirando solo el cuerpo.
  (select string_agg(pg_get_functiondef(a.oid),
                     E'\n\n-- ============================================================\n\n'
                     order by a.firma)
     from aqui a
    where a.firma in ('fn_set_feriado/2','fn_quitar_feriado/1','fn_set_turno/4',
                      'fn_quitar_turno/2','fn_set_horario_semanal/3','fn_set_descanso/2'))
    as las_seis;
