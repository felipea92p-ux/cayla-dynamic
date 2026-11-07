// «Atrás» cierra la hoja de arriba: las decisiones, sin navegador. Viene de Retail (lib/hojas-atras.ts, ADR-0528); quien toca `window.history`
// es `use-atras-cierra-la-hoja.ts`.
//
// QUÉ PROMETE
//   En el teléfono, cada hoja abierta deja una entrada en el historial con la MISMA dirección y su marca. Estas funciones dicen qué hacer con esas
//   entradas: solo la hoja de ARRIBA responde a «atrás» (un «atrás» = una hoja), una hoja que se cerró por otro lado devuelve su entrada, y una
//   entrada que quedó enterrada bajo otra pantalla se salta, para que «atrás» lleve a una pantalla y no a un paso vacío.
//
// QUÉ ASUME
//   Nada del navegador: reciben listas de ids y páginas. Por eso se pueden probar solas (tests/hojas-atras.test.ts).

/** La marca de la entrada de una hoja en `history.state`: guarda su id. */
export const MARCA_HOJA = "__hojaAbierta";

/** Una hoja que pidió cerrar con «atrás»: su id y la página (pathname) donde se abrió. */
export type HojaEnPila = { id: string; pagina: string };

export type AlVolver =
  /** No es un «atrás» sobre una hoja: el router sigue como siempre. */
  | "nada"
  /** Se salió de la entrada de la hoja de arriba: se pide cerrarla y nadie más se entera. */
  | "cerrar"
  /** Se volvió a una entrada huérfana: la pantalla se dibuja y la entrada se salta hacia atrás. */
  | "saltar";

/**
 * Qué hacer con un `popstate`, mirando a dónde se llegó. Se compara por página y no por dirección entera: una pantalla que cambia sus filtros mueve
 * la parte de la consulta de la entrada de la hoja, y seguir siendo la misma pantalla es lo que importa.
 */
export function decidirAlVolver(e: {
  /** La marca de la entrada a la que se llegó (`null` si no tiene). */
  marca: string | null;
  pagina: string;
  /** La página desde la que se llegó (la última que se vio). */
  paginaAntes: string;
  arriba: HojaEnPila | null;
  abiertas: readonly string[];
  /**
   * Esta entrada quedó enterrada por un cambio dentro de la misma página: las secciones de Lo mío, que cambian la dirección sin cambiar de pantalla.
   * Retail no lo necesita: sus pantallas no hacen eso. Sin esto, elegir una sección desde el menú del teléfono dejaba un «atrás» que no hacía nada.
   */
  enterrada?: boolean;
}): AlVolver {
  if (e.arriba) {
    // Se llegó a la entrada de la hoja de arriba (volviendo de una página abierta encima de ella): nada que cerrar.
    if (e.marca === e.arriba.id) return "nada";
    // Fue a otra pantalla (varios pasos de una vez, o «adelante»): no es un «atrás» sobre la hoja.
    if (e.pagina !== e.arriba.pagina) return "nada";
    return "cerrar";
  }
  if (!e.marca || e.abiertas.includes(e.marca)) return "nada";
  // Huérfana en la misma pantalla (se llegó con «adelante», o tras recargar): no se sabe hacia dónde saltar; se deja.
  return e.pagina !== e.paginaAntes || e.enterrada ? "saltar" : "nada";
}

/** Cuántas entradas de arriba se retiran: las de hojas que ya cerraron, hasta la primera que sigue abierta. */
export function cuantasRetirar(entradas: readonly string[], abiertas: readonly string[]): number {
  let n = 0;
  while (n < entradas.length && !abiertas.includes(entradas[entradas.length - 1 - n])) n++;
  return n;
}

/** Las hojas abiertas que todavía no tienen su entrada, en el orden de la pila, solo las de la página donde se está. */
export function cualesPoner(pila: readonly HojaEnPila[], entradas: readonly string[], pagina: string): HojaEnPila[] {
  return pila.filter((h) => !entradas.includes(h.id) && h.pagina === pagina);
}

/**
 * ¿Un `replaceState` conserva la marca de la hoja? Next reescribe el estado de la entrada en cada `router.refresh()` sin copiar lo ajeno: sin esto,
 * guardar dentro de una hoja le borraba su marca y su entrada quedaba vacía, pidiendo un «atrás» de más. Solo si sigue siendo la misma página: si un
 * `router.replace` lleva a otra, la entrada ya es de esa otra pantalla.
 */
export function conservaMarca(paginaActual: string, paginaNueva: string): boolean {
  return paginaActual === paginaNueva;
}
