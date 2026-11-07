"use client";

// Los ganchos del menú con vidrio. Aparte de `lib/vidrio-lateral.ts` porque ese archivo lo importa el layout raíz, que corre en el servidor,
// a través de `lib/vidrio.ts`, y un gancho de React no puede vivir en ese camino.

import { useSyncExternalStore } from "react";
import { CONSULTA_CELULAR, lateralPlegado, suscribirLateral } from "./vidrio-lateral";

/** Si el menú está plegado. En el servidor contesta «no»: lo que se pinta primero lo decide la hoja de estilos con el atributo. */
export function useLateralPlegado(): boolean {
  return useSyncExternalStore(suscribirLateral, lateralPlegado, () => false);
}

function suscribirCelular(oyente: () => void): () => void {
  const consulta = window.matchMedia(CONSULTA_CELULAR);
  consulta.addEventListener("change", oyente);
  return () => consulta.removeEventListener("change", oyente);
}

/** Bajo 768 px el menú es un cajón, y va siempre abierto aunque la preferencia diga «plegado». */
export function useEsCelular(): boolean {
  return useSyncExternalStore(suscribirCelular, () => window.matchMedia(CONSULTA_CELULAR).matches, () => false);
}
