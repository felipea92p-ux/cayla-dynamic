// ============================================================================
// planilla-feriados.test.ts — Por qué un feriado no le corresponde a alguien
// ============================================================================
// Desde la 0505 «no corresponde» tiene dos motivos: anterior al ingreso, o
// posterior al cese. Hasta entonces la tabla de Planilla y el panel de la
// persona escribían cada uno su propia frase y solo conocían el primero, así
// que un feriado posterior al cese se habría mostrado como si se hubiera
// pagado por horas. La boleta usa la misma función para decidir qué feriados
// lista: si alguna vez dejara pasar uno que no corresponde, imprimiría una
// línea de feriado a quien ya se fue.
// ============================================================================
import { describe, expect, it } from "vitest";
import { feriadoNoCorresponde } from "@/lib/admin/planilla/formato";

describe("feriadoNoCorresponde", () => {
  it("anterior al ingreso: no corresponde, y lo dice", () => {
    expect(feriadoNoCorresponde({ antes_ingreso: true })).toBe("no corresponde (anterior al ingreso)");
  });

  it("posterior al cese: no corresponde, y lo dice con su motivo (0505)", () => {
    expect(feriadoNoCorresponde({ antes_ingreso: false, despues_cese: true }))
      .toBe("no corresponde (posterior al cese)");
  });

  it("dentro del vínculo: sí corresponde (null)", () => {
    expect(feriadoNoCorresponde({ antes_ingreso: false, despues_cese: false })).toBeNull();
  });

  it("sin la 0505 pegada, despues_cese no llega: se lee como antes, sin romperse", () => {
    expect(feriadoNoCorresponde({ antes_ingreso: false })).toBeNull();
  });
});
