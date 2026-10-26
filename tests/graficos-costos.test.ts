import { describe, expect, it } from "vitest";
import { abreviarSoles } from "@/components/costos/graficos-costos";

describe("abreviarSoles", () => {
  it("miles y millones, con un decimal", () => {
    expect(abreviarSoles(33404.56)).toBe("S/ 33.4 mil");
    expect(abreviarSoles(104826.32)).toBe("S/ 104.8 mil");
    expect(abreviarSoles(1_250_000)).toBe("S/ 1.3 M");
  });
  it("menos de mil se escribe tal cual, sin decimales", () => {
    expect(abreviarSoles(839.04)).toBe("S/ 839");
    expect(abreviarSoles(0)).toBe("S/ 0");
  });
});
