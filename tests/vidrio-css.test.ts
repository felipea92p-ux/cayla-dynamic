import { describe, expect, it } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";

// LA OTRA MITAD DE «APAGADO NO CAMBIA NADA»: toda regla de apps/web/app/estilos/vidrio/ cuelga del atributo que pone
// lib/vidrio.ts en <html>. Si no hay atributo, ninguna regla de esa carpeta puede alcanzar a nadie.
//
// La receta contra lo que ya pasó aquí: una regla suelta se coló al terminal hasta el 2026-09-07 (ver globals.css).
// No basta con buscar el texto `[data-vidrio` en el selector, porque hay formas de escribirlo que aplican justo cuando
// el atributo NO está (`:not([data-vidrio])`) o que dejan una parte de la lista sin colgar (`[data-vidrio] .a, .b`).
//
// Es un lector de CSS de pocas líneas y no un compilador: lo que no reconoce lo rechaza. Si una regla legítima choca
// contra esto, el motivo se agrega a ARROBAS_CON_REGLAS o al mensaje, no se relaja la comprobación entera.

const CARPETA = path.resolve(import.meta.dirname, "../apps/web/app/estilos/vidrio");

/** Bloques cuyo contenido se revisa regla por regla: no aplican nada por sí mismos. */
const ARROBAS_CON_REGLAS = new Set(["media", "supports", "layer", "container"]);

const ATRIBUTO = /^\[\s*data-vidrio\s*(?:[~|^$*]?=\s*(?:"[^"]*"|'[^']*'|[^\]\s]+)\s*(?:[is]\s*)?)?\]$/;

/** Parte en la coma que está fuera de todo paréntesis y corchete. */
function partirPorComas(selector: string): string[] {
  const partes: string[] = [];
  let profundidad = 0;
  let actual = "";
  for (const c of selector) {
    if (c === "(" || c === "[") profundidad++;
    if (c === ")" || c === "]") profundidad--;
    if (c === "," && profundidad === 0) {
      partes.push(actual);
      actual = "";
    } else {
      actual += c;
    }
  }
  partes.push(actual);
  return partes;
}

/** Devuelve la posición donde cierra el paréntesis o corchete que abre en `i`. */
function cierre(texto: string, i: number): number {
  const abre = texto[i];
  const cierra = abre === "(" ? ")" : "]";
  let profundidad = 0;
  for (let j = i; j < texto.length; j++) {
    if (texto[j] === abre) profundidad++;
    if (texto[j] === cierra && --profundidad === 0) return j;
  }
  return texto.length;
}

/**
 * ¿Este selector exige el atributo para coincidir? Solo cuenta si está en el selector mismo o dentro de `:is()` y
 * `:where()`, donde sigue siendo una exigencia. Dentro de `:not()` significa lo contrario, y de `:has()` otra cosa.
 */
function exigeElAtributo(selector: string): boolean {
  return partirPorComas(selector).every((parte) => {
    for (let i = 0; i < parte.length; i++) {
      if (parte[i] === "[") {
        const fin = cierre(parte, i);
        if (ATRIBUTO.test(parte.slice(i, fin + 1))) return true;
        i = fin;
      } else if (parte[i] === "(") {
        const fin = cierre(parte, i);
        if (/:(is|where)$/.test(parte.slice(0, i)) && exigeElAtributo(parte.slice(i + 1, fin))) return true;
        i = fin;
      }
    }
    return false;
  });
}

/** Quita comentarios sin confundirse con un `/*` que viva dentro de una cadena. */
function sinComentarios(css: string): string {
  let salida = "";
  for (let i = 0; i < css.length; i++) {
    if (css[i] === "/" && css[i + 1] === "*") {
      const fin = css.indexOf("*/", i + 2);
      i = fin === -1 ? css.length : fin + 1;
    } else if (css[i] === '"' || css[i] === "'") {
      let j = i + 1;
      while (j < css.length && css[j] !== css[i]) j += css[j] === "\\" ? 2 : 1;
      salida += css.slice(i, j + 1);
      i = j;
    } else {
      salida += css[i];
    }
  }
  return salida;
}

/** Los errores de un bloque de reglas, recorriendo capas y `@media`. Sin errores = todo cuelga del atributo. */
function revisarBloque(css: string, errores: string[]): void {
  let i = 0;
  while (i < css.length) {
    let j = i;
    let comillas: string | null = null;
    let parentesis = 0;
    while (j < css.length) {
      const c = css[j];
      if (comillas) {
        if (c === "\\") j++;
        else if (c === comillas) comillas = null;
      } else if (c === '"' || c === "'") comillas = c;
      else if (c === "(") parentesis++;
      else if (c === ")") parentesis--;
      else if (parentesis === 0 && (c === "{" || c === ";" || c === "}")) break;
      j++;
    }
    const preludio = css.slice(i, j).trim();
    const fin = css[j];

    if (fin === "{") {
      let profundidad = 1;
      let k = j + 1;
      let dentroDe: string | null = null;
      while (k < css.length && profundidad > 0) {
        const c = css[k];
        if (dentroDe) {
          if (c === "\\") k++;
          else if (c === dentroDe) dentroDe = null;
        } else if (c === '"' || c === "'") dentroDe = c;
        else if (c === "{") profundidad++;
        else if (c === "}") profundidad--;
        k++;
      }
      revisarConBloque(preludio, css.slice(j + 1, k - 1), errores);
      i = k;
    } else {
      if (preludio) revisarSinBloque(preludio, errores);
      i = j + 1;
    }
  }
}

function revisarConBloque(preludio: string, cuerpo: string, errores: string[]): void {
  if (!preludio.startsWith("@")) {
    if (!exigeElAtributo(preludio)) errores.push(`regla que no cuelga de [data-vidrio]: «${preludio}»`);
    return;
  }
  const arroba = /^@([\w-]+)\s*(.*)$/s.exec(preludio);
  const nombre = arroba?.[1] ?? "";
  const parametros = arroba?.[2]?.trim() ?? "";
  if (ARROBAS_CON_REGLAS.has(nombre)) {
    revisarBloque(cuerpo, errores);
  } else if (/^(-\w+-)?keyframes$/.test(nombre)) {
    if (!parametros.startsWith("vidrio-")) {
      errores.push(`@keyframes sin el prefijo vidrio-: «${parametros}» (es global: pisaría a otro del mismo nombre)`);
    }
  } else {
    errores.push(`@${nombre} no está en la lista de lo permitido: se aplicaría sin mirar el atributo`);
  }
}

function revisarSinBloque(preludio: string, errores: string[]): void {
  if (!preludio.startsWith("@")) {
    errores.push(`declaración suelta, fuera de toda regla: «${preludio}»`);
    return;
  }
  const arroba = /^@([\w-]+)\s*(.*)$/s.exec(preludio);
  const nombre = arroba?.[1] ?? "";
  const parametros = arroba?.[2]?.trim() ?? "";
  if (nombre === "import") {
    // Solo archivos de esta misma carpeta, que este recorrido también revisa.
    if (!/^["']\.\/[^"']+\.css["']/.test(parametros)) errores.push(`@import de fuera de la carpeta: «${parametros}»`);
  } else if (nombre === "layer") {
    // Sin esta condición, `@layer utilities, base;` puede reordenar las capas de todo el sistema.
    if (!parametros.split(",").every((n) => n.trim().startsWith("vidrio"))) {
      errores.push(`@layer que nombra capas ajenas: «${parametros}»`);
    }
  } else if (nombre === "custom-variant") {
    // Sin el nombre propio podría redefinir `dark:` o `hover:` para todas las pantallas.
    if (!parametros.startsWith("vidrio") || !/\[data-vidrio[\]=~|^$*\s]/.test(parametros)) {
      errores.push(`@custom-variant debe llamarse vidrio… y exigir [data-vidrio]: «${parametros}»`);
    }
  } else {
    errores.push(`@${nombre} no está en la lista de lo permitido: se aplicaría sin mirar el atributo`);
  }
}

function erroresDeCss(css: string): string[] {
  const errores: string[] = [];
  revisarBloque(sinComentarios(css), errores);
  return errores;
}

describe("toda regla del vidrio cuelga de [data-vidrio]", () => {
  it("los archivos reales de la carpeta cumplen", () => {
    const archivos = (readdirSync(CARPETA, { recursive: true }) as string[]).filter((f) => f.endsWith(".css"));
    // La carpeta tiene que existir y haberse leído: una lista vacía pasaría en verde sin mirar nada.
    expect(archivos.length).toBeGreaterThan(0);
    const errores = archivos.flatMap((f) =>
      erroresDeCss(readFileSync(path.join(CARPETA, f), "utf8")).map((e) => `${f}: ${e}`),
    );
    expect(errores).toEqual([]);
  });

  it.each([
    ["el atributo solo", `[data-vidrio] { color: red; }`],
    ["con valor", `[data-vidrio="panel"] .a { color: red; }`],
    ["en la raíz", `:root[data-vidrio="terminal"] { --radio: 8px; }`],
    ["lista donde todas cuelgan", `[data-vidrio] .a, [data-vidrio="panel"] .b { color: red; }`],
    ["el atributo más adentro de un :is", `:is([data-vidrio] .a, [data-vidrio] .b) .c { color: red; }`],
    ["una lista adentro que no afecta", `[data-vidrio] :is(.a, .b) { color: red; }`],
    ["con :where", `:where([data-vidrio]) .a { color: red; }`],
    ["dentro de @media", `@media (min-width: 640px) { [data-vidrio] .a { color: red; } }`],
    ["dentro de @layer", `@layer vidrio { [data-vidrio] .a { color: red; } }`],
    ["capa y @media anidados", `@layer vidrio { @media print { [data-vidrio] .a { color: red; } } }`],
    ["@supports", `@supports (backdrop-filter: blur(1px)) { [data-vidrio] .a { color: red; } }`],
    ["regla anidada: hereda del padre", `[data-vidrio] .a { color: red; &:hover { color: blue; } .b { color: green; } }`],
    ["animación con prefijo", `@keyframes vidrio-entra { from { opacity: 0; } to { opacity: 1; } }`],
    ["un comentario con una regla suelta", `/* .a { color: red; } */ [data-vidrio] .a { color: red; }`],
    ["llave dentro de una cadena", `[data-vidrio] .a::after { content: "}"; }`],
    ["importar de la misma carpeta", `@import "./botones.css";`],
    ["declarar su propia capa", `@layer vidrio-base, vidrio;`],
    ["variante propia", `@custom-variant vidrio (&:where([data-vidrio] *));`],
    ["vacío", ``],
    ["solo un comentario", `/* nada todavía */`],
  ])("deja pasar: %s", (_nombre, css) => {
    expect(erroresDeCss(css)).toEqual([]);
  });

  it.each([
    ["regla sin el atributo", `.a { color: red; }`],
    ["elemento suelto (lo que se coló al terminal)", `button.bg-tinta:hover { color: red; }`],
    ["la raíz sin el atributo", `:root { --radio: 8px; }`],
    ["una parte de la lista sin colgar", `[data-vidrio] .a, .b { color: red; }`],
    ["una parte de un :is sin colgar", `:is([data-vidrio] .a, .b) .c { color: red; }`],
    ["al revés: aplica justo cuando está apagado", `:not([data-vidrio]) .a { color: red; }`],
    ["otro atributo que empieza igual", `[data-vidrio-x] .a { color: red; }`],
    ["el atributo dentro de :has no exige nada de <html>", `body:has([data-vidrio]) .a { color: red; }`],
    ["suelta dentro de @media", `@media (min-width: 640px) { .a { color: red; } }`],
    ["suelta dentro de @layer", `@layer base { .a { color: red; } }`],
    ["capa y @media anidados, suelta", `@layer vidrio { @media print { .a { color: red; } } }`],
    ["suelta después de una buena", `[data-vidrio] .a { color: red; } .b { color: red; }`],
    ["suelta después de un comentario engañoso", `/* [data-vidrio] */ .a { color: red; }`],
    ["animación sin prefijo", `@keyframes velo-entra { from { opacity: 0; } to { opacity: 1; } }`],
    ["animación con otro prefijo de navegador, sin el nuestro", `@-webkit-keyframes entra { from { opacity: 0; } }`],
    ["@theme define variables para toda la app", `@theme { --color-vidrio: #fff; }`],
    ["@font-face no conoce atributos", `@font-face { font-family: X; src: url(x.woff2); }`],
    ["@utility crea clases sin mirar nada", `@utility vidrio-x { color: red; }`],
    ["@import de Tailwind", `@import "tailwindcss";`],
    ["@import de fuera de la carpeta", `@import "../../globals.css";`],
    ["@import por dirección", `@import url("https://ejemplo.test/x.css");`],
    ["@layer que reordena las capas de todos", `@layer utilities, base;`],
    ["@custom-variant que redefine dark:", `@custom-variant dark (&:where([data-vidrio] *));`],
    ["@custom-variant que no mira el atributo", `@custom-variant vidrio (&:where(.a *));`],
    ["declaración suelta", `color: red;`],
  ])("rechaza: %s", (_nombre, css) => {
    expect(erroresDeCss(css).length).toBeGreaterThan(0);
  });
});
