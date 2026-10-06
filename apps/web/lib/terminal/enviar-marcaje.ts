import type { createTerminalSupabaseClient } from "@cayla-dynamic/database";
import type { OutboxEntry } from "./offline-db";
import { SEGUNDOS_ESPERA_RED, conTope } from "./tope-de-red";

type ClienteTerminal = ReturnType<typeof createTerminalSupabaseClient>;

/**
 * Tope de espera de un envío de marcaje.
 *
 * POR QUÉ EXISTE. Hasta el 2026-08-10 no había ninguno: ni un `AbortSignal` en
 * todo el terminal. Con `navigator.onLine` en true y la red colgada —el caso
 * corriente de un router que responde pero no enruta— la promesa del envío no
 * resolvía nunca, y eso costaba dos cosas a la vez:
 *
 *   · la marca no llegaba a la cola, porque se encolaba DESPUÉS de intentar
 *     enviarla, dentro del `if (error)` que nunca se ejecutaba; y
 *   · `confirmandoRef` no se liberaba —eso pasa en `volverALista()`, al que se
 *     llega por el temporizador de la pantalla de mensaje—, así que el terminal
 *     entero dejaba de aceptar marcajes hasta que alguien recargara la página.
 *
 * Ocho segundos: de sobra para una conexión lenta que funciona, poco para que
 * una persona se quede mirando una pantalla que no avanza. Pasado el tope la
 * marca ya está guardada en la cola y se sincroniza sola.
 *
 * Y EL `.abortSignal()` SOLO CUBRE LA MITAD, descubierto el 2026-09-17 con el
 * terminal congelado en "Confirmando en 0s…" sin llegar nunca a la pantalla
 * de "Listo" ni a la de rechazo. supabase-js resuelve el token de acceso ANTES
 * de invocar `fetch` — `fetchWithAuth` hace `await getAccessToken()` y recién
 * con ese valor arma la petición con el `signal` puesto—, y esa espera del
 * token pasa por `auth.getSession()`, que si el access token está por vencer
 * sale a refrescarlo por red. Ese refresco no lleva NINGÚN `AbortSignal`: es
 * el mismo modo de falla que `tope-de-red.ts` ya documentó para `getSession()`
 * en el arranque, pero ahí seguía sin cubrirse en el camino de marcar. Con la
 * red del mismo tipo que describe ese archivo —responde pero no enruta— el
 * refresco se queda esperando una respuesta que no llega, y NUESTRO tope de
 * 8 s nunca se entera porque corre más abajo, en un `fetch` al que la
 * ejecución ni siquiera había llegado. `conTope` es el segundo cerrojo: no
 * cancela el refresco atascado —eso sigue vivo, igual que en `arrancar()`—
 * pero garantiza que ESTA llamada, la que el terminal está esperando para
 * soltar `confirmandoRef` y salir de la pantalla de confirmación, no se quede
 * esperando más que estos mismos 8 s.
 */
export const SEGUNDOS_ESPERA_ENVIO = SEGUNDOS_ESPERA_RED;

export interface ResultadoEnvio {
  ok: boolean;
  error?: string;
  /**
   * ¿Contestó el servidor? Distingue «lo rechazó» de «no llegué a preguntarle»,
   * y esa diferencia decide si una marca se aparta.
   *
   * La cola deja de reintentar tras seis fallos. Eso está bien para un rechazo
   * —el servidor ya dijo que no y volverá a decirlo—, y está mal para un corte
   * de red: seis ticks son minuto y medio, así que una caída corta de internet
   * apartaría marcas reales. Aquí `llego: false` significa que no hubo
   * respuesta, y esos intentos no cuentan para el tope.
   *
   * supabase-js devuelve los fallos de red como `error` en vez de lanzarlos, así
   * que además del corte por tiempo `esFalloDeRed` reconoce esos textos. Hasta
   * el 2026-10-06 no lo hacía y contaban como respuesta del servidor: seis
   * ticks de «TypeError: Load failed» —minuto y medio sin internet en la sede—
   * apartaban la marca.
   */
  llego: boolean;
}

/**
 * ¿Este «error» es en realidad que la petición no llegó al servidor?
 *
 * postgrest-js no lanza cuando `fetch` falla: arma el error con
 * `${nombre}: ${mensaje}` de la excepción. Lo que se ve según el navegador:
 *   · «TypeError: Load failed»                           Safari (las Mac mini)
 *   · «TypeError: Failed to fetch»                       Chrome
 *   · «TypeError: NetworkError when attempting to fetch» Firefox
 *   · «TimeoutError: signal timed out»                   nuestro `AbortSignal.timeout`
 *   · «AbortError: …» / «FetchError: …»                  corte a mitad de envío
 * Medido en producción el 2026-10-06: las seis marcas de almuerzo de Oficina
 * TRU (tres personas, salida y regreso) se apartaron con «TypeError: Load
 * failed», y las cinco de TRU del 24-sep con «TimeoutError: signal timed out».
 *
 * Los rechazos de la base nunca empiezan así: son texto en español de
 * `fn_registrar_marcaje` o mensajes de Postgres/PostgREST.
 */
export function esFalloDeRed(error: string | undefined): boolean {
  if (!error) return false;
  return /^(TypeError|FetchError|AbortError|TimeoutError): /.test(error);
}

/**
 * ¿Este rechazo es del ESTADO (nunca va a tener éxito reintentando) o es algo
 * que un reintento sí puede resolver?
 *
 * `fn_registrar_marcaje` (supabase/migrations) lanza `tipo % no válido…` en
 * sus dos guardas de la máquina de estados — "se esperaba %" y "la jornada ya
 * está cerrada…" — cuando la marca que llegó no es la que le tocaba a esa
 * persona ahora mismo. Reintentar ESA marca, tal cual, seis veces no cambia
 * nada: el servidor va a decir que no las seis veces, porque la pregunta no
 * cambió. Es distinto de un corte de red, un tiempo de espera agotado o un
 * error transitorio del servidor, donde el mismo intento sí puede tener éxito
 * la segunda vez.
 *
 * Acoplado al texto exacto en español que escribe esa función — la misma
 * clase de acoplamiento que `attendance-state-machine.ts` ya declara con la
 * base de datos ("Debe reflejar exactamente la lógica de fn_registrar_marcaje
 * en Postgres… cualquier cambio aquí debe replicarse allá"). Si el día de
 * mañana se agrega un `raise exception` nuevo de este mismo tipo y no se
 * añade aquí, no se rompe nada — ese rechazo vuelve a tratarse como si fuera
 * de red: sigue los 6 reintentos de siempre, solo tarda más en apartarse.
 */
export function esRechazoDeEstado(error: string | undefined): boolean {
  if (!error) return false;
  return error.includes("no válido");
}

/**
 * ¿La base rechazó la marca porque la SESIÓN de este navegador no es la del
 * terminal que la marca declara? (`fn_registrar_marcaje`: «el terminal
 * autenticado no coincide con p_terminal_id».)
 *
 * No es un rechazo de la marca: es un desajuste de ESTA Mac —su sesión y la
 * ficha de terminal guardada en el navegador dicen cosas distintas—, y se
 * resuelve solo cuando alguien la vuelve a vincular. Medido en producción el
 * 2026-10-03: 110 marcas apartadas por esto (89 solo de TRU, desde julio), todas
 * de personas que sí marcaron. Por eso la cola NO las aparta: las deja en cola
 * y las sube sola cuando la sesión vuelve a ser la del terminal.
 */
export function esRechazoDeSesion(error: string | undefined): boolean {
  if (!error) return false;
  return error.includes("no coincide con p_terminal_id") || esSesionPerdida(error);
}

/**
 * ¿La Mac llamó a la base SIN SESIÓN? Postgres lo dice así:
 * «permission denied for function fn_registrar_marcaje».
 *
 * `fn_registrar_marcaje` solo le da EXECUTE a `authenticated` (migraciones 0353
 * y 0366 le quitan `public` y `anon`). Cuando la sesión de la Mac se pierde —el
 * refresh token fue rechazado y auth-js borró las credenciales— supabase-js
 * sigue enviando la llamada, ahora con la llave anónima, y ese es el texto que
 * vuelve. Medido en producción el 2026-10-06: `has_function_privilege` daba
 * authenticated = true y anon = false, o sea que el permiso estaba bien y lo
 * que faltaba era la sesión. Había 20 marcas apartadas así desde el 12-ago
 * (AQP, TRU, Oficina TRU), la última ese mismo día en Oficina TRU, a las 13:23.
 *
 * Es el mismo caso que «no coincide con p_terminal_id» con otro texto: la marca
 * está bien y el que está mal es el vínculo de ESTA Mac. Por eso `esRechazoDeSesion`
 * lo incluye —la cola la deja esperando en vez de apartarla— y por eso hay una
 * franja fija en pantalla (marcar/page.tsx) para que alguien vuelva a vincularla.
 *
 * Si algún día una migración le quita el permiso a `authenticated` por error, el
 * síntoma sería este mismo texto: las marcas esperarían en cola —ninguna se
 * pierde— y la franja avisaría; el diagnóstico, a la vista, es `has_function_privilege`.
 */
export function esSesionPerdida(error: string | undefined): boolean {
  if (!error) return false;
  return error.includes("permission denied for function fn_registrar_marcaje");
}

/**
 * Manda una marca al servidor con tope de tiempo. NUNCA lanza: quien la llama
 * decide qué hacer con la cola, y una excepción escapada aquí volvería a dejar
 * el terminal colgado, que es justo lo que esto vino a arreglar.
 *
 * Es la única forma de llamar a `fn_registrar_marcaje` desde el terminal. Antes
 * estaba escrita dos veces —en el tap y en la cola— con los mismos siete
 * argumentos; la segunda copia es la que se queda vieja.
 */
export async function enviarMarcaje(
  cliente: ClienteTerminal,
  entry: OutboxEntry,
  msEspera: number = SEGUNDOS_ESPERA_ENVIO * 1000,
): Promise<ResultadoEnvio> {
  const SIN_RESPUESTA = Symbol("sin respuesta");
  try {
    // `conTope` es el segundo cerrojo, no un reemplazo del `.abortSignal()`
    // de abajo — ver el porqué en el comentario de `SEGUNDOS_ESPERA_ENVIO`.
    // El `.abortSignal()` sigue puesto porque, cuando SÍ se llega a hacer el
    // `fetch`, cancelarlo de verdad libera la conexión antes; `conTope` es la
    // red de seguridad para cuando ni siquiera se llega a intentarlo, porque
    // la espera está atascada un paso antes, resolviendo el token.
    const resultado = await conTope(
      cliente
        .rpc("fn_registrar_marcaje", {
          p_persona_id: entry.personaId,
          p_tipo: entry.tipo,
          p_timestamp_cliente: entry.timestampCliente,
          p_client_uuid: entry.clientUuid,
          p_origen: "terminal",
          p_terminal_id: entry.terminalId,
          p_motivo_otro: entry.motivoOtro,
          p_confirmo_sin_refrigerio: entry.confirmoSinRefrigerio,
        })
        .abortSignal(AbortSignal.timeout(msEspera)),
      SIN_RESPUESTA,
      msEspera / 1000,
    );

    if (resultado === SIN_RESPUESTA) {
      return { ok: false, error: "el envío no obtuvo respuesta a tiempo", llego: false };
    }

    // `llego` solo es true si el servidor CONTESTÓ. postgrest-js no lanza cuando
    // el fetch falla: lo devuelve como `error` con el texto «TypeError: Load
    // failed» (Safari), y sin esta comprobación se tomaba por un rechazo.
    return resultado.error
      ? { ok: false, error: resultado.error.message, llego: !esFalloDeRed(resultado.error.message) }
      : { ok: true, llego: true };
  } catch (e) {
    // Aquí cae el corte por tiempo, y también una red que se va a mitad de
    // envío. Los dos son lo mismo para quien llama: no llegó, sigue en la cola.
    return {
      ok: false,
      error: e instanceof Error ? e.message : "el envío se interrumpió",
      llego: false,
    };
  }
}
