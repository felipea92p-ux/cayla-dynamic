import { describe, it, expect } from "vitest";
import { haySinPeriodoDelCese } from "@/lib/admin/liquidacion-periodo";

// El caso real del 2026-10-29: el último periodo termina el 28/10 y el cese es el 29/10.
const PERIODOS = [
  { fecha_ini: "2026-09-28", fecha_fin: "2026-10-28" },
  { fecha_ini: "2026-08-29", fecha_fin: "2026-09-27" },
];

describe("haySinPeriodoDelCese", () => {
  it("el día siguiente al último cierre no tiene periodo (Emily y Milagritos)", () => {
    expect(haySinPeriodoDelCese("2026-10-29", PERIODOS)).toBe(true);
  });
  it("los dos extremos del periodo cuentan como dentro", () => {
    expect(haySinPeriodoDelCese("2026-09-28", PERIODOS)).toBe(false);
    expect(haySinPeriodoDelCese("2026-10-28", PERIODOS)).toBe(false);
  });
  it("un día en medio tiene periodo, y también uno del periodo anterior", () => {
    expect(haySinPeriodoDelCese("2026-10-10", PERIODOS)).toBe(false);
    expect(haySinPeriodoDelCese("2026-09-01", PERIODOS)).toBe(false);
  });
  it("antes del primer periodo cargado tampoco hay", () => {
    expect(haySinPeriodoDelCese("2026-08-28", PERIODOS)).toBe(true);
  });
  it("cuando se crea el periodo siguiente, el aviso se apaga", () => {
    const con = [{ fecha_ini: "2026-10-29", fecha_fin: "2026-11-28" }, ...PERIODOS];
    expect(haySinPeriodoDelCese("2026-10-29", con)).toBe(false);
  });
  it("sin ningún periodo cargado, todo cese está sin periodo", () => {
    expect(haySinPeriodoDelCese("2026-10-29", [])).toBe(true);
  });
});
