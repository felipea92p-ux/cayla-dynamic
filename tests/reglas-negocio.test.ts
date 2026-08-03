// ============================================================================
// reglas-negocio.test.ts — Reglas de negocio que vive el navegador
// ============================================================================
// Blinda dos cosas que el colaborador VE en pantalla:
//   · nivelPlus — los tramos del bono por objetivos. Es el GEMELO en frontend de
//     la regla que ya está blindada en SQL (fn_planilla_calcular: 100%→21%,
//     ≥60%→12.6%, <60%→nada, <30%→observación). Si alguien cambia una y no la
//     otra, la pantalla diría una cosa y la boleta pagaría otra. Esto lo ancla.
//   · formatSoles — cómo se escribe el dinero. Un formato roto siembra dudas
//     sobre montos que en realidad están bien.
// ============================================================================
import { describe, it, expect } from "vitest";
import { nivelPlus } from "@/lib/objetivos";
import { formatSoles, baseDeclaradaDe, RANGOS } from "@/lib/rangos";

describe("nivelPlus — tramos del bono por objetivos", () => {
  it("cumplir el 100% da Plus 21%", () => {
    expect(nivelPlus(10, 10)).toEqual({ etiqueta: "Plus 21%", observacion: false });
  });

  it("cumplir exactamente el 60% da Plus 12.6% (el borde cuenta a favor)", () => {
    expect(nivelPlus(6, 10)).toEqual({ etiqueta: "Plus 12.6%", observacion: false });
  });

  it("por debajo del 60% no hay plus", () => {
    expect(nivelPlus(5, 10).etiqueta).toBe("Sin plus");
  });

  it("al 50% no hay plus PERO tampoco observación (el umbral es 30%)", () => {
    expect(nivelPlus(5, 10).observacion).toBe(false);
  });

  it("por debajo del 30% se marca observación por bajo desempeño", () => {
    expect(nivelPlus(2, 10)).toEqual({ etiqueta: "Sin plus", observacion: true });
  });

  it("sin objetivos cargados no inventa nada (ni plus ni observación)", () => {
    expect(nivelPlus(0, 0)).toEqual({ etiqueta: "—", observacion: false });
  });

  it("cumplir todos de una lista corta también da el 21%", () => {
    // No depende de que el total sea 10: es proporción, no conteo.
    expect(nivelPlus(3, 3).etiqueta).toBe("Plus 21%");
  });
});

describe("formatSoles — cómo se escribe el dinero", () => {
  it("escribe miles con coma y siempre 2 decimales", () => {
    expect(formatSoles(1950)).toContain("1,950.00");
  });

  it("el cero se muestra como 0.00, no vacío", () => {
    expect(formatSoles(0)).toContain("0.00");
  });

  it("redondea a 2 decimales", () => {
    expect(formatSoles(1234.567)).toContain("1,234.57");
  });

  it("lleva el símbolo de soles", () => {
    expect(formatSoles(100)).toMatch(/S\/?/);
  });
});

// La función se llamaba `salarioSugerido` y devolvía el monto que cada rango
// *debería terminar recibiendo* (1,320 · 1,450 · 1,650 · 1,890 · 2,250 · 3,000).
// Pasó a ser `baseDeclaradaDe`: el monto que se DECLARA en el PLAME y que el
// sistema paga. No es un renombre cosmético — cambió lo que el número significa,
// y por eso estas pruebas cambiaron con él.
describe("baseDeclaradaDe — el monto que declara cada rango", () => {
  it("un rango real trae un monto positivo", () => {
    const monto = baseDeclaradaDe("cayla");
    expect(typeof monto).toBe("number");
    expect(monto as number).toBeGreaterThan(0);
  });

  it("un rango inexistente no inventa un monto (devuelve indefinido)", () => {
    expect(baseDeclaradaDe("rango-que-no-existe")).toBeUndefined();
  });

  // Ninguna base puede quedar por debajo de la RMV: sería declarar menos que el
  // mínimo legal. Colibrí y cayla están clavados en ella a propósito, así que este
  // es el guardián de que nadie las baje por descuido — y el recordatorio de que
  // hay que subirlas cuando la RMV suba.
  it("ninguna base declarada cae por debajo de la RMV vigente", () => {
    const RMV = 1130; // D.S. 006-2024-TR, vigente al 2026-08-03
    for (const r of RANGOS) {
      expect(r.baseDeclarada, `${r.label} declara menos que la RMV`).toBeGreaterThanOrEqual(RMV);
    }
  });

  // Las bandas tienen que subir con el rango, o el rango no ordena nada.
  it("las bases no bajan al subir de rango", () => {
    const porOrden = [...RANGOS].sort((a, b) => a.orden - b.orden);
    for (let i = 1; i < porOrden.length; i++) {
      expect(
        porOrden[i].baseDeclarada,
        `${porOrden[i].label} declara menos que ${porOrden[i - 1].label}`,
      ).toBeGreaterThanOrEqual(porOrden[i - 1].baseDeclarada);
    }
  });
});
