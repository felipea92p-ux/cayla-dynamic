// Las animaciones del panel con vidrio: encendidas o quietas. Es el botón «Animaciones» de Retail (ADR-0625 de Retail, Felipe 2026-11-07).
//
// QUÉ PROMETE
//   El panel y Lo mío arrancan QUIETOS: lo que se mueve llega de una vez a su lugar. Quien quiera las animaciones las enciende con el botón de
//   la cabecera, junto al del modo oscuro, y queda recordado en ese aparato. Quieto apaga todo lo decorativo, pero NO las señales de espera
//   (el colibrí de «Guardando…», el hilo y el anillo del loader): sin ellas un guardado lento parece colgado y la persona aprieta dos veces.
//   Si el aparato pide menos movimiento (`prefers-reduced-motion`), eso gana siempre: el botón no enciende lo que el sistema apagó.
//
// QUÉ ASUME
//   Que el guion de lib/vidrio.ts puso `data-movimiento` antes de pintar, y solo en el panel. Sin el atributo —el terminal, o el vidrio
//   apagado— nada cambia: manda solo el sistema operativo, como antes de esto.
//
// DECIDÍ: seguir a Retail: preferencia del aparato, arranca quieto, una sola regla de CSS que deja toda animación en 0,01 ms (sigue llegando
//   `animationend`, así que una pieza que espera el final de la suya termina igual), y una sola pregunta desde JavaScript: `prefiereQuieto()`.
//   Una diferencia con Retail, del 2026-11-09: las TRANSICIONES quedan en 0 s, no en 0,01 ms. Con 0,01 ms, cada elemento que no pidió
//   transición (`transition-property: all` de fábrica) pasaba a transitar todo, y Safari del iPhone dejaba el menú sin palabras. El detalle,
//   en movimiento.css. Por eso nadie en apps/web puede esperar un `transitionend`: quieto, no llega (lo vigila tests/vidrio-movimiento.test.ts).
// DESCARTÉ: tocar uno por uno los bloques `prefers-reduced-motion: no-preference` de estilos/vidrio, porque son decenas y el siguiente que
//   alguien escriba se quedaría afuera sin que nada avise.
// SE ROMPE SI: una pieza anima desde JavaScript preguntando `matchMedia` por su cuenta: no vería el botón (lo vigila tests/vidrio-movimiento.test.ts).
//   O una señal de espera nueva no lleva `data-senal`: se quedaría quieta y un guardado lento parecería colgado.

export type Movimiento = "quieto" | "vivo";

export const MOVIMIENTO_POR_DEFECTO: Movimiento = "quieto";

/** Dónde se guarda lo elegido (localStorage del aparato). La misma clave que Retail: son dos sitios distintos y no se pisan. */
export const CLAVE_MOVIMIENTO = "cayla-movimiento";

/** El atributo de <html> del que cuelga el CSS que aquieta todo (estilos/vidrio/movimiento.css, al final). */
export const ATRIBUTO_MOVIMIENTO = "data-movimiento";

const PIDE_MENOS = "(prefers-reduced-motion: reduce)";

/** Lo guardado puede faltar, ser viejo o estar corrupto: todo lo que no sea «vivo» es quieto. */
export function resolverMovimiento(guardado: unknown): Movimiento {
  return guardado === "vivo" ? "vivo" : MOVIMIENTO_POR_DEFECTO;
}

export function alternarMovimiento(actual: Movimiento): Movimiento {
  return actual === "vivo" ? "quieto" : "vivo";
}

/**
 * ¿Se queda quieto? Sí si el aparato pide menos movimiento, o si la persona no encendió las animaciones. `null` es «aquí no hay botón»
 * (el terminal, o el vidrio apagado): entonces manda solo el sistema operativo.
 */
export function quedaQuieto(movimiento: Movimiento | null, sistemaPideMenos: boolean): boolean {
  return sistemaPideMenos || movimiento === "quieto";
}

/** El nombre accesible no cambia («Animaciones») y el estado va en `aria-pressed`, como el del modo oscuro. El `title` dice qué hará el clic. */
export function textosDelBotonMovimiento(actual: Movimiento): { etiqueta: string; titulo: string } {
  return { etiqueta: "Animaciones", titulo: actual === "vivo" ? "Apagar las animaciones" : "Encender las animaciones" };
}

/**
 * El trozo del guion de lib/vidrio.ts que pone el atributo en el panel antes de pintar. Siempre deja un valor puesto y, si el almacenamiento
 * falla, quieto. Es texto a propósito: la prueba lo ejecuta.
 */
export const GUION_MOVIMIENTO =
  `var mv="quieto";try{if(localStorage.getItem(${JSON.stringify(CLAVE_MOVIMIENTO)})==="vivo")mv="vivo"}catch(e){}` +
  `document.documentElement.setAttribute(${JSON.stringify(ATRIBUTO_MOVIMIENTO)},mv);`;

/** Lo que está puesto AHORA en <html>, o null si aquí no hay botón. */
export function movimientoDelDocumento(): Movimiento | null {
  if (typeof document === "undefined") return null;
  const valor = document.documentElement.getAttribute(ATRIBUTO_MOVIMIENTO);
  return valor === null ? null : resolverMovimiento(valor);
}

function sistemaPideMenos(): boolean {
  return typeof window !== "undefined" && window.matchMedia?.(PIDE_MENOS).matches === true;
}

/**
 * LA pregunta de toda pieza que anima desde JavaScript (una hoja que sale, la gota de las pestañas, un scroll suave, el vuelo del colibrí).
 * En el servidor responde quieto: no hay nada que animar.
 */
export function prefiereQuieto(): boolean {
  if (typeof window === "undefined") return true;
  return quedaQuieto(movimientoDelDocumento(), sistemaPideMenos());
}

function ponerMovimiento(movimiento: Movimiento): void {
  document.documentElement.setAttribute(ATRIBUTO_MOVIMIENTO, movimiento);
}

function leerGuardado(): Movimiento {
  try {
    return resolverMovimiento(localStorage.getItem(CLAVE_MOVIMIENTO));
  } catch {
    return MOVIMIENTO_POR_DEFECTO; // ventana privada o datos bloqueados
  }
}

/** Vuelve a poner lo guardado: al cruzar sin recargar desde el terminal al panel (components/vidrio-en-ruta.tsx). */
export function aplicarMovimientoGuardado(): void {
  ponerMovimiento(leerGuardado());
}

/** Al salir del panel sin recargar: en el terminal no hay botón, y el atributo no debe quedarse. */
export function quitarMovimiento(): void {
  document.documentElement.removeAttribute(ATRIBUTO_MOVIMIENTO);
}

/** Cambia y lo recuerda en este aparato. Sin almacenamiento (ventana privada) vale para esta carga. */
export function cambiarMovimiento(movimiento: Movimiento): void {
  ponerMovimiento(movimiento);
  try {
    localStorage.setItem(CLAVE_MOVIMIENTO, movimiento);
  } catch {
    // vale para esta carga y no se recuerda: no es un error que mostrar
  }
}

/** Para `useSyncExternalStore`: avisa cuando cambia el atributo (el botón u otra pestaña del aparato) o la preferencia del sistema. */
export function suscribirMovimiento(avisar: () => void): () => void {
  const observador = new MutationObserver(avisar);
  observador.observe(document.documentElement, { attributes: true, attributeFilter: [ATRIBUTO_MOVIMIENTO] });
  const sistema = window.matchMedia?.(PIDE_MENOS);
  sistema?.addEventListener?.("change", avisar);
  const alCambiarOtraPestana = (e: StorageEvent) => {
    if ((e.key === CLAVE_MOVIMIENTO || e.key === null) && document.documentElement.hasAttribute(ATRIBUTO_MOVIMIENTO)) {
      ponerMovimiento(resolverMovimiento(e.newValue));
    }
  };
  window.addEventListener("storage", alCambiarOtraPestana);
  return () => {
    observador.disconnect();
    sistema?.removeEventListener?.("change", avisar);
    window.removeEventListener("storage", alCambiarOtraPestana);
  };
}
