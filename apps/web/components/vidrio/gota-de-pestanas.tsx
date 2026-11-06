"use client";

// La gota que fluye de una pestaña a otra. La elegida deja de pintarse a sí misma y una sola pieza, el `::before` de la fila, viaja hasta ella: se estira hasta cubrir la de antes y
// la nueva, y se recoge en la nueva. Viene de Retail (components/ui/IndicadorDeslizante.tsx, variante «gota»).
//
// DECIDÍ: un solo vigilante montado en el marco, que mira toda la pantalla.
// DESCARTÉ: el componente dentro de cada fila, como Retail, porque aquí hay dos formas de escribir pestañas (`Pestanas` y dos `role="tablist"` a mano) y la tercera que alguien
//   escriba se quedaría sin gota sin que nada avise.
// SE ROMPE SI: una fila de pestañas marca la elegida con otra cosa que `aria-current="page"` o `aria-selected="true"`: se queda como en piezas.css, sin viajar. Se ve bien igual.

import { useEffect } from "react";

const FILA = ".vidrio-pestanas, [role='tablist']";
const ELEGIDA = ":scope > [aria-current='page'], :scope > [aria-selected='true']";
/** Un poco menos que el primer tramo de la CSS: el segundo arranca antes de que la gota se detenga. */
const ESTIRA_MS = 140;
const RECOGE_MS = 300;

type Estado = { elegida: Element | null; x: number; w: number; relojes: number[]; tamano: ResizeObserver };

const estados = new WeakMap<HTMLElement, Estado>();

function poner(fila: HTMLElement, e: Estado, x: number, w: number) {
  e.x = x;
  e.w = w;
  fila.style.setProperty("--gota-x", `${x}px`);
  fila.style.setProperty("--gota-w", `${w}px`);
}

function colocarSinViajar(fila: HTMLElement, e: Estado) {
  if (!(e.elegida instanceof HTMLElement)) return;
  fila.removeAttribute("data-fluye");
  poner(fila, e, e.elegida.offsetLeft, e.elegida.offsetWidth);
}

function revisar(fila: HTMLElement) {
  let e = estados.get(fila);
  const elegida = fila.querySelector(ELEGIDA);
  if (!e) {
    const nuevo: Estado = {
      elegida: null,
      x: 0,
      w: 0,
      relojes: [],
      // Algo cambió de tamaño (la ventana, una cuenta que llega, la letra que termina de cargar): se recoloca sin viajar.
      tamano: new ResizeObserver(() => {
        if (!fila.hasAttribute("data-fluye")) colocarSinViajar(fila, nuevo);
      }),
    };
    nuevo.tamano.observe(fila);
    estados.set(fila, nuevo);
    e = nuevo;
  }
  if (elegida === e.elegida) return;
  const antes = e.elegida;
  e.elegida = elegida;
  if (!(elegida instanceof HTMLElement)) {
    fila.removeAttribute("data-gota");
    return;
  }
  const x = elegida.offsetLeft;
  const w = elegida.offsetWidth;
  const quieto = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  e.relojes.forEach((r) => window.clearTimeout(r));
  e.relojes = [];
  if (!antes || quieto) {
    fila.removeAttribute("data-fluye");
    poner(fila, e, x, w);
    fila.setAttribute("data-gota", "");
    return;
  }
  // Fluye: primero cubre las dos, después se recoge en la nueva.
  const izq = Math.min(e.x, x);
  fila.setAttribute("data-fluye", "estira");
  poner(fila, e, izq, Math.max(e.x + e.w, x + w) - izq);
  const actual = e;
  e.relojes.push(
    window.setTimeout(() => {
      fila.setAttribute("data-fluye", "recoge");
      poner(fila, actual, x, w);
      actual.relojes.push(window.setTimeout(() => fila.removeAttribute("data-fluye"), RECOGE_MS));
    }, ESTIRA_MS),
  );
}

export function GotaDePestanas() {
  useEffect(() => {
    let cuadro = 0;
    const revisarTodas = () => {
      cuadro = 0;
      for (const fila of document.querySelectorAll<HTMLElement>(FILA)) {
        if (!fila.closest(".hoja")) revisar(fila);
      }
    };
    const pedir = () => {
      if (!cuadro) cuadro = requestAnimationFrame(revisarTodas);
    };
    revisarTodas();
    const cambios = new MutationObserver(pedir);
    cambios.observe(document.body, { subtree: true, childList: true, attributes: true, attributeFilter: ["aria-current", "aria-selected"] });
    return () => {
      cancelAnimationFrame(cuadro);
      cambios.disconnect();
    };
  }, []);
  return null;
}
