#!/usr/bin/env node
/**
 * Los colores escritos A MANO en el código: un hex, un `rgb()`, un `bg-white`, un `amber-100`. No cambian con el tema, así que una pantalla que
 * los usa se queda clara dentro del modo oscuro. La regla es la de CLAUDE.md: solo los `--color-*` de `globals.css`.
 *
 * SOLO INFORMA. En Retail esto es un candado con su prueba en el CI; aquí no, a propósito: Dynamic ya tiene su regla y una deuda vieja, y una
 * prueba que falla el día uno se aprende a ignorar. Si la obra quiere candado, se pone cuando la deuda baje.
 *
 *   npx pnpm --filter @cayla-dynamic/web tema:colores            los archivos y cuántos
 *   npx pnpm --filter @cayla-dynamic/web tema:colores --lineas   además, cada línea
 *
 * Sale siempre con 0.
 */

import { readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, relative, sep } from "node:path";
import { fileURLToPath } from "node:url";

const WEB = join(dirname(fileURLToPath(import.meta.url)), "..");
const CARPETAS = ["app", "components", "lib"];

/** La paleta por defecto de Tailwind: es lo que prohíbe la regla de CLAUDE.md. */
const CLASES = [
  // `bg-black/NN` NO entra: es el velo de un modal, y CLAUDE.md lo pide así porque oscurece en los dos temas.
  /\b(?:bg|text|border|ring|from|to|via|fill|stroke|divide|outline|shadow|decoration|accent|caret|placeholder)-(?:white|black)(?![\w/-])/g,
  /\bbg-white\/\d+/g,
  /\b(?:text|border|ring|from|to|via|fill|stroke|divide|outline|decoration|accent|caret|placeholder)-(?:white|black)\/\d+/g,
  /\b(?:bg|text|border|ring|from|to|via|fill|stroke|divide|outline|decoration|accent|caret|placeholder)-(?:gray|slate|zinc|neutral|stone|red|green|blue|yellow|amber|orange|emerald|rose|sky|indigo|purple|violet|pink|teal|cyan|lime|fuchsia)-\d{2,3}\b/g,
];

/** Un color crudo en CSS o en código: no siempre es un defecto (un lienzo, una imagen generada), pero siempre hay que poder verlo. */
const CRUDOS = [
  /#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6})\b/g,
  /#(?:fff|000)\b/gi,
  /(?<![A-Za-z0-9])(?:rgb|rgba|hsl|hsla|oklch|oklab|lab|lch)\(/g,
  /\b(?:color|background(?:-color)?|border(?:-(?:top|right|bottom|left))?-color|fill|stroke|outline-color)\s*:\s*(?:white|black)\b/g,
];

/** Cambia por espacios (conservando los saltos de línea) lo que no es código: así los números de línea siguen siendo los reales. */
const blanquear = (texto) => texto.replace(/[^\n]/g, " ");

function sinComentarios(texto, tipo) {
  let sal = texto.replace(/\/\*[\s\S]*?\*\//g, blanquear);
  if (tipo === "ts") sal = sal.replace(/(^|[^:"'`\\])\/\/.*$/gm, (m, previo) => previo + blanquear(m.slice(previo.length)));
  return sal;
}

/** En una hoja de estilos, `--color-x: #hex;` es la definición de un token, no un uso. */
const sinDefiniciones = (css) => css.replace(/^\s*--color-[a-z-]+\s*:[^;\n]*;/gm, blanquear);

const contar = (linea, patrones) => patrones.reduce((n, p) => n + (linea.match(p) ?? []).length, 0);

/**
 * Cuenta los colores sueltos de un texto: `{ clases, crudos, lineas: [{ n, texto }] }`.
 * @param {string} texto
 * @param {"css" | "ts"} tipo
 */
export function coloresSueltosDe(texto, tipo) {
  const crudo = texto.split("\n");
  let limpio = sinComentarios(texto, tipo);
  if (tipo === "css") limpio = sinDefiniciones(limpio);
  const r = { clases: 0, crudos: 0, lineas: [] };
  limpio.split("\n").forEach((l, i) => {
    const clases = contar(l, CLASES);
    const crudos = contar(l, CRUDOS);
    if (!clases && !crudos) return;
    r.clases += clases;
    r.crudos += crudos;
    r.lineas.push({ n: i + 1, texto: crudo[i].trim().slice(0, 140) });
  });
  return r;
}

function archivos(dir, salida = []) {
  for (const nombre of readdirSync(dir)) {
    const ruta = join(dir, nombre);
    if (statSync(ruta).isDirectory()) {
      if (nombre === "node_modules" || nombre.startsWith(".")) continue;
      archivos(ruta, salida);
    } else if (/\.(tsx?|css)$/.test(nombre) && !/\.test\.tsx?$/.test(nombre) && !/\.d\.ts$/.test(nombre)) salida.push(ruta);
  }
  return salida;
}

/** Recorre `app`, `components` y `lib` de `apps/web`. Devuelve solo los archivos que tienen alguno. */
export function escanearColoresSueltos(raiz = WEB) {
  const salida = {};
  for (const carpeta of CARPETAS) {
    for (const ruta of archivos(join(raiz, carpeta))) {
      const r = coloresSueltosDe(readFileSync(ruta, "utf8"), ruta.endsWith(".css") ? "css" : "ts");
      if (r.clases || r.crudos) salida[relative(raiz, ruta).split(sep).join("/")] = r;
    }
  }
  return salida;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const filas = Object.entries(escanearColoresSueltos()).sort((a, b) => b[1].clases + b[1].crudos - (a[1].clases + a[1].crudos));
  const clases = filas.reduce((s, [, r]) => s + r.clases, 0);
  const crudos = filas.reduce((s, [, r]) => s + r.crudos, 0);
  console.log(`${filas.length} archivos · ${clases} clases de la paleta de Tailwind (lo que prohíbe CLAUDE.md) · ${crudos} colores crudos (hex, rgb…)\n`);
  console.log(" clases  crudos  archivo");
  for (const [archivo, r] of filas) {
    console.log(`${String(r.clases).padStart(7)} ${String(r.crudos).padStart(7)}  ${archivo}`);
    if (process.argv.includes("--lineas")) for (const l of r.lineas) console.log(`                  L${l.n}: ${l.texto}`);
  }
}
