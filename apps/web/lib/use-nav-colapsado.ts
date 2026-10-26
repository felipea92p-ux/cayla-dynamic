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
const CLAVE_GRUPOS = "cayla-nav-grupos-cerrados";

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

/**
 * Qué grupos del menú están contraídos, por su etiqueta.
 *
 * Se guarda cuáles están CERRADOS y no cuáles están abiertos, a propósito: un
 * grupo nuevo que alguien agregue mañana a `nav-items.ts` nace abierto sin que
 * haya que tocar nada, que es lo que se espera de algo recién puesto. Al revés,
 * nacería escondido y parecería que no se agregó.
 *
 * La lista se guarda entera en localStorage porque un plegado que se olvida en
 * cada recarga no es un plegado: obliga a rehacerlo cada vez y la gente deja de
 * usarlo.
 *
 * `clave` existe porque desde el 2026-10-06 hay DOS menús con grupos —el del
 * panel y el de «Lo mío»— y los dos tienen un «Pago» y una «Asistencia» con
 * contenido distinto. Con una sola memoria, cerrar «Pago» en «Lo mío» cerraría
 * Planilla, Provisiones y Costos en el panel. Al revés que el plegado a rail
 * (`useNavColapsado`), que es UNA preferencia —«quiero el menú angosto»— y
 * por eso los dos la comparten.
 */
export function useGruposCerrados(clave: string = CLAVE_GRUPOS): {
  cerrados: ReadonlySet<string>;
  alternarGrupo: (etiqueta: string) => void;
} {
  const [cerrados, setCerrados] = useState<ReadonlySet<string>>(() => new Set());

  useEffect(() => {
    try {
      const bruto = localStorage.getItem(clave);
      if (!bruto) return;
      const lista: unknown = JSON.parse(bruto);
      // Se comprueba la forma en vez de confiar: esto es texto que cualquiera
      // puede editar desde las herramientas del navegador, y un valor raro
      // rompería el render del menú entero.
      if (Array.isArray(lista) && lista.every((x) => typeof x === "string")) {
        // eslint-disable-next-line react-hooks/set-state-in-effect
        setCerrados(new Set(lista));
      }
    } catch {
      // Sin localStorage, o con un JSON roto: todos los grupos abiertos, que es
      // el estado por defecto y no molesta a nadie.
    }
  }, [clave]);

  const alternarGrupo = useCallback((etiqueta: string) => {
    setCerrados((antes) => {
      const siguiente = new Set(antes);
      if (siguiente.has(etiqueta)) siguiente.delete(etiqueta);
      else siguiente.add(etiqueta);
      try {
        localStorage.setItem(clave, JSON.stringify([...siguiente]));
      } catch {
        // El grupo se pliega igual en esta pestaña; solo no se acuerda mañana.
      }
      return siguiente;
    });
  }, [clave]);

  return { cerrados, alternarGrupo };
}
