// Lo de atrás se aleja. Con una hoja abierta en el teléfono, la pantalla se aleja a 0,92, baja 12 px y su cabecera se redondea: se lee como una
// tarjeta que sigue ahí, debajo. Mientras el dedo baja la hoja, vuelve a su lugar al mismo ritmo. Viene de Retail (components/ui/fondoDeLaHoja.ts).
//
// QUÉ PROMETE
//   Una sola hoja a la vez es la dueña del efecto: la que se abre encima de otra no aleja nada más. Al terminar no queda ningún estilo puesto.
//
// QUÉ ASUME
//   Que lo que se aleja lleva `data-fondo-hoja`: la cabecera con `="borde"` y el contenido (los pone `components/vidrio/marco.tsx`). Y que las hojas
//   cuelgan de <body>: un `transform` vuelve relativo a su contenedor a todo lo `fixed` de adentro. Lo `fixed` que sí vive adentro («sin conexión», un
//   aviso) se esconde mientras la hoja está abierta, porque se ubicaría mal, y al volver aparece con un fundido corto.

import { fondoDeLadoSegun, fondoSegun } from "@/lib/hoja-gesto";

type Forma = "abajo" | "lado";

const CAPAS = "[data-fondo-hoja]";

let duena: symbol | null = null;
let forma: Forma = "abajo";
let capas: HTMLElement[] = [];
/** De costado: cuánto de cada capa queda fuera de la pantalla arriba y abajo (el recorte redondeado es lo que se ve). */
let fuera = new Map<HTMLElement, { arriba: number; abajo: number }>();
let escondidos: HTMLElement[] = [];
let reloj: ReturnType<typeof setTimeout> | undefined;

function pintar(progreso: number, ms: number, curva = "var(--ease-cayla)") {
  const t = ms ? `${ms}ms ${curva}` : "0ms";
  if (forma === "lado") {
    const { escala, corrida, radio } = fondoDeLadoSegun(progreso);
    for (const el of capas) {
      el.style.transition = `transform ${t}, clip-path ${t}`;
      el.style.transform = `translate3d(${corrida}px, 0, 0) scale(${escala})`;
      const f = fuera.get(el);
      if (f) el.style.clipPath = `inset(${f.arriba}px 0 ${f.abajo}px 0 round ${radio}px)`;
    }
    return;
  }
  const { escala, bajada, radio } = fondoSegun(progreso);
  for (const el of capas) {
    el.style.transition = `transform ${t}, border-radius ${t}`;
    el.style.transform = `translate3d(0, ${bajada}px, 0) scale(${escala})`;
    if (el.dataset.fondoHoja === "borde") {
      el.style.borderTopLeftRadius = `${radio}px`;
      el.style.borderTopRightRadius = `${radio}px`;
    }
  }
}

/** Lo `fixed` dentro de una capa, sin mirar el estilo de cada nodo: un elemento fijo no tiene `offsetParent`. */
function fijosDentro(raices: HTMLElement[]): HTMLElement[] {
  const fijos: HTMLElement[] = [];
  for (const raiz of raices) {
    for (const el of raiz.querySelectorAll("*")) {
      if (el instanceof HTMLElement && el.offsetParent === null && el.getClientRects().length > 0 && getComputedStyle(el).position === "fixed") fijos.push(el);
    }
  }
  return fijos;
}

function soltarTodo() {
  clearTimeout(reloj);
  for (const el of capas) {
    el.removeAttribute("data-fuera-de-pantalla");
    for (const p of ["transition", "transform", "transform-origin", "will-change", "clip-path", "border-top-left-radius", "border-top-right-radius"]) el.style.removeProperty(p);
  }
  for (const el of escondidos) {
    el.style.removeProperty("visibility");
    el.animate?.([{ opacity: 0 }, { opacity: 1 }], { duration: 220, easing: "cubic-bezier(0.32, 0.72, 0.24, 1)" });
  }
  capas = [];
  escondidos = [];
  fuera = new Map();
}

/** Aleja lo de atrás en `ms` y devuelve la llave de quien lo hizo, o `null` si ya hay otra dueña o no hay nada que alejar (el login, por ejemplo). */
export function alejarFondo(ms: number, de: Forma = "abajo"): symbol | null {
  if (duena) return null;
  soltarTodo();
  capas = [...document.querySelectorAll<HTMLElement>(CAPAS)];
  if (capas.length === 0) return null;
  forma = de;
  // ANTES de tocar los estilos: un `will-change: transform` ya vuelve a la capa contenedora de lo fijo de adentro, y eso dejaría de verse como fijo.
  escondidos = fijosDentro(capas);
  const centro = window.innerWidth / 2;
  for (const el of capas) {
    const r = el.getBoundingClientRect();
    el.style.willChange = "transform";
    // Mientras está alejado, lo de atrás está fuera de juego: es lo que dice este atributo a `responsive:check`, que si no lo tomaría por algo que se sale del borde.
    el.setAttribute("data-fuera-de-pantalla", "");
    if (de === "lado") {
      if (el.dataset.fondoHoja === "borde") {
        // La cabecera se aleja alrededor de su propio centro izquierdo: se queda arriba.
        el.style.transformOrigin = "0 50%";
      } else {
        el.style.transformOrigin = `${-r.left}px ${window.innerHeight / 2 - r.top}px`;
        fuera.set(el, { arriba: Math.max(0, Math.round(-r.top)), abajo: Math.max(0, Math.round(r.bottom - window.innerHeight)) });
      }
      continue;
    }
    el.style.transformOrigin = `${centro - r.left}px ${-r.top}px`;
    // Lo que quedaba justo arriba de la pantalla (con la página bajada) asomaría sobre la cabecera al achicarse: se recorta.
    if (el.dataset.fondoHoja !== "borde" && r.top < 0) el.style.clipPath = `inset(${Math.round(-r.top)}px 0 0 0)`;
  }
  for (const el of escondidos) el.style.visibility = "hidden";
  duena = Symbol("hoja");
  pintar(1, 0);
  void document.body.offsetWidth;
  pintar(0, ms);
  return duena;
}

/** Mientras el dedo lleva la hoja: lo de atrás sigue su progreso (0 abierta, 1 cerrada). */
export function moverFondo(llave: symbol | null, progreso: number, ms: number) {
  if (!llave || llave !== duena) return;
  pintar(progreso, ms);
}

/** La hoja se va: lo de atrás vuelve en `ms` y después queda sin ningún estilo puesto. */
export function devolverFondo(llave: symbol | null, ms: number, curva?: string) {
  if (!llave || llave !== duena) return;
  duena = null;
  pintar(1, ms, curva);
  clearTimeout(reloj);
  reloj = setTimeout(soltarTodo, ms + 20);
}
