"use client";

import { useEffect, useRef } from "react";

// Lo que en el Dashboard NO cambia cada 30 segundos —Disciplina, memos,
// contratos— se carga al abrir, se repite cada 5 minutos y se pone al día al
// volver a la pestaña si ya pasó ese tiempo. Antes se cargaba UNA sola vez y la
// propia pantalla pedía «recarga para verlos al día»: en una pantalla que se
// presenta como «en vivo», eso era una mitad congelada sin decirlo.
//
// No cambia QUÉ se consulta ni cómo, solo CUÁNDO.

export const REFRESCO_LENTO_MS = 5 * 60_000;

export function useRefrescoLento(cargar: () => Promise<void>, cadaMs: number = REFRESCO_LENTO_MS) {
  // Siempre la última versión de `cargar`, sin reiniciar el temporizador cada vez que cambia.
  const ultimaCarga = useRef(cargar);
  useEffect(() => { ultimaCarga.current = cargar; });

  useEffect(() => {
    let ultima = 0;
    const correr = () => { ultima = Date.now(); void ultimaCarga.current(); };
    correr();
    const t = setInterval(correr, cadaMs);
    // Los navegadores pausan el temporizador en segundo plano: al volver se
    // recarga solo si ya toca, para no pedir de más por cada cambio de pestaña.
    const alVolver = () => { if (document.visibilityState === "visible" && Date.now() - ultima >= cadaMs) correr(); };
    document.addEventListener("visibilitychange", alVolver);
    return () => { clearInterval(t); document.removeEventListener("visibilitychange", alVolver); };
  }, [cadaMs]);
}
