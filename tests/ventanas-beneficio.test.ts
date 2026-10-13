import { describe, it, expect } from "vitest";
import {
  nombreDelPeriodo,
  periodoAnterior,
  periodoQueContiene,
  periodosHasta,
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

describe("modalidad formativa (0467) — hitos del convenio, no semestres calendario", () => {
  it("cada concepto va a su propia ventana, con el año del pago", () => {
    expect(periodoQueContiene("subvencion_semestral", "2026-06-20")).toEqual({
      beneficio: "subvencion_semestral", ventana: "subvencion_semestral", anio: 2026,
      desde: null, hasta: null, pagoLegal: null,
    });
    expect(periodoQueContiene("descanso_practicante", "2027-01-05")).toMatchObject({
      ventana: "descanso_practicante", anio: 2027,
    });
  });
  it("no tienen periodo anterior: su hito depende del convenio de cada persona", () => {
    const p = periodoQueContiene("subvencion_semestral", "2026-06-20");
    expect(periodoAnterior(p)).toBe(p);
  });
  it("se nombran por lo que son, no como una ventana de planilla", () => {
    expect(nombreDelPeriodo(periodoQueContiene("subvencion_semestral", "2026-06-20"))).toBe("media subvención (2026)");
    expect(nombreDelPeriodo(periodoQueContiene("descanso_practicante", "2026-06-20"))).toBe("descanso de 15 días (2026)");
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

describe("periodosHasta — el depósito atrasado no se queda fuera del formulario", () => {
  const ventanas = (iso: string, n = 3) =>
    periodosHasta(periodoQueContiene("cts", iso), n).map((x) => `${x.ventana} ${x.anio}`);

  it("hasta el 31/10 la CTS de mayo está a un periodo de distancia", () => {
    expect(ventanas("2026-10-10")).toEqual(["cts_nov 2026", "cts_may 2026", "cts_nov 2025"]);
  });
  // El caso que motivó esto: el 15/11 el periodo actual ya es nov–abr, y la CTS
  // de mayo 2026 que no se depositó quedaría a DOS periodos. Con solo actual y
  // anterior, el formulario ya no la ofrecía y la ventana no se podía regularizar.
  it("el 15/11 la CTS de mayo 2026 sigue a la mano, a dos periodos", () => {
    expect(ventanas("2026-11-15")).toEqual(["cts_may 2027", "cts_nov 2026", "cts_may 2026"]);
  });
  it("la gratificación alterna julio y diciembre hacia atrás", () => {
    expect(
      periodosHasta(periodoQueContiene("gratificacion", "2026-12-20"), 3).map((x) => `${x.ventana} ${x.anio}`),
    ).toEqual(["grati_s2 2026", "grati_s1 2026", "grati_s2 2025"]);
  });
  it("el primero es siempre el que contiene la fecha", () => {
    expect(periodosHasta(periodoQueContiene("cts", "2026-06-20"), 1)).toEqual([periodoQueContiene("cts", "2026-06-20")]);
  });
  it("vacaciones y modalidad formativa no tienen hacia atrás: devuelven solo el suyo", () => {
    const vac = periodoQueContiene("vacaciones", "2026-03-01");
    expect(periodosHasta(vac, 3)).toEqual([vac]);
    const sub = periodoQueContiene("subvencion_semestral", "2026-06-20");
    expect(periodosHasta(sub, 3)).toEqual([sub]);
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
