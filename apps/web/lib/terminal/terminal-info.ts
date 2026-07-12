import { createTerminalSupabaseClient } from "@cayla-dynamic/database";

export interface TerminalInfo {
  id: string;
  sedeCodigo: string;
  sedeNombre: string;
  requierePin: boolean;
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

/** Se llama una vez tras vincular el dispositivo; requiere estar online. */
export async function refrescarInfoTerminal(): Promise<TerminalInfo | null> {
  const supabase = createTerminalSupabaseClient();
  const { data, error } = await supabase
    .from("terminales")
    .select("id, requiere_pin, sedes(codigo, nombre)")
    .single();

  if (error || !data) return null;

  const sede = Array.isArray(data.sedes) ? data.sedes[0] : data.sedes;
  const info: TerminalInfo = {
    id: data.id as string,
    sedeCodigo: sede?.codigo ?? "?",
    sedeNombre: sede?.nombre ?? "?",
    requierePin: (data as { requiere_pin?: boolean }).requiere_pin ?? true,
  };
  guardarInfoTerminalCacheada(info);
  return info;
}
