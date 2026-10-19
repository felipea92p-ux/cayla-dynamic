"use client";

// Recorrido guiado de primera vez (driver.js, MIT — ver CLAUDE.md, decisión
// tomada frente a Appcues/WalkMe/Userpilot: ninguna de las tres se justifica
// para ~30 personas, y las tres sacarían la sesión del navegador en pantallas
// con DNI y sueldo). Este archivo es el MOTOR, reutilizable: cada pantalla que
// quiera su propio recorrido solo escribe su lista de `PasoRecorrido` y llama
// al hook — igual que `useTema`/`useFiltroGuardado` son el motor y cada
// pantalla trae su propia clave/config.
//
// "No volver a mostrar" vive en localStorage, por navegador, nunca en la
// base: es un recordatorio de pantalla, no un acuse legal (comparar con
// `anuncios_leidos`, migración 0351, que SÍ es por persona en la base porque
// ahí importa quién vio qué). Si un día hiciera falta saber desde el panel
// quién ya vio un recorrido, ESE día se migra a una tabla — no antes.
//
// `skipMissingElement` + `waitForElement` (de driver.js) son los que resuelven
// que algunas tarjetas de Resumen pidan sus propios datos y tarden en llegar
// (`AdelantoDePago`, `HorasDeLaSemana`) o no existan para todo el mundo
// (sin vacaciones pendientes, RxH sin sueldo fijo): un paso que no aparece en
// 1.2s se salta solo, en vez de que el recorrido se quede buscando algo que
// nunca llega.
//
// Dos cosas viven separadas a propósito (2026-10-19, primer paso de «términos
// primero, guía después»): CUÁNDO se lanza un recorrido —el efecto del hook— y
// CÓMO se lanza —`lanzarRecorrido`—. Antes eran lo mismo y un botón «Ver guía»
// no tenía por dónde entrar: el único camino era que `activo` pasara a `true`
// por primera vez. Ahora el hook devuelve `iniciar()`, que salta la marca de
// «ya lo vio» y lo lanza a pedido; el comportamiento automático no cambió.

import { useCallback, useEffect, useRef } from "react";
import { driver, type DriveStep } from "driver.js";
import "driver.js/dist/driver.css";

export type PasoRecorrido = {
  /** Selector CSS del elemento a resaltar — un `data-tour="…"` puesto a mano
   *  en la pantalla, nunca una clase de estilo: si el diseño cambia, el
   *  recorrido no se tiene que enterar. */
  selector: string;
  titulo: string;
  texto: string;
  /** Lado preferido del recuadro respecto al elemento. driver.js reubica solo
   *  si no entra ahí. */
  lado?: "top" | "right" | "bottom" | "left";
};

function claveDe(tourId: string) {
  return `cayla-recorrido-${tourId}`;
}

/** Si la persona ya marcó «no volver a mostrar» este recorrido en este navegador. */
function yaLoMarcoComoVisto(tourId: string): boolean {
  try {
    return localStorage.getItem(claveDe(tourId)) === "1";
  } catch {
    // Sin localStorage (modo privado, cuota llena) no hay cómo recordar la
    // elección — se muestra igual: es preferible a no mostrarlo nunca por
    // un error de lectura que no tiene nada que ver con la persona.
    return false;
  }
}

/**
 * Arma y lanza el recorrido. No decide SI corresponde mostrarlo —eso es de
 * quien llama—: solo lo muestra. Devuelve cómo apagarlo.
 */
function lanzarRecorrido(tourId: string, pasos: readonly PasoRecorrido[]): () => void {
  const clave = claveDe(tourId);
  let noMostrarDeNuevo = false;
  const sinAnimacion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  const pasosDriver: DriveStep[] = pasos.map((p) => ({
    element: p.selector,
    popover: { title: p.titulo, description: p.texto, side: p.lado ?? "bottom", align: "start" },
  }));

  const instancia = driver({
    steps: pasosDriver,
    animate: !sinAnimacion,
    showProgress: true,
    progressText: "Paso {{current}} de {{total}}",
    nextBtnText: "Siguiente",
    prevBtnText: "Anterior",
    doneBtnText: "Entendido",
    popoverClass: "recorrido-cayla",
    overlayColor: "#000000",
    overlayOpacity: 0.6,
    stageRadius: 16,
    stagePadding: 6,
    smoothScroll: true,
    disableActiveInteraction: true, // que el tour no se convierta en un clic accidental a "Ver mi boleta"
    overlayClickBehavior: "close",
    skipMissingElement: true,
    waitForElement: 1200,
    onPopoverRender: (popover) => {
      popover.nextButton.classList.add("recorrido-btn-primario");

      // El checkbox se reconstruye en cada paso (driver.js rearma el
      // popover entero), así que el estado "marcado" vive en la variable
      // de arriba, no en el DOM — sin esto, marcarlo en el paso 2 se
      // olvidaba al llegar al paso 3.
      const etiqueta = document.createElement("label");
      etiqueta.className = "recorrido-checkbox";
      const casilla = document.createElement("input");
      casilla.type = "checkbox";
      casilla.checked = noMostrarDeNuevo;
      casilla.addEventListener("change", () => { noMostrarDeNuevo = casilla.checked; });
      etiqueta.appendChild(casilla);
      etiqueta.appendChild(document.createTextNode("No volver a mostrar este recorrido"));
      popover.wrapper.insertBefore(etiqueta, popover.footer);
    },
    onDestroyed: () => {
      if (!noMostrarDeNuevo) return;
      try {
        localStorage.setItem(clave, "1");
      } catch {
        // Igual que arriba: si no se puede guardar, se repite la próxima
        // vez — no es un dato que se pueda perder de verdad, es una ayuda.
      }
    },
  });

  instancia.drive();
  return () => instancia.destroy();
}

/**
 * Lanza el recorrido la primera vez que `activo` pasa a `true`, y nunca más
 * si la persona marcó "no volver a mostrar". Un `useRef` evita que ir y
 * volver a la misma pestaña dentro de la misma visita lo repita — "primera
 * vez" es por carga de página, no por cada clic de menú.
 *
 * Devuelve `iniciar()`: lo lanza ahora mismo, aunque ya lo haya visto —para
 * un botón «Ver guía»—. Si hay uno en pantalla, lo reemplaza en vez de apilar
 * dos.
 */
export function useRecorridoGuiado(tourId: string, pasos: readonly PasoRecorrido[], activo: boolean) {
  const yaCorrioRef = useRef(false);
  const apagarRef = useRef<(() => void) | null>(null);

  useEffect(() => {
    if (!activo || yaCorrioRef.current || pasos.length === 0) return;
    yaCorrioRef.current = true;

    if (yaLoMarcoComoVisto(tourId)) return;

    apagarRef.current = lanzarRecorrido(tourId, pasos);
    return () => {
      apagarRef.current?.();
      apagarRef.current = null;
    };
    // `pasos` es una constante de módulo en quien llama (mismo patrón que
    // `SECCIONES`): su identidad no cambia entre renders, así que no hace
    // falta más que declararla acá para el lint de dependencias.
  }, [activo, tourId, pasos]);

  const iniciar = useCallback(() => {
    if (pasos.length === 0) return;
    apagarRef.current?.();
    apagarRef.current = lanzarRecorrido(tourId, pasos);
  }, [tourId, pasos]);

  return { iniciar };
}
