-- ============================================================================
-- huellas_produccion.sql — la huella de cada función de producción
-- ----------------------------------------------------------------------------
-- SOLO LEE. No modifica nada.
--
-- Devuelve la firma y la huella del texto de las funciones que el comparador
-- marcó como distintas. Sirve para responder la pregunta que el comparador NO
-- puede responder: ¿producción está ATRASADA en esa función, o ADELANTADA?
--
-- Cruzando estas huellas contra el índice histórico —el texto de cada función
-- después de cada una de las 101 migraciones— se sabe exactamente en qué punto
-- se quedó cada una. Y si una huella no aparece en ninguna migración, esa
-- versión no existe en el repositorio: se aplicó a mano y hay que recuperarla
-- antes de pisarla.
-- ============================================================================
select p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as firma,
       md5(p.prosrc) as huella,
       length(p.prosrc) as largo
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'fn_agregar_marcaje','fn_agregar_movimiento','fn_anular_marcaje',
    'fn_confirmar_auto_cierre','fn_corregir_marca','fn_corregir_marcaje',
    'fn_crear_periodo','fn_eliminar_marcaje','fn_eliminar_periodo',
    'fn_proyeccion_periodo','fn_proyeccion_planilla','fn_quitar_feriado',
    'fn_quitar_movimiento','fn_quitar_turno','fn_reactivar_marcaje',
    'fn_set_con_hijos','fn_set_descanso','fn_set_feriado',
    'fn_set_horario_semanal','fn_set_meta_cobertura','fn_set_turno',
    'fn_simular_planilla','fn_trg_marcajes_recalcular_jornada','fn_resellar_dia')
order by 1;
