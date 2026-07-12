import { createTerminalSupabaseClient } from "@cayla-dynamic/database";
import { obtenerPendientes, eliminarDeOutbox, registrarIntentoFallido } from "./offline-db";

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
        // Una marca que falla repetidamente ESTANDO ONLINE es un rechazo permanente
        // (día ya cerrado, sesión vencida, tipo inválido…), no un corte de red: el
        // sync ni siquiera corre sin conexión. Tras varios intentos se descarta para
        // no acumular "sin enviar" para siempre. Un fallo transitorio se resuelve
        // mucho antes de 6 intentos, así que no se pierde nada real.
        if ((entry.intentos ?? 0) + 1 >= 6) {
          await eliminarDeOutbox(entry.clientUuid);
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
