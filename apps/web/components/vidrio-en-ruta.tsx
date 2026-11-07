"use client";

import { useLayoutEffect } from "react";
import { usePathname } from "next/navigation";
import { aplicarVidrio, valorVidrio } from "@/lib/vidrio";
import { aplicarLateral } from "@/lib/vidrio-lateral";
import { aplicarMovimientoGuardado, quitarMovimiento } from "@/lib/vidrio-movimiento";
import { aplicarTemaGuardado } from "@/lib/vidrio-tema";

// La mitad del interruptor que el guion en línea no puede hacer: ese guion corre una sola vez, al cargar el documento,
// y el <html> del layout raíz no se vuelve a dibujar al navegar. Entrar a /terminal desde la portada, o salir de la 404
// del terminal hacia el panel, dejaría el atributo de la superficie anterior hasta la próxima recarga.
//
// `useLayoutEffect` y no `useEffect`: corre en la misma confirmación que trae la pantalla nueva y antes de pintarla, así
// que nunca se ve un cuadro de la pantalla nueva con el aspecto de la anterior. Solo se monta si hay algún interruptor
// encendido (ver app/layout.tsx y lib/vidrio.ts, donde está la decisión completa).
export function VidrioEnRuta() {
  const ruta = usePathname();
  useLayoutEffect(() => {
    const valor = valorVidrio(ruta);
    aplicarVidrio(document.documentElement, valor);
    if (valor === "panel") {
      aplicarTemaGuardado();
      aplicarLateral();
      aplicarMovimientoGuardado();
    } else {
      // En el terminal no hay botón de animaciones: el atributo no se queda (lib/vidrio-movimiento.ts).
      quitarMovimiento();
    }
  }, [ruta]);
  return null;
}
