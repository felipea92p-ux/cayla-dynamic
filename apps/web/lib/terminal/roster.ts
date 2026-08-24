import { createTerminalSupabaseClient } from "@cayla-dynamic/database";
import { guardarRoster, obtenerRoster, type RosterEntry } from "./offline-db";
import { topeDeRed } from "./tope-de-red";

/**
 * Lee de `terminal_roster` (vista, 0285) y NO de `personas`, y esa es la mitad
 * del arreglo que no se ve desde aquí.
 *
 * Mientras esto leía `personas`, pedía cuatro campos con toda la educación —pero
 * el token que viaja en la Mac mini alcanzaba la fila entera, y ahí están el DNI
 * y la remuneración. No era un fallo de la policy: **RLS filtra filas, no
 * columnas**, así que ninguna policy podía arreglarlo. La única forma de que ese
 * token no llegue al sueldo es que la superficie que puede leer no lo tenga.
 *
 * La vista sigue acotando a la sede del terminal exactamente como antes: lleva
 * dentro la misma condición de la 0008, y `fn_sede_actual_terminal()` devuelve
 * null a cualquier sesión que no sea un terminal activo.
 */
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
      .from("terminal_roster")
      .select("id, nombres, apellidos, pin_hash, sede_codigo, sede_nombre")
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
  // Y la forma de llegar ahí la fabrica el propio sistema: la vista acota a la
  // sede del terminal AUTENTICADO, de modo que desactivar un terminal
  // —exactamente lo que la 0202 obliga a hacer antes de borrar su cuenta— lo deja
  // devolviendo cero filas con un 200 limpio. Nadie va a marcar en un terminal
  // desactivado, pero tampoco tiene por qué perder lo que ya tenía guardado.
  if (data.length === 0) {
    return obtenerRoster();
  }

  // La vista trae la sede ya resuelta en dos columnas, así que se acabó el
  // desempaquetado del join anidado que PostgREST devolvía a veces como objeto
  // y a veces como array de uno.
  const roster: RosterEntry[] = data.map((p: any) => ({
    id: p.id,
    nombres: p.nombres,
    apellidos: p.apellidos,
    pinHash: p.pin_hash,
    sedeCodigo: p.sede_codigo ?? "?",
    sedeNombre: p.sede_nombre ?? "?",
  }));
  await guardarRoster(roster);
  return roster;
}
