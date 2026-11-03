// sugerencia-entrada.test.ts — lo que la propuesta lee y lo que publica
import { describe, expect, it } from "vitest";
import {
  diaDeLaSemana, diasDeAusencia, filasParaPublicar, promedioDeCompras, restriccionesDesdeDisponibilidad,
} from "../apps/web/lib/admin/sugerencia-entrada";
import type { Propuesta } from "../apps/web/lib/admin/sugerencia-turnos";

describe("promedioDeCompras — 4 semanas, día con día", () => {
  // Del lunes 2026-10-12 al domingo 2026-11-08: cuatro de cada día.
  const filas = [
    { fecha: "2026-10-12", hora: 11, compras: 4 },
    { fecha: "2026-10-19", hora: 11, compras: 8 },
    { fecha: "2026-11-02", hora: 11, compras: 4 }, // el lunes 26-oct no vendió nada a las 11
    { fecha: "2026-11-07", hora: 17, compras: 10 },
  ];
  const prom = promedioDeCompras(filas, "2026-10-12", "2026-11-08");
  it("divide por los cuatro lunes, aunque uno no haya vendido", () => {
    expect(prom(1, 11)).toBe(4);
  });
  it("un sábado con una sola venta en el rango pesa un cuarto", () => {
    expect(prom(6, 17)).toBe(2.5);
    expect(prom(0, 12)).toBe(0);
  });
  it("el domingo es 0, como fn_sede_ventana_semanal", () => {
    expect(diaDeLaSemana("2026-11-08")).toBe(0);
  });
});

describe("restriccionesDesdeDisponibilidad y ausencias", () => {
  it("horario fijo, no puedo todo el día y prefiero no de unas horas", () => {
    const r = restriccionesDesdeDisponibilidad([
      { persona_id: "a", fecha: "2026-11-09", desde: null, hasta: null, estado: "horario_fijo" },
      { persona_id: "a", fecha: "2026-11-10", desde: null, hasta: null, estado: "no_puede" },
      { persona_id: "a", fecha: "2026-11-11", desde: "16:00:00", hasta: "21:00:00", estado: "prefiere_no" },
    ]).get("a")!;
    expect([...r.fijos]).toEqual(["2026-11-09"]);
    expect(r.bloques["2026-11-10"]).toEqual([{ desde: 0, hasta: 1440, estado: "no_puede" }]);
    expect(r.bloques["2026-11-11"]).toEqual([{ desde: 960, hasta: 1260, estado: "prefiere_no" }]);
  });
  it("las ausencias anuladas no cuentan; las demás, solo dentro de la semana", () => {
    const m = diasDeAusencia([
      { persona_id: "a", fecha_inicio: "2026-11-05", fecha_fin: "2026-11-10", anulada: false },
      { persona_id: "b", fecha_inicio: "2026-11-09", fecha_fin: "2026-11-15", anulada: true },
    ], ["2026-11-09", "2026-11-10", "2026-11-11"]);
    expect([...(m.get("a") ?? [])]).toEqual(["2026-11-09", "2026-11-10"]);
    expect(m.has("b")).toBe(false);
  });
});

describe("filasParaPublicar", () => {
  const fechas = ["2026-11-09", "2026-11-10"];
  const propuesta = {
    turnos: {
      ana: { "2026-11-09": { entrada: 540, salida: 1050 }, "2026-11-10": null },
      lia: { "2026-11-09": { entrada: 720, salida: 1230 }, "2026-11-10": { entrada: 540, salida: 1050 } },
    },
    resumen: { ana: { horas: 7.5, dias: 1, objetivo: 7.5 }, lia: { horas: 15, dias: 2, objetivo: 15 } },
    cobertura: {}, avisos: [], costo: 0,
  } satisfies Propuesta;
  const actual = (p: string, f: string) => (p === "ana" && f === "2026-11-09" ? { entrada: 540, salida: 1050 } : f === "2026-11-10" && p === "lia" ? { entrada: 540, salida: 1050 } : null);
  it("solo manda los días que cambian", () => {
    const { filas } = filasParaPublicar({ propuesta, actual, fechas });
    expect(filas).toEqual([
      { persona_id: "lia", fecha: "2026-11-09", entrada: "12:00", salida: "20:30" },
    ]);
  });
  it("el turno propio de una líder va con la semana completa si suma su jornada", () => {
    const { filas, suyoFuera } = filasParaPublicar({ propuesta, actual, fechas, lider: { id: "lia", jornada: 15 } });
    expect(suyoFuera).toBeNull();
    expect(filas.filter((f) => f.persona_id === "lia").map((f) => f.fecha)).toEqual(fechas);
  });
  it("si no la suma, o no tiene jornada, lo suyo no va y se dice", () => {
    expect(filasParaPublicar({ propuesta, actual, fechas, lider: { id: "lia", jornada: 45 } }).suyoFuera).toMatch(/no suma tu jornada/);
    const sin = filasParaPublicar({ propuesta, actual, fechas, lider: { id: "lia", jornada: null } });
    expect(sin.suyoFuera).toMatch(/DO todavía no fija/);
    expect(sin.filas.some((f) => f.persona_id === "lia")).toBe(false);
  });
});
