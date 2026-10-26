// ============================================================================
// periodo-de-prueba.test.ts — el periodo de prueba como condición del contrato
// ============================================================================
// Dos cosas se vigilan, y las dos cuestan plata si salen torcidas:
//   1. El fin de la prueba. Tiene que ser EL MISMO día que imprime el contrato
//      (cláusula TERCERA, `finDelPeriodoDePrueba`): dos fechas para lo mismo
//      es peor que una discutible.
//   2. Quién cuenta como «recién ingresado» para el aviso de feriado (Felipe,
//      2026-10-26: días CALENDARIO desde el ingreso, menos de 15).
// Los casos de calendario se escribieron a mano, desde el Código Civil art. 183,
// antes de correr nada.
// ============================================================================
import { describe, it, expect } from "vitest";
import {
  diasEntreFechas, esIngresoReciente, finDelPeriodoDePruebaDe, MESES_PRUEBA_LEY, periodoDePrueba, sumarDiasFecha, sumarMesesFecha,
  textoPeriodoDePrueba,
} from "@cayla-dynamic/shared";

describe("aritmética de fechas", () => {
  it("suma días cruzando mes y año", () => {
    expect(sumarDiasFecha("2026-10-26", 6)).toBe("2026-11-01");
    expect(sumarDiasFecha("2026-12-31", 1)).toBe("2027-01-01");
    expect(sumarDiasFecha("2027-01-01", -1)).toBe("2026-12-31");
  });
  it("suma meses: cae en el mismo día del mes final", () => {
    expect(sumarMesesFecha("2026-10-19", 3)).toBe("2027-01-19");
  });
  it("si el mes final no tiene ese día, cae en el último (art. 183 CC)", () => {
    expect(sumarMesesFecha("2026-11-30", 3)).toBe("2027-02-28");
    expect(sumarMesesFecha("2027-11-30", 3)).toBe("2028-02-29"); // 2028 es bisiesto
    expect(sumarMesesFecha("2026-01-31", 1)).toBe("2026-02-28");
  });
  it("rechaza una fecha que no existe en vez de corregirla en silencio", () => {
    expect(sumarDiasFecha("2026-02-30", 1)).toBeNull();
    expect(sumarMesesFecha("2026-13-01", 1)).toBeNull();
    expect(sumarMesesFecha("basura", 1)).toBeNull();
    expect(diasEntreFechas("2026-02-30", "2026-03-01")).toBeNull();
  });
  it("cuenta días entre fechas", () => {
    expect(diasEntreFechas("2026-10-26", "2026-11-01")).toBe(6);
    expect(diasEntreFechas("2026-11-01", "2026-10-26")).toBe(-6);
    expect(diasEntreFechas("2026-10-26", "2026-10-26")).toBe(0);
  });
});

describe("el periodo de prueba", () => {
  it("son tres meses por ley", () => {
    expect(MESES_PRUEBA_LEY).toBe(3);
  });
  it("termina el mismo día del mes final, como imprime el contrato", () => {
    expect(periodoDePrueba("2026-10-19", "2026-10-26")?.fin).toBe("2027-01-19");
    expect(finDelPeriodoDePruebaDe("2026-01-15")).toBe("2026-04-15");
    expect(finDelPeriodoDePruebaDe("2026-08-01")).toBe("2026-11-01");
  });
  it("con un mes final corto, cae en el último día del mes", () => {
    expect(periodoDePrueba("2026-11-30", "2026-12-01")?.fin).toBe("2027-02-28");
    expect(finDelPeriodoDePruebaDe("2026-08-31")).toBe("2026-11-30");
  });
  it("está en curso hasta el día de su fin, inclusive", () => {
    expect(periodoDePrueba("2026-10-19", "2027-01-19")).toMatchObject({ enCurso: true, diasRestantes: 0 });
    expect(periodoDePrueba("2026-10-19", "2027-01-20")).toMatchObject({ enCurso: false, diasRestantes: -1 });
  });
  it("dice cuántos días faltan", () => {
    expect(periodoDePrueba("2026-10-19", "2026-10-26")?.diasRestantes).toBe(85);
  });
  it("una fecha que no existe no tiene fin", () => {
    expect(finDelPeriodoDePruebaDe("2026-02-30")).toBeNull();
  });
  it("sin ingreso legible no inventa una prueba", () => {
    expect(periodoDePrueba(null, "2026-10-26")).toBeNull();
    expect(periodoDePrueba(undefined, "2026-10-26")).toBeNull();
    expect(periodoDePrueba("", "2026-10-26")).toBeNull();
    expect(periodoDePrueba("2026-02-30", "2026-10-26")).toBeNull();
    expect(periodoDePrueba("2026-10-19", "no-es-fecha")).toBeNull();
  });
  it("el texto sale como dd/mm/aaaa, o vacío", () => {
    expect(textoPeriodoDePrueba(periodoDePrueba("2026-10-19", "2026-10-26"))).toBe("19/01/2027");
    expect(textoPeriodoDePrueba(null)).toBe("");
  });
});

describe("recién ingresado, para el aviso de feriado", () => {
  // El caso de Felipe: ingresa el lunes 26/10 y el domingo 1/11 es feriado (Todos los Santos).
  it("el domingo 1/11 de quien ingresó el 26/10 lleva 6 días: avisa", () => {
    expect(esIngresoReciente("2026-10-26", "2026-11-01", 15)).toBe(true);
  });
  it("el día del ingreso cuenta 0 y el día 14 todavía avisa; el 15 ya no", () => {
    expect(esIngresoReciente("2026-10-26", "2026-10-26", 15)).toBe(true);
    expect(esIngresoReciente("2026-10-26", "2026-11-09", 15)).toBe(true); // 14 días
    expect(esIngresoReciente("2026-10-26", "2026-11-10", 15)).toBe(false); // 15 días
  });
  it("antes del ingreso no avisa: todavía no trabaja", () => {
    expect(esIngresoReciente("2026-10-26", "2026-10-25", 15)).toBe(false);
  });
  it("respeta el umbral que le pasen", () => {
    expect(esIngresoReciente("2026-10-26", "2026-11-05", 7)).toBe(false);
    expect(esIngresoReciente("2026-10-26", "2026-11-05", 30)).toBe(true);
  });
  it("sin ingreso no avisa (un aviso blando que no sale no cuesta nada)", () => {
    expect(esIngresoReciente(null, "2026-11-01")).toBe(false);
    expect(esIngresoReciente("", "2026-11-01")).toBe(false);
    expect(esIngresoReciente("2026-02-30", "2026-11-01")).toBe(false);
  });
  it("el umbral por defecto es 15", () => {
    expect(esIngresoReciente("2026-10-26", "2026-11-09")).toBe(true);
    expect(esIngresoReciente("2026-10-26", "2026-11-10")).toBe(false);
  });
});
