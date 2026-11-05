// Motor de detección de la verificación de responsive — ver `responsive/README.md`. Traído de CAYLA Retail.
//
// GENÉRICO a propósito: no sabe nada de Planilla, de Lo mío ni de ninguna pantalla. Solo sabe
// mirar el DOM ya renderizado y decir "esto se sale de donde debería caber". Las particularidades
// de cada pantalla (qué escenario preparar, qué excluir) viven en `responsive/pantallas/`.

/** Selectores que se inspeccionan en TODA pantalla salvo que agregue más con `elementosClave`
 *  (botones, inputs, selects, links, controles interactivos, títulos, textos etiquetados y
 *  cualquier cosa que un componente marque a mano con `data-critico`). */
export const SELECTORES_POR_DEFECTO = [
  "button",
  "a[href]",
  "input",
  "select",
  "textarea",
  '[role="button"]',
  '[role="link"]',
  '[role="tab"]',
  '[role="menuitem"]',
  '[role="checkbox"]',
  "h1",
  "h2",
  "h3",
  "label",
  "dl", // resúmenes de datos clave — semántica genérica, no de una pantalla
  "[data-critico]",
];

/**
 * Corre DENTRO del navegador vía `page.evaluate`. No cierra sobre nada del módulo — todo lo que
 * necesita llega por `opts` porque Playwright serializa esta función tal cual para ejecutarla en
 * la página. Devuelve la señal de overflow global + la lista de clipping real encontrado.
 *
 * @param {{ selectoresClave: string[], selectoresExclusion: string[], ambito: string|null, limite: string|null, tolerancia: number }} opts
 */
export function analizarEnPagina(opts) {
  const { selectoresClave, selectoresExclusion = [], ambito = null, limite = null, tolerancia = 1 } = opts;
  const doc = document;
  const html = doc.documentElement;

  const overflowGlobal = {
    innerWidth: window.innerWidth,
    innerHeight: window.innerHeight,
    clientWidth: html.clientWidth,
    scrollWidthDoc: html.scrollWidth,
    scrollWidthBody: doc.body ? doc.body.scrollWidth : null,
  };

  const raizAmbito = ambito ? doc.querySelector(ambito) : html;
  if (ambito && !raizAmbito) {
    return { overflowGlobal, clipping: [], advertencia: `ámbito "${ambito}" no encontrado en el DOM` };
  }

  let limiteRect = { left: 0, top: 0, right: overflowGlobal.clientWidth, bottom: html.clientHeight || overflowGlobal.innerHeight };
  if (limite) {
    const elLimite = doc.querySelector(limite);
    if (elLimite) {
      const r = elLimite.getBoundingClientRect();
      limiteRect = { left: r.left, top: r.top, right: r.right, bottom: r.bottom };
    }
  }

  const selector = (selectoresClave && selectoresClave.length ? selectoresClave : ["button", "a[href]", "input"]).join(",");
  const exclusionSel = selectoresExclusion && selectoresExclusion.length ? selectoresExclusion.join(",") : null;

  const candidatos = Array.from(raizAmbito.querySelectorAll(selector));
  if (raizAmbito !== html && typeof raizAmbito.matches === "function" && raizAmbito.matches(selector)) {
    candidatos.unshift(raizAmbito);
  }

  const clipping = [];
  const vistos = new Set();

  for (const el of candidatos) {
    if (!el || vistos.has(el)) continue;
    vistos.add(el);
    if (!visible(el)) continue;

    const rect = el.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) continue;

    // Reachable-by-scroll: un elemento dentro de un contenedor con scroll horizontal legítimo
    // (una fila de acciones o una tabla ancha que se desplaza a propósito) no está "clipeado" —
    // se llega a él scrolleando ESE contenedor, no el viewport entero — así que se salta del
    // todo. El contenedor mismo no se salta: cuando el bucle llegue a ÉL (si matchea algún
    // selector) o a lo que lo envuelve, sigue comparándose contra SU propio límite, así que un
    // contenedor de scroll que se sale de su padre igual se detecta.
    const contenedor = limite ? null : contenedorScrollX(el, html, tolerancia);
    if (contenedor) continue;

    const limiteEfectivo = limiteRect;
    const contra = limite ? `contenedor:${limite}` : "viewport";

    const izquierdaCorta = rect.left < limiteEfectivo.left - tolerancia;
    const derechaCorta = rect.right > limiteEfectivo.right + tolerancia;
    if (izquierdaCorta || derechaCorta) {
      clipping.push({
        selector: describir(el),
        texto: (el.textContent || "").trim().slice(0, 60),
        tipo: tipoDe(el),
        rect: { left: redondear(rect.left), right: redondear(rect.right), top: redondear(rect.top), bottom: redondear(rect.bottom), width: redondear(rect.width) },
        limite: { left: redondear(limiteEfectivo.left), right: redondear(limiteEfectivo.right) },
        contra,
        lado: izquierdaCorta && derechaCorta ? "ambos" : izquierdaCorta ? "izquierda" : "derecha",
        exceso: redondear(izquierdaCorta ? limiteEfectivo.left - rect.left : rect.right - limiteEfectivo.right),
      });
    }
  }

  return { overflowGlobal, clipping };

  // ---- helpers (declarados dentro: esta función viaja sola al navegador) ----

  function visible(el) {
    const cs = getComputedStyle(el);
    if (cs.display === "none" || cs.visibility === "hidden") return false;
    // Lo que el navegador ya trata como fuera de juego: aria-hidden, [hidden], `inert`, algo marcado
    // como cerrado; y el opt-out explícito para lo que está fuera de pantalla por diseño.
    if (el.closest('[aria-hidden="true"],[hidden],[data-state="closed"],[inert],[data-fuera-de-pantalla]')) return false;
    if (exclusionSel && el.closest(exclusionSel)) return false;
    return true;
  }

  function contenedorScrollX(el, tope, tol) {
    let n = el.parentElement;
    while (n && n !== tope) {
      const cs = getComputedStyle(n);
      if ((cs.overflowX === "auto" || cs.overflowX === "scroll") && n.scrollWidth > n.clientWidth + tol) return n;
      n = n.parentElement;
    }
    return null;
  }

  function redondear(n) {
    return Math.round(n * 10) / 10;
  }

  function tipoDe(el) {
    const tag = el.tagName.toLowerCase();
    const rol = el.getAttribute("role");
    if (tag === "button" || rol === "button") return "boton";
    if (tag === "a") return "link";
    if (tag === "input") return "input";
    if (tag === "select") return "select";
    if (tag === "textarea") return "textarea";
    if (/^h[1-6]$/.test(tag)) return "titulo";
    if (tag === "label") return "etiqueta";
    return "contenedor";
  }

  function describir(el) {
    const etq = el.getAttribute("aria-label") || el.getAttribute("placeholder") || el.getAttribute("title");
    if (etq) return `${el.tagName.toLowerCase()}[${etq.slice(0, 40)}]`;
    const texto = (el.textContent || "").trim();
    if (texto) return `${el.tagName.toLowerCase()}:"${texto.slice(0, 30)}"`;
    if (el.id) return `#${el.id}`;
    if (typeof el.className === "string" && el.className.trim()) return `${el.tagName.toLowerCase()}.${el.className.trim().split(/\s+/)[0]}`;
    return el.tagName.toLowerCase();
  }
}
