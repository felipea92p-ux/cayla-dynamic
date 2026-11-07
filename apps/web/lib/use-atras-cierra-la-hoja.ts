"use client";

// En el teléfono, el botón «atrás» y el gesto desde el borde son la forma natural de quitarse una hoja de encima. Sin esto, «atrás» dejaba la hoja
// abierta y llevaba a la pantalla anterior. Viene de Retail (components/ui/useAtrasCierraLaHoja.ts, ADR-0528); las decisiones, con su prueba, están en
// `hojas-atras.ts`.
//
// QUÉ PROMETE
//   Una pila para todo el sistema: cada hoja abierta, en orden, con una entrada de historial con la MISMA dirección y su marca. Solo la de arriba
//   responde. «Atrás» consume esa entrada y pide el cierre por la misma puerta de siempre. Una hoja que se cierra por otro lado (Cancelar, Escape, el
//   dedo, guardar) deja de estar en la pila y su entrada se retira con un «atrás» propio. Todo se reconcilia en `sincronizar`, una vez por tarea.
//
// QUÉ ASUME
//   Que el `popstate` de un «atrás» propio y el de una hoja se pueden cortar en la captura de `window`: la dirección no cambió, y el router de Next, si
//   restaurara el árbol de la entrada de abajo, podría volver a montar la pantalla entera.
//
// DECIDÍ: esperar el cambio de pantalla antes de retirar la entrada cuando se tocó un enlace a otra pantalla. Tocar un destino del menú cierra el cajón
//   y navega a la vez. Si la entrada se retirara en ese instante, el «atrás» propio llegaría DESPUÉS del `pushState` de la pantalla nueva y devolvería la
//   dirección a la pantalla de antes, con la nueva dibujada. Retail convive con esa carrera; aquí se cierra: el enlace enciende una espera.
// DESCARTÉ: que cada pantalla avise antes de navegar, porque son 94 hojas y el olvido no se notaría hasta que le pasara a alguien.
// SE ROMPE SI: una hoja navega con `router.push` desde un botón (no un enlace) en el mismo instante en que se cierra: esa carrera sigue, y el síntoma
//   sería una dirección que no coincide con lo que se ve hasta el siguiente clic.
//
// El módulo se engancha a `history` al cargarse, así que está detrás del interruptor: apagado, el historial de producción no se toca.

import { useEffect, useId, useRef } from "react";
import { MARCA_HOJA, conservaMarca, cualesPoner, cuantasRetirar, decidirAlVolver, type HojaEnPila } from "@/lib/hojas-atras";
import { interruptoresVidrio } from "@/lib/vidrio";

type Hoja = HojaEnPila & { pedirCierre: () => void };

/** Distinto en cada carga: una entrada que sobrevive a una recarga no se confunde con la de una hoja nueva. */
const SESION = `-${Date.now().toString(36)}`;
/** Lo que se le da a una pantalla para llegar después de tocar su enlace. Si tarda más, la entrada se retira igual. */
const ESPERA_NAVEGACION_MS = 1500;

let pila: Hoja[] = [];
/** Las entradas nuestras que siguen en el historial, de abajo arriba. */
let entradas: string[] = [];
/** Las enterradas por un cambio dentro de la misma página (las secciones de Lo mío). */
const enterradas = new Set<string>();
/** Un «atrás» propio en camino: su `popstate` se corta y, al llegar, se vuelve a sincronizar. */
let enCamino = false;
/** Saltando entradas huérfanas: se sigue mientras se caiga en otra. */
let saltando = false;
let respaldo: number | undefined;
let programado = false;
let navegandoHasta = 0;
let urlConocida = typeof window === "undefined" ? "" : window.location.href;

const paginaDe = (url: string) => {
  try {
    return new URL(url).pathname;
  } catch {
    return url;
  }
};
const paginaActual = () => window.location.pathname;
const marcaActual = (): string | null => {
  const m = (window.history.state as Record<string, unknown> | null)?.[MARCA_HOJA];
  return typeof m === "string" ? m : null;
};
const abiertas = () => pila.map((h) => h.id);

/** El estado de la entrada nueva: el de Next, para que su router no pierda el árbol, con la marca de la hoja. */
function estadoConMarca(id: string) {
  return { ...(window.history.state ?? {}), [MARCA_HOJA]: id };
}

function irAtras(n: number) {
  enCamino = true;
  window.clearTimeout(respaldo);
  // Si el navegador no estaba en condiciones de volver (el primer paso del historial), el `popstate` no llega: no se espera para siempre.
  respaldo = window.setTimeout(() => {
    if (!enCamino) return;
    enCamino = false;
    saltando = false;
    programar();
  }, 1000);
  window.history.go(-n);
}

function sincronizar() {
  programado = false;
  if (enCamino) return;
  const falta = navegandoHasta - performance.now();
  if (falta > 0) {
    window.setTimeout(programar, Math.min(falta, 100));
    return;
  }
  const ultima = entradas[entradas.length - 1];
  if (ultima !== undefined && marcaActual() !== ultima) {
    // Encima de nuestras entradas hay otra: se navegó con hojas abiertas. Con la pila vacía, las de debajo son huérfanas y se olvidan (el `popstate`
    // las salta si se vuelve a ellas); con hojas abiertas, no se toca nada hasta volver.
    if (pila.length === 0) {
      for (const id of entradas) enterradas.add(id);
      entradas = [];
    }
    return;
  }
  const n = cuantasRetirar(entradas, abiertas());
  if (n > 0) {
    entradas = entradas.slice(0, entradas.length - n);
    irAtras(n);
    return;
  }
  for (const h of cualesPoner(pila, entradas, paginaActual())) {
    window.history.pushState(estadoConMarca(h.id), "", window.location.href);
    entradas.push(h.id);
  }
}

/** Una vez por tarea: abrir y cerrar en el mismo instante (una hoja que reemplaza a otra) se resuelve junto. */
function programar() {
  if (programado) return;
  programado = true;
  window.setTimeout(sincronizar, 0);
}

function alVolver(e: PopStateEvent) {
  const paginaAntes = paginaDe(urlConocida);
  urlConocida = window.location.href;
  navegandoHasta = 0;
  if (enCamino) {
    enCamino = false;
    window.clearTimeout(respaldo);
    e.stopImmediatePropagation();
    // Se cayó en otra huérfana: se sigue saltando.
    const m = marcaActual();
    if (saltando && m && !abiertas().includes(m)) return irAtras(1);
    saltando = false;
    programar();
    return;
  }
  const arriba = pila[pila.length - 1] ?? null;
  const marca = marcaActual();
  const decision = decidirAlVolver({ marca, pagina: paginaActual(), paginaAntes, arriba, abiertas: abiertas(), enterrada: marca ? enterradas.has(marca) : false });
  if (decision === "cerrar" && arriba) {
    e.stopImmediatePropagation();
    // La entrada de la hoja quedó adelante: se descuenta. Si la hoja no se cierra (está guardando), `sincronizar` se la devuelve.
    const i = marca ? entradas.indexOf(marca) : -1;
    entradas = entradas.slice(0, i + 1);
    arriba.pedirCierre();
    programar();
  } else if (decision === "saltar") {
    if (marca) enterradas.delete(marca);
    // Esta vuelta es de verdad: la pantalla se dibuja. Después se salta la entrada vacía, hacia atrás.
    window.setTimeout(() => {
      if (enCamino) return;
      saltando = true;
      irAtras(1);
    }, 0);
  }
}

/** Tocar un enlace a otra pantalla: la entrada de una hoja que se cierra con ese toque espera a que la pantalla nueva llegue. */
function alTocarEnlace(e: MouseEvent) {
  if (e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
  const enlace = e.target instanceof Element ? e.target.closest("a[href]") : null;
  if (!(enlace instanceof HTMLAnchorElement) || enlace.target === "_blank" || enlace.origin !== window.location.origin) return;
  if (enlace.pathname !== paginaActual()) navegandoHasta = performance.now() + ESPERA_NAVEGACION_MS;
}

if (typeof window !== "undefined" && interruptoresVidrio().panel) {
  window.addEventListener("popstate", alVolver, { capture: true });
  document.addEventListener("click", alTocarEnlace, { capture: true });
  // Se envuelven los dos métodos para saber la última dirección vista y para que un `replaceState` de la misma página no le borre la marca a la entrada
  // de una hoja (`conservaMarca`). Funciona en cualquier orden con el parche que Next pone a los mismos métodos.
  const empujar = window.history.pushState.bind(window.history);
  const reemplazar = window.history.replaceState.bind(window.history);
  window.history.pushState = function pushState(data, unused, url) {
    const r = empujar(data, unused, url);
    urlConocida = window.location.href;
    if (navegandoHasta) {
      navegandoHasta = 0;
      programar();
    }
    return r;
  };
  window.history.replaceState = function replaceState(data, unused, url) {
    const marca = marcaActual();
    const destino = url == null ? window.location.href : new URL(String(url), window.location.href).href;
    if (marca && data && typeof data === "object" && !(MARCA_HOJA in data) && conservaMarca(paginaActual(), paginaDe(destino))) {
      data = { ...data, [MARCA_HOJA]: marca };
    }
    const r = reemplazar(data, unused, url);
    urlConocida = window.location.href;
    return r;
  };
}

/** La hoja entra a la pila mientras `activo`, y `pedirCierre` es su puerta de siempre. Al dejar de estar activa, sale de la pila y su entrada se retira. */
export function useAtrasCierraLaHoja(activo: boolean, pedirCierre: () => void) {
  const id = `hoja${useId()}${SESION}`;
  const pedirCierreActual = useRef(pedirCierre);
  useEffect(() => {
    pedirCierreActual.current = pedirCierre;
  }, [pedirCierre]);

  useEffect(() => {
    if (!activo) return;
    pila = [...pila.filter((h) => h.id !== id), { id, pagina: paginaActual(), pedirCierre: () => pedirCierreActual.current() }];
    programar();
    return () => {
      pila = pila.filter((h) => h.id !== id);
      programar();
    };
  }, [activo, id]);
}
