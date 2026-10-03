import { createTerminalSupabaseClient } from "@cayla-dynamic/database";
import { enviarMarcaje, esRechazoDeEstado, esRechazoDeSesion } from "./enviar-marcaje";
import { refrescarInfoTerminal } from "./terminal-info";
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
      // Con tope de tiempo, y no es un detalle de cortesía: `sincronizando` se
      // libera en el `finally` de abajo, al que no se llega si un envío se
      // cuelga dentro del bucle. Sin tope, un solo envío colgado dejaba la cola
      // ENTERA parada para siempre — cada tick posterior salía por la primera
      // línea creyendo que ya había una sincronización en marcha.
      let { ok, error, llego } = await enviarMarcaje(supabase, entry);

      // Sesión y ficha del terminal desajustadas: se le pregunta a la propia
      // sesión qué terminal es y se reenvía la marca con ESE id. La persona y la
      // hora no cambian; solo la etiqueta de qué terminal la mandó. Si la sesión
      // no es de un terminal de la sede de esa persona, la base lo vuelve a
      // rechazar (0370), así que esto no abre ninguna puerta nueva.
      if (!ok && llego && esRechazoDeSesion(error)) {
        const info = await refrescarInfoTerminal();
        if (info && info.id !== entry.terminalId) {
          ({ ok, error, llego } = await enviarMarcaje(supabase, { ...entry, terminalId: info.id }));
        }
      }

      if (!ok) {
        await registrarIntentoFallido(entry.clientUuid, error ?? "sin detalle");
        // Tras varios intentos se deja de reintentar para no acumular "sin enviar"
        // para siempre — pero la marca NO se borra: se APARTA.
        //
        // Antes aquí había un db.delete() con el razonamiento de que un rechazo
        // repetido "es permanente, no se pierde nada real". Ese razonamiento falló:
        // la causa #1 de rechazo permanente era una marca ATRASADA (mig. 0068), o
        // sea justo una marca real. Se perdía asistencia en silencio, sin rastro.
        // Regla nueva: una marca que una persona hizo de verdad jamás se destruye.
        //
        // Y solo cuenta para el tope lo que el servidor CONTESTÓ. Un envío que no
        // llegó no dice nada sobre la marca: seis ticks son minuto y medio, así
        // que sin esta condición una caída corta de internet apartaría marcas
        // buenas — el mismo error de fondo que el db.delete() de antes.
        //
        // EXCEPTO un rechazo de ESTADO ("tipo % no válido…"): ese no es una
        // marca que "todavía no se pudo enviar", es una marca que el servidor
        // ya evaluó y dijo que no corresponde — reintentarla igual seis veces
        // no cambia la respuesta, solo demora minuto y medio en que alguien se
        // entere. Se aparta en el primer rechazo confirmado.
        //
        // Y tampoco un rechazo de SESIÓN (ver `esRechazoDeSesion`): la marca está
        // bien, el que está mal es el vínculo de esta Mac. Queda en cola hasta
        // que alguien la re-vincule; apartarla obligaba a corregirla a mano.
        if (esRechazoDeSesion(error)) continue;
        if (llego && (esRechazoDeEstado(error) || (entry.intentos ?? 0) + 1 >= 6)) {
          await marcarComoDescartada(entry.clientUuid, error ?? "sin detalle");
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
