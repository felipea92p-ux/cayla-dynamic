-- ============================================================================
-- Elimina el botón masivo de "sembrar ingresos" (fn_sembrar_ingresos)
-- ----------------------------------------------------------------------------
-- La fecha de ingreso NO es un dato calculable desde las marcas: es una DECISIÓN
-- de negocio ("desde cuándo le corresponden beneficios"). A veces va antes de la
-- primera marca (empleadas de 2025, cuya antigüedad real es anterior al arranque
-- del terminal en 2026) y a veces después (Estefany 13/07 y Judith 01/07, que por
-- decisión no cuentan el feriado del 29-jun aunque marcaron en junio).
--
-- fn_sembrar_ingresos igualaba a TODAS a su primera marca, con dos daños reales:
--   1. Retrocedía la antigüedad de las de 2025 a 2026, borrando CTS/vacaciones/gratis.
--   2. Se saltaba el candado de periodo pagado que sí tiene fn_set_fecha_ingreso (0037).
-- Ningún guard lo salva: el error es tratar una decisión como si fuera un cálculo.
-- La fecha se edita persona por persona; se contrata de una en una. El masivo sobra.
--
-- Se conserva fn_ingresos() (solo LEE las fechas para mostrarlas; no las pisa).
-- Re-ejecutable sin peligro.
-- ============================================================================

drop function if exists fn_sembrar_ingresos();

notify pgrst, 'reload schema';
