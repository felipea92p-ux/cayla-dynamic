import { describe, it, expect } from "vitest";
import {
  nombreDelPeriodo,
  periodoAnterior,
  periodoQueContiene,
  rangoDelPeriodo,
} from "@cayla-dynamic/shared";

// Cada caso afirma lo que haría fn_cts_trunca (0278) con esa fecha de cese:
//   >= 01/11 → periodo nov–abr, ventana cts_may del año SIGUIENTE
//   >= 01/05 → periodo may–oct, ventana cts_nov del mismo año
//   si no    → periodo nov(año-1)–abr, ventana cts_may del mismo año
const cts = (fecha: string) => {
  const p = periodoQueContiene("cts", fecha);
  return `${p.ventana} ${p.anio}`;
};

describe("CTS — el periodo que contiene la fecha, nombrado por el mes del depósito", () => {
  it("30/04 es el último día de nov–abr: cts_may del mismo año", () => {
    expect(cts("2026-04-30")).toBe("cts_may 2026");
  });
  it("01/05 ya es may–oct: cts_nov", () => {
    expect(cts("2026-05-01")).toBe("cts_nov 2026");
  });
  it("el caso medido: un adelanto del 20/06 es cts_nov, no cts_may", () => {
    expect(cts("2026-06-20")).toBe("cts_nov 2026");
  });
  it("31/10 es el último día de may–oct", () => {
    expect(cts("2026-10-31")).toBe("cts_nov 2026");
  });
  it("01/11 empieza el periodo que se deposita en mayo del año siguiente", () => {
    expect(cts("2026-11-01")).toBe("cts_may 2027");
  });
  it("diciembre también es el mayo siguiente, no el noviembre del mismo año", () => {
    expect(cts("2026-12-15")).toBe("cts_may 2027");
    expect(cts("2026-12-31")).toBe("cts_may 2027");
  });
  it("y el 1 de enero sigue en esa misma ventana", () => {
    expect(cts("2027-01-01")).toBe("cts_may 2027");
  });
  it("trae las fechas del periodo y del depósito", () => {
    expect(periodoQueContiene("cts", "2026-12-10")).toEqual({
      beneficio: "cts", ventana: "cts_may", anio: 2027,
      desde: "2026-11-01", hasta: "2027-04-30", pagoLegal: "2027-05-15",
    });
  });
});

describe("gratificación — no cambia: ene–jun y jul–dic del mismo año", () => {
  it("30/06 es grati_s1 y 01/07 es grati_s2", () => {
    expect(periodoQueContiene("gratificacion", "2026-06-30")).toMatchObject({ ventana: "grati_s1", anio: 2026 });
    expect(periodoQueContiene("gratificacion", "2026-07-01")).toMatchObject({ ventana: "grati_s2", anio: 2026 });
  });
  it("diciembre es grati_s2 del mismo año", () => {
    expect(periodoQueContiene("gratificacion", "2026-12-31")).toMatchObject({ ventana: "grati_s2", anio: 2026, pagoLegal: "2026-12-15" });
  });
});

describe("vacaciones — una sola ventana, con el año del pago", () => {
  it("no tiene semestre", () => {
    expect(periodoQueContiene("vacaciones", "2026-02-10")).toMatchObject({ ventana: "vacaciones", anio: 2026, desde: null });
  });
});

describe("periodo anterior — para lo que la fecha sola no resuelve", () => {
  it("una CTS pagada el 10/05 puede ser el depósito atrasado de nov–abr", () => {
    const actual = periodoQueContiene("cts", "2026-05-10");
    expect(actual).toMatchObject({ ventana: "cts_nov", anio: 2026 });
    expect(periodoAnterior(actual)).toMatchObject({ ventana: "cts_may", anio: 2026 });
  });
  it("el anterior a nov–abr es may–oct del año en que empieza", () => {
    expect(periodoAnterior(periodoQueContiene("cts", "2027-02-01"))).toMatchObject({ ventana: "cts_nov", anio: 2026 });
  });
  it("el anterior a ene–jun es jul–dic del año pasado", () => {
    expect(periodoAnterior(periodoQueContiene("gratificacion", "2027-01-05"))).toMatchObject({ ventana: "grati_s2", anio: 2026 });
  });
  it("vacaciones no tiene periodo anterior", () => {
    const v = periodoQueContiene("vacaciones", "2026-03-01");
    expect(periodoAnterior(v)).toBe(v);
  });
});

describe("cómo se le dice a una persona", () => {
  it("nombra el depósito y el rango", () => {
    expect(nombreDelPeriodo(periodoQueContiene("cts", "2026-06-20"))).toBe("CTS de noviembre 2026 (periodo may–oct 2026)");
    expect(nombreDelPeriodo(periodoQueContiene("cts", "2026-12-01"))).toBe("CTS de mayo 2027 (periodo nov 2026–abr 2027)");
    expect(rangoDelPeriodo(periodoQueContiene("gratificacion", "2026-03-01"))).toBe("ene–jun 2026");
  });
  it("una fecha inválida no se adivina", () => {
    expect(() => periodoQueContiene("cts", "")).toThrow();
  });
});
