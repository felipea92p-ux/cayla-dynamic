import { describe, it, expect } from "vitest";
import { decirHecho, fechasLegibles, rangoDeMeses, type HechoEducacion } from "@/lib/educacion-historial";

function h(over: Partial<HechoEducacion>): HechoEducacion {
  return {
    ocurrio_at: "2026-10-17T15:00:00Z", persona_id: "p1", persona: "Ana Rojas", sede: "TRU",
    fuente: "auditoria", campo: null, valor_anterior: null, valor_nuevo: null, motivo: null, quien: "Jorge Díaz",
    entrega_id: null, cubre_desde: null, cubre_hasta: null, ...over,
  };
}

describe("decirHecho · constancias", () => {
  it("un envío normal, para DO y para ella", () => {
    const x = h({ fuente: "envio", campo: "colaboradora", entrega_id: "e1" });
    expect(decirHecho(x, "do").titulo).toBe("Envió su constancia");
    expect(decirHecho(x, "ella").titulo).toBe("Enviaste tu constancia");
  });
  it("un pago adelantado dice los meses que cubre", () => {
    const x = h({ fuente: "envio", campo: "colaboradora", cubre_desde: "2026-08-01", cubre_hasta: "2026-12-01" });
    expect(decirHecho(x, "do")).toMatchObject({ titulo: "Envió un pago adelantado", detalle: "Cubre agosto a diciembre 2026. Espera revisión." });
  });
  it("si cruza el año, dice los dos", () => {
    expect(rangoDeMeses("2026-11-01", "2027-02-01")).toBe("noviembre 2026 a febrero 2027");
  });
  it("aprobada, rechazada con su motivo, y revertida", () => {
    expect(decirHecho(h({ campo: "educacion_entrega", valor_anterior: "pendiente", valor_nuevo: "aprobada" }), "do"))
      .toMatchObject({ tipo: "aprobada", titulo: "Constancia aprobada" });
    expect(decirHecho(h({ campo: "educacion_entrega", valor_anterior: "pendiente", valor_nuevo: "rechazada · ilegible", motivo: "No se ve el monto" }), "ella"))
      .toMatchObject({ tipo: "rechazada", titulo: "Tu constancia se rechazó", detalle: "«No se lee»: No se ve el monto" });
    expect(decirHecho(h({ campo: "educacion_entrega", valor_anterior: "aprobada", valor_nuevo: "rechazada · otro", motivo: "Aprobación revertida: Era de otro mes" }), "do"))
      .toMatchObject({ tipo: "revertida", titulo: "Aprobación revertida", detalle: "«Otro motivo»: Era de otro mes" });
  });
  it("retirar no es rechazar", () => {
    expect(decirHecho(h({ fuente: "retiro" }), "ella")).toMatchObject({ tipo: "retiro", titulo: "Retiraste tu constancia" });
  });
});

describe("decirHecho · el apoyo", () => {
  it("un alta muestra las fechas legibles", () => {
    expect(decirHecho(h({ campo: "educacion_alta", valor_nuevo: "UPN · S/90.00 · 2026-07-01 a 2027-03-31" }), "do").detalle)
      .toBe("UPN · S/90.00 · 01/07/2026 a 31/03/2027");
  });
  it("el motivo interno de DO no se le muestra a ella", () => {
    const x = h({ campo: "educacion_cierre", valor_nuevo: "2026-12-31", motivo: "Dejó de estudiar" });
    expect(decirHecho(x, "do").detalle).toContain("Dejó de estudiar");
    expect(decirHecho(x, "ella").detalle).not.toContain("Dejó de estudiar");
  });
  it("un campo que no se conoce se dice igual, con su valor: no se esconde", () => {
    expect(decirHecho(h({ campo: "educacion_algo_nuevo", valor_nuevo: "x" }), "do")).toMatchObject({ titulo: "Cambio en Educación", detalle: "x" });
  });
});

describe("fechasLegibles", () => {
  it("deja el texto y cambia solo las fechas", () => {
    expect(fechasLegibles("cerradas al 2026-10-31")).toBe("cerradas al 31/10/2026");
    expect(fechasLegibles(null)).toBeNull();
  });
});
