// ============================================================================
// terminos.test.ts — los términos de «Lo mío», comprobados
// ============================================================================
// Tres cosas que no pueden depender de que alguien se acuerde:
//
//   1. COBERTURA. Cada sección de «Lo mío» tiene su decisión de términos. Si
//      mañana se agrega una sección, esta prueba se pone en rojo hasta que
//      alguien decida qué le toca —aunque sea «un aviso y nada más»—.
//   2. EL BORRADOR NO SALE. Un texto sin aprobar es invisible para la pantalla:
//      no se muestra y no bloquea nada. Salir con un texto que nadie revisó
//      dejaría una constancia firmada de algo sin validar.
//   3. LO APROBADO ESTÁ CANDADO. Quien aceptó la v1 aceptó ESA redacción. Cambiar
//      una palabra sin subir la versión es reescribir lo que dijo la constancia.
//      Para cada texto aprobado se guarda la huella de lo que dice, por versión.
//
// CÓMO SE APRUEBA UN TEXTO (lo que Desarrollo Organizacional y el laboralista
// ven en el pull request):
//   a. en `terminos.ts`: `estado: "aprobado"` y `aprobado: { por, fecha }`;
//   b. correr esta prueba: falla diciendo la huella que falta;
//   c. pegar esa huella en `HUELLAS`, abajo, bajo el módulo y su versión.
// Cambiar un texto ya aprobado: subir `version` Y agregar la huella nueva. Las
// huellas viejas NO se borran: son la historia de lo que se dijo.
// ============================================================================
import { describe, it, expect } from "vitest";
import { createHash } from "node:crypto";
import {
  TERMINOS, exigeAceptacion, hoyLima, terminosVigentes, textoAceptado,
  type TerminosModulo,
} from "@cayla-dynamic/shared";
import { TABS } from "@/lib/mio-secciones";

/** modulo → versión → huella (sha256) de `textoAceptado`. Vacío mientras todo sea borrador. */
const HUELLAS: Record<string, Record<number, string>> = {};

const huella = (t: TerminosModulo) => createHash("sha256").update(textoAceptado(t), "utf8").digest("hex");

/** Lo que está mal con los textos aprobados de un catálogo: vacío si todo está en orden. */
function revisar(
  catalogo: readonly TerminosModulo[],
  huellas: Record<string, Record<number, string>>,
): string[] {
  const problemas: string[] = [];
  for (const t of catalogo) {
    if (t.estado !== "aprobado") continue;
    if (!t.aprobado?.por || !t.aprobado?.fecha) {
      problemas.push(`${t.modulo}: está aprobado pero no dice quién lo aprobó ni cuándo`);
    }
    const actual = huella(t);
    const guardada = huellas[t.modulo]?.[t.version];
    if (guardada === undefined) {
      problemas.push(`${t.modulo} v${t.version}: falta su huella. Pega en HUELLAS: ${actual}`);
    } else if (guardada !== actual) {
      problemas.push(`${t.modulo} v${t.version}: el texto cambió sin subir la versión (huella guardada ${guardada}, actual ${actual})`);
    }
    for (let v = 1; v < t.version; v++) {
      if (huellas[t.modulo]?.[v] === undefined) problemas.push(`${t.modulo}: falta la huella de la versión ${v}, que ya existió`);
    }
  }
  return problemas;
}

const ejemplo: TerminosModulo = {
  modulo: "ejemplo", titulo: "Ejemplo", peso: "aceptacion", version: 1, estado: "aprobado",
  aprobado: { por: "Desarrollo Organizacional", fecha: "2026-10-20" },
  puntos: ["Primer punto de ejemplo.", "Segundo punto de ejemplo."],
  texto: "Un texto de ejemplo suficientemente largo para que cuente como constancia de algo.",
};

describe("cobertura: cada sección de «Lo mío» tiene su decisión", () => {
  it("hay una entrada por cada sección más «general» — ni una de más ni una de menos", () => {
    expect(TERMINOS.map((t) => t.modulo).sort()).toEqual(["general", ...TABS].sort());
  });

  it("ningún módulo está dos veces", () => {
    const nombres = TERMINOS.map((t) => t.modulo);
    expect(new Set(nombres).size).toBe(nombres.length);
  });
});

describe("la decisión de cuánto pesa cada uno (2026-10-19)", () => {
  const de = (peso: TerminosModulo["peso"]) => TERMINOS.filter((t) => t.peso === peso).map((t) => t.modulo).sort();

  it("cinco piden casilla: los términos de uso y cuatro módulos", () => {
    expect(de("aceptacion")).toEqual(["ausencias", "datos", "firma", "general", "reportes"]);
  });

  it("cuatro ya tienen su propia constancia y solo apuntan a ella", () => {
    expect(de("constancia_propia")).toEqual(["boletas", "disciplina", "dni", "movilidad"]);
  });

  it("el resto es un aviso", () => {
    expect(de("aviso")).toEqual(["contrato", "educacion", "historial", "objetivos", "resumen", "seguro", "turnos", "dias"].sort());
  });

  it("solo los que apuntan a una constancia propia dicen a cuál", () => {
    for (const t of TERMINOS) {
      if (t.peso === "constancia_propia") expect(t.apuntaA, t.modulo).toBeTruthy();
      else expect(t.apuntaA, t.modulo).toBeUndefined();
    }
  });
});

describe("la forma de cada entrada", () => {
  it("el nombre del módulo cabe en lo que la base acepta (0540: minúsculas y guion bajo)", () => {
    for (const t of TERMINOS) expect(t.modulo, t.modulo).toMatch(/^[a-z][a-z_]{1,31}$/);
  });

  it("la versión es un entero desde 1", () => {
    for (const t of TERMINOS) expect(Number.isInteger(t.version) && t.version >= 1, t.modulo).toBe(true);
  });

  it("de dos a cuatro puntos, y ninguno vacío", () => {
    for (const t of TERMINOS) {
      expect(t.puntos.length, t.modulo).toBeGreaterThanOrEqual(2);
      expect(t.puntos.length, t.modulo).toBeLessThanOrEqual(4);
      for (const p of t.puntos) expect(p.trim().length, t.modulo).toBeGreaterThan(10);
    }
  });

  it("lo que se guardaría como constancia pasa el mínimo de la base (50 caracteres)", () => {
    for (const t of TERMINOS) expect(textoAceptado(t).trim().length, t.modulo).toBeGreaterThanOrEqual(50);
  });

  it("usa el vocabulario de la casa y no lleva montos", () => {
    const prohibido = /\b(empleados?|jefes?|sucursal(es)?|RRHH|supervisor(a|es)?|encargad[oa]s?)\b/i;
    for (const t of TERMINOS) {
      const todo = textoAceptado(t);
      expect(todo, t.modulo).not.toMatch(prohibido);
      expect(todo, t.modulo).not.toMatch(/S\/\s?\d/);
    }
  });
});

describe("el borrador no sale", () => {
  it("un texto en borrador no lo devuelve `terminosVigentes`, y por tanto nada lo muestra", () => {
    for (const t of TERMINOS.filter((x) => x.estado === "borrador")) {
      expect(terminosVigentes(t.modulo), t.modulo).toBeNull();
    }
  });

  it("un borrador nunca exige aceptación, aunque pese «aceptacion»", () => {
    for (const t of TERMINOS.filter((x) => x.estado === "borrador")) {
      expect(exigeAceptacion(t.modulo), t.modulo).toBe(false);
    }
    expect(exigeAceptacion("ejemplo", [{ ...ejemplo, estado: "borrador" }])).toBe(false);
  });

  it("y un módulo que no existe tampoco devuelve nada ni exige nada", () => {
    expect(terminosVigentes("no-existe")).toBeNull();
    expect(exigeAceptacion("no-existe")).toBe(false);
  });

  it("una vez aprobado, sí sale, y exige aceptación solo si pesa «aceptacion»", () => {
    expect(terminosVigentes("ejemplo", [ejemplo])).toEqual(ejemplo);
    expect(exigeAceptacion("ejemplo", [ejemplo])).toBe(true);
    expect(exigeAceptacion("ejemplo", [{ ...ejemplo, peso: "aviso" }])).toBe(false);
    expect(exigeAceptacion("ejemplo", [{ ...ejemplo, peso: "constancia_propia", apuntaA: "x" }])).toBe(false);
  });
});

describe("lo aprobado está candado", () => {
  it("el catálogo real cumple todo: aprobados con su aprobación y su huella", () => {
    expect(revisar(TERMINOS, HUELLAS)).toEqual([]);
  });

  it("un aprobado con su huella y su aprobación pasa", () => {
    expect(revisar([ejemplo], { ejemplo: { 1: huella(ejemplo) } })).toEqual([]);
  });

  it("cambiar una palabra sin subir la versión pone la prueba en rojo", () => {
    const huellas = { ejemplo: { 1: huella(ejemplo) } };
    const tocado = { ...ejemplo, texto: ejemplo.texto + " Y una frase nueva." };
    const problemas = revisar([tocado], huellas);
    expect(problemas).toHaveLength(1);
    expect(problemas[0]).toMatch(/cambió sin subir la versión/);
  });

  it("cambiarlo SUBIENDO la versión pide la huella nueva y exige conservar la vieja", () => {
    const v2 = { ...ejemplo, version: 2, texto: ejemplo.texto + " Una frase nueva." };
    expect(revisar([v2], { ejemplo: { 1: huella(ejemplo) } })[0]).toMatch(/falta su huella/);
    expect(revisar([v2], { ejemplo: { 2: huella(v2) } })[0]).toMatch(/falta la huella de la versión 1/);
    expect(revisar([v2], { ejemplo: { 1: huella(ejemplo), 2: huella(v2) } })).toEqual([]);
  });

  it("un aprobado sin decir quién ni cuándo no pasa, aunque tenga huella", () => {
    const sinFirma = { ...ejemplo, aprobado: undefined };
    expect(revisar([sinFirma], { ejemplo: { 1: huella(sinFirma) } })[0]).toMatch(/quién lo aprobó/);
  });

  it("la huella cambia si cambia el título, un punto o el texto — no solo el texto", () => {
    const base = huella(ejemplo);
    expect(huella({ ...ejemplo, titulo: "Otro" })).not.toBe(base);
    expect(huella({ ...ejemplo, puntos: ["Primer punto de ejemplo.", "Otro."] })).not.toBe(base);
    expect(huella({ ...ejemplo, texto: ejemplo.texto + "." })).not.toBe(base);
  });

  it("la fecha de aprobación no es del futuro", () => {
    for (const t of TERMINOS.filter((x) => x.estado === "aprobado")) {
      expect(t.aprobado?.fecha ?? "", t.modulo).toMatch(/^\d{4}-\d{2}-\d{2}$/);
      expect((t.aprobado?.fecha ?? "") <= hoyLima(), t.modulo).toBe(true);
    }
  });
});
