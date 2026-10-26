// ============================================================================
// feriado-recien-ingresado.test.ts — a quién se le recomienda descanso en un feriado
// ============================================================================
// El aviso es blando (no frena nada), así que lo que hay que vigilar es a QUIÉN
// le salta: solo planilla, solo un feriado, y solo con menos de N días CALENDARIO
// desde el ingreso, contados a la fecha del feriado (Felipe, 2026-10-26).
// Un aviso que salta de más se aprende a ignorar; uno que no salta cuesta plata.
// ============================================================================
import { describe, it, expect } from "vitest";
import {
  avisoDeCopiar, conviveDarDescanso, cuerpoDelAviso, DIAS_AVISO_FERIADO_DEFECTO, diasDesdeIngreso, lineaDeSemana,
  textoAntiguedad, tituloDelAviso, type IngresoDelDia,
} from "@/lib/admin/feriado-recien-ingresado";

const persona = (o: Partial<IngresoDelDia> = {}): IngresoDelDia => ({ tipoVinculo: "planilla", fechaIngreso: "2026-10-26", ...o });
const TODOS_LOS_SANTOS = "2026-11-01";

describe("a quién se le recomienda descanso", () => {
  it("a quien ingresó el 26/10, el domingo 1/11 (6 días): es el caso de Felipe", () => {
    expect(conviveDarDescanso(persona(), TODOS_LOS_SANTOS, true)).toBe(true);
  });
  it("nunca un día que no es feriado", () => {
    expect(conviveDarDescanso(persona(), TODOS_LOS_SANTOS, false)).toBe(false);
  });
  it("nunca a quien no está en planilla", () => {
    for (const v of ["practicante", "rxh", "no_trabajador", null]) {
      expect(conviveDarDescanso(persona({ tipoVinculo: v }), TODOS_LOS_SANTOS, true)).toBe(false);
    }
  });
  it("quien aún figure con el vínculo «prueba» (que se retira) sigue siendo planilla", () => {
    expect(conviveDarDescanso(persona({ tipoVinculo: "prueba" }), TODOS_LOS_SANTOS, true)).toBe(true);
  });
  it("el día 14 todavía avisa y el 15 ya no (menos de 15 días calendario)", () => {
    expect(conviveDarDescanso(persona(), "2026-11-09", true)).toBe(true);
    expect(conviveDarDescanso(persona(), "2026-11-10", true)).toBe(false);
  });
  it("quien lleva meses no recibe el aviso", () => {
    expect(conviveDarDescanso(persona({ fechaIngreso: "2026-03-02" }), TODOS_LOS_SANTOS, true)).toBe(false);
  });
  it("quien todavía no ingresó ese día no es la persona a quien se cuida", () => {
    expect(conviveDarDescanso(persona({ fechaIngreso: "2026-11-05" }), TODOS_LOS_SANTOS, true)).toBe(false);
  });
  it("respeta el umbral de Parámetros", () => {
    expect(conviveDarDescanso(persona(), "2026-11-05", true, 7)).toBe(false);
    expect(conviveDarDescanso(persona(), "2026-11-05", true, 30)).toBe(true);
  });
  it("el umbral de partida es 15", () => {
    expect(DIAS_AVISO_FERIADO_DEFECTO).toBe(15);
  });
  it("sin ingreso legible no avisa: un aviso blando que no sale no cuesta nada", () => {
    expect(conviveDarDescanso(persona({ fechaIngreso: null }), TODOS_LOS_SANTOS, true)).toBe(false);
    expect(conviveDarDescanso(persona({ fechaIngreso: "2026-02-30" }), TODOS_LOS_SANTOS, true)).toBe(false);
  });
});

describe("lo que dicen los textos", () => {
  it("la antigüedad se dice en días, con singular y el mismo día", () => {
    expect(textoAntiguedad(6)).toBe("ingresó hace 6 días");
    expect(textoAntiguedad(1)).toBe("ingresó hace 1 día");
    expect(textoAntiguedad(0)).toBe("ingresa ese mismo día");
    expect(textoAntiguedad(null)).toBe("");
    expect(textoAntiguedad(-3)).toBe("");
  });
  it("cuenta los días desde el ingreso", () => {
    expect(diasDesdeIngreso("2026-10-26", TODOS_LOS_SANTOS)).toBe(6);
    expect(diasDesdeIngreso(null, TODOS_LOS_SANTOS)).toBeNull();
  });
  it("el cuerpo recomienda descanso, aclara que el feriado se paga igual y deja trabajar si se confirma", () => {
    const t = cuerpoDelAviso({ dias: 6 });
    expect(t).toContain("ingresó hace 6 días");
    expect(t).toMatch(/descanso/i);
    expect(t).toMatch(/no es dejar de pagarle/);
    expect(t).toMatch(/descanso sustitutorio/);
    expect(t).toMatch(/confirmarlo/);
  });
  it("sin días leídos no inventa el conteo", () => {
    expect(cuerpoDelAviso({ dias: null })).not.toMatch(/ingresó hace/);
  });
  it("el título nombra el feriado si lo conoce", () => {
    expect(tituloDelAviso("Todos los Santos")).toContain("Todos los Santos");
    expect(tituloDelAviso(null)).toBe("Es feriado y ingresó hace poco");
  });
  it("no pone cifras de dinero (envejecerían en silencio)", () => {
    expect(cuerpoDelAviso({ dias: 6 })).not.toMatch(/S\/|triple|\d+\s?%/);
  });
  it("no dice nunca que el vínculo es «de prueba» ni que se retira a alguien", () => {
    expect(cuerpoDelAviso({ dias: 6 })).not.toMatch(/de prueba/i);
    expect(tituloDelAviso("X")).not.toMatch(/de prueba/i);
  });
  it("la línea de la semana junta persona, día, feriado y antigüedad", () => {
    expect(lineaDeSemana({ personaId: "x", nombre: "Mariel Sarmiento", fecha: TODOS_LOS_SANTOS, feriado: "Todos los Santos", dias: 6 }, "Dom 1 nov"))
      .toBe("Mariel Sarmiento — Dom 1 nov · Todos los Santos · ingresó hace 6 días");
  });
});

describe("copiar semana", () => {
  it("no dice nada si no hay feriado o no hay gente recién ingresada", () => {
    expect(avisoDeCopiar([], true)).toBeNull();
    expect(avisoDeCopiar(["Navidad"], false)).toBeNull();
  });
  it("nombra el feriado cuando hay los dos", () => {
    expect(avisoDeCopiar(["Navidad"], true)).toContain("«Navidad»");
  });
});
