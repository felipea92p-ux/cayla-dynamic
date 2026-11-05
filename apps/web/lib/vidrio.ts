// ============================================================================
// El interruptor del vidrio: la única fuente de verdad de «¿esta pantalla lleva el diseño nuevo?»
// ============================================================================
//
// QUÉ PROMETE
//   interruptoresVidrio(): qué superficies quedaron encendidas en ESTA construcción; solo un "1" exacto enciende, sin variable está apagado.
//   superficieDeRuta(ruta) y valorVidrio(ruta): de quién es esa dirección, y qué debe decir el atributo ahí (null = el atributo no debe existir).
//   guionVidrioAntesDePintar(): el JavaScript que pone el atributo antes del primer pintado, o null si todo está apagado (no se agrega NADA a la página).
//
// QUÉ ASUME
//   Que todo lo del terminal vive bajo /terminal: lo comprueba tests/vidrio-interruptor.test.ts contra las carpetas
//   de app/(terminal), app/(admin) y app/(mio). Y que estas variables se leen escritas tal cual: Next solo hornea
//   `process.env.NEXT_PUBLIC_X` literal; con `process.env[nombre]` el navegador leería «apagado» sin avisar.
//
// CÓMO SE USA DESDE LA HOJA DE ESTILOS
//   [data-vidrio="panel"] .x     solo el panel y Lo mío; aunque el terminal esté encendido, no lo alcanza.
//   [data-vidrio="terminal"] .x  solo el terminal.
//   [data-vidrio] .x             las dos superficies. Se usa solo sabiendo que llega a las dos: una regla pensada para
//                                el panel que se cuela al terminal ya pasó una vez (ver el comentario en globals.css).
//
// DECIDÍ: un guion en línea al principio de <body> que decide con la dirección del navegador, más un componente mínimo
//   (components/vidrio-en-ruta.tsx) que vuelve a preguntar cuando la ruta cambia sin recargar. Los dos existen solo si
//   hay algún interruptor encendido: apagado, el HTML de producción no lleva nada de esto.
//   Hace falta el segundo porque sí se cruza sin recargar: la portada (/) enlaza a /terminal y a /admin con <Link>, y
//   la página 404 de /terminal/lo-que-sea enlaza a /admin/dashboard. El <html> no se vuelve a dibujar en ese cruce.
// DESCARTÉ:
//   · `headers()` o un proxy en el layout raíz, porque vuelve dinámicas las 61 rutas estáticas de hoy (medido en
//     `next build`, 2026-11-05) y eso producción sí lo notaría, también apagado.
//   · Un layout raíz propio para el terminal, porque duplica fuentes, tema y avisos para poner un atributo.
//   · El atributo en el <div> de cada layout, porque los modales y menús que cuelgan de <body> quedarían fuera.
//   · Cambiar esos <Link> por <a> para evitar el segundo componente, porque el siguiente <Link> que alguien escriba
//     dejaría el atributo equivocado en silencio hasta la próxima recarga.
// SE ROMPE SI:
//   · Alguien crea una pantalla del terminal fuera de /terminal: se pintaría como panel (la prueba de rutas lo frena).
//   · Revienta `global-error.tsx`: reemplaza el <html> entero y se queda sin atributo. Se acepta: lleva estilos propios.
//   · Se cambia la variable en Vercel y no se construye de nuevo: no pasa nada hasta el siguiente despliegue, que con
//     `main` publicándose sola puede ser la fusión de otra sesión, sin que nadie haya elegido ese momento.
// ============================================================================

export type Superficie = "panel" | "terminal";

export interface InterruptoresVidrio {
  panel: boolean;
  terminal: boolean;
}

export const ATRIBUTO_VIDRIO = "data-vidrio";

const INICIO_TERMINAL = "/terminal";

export function interruptoresVidrio(): InterruptoresVidrio {
  return {
    panel: process.env.NEXT_PUBLIC_VIDRIO === "1",
    terminal: process.env.NEXT_PUBLIC_VIDRIO_TERMINAL === "1",
  };
}

export function superficieDeRuta(ruta: string): Superficie {
  return ruta === INICIO_TERMINAL || ruta.startsWith(`${INICIO_TERMINAL}/`) ? "terminal" : "panel";
}

export function valorVidrio(ruta: string, interruptores: InterruptoresVidrio = interruptoresVidrio()): Superficie | null {
  const superficie = superficieDeRuta(ruta);
  return interruptores[superficie] ? superficie : null;
}

/** Lleva `elemento` al valor pedido: con null el atributo desaparece, no queda vacío. */
export function aplicarVidrio(elemento: Pick<Element, "setAttribute" | "removeAttribute">, valor: Superficie | null): void {
  if (valor) elemento.setAttribute(ATRIBUTO_VIDRIO, valor);
  else elemento.removeAttribute(ATRIBUTO_VIDRIO);
}

/**
 * Corre antes de que exista nada en <body>, así que no hay nada pintado a lo que cambiarle el aspecto. Repite la
 * condición de `superficieDeRuta` porque aquí no hay módulos: la prueba corre este texto contra todas las rutas reales
 * y exige que conteste igual que `valorVidrio`, para que las dos copias no se separen.
 */
export function guionVidrioAntesDePintar(interruptores: InterruptoresVidrio = interruptoresVidrio()): string | null {
  if (!interruptores.panel && !interruptores.terminal) return null;
  const inicio = JSON.stringify(INICIO_TERMINAL);
  const enTerminal = JSON.stringify(interruptores.terminal ? "terminal" : null);
  const enPanel = JSON.stringify(interruptores.panel ? "panel" : null);
  return `(function(){var r=location.pathname,v=r===${inicio}||r.indexOf(${inicio}+"/")===0?${enTerminal}:${enPanel};if(v)document.documentElement.setAttribute(${JSON.stringify(ATRIBUTO_VIDRIO)},v);})();`;
}
