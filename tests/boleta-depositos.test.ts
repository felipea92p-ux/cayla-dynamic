import { describe, expect, it } from "vitest";
import { detalleDeposito, nombreDeposito } from "../apps/web/lib/boleta-depositos";

describe("lo ya depositado en la boleta (0622)", () => {
  it("nombra cada semestre con su nombre legal", () => {
    expect(nombreDeposito({ ventana: "cts_nov", anio: 2026 })).toBe("CTS may–oct 2026");
    expect(nombreDeposito({ ventana: "cts_may", anio: 2026 })).toBe("CTS nov 2025–abr 2026");
    expect(nombreDeposito({ ventana: "grati_s1", anio: 2026 })).toBe("Gratificación ene–jun 2026");
    expect(nombreDeposito({ ventana: "grati_s2", anio: 2026 })).toBe("Gratificación jul–dic 2026");
  });

  it("nunca llama «bono» a un derecho de ley (0621)", () => {
    for (const ventana of ["grati_s1", "grati_s2", "cts_may", "cts_nov", "vacaciones", "subvencion_semestral", "descanso_practicante"]) {
      expect(nombreDeposito({ ventana, anio: 2026 })).not.toMatch(/bono/i);
    }
  });

  it("la CTS dice que fue a la cuenta CTS; lo demás, que se pagó aparte", () => {
    expect(detalleDeposito({ ventana: "cts_nov", fecha_pago: "2026-11-14" })).toBe("depositada en tu cuenta CTS el 14 nov");
    expect(detalleDeposito({ ventana: "grati_s2", fecha_pago: "2026-12-15" })).toBe("pagada el 15 dic, aparte de este pago");
  });
});
