"use client";

// Si el sidebar del panel se ve ancho (con etiquetas) o como rail (solo
// iconos). Mismo espíritu que `useTema`: la preferencia personal vive en
// localStorage y, mientras nadie la toque, manda el valor por defecto.
//
// La diferencia con el tema es de dónde sale ese valor por defecto: acá es el
// ANCHO DE LA VENTANA, y el ancho de la ventana no existe en el render del
// servidor. Por eso el estado tiene tres valores y no dos:
//
//   "auto"  — nadie eligió. El ancho lo decide la CSS con `xl:` (ver
//             CLASES_* en panel-navegacion.tsx). Es el único modo que se
//             puede pintar en el servidor sin adivinar, así que es el estado
//             inicial y por eso el primer pintado NUNCA parpadea.
//   "rail"  — elegido a mano: siempre iconos, aunque haya sitio de sobra.
//   "ancho" — elegido a mano: siempre etiquetas, aunque la ventana sea chica.
//
// Quien haya elegido a mano algo distinto de lo que su ancho daría por defecto
// puede ver un fotograma con el ancho equivocado, porque localStorage recién se
// lee después de montar. Se aceptó a cambio de no tocar el script
// anti-parpadeo de `app/layout.tsx`, que es del layout raíz y lo comparte el
// terminal de las cuatro sedes.

import { useCallback, useEffect, useState } from "react";

const CLAVE = "cayla-nav-colapsado";

// 80rem = 1280px = el `xl` de Tailwind. Escrito en rem, no en px, para que
// siga al tamaño de fuente del navegador igual que lo hace la utilidad `xl:`
// con la que tiene que coincidir.
const CONSULTA_ANCHA = "(min-width: 80rem)";

export type ModoNav = "auto" | "rail" | "ancho";

export function useNavColapsado(): {
  modo: ModoNav;
  /** Si en este instante se ven las etiquetas. Solo fiable después de montar. */
  expandido: boolean;
  alternar: () => void;
} {
  const [modo, setModo] = useState<ModoNav>("auto");
  const [ventanaAncha, setVentanaAncha] = useState(true);

  useEffect(() => {
    try {
      const guardado = localStorage.getItem(CLAVE);
      // Mismo desactivado puntual, y por la misma razón, que `use-tema.ts`:
      // localStorage no existe en el render del servidor, así que leerlo
      // DESPUÉS de montar no es un efecto evitable — es la única forma de que
      // el primer render coincida con el del servidor. El precio es el
      // fotograma de "auto" que el comentario de arriba ya explica.
      // eslint-disable-next-line react-hooks/set-state-in-effect
      if (guardado === "rail" || guardado === "ancho") setModo(guardado);
    } catch {
      // Sin localStorage (modo privado, cuota llena) no hay preferencia que
      // leer: se queda en "auto", que es un estado perfectamente válido.
    }

    const mq = window.matchMedia(CONSULTA_ANCHA);
    const alCambiar = () => setVentanaAncha(mq.matches);
    alCambiar();
    mq.addEventListener("change", alCambiar);
    return () => mq.removeEventListener("change", alCambiar);
  }, []);

  const expandido = modo === "auto" ? ventanaAncha : modo === "ancho";

  const alternar = useCallback(() => {
    // Se le pregunta al navegador EN EL MOMENTO DEL CLIC en vez de mirar
    // `ventanaAncha`. Ese estado depende de que el evento `change` del media
    // query haya llegado y React lo haya procesado, y si se quedó atrás el
    // botón alterna al revés: colapsar deja el sidebar ancho. Pasó al
    // verificarlo (la pestaña estaba en segundo plano y el navegador no
    // despachó el cambio), y aunque ahí fue artefacto de la prueba, el modo de
    // fallo es real y no cuesta nada evitarlo. `ventanaAncha` se queda solo
    // para `aria-expanded`, donde un fotograma desfasado no rompe nada.
    const anchaAhora =
      modo === "auto" ? window.matchMedia(CONSULTA_ANCHA).matches : modo === "ancho";
    const siguiente: ModoNav = anchaAhora ? "rail" : "ancho";
    try {
      localStorage.setItem(CLAVE, siguiente);
    } catch {
      // El sidebar cambia igual en esta pestaña; solo no se acuerda mañana.
    }
    setModo(siguiente);
  }, [modo]);

  return { modo, expandido, alternar };
}
