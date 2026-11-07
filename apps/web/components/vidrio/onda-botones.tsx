"use client";

// La onda que nace donde se toca un botón: la mano ve que el botón la escuchó, también con el dedo. Montado una vez en el marco: ninguna pantalla hace nada. Solo mueve el
// dibujo (`::before`, en movimiento.css); nunca toca el clic ni el foco. Viene de Retail (components/ui/OndaBotones.tsx).

import { useEffect } from "react";

const BOTON = "button.rounded-control, a.rounded-control";

export function OndaBotones() {
  useEffect(() => {
    const alPresionar = (e: PointerEvent) => {
      const boton = e.target instanceof Element ? e.target.closest<HTMLElement>(BOTON) : null;
      if (!boton || boton.matches(":disabled, [aria-disabled='true']")) return;
      const r = boton.getBoundingClientRect();
      const x = e.clientX - r.left;
      const y = e.clientY - r.top;
      // El diámetro alcanza la esquina más lejana: la onda llena el botón venga de donde venga el toque.
      const d = 2 * Math.hypot(Math.max(x, r.width - x), Math.max(y, r.height - y));
      boton.style.setProperty("--onda-x", `${x}px`);
      boton.style.setProperty("--onda-y", `${y}px`);
      boton.style.setProperty("--onda-d", `${d}px`);
      // Quitar y volver a poner el atributo reinicia la animación aunque el botón se toque dos veces seguidas.
      boton.removeAttribute("data-onda");
      void boton.offsetWidth;
      boton.setAttribute("data-onda", "");
      window.setTimeout(() => boton.removeAttribute("data-onda"), 500);
    };
    document.addEventListener("pointerdown", alPresionar, { capture: true, passive: true });
    return () => document.removeEventListener("pointerdown", alPresionar, { capture: true });
  }, []);
  return null;
}
