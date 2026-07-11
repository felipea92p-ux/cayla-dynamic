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
    .select("id, nombres, apellidos, pin_hash")
    .order("nombres");

  if (error || !data) {
    return obtenerRoster();
  }

  const roster: RosterEntry[] = data.map((p: any) => ({
    id: p.id,
    nombres: p.nombres,
    apellidos: p.apellidos,
    pinHash: p.pin_hash,
  }));
  await guardarRoster(roster);
  return roster;
}
