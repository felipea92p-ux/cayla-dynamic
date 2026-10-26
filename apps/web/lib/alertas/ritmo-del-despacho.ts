// EL RITMO DEL DESPACHO — reloj, espera y tope de tiempo de la ruta de correos.
//
// PROMETE: tres cosas pequeñas que la ruta necesita y que las pruebas necesitan
// poder reemplazar: qué hora es (`ahoraMs`), esperar un rato (`esperarMs`) y
// cuánto esperar cuando Resend dice «demasiadas peticiones por segundo»
// (`esperaPorSegundo`).
// ASUME: nada de Next ni de Supabase. Viven en un módulo aparte, y no dentro de
// `route.ts`, porque una ruta de Next solo puede exportar sus métodos HTTP y su
// configuración: lo demás rompe la compilación. Aparte, además, una prueba puede
// sustituir el reloj y la espera sin tocar los de verdad (un lote de 45 s no se
// prueba esperando 45 s).

/**
 * Tope BLANDO del lote, en milisegundos. Pasado este tiempo, la ruta deja de
 * reservar filas nuevas y responde. Es blando a propósito: `maxDuration` (60 s)
 * es el tope duro de Vercel, y si la función muere en él no llega ni el aviso a
 * Sentry ni la respuesta, y deja una fila 'procesando' con el intento gastado
 * (y, si Resend sí aceptó ese correo, un correo doble mañana). 45 s deja 15 s
 * para la fila en vuelo, los avisos y la respuesta.
 */
export const LIMITE_BLANDO_MS = 45_000;

/** La hora de ahora, en milisegundos. Reemplazable en pruebas. */
export function ahoraMs(): number {
  return Date.now();
}

/** Esperar `ms` milisegundos. Reemplazable en pruebas. */
export function esperarMs(ms: number): Promise<void> {
  return new Promise((resolver) => setTimeout(resolver, ms));
}

/**
 * Cuánto esperar antes de reintentar un 429 «por segundo»: lo que diga la
 * cabecera `retry-after` de Resend (en segundos), con un techo de 2 s —la ruta
 * tiene 45 s de presupuesto para todo el lote— y 1 s si la cabecera falta, no es
 * un número (puede venir como fecha HTTP) o es cero o negativa.
 */
export function esperaPorSegundo(retryAfter: string | null | undefined): number {
  const segundos = retryAfter === null || retryAfter === undefined || retryAfter.trim() === "" ? NaN : Number(retryAfter);
  if (!Number.isFinite(segundos) || segundos <= 0) return 1000;
  return Math.min(2000, Math.round(segundos * 1000));
}
