// ============================================================================
// prueba-en-feriado.test.ts — a quién se le recomienda descanso en un feriado
// ============================================================================
// El aviso es blando (no frena nada), así que lo que hay que vigilar es a QUIÉN
// le salta: solo vínculo «prueba» con la prueba en curso, y solo en feriado.
// Un aviso que salta de más se aprende a ignorar; uno que no salta cuesta plata.
// ============================================================================
import { describe, it, expect } from "vitest";
import {
  avisoDeCopiar, conviveDarDescanso, cuerpoDelAviso, lineaDeSemana, tituloDelAviso, type PruebaDelDia,
} from "@/lib/admin/prueba-en-feriado";

const prueba = (o: Partial<PruebaDelDia> = {}): PruebaDelDia => ({ tipoVinculo: "prueba", situacion: "en_curso", dias: 1, plazo: 3, ...o });

describe("a quién se le recomienda descanso", () => {
  it("a quien está de prueba, en curso, un feriado", () => {
    expect(conviveDarDescanso(prueba(), true)).toBe(true);
  });
  it("nunca un día que no es feriado", () => {
    expect(conviveDarDescanso(prueba(), false)).toBe(false);
  });
  it("nunca a quien no tiene vínculo «prueba»", () => {
    for (const v of ["planilla", "practicante", "rxh", null]) expect(conviveDarDescanso(prueba({ tipoVinculo: v }), true)).toBe(false);
  });
  it("no a quien ya cumplió o pasó sus días: toca contrato, no cuidarlo", () => {
    expect(conviveDarDescanso(prueba({ situacion: "cumplida", dias: 3 }), true)).toBe(false);
    expect(conviveDarDescanso(prueba({ situacion: "vencida", dias: 4 }), true)).toBe(false);
  });
  it("si no se pudo leer la prueba, avisa igual por el vínculo", () => {
    expect(conviveDarDescanso(prueba({ situacion: null, dias: null, plazo: null }), true)).toBe(true);
  });
});

describe("lo que dicen los textos", () => {
  it("el cuerpo recomienda descanso, dice que se le paga y deja trabajar si se confirma", () => {
    const t = cuerpoDelAviso({ dias: 1, plazo: 3 });
    expect(t).toContain("lleva 1 de 3 días de preselección");
    expect(t).toMatch(/descanso/i);
    expect(t).toMatch(/se le paga/);
    expect(t).toMatch(/confírmalo/);
  });
  it("sin días leídos no inventa el conteo", () => {
    expect(cuerpoDelAviso({ dias: null, plazo: null })).not.toMatch(/lleva/);
  });
  it("el título nombra el feriado si lo conoce", () => {
    expect(tituloDelAviso("Fiestas Patrias")).toContain("Fiestas Patrias");
    expect(tituloDelAviso(null)).toBe("Es feriado y está en preselección");
  });
  it("no pone cifras de dinero (envejecerían en silencio)", () => {
    expect(cuerpoDelAviso({ dias: 1, plazo: 3 })).not.toMatch(/S\/|triple|\d+\s?%/);
  });
  it("la línea de la semana junta persona, día, feriado y días de prueba", () => {
    expect(lineaDeSemana({ personaId: "x", nombre: "Mariel Sarmiento", fecha: "2026-11-01", feriado: "Todos los Santos", dias: 2, plazo: 3 }, "Dom 1 nov"))
      .toBe("Mariel Sarmiento — Dom 1 nov · Todos los Santos · lleva 2 de 3 días de preselección");
  });
});

describe("copiar semana", () => {
  it("no dice nada si no hay feriado o no hay gente de prueba", () => {
    expect(avisoDeCopiar([], true)).toBeNull();
    expect(avisoDeCopiar(["Navidad"], false)).toBeNull();
  });
  it("nombra el feriado cuando hay los dos", () => {
    expect(avisoDeCopiar(["Navidad"], true)).toContain("«Navidad»");
  });
});
