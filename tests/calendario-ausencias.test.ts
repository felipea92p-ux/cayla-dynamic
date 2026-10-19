// calendario-ausencias.test.ts — qué casilla pinta cada día del mes
import { describe, expect, it } from "vitest";
import { diasDelMes, filasDelMes, mesVecino, type AusenciaDeCalendario } from "../apps/web/lib/admin/calendario-ausencias";

const aus = (o: Partial<AusenciaDeCalendario> & { inicio: string; fin: string }): AusenciaDeCalendario => ({
  id: "x", personaId: "p1", nombre: "Elena Integrante", tipo: "permiso_personal", tipoNombre: "Permiso personal",
  pendiente: false, anulada: false, ...o,
});

describe("diasDelMes", () => {
  it("octubre tiene 31, febrero 28 o 29", () => {
    expect(diasDelMes(2026, 10)).toBe(31);
    expect(diasDelMes(2026, 2)).toBe(28);
    expect(diasDelMes(2028, 2)).toBe(29);
  });
});

describe("filasDelMes", () => {
  it("pinta solo los días que la ausencia cubre, de inicio a fin inclusive", () => {
    const [fila] = filasDelMes([aus({ inicio: "2026-10-05", fin: "2026-10-09" })], 2026, 10);
    const pintados = fila.casillas.filter((c) => c.ausencia).map((c) => c.dia);
    expect(pintados).toEqual([5, 6, 7, 8, 9]);
  });

  it("una ausencia que viene del mes anterior se pinta desde el día 1", () => {
    const [fila] = filasDelMes([aus({ inicio: "2026-09-14", fin: "2026-10-12" })], 2026, 10);
    const pintados = fila.casillas.filter((c) => c.ausencia).map((c) => c.dia);
    expect(pintados[0]).toBe(1);
    expect(pintados.at(-1)).toBe(12);
    expect(pintados).toHaveLength(12);
  });

  it("una ausencia que sigue en el mes siguiente se pinta hasta el último día", () => {
    const [fila] = filasDelMes([aus({ inicio: "2026-10-28", fin: "2026-11-03" })], 2026, 10);
    expect(fila.casillas.filter((c) => c.ausencia).map((c) => c.dia)).toEqual([28, 29, 30, 31]);
  });

  it("las anuladas no se dibujan, y quien solo tiene anuladas no tiene fila", () => {
    expect(filasDelMes([aus({ inicio: "2026-10-08", fin: "2026-10-08", anulada: true })], 2026, 10)).toEqual([]);
  });

  it("lo pendiente de aprobar se marca para dibujarlo rayado", () => {
    const [fila] = filasDelMes([aus({ inicio: "2026-10-26", fin: "2026-10-27", pendiente: true })], 2026, 10);
    expect(fila.casillas[25].ausencia?.pendiente).toBe(true);
  });

  it("una fila por persona, ordenadas por nombre, con todas sus ausencias del mes", () => {
    const filas = filasDelMes([
      aus({ id: "a", personaId: "p2", nombre: "Bruno Integrante", inicio: "2026-10-26", fin: "2026-10-27" }),
      aus({ id: "b", inicio: "2026-10-02", fin: "2026-10-02" }),
      aus({ id: "c", inicio: "2026-10-09", fin: "2026-10-09" }),
    ], 2026, 10);
    expect(filas.map((f) => f.nombre)).toEqual(["Bruno Integrante", "Elena Integrante"]);
    expect(filas[1].casillas.filter((c) => c.ausencia).map((c) => c.dia)).toEqual([2, 9]);
  });

  it("una ausencia fuera del mes no genera fila", () => {
    expect(filasDelMes([aus({ inicio: "2026-08-01", fin: "2026-08-03" })], 2026, 10)).toEqual([]);
  });
});

describe("mesVecino", () => {
  it("cruza el año en los dos sentidos", () => {
    expect(mesVecino(2026, 12, 1)).toEqual({ anio: 2027, mes: 1 });
    expect(mesVecino(2026, 1, -1)).toEqual({ anio: 2025, mes: 12 });
    expect(mesVecino(2026, 10, 1)).toEqual({ anio: 2026, mes: 11 });
  });
});
