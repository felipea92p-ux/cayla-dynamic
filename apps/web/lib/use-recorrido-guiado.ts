"use client";

// Recorrido guiado de primera vez (driver.js, MIT — ver CLAUDE.md, decisión
// tomada frente a Appcues/WalkMe/Userpilot: ninguna de las tres se justifica
// para ~30 personas, y las tres sacarían la sesión del navegador en pantallas
// con DNI y sueldo). Este archivo es el MOTOR, reutilizable: cada pantalla que
// quiera su propio recorrido solo escribe su lista de `PasoRecorrido` y llama
// al hook — igual que `useTema`/`useFiltroGuardado` son el motor y cada
// pantalla trae su propia clave/config.
//
// Que ya se vio un recorrido vive en localStorage, por navegador, nunca en la
// base: es un recordatorio de pantalla, no un acuse legal (comparar con
// `anuncios_leidos`, migración 0351, que SÍ es por persona en la base porque
// ahí importa quién vio qué). Si un día hiciera falta saber desde el panel
// quién ya vio un recorrido, ESE día se migra a una tabla — no antes.
//
// QUÉ CUENTA COMO «YA LO VIO» (2026-10-19). Antes había que marcar una casilla
// «no volver a mostrar»; quien no la marcaba lo veía en cada visita, y para
// quien no sabía que existía era un recorrido que volvía solo. Ahora cuenta
// terminarlo O dejarlo (omitir, la X, Escape, un clic afuera): una persona que
// decide no verlo ya dijo lo que quería decir. Lo único que NO cuenta es que
// la pantalla lo apague por su cuenta (salir de ella a mitad de camino): eso no
// lo decidió nadie, y se vuelve a ofrecer. Quien lo quiera de nuevo tiene
// `iniciar()`.
//
// LA GUÍA ES LIVIANA A PROPÓSITO: velo casi transparente y un aro sobre lo que
// explica, no una pantalla negra con un recuadro. La maqueta es
// docs/terminos-y-guia-mio-prototipo-2026-10-19.html.
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

/** Si la persona ya vio (o dejó) este recorrido en este navegador. */
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

function marcarComoVisto(tourId: string) {
  try {
    localStorage.setItem(claveDe(tourId), "1");
  } catch {
    // Si no se puede guardar, se ofrece otra vez la próxima visita: es una
    // ayuda, no un dato que se pueda perder de verdad.
  }
}

/**
 * Arma y lanza el recorrido. No decide SI corresponde mostrarlo —eso es de
 * quien llama—: solo lo muestra. Devuelve cómo apagarlo.
 */
function lanzarRecorrido(tourId: string, pasos: readonly PasoRecorrido[]): () => void {
  // Lo que cuenta como «ya lo vio» es lo que la persona decide: terminarlo,
  // omitirlo, la X, Escape o un clic afuera. driver.js llama a
  // `onDestroyStarted` SOLO por esos caminos; cuando lo apaga el código
  // (`instancia.destroy()`: salir de la pantalla, o reemplazarlo con
  // `iniciar`) no lo llama. Esa diferencia es toda la regla, y no hace falta
  // una bandera: ver `terminar` abajo.
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
    // Sin «Anterior»: con tres pasos no se vuelve atrás por nada, y los tres
    // botones más el contador no caben en un recuadro de 300px sin partirse.
    showButtons: ["next", "close"],
    doneBtnText: "Listo",
    popoverClass: "recorrido-cayla",
    // Velo casi transparente: el aro de `.driver-active-element` (globals.css)
    // es lo que señala, no el negro alrededor. Era 0.6.
    overlayColor: "#000000",
    overlayOpacity: 0.12,
    stageRadius: 16,
    stagePadding: 6,
    smoothScroll: true,
    disableActiveInteraction: true, // que el tour no se convierta en un clic accidental a "Ver mi boleta"
    overlayClickBehavior: "close",
    skipMissingElement: true,
    waitForElement: 1200,
    onPopoverRender: (popover) => {
      popover.nextButton.classList.add("recorrido-btn-primario");

      // «Omitir» siempre a la vista, no solo la X de la esquina. driver.js
      // rearma el popover entero en cada paso, así que el botón se vuelve a
      // poner cada vez.
      const omitir = document.createElement("button");
      omitir.type = "button";
      omitir.className = "recorrido-omitir";
      omitir.textContent = "Omitir";
      omitir.addEventListener("click", () => terminar());
      popover.footerButtons.insertBefore(omitir, popover.footerButtons.firstChild);
    },
    // Se probó primero con `onDestroyed` y no funcionó: medido en el navegador
    // (2026-10-19), cerrar con la X o con «Omitir» en el primer paso cerraba el
    // recorrido sin llamarlo, y no quedaba nada recordado. `onDestroyStarted` sí
    // se llama en esos caminos.
    onDestroyStarted: () => terminar(),
  });

  // La persona lo cerró: se recuerda y se apaga. (`destroy()` de driver.js no
  // vuelve a llamar a `onDestroyStarted`, así que no hay bucle.)
  function terminar() {
    marcarComoVisto(tourId);
    instancia.destroy();
  }

  instancia.drive();
  return () => instancia.destroy();
}

/**
 * Lanza el recorrido la primera vez que `activo` pasa a `true`, y nunca más si
 * la persona ya lo vio (ver arriba qué cuenta). Un `useRef` evita que ir y
 * volver a la misma pestaña dentro de la misma visita lo repita — "primera
 * vez" es por carga de página, no por cada clic de menú.
 *
 * La memoria de «ya corrió en esta visita» es POR RECORRIDO (`tourId`), no una
 * sola para el hook: «Lo mío» lo llama con una sección distinta cada vez que
 * se cambia de pestaña, y con una sola marca el recorrido de la primera
 * sección vista habría dejado sin recorrido a todas las demás.
 *
 * Devuelve `iniciar()`: lo lanza ahora mismo, aunque ya lo haya visto —para
 * un botón «Ver guía»—. Si hay uno en pantalla, lo reemplaza en vez de apilar
 * dos.
 */
export function useRecorridoGuiado(tourId: string, pasos: readonly PasoRecorrido[], activo: boolean) {
  const yaCorrieronRef = useRef<Set<string>>(new Set());
  const apagarRef = useRef<(() => void) | null>(null);

  useEffect(() => {
    if (!activo || pasos.length === 0 || yaCorrieronRef.current.has(tourId)) return;
    yaCorrieronRef.current.add(tourId);

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
