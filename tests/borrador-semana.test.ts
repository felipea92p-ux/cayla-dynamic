// borrador-semana.test.ts — el borrador de la semana (0592): comparar y «cumple»
import { describe, expect, it } from "vitest";
import {
  comoPropuesta, compararSemanas, cumpleJornada, filasParaGuardar, horasNetas, semanaDesdeBorrador, textoCumple,
} from "../apps/web/lib/admin/borrador-semana";
import { filasParaPublicar } from "../apps/web/lib/admin/sugerencia-entrada";
import type { Turno } from "../apps/web/lib/admin/sugerencia-turnos";

const h = (x: number) => x * 60;
const T = (a: number, b: number): Turno => ({ entrada: h(a), salida: h(b) });
const FECHAS = ["2026-11-09", "2026-11-10", "2026-11-11", "2026-11-12", "2026-11-13", "2026-11-14", "2026-11-15"];
// Ana trabaja de lunes a sábado de 9 a 17:30 (7,5 h netas con 1 h de refrigerio) y descansa el domingo: 45 h.
const actualAna = (_: string, f: string): Turno | null => (f === "2026-11-15" ? null : T(9, 17.5));

describe("semanaDesdeBorrador — de la base a la grilla", () => {
  it("lee entrada y salida con segundos, y el descanso como null", () => {
    const s = semanaDesdeBorrador([
      { persona_id: "ana", fecha: "2026-11-09", entrada: "10:00:00", salida: "18:30:00" },
      { persona_id: "ana", fecha: "2026-11-10", entrada: null, salida: null },
    ], FECHAS, actualAna);
    expect(s.ana["2026-11-09"]).toEqual(T(10, 18.5));
    expect(s.ana["2026-11-10"]).toBeNull();
  });
  it("un día que el borrador no trae NO es descanso: queda lo que tiene hoy", () => {
    const s = semanaDesdeBorrador([{ persona_id: "ana", fecha: "2026-11-09", entrada: "10:00", salida: "18:30" }], FECHAS, actualAna);
    expect(s.ana["2026-11-11"]).toEqual(T(9, 17.5));
    expect(s.ana["2026-11-15"]).toBeNull();
    // Y por eso, al publicar, solo cambia el lunes.
    const { filas } = filasParaPublicar({ propuesta: comoPropuesta(s, FECHAS, () => 60), actual: actualAna, fechas: FECHAS });
    expect(filas).toEqual([{ persona_id: "ana", fecha: "2026-11-09", entrada: "10:00", salida: "18:30" }]);
  });
  it("ida y vuelta: lo que se guarda vuelve igual", () => {
    const s = semanaDesdeBorrador([{ persona_id: "ana", fecha: "2026-11-09", entrada: "10:00", salida: "18:30" }], FECHAS, actualAna);
    const filas = filasParaGuardar(s, FECHAS);
    expect(filas).toHaveLength(7);
    expect(semanaDesdeBorrador(filas, FECHAS, () => null)).toEqual(s);
  });
});

describe("cumpleJornada — contra la jornada que fija DO", () => {
  it("45 h de 45: cumple; con 15 minutos de margen", () => {
    expect(cumpleJornada(45, 45).estado).toBe("cumple");
    expect(cumpleJornada(44.75, 45).estado).toBe("cumple");
    expect(cumpleJornada(44.5, 45)).toMatchObject({ estado: "faltan", diferencia: -0.5 });
    expect(cumpleJornada(46, 45)).toMatchObject({ estado: "sobra", diferencia: 1 });
  });
  it("quien tiene 30 h se mide contra 30, no contra 45", () => {
    expect(cumpleJornada(30, 30).estado).toBe("cumple");
    expect(textoCumple(cumpleJornada(27, 30))).toBe("faltan 3 h de 30");
  });
  it("pasar de 48 h y un día de menos de 4 h se avisan aparte", () => {
    const c = cumpleJornada(49, 45, [{ fecha: "2026-11-09", horas: 3.5 }, { fecha: "2026-11-10", horas: 8 }]);
    expect(c.pasa48).toBe(true);
    expect(c.diasCortos).toEqual(["2026-11-09"]);
    expect(cumpleJornada(48, 45).pasa48).toBe(false);
  });
  it("sin jornada fijada no dice que falta ni que sobra", () => {
    expect(textoCumple(cumpleJornada(40, null))).toBe("40 h · sin jornada fijada");
  });
  it("en palabras", () => {
    expect(textoCumple(cumpleJornada(45, 45))).toBe("cumple 45 h");
    expect(textoCumple(cumpleJornada(47.5, 45))).toBe("se pasa 2,5 h de 45");
  });
});

describe("compararSemanas — lo que hay contra lo que se propone", () => {
  it("horas, días y qué días cambian, con el refrigerio descontado", () => {
    const despues = {
      ana: Object.fromEntries(FECHAS.map((f) => [f, f === "2026-11-09" ? null : f === "2026-11-15" ? T(10, 18.5) : T(9, 17.5)])),
    };
    const [ana] = compararSemanas({ fechas: FECHAS, antes: actualAna, despues, refrigerioMin: () => 60, jornada: () => 45 });
    expect(ana.antes).toEqual({ horas: 45, dias: 6 });
    expect(ana.despues).toEqual({ horas: 45, dias: 6 });
    expect(ana.cambian).toEqual(["2026-11-09", "2026-11-15"]);
    expect(ana.cumple.estado).toBe("cumple");
  });
  it("horasNetas nunca resta de más", () => {
    expect(horasNetas({ a: T(9, 9.5) }, ["a"], 60).total).toBe(0);
  });
});
