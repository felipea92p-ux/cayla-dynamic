// ============================================================================
// vidrio-contraste.test.ts — la letra y el borde se leen sobre un degradado
// ============================================================================
// `tema:auditar` lee la página real pero solo suma colores planos, así que un degradado no lo ve. Esta prueba mide el peor punto del degradado sobre
// todo lo que puede haber detrás, en los dos temas: 4.5:1 para la letra (WCAG 1.4.3) y 3:1 para el borde de un control (WCAG 1.4.11).
//
// Dynamic todavía no tiene recetas de vidrio. Las de aquí son de ensayo y usan los tokens reales; en la Etapa 1 se le agrega la hoja de recetas a
// `temasDe(css, recetas)` y una fila a `RECETAS`. Traída de CAYLA Retail; la utilidad vive en `apps/web/tema/contraste-calculado.ts`.
// ============================================================================
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { color, contraste, muestras, peorBorde, peorLetra, pintados, temasDe, UMBRAL, type Rgba } from "../apps/web/tema/contraste-calculado";

const css = readFileSync(join(__dirname, "../apps/web/app/globals.css"), "utf8");
const TEMAS = temasDe(css);
const NOMBRES = ["claro", "oscuro"] as const;

const BLANCO: Rgba = [255, 255, 255, 1];
const NEGRO: Rgba = [0, 0, 0, 1];
const SIN_VARS = {};

describe("la fórmula y los colores", () => {
  it("los extremos de WCAG: negro sobre blanco es 21:1, y un color contra sí mismo es 1:1", () => {
    expect(contraste(NEGRO, BLANCO)).toBeCloseTo(21, 5);
    expect(contraste(BLANCO, BLANCO)).toBe(1);
  });

  it("entiende hex, rgb() y transparente, con su alfa", () => {
    expect(color("#fff", SIN_VARS)).toEqual([255, 255, 255, 1]);
    expect(color("#ff000080", SIN_VARS)[3]).toBeCloseTo(0.502, 2);
    expect(color("rgb(1 2 3 / 50%)", SIN_VARS)).toEqual([1, 2, 3, 0.5]);
    expect(color("rgba(1, 2, 3, 0.25)", SIN_VARS)).toEqual([1, 2, 3, 0.25]);
    expect(color("transparent", SIN_VARS)[3]).toBe(0);
  });

  it("color-mix con transparente baja el alfa y no cambia el color, también en oklab (el `bg-rojo/10` de Tailwind)", () => {
    expect(color("color-mix(in srgb, #ff0000 40%, transparent)", SIN_VARS)).toEqual([255, 0, 0, 0.4]);
    expect(color("color-mix(in oklab, #ff0000 10%, transparent)", SIN_VARS)).toEqual([255, 0, 0, 0.1]);
  });

  it("color-mix de dos colores opacos promedia los canales", () => {
    expect(color("color-mix(in srgb, #000000 50%, #ffffff)", SIN_VARS)).toEqual([127.5, 127.5, 127.5, 1]);
  });

  it("nunca adivina: lo que no entiende es un error, no un número", () => {
    expect(() => color("var(--no-existe)", SIN_VARS)).toThrow(/no existe/);
    expect(() => color("azulito", SIN_VARS)).toThrow(/no entiendo/);
    expect(() => color("#12", SIN_VARS)).toThrow(/no entiendo/);
    expect(() => color("color-mix(in oklab, #000000 50%, #ffffff)", SIN_VARS)).toThrow(/solo sé mezclar/);
    expect(() => peorLetra("#000", "linear-gradient(90deg, #fff)", SIN_VARS, ["#fff"])).toThrow(/dos colores/);
  });
});

describe("el degradado se recorre entero", () => {
  // DEBE FALLAR. Este gris pasa 4.5:1 contra el blanco y contra el negro, así que mirando solo los extremos se daría por bueno.
  it("una letra que pasa en los dos extremos falla a mitad de camino, cuando el fondo se le parece", () => {
    const letra = "#767676";
    expect(peorLetra(letra, "#fff", SIN_VARS, ["#fff"])).toBeGreaterThanOrEqual(UMBRAL.texto);
    expect(peorLetra(letra, "#000", SIN_VARS, ["#000"])).toBeGreaterThanOrEqual(UMBRAL.texto);
    expect(peorLetra(letra, "linear-gradient(180deg, #fff, #000)", SIN_VARS, ["#fff"])).toBeLessThan(1.2);
  });

  it("sin ángulo, el primer color no se pierde: negro sobre negro-a-blanco es 1:1", () => {
    expect(peorLetra("#000", "linear-gradient(#000, #fff)", SIN_VARS, ["#fff"])).toBeCloseTo(1, 5);
  });

  it("entiende las posiciones de cada parada", () => {
    expect(muestras("linear-gradient(to bottom, #fff 0%, #fff 40%, #000 100%)", SIN_VARS).at(-1)).toEqual([0, 0, 0, 1]);
    expect(muestras("linear-gradient(270deg, #fff 10px 20px, #000 var(--a))", SIN_VARS).at(-1)).toEqual([0, 0, 0, 1]);
  });

  it("varias capas se pintan una sobre otra, la de arriba primero", () => {
    expect(pintados("linear-gradient(#000, #000), #fff", BLANCO, SIN_VARS).every((c) => c[0] === 0)).toBe(true);
    expect(pintados("transparent, #000", BLANCO, SIN_VARS).every((c) => c[0] === 0)).toBe(true);
  });

  it("lo que hay detrás cuenta: un vidrio casi transparente deja pasar la superficie", () => {
    const vidrio = "linear-gradient(180deg, color-mix(in srgb, #fff 10%, transparent), color-mix(in srgb, #fff 10%, transparent))";
    expect(peorLetra("#000", vidrio, SIN_VARS, ["#fff"])).toBeGreaterThan(15);
    expect(peorLetra("#000", vidrio, SIN_VARS, ["#fff", "#333"])).toBeLessThan(UMBRAL.texto);
  });
});

/** Recetas de ensayo: la forma que tiene el vidrio de Retail, hecha con los tokens de Dynamic. */
const GOTA = "linear-gradient(180deg, color-mix(in srgb, var(--color-papel) 58%, transparent), color-mix(in srgb, var(--color-papel) 22%, transparent))";
const AHUMADO = "linear-gradient(180deg, color-mix(in srgb, var(--color-tinta) 72%, transparent), color-mix(in srgb, var(--color-tinta) 93%, transparent))";
const RECETAS: Array<[nombre: string, letra: string, fondo: string]> = [
  ["la gota, con letra de tinta", "var(--color-tinta)", GOTA],
  ["el ahumado, con letra de crema", "var(--color-crema)", AHUMADO],
];

describe("una receta de vidrio pasa el umbral en los dos temas", () => {
  for (const tema of NOMBRES) {
    for (const [nombre, letra, fondo] of RECETAS) {
      it(`${tema}: ${nombre} ≥ ${UMBRAL.texto}:1`, () => {
        expect(peorLetra(letra, fondo, TEMAS[tema])).toBeGreaterThanOrEqual(UMBRAL.texto);
      });
    }

    // DEBE FALLAR: el mismo vidrio con una letra aguada, y el borde decorativo usado como borde de un control.
    it(`${tema}: una letra aguada sobre la gota NO alcanza`, () => {
      expect(peorLetra("color-mix(in srgb, var(--color-taupe) 60%, transparent)", GOTA, TEMAS[tema])).toBeLessThan(UMBRAL.texto);
    });
    it(`${tema}: \`sand\` NO alcanza como borde de un control`, () => {
      expect(peorBorde("var(--color-sand)", TEMAS[tema])).toBeLessThan(UMBRAL.bordeControl);
    });

    it(`${tema}: el borde de control pasa ${UMBRAL.bordeControl}:1 sobre todo lo que puede haber detrás`, () => {
      expect(peorBorde("var(--color-borde-control)", TEMAS[tema])).toBeGreaterThanOrEqual(UMBRAL.bordeControl);
    });
    it(`${tema}: el borde de control pasa también sobre un campo de vidrio`, () => {
      expect(peorBorde("var(--color-borde-control)", TEMAS[tema], { fondo: GOTA })).toBeGreaterThanOrEqual(UMBRAL.bordeControl);
    });
  }
});

// La línea base de los tokens, medida el 2026-11-05. Estos pares NO alcanzan 4.5:1 como texto normal: se anotan para que la Etapa 1 los vea y para que
// empeorar otro par cualquiera se ponga en rojo, no para aprobarlos. Si un retono arregla uno, esta prueba pide sacarlo de la lista.
const DEUDA: Record<string, number> = {
  "claro: rojo sobre hueso": 4.23,
  "claro: rojo sobre sand": 4.18,
  "oscuro: rojo sobre papel": 4.28,
  "oscuro: rojo sobre sand": 3.64,
};

describe("la línea base de los tokens como texto (4.5:1)", () => {
  const LETRAS = ["tinta", "taupe", "rojo", "rojo-profundo", "verde", "ambar", "pizarra", "azul", "ceniza"];
  const SUPERFICIES_DE_TEXTO = ["crema", "papel", "hueso", "sand"];
  for (const tema of NOMBRES) {
    for (const letra of LETRAS) {
      for (const superficie of SUPERFICIES_DE_TEXTO) {
        const par = `${tema}: ${letra} sobre ${superficie}`;
        it(par, () => {
          const ratio = peorLetra(`var(--color-${letra})`, null, TEMAS[tema], [`var(--color-${superficie})`]);
          if (par in DEUDA) {
            expect(ratio, "este par ya cumple: sácalo de DEUDA").toBeLessThan(UMBRAL.texto);
            expect(ratio).toBeCloseTo(DEUDA[par], 1);
          } else {
            expect(ratio).toBeGreaterThanOrEqual(UMBRAL.texto);
          }
        });
      }
    }
  }
});
