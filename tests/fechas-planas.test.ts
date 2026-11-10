import { describe, expect, it } from "vitest";
import { diasDelTramo, diasEntre, sumarDias, sumarMeses } from "@cayla-dynamic/shared";

// La aritmética de fechas planas (`AAAA-MM-DD`) de `fecha-lima.ts`: la única copia desde el 2026-11-10. Antes había
// unas veinte en `apps/web`, y se comprobó que la versión única da lo mismo que cada una en más de un millón de
// casos (2023–2029, ±400 días, ±30 meses) antes de reemplazarlas.

describe("sumarDias", () => {
  it("cruza el fin de mes y de año, hacia adelante y hacia atrás", () => {
    expect(sumarDias("2026-01-31", 1)).toBe("2026-02-01");
    expect(sumarDias("2026-12-31", 1)).toBe("2027-01-01");
    expect(sumarDias("2027-01-01", -1)).toBe("2026-12-31");
    expect(sumarDias("2026-11-09", 0)).toBe("2026-11-09");
  });
  it("respeta el 29 de febrero de los bisiestos", () => {
    expect(sumarDias("2028-02-28", 1)).toBe("2028-02-29");
    expect(sumarDias("2026-02-28", 1)).toBe("2026-03-01");
  });
});

describe("sumarMeses: la misma cuenta que `interval 'N months'` de Postgres", () => {
  it("se recorta al último día del mes de llegada, no salta al siguiente", () => {
    expect(sumarMeses("2026-01-31", 1)).toBe("2026-02-28");
    expect(sumarMeses("2028-01-31", 1)).toBe("2028-02-29");
    expect(sumarMeses("2028-02-29", 12)).toBe("2029-02-28");
  });
  it("cruza el año en los dos sentidos", () => {
    expect(sumarMeses("2026-11-15", 3)).toBe("2027-02-15");
    expect(sumarMeses("2026-01-15", -2)).toBe("2025-11-15");
  });
});

describe("diasEntre y diasDelTramo no son lo mismo, y por eso tienen nombres distintos", () => {
  it("diasEntre es la distancia: del 1 al 3 son 2", () => {
    expect(diasEntre("2026-11-01", "2026-11-03")).toBe(2);
    expect(diasEntre("2026-11-03", "2026-11-01")).toBe(-2);
    expect(diasEntre("2026-11-09", "2026-11-09")).toBe(0);
  });
  it("diasDelTramo cuenta los dos extremos: del 1 al 3 son 3, y un solo día es 1", () => {
    expect(diasDelTramo("2026-11-01", "2026-11-03")).toBe(3);
    expect(diasDelTramo("2026-11-09", "2026-11-09")).toBe(1);
  });
  it("un año bisiesto tiene 366 días en su tramo", () => {
    expect(diasDelTramo("2028-01-01", "2028-12-31")).toBe(366);
  });
});
