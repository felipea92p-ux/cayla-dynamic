// ============================================================================
// pago-adelantado.ts — cuándo marcar «pagado» es pagar un periodo que todavía no terminó
// ============================================================================
// QUÉ PROMETE   · `diasQueFaltanParaTerminar(fecha_fin, hoy)` dice cuántos días faltan para el cierre del periodo,
//                 contando desde mañana: 7 si hoy es 21 y el periodo cierra el 28.
//                   · `null` → el periodo YA terminó (`fecha_fin` es anterior a hoy): pagar es lo normal, no se avisa nada.
//                   · `0`    → HOY es el cierre: el periodo todavía no terminó, el grupo marca hasta la salida.
//                   · `N>0`  → faltan N días.
//                 Son tres respuestas y no un número porque «0 días» y «ya terminó» no son lo mismo: pagar a media jornada
//                 del último día sella las marcas que quedan de ese día igual que pagar siete días antes.
//                 `tituloAvisoPagoAdelantado(dias)` es el encabezado del aviso; `confirmaPagoAdelantado(texto)` dice si lo
//                 escrito en el campo es la palabra que se exige.
// QUÉ ASUME     · que `hoy` viene de `hoyLima()` (packages/shared): aquí no se calcula, a propósito. Con `new Date()` a
//                 secas, desde las 7 pm de Lima ya es el día siguiente en UTC y el conteo se adelantaría un día.
// QUÉ NO HACE   · no bloquea nada. Felipe lo decidió el 2026-10-22: a veces el pago adelantado es una excepción legítima
//                 (una liquidación, un practicante que se va), así que la pantalla pide una confirmación fuerte y la
//                 decisión sigue siendo de la persona. Tampoco consulta la base: el candado real es de `fn_periodo_pagado`.
//
// POR QUÉ EXISTE · el 2026-10-21 (15:27, Lima) se marcó «pagado» el grupo planilla del periodo 28-sep → 28-oct, siete días
//                 antes de terminar. Desde ese instante cada marca nueva de esas personas entró sellada y sus jornadas
//                 no se recalcularon. El clic era el mismo que el de un periodo terminado y la pantalla no avisaba nada.
//                 La base lo permite a propósito, así que el freno vive en la pantalla.
//                 El mismo día del cierre se incluyó el 2026-10-22, también por decisión de Felipe: la regla inicial era
//                 «fecha_fin posterior a hoy» y dejaba sin aviso justo el último día, que sella igual.
// ============================================================================
import { diasEntre } from "./formato";

/**
 * La palabra que se escribe para confirmar. No es el mes (la de «Eliminar periodo»): son dos decisiones distintas y
 * una misma palabra, escrita de memoria en la una, se escribiría igual en la otra.
 */
export const PALABRA_PAGO_ADELANTADO = "adelantar";

/** Días que faltan para el cierre, desde mañana: `0` si hoy es el cierre, `null` si el periodo ya terminó. */
export function diasQueFaltanParaTerminar(fechaFin: string, hoy: string): number | null {
  if (fechaFin < hoy) return null;
  // `diasEntre` cuenta los dos extremos; hoy no es un día que «falte».
  return diasEntre(hoy, fechaFin) - 1;
}

/** «Faltan 7 días para que termine este periodo» / «Falta 1 día…» / «Hoy es el último día de este periodo». */
export function tituloAvisoPagoAdelantado(dias: number): string {
  if (dias === 0) return "Hoy es el último día de este periodo";
  return `${dias === 1 ? "Falta 1 día" : `Faltan ${dias} días`} para que termine este periodo`;
}

/** Sin distinguir mayúsculas ni espacios de los lados, igual que la palabra de «Eliminar periodo». */
export function confirmaPagoAdelantado(texto: string): boolean {
  return texto.trim().toLowerCase() === PALABRA_PAGO_ADELANTADO;
}
