// ============================================================================
// fecha-lima.test.ts — Cuándo es "hoy" en Perú
// ============================================================================
// El corte del día decide a qué fecha se le carga un marcaje, o sea a qué día
// se le pagan las horas. El servidor corre en UTC: a las 7pm de Lima ya es el
// día siguiente allá. Estas pruebas fijan instantes reales alrededor de ese
// borde y comprueban que la respuesta sea la fecha peruana.
// ============================================================================
import { describe, it, expect } from "vitest";
import {
  TZ_LIMA, fechaLima, rangoDelDiaLima, rangoDelMesLima, horaLima, horaDecimalLima,
} from "@cayla-dynamic/shared";

describe("el borde de medianoche, que es donde se pierde un día de pago", () => {
  it("23:30 de Lima sigue siendo el mismo día, aunque en UTC ya sea el siguiente", () => {
    // 2026-08-04 23:30 Lima = 2026-08-05 04:30 UTC
    expect(fechaLima("2026-08-05T04:30:00Z")).toBe("2026-08-04");
  });
  it("00:30 de Lima ya es el día nuevo", () => {
    // 2026-08-05 00:30 Lima = 2026-08-05 05:30 UTC
    expect(fechaLima("2026-08-05T05:30:00Z")).toBe("2026-08-05");
  });
  it("las 00:00 UTC caen en el día ANTERIOR en Lima", () => {
    expect(fechaLima("2026-08-05T00:00:00Z")).toBe("2026-08-04");
  });
});

describe("Perú no cambia de hora, ni en enero ni en julio", () => {
  // Desde 1994 no hay horario de verano. Si esto fallara, media planilla se
  // correría un día en una mitad del año y no en la otra.
  it("enero y julio tienen el mismo desfase", () => {
    expect(fechaLima("2026-01-15T04:30:00Z")).toBe("2026-01-14");
    expect(fechaLima("2026-07-15T04:30:00Z")).toBe("2026-07-14");
  });
  it("la zona es la de Lima", () => {
    expect(TZ_LIMA).toBe("America/Lima");
  });
});

describe("el rango de un día no se solapa con el siguiente", () => {
  it("cubre el día entero y cierra antes de medianoche", () => {
    const { inicio, fin } = rangoDelDiaLima("2026-08-04");
    expect(inicio).toBe("2026-08-04T00:00:00-05:00");
    expect(fin).toBe("2026-08-04T23:59:59.999-05:00");
  });
  it("el fin de un día es anterior al inicio del siguiente", () => {
    const hoy = rangoDelDiaLima("2026-08-04");
    const manana = rangoDelDiaLima("2026-08-05");
    expect(new Date(hoy.fin).getTime()).toBeLessThan(new Date(manana.inicio).getTime());
  });
});

describe("el rango del mes acierta el último día", () => {
  it("agosto tiene 31", () => {
    expect(rangoDelMesLima("2026-08-15")).toEqual({ inicio: "2026-08-01", fin: "2026-08-31" });
  });
  it("febrero normal tiene 28", () => {
    expect(rangoDelMesLima("2026-02-10").fin).toBe("2026-02-28");
  });
  it("febrero bisiesto tiene 29", () => {
    expect(rangoDelMesLima("2028-02-10").fin).toBe("2028-02-29");
  });
});

describe("la hora, para pintar y para comparar contra el corte de turno", () => {
  it("14:15 de Lima se muestra como 14:15", () => {
    // 2026-08-04 14:15 Lima = 19:15 UTC
    expect(horaLima("2026-08-04T19:15:00Z")).toBe("14:15");
  });
  it("14:15 en decimal es 14.25 — el corte mañana/tarde de Turnos y Dashboard", () => {
    expect(horaDecimalLima("2026-08-04T19:15:00Z")).toBe(14.25);
  });
  it("medianoche de Lima es 0, no 24", () => {
    expect(horaDecimalLima("2026-08-04T05:00:00Z")).toBe(0);
  });
});
