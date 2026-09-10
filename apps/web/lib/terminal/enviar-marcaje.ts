import type { createTerminalSupabaseClient } from "@cayla-dynamic/database";
import type { OutboxEntry } from "./offline-db";
import { SEGUNDOS_ESPERA_RED } from "./tope-de-red";

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
  try {
    const { error } = await cliente
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
      .abortSignal(AbortSignal.timeout(msEspera));

    return error
      ? { ok: false, error: error.message, llego: true }
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
