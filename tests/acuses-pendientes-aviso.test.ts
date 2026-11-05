// ============================================================================
// acuses-pendientes-aviso.test.ts — el aviso de constancias no estorba al firmar
// ============================================================================
// El aviso mandaba a /admin/normas#doc-<id>, y ahí se volvía a pintar ENCIMA del
// documento que acababa de abrirse (2026-11-04): el marco del panel monta su
// propio aviso desde cero y el «ya lo cerré» vivía en el componente anterior.
// Esto fija las dos reglas que lo arreglan.

import { describe, expect, it } from "vitest";
import {
  acusesPendientes,
  avisoYaCerrado,
  esPantallaDeConstancia,
  recordarAvisoCerrado,
} from "@/lib/acuses-pendientes";

describe("el aviso de constancias no estorba a quien va a firmar", () => {
  it("calla en todas las pantallas a las que él mismo manda", () => {
    const lista = acusesPendientes({ version: 1, mi_acuse: null }, [
      { documento_id: "abc", titulo: "RIT", tipo_nombre: "Reglamento", requiere_acuse: true, mi_acuse_at: null },
    ]);
    expect(lista).toHaveLength(2);
    for (const { href } of lista) {
      // `usePathname` no incluye el ancla.
      expect(esPantallaDeConstancia(href.split("#")[0]!)).toBe(true);
    }
  });

  it("sigue saliendo en el resto, también en rutas que solo se parecen", () => {
    for (const ruta of ["/mio", "/mio/bandeja", "/admin/dashboard", "/admin/normas-viejas"]) {
      expect(esPantallaDeConstancia(ruta)).toBe(false);
    }
  });

  it("recuerda el cierre aunque se desmonte el componente, y solo para esa persona", () => {
    expect(avisoYaCerrado("ana")).toBe(false);
    recordarAvisoCerrado("ana");
    expect(avisoYaCerrado("ana")).toBe(true);
    expect(avisoYaCerrado("otra-persona")).toBe(false);
  });
});
