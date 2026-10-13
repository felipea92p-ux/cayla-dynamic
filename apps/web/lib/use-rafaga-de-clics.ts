"use client";

// Cinco clics seguidos sobre algo (el colibrí del login) y «se activa» durante
// un momento. La cuenta es `registrarClic`, de `lib/easter-eggs.ts`; esto solo
// la conecta con React. `activo` se apaga solo a los `duracionMs`.

import { useCallback, useEffect, useRef, useState } from "react";
import { registrarClic } from "./easter-eggs";

export function useRafagaDeClics(duracionMs = 1400): { activo: boolean; alClic: () => void } {
  const marcas = useRef<number[]>([]);
  const [activo, setActivo] = useState(false);

  const alClic = useCallback(() => {
    const r = registrarClic(marcas.current, Date.now());
    marcas.current = r.marcas;
    if (r.dispara) setActivo(true);
  }, []);

  useEffect(() => {
    if (!activo) return;
    const t = setTimeout(() => setActivo(false), duracionMs);
    return () => clearTimeout(t);
  }, [activo, duracionMs]);

  return { activo, alClic };
}
