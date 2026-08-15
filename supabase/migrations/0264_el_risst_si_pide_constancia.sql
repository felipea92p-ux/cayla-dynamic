-- ============================================================================
-- 0264_el_risst_si_pide_constancia.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que el Reglamento Interno de Seguridad y Salud en el Trabajo quede marcado
--   como documento QUE SÍ PIDE CONSTANCIA, y no como uno de consulta.
--
-- QUÉ ASUME
--   Que existe la fila con ese nombre en `documentos_tipos` — se creó desde la
--   pantalla el 2026-08-15 — y que TODAVÍA NO hay ninguna versión publicada de
--   ese tipo. Si la hubiera, ver abajo «qué pasa con lo ya publicado».
--
-- ── POR QUÉ HACE FALTA ──────────────────────────────────────────────────────
--
-- El tipo se creó con `requiere_acuse = false` por un descuido de un clic: la
-- casilla viene marcada y se desmarcó de más. Nadie lo habría notado hasta el
-- día de la inspección, porque un documento sin acuse no falla, no avisa y no
-- aparece en ninguna lista de pendientes: sencillamente no se le pide la
-- constancia a nadie. **Falla en silencio, que es la única forma en que esto
-- puede fallar.**
--
-- Y para este documento la constancia no es una preferencia. El art. 74 del
-- D.S. 005-2012-TR obliga al empleador a entregar el RISST a cada trabajador,
-- igual que el D.S. 039-91-TR obliga con el RIT. Publicarlo «para consulta»
-- sería tener el documento y no tener la prueba de haberlo entregado — que es
-- exactamente lo que esta pantalla existe para evitar (ver la 0208).
--
-- ── POR QUÉ POR NOMBRE Y NO POR CÓDIGO ──────────────────────────────────────
--
-- El código lo deriva la pantalla del nombre y lo CORTA a 40 caracteres, que es
-- lo que admite el `check` de la tabla. «Reglamento Interno de Seguridad y
-- Salud en el Trabajo» tiene 52, así que el código quedó truncado en mitad de
-- una palabra. Escribirlo aquí a mano sería copiar un truncamiento contando
-- caracteres — y equivocarse en uno deja este `update` sin tocar ninguna fila,
-- en silencio y sin error. El nombre es el dato que una persona puede leer y
-- verificar de un vistazo.
--
-- Por eso el `select` de comprobación de abajo NO es decoración: es la única
-- forma de saber que esto hizo algo.
--
-- ── QUÉ PASA CON LO YA PUBLICADO ────────────────────────────────────────────
--
-- Nada, porque no hay nada: el tipo se creó hoy y aún no tiene ninguna versión.
-- Si alguna vez se publicara antes de correr esto, el cambio seguiría siendo
-- correcto — `requiere_acuse` se lee del tipo, no se copia a la versión — y el
-- efecto sería que a todo el equipo le aparecería la constancia pendiente. Que
-- es justo lo que debe pasar.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
--   update documentos_tipos set requiere_acuse = false
--    where nombre = 'Reglamento Interno de Seguridad y Salud en el Trabajo';
--
-- No se revierte «por si acaso»: revertirlo es decidir que el RISST se entrega
-- sin cargo, y esa decisión tiene una norma en contra.
-- ============================================================================

-- Idempotente: correrla dos veces deja la fila igual.
update documentos_tipos
   set requiere_acuse = true
 where nombre = 'Reglamento Interno de Seguridad y Salud en el Trabajo'
   and requiere_acuse is distinct from true;

-- Comprobación. Tiene que devolver UNA fila con `pide_constancia = true`.
-- Si devuelve cero filas, el nombre no coincide —una tilde, un espacio de más—
-- y el `update` de arriba no tocó nada.
select codigo,
       nombre,
       requiere_acuse as pide_constancia
  from documentos_tipos
 where nombre = 'Reglamento Interno de Seguridad y Salud en el Trabajo';
