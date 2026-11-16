-- ============================================================================
-- 0620 · LO QUE PASA DEL MÁXIMO LEGAL SE PUEDE PAGAR AL PRACTICANTE
-- ============================================================================
--
-- QUÉ PROMETE
--   Que el tope semanal del practicante se pueda abrir desde Parámetros, para
--   pagar todo lo marcado como antes del 2026-10-29. Felipe, 2026-11-16: «que
--   se pague lo que pasa del máximo legal … así como antes».
--
--   Los dos parámetros del tope (0577) podían ir hasta el máximo legal: 30 h
--   el preprofesional y 48 h el egresado. Esta migración les sube el máximo a
--   168 h, las horas que tiene una semana. Con el tope en 168 el factor de la
--   planilla nunca baja de 1, porque ninguna semana de lunes a domingo suma
--   más de 168 h: se paga cada hora marcada, a la tarifa de su base. Es el pago
--   «sin tope», al céntimo.
--
--   POR SÍ SOLA NO MUEVE NI UN SOL. Los dos topes siguen valiendo 30 y 48 hasta
--   que la dirección los cambie en /admin/parametros:
--     · «Tope semanal del practicante preprofesional» → 168, rige desde el
--       29/10/2026 (inicio del periodo abierto), con su motivo.
--     · «Tope semanal del practicante egresado»       → 168, misma fecha.
--   La base se niega si esa fecha cae en un periodo ya pagado para el grupo.
--   La comprobación del final dice, antes de ir a la pantalla, si el 29/10 se
--   puede usar.
--
--   Ejemplos con S/ 1 230 en un periodo de 28 días (prueba 505):
--     preprofesional 36 h/sem → 1 476.00   (con tope 30: 1 230.00)
--     egresado       50 h/sem → 1 366.67   (con tope 48: 1 312.00)
--
-- POR QUÉ ASÍ, Y NO REESCRIBIENDO LA PLANILLA
--   · La 0577 ya lee el tope de Parámetros, con el valor que regía al empezar el
--     periodo. Quitar el tope dentro de fn_planilla_calcular_nucleo (2 268
--     líneas) exigiría el md5 de producción y repetir el camino de la 0261 y la
--     0276. Esta migración no reescribe ninguna función.
--   · El cambio queda con autor, motivo y fecha en parametros_historial, y se
--     deshace igual: otro valor desde otra fecha, sin migración.
--   · 168 no es un número inventado: es el techo físico de una semana. Por eso
--     el tope en 168 significa «sin tope» y no «un tope muy alto».
--
-- QUÉ NO CAMBIA
--   · La base (30 h el preprofesional, 45 h el egresado): la hora vale lo mismo.
--   · No hay recargo de sobretiempo. El practicante no está en planilla
--     (`en_planilla` es false) y la 0185 solo lo calcula para quien sí lo está.
--     Lo que pasa del máximo se paga a la tarifa normal, como antes.
--   · El practicante sin modalidad ya no tenía tope y sigue igual.
--   · Los periodos que empiezan antes del 2026-10-29 siguen con la fórmula de
--     antes de la 0573 (0575).
--   · Los parámetros de la BASE siguen con su máximo legal (30 y 48).
--
-- LO QUE NO RESUELVE
--   La Ley 28518 (art. 44) fija 30 h semanales para el preprofesional. Que
--   alguien marque más queda escrito igual en sus marcas: pagarlo no crea ese
--   exceso ni lo arregla. Va a la lista del laboralista, con el feriado del
--   practicante (art. 42.4) y el art. 45.
--
-- QUÉ ASUME
--   · La 0577 pegada: los dos parámetros del tope existen. La guardia se niega
--     sin ellos.
--   · No reescribe ninguna función, así que no hay md5 de partida que declarar.
--
-- CÓMO SE REVIERTE
--   Si ya se cambió el valor: en Parámetros, volver a 30 y 48 desde una fecha
--   posterior. El máximo del catálogo vuelve con
--     update parametros_catalogo set valor_max = 30 where parametro = 'practicante_tope_preprofesional';
--     update parametros_catalogo set valor_max = 48 where parametro = 'practicante_tope_egresado';
--   (las versiones ya guardadas no se tocan: son historia).
-- ============================================================================

-- ── 0 · Guardia ────────────────────────────────────────────────────────────
do $guardia$
begin
  if (select count(*) from parametros_catalogo
       where parametro in ('practicante_tope_preprofesional', 'practicante_tope_egresado')
         and clase = 'plata' and almacen = 'vigencias') <> 2 then
    raise exception 'PARA. Faltan los parámetros del tope del practicante: la 0577 no está pegada. Pégala antes.';
  end if;
end
$guardia$;

-- ── 1 · El máximo pasa a ser el de una semana ─────────────────────────────
update parametros_catalogo
   set valor_max   = 168,
       descripcion = 'Lo marcado por encima de estas horas en una semana (lunes a domingo) no se paga. '
                     || 'En 168 (las horas de una semana) no corta nunca: se paga todo lo marcado, como antes del 29-oct-2026.',
       base        = 'Ley 28518 art. 44 (jornada máxima 30 h). Pagar lo que pasa de ahí: decisión de Felipe 2026-11-16 (0620)'
 where parametro = 'practicante_tope_preprofesional';

update parametros_catalogo
   set valor_max   = 168,
       descripcion = 'Lo marcado por encima de estas horas en una semana (lunes a domingo) no se paga. '
                     || 'En 168 (las horas de una semana) no corta nunca: se paga todo lo marcado, como antes del 29-oct-2026.',
       base        = 'Jornada máxima de 48 h semanales. Pagar lo que pasa de ahí: decisión de Felipe 2026-11-16 (0620)'
 where parametro = 'practicante_tope_egresado';

insert into migraciones_aplicadas (numero, nombre)
values (620, 'lo_que_pasa_del_maximo_legal_se_puede_pagar_al_practicante')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── Comprobación ───────────────────────────────────────────────────────────
-- Debe dar: 168 · 168 · 30 · 48 · 0 · (vacío) · (vacío) · «620 · lo_que_pasa_…»
--   · tope_pre_29oct y tope_egr_29oct: lo que rige hoy en el periodo abierto.
--     Siguen en 30 y 48 hasta que se cambien en Parámetros.
--   · versiones_del_tope = 0 quiere decir que nadie los cambió todavía, así que
--     la pantalla acepta «rige desde el 29/10/2026».
--   · pagado_pre y pagado_egr vacíos quieren decir que ningún periodo que
--     termina desde el 29-oct está pagado para ese grupo. Si muestran una
--     fecha, el 29/10 no se puede usar: hay que elegir el día siguiente a esa.
select
  (select valor_max from parametros_catalogo where parametro = 'practicante_tope_preprofesional') as max_tope_pre,
  (select valor_max from parametros_catalogo where parametro = 'practicante_tope_egresado')       as max_tope_egr,
  fn_parametro_valor_en('practicante_tope_preprofesional', date '2026-10-29')                     as tope_pre_29oct,
  fn_parametro_valor_en('practicante_tope_egresado', date '2026-10-29')                           as tope_egr_29oct,
  (select count(*) from parametros_vigencias
    where parametro in ('practicante_tope_preprofesional', 'practicante_tope_egresado'))         as versiones_del_tope,
  fn_parametro_periodo_pagado_desde('practicante_preprofesional', date '2026-10-29')              as pagado_pre,
  fn_parametro_periodo_pagado_desde('practicante_profesional', date '2026-10-29')                 as pagado_egr,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 620)                as registro;
