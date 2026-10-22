// ============================================================================
// pago-adelantado.ts — cuándo marcar «pagado» es pagar un periodo que todavía no terminó
// ============================================================================
// QUÉ PROMETE   · `diasQueFaltanParaTerminar(fecha_fin, hoy)` dice cuántos días faltan para el cierre del periodo,
//                 contando desde mañana: 7 si hoy es 21 y el periodo cierra el 28. Da 0 cuando el periodo ya cerró
//                 y también el MISMO día del cierre —ver «QUÉ NO HACE»—.
//                 `confirmaPagoAdelantado(texto)` dice si lo escrito en el campo es la palabra que se exige.
// QUÉ ASUME     · que `hoy` viene de `hoyLima()` (packages/shared): aquí no se calcula, a propósito. Con `new Date()` a
//                 secas, desde las 7 pm de Lima ya es el día siguiente en UTC y el conteo se adelantaría un día.
// QUÉ NO HACE   · no bloquea nada. Felipe lo decidió el 2026-10-22: a veces el pago adelantado es una excepción legítima
//                 (una liquidación, un practicante que se va), así que la pantalla pide una confirmación fuerte y la
//                 decisión sigue siendo de la persona. Tampoco consulta la base: el candado real es de `fn_periodo_pagado`.
//               · no avisa el día del cierre (`fecha_fin` == hoy), porque la regla pedida es «fecha_fin posterior a hoy».
//                 Ese día el grupo todavía puede marcar hasta la salida, y pagar a media jornada sellaría esas marcas igual.
//                 Si se quiere cubrir, el cambio es una línea (`>=` en vez de `>`), pero es decisión de Felipe.
//
// POR QUÉ EXISTE · el 2026-10-21 (15:27, Lima) se marcó «pagado» el grupo planilla del periodo 28-sep → 28-oct, siete días
//                 antes de terminar. Desde ese instante cada marca nueva de esas personas entró sellada y sus jornadas
//                 no se recalcularon. El clic era el mismo que el de un periodo terminado y la pantalla no avisaba nada.
//                 La base lo permite a propósito, así que el freno vive en la pantalla.
// ============================================================================
import { diasEntre } from "./formato";

/**
 * La palabra que se escribe para confirmar. No es el mes (la de «Eliminar periodo»): son dos decisiones distintas y
 * una misma palabra, escrita de memoria en la una, se escribiría igual en la otra.
 */
export const PALABRA_PAGO_ADELANTADO = "adelantar";

/** Días que faltan para el cierre, desde mañana. 0 si `fecha_fin` es hoy o ya pasó. */
export function diasQueFaltanParaTerminar(fechaFin: string, hoy: string): number {
  if (fechaFin <= hoy) return 0;
  // `diasEntre` cuenta los dos extremos; hoy no es un día que «falte».
  return diasEntre(hoy, fechaFin) - 1;
}

/** «Falta 1 día» / «Faltan 7 días». */
export function textoDiasQueFaltan(dias: number): string {
  return dias === 1 ? "Falta 1 día" : `Faltan ${dias} días`;
}

/** Sin distinguir mayúsculas ni espacios de los lados, igual que la palabra de «Eliminar periodo». */
export function confirmaPagoAdelantado(texto: string): boolean {
  return texto.trim().toLowerCase() === PALABRA_PAGO_ADELANTADO;
}
