"use client";

import { useEffect } from "react";

// Solo se monta en `(terminal)/layout.tsx` — no en la raíz, y a propósito.
// Registra `/terminal/sw.js` con `scope: '/terminal/'`, que además es el
// alcance MÁXIMO posible para un archivo que vive en `/terminal/`: aunque
// alguien quitara el `scope` explícito mañana, este service worker nunca
// podría interceptar una petición de `/admin` ni de `/mio`. Ver sw.js para
// qué problema resuelve y qué no toca.
//
// Solo en producción. En `pnpm dev` los paquetes de Next no tienen hash
// estable entre recargas — cachear una versión de desarrollo solo produce
// código viejo sirviéndose después de un cambio, que es lo último que hace
// falta mientras se está probando el terminal en esta misma Mac.
export function RegistrarServiceWorker() {
  useEffect(() => {
    if (process.env.NODE_ENV !== "production") return;
    if (!("serviceWorker" in navigator)) return;
    navigator.serviceWorker.register("/terminal/sw.js", { scope: "/terminal/" }).catch(() => {
      // Sin service worker el terminal sigue funcionando exactamente como
      // hoy: solo pierde la resistencia a un reinicio sin red. No hay nada
      // que avisarle a quien está marcando por esto.
    });
  }, []);
  return null;
}
