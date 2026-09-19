// ============================================================================
// cobertura-turnos.test.ts — lo que Turnos le dice a quien arma la semana
// ============================================================================
// El caso que las originó (2026-09-18): Oficina TRU, cinco personas con turno,
// todas en áreas que no son operativas. La pantalla decía «sin turnos» y pintaba
// la cobertura como un bloque sólido. Aquí se fija que «no hay nadie DEL GRUPO
// MEDIDO» nunca se diga como «no hay turnos».
// ============================================================================
import { describe, expect, it } from "vitest";
import { colorCobertura, etiquetaCobertura } from "@/lib/admin/cobertura-turnos";

const base = { quien: "operativas" as const, hayGente: true, sinMeta: false, hayMeta: true, pct: 75 };

describe("etiquetaCobertura — operativas", () => {
  it("con gente y con meta: el porcentaje cubierto", () => {
    expect(etiquetaCobertura(base)).toEqual({ texto: "cubierto 75%", tono: "porcentaje" });
  });

  it("con meta puesta y ninguna operativa programada: alerta roja", () => {
    // Alguien olvidó armar los turnos de ese día: se avisa, no se calla en gris.
    const r = etiquetaCobertura({ ...base, hayGente: false });
    expect(r).toEqual({ texto: "¡ninguna operativa programada!", tono: "alerta" });
  });

  it("sin meta y ninguna operativa (Oficina TRU): un dato neutro que NO dice «sin turnos»", () => {
    const r = etiquetaCobertura({ ...base, hayGente: false, hayMeta: false });
    expect(r).toEqual({ texto: "sin operativas programadas", tono: "neutro" });
    expect(r.texto).not.toMatch(/sin turnos/i);
  });

  it("con gente pero sin meta: «sin meta»", () => {
    expect(etiquetaCobertura({ ...base, sinMeta: true, hayMeta: false })).toEqual({ texto: "sin meta", tono: "neutro" });
  });

  it("la alerta manda sobre «sin meta»: meta puesta y nadie es lo más urgente", () => {
    // Con meta y sin gente, `sinMeta` no aplica (no hubo contra qué comparar la
    // gente que no existe), y aun así la alerta tiene que ganar.
    const r = etiquetaCobertura({ ...base, hayGente: false, sinMeta: false, hayMeta: true });
    expect(r.tono).toBe("alerta");
  });
});

describe("etiquetaCobertura — encargadas", () => {
  const enc = { ...base, quien: "encargadas" as const };

  it("las mismas cuatro respuestas, en su propio idioma", () => {
    expect(etiquetaCobertura(enc)).toEqual({ texto: "cubierto 75%", tono: "porcentaje" });
    expect(etiquetaCobertura({ ...enc, hayGente: false })).toEqual({ texto: "¡ninguna encargada programada!", tono: "alerta" });
    expect(etiquetaCobertura({ ...enc, hayGente: false, hayMeta: false })).toEqual({ texto: "sin encargadas programadas", tono: "neutro" });
    expect(etiquetaCobertura({ ...enc, sinMeta: true, hayMeta: false })).toEqual({ texto: "sin meta", tono: "neutro" });
  });

  it("tampoco dice «sin turnos»", () => {
    for (const hayMeta of [true, false]) {
      expect(etiquetaCobertura({ ...enc, hayGente: false, hayMeta }).texto).not.toMatch(/sin turnos/i);
    }
  });
});

describe("colorCobertura — de qué color se pinta una hora", () => {
  it("sin meta y sin nadie: arena tenue, no un bloque sólido que parezca «todo cubierto»", () => {
    const c = colorCobertura(0, 0);
    expect(c).toContain("--color-sand");
    expect(c).not.toBe("var(--color-taupe)");
  });

  it("sin meta pero con gente: taupe neutro (hay gente, no hay contra qué medirla)", () => {
    expect(colorCobertura(3, 0)).toBe("var(--color-taupe)");
  });

  it("con meta y nadie: el rojo entero", () => {
    expect(colorCobertura(0, 2)).toContain("--color-verde) 0%");
  });

  it("con la meta cubierta o pasada: el verde entero, sin pasarse", () => {
    expect(colorCobertura(2, 2)).toContain("--color-verde) 100%");
    expect(colorCobertura(9, 2)).toContain("--color-verde) 100%");
  });

  it("a medias: la proporción exacta", () => {
    expect(colorCobertura(1, 2)).toContain("--color-verde) 50%");
  });
});
