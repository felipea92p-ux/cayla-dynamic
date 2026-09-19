import { describe, expect, it } from "vitest";
import { valorDeCorreccion } from "@/lib/admin/valor-de-correccion";

// El caso real del 2026-09-19: el rastro mostraba «2026-09-05 19:28:31.621+00»
// y en Lima eran las 14:28. Cinco horas de diferencia sobre una corrección.
describe("valorDeCorreccion", () => {
  it("un instante en UTC se muestra en hora de Lima, no en UTC", () => {
    const v = valorDeCorreccion("2026-09-05 19:28:31.621+00");
    expect(v).toContain("14:28:31");
    expect(v).not.toContain("19:28");
  });

  it("acepta las formas con que Postgres devuelve el offset", () => {
    for (const s of [
      "2026-09-05 19:29:00+00", "2026-09-05T19:29:00Z", "2026-09-05 19:29:00+00:00",
      "2026-09-05 14:29:00-05", "2026-09-05 14:29:00.123456-0500",
    ]) {
      expect(valorDeCorreccion(s), s).toContain("14:29:");
    }
  });

  it("lo que no es un instante con zona se devuelve tal cual, sin adivinar", () => {
    expect(valorDeCorreccion("entrada")).toBe("entrada");
    expect(valorDeCorreccion("142")).toBe("142");
    expect(valorDeCorreccion("2026-09-05 19:29:00")).toBe("2026-09-05 19:29:00"); // sin zona: no se sabe
  });

  it("nulo o vacío se dicen con una raya", () => {
    expect(valorDeCorreccion(null)).toBe("—");
    expect(valorDeCorreccion("")).toBe("—");
  });
});
