"use client";

// La gota que fluye de una pestaña a otra. La elegida deja de pintarse a sí misma y una sola pieza, el `::before` de la fila, viaja hasta ella: se estira hasta cubrir la de antes y
// la nueva, y se recoge en la nueva. Viene de Retail (components/ui/IndicadorDeslizante.tsx, variante «gota»).
//
// DECIDÍ: va DENTRO de cada fila de pestañas, como en Retail, y mira a su padre.
// DESCARTÉ: un solo vigilante en el marco que busca las filas en toda la pantalla, que fue la primera versión. El marco despierta antes que la pantalla, así que la gota escribía
//   sobre una fila que React todavía no había recibido del servidor, y React avisaba que «no coincide»: se vio en Turnos y Dashboard, el 2026-11-05.
// SE ROMPE SI: alguien escribe una fila nueva con `role="tablist"` sin ponerle esto, o marca la elegida con otra cosa que `aria-current="page"` o `aria-selected="true"`. Se queda
//   como en piezas.css, sin viajar: se ve bien igual.

import { prefiereQuieto } from "@/lib/vidrio-movimiento";
import { useEffect, useRef } from "react";

const ELEGIDA = ":scope > [aria-current='page'], :scope > [aria-selected='true']";
/** Un poco menos que el primer tramo de la CSS: el segundo arranca antes de que la gota se detenga. */
const ESTIRA_MS = 140;
const RECOGE_MS = 300;

export function GotaDePestanas() {
  const ancla = useRef<HTMLSpanElement>(null);

  useEffect(() => {
    const fila = ancla.current?.parentElement;
    if (!fila || fila.closest(".hoja")) return;

    let elegida: Element | null = null;
    let x = 0;
    let w = 0;
    let relojes: number[] = [];
    const poner = (nx: number, nw: number) => {
      x = nx;
      w = nw;
      fila.style.setProperty("--gota-x", `${nx}px`);
      fila.style.setProperty("--gota-w", `${nw}px`);
    };

    const revisar = () => {
      const nueva = fila.querySelector(ELEGIDA);
      if (nueva === elegida) return;
      const habia = elegida !== null;
      elegida = nueva;
      if (!(nueva instanceof HTMLElement)) {
        fila.removeAttribute("data-gota");
        return;
      }
      const nx = nueva.offsetLeft;
      const nw = nueva.offsetWidth;
      relojes.forEach((r) => window.clearTimeout(r));
      relojes = [];
      if (!habia || prefiereQuieto()) {
        fila.removeAttribute("data-fluye");
        poner(nx, nw);
        fila.setAttribute("data-gota", "");
        return;
      }
      // Fluye: primero cubre las dos, después se recoge en la nueva.
      const izq = Math.min(x, nx);
      fila.setAttribute("data-fluye", "estira");
      poner(izq, Math.max(x + w, nx + nw) - izq);
      relojes.push(
        window.setTimeout(() => {
          fila.setAttribute("data-fluye", "recoge");
          poner(nx, nw);
          relojes.push(window.setTimeout(() => fila.removeAttribute("data-fluye"), RECOGE_MS));
        }, ESTIRA_MS),
      );
    };

    revisar();
    const cambios = new MutationObserver(revisar);
    cambios.observe(fila, { subtree: true, childList: true, attributes: true, attributeFilter: ["aria-current", "aria-selected"] });
    // Algo cambió de tamaño (la ventana, una cuenta que llega, la letra que termina de cargar): se recoloca sin viajar.
    const tamano = new ResizeObserver(() => {
      if (elegida instanceof HTMLElement && !fila.hasAttribute("data-fluye")) poner(elegida.offsetLeft, elegida.offsetWidth);
    });
    tamano.observe(fila);
    return () => {
      cambios.disconnect();
      tamano.disconnect();
      relojes.forEach((r) => window.clearTimeout(r));
    };
  }, []);

  return <span ref={ancla} hidden aria-hidden />;
}
