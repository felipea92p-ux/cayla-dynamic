// ============================================================================
// refresco.ts — cuándo el terminal vuelve a preguntarle a la base
// ============================================================================
// El terminal de cada sede refresca su lista cada minuto (`marcar/page.tsx`).
// Medido en producción el 2026-10-30, eso costaba caro por dos razones que esta
// lógica corrige, sin tocar lo que hace falta para marcar:
//
//  1. Cada vuelta volvía a bajar las «sugerencias» (`sugerencias.ts`): 30 días
//     de salidas a refrigerio, TODOS los horarios y los turnos de hoy. Son datos
//     que cambian una vez al día, pedidos 1 440 veces. La lectura de los 30 días
//     era la consulta que más tiempo de base gastaba de todo el proyecto (993 ms
//     de promedio, 12,6 horas desde el 17-oct) y llevó la memoria a «SEVERE».
//     Ahora se piden al arrancar, al cambiar de día y como mucho cada 15 min (un
//     turno de hoy que se cambia en el panel llega igual, solo hasta 15 min tarde).
//
//  2. El terminal de AQP tenía tres pestañas abiertas, ocultas, y las tres
//     preguntaban cada minuto, día y noche: 8 535 lecturas de marcajes en 24 h,
//     el 78 % de todas. Una pestaña oculta ya no refresca por reloj; al volver a
//     verse refresca en el acto (`visibilitychange`), así que quien llega a marcar
//     ve la lista al día igual que antes.
//
// Lo que NO cambia: la cola de marcas sin enviar sigue subiendo con la pestaña
// oculta (`sync.ts`), y la lista y las marcas de hoy siguen refrescándose cada
// minuto mientras el terminal está a la vista.
// ============================================================================

/** Cada cuánto, como mucho, se vuelven a pedir las sugerencias en el mismo día. */
export const VIGENCIA_SUGERENCIAS_MS = 15 * 60 * 1000;

/** La última carga de sugerencias que se pudo usar: de qué día y a qué hora. */
export interface CargaSugerencias {
  dia: string;
  ms: number;
}

/**
 * ¿Hay que volver a pedir las sugerencias? Sí si nunca se cargaron (o la última
 * vino vacía: `null`), si cambió el día en Lima o si ya pasó la vigencia.
 * `ahoraMs` menor que la carga (el reloj de la Mac retrocedió) también cuenta
 * como vencida: mejor una consulta de más que quedarse con datos de quién sabe.
 */
export function sugerenciasVencidas(ultima: CargaSugerencias | null, dia: string, ahoraMs: number): boolean {
  if (!ultima) return true;
  if (ultima.dia !== dia) return true;
  const edad = ahoraMs - ultima.ms;
  return edad < 0 || edad >= VIGENCIA_SUGERENCIAS_MS;
}

/**
 * ¿Toca el refresco por reloj? Solo con red y con la pestaña a la vista.
 * `visibilidad` ausente (un navegador que no la informa) se trata como visible:
 * ante la duda, el terminal sigue refrescando como siempre.
 */
export function refrescoPorRelojPermitido(enLinea: boolean, visibilidad: DocumentVisibilityState | undefined): boolean {
  return enLinea && visibilidad !== "hidden";
}
