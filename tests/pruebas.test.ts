// ============================================================================
// pruebas.test.ts — lo que una pantalla dice de la prueba de tres días
// ============================================================================
// El texto que más importa es el de «se retiró»: es la única advertencia entre
// quien decide y una hora de trabajo sin pagar. Se vigila que SIEMPRE diga que
// no se paga y cuántas horas son, y que «no apto» diga lo contrario.
// ============================================================================
import { describe, it, expect } from "vitest";
import {
  consecuenciaDelCierre, etiquetaDePrueba, mensajeDeCierre, motivoValido, nombreDe, ordenarPruebas,
  puedeHacerContrato, resumenDeCierre, situacionDe, textoConsentimientoDni, textoDeHoras, textoDelDia,
  type CierrePrueba, type FilaPrueba,
} from "@/lib/admin/pruebas";

function fila(o: Partial<FilaPrueba> = {}): FilaPrueba {
  return {
    prueba_id: "p1", persona_id: "x1", nombres: "Mariel", apellidos: "Sarmiento", sede_id: "s1", sede_codigo: "TRU",
    inicio: "2026-10-16", dias_trabajados: 1, dias_plazo: 3, situacion: "en_curso", ultima_jornada: "2026-10-16",
    registrada: true, horas_marcadas: 5.35, dni_cargado: false, ...o,
  };
}

describe("la situación de una prueba", () => {
  it("se confía en la que dice la base", () => {
    expect(situacionDe(fila({ situacion: "cumplida", dias_trabajados: 3 }))).toBe("cumplida");
    expect(situacionDe(fila({ situacion: "vencida", dias_trabajados: 4 }))).toBe("vencida");
  });

  it("si llega algo desconocido se deriva de los días, y nunca se inventa una pasada de plazo", () => {
    expect(situacionDe(fila({ situacion: "otra", dias_trabajados: 1 }))).toBe("en_curso");
    expect(situacionDe(fila({ situacion: "", dias_trabajados: 3 }))).toBe("cumplida");
    expect(situacionDe(fila({ situacion: "x", dias_trabajados: 4 }))).toBe("vencida");
  });
});

describe("la etiqueta «Prueba · X de 3»", () => {
  it("en curso dice cuántos días lleva y es informativa", () => {
    expect(etiquetaDePrueba(fila({ dias_trabajados: 2 }))).toEqual({ texto: "Prueba · 2 de 3", variante: "informativo" });
    expect(etiquetaDePrueba(fila({ dias_trabajados: 0 }))).toEqual({ texto: "Prueba · 0 de 3", variante: "informativo" });
  });

  it("al completar el plazo avisa que toca decidir", () => {
    expect(etiquetaDePrueba(fila({ situacion: "cumplida", dias_trabajados: 3 })))
      .toEqual({ texto: "Prueba · 3 de 3", variante: "advertencia" });
  });

  it("pasado el plazo sube a alerta y dice los días reales", () => {
    expect(etiquetaDePrueba(fila({ situacion: "vencida", dias_trabajados: 5 })))
      .toEqual({ texto: "Prueba · 5 días", variante: "alerta" });
  });

  it("el plazo no está escrito a mano: sale de la fila", () => {
    expect(etiquetaDePrueba(fila({ dias_trabajados: 1, dias_plazo: 5 })).texto).toBe("Prueba · 1 de 5");
  });
});

describe("la frase del día", () => {
  it("en curso: cuántos lleva y cuántos le faltan, en singular y plural", () => {
    expect(textoDelDia(fila({ dias_trabajados: 1 }))).toContain("faltan 2 días");
    expect(textoDelDia(fila({ dias_trabajados: 2 }))).toContain("falta 1 día");
  });

  it("cumplida: dice que toca decidir", () => {
    expect(textoDelDia(fila({ situacion: "cumplida", dias_trabajados: 3 }))).toContain("toca decidir");
  });

  it("vencida: dice cuántos días se pasó y que nadie decidió", () => {
    const t = textoDelDia(fila({ situacion: "vencida", dias_trabajados: 5 }));
    expect(t).toContain("2 más que el plazo");
    expect(t).toContain("nadie decidió");
  });
});

describe("hacer contrato", () => {
  it("solo cuando completó el plazo", () => {
    expect(puedeHacerContrato(fila({ dias_trabajados: 2 }))).toBe(false);
    expect(puedeHacerContrato(fila({ situacion: "cumplida", dias_trabajados: 3 }))).toBe(true);
    expect(puedeHacerContrato(fila({ situacion: "vencida", dias_trabajados: 4 }))).toBe(true);
  });
});

describe("el orden", () => {
  it("primero las vencidas, luego las que tocan decidir, luego las en curso", () => {
    const orden = ordenarPruebas([
      fila({ persona_id: "a", nombres: "A", situacion: "en_curso" }),
      fila({ persona_id: "b", nombres: "B", situacion: "vencida", dias_trabajados: 4 }),
      fila({ persona_id: "c", nombres: "C", situacion: "cumplida", dias_trabajados: 3 }),
    ]).map((f) => f.persona_id);
    expect(orden).toEqual(["b", "c", "a"]);
  });

  it("dentro de una misma situación, la que empezó antes primero; y no toca el original", () => {
    const originales = [
      fila({ persona_id: "tarde", inicio: "2026-10-18" }),
      fila({ persona_id: "temprano", inicio: "2026-10-10" }),
    ];
    expect(ordenarPruebas(originales).map((f) => f.persona_id)).toEqual(["temprano", "tarde"]);
    expect(originales.map((f) => f.persona_id)).toEqual(["tarde", "temprano"]);
  });
});

describe("lo que se lee antes de confirmar", () => {
  it("«se retiró» dice SIEMPRE que no se paga, y cuántas horas son", () => {
    const c = consecuenciaDelCierre("retirado", { dias_trabajados: 1, horas_marcadas: 5.35 });
    expect(c.peligro).toBe(true);
    expect(c.lineas[0]).toContain("NO se le paga");
    expect(c.lineas[0]).toContain("5,35 h");
    expect(c.lineas[0]).toContain("1 día");
  });

  it("«no apto» dice que SÍ se paga, y que no cobra asignación familiar", () => {
    const c = consecuenciaDelCierre("no_apto", { dias_trabajados: 3, horas_marcadas: 19.5 });
    expect(c.peligro).toBe(false);
    expect(c.lineas[0]).toContain("Se le paga lo trabajado");
    expect(c.lineas[0]).toContain("3 días");
    expect(c.lineas[0]).toContain("19,5 h");
    expect(c.lineas[0]).toContain("asignación familiar");
    expect(c.lineas[0]).not.toContain("NO se le paga");
  });

  it("las dos dicen que queda registrado quién lo decidió", () => {
    for (const r of ["retirado", "no_apto"] as const) {
      expect(consecuenciaDelCierre(r, { dias_trabajados: 0, horas_marcadas: 0 }).lineas.join(" ")).toContain("quién lo decidió");
    }
  });

  it("sin horas marcadas no inventa nada: dice 0 h", () => {
    expect(consecuenciaDelCierre("retirado", { dias_trabajados: 0, horas_marcadas: 0 }).lineas[0]).toContain("0 h");
  });

  it("el aviso final dice qué pasó con el pago", () => {
    expect(mensajeDeCierre("retirado", "Mariel")).toContain("no se paga");
    expect(mensajeDeCierre("no_apto", "Mariel")).toContain("se le pagará");
  });
});

describe("las horas", () => {
  it("con coma, sin ceros que sobran", () => {
    expect(textoDeHoras(5.35)).toBe("5,35 h");
    expect(textoDeHoras(6.5)).toBe("6,5 h");
    expect(textoDeHoras(8)).toBe("8 h");
    expect(textoDeHoras(0)).toBe("0 h");
    expect(textoDeHoras(5.3499999)).toBe("5,35 h");
  });
});

describe("el motivo", () => {
  it("tres letras como mínimo, sin contar espacios — la misma regla que la base", () => {
    expect(motivoValido("")).toBe(false);
    expect(motivoValido("  ab ")).toBe(false);
    expect(motivoValido("no")).toBe(false);
    expect(motivoValido("sí, no")).toBe(true);
    expect(motivoValido("   abc   ")).toBe(true);
  });
});

describe("los cierres recientes", () => {
  const cierre = (o: Partial<CierrePrueba> = {}): CierrePrueba => ({
    prueba_id: "c1", persona_id: "x", nombres: "Deyvid", apellidos: "Gamboa", sede_codigo: "OTRU", resultado: "retirado",
    motivo: "Dijo que no volvía", decidida_por: "Ana Supervisora", cerrada_at: "2026-10-17T15:00:00Z",
    cerrada_fecha: "2026-10-16", dias_trabajados: 1, horas_marcadas: 3.79, ...o,
  });

  it("un retiro dice que quedó sin pagar; un no apto, que se paga", () => {
    expect(resumenDeCierre(cierre())).toBe("Se retiró · decidió Ana Supervisora · 1 día, 3,79 h sin pagar");
    expect(resumenDeCierre(cierre({ resultado: "no_apto", dias_trabajados: 3, horas_marcadas: 19.5 })))
      .toBe("No fue apto · decidió Ana Supervisora · 3 días, 19,5 h a pagar");
  });

  it("sin nombre de quien decidió no inventa uno", () => {
    expect(resumenDeCierre(cierre({ decidida_por: null }))).not.toContain("decidió");
  });
});

describe("nombres", () => {
  it("junta nombres y apellidos", () => {
    expect(nombreDe({ nombres: "Rufina", apellidos: "Inca" })).toBe("Rufina Inca");
  });
});

describe("la constancia de consentimiento del DNI", () => {
  it("nombra a la persona, a la empresa y la finalidad, y alcanza el mínimo que exige la base (50 letras)", () => {
    const t = textoConsentimientoDni("Mariel Sarmiento", 3);
    expect(t).toContain("Mariel Sarmiento");
    expect(t).toContain("CAYLA S.A.C.");
    expect(t).toContain("verificar su identidad");
    expect(t.trim().length).toBeGreaterThanOrEqual(50);
  });

  it("el plazo sale del argumento, no está escrito a mano", () => {
    expect(textoConsentimientoDni("A B", 5)).toContain("prueba de 5 días");
  });

  it("dice cómo ejercer los derechos de acceso, rectificación, cancelación y oposición", () => {
    expect(textoConsentimientoDni("A B", 3)).toContain("acceso, rectificación, cancelación y oposición");
  });
});
