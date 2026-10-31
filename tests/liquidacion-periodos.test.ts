import { describe, it, expect } from "vitest";
import {
  normalizarPeriodosAnteriores, resumenPeriodosAnteriores, dondeSePaga,
} from "@/lib/admin/liquidacion-periodos";

// Los dos casos reales del 2026-10-29: Emily y Milagritos cesaron el 29/10 y su
// sueldo del 28/09 al 28/10 —todavía en una planilla abierta— no aparecía.
const EMILY = [{ periodo_id: "p1", fecha_ini: "2026-09-28", fecha_fin: "2026-10-28", estado: "abierto", total: "438.42" }];

describe("normalizarPeriodosAnteriores", () => {
  it("acepta el monto como texto, que es como lo manda el rpc", () => {
    expect(normalizarPeriodosAnteriores(EMILY)).toEqual([
      { periodo_id: "p1", fecha_ini: "2026-09-28", fecha_fin: "2026-10-28", estado: "abierto", total: 438.42 },
    ]);
  });

  it("descarta lo que no se entiende en vez de pintar un monto inventado", () => {
    expect(normalizarPeriodosAnteriores(null)).toEqual([]);
    expect(normalizarPeriodosAnteriores("x")).toEqual([]);
    expect(normalizarPeriodosAnteriores([{ periodo_id: "p", fecha_ini: "2026-01-01", fecha_fin: "2026-01-31", total: "abc" }])).toEqual([]);
    expect(normalizarPeriodosAnteriores([{ fecha_ini: "2026-01-01", fecha_fin: "2026-01-31", total: 10 }])).toEqual([]);
  });

  it("no lista un periodo en cero ni negativo", () => {
    expect(normalizarPeriodosAnteriores([{ ...EMILY[0], total: 0 }])).toEqual([]);
    expect(normalizarPeriodosAnteriores([{ ...EMILY[0], total: -5 }])).toEqual([]);
  });

  it("los ordena del más viejo al más nuevo", () => {
    const filas = normalizarPeriodosAnteriores([
      { ...EMILY[0], periodo_id: "b", fecha_ini: "2026-10-29", fecha_fin: "2026-11-28" },
      { ...EMILY[0], periodo_id: "a" },
    ]);
    expect(filas.map((f) => f.periodo_id)).toEqual(["a", "b"]);
  });
});

describe("resumenPeriodosAnteriores", () => {
  it("Emily: S/ 438.42 del periodo anterior + S/ 145.17 de su liquidación = S/ 583.59", () => {
    const r = resumenPeriodosAnteriores(normalizarPeriodosAnteriores(EMILY), 145.17);
    expect(r.suma).toBe(438.42);
    expect(r.totalGeneral).toBe(583.59);
  });

  it("suma en céntimos, sin los restos de coma flotante", () => {
    const filas = normalizarPeriodosAnteriores([
      { ...EMILY[0], periodo_id: "a", total: 0.1 },
      { ...EMILY[0], periodo_id: "b", fecha_ini: "2026-10-29", total: 0.2 },
    ]);
    expect(resumenPeriodosAnteriores(filas, 0).suma).toBe(0.3);
  });

  it("sin periodos anteriores el total general es el de la liquidación, intacto", () => {
    expect(resumenPeriodosAnteriores([], 145.17)).toEqual({ suma: 0, totalGeneral: 145.17 });
  });
});

describe("dondeSePaga", () => {
  it("un periodo abierto se paga al cerrarlo", () => {
    expect(dondeSePaga("abierto")).toMatch(/se paga al cerrar/);
  });
  it("un periodo pagado a otros grupos manda a revisar Planilla", () => {
    expect(dondeSePaga("pagado")).toMatch(/Planilla/);
  });
});
