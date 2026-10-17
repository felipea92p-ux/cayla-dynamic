import { describe, it, expect } from "vitest";
import { mesesEntreIncluidos, mesesParaLaBase, problemaDelPago, repartirPago, sumaDelPago } from "@/lib/educacion-adelantado";

const base = { desde: "2026-08", hasta: "2026-12", sabe: "total" as const, total: 600, cada: 0, correcciones: {} };

describe("mesesEntreIncluidos", () => {
  it("agosto a diciembre son 5 meses, ambos incluidos", () => {
    expect(mesesEntreIncluidos("2026-08", "2026-12")).toEqual(["2026-08", "2026-09", "2026-10", "2026-11", "2026-12"]);
  });
  it("cruza el año", () => {
    expect(mesesEntreIncluidos("2026-11", "2027-02")).toHaveLength(4);
  });
  it("al revés no hay meses", () => {
    expect(mesesEntreIncluidos("2026-12", "2026-08")).toEqual([]);
  });
});

describe("repartirPago", () => {
  it("solo sabe el total: se divide entre los meses", () => {
    const r = repartirPago(base);
    expect(r.map((x) => x.monto)).toEqual([120, 120, 120, 120, 120]);
    expect(r.every((x) => x.origen === "calculado")).toBe(true);
  });
  it("los céntimos que sobran van al último mes y la suma da exacto", () => {
    const r = repartirPago({ ...base, desde: "2026-08", hasta: "2026-10", total: 100 });
    expect(r.map((x) => x.monto)).toEqual([33.33, 33.33, 33.34]);
    expect(sumaDelPago(r)).toBe(100);
  });
  it("lo corregido a mano se respeta y el resto se reparte entre los otros meses", () => {
    const r = repartirPago({ ...base, correcciones: { "2026-08": { monto: 180, motivo: "incluye la matrícula" } } });
    expect(r.map((x) => x.monto)).toEqual([180, 105, 105, 105, 105]);
    expect(r[0]).toMatchObject({ origen: "manual", motivo: "incluye la matrícula" });
    expect(sumaDelPago(r)).toBe(600);
  });
  it("si sabe el de cada mes, cada mes lleva ese monto", () => {
    const r = repartirPago({ ...base, sabe: "cada", cada: 130 });
    expect(r.map((x) => [x.monto, x.origen])).toEqual(Array(5).fill([130, "puesto"]));
  });
});

describe("problemaDelPago", () => {
  it("un solo mes no es un pago adelantado", () => {
    expect(problemaDelPago(repartirPago({ ...base, hasta: "2026-08" }), "total", 600)).toMatch(/al menos dos meses/);
  });
  it("corregir sin motivo no se puede", () => {
    const r = repartirPago({ ...base, correcciones: { "2026-09": { monto: 100, motivo: "ab" } } });
    expect(problemaDelPago(r, "total", 600)).toMatch(/por qué corregiste/);
  });
  it("lo corregido no puede pasar el total", () => {
    const r = repartirPago({ ...base, correcciones: { "2026-09": { monto: 900, motivo: "prueba" } } });
    expect(problemaDelPago(r, "total", 600)).toMatch(/suman más que el total/);
  });
  it("sin total no se envía", () => {
    expect(problemaDelPago(repartirPago({ ...base, total: 0 }), "total", 0)).toMatch(/total que pagaste/);
  });
  it("lo normal pasa", () => {
    expect(problemaDelPago(repartirPago(base), "total", 600)).toBeNull();
  });
});

describe("mesesParaLaBase", () => {
  it("manda cada mes por su día 1, y el motivo solo si se corrigió", () => {
    const r = mesesParaLaBase(repartirPago({ ...base, correcciones: { "2026-08": { monto: 180, motivo: " matrícula " } } }));
    expect(r[0]).toEqual({ mes: "2026-08-01", monto: 180, origen: "manual", motivo: "matrícula" });
    expect(r[1]).toEqual({ mes: "2026-09-01", monto: 105, origen: "calculado" });
  });
});
