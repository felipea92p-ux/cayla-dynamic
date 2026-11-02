import { describe, it, expect } from "vitest";
import { esAvisoDeOtraPestana, tocaPonerseAlDia, MINIMO_ENTRE_LECTURAS_MS } from "@/lib/admin/turnos-al-dia";

// Turnos y cobertura se pone al día sin recargar (2026-11-02). Lo que se prueba
// es CUÁNDO vuelve a leer; qué lee sigue siendo de la pantalla.

describe("tocaPonerseAlDia", () => {
  const base = { visible: true, escribiendo: false, desdeUltimaMs: 60_000 };

  it("lee con la pestaña a la vista, sin nadie escribiendo y pasado el mínimo", () => {
    expect(tocaPonerseAlDia(base)).toBe(true);
  });

  it("no lee con la pestaña escondida: nadie la mira", () => {
    expect(tocaPonerseAlDia({ ...base, visible: false })).toBe(false);
  });

  it("no lee mientras alguien escribe: pisaría la meta que está tecleando", () => {
    expect(tocaPonerseAlDia({ ...base, escribiendo: true })).toBe(false);
  });

  it("no repite una lectura recién hecha al volver a la pestaña", () => {
    expect(tocaPonerseAlDia({ ...base, desdeUltimaMs: MINIMO_ENTRE_LECTURAS_MS - 1 })).toBe(false);
    expect(tocaPonerseAlDia({ ...base, desdeUltimaMs: MINIMO_ENTRE_LECTURAS_MS })).toBe(true);
  });

  it("un aviso de otra pestaña lee en el acto (mínimo 0), pero tampoco encima de lo que se escribe", () => {
    expect(tocaPonerseAlDia({ ...base, desdeUltimaMs: 0, minimoMs: 0 })).toBe(true);
    expect(tocaPonerseAlDia({ ...base, desdeUltimaMs: 0, minimoMs: 0, escribiendo: true })).toBe(false);
  });
});

describe("esAvisoDeOtraPestana", () => {
  it("acepta un aviso de cambio que vino de otra pestaña", () => {
    expect(esAvisoDeOtraPestana({ tipo: "cambio", origen: "b" }, "a")).toBe(true);
  });

  it("ignora el aviso que salió de esta misma pestaña: ya se puso al día al guardar", () => {
    expect(esAvisoDeOtraPestana({ tipo: "cambio", origen: "a" }, "a")).toBe(false);
  });

  it("ignora cualquier otra cosa que pase por el canal", () => {
    for (const dato of [null, undefined, "cambio", 42, {}, { tipo: "otro", origen: "b" }, { tipo: "cambio" }]) {
      expect(esAvisoDeOtraPestana(dato, "a")).toBe(false);
    }
  });
});
