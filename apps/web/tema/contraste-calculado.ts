// El contraste calculado sobre DEGRADADOS y vidrio. `tema:auditar` lee la página real pero solo suma `background-color`: un degradado no lo ve, y casi
// todo el vidrio es un degradado. Esto mide lo que el navegador no puede contar: toma el CSS, compone cada tramo del fondo sobre lo que puede haber
// detrás y devuelve el PEOR punto. Traído de CAYLA Retail (`lib/vidrio-contraste.test.ts`) y separado de su prueba, para medir recetas en la Etapa 1.
//
// Promete: nunca adivina. Un color que no entiende o una variable que no existe lanzan un error; un `NaN` compara mal y puede pasar por bueno.
// Asume: el color de la letra y del borde es fijo, y lo único que varía es el fondo. No sabe de `backdrop-filter`: el desenfoque promedia lo de atrás
// y no cambia lo que se puede llegar a tener detrás, así que no sube ni baja el peor caso de superficies parejas.
//
// Dos diferencias con la de Retail, las dos porque daban por bueno lo que no lo era:
//   · Retail medía solo los extremos del degradado, con la idea de que el peor es uno de ellos. No es cierto si la letra cae ENTRE los dos: un gris
//     #767676 pasa 4.5:1 contra el blanco y contra el negro, y a mitad de camino entre ellos da 1:1. Aquí se recorre el tramo.
//   · Retail botaba siempre la primera parte del degradado creyéndola el ángulo: en `linear-gradient(#000, #fff)` eso se comía un color entero.

export type Rgba = readonly [r: number, g: number, b: number, a: number];
export type Vars = Readonly<Record<string, string>>;

export const UMBRAL = {
  /** WCAG 1.4.3, texto normal. */
  texto: 4.5,
  /** WCAG 1.4.11: lo único que identifica a un control es su borde. */
  bordeControl: 3,
} as const;

/** Lo que puede haber detrás de una pieza de la interfaz. */
export const SUPERFICIES = ["var(--color-crema)", "var(--color-papel)", "var(--color-hueso)"] as const;

const MUESTRAS_POR_TRAMO = 16;

/** `a` encima de `b`, con su transparencia. */
export function sobre(a: Rgba, b: Rgba): Rgba {
  const alfa = a[3] + b[3] * (1 - a[3]);
  if (alfa === 0) return [0, 0, 0, 0];
  const canal = (i: number) => (a[i] * a[3] + b[i] * b[3] * (1 - a[3])) / alfa;
  return [canal(0), canal(1), canal(2), alfa];
}

function luminancia(c: Rgba): number {
  const [r, g, b] = [c[0], c[1], c[2]].map((v) => {
    const x = v / 255;
    return x <= 0.03928 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

export function contraste(a: Rgba, b: Rgba): number {
  const [claro, oscuro] = [luminancia(a), luminancia(b)].sort((x, y) => y - x);
  return (claro + 0.05) / (oscuro + 0.05);
}

/** Parte `a, b, c` por las comas de primer nivel. */
function partes(texto: string): string[] {
  const salida: string[] = [];
  let hondo = 0;
  let actual = "";
  for (const ch of texto) {
    if (ch === "(") hondo++;
    if (ch === ")") hondo--;
    if (ch === "," && hondo === 0) {
      salida.push(actual.trim());
      actual = "";
    } else actual += ch;
  }
  salida.push(actual.trim());
  return salida;
}

function deHex(valor: string): Rgba {
  const n = valor.slice(1);
  if (!/^(?:[0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(n)) throw new Error(`no entiendo el color «${valor}»`);
  const largo = n.length <= 4 ? n.replace(/./g, "$&$&") : n;
  const canal = (i: number) => parseInt(largo.slice(i, i + 2), 16);
  return [canal(0), canal(2), canal(4), largo.length === 8 ? canal(6) / 255 : 1];
}

function deRgb(valor: string, cuerpo: string): Rgba {
  const v = cuerpo.split(/[\s,/]+/).filter(Boolean);
  if (v.length !== 3 && v.length !== 4) throw new Error(`no entiendo el color «${valor}»`);
  const [r, g, b] = v.slice(0, 3).map((x) => (x.endsWith("%") ? (parseFloat(x) * 255) / 100 : parseFloat(x)));
  const a = v[3] === undefined ? 1 : v[3].endsWith("%") ? parseFloat(v[3]) / 100 : parseFloat(v[3]);
  if ([r, g, b, a].some(Number.isNaN)) throw new Error(`no entiendo el color «${valor}»`);
  return [r, g, b, a];
}

/** `color-mix` mezcla premultiplicado: el transparente no cambia el color, solo le baja el alfa. */
function deMezcla(valor: string, espacio: string, cuerpo: string, vars: Vars): Rgba {
  const lados = partes(cuerpo);
  if (lados.length !== 2) throw new Error(`no entiendo la mezcla «${valor}»`);
  const [a, b] = lados.map((lado) => {
    const m = lado.match(/^(.*\S)\s+([\d.]+)%$/);
    return { c: color(m ? m[1] : lado, vars), pct: m ? Number(m[2]) / 100 : null };
  });
  const pa = a.pct ?? (b.pct === null ? 0.5 : 1 - b.pct);
  const pb = b.pct ?? 1 - pa;
  // En otro espacio de color la mezcla de dos colores da otro resultado. Con transparente no: es el caso de `bg-rojo/10` en Tailwind, que sí se puede medir.
  if (espacio !== "srgb" && a.c[3] !== 0 && b.c[3] !== 0) throw new Error(`solo sé mezclar en srgb, o con transparente: «${valor}»`);
  const total = pa + pb;
  const peso = Math.min(1, total);
  const alfa = ((a.c[3] * pa + b.c[3] * pb) / total) * peso;
  if (alfa === 0) return [0, 0, 0, 0];
  const canal = (i: number) => ((a.c[i] * a.c[3] * pa + b.c[i] * b.c[3] * pb) / total) * (peso / alfa);
  return [canal(0), canal(1), canal(2), alfa];
}

/** Un color de CSS con los valores de un tema: hex, `rgb()`, `var(--x)`, `color-mix(…)`, `transparent`, `white` o `black`. */
export function color(valor: string, vars: Vars): Rgba {
  const v = valor.trim();
  if (v === "transparent") return [0, 0, 0, 0];
  if (v === "white") return [255, 255, 255, 1];
  if (v === "black") return [0, 0, 0, 1];
  if (v.startsWith("#")) return deHex(v);
  const unaVar = v.match(/^var\((--[a-z0-9-]+)(?:\s*,\s*(.*))?\)$/s);
  if (unaVar) {
    const resuelto = vars[unaVar[1]] ?? unaVar[2];
    if (resuelto === undefined) throw new Error(`no existe ${unaVar[1]}`);
    return color(resuelto, vars);
  }
  const rgb = v.match(/^rgba?\((.*)\)$/s);
  if (rgb) return deRgb(v, rgb[1]);
  const mezcla = v.match(/^color-mix\(in\s+(srgb|oklab|oklch)\s*,\s*(.*)\)$/s);
  if (mezcla) return deMezcla(v, mezcla[1], mezcla[2], vars);
  throw new Error(`no entiendo el color «${v}»`);
}

/** Un punto del camino entre dos paradas. CSS interpola premultiplicado: un extremo transparente no ensucia el color del otro. */
function entre(a: Rgba, b: Rgba, t: number): Rgba {
  const alfa = a[3] * (1 - t) + b[3] * t;
  if (alfa === 0) return [0, 0, 0, 0];
  const canal = (i: number) => (a[i] * a[3] * (1 - t) + b[i] * b[3] * t) / alfa;
  return [canal(0), canal(1), canal(2), alfa];
}

const ES_PRELUDIO = /^(?:to\s|from\s|at\s|circle|ellipse|closest-|farthest-|[-\d.]+(?:deg|grad|rad|turn)\b)/;
/** La posición de una parada: `#fff 40%`, `var(--a) 10% 20%`, `var(--a) var(--b)`. */
const POSICIONES = /(?:\s+(?:-?[\d.]+(?:%|px|rem|em)?|var\(--[a-z0-9-]+\)|calc\([^)]*\)))+$/;

/** Una capa de fondo convertida en los colores por los que pasa: uno si es pareja, y todo el recorrido si es un degradado. */
export function muestras(capa: string, vars: Vars): Rgba[] {
  const v = capa.trim();
  const unaVar = v.match(/^var\((--[a-z0-9-]+)\)$/);
  if (unaVar && vars[unaVar[1]] !== undefined) {
    const adentro = partes(vars[unaVar[1]]);
    if (adentro.length > 1) throw new Error(`${unaVar[1]} trae varias capas: pásala con \`pintados\`, no como una sola`);
    return muestras(vars[unaVar[1]], vars);
  }
  const degradado = v.match(/^(?:repeating-)?(?:linear|radial|conic)-gradient\((.*)\)$/s);
  if (!degradado) return [color(v, vars)];
  const paradas = partes(degradado[1])
    .filter((p, i) => !(i === 0 && ES_PRELUDIO.test(p)))
    .map((p) => color(p.replace(POSICIONES, ""), vars));
  if (paradas.length < 2) throw new Error(`un degradado necesita dos colores: «${v}»`);
  const salida: Rgba[] = [paradas[0]];
  for (let i = 1; i < paradas.length; i++) {
    for (let k = 1; k <= MUESTRAS_POR_TRAMO; k++) salida.push(entre(paradas[i - 1], paradas[i], k / MUESTRAS_POR_TRAMO));
  }
  return salida;
}

/** Cada color con el que puede terminar pintado un fondo sobre `detras`. `fondo` admite varias capas separadas por comas, la de arriba primero. */
export function pintados(fondo: string, detras: Rgba, vars: Vars): Rgba[] {
  const directa = fondo.trim().match(/^var\((--[a-z0-9-]+)\)$/);
  const texto = directa && vars[directa[1]] !== undefined ? vars[directa[1]] : fondo;
  let salida: Rgba[] = [detras];
  for (const capa of partes(texto).reverse()) {
    const colores = muestras(capa, vars);
    salida = salida.flatMap((base) => colores.map((c) => sobre(c, base)));
  }
  return salida;
}

/** El peor contraste de una letra sobre un fondo, contra todo lo que puede haber detrás. `fondo` en null: la letra va directo sobre la superficie. */
export function peorLetra(letra: string, fondo: string | null, vars: Vars, detras: readonly string[] = SUPERFICIES): number {
  const tinta = color(letra, vars);
  let peor = Infinity;
  for (const superficie of detras) {
    const base = color(superficie, vars);
    for (const pintado of fondo === null ? [base] : pintados(fondo, base, vars)) peor = Math.min(peor, contraste(sobre(tinta, pintado), pintado));
  }
  return peor;
}

/** El peor contraste del borde de un control contra lo que tiene alrededor. Si el control tiene `fondo`, el borde se pinta encima de él, como en CSS. */
export function peorBorde(borde: string, vars: Vars, { fondo = null, detras = SUPERFICIES }: { fondo?: string | null; detras?: readonly string[] } = {}): number {
  const trazo = color(borde, vars);
  let peor = Infinity;
  for (const superficie of detras) {
    const base = color(superficie, vars);
    for (const pintado of fondo === null ? [base] : pintados(fondo, base, vars)) peor = Math.min(peor, contraste(sobre(trazo, pintado), base));
  }
  return peor;
}

/** El cuerpo de cada bloque cuyo selector es EXACTAMENTE ese: uno dentro de una lista con comas (como el de `@media print`) no cuenta. */
function bloques(css: string, selector: string): string[] {
  const salida: string[] = [];
  let desde = 0;
  for (;;) {
    const i = css.indexOf(selector, desde);
    if (i < 0) return salida;
    desde = i + selector.length;
    const antes = css.slice(0, i).trimEnd().at(-1);
    if (!css.slice(desde).trimStart().startsWith("{") || (antes !== undefined && !"{};".includes(antes))) continue;
    const inicio = css.indexOf("{", desde);
    let hondo = 1;
    let j = inicio + 1;
    for (; hondo > 0 && j < css.length; j++) {
      if (css[j] === "{") hondo++;
      if (css[j] === "}") hondo--;
    }
    salida.push(css.slice(inicio + 1, j - 1));
  }
}

function declaraciones(cuerpos: string[]): Record<string, string> {
  const salida: Record<string, string> = {};
  for (const cuerpo of cuerpos) {
    for (const m of cuerpo.matchAll(/(--[a-z0-9-]+)\s*:\s*([^;]+);/g)) salida[m[1]] = m[2].replace(/\s+/g, " ").trim();
  }
  return salida;
}

/**
 * Los valores de cada tema, leídos de las hojas tal como se escriben: `@theme` y `:root` para el claro; el oscuro hereda esos y le encima
 * `:root[data-tema="oscuro"]`. La Etapa 1 agrega aquí su hoja de recetas: `temasDe(globals, recetas)`.
 */
export function temasDe(...hojas: string[]): { claro: Vars; oscuro: Vars } {
  const limpias = hojas.map((h) => h.replace(/\/\*[\s\S]*?\*\//g, ""));
  const claro = declaraciones(limpias.flatMap((h) => [...bloques(h, "@theme"), ...bloques(h, ":root")]));
  const propiasDelOscuro = declaraciones(limpias.flatMap((h) => bloques(h, ':root[data-tema="oscuro"]')));
  if (!Object.keys(claro).length || !Object.keys(propiasDelOscuro).length) throw new Error("No encontré los dos temas en esas hojas: ¿les cambiaron la forma?");
  return { claro, oscuro: { ...claro, ...propiasDelOscuro } };
}
