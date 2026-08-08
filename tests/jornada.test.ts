// ============================================================================
// jornada.test.ts — Los dos topes no pueden confundirse
// ============================================================================
// CAYLA pacta jornada ordinaria de 48 h (el máximo del art. 25 de la
// Constitución) y programa un horario de 45 h. La diferencia parece cosmética y
// no lo es: el sobretiempo se mide contra la jornada ORDINARIA, no contra el
// horario (D.S. 007-2002-TR art. 9).
//
// Si alguien iguala las dos constantes —por "simplificar", o por creer que la
// jornada de CAYLA son 45 h— las horas 46 a 48 se convierten en sobretiempo con
// recargo del 25 % / 35 %. Al 2026-08-07 hay tres personas trabajando en ese
// rango, así que el cambio no sería teórico: crearía un pasivo el mismo día.
//
// Estas pruebas están para que ese cambio no pase inadvertido.
// ============================================================================
import { describe, it, expect } from "vitest";
import {
  MAXIMO_LEGAL_SEMANAL,
  HORARIO_PROGRAMADO_SEMANAL,
  RECARGO_SOBRETIEMPO,
  excesoSobreJornada,
  MAXIMO_DIAS_SIN_DESCANSO,
  diasSeguidosTrabajados,
} from "@cayla-dynamic/shared";

describe("los topes de jornada", () => {
  it("el máximo legal es 48 h: es el techo del art. 25 de la Constitución", () => {
    expect(MAXIMO_LEGAL_SEMANAL).toBe(48);
  });

  it("el horario programado es 45 h y va POR DEBAJO del máximo legal", () => {
    expect(HORARIO_PROGRAMADO_SEMANAL).toBe(45);
    expect(HORARIO_PROGRAMADO_SEMANAL).toBeLessThan(MAXIMO_LEGAL_SEMANAL);
  });

  it("las dos cifras son distintas — igualarlas convierte las horas 46 a 48 en sobretiempo", () => {
    expect(HORARIO_PROGRAMADO_SEMANAL).not.toBe(MAXIMO_LEGAL_SEMANAL);
  });

  it("el recargo es 25 % las dos primeras horas y 35 % las siguientes", () => {
    expect(RECARGO_SOBRETIEMPO.horasPrimerTramo).toBe(2);
    expect(RECARGO_SOBRETIEMPO.primerTramo).toBe(0.25);
    expect(RECARGO_SOBRETIEMPO.tramoSiguiente).toBe(0.35);
  });
});

describe("excesoSobreJornada", () => {
  it("no hay exceso cuando se trabaja el horario programado", () => {
    expect(excesoSobreJornada(45)).toBe(0);
  });

  it("no hay exceso justo en el máximo legal", () => {
    expect(excesoSobreJornada(48)).toBe(0);
  });

  it("el exceso se mide desde 48, no desde 45", () => {
    // 47 h está por encima del horario programado pero dentro de la jornada
    // ordinaria pactada: no es sobretiempo.
    expect(excesoSobreJornada(47)).toBe(0);
    expect(excesoSobreJornada(49.3)).toBeCloseTo(1.3, 5);
  });

  it("nunca devuelve un negativo, aunque se trabaje poco", () => {
    expect(excesoSobreJornada(0)).toBe(0);
    expect(excesoSobreJornada(12.5)).toBe(0);
  });
});

describe("diasSeguidosTrabajados", () => {
  it("cuenta los días seguidos hacia atrás", () => {
    const f = ["2026-08-03", "2026-08-04", "2026-08-05", "2026-08-06"];
    expect(diasSeguidosTrabajados(f, "2026-08-06")).toBe(4);
  });

  it("un descanso corta la racha: solo cuenta lo posterior", () => {
    // Descansó el 5. Los días previos no suman.
    const f = ["2026-08-01", "2026-08-02", "2026-08-03", "2026-08-04", "2026-08-06", "2026-08-07"];
    expect(diasSeguidosTrabajados(f, "2026-08-07")).toBe(2);
  });

  it("devuelve 0 si ese día no trabajó", () => {
    expect(diasSeguidosTrabajados(["2026-08-03", "2026-08-04"], "2026-08-05")).toBe(0);
  });

  it("el caso que motivó todo: doce días seguidos con descanso rotativo mal puesto", () => {
    // Descansó el lunes 3 y el domingo 16. Cada semana calendario cuadra, pero
    // del martes 4 al sábado 15 no descansó ni un día.
    const f: string[] = [];
    for (let d = 4; d <= 15; d++) f.push(`2026-08-${String(d).padStart(2, "0")}`);
    expect(diasSeguidosTrabajados(f, "2026-08-15")).toBe(12);
    expect(diasSeguidosTrabajados(f, "2026-08-15")).toBeGreaterThan(MAXIMO_DIAS_SIN_DESCANSO);
  });

  it("cruza el fin de mes sin romperse", () => {
    const f = ["2026-07-29", "2026-07-30", "2026-07-31", "2026-08-01", "2026-08-02"];
    expect(diasSeguidosTrabajados(f, "2026-08-02")).toBe(5);
  });

  it("seis días seguidos todavía está dentro; el séptimo ya no", () => {
    const seis = ["2026-08-03","2026-08-04","2026-08-05","2026-08-06","2026-08-07","2026-08-08"];
    expect(diasSeguidosTrabajados(seis, "2026-08-08")).toBe(MAXIMO_DIAS_SIN_DESCANSO);
    expect(diasSeguidosTrabajados([...seis, "2026-08-09"], "2026-08-09"))
      .toBeGreaterThan(MAXIMO_DIAS_SIN_DESCANSO);
  });
});
