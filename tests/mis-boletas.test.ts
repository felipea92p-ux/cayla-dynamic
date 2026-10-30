// ============================================================================
// mis-boletas.test.ts — cómo se nombra un periodo y una hoja, y cuántas boletas
// nuevas tiene una persona (0482)
// ============================================================================
// Tres sitios (el globito del menú de /mio, la pestaña «Boletas» y la Bandeja)
// contestan «¿cuántas boletas nuevas tengo?» con `contarBoletasNuevas`. Lo que se
// defiende: que el periodo del 29 al 28 se llame por el mes en que TERMINA, y que
// el nombre con que se guarda una hoja no lleve nada que rompa en un teléfono.
// ============================================================================
import { describe, expect, it } from "vitest";
import { contarBoletasNuevas, contarBoletasPorFirmar, nombreDeArchivoDeBoleta, nombreDelPeriodo } from "@/lib/mis-boletas";

describe("nombreDelPeriodo", () => {
  it("se llama por el mes en que termina, no por el que empieza", () => {
    // Del 29 de julio al 28 de agosto: es «Agosto».
    expect(nombreDelPeriodo("2026-08-28")).toBe("Agosto 2026");
  });

  it("el año también es el de fecha_fin: el periodo que cierra en enero es de enero", () => {
    expect(nombreDelPeriodo("2027-01-28")).toBe("Enero 2027");
  });

  it("sin año y en minúscula, para meterlo en una frase", () => {
    expect(nombreDelPeriodo("2026-09-28", { conAnio: false, minuscula: true })).toBe("septiembre");
  });
});

describe("nombreDeArchivoDeBoleta", () => {
  it("una sola hoja no lleva número", () => {
    expect(nombreDeArchivoDeBoleta("2026-08-28", 1, 1, "pdf")).toBe("Boleta-Agosto-2026.pdf");
  });

  it("varias hojas se numeran desde 1", () => {
    expect(nombreDeArchivoDeBoleta("2026-08-28", 2, 3, "jpg")).toBe("Boleta-Agosto-2026-2.jpg");
  });

  it("la extensión se normaliza: sin punto y en minúscula", () => {
    expect(nombreDeArchivoDeBoleta("2026-08-28", 1, 1, ".PDF")).toBe("Boleta-Agosto-2026.pdf");
  });
});

describe("contarBoletasNuevas", () => {
  it("cuenta solo las publicadas que todavía no abrió", () => {
    expect(contarBoletasNuevas([
      { estado: "publicada", vista_at: null },
      { estado: "publicada", vista_at: "2026-09-06T10:00:00Z" },
      { estado: "papel", vista_at: null },
      { estado: null, vista_at: null },
    ])).toBe(1);
  });

  it("sin filas, cero", () => {
    expect(contarBoletasNuevas([])).toBe(0);
  });
});

describe("contarBoletasPorFirmar (0532)", () => {
  it("cuenta las publicadas sin firmar, abiertas o no: es lo que dice el globito", () => {
    expect(contarBoletasPorFirmar([
      { estado: "publicada", recibida_at: null },
      { estado: "publicada", recibida_at: null },
      { estado: "publicada", recibida_at: "2026-09-06T10:00:00Z" },
      { estado: "papel", recibida_at: null },
      { estado: "anulada", recibida_at: null },
      { estado: null, recibida_at: null },
    ])).toBe(2);
  });

  it("sin filas, cero", () => {
    expect(contarBoletasPorFirmar([])).toBe(0);
  });
});
