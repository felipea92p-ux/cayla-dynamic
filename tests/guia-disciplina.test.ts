// «Cómo funciona la disciplina», la guía de Info (lib/guia-disciplina.ts).
//
// Lo que importa acá, en este orden:
//   1. Que cada cita «RIT 19.2» apunte a un numeral que EXISTE en el Reglamento
//      del repositorio. Una cita equivocada en un texto para colaboradoras es
//      peor que ninguna: manda a leer otra regla.
//   2. Que si el Reglamento del repositorio sube de versión, esta prueba se
//      ponga en rojo hasta que alguien revise la guía. Es lo que evita que la
//      guía envejezca en silencio (el defecto con el que nació como artefacto).
//   3. Que la pantalla no afirme «al día» ni «desactualizada» sin dato.
//   4. Que el vocabulario sea el de la casa.

import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import {
  CARGOS, EJEMPLOS_DE_PLAZO, GUIA_REVISADA, INASISTENCIAS, REGLAMENTO_RESUMIDO, TARDANZAS, citasDe, estadoDeLaGuia,
  normalizarEtiqueta, tiraDePlazo, todosLosTextos, trozos,
} from "@/lib/guia-disciplina";

const RAIZ = path.resolve(import.meta.dirname, "..");
const RIT = readFileSync(path.join(RAIZ, "docs/reglamento-interno-de-trabajo.md"), "utf8");
const escapar = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/** ¿Existe este numeral («19.2») o artículo («22») en el texto del Reglamento? */
function existeEnElReglamento(cita: string): boolean {
  if (/^\d+$/.test(cita)) return new RegExp(`^### ARTÍCULO ${cita}\\.-`, "m").test(RIT);
  // Los numerales se escriben «**19.2. Gradación.**» o «**2.5.** Locadoras…»: los dos empiezan igual.
  return new RegExp(`\\*\\*${escapar(cita)}\\.`).test(RIT);
}

describe("las citas al Reglamento", () => {
  const citas = [...new Set(todosLosTextos().flatMap(citasDe))].sort();

  it("hay citas que revisar (si esto da cero, la prueba no está mirando nada)", () => {
    expect(citas.length).toBeGreaterThan(40);
  });

  it.each(citas)("RIT %s existe en docs/reglamento-interno-de-trabajo.md", (cita) => {
    expect(existeEnElReglamento(cita)).toBe(true);
  });

  it("el control sí rechaza un numeral que no existe", () => {
    expect(existeEnElReglamento("19.9")).toBe(false);
    expect(existeEnElReglamento("99")).toBe(false);
    expect(existeEnElReglamento("19.2")).toBe(true);
  });

  it("ninguna cita quedó mal escrita (sin «RIT», sin letras sueltas)", () => {
    for (const c of citas) expect(c).toMatch(/^\d+(\.\d+)?$/);
  });
});

describe("la versión que resume", () => {
  it("es la misma que declara el Reglamento del repositorio: si este sube de versión, hay que revisar la guía", () => {
    const declarada = RIT.match(/\*\*Versión ([0-9.]+)\*\*/)?.[1];
    expect(declarada).toBe(REGLAMENTO_RESUMIDO.etiqueta);
  });

  it("y su fecha de vigencia coincide con la del Reglamento", () => {
    expect(RIT).toMatch(/Entra en vigencia el 10 de agosto de 2026/);
    expect(REGLAMENTO_RESUMIDO.vigenteDesde).toBe("2026-08-10");
  });
});

describe("¿está al día con el Reglamento vigente?", () => {
  it("normaliza cómo puede venir escrita la etiqueta", () => {
    expect(normalizarEtiqueta("4.0")).toBe("4.0");
    expect(normalizarEtiqueta(" v4.0 ")).toBe("4.0");
    expect(normalizarEtiqueta("Versión 4.0")).toBe("4.0");
    expect(normalizarEtiqueta("4")).toBe("4.0");
    expect(normalizarEtiqueta("")).toBeNull();
    expect(normalizarEtiqueta("   ")).toBeNull();
    expect(normalizarEtiqueta(null)).toBeNull();
  });

  it("al día cuando el vigente es la misma versión", () => {
    expect(estadoDeLaGuia({ etiqueta_version: "4.0", vigente_desde: "2026-08-10" })).toEqual({ clase: "al_dia", vigente: "4.0" });
  });

  it("desactualizada cuando el vigente es otra versión", () => {
    expect(estadoDeLaGuia({ etiqueta_version: "4.1", vigente_desde: "2027-01-15" }))
      .toEqual({ clase: "desactualizada", vigente: "4.1", desde: "2027-01-15" });
  });

  it("la etiqueta manda sobre la fecha: la misma 4.0 republicada sigue al día", () => {
    expect(estadoDeLaGuia({ etiqueta_version: "4.0", vigente_desde: "2026-11-20" })).toEqual({ clase: "al_dia", vigente: "4.0" });
  });

  it("PRODUCCIÓN, medido el 2026-11-09: sin etiqueta y cargado el 11 de agosto → al día, no «desactualizada»", () => {
    // La primera versión comparaba esta fecha con el 10 de agosto que declara el texto y avisaba a todo el equipo.
    expect(estadoDeLaGuia({ etiqueta_version: null, vigente_desde: "2026-08-11" })).toEqual({ clase: "al_dia", vigente: null });
  });

  it("sin etiqueta, avisa solo si se publicó un Reglamento después de la última revisión de la guía", () => {
    expect(estadoDeLaGuia({ etiqueta_version: "", vigente_desde: GUIA_REVISADA })).toEqual({ clase: "al_dia", vigente: null });
    expect(estadoDeLaGuia({ etiqueta_version: null, vigente_desde: "2026-11-20" }))
      .toEqual({ clase: "desactualizada", vigente: null, desde: "2026-11-20" });
    // Un timestamptz también sirve: se mira solo el día.
    expect(estadoDeLaGuia({ etiqueta_version: null, vigente_desde: "2027-01-15T05:00:00+00:00" }))
      .toEqual({ clase: "desactualizada", vigente: null, desde: "2027-01-15" });
  });

  it("la fecha de revisión tiene forma de fecha, para que la comparación como texto sea una comparación de fechas", () => {
    expect(GUIA_REVISADA).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });

  it("sin ningún dato no afirma nada: ni al día ni vieja", () => {
    expect(estadoDeLaGuia(null)).toEqual({ clase: "sin_saber" });
    expect(estadoDeLaGuia({ etiqueta_version: null })).toEqual({ clase: "sin_saber" });
    expect(estadoDeLaGuia({ etiqueta_version: null, vigente_desde: null })).toEqual({ clase: "sin_saber" });
  });
});

describe("la tira de días hábiles", () => {
  const forma = (inicio: number) => tiraDePlazo(inicio).map((c) => `${c.dia}:${c.clase}`);

  it("lunes → vence el miércoles", () => {
    expect(forma(1)).toEqual(["Lun:inicio", "Mar:habil", "Mié:vence"]);
  });
  it("jueves → salta el fin de semana y vence el lunes", () => {
    expect(forma(4)).toEqual(["Jue:inicio", "Vie:habil", "Sáb:fuera", "Dom:fuera", "Lun:vence"]);
  });
  it("viernes → vence el martes", () => {
    expect(forma(5)).toEqual(["Vie:inicio", "Sáb:fuera", "Dom:fuera", "Lun:habil", "Mar:vence"]);
  });
  it("sábado (Trujillo trabaja) → vence el martes, como en fn_sumar_dias_habiles", () => {
    expect(forma(6)).toEqual(["Sáb:inicio", "Dom:fuera", "Lun:habil", "Mar:vence"]);
  });
  it("los ejemplos que se dibujan terminan siempre en «vence»", () => {
    for (const e of EJEMPLOS_DE_PLAZO) expect(tiraDePlazo(e.inicio).at(-1)?.clase).toBe("vence");
  });
});

describe("las marcas del texto", () => {
  it("separa negrita y cita", () => {
    expect(trozos("Hola **tú** y [[19.2 · 57.10]].")).toEqual([
      { tipo: "texto", valor: "Hola " }, { tipo: "negrita", valor: "tú" },
      { tipo: "texto", valor: " y " }, { tipo: "ref", valor: "19.2 · 57.10" }, { tipo: "texto", valor: "." },
    ]);
    expect(citasDe("x [[19.2 · 57.10]] y [[22]]")).toEqual(["19.2", "57.10", "22"]);
  });
  it("una marca sin cerrar queda como texto", () => {
    expect(trozos("a **b")).toEqual([{ tipo: "texto", valor: "a **b" }]);
  });
  it("ningún texto deja una marca a medio cerrar", () => {
    for (const t of todosLosTextos()) {
      const sinMarcas = trozos(t).filter((x) => x.tipo === "texto").map((x) => x.valor).join("");
      expect(sinMarcas).not.toMatch(/\*\*|\[\[|\]\]/);
    }
  });
});

describe("el contenido", () => {
  it("la escalera de tardanzas tiene sus cinco peldaños, de 0 a 4", () => {
    expect(TARDANZAS.escalera.map((e) => e.n)).toEqual([0, 1, 2, 3, 4]);
  });
  it("la de inasistencias tiene tres, de 1 a 3", () => {
    expect(INASISTENCIAS.escalera.map((e) => e.n)).toEqual([1, 2, 3]);
  });
  it("los pasos de los cargos son siete", () => {
    expect(CARGOS.pasos).toHaveLength(7);
  });
  it("respeta el vocabulario de la casa", () => {
    for (const t of todosLosTextos()) {
      expect(t).not.toMatch(/\b(emplead[oa]s?|jef[ea]s?|supervisor[ae]?s?|sucursal(es)?|rrhh|encargad[oa]s?)\b/i);
      // «clienta» para quien compra; «cliente» no aparece.
      expect(t).not.toMatch(/\bclientes?\b/i);
    }
  });
  it("nunca habla como si el sistema sancionara", () => {
    for (const t of todosLosTextos()) expect(t).not.toMatch(/te corresponde|se te sanciona autom|el sistema (te )?sanciona/i);
  });
});
