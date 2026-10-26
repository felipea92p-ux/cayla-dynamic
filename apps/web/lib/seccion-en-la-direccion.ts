// ============================================================================
// La sección de una pantalla, escrita en la dirección (`?tab=`)
// ============================================================================
//
// QUÉ PROMETE
//   Qué sección abrir al llegar a la pantalla y qué dirección escribir al
//   cambiar de sección, de modo que se cumplan las tres a la vez:
//     · un enlace con `?tab=<sección>` —un aviso de la Bandeja, «← Tus
//       reportes»— abre esa sección;
//     · «atrás» (el botón del navegador o el gesto del teléfono) devuelve a la
//       sección en la que estabas, no a la inicial;
//     · recargar abre SIEMPRE la sección inicial.
//
// QUÉ ASUME
//   Que la sección inicial no se escribe: su dirección es la limpia (`/mio`).
//   Y que quien llama sabe si es la primera vez que la pantalla aparece desde
//   que se cargó el documento (ver `esRecargaDeEstaDireccion`).
//
// POR QUÉ LA RECARGA ES UN CASO APARTE
//   Mirando solo la dirección, las dos últimas reglas se contradicen: la
//   dirección `/mio?tab=reportes` que deja a «atrás» volver a Reportes es la
//   misma que, al recargar, volvería a abrir Reportes. Lo que las distingue no
//   está en la dirección sino en CÓMO se llegó, y eso el navegador lo anota:
//   `performance.getEntriesByType("navigation")` dice si el documento se cargó
//   por una recarga. Este caso especial no se puede quitar rediseñando —es
//   exactamente lo que se pidió el 2026-10-06—, así que vive aquí, con sus
//   pruebas, y no repartido en la pantalla.
//
// SE ROMPE SI
//   Alguien cambia de sección sin pasar por `direccionDeSeccion` (la dirección
//   deja de decir la verdad y «atrás» vuelve a donde no estabas), o escribe la
//   dirección con `history.pushState(window.history.state, …)`: Next.js no
//   reconoce un cambio que ya trae su propio estado interno, y su router queda
//   creyendo que sigue en la dirección anterior. Siempre `null`.
// ============================================================================

/** El parámetro de la dirección donde vive la sección. */
const PARAMETRO = "tab";

/** Cómo se cargó el documento: `PerformanceNavigationTiming.type` y `.name`. */
export interface CargaDelDocumento {
  tipo: string;
  direccion: string;
}

export interface Llegada {
  /** `window.location.href` en el momento en que la pantalla aparece. */
  direccion: string;
  /** `null` si el navegador no lo informa: entonces nunca se trata como recarga. */
  carga: CargaDelDocumento | null;
  /** Si es la primera vez que esta pantalla aparece desde que se cargó el documento. */
  primeraVez: boolean;
}

/** La sección que dice la dirección, o la inicial si no dice ninguna válida. */
export function seccionDeLaDireccion<T extends string>(
  direccion: string, secciones: readonly T[], inicial: T,
): T {
  const t = new URL(direccion).searchParams.get(PARAMETRO);
  return t !== null && (secciones as readonly string[]).includes(t) ? (t as T) : inicial;
}

/** La misma dirección con la sección escrita (o borrada, si es la inicial). Conserva lo demás. */
export function direccionDeSeccion<T extends string>(direccion: string, seccion: T, inicial: T): string {
  const url = new URL(direccion);
  if (seccion === inicial) url.searchParams.delete(PARAMETRO);
  else url.searchParams.set(PARAMETRO, seccion);
  return url.href;
}

function sinAncla(direccion: string): string {
  const url = new URL(direccion);
  url.hash = "";
  return url.href;
}

/**
 * ¿Esta llegada es la recarga de esta misma pantalla? Hacen falta las tres
 * condiciones, y cada una se ganó con un caso que fallaba sin ella:
 *
 *   · el documento se cargó por una recarga — si no, es un enlace o un «atrás»;
 *   · se recargó ESTA dirección — sin esto, recargar la Bandeja y después
 *     tocar el aviso «Ver tu boleta» abriría Resumen: el documento sí salió de
 *     una recarga, pero de otra pantalla;
 *   · es la primera vez que la pantalla aparece en el documento — sin esto,
 *     recargar en Reportes, abrir un reporte y volver «atrás» abriría Resumen:
 *     la dirección vuelve a coincidir con la recargada, pero lo que pasó fue
 *     un «atrás».
 */
export function esRecargaDeEstaDireccion(llegada: Llegada): boolean {
  return llegada.primeraVez
    && llegada.carga?.tipo === "reload"
    && sinAncla(llegada.carga.direccion) === sinAncla(llegada.direccion);
}

/**
 * Qué sección abrir al llegar, y con qué dirección reemplazar la actual si no
 * dice la verdad (`null` si ya la dice): tras una recarga, con un `?tab=` mal
 * escrito o con `?tab=<la inicial>`, la dirección pasa a ser la limpia.
 */
export function seccionAlLlegar<T extends string>(
  llegada: Llegada, secciones: readonly T[], inicial: T,
): { seccion: T; reemplazarPor: string | null } {
  const seccion = esRecargaDeEstaDireccion(llegada)
    ? inicial
    : seccionDeLaDireccion(llegada.direccion, secciones, inicial);
  const verdadera = direccionDeSeccion(llegada.direccion, seccion, inicial);
  return { seccion, reemplazarPor: verdadera === new URL(llegada.direccion).href ? null : verdadera };
}
