"use client";

// Un panel que se abre ENCIMA de la pantalla —un cajón, un menú de teléfono—
// tiene que hacer siempre las mismas tres cosas, y las tres se olvidan por
// igual: poner el foco adentro al abrirse, no dejarlo salir mientras siga
// abierto, y devolverlo a donde estaba al cerrarse.
//
// Esto vivía escrito una sola vez, dentro de `CajonAdmin`, con su porqué
// anotado: «Felipe abre el panel desde el teléfono, y el menú viejo no
// atrapaba el foco, no cerraba con Escape y no devolvía el foco a la
// hamburguesa al cerrarse: con el teclado te ibas caminando por detrás del
// menú abierto sin ninguna forma de volver».
//
// Se sacó de ahí el 2026-09-10, al aparecer el SEGUNDO cajón —el menú de
// secciones de «Lo mío»—, y no por prolijidad: un cajón sin trampa de foco
// funciona perfectamente con el ratón. El día que la copia se quedara atrás,
// nada fallaría a la vista; simplemente habría una pantalla en la que el
// teclado se escapa.

import { useEffect } from "react";

const FOCUSABLES =
  'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

/**
 * Atrapa el foco dentro de `caja` mientras `abierto` sea cierto, cierra con
 * Escape y devuelve el foco a `volverElFocoA` al cerrarse.
 *
 * Los dos genéricos existen porque `RefObject` es invariante: un
 * `RefObject<HTMLButtonElement | null>` no encaja en un
 * `RefObject<HTMLElement | null>`, así que sin ellos cada llamada tendría que
 * ensanchar el tipo de su propia ref para poder pasarla.
 */
export function useFocoAtrapado<C extends HTMLElement, D extends HTMLElement>({
  abierto,
  onCerrar,
  caja,
  volverElFocoA,
}: {
  abierto: boolean;
  onCerrar: () => void;
  /** El contenedor del panel. */
  caja: React.RefObject<C | null>;
  /** Lo que lo abrió, para devolverle el foco al cerrar. */
  volverElFocoA: React.RefObject<D | null>;
}): void {
  useEffect(() => {
    if (!abierto) return;

    const disparador = volverElFocoA.current;
    // El primer enlace, no el contenedor: quien abre el menú con el teclado
    // espera estar YA sobre algo que pueda pulsar.
    const primero = caja.current?.querySelector<HTMLElement>(FOCUSABLES);
    primero?.focus();

    function alPresionar(e: KeyboardEvent) {
      if (e.key === "Escape") {
        e.preventDefault();
        onCerrar();
        return;
      }
      if (e.key !== "Tab" || !caja.current) return;

      // Atrapar el foco: sin esto, tabular desde el último enlace del menú
      // sigue hacia la página que está debajo del velo, que no se puede ver
      // ni tocar.
      const focusables = Array.from(caja.current.querySelectorAll<HTMLElement>(FOCUSABLES));
      if (focusables.length === 0) return;
      const inicio = focusables[0];
      const fin = focusables[focusables.length - 1];

      if (e.shiftKey && document.activeElement === inicio) {
        e.preventDefault();
        fin.focus();
      } else if (!e.shiftKey && document.activeElement === fin) {
        e.preventDefault();
        inicio.focus();
      }
    }

    document.addEventListener("keydown", alPresionar);
    return () => {
      document.removeEventListener("keydown", alPresionar);
      // Al cerrar, el foco vuelve de donde salió. Si no, se queda en el
      // <body> y la siguiente tabulación arranca desde el principio de todo.
      disparador?.focus();
    };
  }, [abierto, onCerrar, caja, volverElFocoA]);
}
