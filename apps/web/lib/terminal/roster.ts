import { createTerminalSupabaseClient } from "@cayla-dynamic/database";
import { guardarRoster, obtenerRoster, type RosterEntry } from "./offline-db";

/** RLS ya acota el resultado a la sede del terminal autenticado (ver personas_select_terminal_roster). */
export async function cargarRoster(): Promise<RosterEntry[]> {
  if (typeof navigator !== "undefined" && !navigator.onLine) {
    return obtenerRoster();
  }

  const supabase = createTerminalSupabaseClient();
  const { data, error } = await supabase
    .from("personas")
    .select("id, nombres, apellidos, pin_hash, sedes:sede_base_id(codigo, nombre)")
    .order("nombres");

  if (error || !data) {
    return obtenerRoster();
  }

  const roster: RosterEntry[] = data.map((p: any) => {
    const sede = Array.isArray(p.sedes) ? p.sedes[0] : p.sedes;
    return {
      id: p.id,
      nombres: p.nombres,
      apellidos: p.apellidos,
      pinHash: p.pin_hash,
      sedeCodigo: sede?.codigo ?? "?",
      sedeNombre: sede?.nombre ?? "?",
    };
  });
  await guardarRoster(roster);
  return roster;
}
