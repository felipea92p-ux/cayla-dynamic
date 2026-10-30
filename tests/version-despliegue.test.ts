// ============================================================================
// version-despliegue.test.ts — «¿hay una versión nueva?», decidido sin red
// ============================================================================
// El aviso de versión nueva se equivoca en una sola dirección que importa: avisar
// de MÁS. Una barra que baja sin que haya nada nuevo se aprende a ignorar, y el
// día que sí haya algo nadie la mira. Por eso lo que hay que probar es lo que
// NO debe avisar.
// ============================================================================
import { describe, it, expect } from "vitest";
import { hayVersionNueva } from "@/lib/version-despliegue";

describe("hayVersionNueva", () => {
  it("avisa cuando el servidor contesta un despliegue distinto del de la página", () => {
    expect(hayVersionNueva("dpl_AAA", "dpl_BBB")).toBe(true);
  });

  it("no avisa cuando es el mismo despliegue", () => {
    expect(hayVersionNueva("dpl_AAA", "dpl_AAA")).toBe(false);
  });

  it("no avisa si esta página no sabe su versión (fuera de Vercel): no hay con qué comparar", () => {
    expect(hayVersionNueva("", "dpl_BBB")).toBe(false);
  });

  it("no avisa si el servidor no dice versión: ni vacía, ni en blanco, ni un tipo raro", () => {
    for (const rota of ["", "   ", null, undefined, 42, {}, [], true]) {
      expect(hayVersionNueva("dpl_AAA", rota)).toBe(false);
    }
  });

  it("un espacio o un salto de línea de más en la respuesta no inventa una versión nueva", () => {
    expect(hayVersionNueva("dpl_AAA", "dpl_AAA\n")).toBe(false);
    expect(hayVersionNueva("dpl_AAA", " dpl_AAA ")).toBe(false);
  });
});
