-- ############################################################################
-- ####  PONER EL MONTO DEL SUBSIDIO A UNA LICENCIA POR MATERNIDAD          ####
-- ############################################################################
--
-- CUÁNDO SE USA. Cuando una integrante entra en licencia por maternidad y
-- EsSalud ya dijo cuánto es el subsidio diario. Hasta que el formulario de
-- Ausencias aprenda el campo (migración pendiente sobre `fn_registrar_ausencia`),
-- este es el camino: la licencia se registra en la pantalla como siempre, y el
-- monto se pone acá.
--
-- SIN ESTO LA LICENCIA SE PAGA 0.00. La 0256 no se inventa el monto a propósito:
-- el promedio diario sale de los 12 meses anteriores a la contingencia, y esos
-- meses pueden incluir empleadores anteriores a CAYLA. Calcularlo con lo que hay
-- en esta base daría un número más bajo que el legal con toda la apariencia de
-- estar bien. Por eso lo dice EsSalud y acá solo se multiplica por los días.
--
-- LA PANTALLA YA AVISA si falta: la planilla marca esos días como
-- `dias_maternidad_sin_monto`. Un cero mudo era justo lo que había que evitar.
--
-- QUÉ HAY QUE CAMBIAR ABAJO — las dos líneas de `datos`:
--   · quien   → nombre o apellido, como aparece en la pantalla de personas
--   · diario  → el subsidio DIARIO de EsSalud, no el total del mes
--
-- ES UNA SOLA SENTENCIA, con `returning`, porque el SQL Editor de Supabase solo
-- muestra el resultado de la última — y un `update` mudo seguido de un `select`
-- se lee igual que un update que no hizo nada.
--
-- SI DEVUELVE 0 FILAS: o el nombre no coincide, o esa persona no tiene una
-- licencia de tipo `maternidad` registrada todavía. Regístrala primero en
-- /admin/ausencias.
-- ############################################################################

with datos as (
  select 'APELLIDO_O_NOMBRE'::text as quien,     -- ← cámbialo
         0.00::numeric(12,2)       as diario     -- ← cámbialo (subsidio POR DÍA)
)
update public.ausencias a
   set subsidio_diario = d.diario
  from datos d, public.personas p
 where a.persona_id = p.id
   and a.tipo       = 'maternidad'
   and a.anulada_at is null
   and (p.nombres ilike '%' || d.quien || '%' or p.apellidos ilike '%' || d.quien || '%')
returning p.nombres || ' ' || p.apellidos                       as persona,
          a.fecha_inicio,
          a.fecha_fin,
          (a.fecha_fin - a.fecha_inicio + 1)                    as dias_de_licencia,
          a.subsidio_diario                                     as subsidio_por_dia,
          (a.fecha_fin - a.fecha_inicio + 1) * a.subsidio_diario as total_de_la_licencia,
          case when (a.fecha_fin - a.fecha_inicio + 1) > 98
               then '⚠ pasa de 98 días — solo válido por parto múltiple o hijo con discapacidad'
               else '✓ dentro de los 98 días' end               as revisar;
