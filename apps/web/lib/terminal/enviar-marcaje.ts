import type { createTerminalSupabaseClient } from "@cayla-dynamic/database";
import type { OutboxEntry } from "./offline-db";

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
export const SEGUNDOS_ESPERA_ENVIO = 8;

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
