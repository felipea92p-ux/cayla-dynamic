// ============================================================================
// selector-tema.test.ts — "claro" explícito tiene que ser siempre alcanzable
// ============================================================================
// El botón del selector rota sistema → claro → oscuro → sistema, saltando el
// paso "sistema" cuando se vería igual que lo que ya está en pantalla (para
// que el clic no se sienta roto). Hasta este arreglo, el salto se evaluaba
// para CUALQUIER candidato, no solo "sistema": en un equipo cuyo sistema
// operativo ya prefiere claro, pasar de "sistema" a "claro" se veía igual, el
// salto se disparaba igual, y el clic caía directo en "oscuro" — "claro"
// explícito quedaba inalcanzable. La persona terminaba en "sistema" (que no
// se guarda) creyendo que había elegido "claro", y el tema volvía a lo
// global en cuanto recargaba o cambiaba de pantalla.
// ============================================================================

import { afterEach, describe, expect, it, vi } from "vitest";

function conSistemaOperativoPrefiriendo(oscuro: boolean) {
  vi.stubGlobal("window", {
    matchMedia: (query: string) => ({
      matches: query === "(prefers-color-scheme: dark)" && oscuro,
    }),
  });
}

afterEach(() => {
  vi.unstubAllGlobals();
  vi.resetModules();
});

describe("el ciclo del selector de tema", () => {
  it("con el sistema operativo en claro, 'claro' explícito es alcanzable desde 'sistema'", async () => {
    conSistemaOperativoPrefiriendo(false);
    const { siguienteVisible } = await import("../apps/web/components/selector-tema");

    expect(siguienteVisible("sistema")).toBe("claro");
    expect(siguienteVisible("claro")).toBe("oscuro");
    expect(siguienteVisible("oscuro")).toBe("sistema");
  });

  it("con el sistema operativo en oscuro, el salto de 'sistema' sigue funcionando (sin regresión)", async () => {
    conSistemaOperativoPrefiriendo(true);
    const { siguienteVisible } = await import("../apps/web/components/selector-tema");

    // "oscuro" → "sistema" se vería igual (SO ya oscuro): salta a "claro".
    expect(siguienteVisible("oscuro")).toBe("claro");
    expect(siguienteVisible("claro")).toBe("oscuro");
    expect(siguienteVisible("sistema")).toBe("claro");
  });
});
