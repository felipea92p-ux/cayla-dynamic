import { describe, expect, it } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";

// El papel con vidrio: en pantalla sigue el tema, y al imprimir sale claro.
//
// Hasta el 2026-11-09 el papel se quedaba claro también en oscuro (el `.papel-fijo` de Retail), con una copia de los trece colores del bloque de
// impresión. Felipe lo vio en el teléfono —un bloque claro en medio de la pantalla oscura— y decidió que el papel siga el tema. Estas pruebas cuidan
// las dos mitades de esa decisión: que ninguna regla del vidrio vuelva a fijarle colores al papel en pantalla, y que lo impreso siga siendo de día.

const WEB = path.resolve(import.meta.dirname, "../apps/web");
const leer = (f: string) => readFileSync(path.join(WEB, f), "utf8");
const tokens = (css: string) => Object.fromEntries([...css.matchAll(/(--color-[a-z-]+): ([^;]+);/g)].map((m) => [m[1], m[2]]));
const VIDRIO = "app/estilos/vidrio";
const hojasDelVidrio = readdirSync(path.join(WEB, VIDRIO)).filter((f) => f.endsWith(".css"));

/** Cada regla de una hoja de estilos como [selector, cuerpo], aplanando los @media. Basta para estas hojas: no hay llaves dentro de cadenas. */
function reglas(css: string): Array<[string, string]> {
  const sinComentarios = css.replace(/\/\*[\s\S]*?\*\//g, "");
  const salida: Array<[string, string]> = [];
  for (const m of sinComentarios.matchAll(/([^{};]+)\{([^{}]*)\}/g)) salida.push([m[1].trim(), m[2]]);
  return salida;
}

describe("el papel en su bandeja", () => {
  const piezas = leer(`${VIDRIO}/piezas.css`);
  const papel = /\[data-vidrio="panel"\] :is\(\.hoja:not\(main\), \.vidrio-papel\) \{(.*?)\n  \}/s.exec(piezas)![1];

  it("en pantalla sigue el tema: no fija colores ni esquema", () => {
    expect(tokens(papel)).toEqual({});
    expect(papel).not.toMatch(/color-scheme|--firma-/);
  });

  it("ninguna regla del vidrio le fija un color del tema a un documento", () => {
    const culpables = hojasDelVidrio.flatMap((f) =>
      reglas(leer(`${VIDRIO}/${f}`))
        .filter(([selector, cuerpo]) => /\.hoja|\.vidrio-papel|\.contrato/.test(selector) && /--color-[a-z-]+\s*:|color-scheme\s*:/.test(cuerpo))
        .map(([selector]) => `${f}: ${selector}`),
    );
    expect(culpables).toEqual([]);
  });

  it("la firma escaneada se apoya en su recuadro crema en oscuro, como sin vidrio (#680)", () => {
    const globals = leer("app/globals.css");
    const oscuro = /\n:root\[data-tema="oscuro"\] \{(.*?)\n\}/s.exec(globals)![1];
    expect(oscuro).toContain("--firma-fondo: var(--color-crema-fija);");
  });

  it("al imprimir sale claro: el bloque de impresión lleva los trece colores del tema claro", () => {
    const globals = leer("app/globals.css");
    const impresion = tokens(/@media print \{.*?:root\[data-tema="oscuro"\] \{(.*?)\n  \}/s.exec(globals)![1]);
    const claro = tokens(/@theme \{(.*?)\n\}/s.exec(globals)![1]);
    expect(Object.keys(impresion)).toHaveLength(13);
    for (const [nombre, valor] of Object.entries(impresion)) expect([nombre, claro[nombre]]).toEqual([nombre, valor]);
  });

  it("el papel y su bandeja solo existen en pantalla", () => {
    const antes = piezas.slice(0, piezas.indexOf(":is(.hoja:not(main), .vidrio-papel) {"));
    const abiertos = (antes.match(/@media screen/g) ?? []).length;
    expect(abiertos).toBeGreaterThan(0);
    const movimiento = leer(`${VIDRIO}/movimiento.css`);
    expect(movimiento.indexOf("@media screen")).toBeLessThan(movimiento.indexOf('.vidrio-papel) {'));
  });
});
