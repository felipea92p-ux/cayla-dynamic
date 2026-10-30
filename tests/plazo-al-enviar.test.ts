import { describe, it, expect } from "vitest";
import { diasAlEnviar, diasHasta, fraseDePlazo } from "@/lib/alertas/plazo-al-enviar";

describe("diasHasta: la resta de fechas de calendario", () => {
  it("hoy es el día 0, mañana el 1, ayer el -1", () => {
    expect(diasHasta("2026-10-25", "2026-10-25")).toBe(0);
    expect(diasHasta("2026-10-26", "2026-10-25")).toBe(1);
    expect(diasHasta("2026-10-24", "2026-10-25")).toBe(-1);
  });

  it("cruza el fin de mes y de año", () => {
    expect(diasHasta("2026-11-02", "2026-10-30")).toBe(3);
    expect(diasHasta("2027-01-02", "2026-12-30")).toBe(3);
    expect(diasHasta("2026-10-30", "2026-11-02")).toBe(-3);
  });

  it("febrero: año común y bisiesto", () => {
    expect(diasHasta("2026-03-01", "2026-02-28")).toBe(1);
    expect(diasHasta("2028-03-01", "2028-02-28")).toBe(2);
  });

  it("un mes entero de octubre a noviembre (31 días)", () => {
    expect(diasHasta("2026-11-25", "2026-10-25")).toBe(31);
  });

  it("fechas que no son de calendario devuelven null (no se inventa)", () => {
    for (const f of ["2026-02-31", "2026-13-01", "no es fecha", "", "2026-10-25T10:00:00Z", null, undefined, 20261025]) {
      expect(diasHasta(f, "2026-10-25")).toBeNull();
    }
    expect(diasHasta("2026-10-25", "mañana")).toBeNull();
  });
});

describe("diasAlEnviar: la fecha manda, el número del payload es respaldo", () => {
  it("una fila generada con 12 días que sale 4 días tarde dice 8, no 12", () => {
    // El payload se escribió el 2026-10-24 (vence el 11-05 = 12 días); sale el 10-28.
    expect(diasAlEnviar("2026-11-05", 12, "2026-10-28")).toBe(8);
  });

  it("sin fecha, o con fecha rota, cae al número del payload (número o texto)", () => {
    expect(diasAlEnviar(undefined, 12, "2026-10-28")).toBe(12);
    expect(diasAlEnviar("2026-02-31", "7", "2026-10-28")).toBe(7);
    expect(diasAlEnviar("basura", -2, "2026-10-28")).toBe(-2);
  });

  it("sin fecha ni número, null", () => {
    expect(diasAlEnviar(undefined, undefined, "2026-10-28")).toBeNull();
    expect(diasAlEnviar(null, "", "2026-10-28")).toBeNull();
    expect(diasAlEnviar(null, "abc", "2026-10-28")).toBeNull();
  });

  it("si venció mientras la fila esperaba, da negativo", () => {
    expect(diasAlEnviar("2026-10-20", 3, "2026-10-25")).toBe(-5);
  });
});

describe("fraseDePlazo", () => {
  it("futuro y hoy", () => {
    expect(fraseDePlazo(12)).toEqual({ verbo: "vence", plazo: "en 12 días", frase: "vence en 12 días" });
    expect(fraseDePlazo(1).frase).toBe("vence mañana");
    expect(fraseDePlazo(0).frase).toBe("vence hoy");
  });

  it("pasado cambia el verbo: no se dice «vence» de lo que ya venció", () => {
    expect(fraseDePlazo(-1).frase).toBe("venció ayer");
    expect(fraseDePlazo(-5)).toEqual({ verbo: "venció", plazo: "hace 5 días", frase: "venció hace 5 días" });
  });

  it("sin dato no inventa un plazo", () => {
    expect(fraseDePlazo(null)).toEqual({ verbo: "vence", plazo: null, frase: "vence pronto" });
  });
});
