-- ############################################################################
-- ####  SOLO LEE. Devuelve UNA fila. Instantáneo. ES LA ÚLTIMA.            ####
-- ############################################################################
--
-- quien_perdio_el_candado_de_pagado.sql
--
-- QUÉ PREGUNTA, EN UNA LÍNEA
--   ¿Qué funciones de producción dejan cambiar algo dentro de un periodo de
--   planilla YA PAGADO?
--
-- POR QUÉ SE PREGUNTA. El repositorio pone el mismo bloque de guarda —289
-- caracteres— dentro de 19 funciones. Dice, en cristiano: «esta fecha cae en un
-- periodo que ya se pagó; cambiarla alteraría una planilla pagada; reabre el
-- periodo primero».
--
--   Sin ese bloque, cambiar un feriado, un turno, un horario o un descanso de
--   una fecha ya pagada NO da error. La jornada se recalcula, las horas del
--   mes cambian, y la planilla que se pagó el mes pasado deja de cuadrar con
--   lo que el sistema dice hoy. Nadie ve un error: simplemente el pasado deja
--   de coincidir consigo mismo.
--
-- POR QUÉ SE SOSPECHA QUE FALTA. Al comparar los tamaños, seis funciones de
-- producción son más cortas que las del repositorio en 289, 289, 280, 277, 276
-- y 272 caracteres — el bloque de guarda, con el texto propio de cada una.
-- Encaja demasiado bien para ser casualidad, pero un tamaño es un indicio, no
-- una prueba. Esto lo convierte en prueba: pregunta por el texto.
--
-- CÓMO SE LEE
--   `con_candado`   las que sí lo tienen. En el repositorio son 19.
--   `SIN_CANDADO`   las que deberían tenerlo y no lo tienen. Aquí está la
--                   respuesta: si sale vacío, la sospecha era falsa y el tema
--                   se cierra.
-- ############################################################################

with deberian(firma) as (
  -- Las 19 del repositorio, hoy. No es una lista de sospechosas: es la lista
  -- completa de lo que el repositorio protege, para que la comparación diga
  -- también si a producción le sobra alguna.
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
  select p.proname || '/' || p.pronargs as firma,
         (p.prosrc like '%periodo ya PAGADO%') as tiene
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
)
select
  coalesce((select string_agg(a.firma, ' ' order by a.firma)
              from aqui a where a.tiene), 'ninguna') as con_candado,

  coalesce((select string_agg(d.firma, ' ' order by d.firma)
              from deberian d
              left join aqui a on a.firma = d.firma
             where coalesce(a.tiene, false) is false), 'ninguna — todo en orden')
    as sin_candado,

  (select count(*) from aqui a where a.tiene) as cuantas_lo_tienen;
