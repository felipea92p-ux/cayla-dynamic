import { describe, expect, it } from "vitest";
import { bandaDe, racimoDeVencimientos } from "../apps/web/lib/admin/contratos-bandas";

describe("bandaDe", () => {
  it("el art. 77 y el vencido son «ya pasó el plazo»", () => {
    expect(bandaDe({ estado: "desnaturalizado", fecha_fin_contrato: "2026-10-01" })).toBe("paso");
    expect(bandaDe({ estado: "vencido", fecha_fin_contrato: "2026-10-01" })).toBe("paso");
  });
  it("por vencer es «pronto»", () => expect(bandaDe({ estado: "por_vencer", fecha_fin_contrato: "2026-12-01" })).toBe("pronto"));
  it("sin firmar y falta la copia son «firma»", () => {
    expect(bandaDe({ estado: "sin_firmar", fecha_fin_contrato: null })).toBe("firma");
    expect(bandaDe({ estado: "tramite_pendiente", fecha_fin_contrato: null })).toBe("firma");
  });
  it("sin contrato y SIN fecha de fin pide atención; con fecha («en papel») es historia", () => {
    expect(bandaDe({ estado: "sin_contrato", fecha_fin_contrato: null })).toBe("sin_contrato");
    expect(bandaDe({ estado: "sin_contrato", fecha_fin_contrato: "2026-12-31" })).toBe("al_dia");
  });
  it("ok, sin vencimiento y un estado que no conoce caen en «al día»: lo seguro es no gritar", () => {
    expect(bandaDe({ estado: "ok", fecha_fin_contrato: "2027-06-30" })).toBe("al_dia");
    expect(bandaDe({ estado: "sin_vencimiento", fecha_fin_contrato: null })).toBe("al_dia");
    expect(bandaDe({ estado: "algo_nuevo", fecha_fin_contrato: null })).toBe("al_dia");
  });
});

describe("racimoDeVencimientos", () => {
  it("avisa cuando 3 o más vencen el mismo día", () => {
    expect(racimoDeVencimientos(["2026-12-31", "2026-12-31", "2026-12-31", "2026-11-20", null])).toEqual({ fecha: "2026-12-31", cuantos: 3 });
  });
  it("dos el mismo día no es un racimo", () => {
    expect(racimoDeVencimientos(["2026-12-31", "2026-12-31", "2026-11-20"])).toBeNull();
  });
  it("sin fechas, nada", () => expect(racimoDeVencimientos([null, null])).toBeNull());
});
