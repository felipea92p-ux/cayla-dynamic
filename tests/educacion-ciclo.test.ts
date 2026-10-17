import { describe, it, expect } from "vitest";
import { CICLOS_A_OFRECER, cicloInicial, etiquetaCiclo, rechazoIncompleto, type PeriodoCiclo } from "@/lib/admin/educacion-ciclo";

const p = (id: string, ini: string, fin: string, estado = "abierto"): PeriodoCiclo => ({ id, fecha_ini: ini, fecha_fin: fin, estado });

// Los periodos de planilla van del 29 al 28 —no son meses calendario—.
const SEP = p("sep", "2026-08-29", "2026-09-28", "pagado");
const OCT = p("oct", "2026-09-29", "2026-10-28");
const NOV = p("nov", "2026-10-29", "2026-11-28");

describe("cicloInicial", () => {
  it("abre en el periodo que contiene hoy", () => {
    expect(cicloInicial([NOV, OCT, SEP], "2026-10-17")).toBe("oct");
  });
  it("el día 29 ya es el periodo siguiente, no el mes anterior", () => {
    expect(cicloInicial([NOV, OCT, SEP], "2026-10-29")).toBe("nov");
    expect(cicloInicial([NOV, OCT, SEP], "2026-10-28")).toBe("oct");
  });
  it("si hoy cae en un hueco, abre en el más reciente que ya empezó", () => {
    expect(cicloInicial([OCT, SEP], "2026-11-03")).toBe("oct");
  });
  it("si todavía no empezó ninguno, abre en el primero de la lista", () => {
    expect(cicloInicial([NOV, OCT], "2026-08-01")).toBe("nov");
  });
  it("sin periodos no hay ciclo", () => {
    expect(cicloInicial([], "2026-10-17")).toBeNull();
  });
});

describe("etiquetaCiclo", () => {
  it("dice las dos fechas y si ya se pagó", () => {
    expect(etiquetaCiclo(SEP)).toBe("29/08/2026 → 28/09/2026 · pagado");
    expect(etiquetaCiclo(OCT)).toBe("29/09/2026 → 28/10/2026 · abierto");
  });
});

describe("rechazoIncompleto", () => {
  it("pide el motivo primero", () => {
    expect(rechazoIncompleto("", "No se lee bien")).toBe("Elige el motivo del rechazo.");
  });
  it("el texto pide al menos 3 letras, también con «Otro»", () => {
    expect(rechazoIncompleto("otro", "ab")).toMatch(/qué tiene que corregir/);
    expect(rechazoIncompleto("ilegible", "   ")).toMatch(/qué tiene que corregir/);
    expect(rechazoIncompleto("otro", "abc")).toBeNull();
  });
  it("no tiene máximo", () => {
    expect(rechazoIncompleto("otro", "x".repeat(5000))).toBeNull();
  });
});

describe("CICLOS_A_OFRECER", () => {
  it("alcanza para un año de planilla", () => {
    expect(CICLOS_A_OFRECER).toBeGreaterThanOrEqual(12);
  });
});
