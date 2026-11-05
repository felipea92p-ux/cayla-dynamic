"use client";

// El cajón del menú en el teléfono se cierra también deslizándolo hacia la izquierda, como el de cualquier app. El menú sigue al dedo,
// el velo se aclara en la misma proporción y, al soltar, se va (pasado un tercio, o de un tirón) o vuelve a su lugar. Un dedo que va de
// arriba abajo sigue desplazando el menú. La forma y los números son los de Retail (components/useLateralConElDedo.ts, lib/hoja-gesto.ts);
// lo de alejar la pantalla de atrás llega con el bloque de movimiento.

import { useEffect, useRef, type RefObject } from "react";
import { CONSULTA_CELULAR } from "@/lib/vidrio-lateral";

/** Lo que no se arrastra aunque el dedo vaya de lado. */
const NO_ARRASTRA = 'input, textarea, select, [contenteditable="true"], [role="slider"]';
const MOVIMIENTO_MINIMO = 6;
const FRACCION_PARA_CERRAR = 1 / 3;
const TIRON = 0.45; // px por ms

type Muestra = { t: number; x: number };

/** ¿El dedo va de lado o es otra cosa? null: todavía no se sabe. */
export function decidirLado(dx: number, dy: number): "lado" | "otro" | null {
  if (Math.abs(dx) < MOVIMIENTO_MINIMO && Math.abs(dy) < MOVIMIENTO_MINIMO) return null;
  return Math.abs(dx) > Math.abs(dy) * 1.2 ? "lado" : "otro";
}

/** Al soltar: se cierra quien recorrió un tercio del ancho o fue un tirón hacia la izquierda. */
export function cierraElCajon(dx: number, vx: number, ancho: number): boolean {
  if (dx >= 0) return false;
  return -dx > ancho * FRACCION_PARA_CERRAR || vx < -TIRON;
}

/** A la izquierda, uno a uno; a la derecha ya está abierto: resiste y se frena en 16 px. */
export function posicionDelCajon(dx: number): number {
  if (dx <= 0) return dx;
  return (1 - 1 / (dx / (16 * 3.6) + 1)) * 16;
}

function velocidad(muestras: readonly Muestra[]): number {
  const ultima = muestras[muestras.length - 1];
  const recientes = muestras.filter((m) => ultima.t - m.t <= 100);
  const primera = recientes[0];
  const dt = ultima.t - primera.t;
  return dt <= 0 ? 0 : (ultima.x - primera.x) / Math.max(16, dt);
}

export function useCerrarConElDedo(
  cajon: RefObject<HTMLElement | null>,
  velo: RefObject<HTMLElement | null>,
  abierto: boolean,
  cerrar: () => void,
): void {
  const alCerrar = useRef(cerrar);
  useEffect(() => {
    alCerrar.current = cerrar;
  });

  useEffect(() => {
    const el = cajon.current;
    if (!el || !abierto) return;
    let gesto: { x0: number; y0: number; deLado: boolean; muestras: Muestra[] } | null = null;

    const pintar = (x: number) => {
      el.style.transition = "none";
      el.style.transform = `translate3d(${x}px, 0, 0)`;
      const v = velo.current;
      if (v) {
        v.style.transition = "none";
        v.style.opacity = String(1 - Math.min(1, Math.max(0, -x / el.offsetWidth)));
      }
    };
    const soltarEstilos = () => {
      el.style.transition = "";
      el.style.transform = "";
      const v = velo.current;
      if (v) {
        v.style.transition = "";
        v.style.opacity = "";
      }
    };

    const alTocar = (e: TouchEvent) => {
      gesto = null;
      if (e.touches.length !== 1 || !window.matchMedia(CONSULTA_CELULAR).matches) return;
      const objetivo = e.target instanceof Element ? e.target : null;
      if (!objetivo || objetivo.closest(NO_ARRASTRA)) return;
      const t = e.touches[0];
      gesto = { x0: t.clientX, y0: t.clientY, deLado: false, muestras: [{ t: performance.now(), x: t.clientX }] };
    };
    const alMover = (e: TouchEvent) => {
      if (!gesto || e.touches.length !== 1) return;
      const t = e.touches[0];
      const dx = t.clientX - gesto.x0;
      if (!gesto.deLado) {
        const d = decidirLado(dx, t.clientY - gesto.y0);
        if (d === null) return;
        if (d === "otro") {
          gesto = null;
          return;
        }
        gesto.deLado = true;
      }
      if (e.cancelable) e.preventDefault();
      gesto.muestras.push({ t: performance.now(), x: t.clientX });
      if (gesto.muestras.length > 12) gesto.muestras.shift();
      pintar(posicionDelCajon(dx));
    };
    const alSoltar = (e: TouchEvent) => {
      const g = gesto;
      gesto = null;
      if (!g?.deLado) return;
      const dx = g.muestras[g.muestras.length - 1].x - g.x0;
      const vx = e.type === "touchcancel" ? 0 : velocidad(g.muestras);
      soltarEstilos();
      if (e.type !== "touchcancel" && cierraElCajon(dx, vx, el.offsetWidth)) alCerrar.current();
    };

    el.addEventListener("touchstart", alTocar, { passive: true });
    el.addEventListener("touchmove", alMover, { passive: false });
    el.addEventListener("touchend", alSoltar);
    el.addEventListener("touchcancel", alSoltar);
    return () => {
      el.removeEventListener("touchstart", alTocar);
      el.removeEventListener("touchmove", alMover);
      el.removeEventListener("touchend", alSoltar);
      el.removeEventListener("touchcancel", alSoltar);
      soltarEstilos();
    };
  }, [cajon, velo, abierto]);
}
