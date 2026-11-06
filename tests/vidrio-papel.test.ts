import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Un documento se revisa en pantalla con los colores con que va a salir. Son dos copias de la misma lista: en globals.css, la del bloque de impresión; en piezas.css, la del papel con
// vidrio. Esa lista ya se desincronizó una vez (ver el comentario en globals.css), y la señal sería un contrato que en pantalla se ve de un color y en el papel de otro.

const WEB = path.resolve(import.meta.dirname, "../apps/web");
const leer = (f: string) => readFileSync(path.join(WEB, f), "utf8");
const tokens = (css: string) => Object.fromEntries([...css.matchAll(/(--color-[a-z-]+): ([^;]+);/g)].map((m) => [m[1], m[2]]));

describe("el papel en su bandeja", () => {
  const impresion = /@media print \{.*?:root\[data-tema="oscuro"\] \{(.*?)\n  \}/s.exec(leer("app/globals.css"))![1];
  const piezas = leer("app/estilos/vidrio/piezas.css");
  const papel = /\[data-vidrio="panel"\] \.hoja \{\n    color-scheme: light;(.*?)\n  \}/s.exec(piezas)![1];

  it("lleva los mismos colores que al imprimir", () => {
    expect(Object.keys(tokens(impresion))).toHaveLength(13);
    expect(tokens(papel)).toEqual(tokens(impresion));
  });

  it("la firma va directo sobre el papel, también en oscuro", () => {
    expect(papel).toContain("--firma-fondo: transparent;");
    expect(papel).toContain("--firma-aire: 0;");
  });

  it("el papel y su bandeja solo existen en pantalla", () => {
    const antes = piezas.slice(0, piezas.indexOf('[data-vidrio="panel"] .hoja {\n    color-scheme'));
    const abiertos = (antes.match(/@media screen/g) ?? []).length;
    expect(abiertos).toBeGreaterThan(0);
    const movimiento = leer("app/estilos/vidrio/movimiento.css");
    expect(movimiento.indexOf("@media screen")).toBeLessThan(movimiento.indexOf('[data-vidrio="panel"] .hoja {'));
  });
});
