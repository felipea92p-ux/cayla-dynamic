// ============================================================================
// cargo-no-es-codigo-de-area.test.ts — un papel nunca dice «calidad_servicio»
// ============================================================================
// El caso que la originó (2026-11-07): la declaración de ruta, el papel que
// sostiene que la movilidad no paga impuestos ni descuentos, decía «que
// desempeño el cargo de calidad_servicio». `personas.funcion` es el código del
// área, no un cargo. Lo mismo salía en la ficha («Rol / cargo») y en Lo mío
// («Función»). Lo que se defiende acá: el papel dice el cargo de la ficha, como
// el contrato; sin cargo, el nombre del área; y ninguna pantalla vuelve a
// imprimir `.funcion` suelto.
// ============================================================================

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { AREAS_FALLBACK, cargoParaUnPapel } from "../apps/web/lib/areas";

describe("lo que dice un papel tras «el cargo de»", () => {
  it("el cargo de la ficha, el mismo del contrato", () => {
    expect(cargoParaUnPapel({ cargo: "Asesora de experiencia", funcion: "calidad_servicio" }, AREAS_FALLBACK)).toBe("Asesora de experiencia");
  });

  it("sin cargo escrito, el nombre del área, nunca su código", () => {
    expect(cargoParaUnPapel({ cargo: null, funcion: "calidad_servicio" }, AREAS_FALLBACK)).toBe("Calidad & servicio al cliente");
  });

  it("un cargo de puros espacios cuenta como vacío", () => {
    expect(cargoParaUnPapel({ cargo: "   ", funcion: "taller_produccion" }, AREAS_FALLBACK)).toBe("Taller y producción");
  });

  it("sin cargo ni área, no inventa nada", () => {
    expect(cargoParaUnPapel({ cargo: null, funcion: null }, AREAS_FALLBACK)).toBeNull();
  });
});

describe("ninguna pantalla imprime el código del área", () => {
  const WEB = join(__dirname, "..", "apps", "web");
  // Los cuatro sitios que lo imprimían. `funcion` se sigue usando para filtrar, comparar y elegir el área en un desplegable: eso está bien.
  const ARCHIVOS = [
    "app/(mio)/mio/movilidad/page.tsx",
    "app/(admin)/admin/documentacion/page.tsx",
    "app/(admin)/admin/personas/[id]/page.tsx",
    "app/(mio)/mio/page.tsx",
  ];
  // `{algo.funcion}`, `{algo?.funcion ?? "—"}` o `{algo.funcion || "…"}` como texto, o `valor={algo.funcion}` en un dato de la ficha.
  const IMPRIME = /(?<![\w-]=)\{\s*[\w?.]+\.funcion\s*(?:\}|\?\?|\|\|)/;

  for (const archivo of ARCHIVOS) {
    it(`${archivo} no lo imprime suelto`, () => {
      const lineas = readFileSync(join(WEB, archivo), "utf8").split("\n");
      const malas = lineas.filter((l) => IMPRIME.test(l) || /valor=\{[\w?.]+\.funcion\}/.test(l));
      expect(malas).toEqual([]);
    });
  }

  it("el detector sí ve las formas que había", () => {
    for (const l of ['<strong>{yo?.funcion ?? "—"}</strong>', "<strong>{quien.funcion}</strong>", "{persona.funcion} · Sede", '<dd>{misDatos.funcion || "— no registrado —"}</dd>']) {
      expect(IMPRIME.test(l)).toBe(true);
    }
    expect(/valor=\{[\w?.]+\.funcion\}/.test('<Dato label="Rol / cargo" valor={persona.funcion} />')).toBe(true);
    expect(IMPRIME.test("value={form.funcion}")).toBe(false);
  });
});
