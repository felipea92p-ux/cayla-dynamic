import { createTerminalSupabaseClient } from "@cayla-dynamic/database";
import { determinarSiguienteAccion, type MarcajeDelDia, type SiguienteAccion } from "@cayla-dynamic/shared";
import { obtenerPendientes } from "./offline-db";

/** Perú (America/Lima) no tiene horario de verano — offset fijo -05:00 todo el año. */
export function fechaLimaHoy(): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Lima" }).format(new Date());
}

export async function cargarMarcajesHoyPorPersona(): Promise<Map<string, MarcajeDelDia[]>> {
  const mapa = new Map<string, MarcajeDelDia[]>();

  if (typeof navigator !== "undefined" && navigator.onLine) {
    const supabase = createTerminalSupabaseClient();
    const inicioDia = `${fechaLimaHoy()}T00:00:00-05:00`;
    const { data } = await supabase
      .from("marcajes")
      .select("persona_id, tipo, timestamp_marca")
      .gte("timestamp_marca", inicioDia);

    for (const m of data ?? []) {
      const lista = mapa.get(m.persona_id) ?? [];
      lista.push({ tipo: m.tipo, timestamp: m.timestamp_marca });
      mapa.set(m.persona_id, lista);
    }
  }

  // Superpone marcajes locales aún no sincronizados (offline u optimistas recién hechos),
  // pero SOLO los de HOY: una marca vieja atascada de ayer no debe mostrarse como si
  // fuera de hoy (eso confundía el estado del día tras cruzar la medianoche).
  const hoy = fechaLimaHoy();
  const pendientes = await obtenerPendientes();
  for (const p of pendientes) {
    const fechaMarca = new Intl.DateTimeFormat("en-CA", { timeZone: "America/Lima" }).format(
      new Date(p.timestampCliente),
    );
    if (fechaMarca !== hoy) continue;
    const lista = mapa.get(p.personaId) ?? [];
    lista.push({ tipo: p.tipo, timestamp: p.timestampCliente });
    mapa.set(p.personaId, lista);
  }

  return mapa;
}

export function siguienteAccionPara(marcajesHoy: MarcajeDelDia[]): SiguienteAccion {
  return determinarSiguienteAccion(marcajesHoy);
}
