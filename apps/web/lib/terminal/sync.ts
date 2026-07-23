import { createTerminalSupabaseClient } from "@cayla-dynamic/database";
import {
  obtenerPendientes,
  eliminarDeOutbox,
  registrarIntentoFallido,
  marcarComoDescartada,
} from "./offline-db";

let sincronizando = false;

export async function sincronizarPendientes() {
  if (sincronizando) return;
  if (typeof navigator !== "undefined" && !navigator.onLine) return;

  sincronizando = true;
  try {
    const pendientes = await obtenerPendientes();
    if (pendientes.length === 0) return;

    const supabase = createTerminalSupabaseClient();
    for (const entry of pendientes) {
      const { error } = await supabase.rpc("fn_registrar_marcaje", {
        p_persona_id: entry.personaId,
        p_tipo: entry.tipo,
        p_timestamp_cliente: entry.timestampCliente,
        p_client_uuid: entry.clientUuid,
        p_origen: "terminal",
        p_terminal_id: entry.terminalId,
        p_motivo_otro: entry.motivoOtro,
      });

      if (error) {
        await registrarIntentoFallido(entry.clientUuid, error.message);
        // Tras varios intentos se deja de reintentar para no acumular "sin enviar"
        // para siempre — pero la marca NO se borra: se APARTA.
        //
        // Antes aquí había un db.delete() con el razonamiento de que un rechazo
        // repetido "es permanente, no se pierde nada real". Ese razonamiento falló:
        // la causa #1 de rechazo permanente era una marca ATRASADA (mig. 0068), o
        // sea justo una marca real. Se perdía asistencia en silencio, sin rastro.
        // Regla nueva: una marca que una persona hizo de verdad jamás se destruye.
        if ((entry.intentos ?? 0) + 1 >= 6) {
          await marcarComoDescartada(entry.clientUuid, error.message);
        }
        continue; // no bloquea el resto de la cola por un fallo puntual
      }
      await eliminarDeOutbox(entry.clientUuid);
    }
  } finally {
    sincronizando = false;
  }
}

/** Devuelve una función de limpieza — llamarla en el cleanup de useEffect. */
export function iniciarSincronizacionPeriodica(intervaloMs = 15_000): () => void {
  if (typeof window === "undefined") return () => {};

  const onOnline = () => void sincronizarPendientes();
  window.addEventListener("online", onOnline);
  const interval = window.setInterval(() => void sincronizarPendientes(), intervaloMs);
  void sincronizarPendientes();

  return () => {
    window.removeEventListener("online", onOnline);
    window.clearInterval(interval);
  };
}
