"use client";

// Lo que comparten las tres hojas con vidrio (Modal, Drawer, HojaInferior): cómo se van, qué pasa detrás, «atrás», el dedo, el teclado y los botones.
// Las usa `components/ui/hojas-vidrio.tsx`; apagado el interruptor, nada de esto corre.
//
// QUÉ PROMETE
//   · Toda hoja se va animada, también la que su pantalla desmonta de golpe.
//   · En el teléfono: «atrás» la cierra, el dedo la baja, lo de atrás se aleja y la página no se desplaza por debajo.
//   · Si la hoja es más larga que la pantalla, sus botones se quedan a la vista.
//
// QUÉ ASUME
//   Que el componente que la usa solo existe mientras la hoja está abierta: abrir es montarlo y cerrar es desmontarlo.
//
// DECIDÍ: la hoja que se va es una FOTO: una copia de sus nodos, sin vida, que anima y se borra sola.
// DESCARTÉ: mantener la hoja montada 220 ms más (como Retail o `useSalidaAnimada`), porque de 112 hojas de Dynamic hay 18 que su pantalla escribe como
//   `{x && <Modal abierto …>}`: se desmontan antes de poder animar nada. Y las demás suelen leer el dato que acaba de quedar en null (`{anulando && …}`), así
//   que se quedarían en blanco justo mientras se van. Con la foto no hay que tocar ni una pantalla y nada puede volver a guardarse durante esos 220 ms.
// SE ROMPE SI: una hoja lleva un <video> en reproducción: su copia saldría quieta. Hoy ninguna lo tiene.

import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import { alejarFondo, devolverFondo, moverFondo } from "@/lib/fondo-de-la-hoja";
import { useAtrasCierraLaHoja } from "@/lib/use-atras-cierra-la-hoja";
import { CELULAR_HOJA, useHojaArrastre } from "@/lib/use-hoja-arrastre";

/** Deben coincidir con `vidrio-hoja-sale` y `vidrio-hoja-movil-sale` en movimiento.css. */
const MS_SALIDA = 220;
const MS_SALIDA_CELULAR = 300;
/** Lo que tarda en llegar desde el borde (`vidrio-hoja-movil-entra`): lo de atrás se aleja a su ritmo. */
const MS_ENTRADA_CELULAR = 460;
/** Menos que esto no es un teclado: la barra del navegador que se esconde mueve el alto unos 50 a 80 px. */
const MIN_TECLADO = 120;

const sinMovimiento = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches;

/** Copia la hoja tal como se ve: lo escrito y el desplazamiento no viajan con `cloneNode`. Hay que llamarla mientras sigue en la pantalla. */
function tomarFoto(velo: HTMLElement): { copia: HTMLElement; desplazados: [HTMLElement, number][] } {
  const copia = velo.cloneNode(true) as HTMLElement;
  const originales = velo.querySelectorAll<HTMLElement>("*");
  const copias = copia.querySelectorAll<HTMLElement>("*");
  const desplazados: [HTMLElement, number][] = [];
  originales.forEach((el, i) => {
    const c = copias[i];
    if (el.scrollTop) desplazados.push([c, el.scrollTop]);
    if (el instanceof HTMLInputElement && c instanceof HTMLInputElement) {
      c.value = el.value;
      c.checked = el.checked;
    } else if (el instanceof HTMLTextAreaElement && c instanceof HTMLTextAreaElement) {
      c.value = el.value;
    } else if (el instanceof HTMLSelectElement && c instanceof HTMLSelectElement) {
      c.selectedIndex = el.selectedIndex;
    } else if (el instanceof HTMLCanvasElement && c instanceof HTMLCanvasElement) {
      // Una firma a medio dibujar: una copia de <canvas> nace en blanco.
      c.getContext("2d")?.drawImage(el, 0, 0);
    }
    c.removeAttribute("id");
  });
  for (const el of copia.querySelectorAll("[aria-modal], [aria-labelledby]")) {
    el.removeAttribute("aria-modal");
    el.removeAttribute("aria-labelledby");
  }
  copia.setAttribute("data-se-va", "");
  copia.setAttribute("aria-hidden", "true");
  copia.inert = true;
  return { copia, desplazados };
}

function soltarFoto({ copia, desplazados }: ReturnType<typeof tomarFoto>, ms: number) {
  document.body.appendChild(copia);
  for (const [el, y] of desplazados) el.scrollTop = y;
  window.setTimeout(() => copia.remove(), ms + 40);
}

/** Con una hoja abierta en el teléfono, la página de atrás no se desplaza. Cuenta cuántas hay: la de encima no puede devolver lo que la de abajo pidió. */
let quietas = 0;
let overflowAntes = "";
function aquietarPagina() {
  if (quietas++ === 0) {
    overflowAntes = document.body.style.overflow;
    document.body.style.overflow = "hidden";
  }
  return () => {
    if (--quietas === 0) document.body.style.overflow = overflowAntes;
  };
}

/** La última fila de la hoja, si es de botones: lo que tiene que seguir a la vista. Baja por los envoltorios y sube por los que solo la envuelven a ella. */
function buscarPie(cuerpo: Element): HTMLElement | null {
  let el = cuerpo.lastElementChild;
  for (let nivel = 0; el && nivel < 6; nivel++) {
    if (el.matches("table, .hoja, .sticky, [data-asa-hoja]")) return null;
    if (esFilaDeBotones(el)) break;
    if (!el.matches("div, form, section")) return null;
    el = el.lastElementChild;
  }
  if (!(el instanceof HTMLElement) || !esFilaDeBotones(el)) return null;
  let pie = el;
  while (pie.parentElement && pie.parentElement !== cuerpo && pie.parentElement.children.length === 1) pie = pie.parentElement;
  return pie;
}

function esFilaDeBotones(el: Element): boolean {
  if (!el.matches(".flex, .grid")) return false;
  const hijos = Array.from(el.children);
  const accionables = hijos.filter((h) => h.matches("button, a[href]"));
  if (accionables.length === 0 || accionables.length > 4) return false;
  if (!accionables.some((h) => h.matches(".rounded-control, .bg-tinta"))) return false;
  return hijos.every((h) => h.matches("button, a[href], span, p")) && !el.querySelector("input, select, textarea");
}

function quitarPie(pie: HTMLElement) {
  pie.removeAttribute("data-pie-hoja");
  pie.removeAttribute("data-hoja-corre");
  for (const v of ["--pie-izq", "--pie-der", "--pie-abajo"]) pie.style.removeProperty(v);
}

/** Marca el pie y le dice cuánto le falta para llegar al borde de la hoja. Sin hoja que corra, no se pega ni se pinta: no hay nada que tape. */
function usePieALaVista(hoja: React.RefObject<HTMLElement | null>) {
  useEffect(() => {
    const raiz = hoja.current;
    if (!raiz) return;
    const cuerpo = raiz.matches(".overflow-y-auto") ? raiz : raiz.querySelector<HTMLElement>(":scope > .overflow-y-auto");
    if (!cuerpo) return;
    let actual: HTMLElement | null = null;
    let cuadro = 0;
    const ajustar = () => {
      cuadro = 0;
      const pie = buscarPie(cuerpo);
      if (pie !== actual) {
        if (actual) quitarPie(actual);
        actual = pie;
      }
      if (!pie) return;
      if (!pie.hasAttribute("data-pie-hoja")) {
        const c = cuerpo.getBoundingClientRect();
        const p = pie.getBoundingClientRect();
        // La hoja puede estar entrando, todavía achicada: las medidas se llevan a su tamaño real.
        const escala = c.width / cuerpo.offsetWidth || 1;
        pie.style.setProperty("--pie-izq", `${Math.max(0, (p.left - c.left) / escala - cuerpo.clientLeft)}px`);
        pie.style.setProperty("--pie-der", `${Math.max(0, (c.right - p.right) / escala - (cuerpo.offsetWidth - cuerpo.clientWidth - cuerpo.clientLeft))}px`);
        pie.style.setProperty("--pie-abajo", getComputedStyle(cuerpo).paddingBottom);
        pie.setAttribute("data-pie-hoja", "");
      }
      pie.toggleAttribute("data-hoja-corre", cuerpo.scrollHeight > cuerpo.clientHeight + 1);
    };
    const pedir = () => {
      if (!cuadro) cuadro = requestAnimationFrame(ajustar);
    };
    ajustar();
    const cambios = new MutationObserver(pedir);
    cambios.observe(cuerpo, { childList: true, subtree: true });
    const tamano = new ResizeObserver(pedir);
    tamano.observe(cuerpo);
    return () => {
      cancelAnimationFrame(cuadro);
      cambios.disconnect();
      tamano.disconnect();
    };
  }, [hoja]);
}

/**
 * Con el teclado arriba, abrirlo no achica la página: solo lo que se ve. La hoja pegada abajo quedaría tapada, con su botón y con el campo donde se
 * escribe. Así que el velo empieza en el borde de arriba de lo visible y la hoja reserva, con relleno, lo que tapa el teclado (reglas en movimiento.css).
 * Viene de Retail (useHojaSobreElTeclado): no se pega al borde de abajo de lo visible porque hay navegadores de Android que reportan ese alto corto.
 */
function useHojaSobreElTeclado(velo: React.RefObject<HTMLElement | null>) {
  useEffect(() => {
    const vv = window.visualViewport;
    if (!vv) return;
    let conTeclado = false;
    let tocado: HTMLElement | null = null;
    const soltar = () => {
      tocado?.style.removeProperty("top");
      tocado?.style.removeProperty("--teclado");
      tocado?.style.removeProperty("--alto-pie");
      tocado?.removeAttribute("data-teclado");
      tocado = null;
    };
    const ajustar = () => {
      const el = velo.current;
      if (!el) return;
      const teclado = window.innerHeight - vv.height;
      if (vv.scale > 1.01 || teclado < MIN_TECLADO) {
        if (conTeclado) soltar();
        conTeclado = false;
        return;
      }
      tocado = el;
      el.style.top = `${vv.offsetTop}px`;
      el.style.setProperty("--teclado", `${Math.max(0, Math.round(window.innerHeight - vv.offsetTop - vv.height))}px`);
      el.setAttribute("data-teclado", "");
      el.style.setProperty("--alto-pie", `${el.querySelector<HTMLElement>("[data-pie-hoja]")?.offsetHeight ?? 0}px`);
      // Solo al subir el teclado: después, quien escribe puede desplazar la hoja sin que se la devuelvan al campo.
      if (!conTeclado) {
        const foco = document.activeElement;
        if (foco instanceof HTMLElement && el.contains(foco)) requestAnimationFrame(() => foco.scrollIntoView({ block: "nearest" }));
      }
      conTeclado = true;
    };
    // Un campo que recibe el foco con el teclado arriba queda a la vista por encima del pie.
    const alEnfocar = (e: FocusEvent) => {
      const el = velo.current;
      const campo = e.target;
      if (!conTeclado || !el || !(campo instanceof HTMLElement) || !el.contains(campo) || campo.closest("[data-pie-hoja]")) return;
      requestAnimationFrame(() => campo.scrollIntoView({ block: "nearest" }));
    };
    ajustar();
    document.addEventListener("focusin", alEnfocar);
    vv.addEventListener("resize", ajustar);
    vv.addEventListener("scroll", ajustar);
    window.addEventListener("resize", ajustar);
    return () => {
      document.removeEventListener("focusin", alEnfocar);
      vv.removeEventListener("resize", ajustar);
      vv.removeEventListener("scroll", ajustar);
      window.removeEventListener("resize", ajustar);
      soltar();
    };
  }, [velo]);
}

export function useHojaViva({ onCerrar, bloqueado = false }: { onCerrar: () => void; bloqueado?: boolean }) {
  const velo = useRef<HTMLDivElement>(null);
  const hoja = useRef<HTMLDivElement | null>(null);
  const fondo = useRef<symbol | null>(null);
  const vive = useRef(false);
  const salioConElDedo = useRef(false);
  const reloj = useRef<number | undefined>(undefined);
  const cerrar = useRef(onCerrar);
  useEffect(() => {
    cerrar.current = onCerrar;
  });

  // Se lee al abrir: girar el teléfono con la hoja abierta no cambia quién cierra con «atrás».
  const [enCelular] = useState(() => typeof window !== "undefined" && window.matchMedia(CELULAR_HOJA).matches);
  useAtrasCierraLaHoja(enCelular, () => {
    if (!bloqueado) cerrar.current();
  });

  const arrastre = useHojaArrastre({
    bloqueado,
    velo,
    alSalir: (ms) => {
      salioConElDedo.current = true;
      devolverFondo(fondo.current, ms);
      reloj.current = window.setTimeout(() => cerrar.current(), ms);
    },
    alMoverse: (progreso, ms) => moverFondo(fondo.current, progreso, ms),
  });
  const ponerHoja = useCallback(
    (el: HTMLDivElement | null) => {
      hoja.current = el;
      arrastre.enlazar(el);
    },
    [arrastre],
  );

  useLayoutEffect(() => {
    vive.current = true;
    const nodo = velo.current;
    const quieta = !sinMovimiento();
    const llave = enCelular && quieta ? alejarFondo(MS_ENTRADA_CELULAR) : null;
    fondo.current = llave;
    const soltarPagina = enCelular ? aquietarPagina() : null;
    return () => {
      vive.current = false;
      window.clearTimeout(reloj.current);
      soltarPagina?.();
      const ms = sinMovimiento() ? 0 : window.matchMedia(CELULAR_HOJA).matches ? MS_SALIDA_CELULAR : MS_SALIDA;
      devolverFondo(llave, ms);
      fondo.current = null;
      if (!nodo || !ms || salioConElDedo.current) return;
      const foto = tomarFoto(nodo);
      // React, en desarrollo, desmonta y vuelve a montar todo una vez para probarlo: ese desmontaje de mentira no debe dejar una foto encima.
      queueMicrotask(() => {
        if (!vive.current) soltarFoto(foto, ms);
      });
    };
  }, [enCelular]);

  usePieALaVista(hoja);
  useHojaSobreElTeclado(velo);

  return { velo, hoja, ponerHoja };
}
