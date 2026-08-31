"use client";

// El tema claro/oscuro/sistema. La paleta oscura y las reglas que la aplican
// viven en `globals.css`; este hook solo decide y recuerda CUÁL de las tres
// está activa, y lo refleja en `data-tema` sobre <html>.
//
// "Sistema" no se guarda como valor: es la AUSENCIA de la clave en
// localStorage, y así el CSS ya sabía leerla (`prefers-color-scheme`) antes
// de que este hook existiera. Guardarlo como un tercer string habría hecho
// falta enseñarle a la CSS un tercer estado que no necesita.
//
// Arranca en "sistema" para coincidir con el primer render del servidor —
// donde no hay `localStorage`— y recién se sincroniza con lo guardado DESPUÉS
// de montar, mismo patrón hidratación-segura que `useFiltroGuardado`. Eso NO
// es lo que evita el parpadeo del tema equivocado: eso lo hace el script en
// `app/layout.tsx`, que pone `data-tema` en el <html> antes de que React
// pinte nada. Este hook solo mantiene el botón del selector en sintonía con
// lo que ya se ve en pantalla.

import { useCallback, useEffect, useState } from "react";

const CLAVE = "cayla-tema";

export type Tema = "claro" | "oscuro" | "sistema";

function aplicar(tema: Tema) {
  if (tema === "sistema") document.documentElement.removeAttribute("data-tema");
  else document.documentElement.setAttribute("data-tema", tema);
  try {
    if (tema === "sistema") localStorage.removeItem(CLAVE);
    else localStorage.setItem(CLAVE, tema);
  } catch {
    // localStorage puede fallar (modo privado, cuota llena) — el tema sigue
    // aplicado en esta pestaña, solo no se acuerda entre visitas.
  }
}

export function useTema(): [Tema, (tema: Tema) => void] {
  const [tema, setTemaState] = useState<Tema>("sistema");

  useEffect(() => {
    try {
      const guardado = localStorage.getItem(CLAVE);
      // eslint-disable-next-line react-hooks/set-state-in-effect
      if (guardado === "claro" || guardado === "oscuro") setTemaState(guardado);
    } catch {
      // sin localStorage no hay nada guardado que leer — se queda en "sistema".
    }
  }, []);

  const setTema = useCallback((t: Tema) => {
    aplicar(t);
    setTemaState(t);
  }, []);

  return [tema, setTema];
}
