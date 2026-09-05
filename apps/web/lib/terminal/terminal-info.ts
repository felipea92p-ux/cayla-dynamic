import { createTerminalSupabaseClient } from "@cayla-dynamic/database";
import { topeDeRed } from "./tope-de-red";

export interface TerminalInfo {
  id: string;
  sedeCodigo: string;
  sedeNombre: string;
}

const STORAGE_KEY = "cayla-terminal-info";

export function leerInfoTerminalCacheada(): TerminalInfo | null {
  if (typeof window === "undefined") return null;
  const raw = window.localStorage.getItem(STORAGE_KEY);
  return raw ? (JSON.parse(raw) as TerminalInfo) : null;
}

function guardarInfoTerminalCacheada(info: TerminalInfo) {
  window.localStorage.setItem(STORAGE_KEY, JSON.stringify(info));
}

/**
 * Se llama una vez tras vincular el dispositivo, y de nuevo en cada arranque.
 *
 * CON TOPE, y es la llamada donde más importa: es la PRIMERA que el terminal
 * espera al abrirse. Sin tope, una red colgada la dejaba pendiente para siempre
 * y el arranque no llegaba nunca a su propio respaldo por caché —que está tres
 * líneas más abajo, escrito justo para esto—. La sede se quedaba mirando «Nadie
 * en esta sede todavía.», que no parece una avería. Ver `tope-de-red.ts`.
 *
 * Devuelve null si no se pudo: quien llama ya sabe caer a la caché.
 */
export async function refrescarInfoTerminal(): Promise<TerminalInfo | null> {
  const supabase = createTerminalSupabaseClient();
  // El try no es decorativo: al agotarse el tope, postgrest LANZA en vez de
  // devolver { error }. Sin él, cambiaríamos un cuelgue por una excepción en el
  // arranque, que deja a la sede igual de incapaz de marcar.
  type Fila = {
    id: string;
    sedes: { codigo?: string; nombre?: string } | { codigo?: string; nombre?: string }[] | null;
  };
  let data: Fila | null = null;
  try {
    const res = await supabase
      .from("terminales")
      .select("id, sedes(codigo, nombre)")
      .abortSignal(topeDeRed())
      .single();
    if (res.error) return null;
    data = res.data as unknown as Fila;
  } catch {
    return null;
  }

  if (!data) return null;

  const sede = Array.isArray(data.sedes) ? data.sedes[0] : data.sedes;
  const info: TerminalInfo = {
    id: data.id,
    sedeCodigo: sede?.codigo ?? "?",
    sedeNombre: sede?.nombre ?? "?",
  };
  guardarInfoTerminalCacheada(info);
  return info;
}
