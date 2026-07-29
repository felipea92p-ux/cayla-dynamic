-- ============================================================================
-- huellas_produccion.sql — la huella de cada función y de cada candado
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
--
-- Devuelve DOS resultados: las funciones (abajo) y los CANDADOS de la base
-- (más abajo). Ver el encabezado de la segunda consulta para el porqué.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) Funciones
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- 2) Candados: lo que impide que algo se registre (o se pague) dos veces
-- ---------------------------------------------------------------------------
-- Las huellas de arriba solo miran pg_proc. Una función puede estar perfecta y
-- la tabla haber perdido su candado: el código sigue corriendo, nadie ve un
-- error, y el día que alguien escriba por otra puerta el daño ya está hecho.
-- El caso que motivó esto: `periodos_sin_solape` en periodos_planilla. Si ese
-- constraint no está, dos periodos pueden compartir días y esos días se pagan
-- dos veces, sin aviso y sin descuadre visible en ninguna de las dos planillas.
--
-- QUÉ SE LISTA Y POR QUÉ ESE CORTE
--   · constraints de EXCLUSIÓN ('x') — los tres anti-solape del sistema:
--     periodos de planilla, tramos de salario y ausencias.
--   · constraints ÚNICOS ('u') — una jornada por persona y día, un marcaje por
--     client_uuid, un correlativo por documento…
--   · índices ÚNICOS que no respaldan a ningún constraint, que en pg_constraint
--     no aparecen y se perderían si solo mirásemos ahí. `periodos_etiqueta_unica`
--     es uno de ellos: se creó con `create unique index`, no como constraint.
-- Fuera quedan los CHECK y las claves foráneas: validan la forma de una fila,
-- no impiden que la misma cosa entre dos veces, que es el daño que se busca.
--
-- No se filtra por una lista de tablas a mano, a propósito: un candado que
-- falta no puede detectarse si la tabla que lo perdió se nos olvidó anotar.
-- Se barre todo `public` y que el comparador diga qué sobra y qué falta.
--
-- La huella es del texto CANÓNICO que deparsa el propio Postgres
-- (pg_get_constraintdef / pg_get_indexdef), no del texto de la migración: así
-- dos formas distintas de escribir el mismo candado dan la misma huella. A
-- cambio, comparar solo tiene sentido entre bases de la MISMA versión mayor de
-- Postgres (producción y la base de referencia local hoy son PG 17).
select tipo, objeto, md5(definicion) as huella, definicion
from (
  select case con.contype when 'x' then 'exclusion' else 'unico' end as tipo,
         c.relname || '.' || con.conname as objeto,
         pg_get_constraintdef(con.oid) as definicion
  from pg_constraint con
  join pg_class c on c.oid = con.conrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and con.contype in ('x', 'u')

  union all

  -- índices únicos que viven solos: sin constraint detrás que los delate
  select 'indice unico',
         c.relname || '.' || ix.relname,
         pg_get_indexdef(i.indexrelid)
  from pg_index i
  join pg_class c on c.oid = i.indrelid
  join pg_class ix on ix.oid = i.indexrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and i.indisunique
    and not exists (select 1 from pg_constraint k where k.conindid = i.indexrelid)
) t
order by objeto;
