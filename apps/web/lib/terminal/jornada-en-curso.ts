import type { MarcajeDelDia } from "@cayla-dynamic/shared";

/**
 * Qué marcas componen la jornada que esta persona tiene EN CURSO ahora mismo.
 *
 * POR QUÉ EXISTE. El terminal decidía qué ofrecer mirando solo las marcas de
 * HOY. A las 00:30, «hoy» es el día nuevo y está vacío, así que a quien acababa
 * de cerrar tienda le ofrecía «Entrada» — y con eso abría un día fantasma que el
 * auto-cierre remataba en 22 horas. La salida real nunca llegaba a existir (C4).
 *
 * POR QUÉ NO BASTA CON MIRAR AYER Y HOY JUNTOS, que fue lo primero que probé:
 * `determinarSiguienteAccion` responde «cerrado» en cuanto ve un `salida_final`
 * en la lista. Pasarle el día de ayer completo haría que a quien ayer cerró
 * normal y hoy llega a las 08:00 el terminal le dijera «ya registraste tu salida
 * final de hoy». Un error por otro.
 *
 * LA REGLA, y es la del turno, no la del calendario:
 *
 *   · Si ya marcó algo HOY, la jornada en curso es la de hoy. Da igual lo de
 *     ayer: la noche terminó.
 *   · Si no marcó nada hoy y la de AYER se quedó sin salida final, entonces
 *     sigue dentro de esa jornada — cruzó la medianoche.
 *   · En cualquier otro caso no hay jornada en curso, y le toca entrar.
 *
 * Vive aparte y sin tocar red ni React para poder probarla: es una decisión de
 * negocio, y la pantalla solo la consulta.
 */
export function marcasDeLaJornadaEnCurso(
  deAyer: MarcajeDelDia[],
  deHoy: MarcajeDelDia[],
): MarcajeDelDia[] {
  if (deHoy.length > 0) return deHoy;
  if (deAyer.length === 0) return [];

  const ayerSigueAbierta = !deAyer.some((m) => m.tipo === "salida_final");
  return ayerSigueAbierta ? deAyer : [];
}
