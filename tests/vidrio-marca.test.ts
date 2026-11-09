// ============================================================================
// vidrio-marca.test.ts — los colores del vidrio se leen, y no salen al papel
// ============================================================================
// Mide los tokens de estilos/vidrio/marca.css sin navegador: 4.5:1 para el texto (WCAG 1.4.3) y 3:1 para el borde de un control
// (WCAG 1.4.11), en los dos temas. Lo que da por debajo está escrito aquí con su número: si mejora o empeora, la prueba avisa.
// `tema:auditar` mide la página real; esto mide que la paleta misma no traiga el defecto.
// ============================================================================
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { color, contraste } from "../apps/web/tema/contraste-calculado";

const RAIZ = join(__dirname, "..");
const leer = (ruta: string) => readFileSync(join(RAIZ, ruta), "utf8").replace(/\/\*[\s\S]*?\*\//g, "");
const globals = leer("apps/web/app/globals.css");
const marca = leer("apps/web/app/estilos/vidrio/marca.css");
const marco = leer("apps/web/app/estilos/vidrio/marco.css");

function cuerpo(css: string, cabecera: string): string {
  const i = css.indexOf(cabecera);
  if (i < 0) throw new Error(`no encontré «${cabecera}»`);
  const inicio = css.indexOf("{", i);
  return css.slice(inicio + 1, css.indexOf("}", inicio));
}
function tokens(bloque: string): Record<string, string> {
  const salida: Record<string, string> = {};
  for (const m of bloque.matchAll(/--color-([a-z-]+):\s*(#[0-9a-f]{6})/gi)) salida[m[1]] = m[2].toLowerCase();
  return salida;
}

const hoyClaro = tokens(cuerpo(globals, "@theme {"));
const hoyOscuro = tokens(cuerpo(globals, ':root[data-tema="oscuro"] {'));
const TEMAS = {
  claro: { ...hoyClaro, ...tokens(cuerpo(marca, ':root[data-vidrio="panel"]:not([data-tema="oscuro"]) {')) },
  oscuro: { ...hoyClaro, ...hoyOscuro, ...tokens(cuerpo(marca, ':root[data-vidrio="panel"][data-tema="oscuro"] {')) },
};
const SUPERFICIES = ["crema", "papel", "hueso"];
const TEXTOS = ["tinta", "taupe", "rojo", "rojo-profundo", "verde", "ambar", "pizarra", "azul", "ceniza"];

const razon = (a: string, b: string) => contraste(color(a, {}), color(b, {}));

// Lo que hoy no llega, medido: se conserva a la vista hasta decidirlo. Son de la paleta clara de siempre, igual en los dos sistemas.
const DEBAJO: Record<string, number> = {
  "claro:rojo/hueso": 4.23,
};

describe("los colores del vidrio se leen", () => {
  for (const [nombre, tema] of Object.entries(TEMAS)) {
    for (const texto of TEXTOS) {
      for (const superficie of SUPERFICIES) {
        const clave = `${nombre}:${texto}/${superficie}`;
        it(`${clave} pasa 4.5:1, o está declarado`, () => {
          const r = razon(tema[texto], tema[superficie]);
          if (DEBAJO[clave] !== undefined) expect(r).toBeCloseTo(DEBAJO[clave], 1);
          else expect(r, `${tema[texto]} sobre ${tema[superficie]} da ${r.toFixed(2)}:1`).toBeGreaterThanOrEqual(4.5);
        });
      }
    }
    for (const superficie of SUPERFICIES) {
      it(`${nombre}: el borde de un control pasa 3:1 sobre ${superficie}`, () => {
        const r = razon(tema["borde-control"], tema[superficie]);
        expect(r, `da ${r.toFixed(2)}:1`).toBeGreaterThanOrEqual(3);
      });
    }
  }

  it("la prueba puede fallar: el rojo del oscuro de hoy no pasaba sobre papel", () => {
    expect(razon(hoyOscuro.rojo, hoyOscuro.papel)).toBeLessThan(4.5);
  });
});

describe("el vidrio no sale al papel ni al terminal", () => {
  /** Lo que queda de un CSS fuera de `@media screen`, contando llaves. */
  function fueraDePantalla(css: string): string {
    let salida = css;
    for (;;) {
      const i = salida.indexOf("@media screen");
      if (i < 0) return salida;
      let hondura = 0;
      let j = salida.indexOf("{", i);
      for (; j < salida.length; j++) {
        if (salida[j] === "{") hondura++;
        else if (salida[j] === "}" && --hondura === 0) break;
      }
      salida = salida.slice(0, i) + salida.slice(j + 1);
    }
  }

  it("colores, fondo y botón viven solo en pantalla", () => {
    expect(fueraDePantalla(marca).trim()).toBe("");
    // Un @keyframes es global y no pinta nada por sí solo.
    expect(fueraDePantalla(marco).replace(/@keyframes vidrio-[\w-]+\s*\{[^{}]*\{[^{}]*\}\s*\}/g, "").trim()).toBe("");
  });

  it("cada superficie se nombra: ningún [data-vidrio] a secas, que alcanzaría a las dos sin quererlo", () => {
    for (const css of [marca, marco]) {
      for (const m of css.matchAll(/\[data-vidrio(="[a-z]+")?\]/g)) expect(['="panel"', '="terminal"']).toContain(m[1]);
    }
  });

  it("el terminal lleva los mismos colores que el panel: comparte sus dos bloques, no tiene una copia", () => {
    for (const tema of [':not([data-tema="oscuro"])', '[data-tema="oscuro"]']) {
      expect(marca).toMatch(new RegExp(`:root\\[data-vidrio="terminal"\\]${tema.replace(/[[\]()]/g, "\\$&")},\\s*:root\\[data-vidrio="panel"\\]`));
    }
    expect(marca.match(/--color-crema:/g)).toHaveLength(1);
  });

  it("del marco, al terminal solo le llegan el fondo y el botón del tema: el menú y la cabecera del panel no", () => {
    const reglasDelTerminal = [...marco.matchAll(/[^{};]*\[data-vidrio="terminal"\][^{};,]*/g)].map((m) => m[0]);
    expect(reglasDelTerminal.length).toBeGreaterThan(0);
    for (const regla of reglasDelTerminal) expect(regla).toMatch(/vidrio-aurora|boton-tema/);
  });

  it("los colores fijos y los del terminal no se tocan", () => {
    for (const nombre of ["tinta-fija", "crema-fija", "azul", "ceniza"]) expect(marca).not.toContain(`--color-${nombre}:`);
  });
});
