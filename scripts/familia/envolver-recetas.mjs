// La copia de recetas.css de Retail a Dynamic pasa por aquí. No es una copia: es una reescritura que se niega a seguir si no entiende algo.
//
// PROMETE: de un recetas.css hecho solo de variables, devuelve un CSS que no le hace nada a una pantalla con `data-vidrio` apagado, y que con
//          el vidrio prendido responde a las dos maneras en que Dynamic se pone oscuro (la elegida a mano y la del aparato).
// ASUME:   que recetas.css sigue siendo lo que es hoy (2026-11-05): 204 variables, 0 reglas de clase, 0 @keyframes, 0 @layer. Medido, no supuesto.
// SI NO:   lanza RecetaRechazada con el motivo. Nada llega a Dynamic hasta que alguien lo mire. Por qué así: docs/familia/README.md.
//
// Puro: no lee archivos ni la red. Por eso se prueba sin levantar nada (tests/familia-vigilante.test.ts).

export class RecetaRechazada extends Error {}

const ATRIBUTO = "data-vidrio";
const RAIZ = `:root[${ATRIBUTO}]`;
const OSCURO_A_MANO = `${RAIZ}[data-tema="oscuro"]`;
// La rama que Retail no tiene: Retail arranca siempre en claro y solo conoce `[data-tema="oscuro"]`. Dynamic, sin atributo, sigue al aparato
// (producto D4 del contrato, y `globals.css` escribe los dos bloques). Sin esta rama, una persona con el teléfono en oscuro vería vidrio blanco
// al 70 % sobre una página negra.
const OSCURO_DEL_APARATO = `${RAIZ}:not([data-tema="claro"])`;

export const sinComentarios = (css) => css.replace(/\/\*[\s\S]*?\*\//g, "");

/** Dónde termina lo que empieza en `i` si es una cadena o un comentario; `i` si no es ninguna de las dos. */
function saltar(css, i) {
  if (css.startsWith("/*", i)) {
    const fin = css.indexOf("*/", i + 2);
    if (fin < 0) throw new RecetaRechazada("hay un comentario sin cerrar");
    return fin + 2;
  }
  const c = css[i];
  if (c === '"' || c === "'") {
    for (let j = i + 1; j < css.length; j++) {
      if (css[j] === "\\") j++;
      else if (css[j] === c) return j + 1;
    }
    throw new RecetaRechazada("hay una cadena sin cerrar");
  }
  return i;
}

/** Parte un CSS en sus piezas de primer nivel: comentarios, sentencias (`@import …;`) y bloques (`preludio { cuerpo }`). */
export function partir(css) {
  const piezas = [];
  let i = 0;
  while (i < css.length) {
    if (/\s/.test(css[i])) { i++; continue; }
    if (css.startsWith("/*", i)) {
      const fin = saltar(css, i);
      piezas.push({ tipo: "comentario", texto: css.slice(i, fin) });
      i = fin;
      continue;
    }
    const inicio = i;
    let hondura = 0;
    let abre = -1;
    let sentencia = -1;
    while (i < css.length) {
      const despues = saltar(css, i);
      if (despues !== i) { i = despues; continue; }
      const c = css[i];
      if (c === "(") hondura++;
      else if (c === ")") hondura--;
      else if (hondura === 0 && c === "{") { abre = i; break; }
      else if (hondura === 0 && c === ";") { sentencia = i; break; }
      i++;
    }
    if (sentencia >= 0) {
      piezas.push({ tipo: "sentencia", preludio: sinComentarios(css.slice(inicio, sentencia)).trim() });
      i = sentencia + 1;
      continue;
    }
    if (abre < 0) throw new RecetaRechazada(`hay texto suelto que no es CSS: «${css.slice(inicio, inicio + 60).trim()}»`);
    let llaves = 1;
    let j = abre + 1;
    while (j < css.length && llaves > 0) {
      const despues = saltar(css, j);
      if (despues !== j) { j = despues; continue; }
      if (css[j] === "{") llaves++;
      else if (css[j] === "}") llaves--;
      j++;
    }
    if (llaves > 0) throw new RecetaRechazada(`el bloque «${css.slice(inicio, abre).trim()}» no se cierra`);
    piezas.push({
      tipo: "bloque",
      preludio: sinComentarios(css.slice(inicio, abre)).replace(/\s+/g, " ").trim(),
      cuerpo: css.slice(abre + 1, j - 1),
    });
    i = j;
  }
  return piezas;
}

/** Las declaraciones de un cuerpo, cortadas por `;` que no estén dentro de un paréntesis o una cadena. */
function declaraciones(cuerpo) {
  const limpio = sinComentarios(cuerpo);
  const salida = [];
  let hondura = 0;
  let desde = 0;
  let i = 0;
  while (i < limpio.length) {
    const despues = saltar(limpio, i);
    if (despues !== i) { i = despues; continue; }
    const c = limpio[i];
    if (c === "(") hondura++;
    else if (c === ")") hondura--;
    else if (c === "{" || c === "}") throw new RecetaRechazada("hay una regla anidada dentro de un bloque de variables");
    else if (c === ";" && hondura === 0) { salida.push(limpio.slice(desde, i).trim()); desde = i + 1; }
    i++;
  }
  salida.push(limpio.slice(desde).trim());
  return salida.filter(Boolean);
}

function exigirSoloVariables(cuerpo, donde) {
  for (const d of declaraciones(cuerpo)) {
    if (!/^--[a-z0-9-]+\s*:/i.test(d)) {
      throw new RecetaRechazada(`${donde}: «${d.slice(0, 70)}» no es una variable. Una regla así se aplicaría a las pantallas de Dynamic, también al terminal.`);
    }
  }
}

function indentar(texto) {
  return texto.split("\n").map((l) => (l.trim() === "" ? "" : `  ${l}`)).join("\n");
}

function soloUnBloque(piezas, selector, donde) {
  for (const p of piezas) {
    if (p.tipo === "comentario") continue;
    if (p.tipo !== "bloque" || p.preludio !== selector) {
      throw new RecetaRechazada(`${donde}: esperaba solo «${selector}» y encontré «${p.preludio}»`);
    }
    exigirSoloVariables(p.cuerpo, `${donde} › ${selector}`);
  }
  return piezas;
}

/**
 * Las tres formas que tiene hoy recetas.css. Cualquier otra se rechaza: un @keyframes tiene nombre global y pisaría al de Dynamic sin importar el
 * atributo; un @layer cambia el orden de las capas de Tailwind; una regla de clase apunta al HTML de Retail, no al de Dynamic.
 */
export function envolverRecetas(css, { origen = "" } = {}) {
  const salida = [
    "/* GENERADO por scripts/familia/envolver-recetas.mjs. No se edita a mano: se pisa en la próxima toma.\n" +
      `   Origen: ${origen || "recetas.css de CAYLA Retail"}.\n` +
      `   Todo cuelga de ${RAIZ}: con el vidrio apagado este archivo no le hace nada a ninguna pantalla. */`,
  ];
  for (const p of partir(css)) {
    if (p.tipo === "comentario") {
      salida.push(p.texto);
    } else if (p.tipo === "sentencia") {
      throw new RecetaRechazada(`«${p.preludio}» no es una variable y no se puede colgar de ${ATRIBUTO}`);
    } else if (p.preludio === ":root") {
      exigirSoloVariables(p.cuerpo, ":root");
      salida.push(`${RAIZ} {${p.cuerpo}}`);
    } else if (p.preludio === "@media screen") {
      const adentro = soloUnBloque(partir(p.cuerpo), ':root[data-tema="oscuro"]', "@media screen");
      const aMano = adentro.map((q) => (q.tipo === "comentario" ? q.texto : `${OSCURO_A_MANO} {${q.cuerpo}}`)).join("\n");
      const delAparato = adentro.filter((q) => q.tipo === "bloque").map((q) => `${OSCURO_DEL_APARATO} {${sinComentarios(q.cuerpo)}}`).join("\n");
      salida.push(`@media screen {\n${indentar(aMano)}\n}`);
      salida.push(`@media screen and (prefers-color-scheme: dark) {\n${indentar(delAparato)}\n}`);
    } else if (p.preludio === "@media (prefers-reduced-transparency: reduce)") {
      const selector = ':root, :root[data-tema="oscuro"]';
      const adentro = soloUnBloque(partir(p.cuerpo), selector, p.preludio);
      const texto = adentro.map((q) => (q.tipo === "comentario" ? q.texto : `${RAIZ},\n${OSCURO_A_MANO},\n${OSCURO_DEL_APARATO} {${q.cuerpo}}`)).join("\n");
      salida.push(`${p.preludio} {\n${indentar(texto)}\n}`);
    } else {
      throw new RecetaRechazada(`«${p.preludio}» es una forma que recetas.css no tenía. Hay que decidir qué hacer con ella antes de que viaje.`);
    }
  }
  return `${salida.join("\n\n")}\n`;
}

/** Las variables que declara un CSS. */
export function variablesDe(css) {
  return new Set([...sinComentarios(css).matchAll(/(?:^|[\s;{])(--[a-z0-9-]+)\s*:/gi)].map((m) => m[1]));
}

/** Las variables de afuera que un CSS consume: lo que tiene que existir para que la receta funcione. */
export function dependenciasDe(css) {
  const propias = variablesDe(css);
  const usadas = new Set([...sinComentarios(css).matchAll(/var\(\s*(--[a-z0-9-]+)/gi)].map((m) => m[1]));
  return [...usadas].filter((v) => !propias.has(v)).sort();
}

/**
 * Lo que puede salir mal sin que ningún navegador avise: una variable que no existe deja a la propiedad en nada, en silencio. Devuelve los motivos
 * para frenar (vacío si no hay ninguno). `conocidas` son las dependencias que faltan y ya están declaradas como deuda.
 */
export function revisarContraDynamic(css, { cssDeDynamic, conocidas = [] }) {
  const motivos = [];
  const deDynamic = variablesDe(cssDeDynamic);
  for (const v of dependenciasDe(css)) {
    if (!deDynamic.has(v) && !conocidas.includes(v)) motivos.push(`la receta pide ${v}, que Dynamic no tiene`);
  }
  for (const v of variablesDe(css)) {
    if (deDynamic.has(v)) motivos.push(`la receta redefine ${v}, que ya existe en Dynamic`);
    else if (/^--(color|radius)-/.test(v)) motivos.push(`${v} es un valor de marca: entra por el contrato, no por las recetas`);
  }
  return motivos;
}
