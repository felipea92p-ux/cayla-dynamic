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
   * No es perfecto y conviene saberlo: supabase-js devuelve algunos fallos de
   * red como `error` en vez de lanzarlos, y esos siguen contando. Cubre el caso
   * identificable —el corte por tiempo—, que es el que este módulo introduce.
   */
  llego: boolean;
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

    return resultado.error
      ? { ok: false, error: resultado.error.message, llego: true }
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
