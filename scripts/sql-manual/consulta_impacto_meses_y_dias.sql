-- ############################################################################
-- ####  SOLO LEE. Pégala en el SQL Editor de producción DESPUÉS de la 0340. ####
-- ############################################################################
--
-- consulta_impacto_meses_y_dias.sql — ¿alguna liquidación ya pagada quedó
-- inflada por el defecto que la 0340 corrigió?
--
-- EL DEFECTO (ver la cabecera de la migración 0340 para el detalle completo).
-- `fn_meses_y_dias` inventaba días de más en un rango corto que no llegaba a
-- completar el mes calendario siguiente. `fn_vacaciones_truncas` ya se
-- protegía del caso "menos de un mes de servicios" (art. 23 D.S. 012-92-TR:
-- devuelve 0 directo), así que quien cesó en su primer mes NUNCA estuvo
-- expuesto por esta vía. El caso real es otro: alguien con CUALQUIER
-- antigüedad que cesó dentro de, aproximadamente, los primeros 35 días
-- después de su último aniversario laboral — ahí el "récord trunco" que se
-- mide desde ese aniversario hasta el cese es el rango corto que disparaba
-- el defecto.
--
-- QUÉ HACE ESTA CONSULTA
--   Por cada liquidación ya congelada (`liquidacion_pagada`, no anulada),
--   recalcula `fn_vacaciones_truncas` con la función YA CORREGIDA (la que
--   deja la 0340) y lo compara contra `monto_vacaciones`, el monto que
--   quedó congelado el día que se pagó. Si difieren, esa liquidación se
--   calculó con la versión vieja y hay que decidir qué hacer con la
--   diferencia — no lo decide esta consulta, solo la mide.
--
-- CÓMO LEER EL RESULTADO
--   Si no devuelve filas: ninguna liquidación pagada quedó del lado corto
--   del defecto. Nada que hacer.
--   Si devuelve filas: `diferencia` es lo que se pagó de más (positivo) o de
--   menos (negativo) en vacaciones truncas respecto de lo que la fórmula
--   correcta dice hoy. `dias_desde_aniversario` explica por qué: cuanto más
--   chico ese número, más cerca estaba del defecto.
--
-- ⚠️ Esto es una RECONSTRUCCIÓN con la función de HOY, no una repetición
-- exacta del cálculo del día que se pagó (los datos de jornadas, sueldo, etc.
-- de ese momento pueden haber cambiado desde entonces por otras razones,
-- ajenas a este defecto). Una diferencia grande que no calza con
-- "cesó cerca de su aniversario" probablemente sea por otro motivo — mirar
-- `dias_desde_aniversario` antes de asumir que es este defecto.
-- ############################################################################

select
  lp.persona,
  lp.fecha_ingreso,
  lp.fecha_cese,
  -- El aniversario que fn_vacaciones_truncas usa por dentro, para ver qué tan
  -- cerca cesó de él. Bajo ~35 días es la zona de riesgo real.
  (lp.fecha_cese - (lp.fecha_ingreso
     + make_interval(years => extract(year from age(lp.fecha_cese, lp.fecha_ingreso))::int))::date
  ) as dias_desde_aniversario,
  lp.monto_vacaciones as pagado_en_su_momento,
  (fn_vacaciones_truncas(lp.persona_id, lp.fecha_cese)->>'monto')::numeric(12,2) as segun_la_formula_corregida,
  round(
    lp.monto_vacaciones - (fn_vacaciones_truncas(lp.persona_id, lp.fecha_cese)->>'monto')::numeric,
  2) as diferencia
from liquidacion_pagada lp
where lp.anulada is not true
  and lp.monto_vacaciones
      <> round((fn_vacaciones_truncas(lp.persona_id, lp.fecha_cese)->>'monto')::numeric, 2)
order by abs(lp.monto_vacaciones - (fn_vacaciones_truncas(lp.persona_id, lp.fecha_cese)->>'monto')::numeric) desc;
