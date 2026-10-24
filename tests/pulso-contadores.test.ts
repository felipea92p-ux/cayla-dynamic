import { describe, it, expect } from "vitest";
import { vencioElContador, VIGENCIA_CONTADORES_MS } from "@/lib/admin/use-pulso-contadores";

// El menú del panel ya no vuelve a pedir sus contadores en cada navegación:
// esta es la regla de cuándo sí. Si se equivoca hacia «nunca», un reclamo sin
// leer en Incidencias deja de verse; hacia «siempre», vuelven las ~60
// consultas por pantalla.
describe("vencioElContador", () => {
  const T0 = 1_000_000;

  it("sin consulta previa, toca consultar", () => {
    expect(vencioElContador(null, T0)).toBe(true);
  });

  it("dentro de la vigencia no toca: navegar rápido entre pantallas no repite nada", () => {
    expect(vencioElContador(T0, T0 + 1)).toBe(false);
    expect(vencioElContador(T0, T0 + VIGENCIA_CONTADORES_MS - 1)).toBe(false);
  });

  it("al cumplirse la vigencia exacta ya toca (el borde cuenta como vencido)", () => {
    expect(vencioElContador(T0, T0 + VIGENCIA_CONTADORES_MS)).toBe(true);
  });

  it("pasada la vigencia toca, y respeta una vigencia propia", () => {
    expect(vencioElContador(T0, T0 + 5 * VIGENCIA_CONTADORES_MS)).toBe(true);
    expect(vencioElContador(T0, T0 + 999, 1_000)).toBe(false);
    expect(vencioElContador(T0, T0 + 1_000, 1_000)).toBe(true);
  });
});
