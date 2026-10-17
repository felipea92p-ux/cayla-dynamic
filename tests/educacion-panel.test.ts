import { describe, it, expect } from "vitest";
import { haceCuanto, mesesQueCuenta, resumenDelPanel, ultimaAprobada } from "@/lib/admin/educacion-panel";
import type { CoberturaMes } from "@/lib/admin/educacion-meses";
import type { Entrega, Situacion } from "@/lib/admin/educacion-tipos";

const HOY = "2026-10-17";

function sit(over: Partial<Situacion> = {}): Situacion {
  return {
    familia_id: "f1", asignacion_id: "a1", persona_id: "p1", persona: "Diego Narro", sede: "OTRU", rango: "colibri",
    institucion: "Tecsup", beneficiario: "trabajador", beneficiario_nombre: null, monto: 90,
    vigente_desde: "2024-06-03", vigente_hasta: "2027-10-30", vigencia: "vigente", paga: true,
    frecuencia_pago: null, proxima_fecha_pago: null, dias_para_pago: null, pago_proximo: false,
    estado_constancia: "sin_calendario", fecha_pago_constancia: null, plazo: null, dias_para_plazo: null,
    entrega_id: null, entrega_estado: null, entrega_enviada_at: null, entrega_archivos: null,
    aprobadas: 1, aviso_fin_id: null, aviso_fin_motivo: null,
    ...over,
  };
}

function ent(over: Partial<Entrega> = {}): Entrega {
  return {
    id: "e1", asignacion_id: "a1", fecha_pago: "2024-06-01", tipo: "otro",
    proxima_fecha_pago: null, nota: null, estado: "aprobada", origen: "do",
    enviada_at: "2026-10-17T15:05:00Z", enviada_por: "Felipe", revisada_at: null, revisada_por: null,
    retirada_at: null, motivo_categoria: null, motivo_comentario: null, reemplaza_a: null, archivos: [],
    aprobada_at: null, aprobada_por: null, revertida_at: null, revertida_por: null,
    ...over,
  };
}

const cobertura = (entrega_id: string, mes: string): CoberturaMes => ({
  entrega_id, familia_id: "f1", mes, monto: 100, origen: "calculado", motivo: null,
});

describe("ultimaAprobada", () => {
  it("toma la de fecha de pago más reciente y deja pasar las que no están aprobadas", () => {
    const e = [
      ent({ id: "vieja", fecha_pago: "2026-07-30" }),
      ent({ id: "nueva", fecha_pago: "2026-09-30" }),
      ent({ id: "pendiente", fecha_pago: "2026-10-15", estado: "pendiente" }),
      ent({ id: "rechazada", fecha_pago: "2026-10-16", estado: "rechazada" }),
      ent({ id: "retirada", fecha_pago: "2026-10-17", estado: "retirada" }),
    ];
    expect(ultimaAprobada(e)?.id).toBe("nueva");
  });

  it("con el mismo día de pago gana el último envío, y al final el id: no depende del orden de la lista", () => {
    const a = ent({ id: "a", enviada_at: "2026-10-01T10:00:00Z" });
    const b = ent({ id: "b", enviada_at: "2026-10-02T10:00:00Z" });
    expect(ultimaAprobada([a, b])?.id).toBe("b");
    expect(ultimaAprobada([b, a])?.id).toBe("b");
    const c = ent({ id: "c" }), d = ent({ id: "d" });
    expect(ultimaAprobada([c, d])?.id).toBe(ultimaAprobada([d, c])?.id);
  });

  it("sin ninguna aprobada, null", () => {
    expect(ultimaAprobada([])).toBeNull();
    expect(ultimaAprobada([ent({ estado: "pendiente" })])).toBeNull();
  });
});

describe("mesesQueCuenta", () => {
  it("un pago normal cuenta para el mes de su fecha de pago", () => {
    expect(mesesQueCuenta(ent({ fecha_pago: "2024-06-01" }))).toBe("jun 2024");
  });

  it("un pago adelantado dice sus meses, con el año una sola vez si es el mismo", () => {
    const e = ent({ id: "adel", fecha_pago: "2026-07-28" });
    const filas = ["2026-08-01", "2026-09-01", "2026-10-01", "2026-11-01", "2026-12-01"].map((m) => cobertura("adel", m));
    expect(mesesQueCuenta(e, new Map([["adel", filas]]))).toBe("ago – dic 2026");
  });

  it("un pago adelantado que cruza de año dice los dos años", () => {
    const e = ent({ id: "adel", fecha_pago: "2026-11-28" });
    const filas = ["2026-12-01", "2027-01-01", "2027-02-01"].map((m) => cobertura("adel", m));
    expect(mesesQueCuenta(e, new Map([["adel", filas]]))).toBe("dic 2026 – feb 2027");
  });

  it("no depende del orden en que llegaron las filas de cobertura", () => {
    const e = ent({ id: "adel", fecha_pago: "2026-07-28" });
    const filas = ["2026-10-01", "2026-08-01", "2026-09-01"].map((m) => cobertura("adel", m));
    expect(mesesQueCuenta(e, new Map([["adel", filas]]))).toBe("ago – oct 2026");
  });
});

describe("haceCuanto", () => {
  it("dice el mes en palabras", () => {
    expect(haceCuanto("2026-10", HOY)).toBe("este mes");
    expect(haceCuanto("2026-09", HOY)).toBe("el mes pasado");
    expect(haceCuanto("2024-06", HOY)).toBe("hace 28 meses");
    expect(haceCuanto("2026-12", HOY)).toBe("de un mes que todavía no llega");
  });
});

describe("resumenDelPanel", () => {
  it("el caso que lo originó: constancia aprobada de junio de 2024, sin calendario, hoy octubre de 2026", () => {
    const r = resumenDelPanel(sit(), [ent()], HOY);
    expect(r.frase).toContain("No se sabe cuándo toca su próximo pago");
    expect(r.frase).toContain("cierra la asignación");
    expect(r.ultima).toBe("Última constancia aprobada: pago del 01/06/2024, cuenta para jun 2024 (hace 28 meses).");
    expect(r.ojo).toContain("jun 2024");
    expect(r.ojo).toContain("«Aprobadas del ciclo»");
  });

  it("una constancia reciente no levanta el «ojo»", () => {
    const r = resumenDelPanel(sit({ estado_constancia: "al_dia", frecuencia_pago: "mensual", proxima_fecha_pago: "2026-10-30" }),
      [ent({ fecha_pago: "2026-09-30" })], HOY);
    expect(r.frase).toBe("Está al día. Su próximo pago es el 30/10/2026.");
    expect(r.ultima).toContain("el mes pasado");
    expect(r.ojo).toBeNull();
  });

  it("un pago adelantado se mide por su ÚLTIMO mes cubierto, no por el día en que se pagó", () => {
    const e = ent({ id: "adel", fecha_pago: "2026-03-28" });
    const filas = ["2026-04-01", "2026-05-01", "2026-06-01", "2026-07-01", "2026-08-01", "2026-09-01", "2026-10-01"].map((m) => cobertura("adel", m));
    const r = resumenDelPanel(sit({ estado_constancia: "al_dia" }), [e], HOY, new Map([["adel", filas]]));
    expect(r.ultima).toContain("abr – oct 2026");
    expect(r.ultima).toContain("este mes");
    expect(r.ojo).toBeNull();
  });

  it("si el estudio ya terminó no se señala nada: no hay cuadrícula de ahora que mirar", () => {
    const r = resumenDelPanel(sit({ vigencia: "terminada" }), [ent()], HOY);
    expect(r.ojo).toBeNull();
  });

  it("mientras llegan las constancias, solo la frase del estado", () => {
    const r = resumenDelPanel(sit(), null, HOY);
    expect(r.frase).toContain("No se sabe cuándo");
    expect(r.ultima).toBeNull();
    expect(r.ojo).toBeNull();
  });

  it("sin ninguna aprobada lo dice", () => {
    const r = resumenDelPanel(sit({ aprobadas: 0 }), [ent({ estado: "pendiente" })], HOY);
    expect(r.ultima).toBe("Todavía no tiene ninguna constancia aprobada.");
    expect(r.ojo).toBeNull();
  });

  it("los estados que piden algo repiten lo que dijo la base: de qué pago y hasta cuándo", () => {
    for (const estado of ["por_vencer", "vencida", "falta_enviar"] as const) {
      const r = resumenDelPanel(sit({ estado_constancia: estado, fecha_pago_constancia: "2026-10-30", plazo: "2026-11-05" }), [], HOY);
      expect(r.frase).toBe("Falta la constancia del pago del 30/10/2026, plazo 05/11/2026.");
    }
  });

  it("pendiente y rechazada mandan a la revisión y a esperar, sin inventar plazos", () => {
    expect(resumenDelPanel(sit({ estado_constancia: "pendiente_revision" }), [], HOY).frase).toContain("más abajo puedes aprobarla o rechazarla");
    expect(resumenDelPanel(sit({ estado_constancia: "rechazada" }), [], HOY).frase).toContain("se espera que la integrante envíe la corregida");
  });
});
