import { describe, expect, it } from "vitest";
import { horaCompleta, instanteDeMarca } from "../apps/web/lib/admin/hora-de-marca";

describe("hora de una marca escrita a mano", () => {
  it("arma el instante en hora de Lima", () => {
    expect(instanteDeMarca("2026-11-13", "15:00")).toBe("2026-11-13T15:00:00-05:00");
  });

  it("descarta los segundos si el navegador los manda", () => {
    expect(instanteDeMarca("2026-11-13", "15:00:30")).toBe("2026-11-13T15:00:00-05:00");
  });

  // El caso real del 2026-11-13: el campo mostraba «03:00 p.m.» y llegó vacío.
  it("nunca arma un instante con la hora vacía", () => {
    expect(instanteDeMarca("2026-11-13", "")).toBeNull();
    expect(instanteDeMarca("2026-11-13", undefined)).toBeNull();
  });

  it("rechaza horas a medio escribir o imposibles", () => {
    for (const h of [":00", "3:00", "15:", "24:00", "15:60", "15h00"]) expect(horaCompleta(h)).toBeNull();
  });

  it("rechaza una fecha vacía", () => {
    expect(instanteDeMarca("", "15:00")).toBeNull();
  });
});
