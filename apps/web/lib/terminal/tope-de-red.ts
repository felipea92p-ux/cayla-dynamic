/**
 * El tope de espera de CUALQUIER llamada de red del terminal.
 *
 * POR QUÉ EXISTE, Y POR QUÉ NO BASTABA CON PONERLO EN EL ENVÍO
 *
 * El 2026-08-10 se le puso tope al envío de marcajes (`enviar-marcaje.ts`) y se
 * dio el problema por cerrado. No lo estaba: ese era el ÚNICO `AbortSignal` del
 * frontend, y las llamadas del ARRANQUE seguían sin ninguno — justo las que
 * corren antes de que nadie pueda marcar nada.
 *
 * El modo de falla es el mismo de siempre y no es raro: `navigator.onLine` en
 * true con la red muerta, un router que responde pero no enruta, un portal
 * cautivo que completa el saludo TCP y calla. La promesa no resuelve nunca.
 *
 * Y en el arranque eso es peor que perder una marca. El respaldo por caché
 * existe y está escrito exactamente para este caso, pero vive DESPUÉS del
 * `await` que se quedó colgado, así que no se llega. La sede se encuentra un
 * terminal con su reloj, su cabecera y la frase «Nadie en esta sede todavía.»
 * — que no se lee como una avería sino como una configuración correcta, así que
 * nadie llama a la encargada. No se marca ni se encola nada: la cola offline no
 * llega ni a existir, y el turno entero se reconstruye después a mano.
 *
 * OCHO SEGUNDOS. De sobra para una conexión lenta que funciona, poco para que
 * alguien se quede mirando una pantalla que no avanza.
 *
 * Y hay una razón más para que el tope viaje en la señal y no en un `setTimeout`
 * de fuera: postgrest-js reintenta los GET cuatro veces con esperas de 1 s, 2 s
 * y 4 s. Un `.abortSignal()` corta el bucle ENTERO —su `sleep` despierta al
 * abortar—, mientras que envolver la promesa por fuera dejaría los reintentos
 * corriendo debajo.
 */
export const SEGUNDOS_ESPERA_RED = 8;

/**
 * La señal para las consultas de Supabase: `.abortSignal(topeDeRed())`.
 *
 * Ojo al usarla: al abortar, postgrest LANZA en vez de devolver `{ error }`.
 * Toda llamada que la use tiene que ir dentro de un `try`, o el arranque se
 * cambia por una excepción — que es otra forma de dejar la sede sin marcar.
 */
export function topeDeRed(segundos: number = SEGUNDOS_ESPERA_RED): AbortSignal {
  return AbortSignal.timeout(segundos * 1000);
}

/**
 * Para las promesas que NO aceptan una señal de aborto — hoy `auth.getSession()`,
 * que cuando el token guardado está vencido sale a la red a renovarlo sin dar
 * ninguna forma de cancelarlo.
 *
 * Devuelve `respaldo` si se agota el tiempo. La llamada de abajo sigue viva
 * —no hay manera de matarla— pero deja de bloquear a quien esperaba, que es lo
 * único que importa aquí.
 *
 * El respaldo tiene que poder distinguirse de una respuesta real: en el arranque,
 * «no hubo respuesta» y «no hay sesión» llevan a sitios opuestos —seguir con la
 * caché, o mandar a vincular el dispositivo— y confundirlos manda a la sede a
 * una pantalla de vinculación que no necesita.
 */
export async function conTope<T, R>(
  promesa: PromiseLike<T>,
  respaldo: R,
  segundos: number = SEGUNDOS_ESPERA_RED,
): Promise<T | R> {
  let temporizador: ReturnType<typeof setTimeout> | undefined;
  const espera = new Promise<R>((resolver) => {
    temporizador = setTimeout(() => resolver(respaldo), segundos * 1000);
  });
  try {
    return await Promise.race([promesa, espera]);
  } finally {
    // Sin esto, el temporizador mantiene vivo el proceso en las pruebas y retrasa
    // el cierre de la pestaña. Se limpia siempre, gane quien gane la carrera.
    if (temporizador !== undefined) clearTimeout(temporizador);
  }
}
