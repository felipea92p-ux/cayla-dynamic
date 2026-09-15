import { describe, expect, it } from "vitest";
import { leCorrespondeHorario } from "@cayla-dynamic/shared";

// ============================================================================
// A quién se le pide horario
// ============================================================================
// Horarios base avisaba «necesita horario» a la Gerencia General y a quien
// factura por RxH (2026-09-15). La regla ya estaba en la Bandeja (0385) y en
// Correcciones; estas pruebas cuidan que la versión compartida diga lo mismo.

describe("leCorrespondeHorario", () => {
  it("un locador por honorarios no lleva horario", () => {
    expect(leCorrespondeHorario("rxh", false)).toBe(false);
  });

  it("sin vínculo laboral tampoco", () => {
    expect(leCorrespondeHorario("no_trabajador", false)).toBe(false);
  });

  it("el personal de dirección no lleva horario aunque esté en planilla", () => {
    expect(leCorrespondeHorario("planilla", true)).toBe(false);
  });

  it("planilla, prueba y practicante sí lo llevan", () => {
    expect(leCorrespondeHorario("planilla", false)).toBe(true);
    expect(leCorrespondeHorario("prueba", false)).toBe(true);
    expect(leCorrespondeHorario("practicante", false)).toBe(true);
  });

  it("un dato que no llegó sigue pidiendo horario", () => {
    expect(leCorrespondeHorario(undefined, undefined)).toBe(true);
    expect(leCorrespondeHorario(null, null)).toBe(true);
  });
});
