// El tema con el vidrio encendido: claro u oscuro, y nada más.
//
// QUÉ PROMETE
//   Arranca en claro y solo cambia cuando alguien pulsa el botón. Lo elegido se recuerda en este aparato. Lo guardado que no sea
//   «oscuro» —ausente, viejo como «sistema», corrupto— es claro.
//
// QUÉ ASUME
//   Que el guion de lib/vidrio.ts ya puso `data-tema` antes de pintar. Usa la misma clave que `use-tema.ts`, así que quien hoy
//   eligió oscuro a mano sigue en oscuro el día del estreno.
//
// DECIDÍ: seguir a Retail: el tema es de cada aparato, y ni el sistema operativo ni /admin/apariencia mandan sobre el panel.
// DESCARTÉ: reutilizar `useTema`, porque sus tres estados y su lectura de la configuración global son lo que se está dejando atrás,
//   y mezclarlos obligaría a un `if` por cada rama. El día del estreno se borra el otro.
// SE ROMPE SI: alguien espera que /admin/apariencia cambie el panel. Con el vidrio encendido ya no lo hace: sigue mandando solo
//   sobre el terminal, hasta que el terminal tenga su módulo.

export type TemaVidrio = "claro" | "oscuro";

export const CLAVE_TEMA = "cayla-tema";
const ATRIBUTO_TEMA = "data-tema";

/** El color de la barra del navegador en el teléfono: el de la página en cada tema. */
export const COLOR_BARRA: Record<TemaVidrio, string> = { claro: "#f5f0e8", oscuro: "#1c1a17" };

export function resolverTema(guardado: unknown): TemaVidrio {
  return guardado === "oscuro" ? "oscuro" : "claro";
}

export function alternarTema(actual: TemaVidrio): TemaVidrio {
  return actual === "oscuro" ? "claro" : "oscuro";
}

/** El nombre accesible no cambia y el estado va en `aria-pressed`. El `title` sí dice qué hará el clic. */
export function textosDelBoton(actual: TemaVidrio): { etiqueta: string; titulo: string } {
  return { etiqueta: "Modo oscuro", titulo: actual === "oscuro" ? "Cambiar a modo claro" : "Cambiar a modo oscuro" };
}

export function temaDelDocumento(): TemaVidrio {
  return resolverTema(document.documentElement.getAttribute(ATRIBUTO_TEMA));
}

function leerGuardado(): TemaVidrio {
  try {
    return resolverTema(localStorage.getItem(CLAVE_TEMA));
  } catch {
    return "claro"; // ventana privada o datos bloqueados: vale para esta carga
  }
}

function ponerTema(tema: TemaVidrio): void {
  document.documentElement.setAttribute(ATRIBUTO_TEMA, tema);
  document.querySelector('meta[name="theme-color"]')?.setAttribute("content", COLOR_BARRA[tema]);
}

/** Vuelve a poner el tema guardado: al cruzar sin recargar desde una pantalla que no sigue estas reglas. */
export function aplicarTemaGuardado(): void {
  ponerTema(leerGuardado());
}

/** Cambia el tema y lo recuerda. Con la API de transiciones la página se funde en 280 ms; sin ella o con movimiento reducido, al instante. */
export function cambiarTema(tema: TemaVidrio): void {
  if (tema === temaDelDocumento()) return;
  const aplicar = () => {
    ponerTema(tema);
    try {
      localStorage.setItem(CLAVE_TEMA, tema);
    } catch {
      // vale para esta carga y no se recuerda: no es un error que mostrar
    }
  };
  const sinMovimiento = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false;
  type Transicion = { ready?: Promise<unknown>; finished?: Promise<unknown>; updateCallbackDone?: Promise<unknown> };
  const conTransicion = document as Document & { startViewTransition?: (cuando: () => void) => Transicion };
  if (sinMovimiento || typeof conTransicion.startViewTransition !== "function") {
    aplicar();
    return;
  }
  const transicion = conTransicion.startViewTransition(aplicar);
  // El navegador rechaza estas promesas si aborta la transición. El tema ya quedó puesto: que se salte el fundido no es un error.
  for (const promesa of [transicion?.ready, transicion?.finished, transicion?.updateCallbackDone]) promesa?.catch(() => {});
}

/** Para `useSyncExternalStore`: avisa cuando cambia el atributo, por el botón o porque otra pestaña del aparato cambió el tema. */
export function suscribirTema(avisar: () => void): () => void {
  const observador = new MutationObserver(avisar);
  observador.observe(document.documentElement, { attributes: true, attributeFilter: [ATRIBUTO_TEMA] });
  const alCambiarOtraPestana = (e: StorageEvent) => {
    if (e.key === CLAVE_TEMA || e.key === null) ponerTema(resolverTema(e.newValue));
  };
  window.addEventListener("storage", alCambiarOtraPestana);
  return () => {
    observador.disconnect();
    window.removeEventListener("storage", alCambiarOtraPestana);
  };
}
