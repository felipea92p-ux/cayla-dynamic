"use client";

// El terminal no tiene SelectorTema (kiosco de un solo propósito, sin chrome
// de aplicación) — nadie ahí elige un tema a mano. Este componente no dibuja
// nada: solo mantiene <html data-tema> en sintonía con la configuración
// global de /admin/apariencia, para que "poner todos los terminales en
// oscuro" se pueda hacer desde un solo lugar en vez de Mac mini por Mac mini.
// Ver lib/use-tema.ts para la prioridad completa.
//
// PENDIENTE (medido 2026-09-07, sin resolver acá — es decisión de Felipe, no
// de presentación): en el terminal, el oscuro no mejora nada de lo que
// importa en este kiosco — el borde de las casillas de nombres pasa de
// 1,16:1 a 1,29:1 (sigue invisible) y la píldora de marcas perdidas de
// 3,93:1 a 3,92:1 (sigue reprobando) — y a cambio un fondo casi negro en una
// tienda iluminada convierte la pantalla en espejo. Dos salidas, ninguna se
// puede tomar solo en este archivo: forzar el terminal siempre claro (como
// `.hoja` fuerza claro al imprimir) y corregir la frase de
// admin/apariencia/page.tsx que hoy promete «los terminales siempre siguen
// esta configuración»; o arreglar antes el contraste del borde y la píldora
// en la paleta oscura.

import { createTerminalSupabaseClient } from "@cayla-dynamic/database";
import { useTema } from "@/lib/use-tema";

export function SeguirTemaGlobal() {
  useTema(createTerminalSupabaseClient());
  return null;
}
