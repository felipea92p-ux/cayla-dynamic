"use client";

// El terminal no tiene SelectorTema (kiosco de un solo propósito, sin chrome
// de aplicación) — nadie ahí elige un tema a mano. Este componente no dibuja
// nada: solo mantiene <html data-tema> en sintonía con la configuración
// global de /admin/apariencia, para que "poner todos los terminales en
// oscuro" se pueda hacer desde un solo lugar en vez de Mac mini por Mac mini.
// Ver lib/use-tema.ts para la prioridad completa.

import { createTerminalSupabaseClient } from "@cayla-dynamic/database";
import { useTema } from "@/lib/use-tema";

export function SeguirTemaGlobal() {
  useTema(createTerminalSupabaseClient());
  return null;
}
