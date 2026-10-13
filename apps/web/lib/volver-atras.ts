// ============================================================================
// «← Volver» que de verdad vuelve (y no abre una página nueva)
// ============================================================================
//
// QUÉ PROMETE
//   `elDestinoEsLaPaginaAnterior(destino)` dice si tocar un enlace «volver» a
//   `destino` equivale exactamente a usar «atrás». Si es así, el enlace llama a
//   `router.back()`: la página de la que vienes sale del historial y el
//   «atrás» siguiente ya no te devuelve al reporte que acabas de cerrar. Si no
//   es así, el enlace navega como cualquier otro: nunca saca a nadie de la app.
//
// QUÉ ASUME
//   Que alguien avisa cada cambio de dirección (`alCambiarLaDireccion`) y cada
//   retroceso por el historial (`porHistorial`), en el orden que sea: el aviso
//   del retroceso puede llegar antes o después de que la dirección ya esté
//   anotada. Lo hace `SeguirRuta`, montado en el layout de «Lo mío».
//
// POR QUÉ NO BASTA CON `router.back()` A SECAS
//   Quien abre `/mio/reportes/nuevo` pegando la dirección, o desde un enlace de
//   fuera, no tiene nada de la app detrás: `back()` lo mandaría a donde estaba
//   antes —otro sitio—, y un «Cancelar» que te saca de la app es peor que el
//   que abría una página nueva. `history.length` tampoco sirve: cuenta lo que
//   hubo antes de la app. Solo la propia app sabe de dónde llegó.
//
// POR QUÉ UN RETROCESO BORRA LO QUE SE SABE
//   Tras un «atrás» o un «adelante» ya no se sabe qué hay detrás: A → B → C,
//   «atrás» hasta B, y la página anterior que se había anotado (C) no es la que
//   está en el historial (A). Fiarse de esa nota llevaría a otra parte. Se
//   olvida y el enlace navega normal. Es lo conservador: lo peor que pasa es
//   que ese enlace abra una página en vez de retroceder, como hasta hoy.
//
// SE ROMPE SI
//   Alguien cambia la dirección con `history.pushState` sin pasar por Next
//   (`SeguirRuta` lo notaría igual por `usePathname`, salvo que la dirección
//   nueva tenga la misma ruta y los mismos parámetros), o monta `SeguirRuta`
//   fuera del layout, donde no vería la primera dirección.
// ============================================================================

let actual: string | null = null;
let anterior: string | null = null;

/** Ruta y parámetros de una dirección, sin el servidor ni el ancla. */
function aRuta(direccion: string): URL {
  return new URL(direccion, "https://cayla.invalid");
}

/**
 * La dirección de la pantalla cambió. `porHistorial` es `true` si fue por
 * «atrás» o «adelante»: ahí no se sabe qué hay detrás, y se olvida.
 */
export function alCambiarLaDireccion(direccion: string, porHistorial = false): void {
  if (porHistorial) {
    // Sin el atajo de «misma dirección»: en un retroceso Next vuelve a pintar
    // ANTES de que llegue `popstate` (medido el 2026-10-06: 27 ms antes), y para
    // entonces el efecto ya anotó la dirección como una navegación más. Aquí se
    // borra lo que se sabía aunque ya esté anotada, venga primero lo que venga.
    anterior = null;
    actual = direccion;
    return;
  }
  if (direccion === actual) return;
  anterior = actual;
  actual = direccion;
}

/**
 * ¿La página anterior ES el destino de este enlace? Misma ruta, y cada
 * parámetro que el destino pide lo tiene igual la página anterior. Por eso
 * `/mio` (que no pide ninguno) acepta volver a cualquier sección de «Lo mío» —
 * incluida aquella desde la que se abrió el memo o la boleta—, mientras que
 * `/mio?tab=reportes` solo acepta volver a Reportes: desde el Resumen no, que
 * es otro sitio.
 */
export function elDestinoEsLaPaginaAnterior(destino: string): boolean {
  if (anterior === null) return false;
  try {
    const previa = aRuta(anterior);
    const pedida = aRuta(destino);
    if (previa.pathname !== pedida.pathname) return false;
    for (const [clave, valor] of pedida.searchParams) {
      if (previa.searchParams.get(clave) !== valor) return false;
    }
    return true;
  } catch {
    return false;
  }
}

/** Solo para las pruebas: arrancar sin historia, como un documento recién cargado. */
export function olvidarLaRuta(): void {
  actual = null;
  anterior = null;
}

