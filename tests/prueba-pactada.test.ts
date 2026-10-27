// ============================================================================
// prueba-pactada.test.ts — lo que se elige en Equipo y lo que se guarda (0556)
// ============================================================================
import { describe, it, expect } from "vitest";
import { leerPruebaDelForm, pruebaDeLoGuardado } from "@/lib/admin/prueba-pactada";

describe("de lo guardado a lo que se ve", () => {
  it("null es la ley, 0 es sin prueba, N es menor", () => {
    expect(pruebaDeLoGuardado(null)).toEqual({ modo: "ley", dias: "" });
    expect(pruebaDeLoGuardado(undefined)).toEqual({ modo: "ley", dias: "" });
    expect(pruebaDeLoGuardado(0)).toEqual({ modo: "sin", dias: "" });
    expect(pruebaDeLoGuardado(45)).toEqual({ modo: "menor", dias: "45" });
  });
});

describe("de lo que se ve a lo que se guarda", () => {
  it("la ley no pide nada y guarda null", () => {
    expect(leerPruebaDelForm({ modo: "ley", dias: "", motivo: "" })).toEqual({ ok: true, dias: null, motivo: "" });
  });
  it("sin prueba pide motivo y guarda 0", () => {
    expect(leerPruebaDelForm({ modo: "sin", dias: "", motivo: "Reingreso" })).toEqual({ ok: true, dias: 0, motivo: "Reingreso" });
    expect(leerPruebaDelForm({ modo: "sin", dias: "", motivo: "  " }).ok).toBe(false);
  });
  it("un periodo menor guarda sus días", () => {
    expect(leerPruebaDelForm({ modo: "menor", dias: "45", motivo: "Pactado en el contrato" })).toEqual({ ok: true, dias: 45, motivo: "Pactado en el contrato" });
  });
  it("rechaza días que no son un entero de 1 a 89", () => {
    for (const dias of ["", "abc", "0", "90", "12.5", "-3", "1e2"]) {
      expect(leerPruebaDelForm({ modo: "menor", dias, motivo: "Pactado" }).ok).toBe(false);
    }
    expect(leerPruebaDelForm({ modo: "menor", dias: "89", motivo: "Pactado" }).ok).toBe(true);
    expect(leerPruebaDelForm({ modo: "menor", dias: "1", motivo: "Pactado" }).ok).toBe(true);
  });
  it("un periodo menor sin motivo se rechaza antes de viajar", () => {
    const r = leerPruebaDelForm({ modo: "menor", dias: "30", motivo: "" });
    expect(r.ok).toBe(false);
  });
});
