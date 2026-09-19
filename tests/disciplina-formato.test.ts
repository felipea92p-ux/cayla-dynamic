// Cómo se escriben las fechas de Disciplina. Lo que importa acá: un antecedente
// que vence lleva su AÑO, y sus doce meses son de calendario (RIT 56.1), no 365 días.

import { describe, it, expect } from "vitest";
import { fechaConAnio, sumarMeses } from "@/components/disciplina/formato";

describe("fechaConAnio", () => {
  it("dice el año, para que «vigente hasta el 25-ago-2027» no se lea vencido en setiembre de 2026", () => {
    expect(fechaConAnio("2027-08-25")).toBe("25-ago-2027");
    expect(fechaConAnio("2026-09-02")).toBe("02-set-2026");
  });
});

describe("sumarMeses", () => {
  it("doce meses de calendario, el mismo día un año después", () => {
    expect(sumarMeses("2026-08-25", 12)).toBe("2027-08-25");
  });
  it("cruzando un 29 de febrero NO son 365 días: sigue siendo el mismo día del año siguiente", () => {
    expect(sumarMeses("2027-03-10", 12)).toBe("2028-03-10");
  });
  it("no se pasa de fin de mes", () => {
    expect(sumarMeses("2028-02-29", 12)).toBe("2029-02-28");
    expect(sumarMeses("2026-01-31", 1)).toBe("2026-02-28");
  });
});
