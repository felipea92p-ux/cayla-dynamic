"use client";

// La hoja del teléfono sigue al dedo. Viene de Retail (components/ui/useHojaArrastre.ts, ADR-0479), sin la media altura, que aquí ninguna hoja usa; las
// reglas de cuándo y a dónde viven puras en `hoja-gesto.ts`.
//
// QUÉ PROMETE
//   `enlazar` es un ref ESTABLE para la hoja: los oyentes se ponen una vez y un nuevo render no corta un arrastre a la mitad. Mueve la hoja y el velo
//   escribiendo el estilo directo, sin estado de React (un dedo dispara un evento por cuadro), y con `!important`, porque una animación CSS en curso le
//   gana a un estilo en línea normal. Abierta del todo, suelta todo y la hoja queda con sus clases de siempre.
//
// QUÉ ASUME
//   Solo con el dedo y bajo 640 px: en la computadora y en la tablet la hoja va arriba y al centro, y esto no hace nada.

import { useCallback, useEffect, useMemo, useRef, type RefObject } from "react";
import { decidirGesto, duracionHacia, posicionAlArrastrar, progresoDeCierre, seVaAlSoltar, velocidad, type Muestra } from "@/lib/hoja-gesto";

/** Debe coincidir con la regla de piezas.css: solo bajo 640 px la hoja va pegada abajo. */
export const CELULAR_HOJA = "(max-width: 39.99rem)";

/** Lo que no arrastra la hoja aunque el dedo baje encima: escribir, elegir, mover un deslizador. */
const NO_ARRASTRA = 'input, textarea, select, [contenteditable="true"], [role="slider"], canvas';

type Opciones = {
  /** Guardando: la hoja oye el dedo pero no se va. */
  bloqueado: boolean;
  /** El velo de la hoja: se aclara en la misma proporción en que baja. */
  velo: RefObject<HTMLElement | null>;
  /** La hoja ya va saliendo con el dedo y llega abajo en `ms`: quien la abrió la desmonta sin su animación de salida. */
  alSalir: (ms: number) => void;
  /** Cada vez que la hoja se mueve: cuánto de ella se fue y en cuántos ms llega. Lo usa lo de atrás. */
  alMoverse?: (progreso: number, ms: number) => void;
};

type Gesto = { x0: number; y0: number; eje: "hoja" | null; muestras: Muestra[]; corredores: HTMLElement[] };

export function useHojaArrastre(opciones: Opciones) {
  const op = useRef(opciones);
  useEffect(() => {
    op.current = opciones;
  });
  const quitar = useRef<(() => void) | null>(null);

  const enlazar = useCallback((hoja: HTMLElement | null) => {
    quitar.current?.();
    quitar.current = null;
    if (!hoja) return;

    let g: Gesto | null = null;
    let alto = 0;
    let yAhora = 0;
    let reloj: ReturnType<typeof setTimeout> | undefined;
    const sinMovimiento = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const enCelular = () => window.matchMedia(CELULAR_HOJA).matches;

    const pintar = (y: number, ms = 0) => {
      yAhora = y;
      const transicion = ms ? `${ms}ms var(--ease-cayla)` : "";
      hoja.style.setProperty("transition", transicion ? `transform ${transicion}` : "none", "important");
      hoja.style.setProperty("transform", `translate3d(0, ${y}px, 0)`, "important");
      const p = progresoDeCierre(y, alto);
      const velo = op.current.velo.current;
      if (velo) {
        velo.style.setProperty("transition", transicion ? `opacity ${transicion}` : "none", "important");
        velo.style.setProperty("opacity", String(1 - p), "important");
      }
      op.current.alMoverse?.(p, ms);
    };
    const soltarEstilos = () => {
      for (const el of [hoja, op.current.velo.current]) {
        el?.style.removeProperty("transition");
        el?.style.removeProperty("transform");
        el?.style.removeProperty("opacity");
      }
      yAhora = 0;
    };

    const alTocar = (e: TouchEvent) => {
      g = null;
      if (e.touches.length !== 1 || !enCelular()) return;
      const objetivo = e.target instanceof Element ? e.target : null;
      if (!objetivo || objetivo.closest(NO_ARRASTRA)) return;
      // Lo que corre bajo el dedo, de adentro hacia la hoja: si algo no está arriba del todo, bajar el dedo es desplazarlo. Salvo el asa: se queda a la
      // vista al correr y tirar de ella siempre mueve la hoja.
      const corredores: HTMLElement[] = [];
      for (let el: Element | null = objetivo.closest("[data-asa-hoja]") ? null : objetivo; el && hoja.contains(el); el = el.parentElement) {
        if (el instanceof HTMLElement && el.scrollHeight > el.clientHeight + 1 && /(auto|scroll)/.test(getComputedStyle(el).overflowY)) corredores.push(el);
      }
      const t = e.touches[0];
      alto = hoja.offsetHeight;
      g = { x0: t.clientX, y0: t.clientY, eje: null, muestras: [{ t: performance.now(), y: t.clientY }], corredores };
    };

    const alMover = (e: TouchEvent) => {
      if (!g || e.touches.length !== 1) return;
      const t = e.touches[0];
      const dx = t.clientX - g.x0;
      const dy = t.clientY - g.y0;
      if (g.eje === null) {
        const arriba = g.corredores.every((c) => c.scrollTop <= 0);
        // Mientras se decide, un dedo que va a ser de la hoja no se le entrega al navegador: si empieza su gesto, no lo suelta.
        if (e.cancelable && dy > 0 && arriba) e.preventDefault();
        const eje = decidirGesto(dx, dy, arriba);
        if (eje === null) return;
        if (eje === "contenido") {
          g = null;
          return;
        }
        g.eje = "hoja";
        clearTimeout(reloj);
        hoja.setAttribute("data-arrastrando", "");
      }
      if (e.cancelable) e.preventDefault();
      g.muestras.push({ t: performance.now(), y: t.clientY });
      if (g.muestras.length > 12) g.muestras.shift();
      pintar(posicionAlArrastrar(dy, op.current.bloqueado));
    };

    const alSoltar = (e: TouchEvent) => {
      const gesto = g;
      g = null;
      if (!gesto || gesto.eje !== "hoja") return;
      hoja.removeAttribute("data-arrastrando");
      const vy = e.type === "touchcancel" ? 0 : velocidad(gesto.muestras);
      if (!op.current.bloqueado && e.type !== "touchcancel" && seVaAlSoltar(yAhora, alto, vy)) {
        const ms = sinMovimiento() ? 0 : duracionHacia(alto - yAhora, vy);
        pintar(alto, ms);
        op.current.alSalir(ms);
        return;
      }
      const ms = sinMovimiento() ? 0 : duracionHacia(yAhora, vy);
      pintar(0, ms);
      reloj = setTimeout(soltarEstilos, ms + 20);
    };

    hoja.addEventListener("touchstart", alTocar, { passive: true });
    hoja.addEventListener("touchmove", alMover, { passive: false });
    hoja.addEventListener("touchend", alSoltar);
    hoja.addEventListener("touchcancel", alSoltar);
    quitar.current = () => {
      clearTimeout(reloj);
      hoja.removeEventListener("touchstart", alTocar);
      hoja.removeEventListener("touchmove", alMover);
      hoja.removeEventListener("touchend", alSoltar);
      hoja.removeEventListener("touchcancel", alSoltar);
    };
  }, []);

  return useMemo(() => ({ enlazar }), [enlazar]);
}
