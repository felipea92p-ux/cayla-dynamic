import { createTerminalSupabaseClient } from "@cayla-dynamic/database";
import { obtenerDescartadas, eliminarDeOutbox, type OutboxEntry } from "./offline-db";

/**
 * SUBIR LAS MARCAS APARTADAS, Y BORRAR LAS QUE YA SE RESOLVIERON.
 *
 * PROMETE: que una marca apartada deje de existir solo en este navegador, y que
 *   el aviso rojo del terminal baje cuando alguien la resolvió desde el panel.
 *   Devuelve cuántas quedan apartadas después de sincronizar. Nunca lanza.
 * ASUME: hay red. Sin red no hace nada y lo apartado sigue apartado — que es
 *   exactamente lo que debe pasar.
 * NO HACE: no registra marcajes. Reponer una marca es una decisión de una
 *   persona, con motivo, desde Correcciones.
 *
 * ── POR QUÉ EXISTE ──────────────────────────────────────────────────────────
 * La cola aparta una marca tras seis fallos en vez de borrarla —«una marca que
 * una persona hizo de verdad jamás se destruye»— y hasta la 0304 ese era el
 * final del camino: la marca quedaba en el IndexedDB de esta Mac mini, el aviso
 * decía «avisa a tu encargada» y la encargada no tenía dónde mirar. Las dos del
 * 13-ago llevaban doce días ahí.
 *
 * Un aviso rojo permanente en la pantalla que mira todo el equipo deja de leerse
 * en tres días. Que baje solo cuando el problema se resolvió es lo que lo
 * mantiene siendo un aviso.
 */
export async function sincronizarApartadas(): Promise<number> {
  let apartadas: OutboxEntry[] = [];
  try {
    apartadas = await obtenerDescartadas();
  } catch {
    return 0;
  }
  if (apartadas.length === 0) return 0;

  if (typeof navigator !== "undefined" && !navigator.onLine) return apartadas.length;

  const cliente = createTerminalSupabaseClient();

  // 1 · Reportarlas. Es idempotente por `clientUuid`, así que se hace en cada
  //     pasada sin llevar la cuenta de cuáles ya subieron: una marca que se
  //     subió y se perdió por un error de red volvería a intentarlo sola.
  for (const e of apartadas) {
    try {
      await cliente.rpc("fn_marca_apartada_reportar", {
        p_client_uuid: e.clientUuid,
        p_persona_id: e.personaId,
        p_tipo: e.tipo,
        p_timestamp_cliente: e.timestampCliente,
        p_terminal_id: e.terminalId,
        p_ultimo_error: e.ultimoError ?? null,
        p_motivo_otro: e.motivoOtro ?? null,
      });
    } catch {
      // Sin red o servidor caído: se reintenta en la próxima pasada.
    }
  }

  // 2 · Preguntar cuáles ya se resolvieron —o entraron por su cuenta— y sacarlas
  //     de la cola. Esta es la ÚNICA forma de que el aviso baje.
  try {
    const { data, error } = await cliente.rpc("fn_marcas_apartadas_resueltas", {
      p_client_uuids: apartadas.map((e) => e.clientUuid),
    });
    if (error || !data) return apartadas.length;

    const resueltas = new Set(data as unknown as string[]);
    for (const uuid of resueltas) await eliminarDeOutbox(uuid);
    return apartadas.length - resueltas.size;
  } catch {
    return apartadas.length;
  }
}
