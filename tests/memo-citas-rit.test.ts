import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";

// Lo que el memo disciplinario cita del Reglamento Interno de Trabajo tiene que
// existir en el Reglamento, y decir lo que el memo cree que dice.
//
// POR QUÉ ESTE ARCHIVO. El RIT v4.0 (15-ago-2026) renumeró el articulado entero.
// Ese día se tradujeron las citas del memo —la tabla está en
// `admin/disciplina/memo/[id]/page.tsx`—, pero dos se quedaron en la v3: la
// amonestación por tardanzas invocaba el «artículo 7» (hoy PERIODO DE PRUEBA) y
// la de inasistencias el «8.3-b» (hoy contratos sujetos a modalidad). Lo vio
// una auditoría el 13-sep, se reconfirmó el 19-sep, y se siguió imprimiendo
// hasta el 6-oct. Es el papel que se le entrega a una persona, y el RIT 55.3
// exige la norma infringida con su numeral y su literal: quien abra el
// Reglamento por donde el memo le dice encuentra otra materia.
//
// QUÉ COMPRUEBA. Tres cosas que se pueden equivocar sin que nada falle:
//   1. que cada «numeral NN.N» citado exista en el RIT;
//   2. que cada «literal x) del numeral NN.N» exista DENTRO de ese numeral;
//   3. que cada «artículo N del RIT» citado sea uno que alguien revisó a mano
//      (`ARTICULOS_REVISADOS`, con su título). Existir no basta: el artículo 7
//      existe, y es justamente el que estaba mal.
// Y prohíbe la notación de la v3 («8.3-b»), que la v4 no usa en ningún lado.
//
// Si mañana sale una v5, esta prueba falla en cuanto se actualice
// `docs/reglamento-interno-de-trabajo.md` — que es exactamente cuándo tiene que
// fallar: antes de emitir nada con la numeración vieja.

const RAIZ = join(import.meta.dirname, "..");
const MEMO = readFileSync(join(RAIZ, "apps/web/components/disciplina/memo-documento.tsx"), "utf8");
const RIT = readFileSync(join(RAIZ, "docs/reglamento-interno-de-trabajo.md"), "utf8");

/**
 * Los artículos que el memo cita por número de artículo, y no por numeral, con
 * el título que tienen en el RIT. Agregar uno aquí es afirmar «lo leí y es lo
 * que quiero citar»; la prueba comprueba que el título siga siendo ese.
 */
const ARTICULOS_REVISADOS: Record<string, string> = {
  "20": "INASISTENCIAS", // «contraviene el deber de asistencia (artículo 20 del RIT)»
};

/** El texto de un numeral del RIT, desde «**19.2. » hasta el siguiente numeral o artículo. */
function textoDelNumeral(n: string): string | null {
  const marca = `**${n}. `;
  const inicio = RIT.indexOf(marca);
  if (inicio < 0) return null;
  const resto = RIT.slice(inicio + marca.length);
  const fin = resto.search(/\n\*\*\d+(?:-[A-Z])?\.\d+\. |\n### /);
  return fin < 0 ? resto : resto.slice(0, fin);
}

/** Lo que está mal citado en un texto, dicho de forma que se entienda al leer el fallo. */
function citasRotas(texto: string): string[] {
  const rotas: string[] = [];

  for (const [, n] of texto.matchAll(/numeral (\d+\.\d+)/g)) {
    if (textoDelNumeral(n) === null) rotas.push(`el numeral ${n} no existe en el RIT`);
  }

  for (const [, literal, n] of texto.matchAll(/literal ([a-z])\) del numeral (\d+\.\d+)/g)) {
    const cuerpo = textoDelNumeral(n);
    if (cuerpo !== null && !new RegExp(`(^|\\n)(\\*\\*)?${literal}\\) `).test(cuerpo)) {
      rotas.push(`el numeral ${n} no tiene literal ${literal})`);
    }
  }

  for (const [, art] of texto.matchAll(/artículo (\S+?) del (?:RIT|Reglamento)/g)) {
    const titulo = ARTICULOS_REVISADOS[art];
    if (!titulo) {
      rotas.push(`cita el artículo ${art} del RIT sin que nadie lo haya revisado (agrégalo a ARTICULOS_REVISADOS con su título)`);
    } else if (!RIT.includes(`### ARTÍCULO ${art}.- ${titulo}`)) {
      rotas.push(`el artículo ${art} del RIT ya no se titula «${titulo}»`);
    }
  }

  for (const [cita] of texto.matchAll(/\b\d+\.\d+-[a-z]\b/g)) {
    rotas.push(`«${cita}» es notación del RIT v3`);
  }

  return rotas;
}

describe("las citas del memo disciplinario", () => {
  it("existen en el RIT vigente y dicen lo que el memo cree", () => {
    expect(citasRotas(MEMO)).toEqual([]);
  });

  it("el memo cita al menos los numerales que el RIT 55.3 le exige", () => {
    // Si alguien borra las citas en vez de corregirlas, la prueba de arriba
    // pasaría en verde. Estas son las que no pueden faltar.
    for (const cita of [
      "literal b) del numeral 19.2", // umbral de la amonestación por tardanzas
      "literal b) del numeral 53.2", // las tardanzas reiteradas como falta
      "literal c) del numeral 53.2", // la inasistencia injustificada como falta
      "literal b) del numeral 21.2", // lo que viene tras la amonestación por inasistencias
      "numeral 56.1",                // vigencia de doce meses del antecedente
    ]) {
      expect(MEMO).toContain(cita);
    }
  });
});

describe("el freno caza lo que tiene que cazar", () => {
  // Las dos frases exactas que se imprimieron desde el 15-ago hasta el 6-oct.
  // Si el freno no las ve, no protege de nada.
  it("el «artículo 7» de la v3, que en la v4 es el periodo de prueba", () => {
    expect(citasRotas("superando el umbral b) del artículo 7 del Reglamento Interno de Trabajo")).toEqual([
      "cita el artículo 7 del RIT sin que nadie lo haya revisado (agrégalo a ARTICULOS_REVISADOS con su título)",
    ]);
  });

  it("el «8.3-b» de la v3", () => {
    expect(citasRotas("dará lugar a suspensión sin goce de haber (artículo 8.3-b)")).toEqual([
      "«8.3-b» es notación del RIT v3",
    ]);
  });

  it("un numeral que no existe y un literal que no está en su numeral", () => {
    expect(citasRotas("conforme al numeral 99.9 y al literal z) del numeral 19.2")).toEqual([
      "el numeral 99.9 no existe en el RIT",
      "el numeral 19.2 no tiene literal z)",
    ]);
  });
});
