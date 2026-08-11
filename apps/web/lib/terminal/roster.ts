import { createTerminalSupabaseClient } from "@cayla-dynamic/database";
import { guardarRoster, obtenerRoster, type RosterEntry } from "./offline-db";
import { topeDeRed } from "./tope-de-red";

/** RLS ya acota el resultado a la sede del terminal autenticado (ver personas_select_terminal_roster). */
export async function cargarRoster(): Promise<RosterEntry[]> {
  if (typeof navigator !== "undefined" && !navigator.onLine) {
    return obtenerRoster();
  }

  const supabase = createTerminalSupabaseClient();
  // Con tope y dentro de un try, por lo mismo que terminal-info.ts: sin él, una
  // red colgada dejaba esta promesa pendiente para siempre y la caché de abajo
  // —que existe justo para eso— no llegaba a usarse nunca. Y al abortar,
  // postgrest lanza en vez de devolver { error }.
  let data: unknown[] | null = null;
  try {
    const res = await supabase
      .from("personas")
      .select("id, nombres, apellidos, pin_hash, sedes:sede_base_id(codigo, nombre)")
      .abortSignal(topeDeRed())
      .order("nombres");
    if (res.error) return obtenerRoster();
    data = res.data;
  } catch {
    return obtenerRoster();
  }

  if (!data) {
    return obtenerRoster();
  }

  // UNA RESPUESTA VACÍA NO BORRA LA CACHÉ, y esto es un caso real, no teórico:
  // `guardarRoster` empieza por vaciar el almacén, así que un 200 con cero filas
  // dejaba al terminal sin roster también para cuando volviera a estar offline.
  //
  // Y la forma de llegar ahí la fabrica el propio sistema: RLS acota este SELECT
  // a la sede del terminal AUTENTICADO, de modo que desactivar un terminal
  // —exactamente lo que la 0202 obliga a hacer antes de borrar su cuenta— lo deja
  // devolviendo cero filas con un 200 limpio. Nadie va a marcar en un terminal
  // desactivado, pero tampoco tiene por qué perder lo que ya tenía guardado.
  if (data.length === 0) {
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
