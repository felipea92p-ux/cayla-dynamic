// ============================================================================
// practicantes-piso-misma-regla.test.ts — la regla de la 0502 es UNA
// ============================================================================
// La 0502 sube a su piso legal a los practicantes que hoy cobran menos. «Quién
// sube y a cuánto» es una consulta (la vista `v0502`) y vive escrita en TRES
// archivos, porque cada uno la necesita donde está:
//
//   · la migración la ejecuta;
//   · la prueba pgTAP 396 la mide sobre practicantes de laboratorio;
//   · el script de comprobación se la muestra a Felipe ANTES de pegar, persona
//     por persona, y es lo que él lee para confirmar la suposición «jornada
//     completa» de quien no tiene horas pactadas en un convenio.
//
// El riesgo no es que la regla esté mal escrita: es que las tres copias se
// separen. Si el script dijera «SUBE a 820» y la migración subiera a 1,230,
// Felipe habría confirmado una cosa y el sistema habría hecho otra —y subirle de
// más a quien trabaja menos no se puede deshacer—. Esto las compara, palabra por
// palabra (sin contar espacios ni líneas en blanco), entre los marcadores
// `-- >>> REGLA 0502` y `-- <<< REGLA 0502`.
//
// No prueba que la regla sea CORRECTA: eso lo hace la 396. Prueba que la que se
// ejecuta es la misma que se midió y la que se leyó.
// ============================================================================
import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

const RAIZ = path.resolve(import.meta.dirname, "..");
const ARCHIVOS = {
  migracion: "supabase/migrations/0502_los_practicantes_llegan_al_piso_de_1230.sql",
  prueba: "supabase/tests/396_los_practicantes_llegan_al_piso_de_1230.test.sql",
  script: "scripts/sql-manual/antes_de_pegar_los_practicantes_1230.sql",
} as const;

const ABRE = "-- >>> REGLA 0502";
const CIERRA = "-- <<< REGLA 0502";

function leer(ruta: string): string {
  // \r\n → \n: un archivo pegado desde Windows no debe romper la comparación.
  return readFileSync(path.join(RAIZ, ruta), "utf8").replace(/\r\n/g, "\n");
}

/** Las líneas entre los marcadores, sin sangrías ni líneas en blanco. */
function laRegla(sql: string): string[] {
  const lineas = sql.split("\n").map((l) => l.trim());
  const abre = lineas.reduce<number[]>((a, l, i) => (l === ABRE ? [...a, i] : a), []);
  const cierra = lineas.reduce<number[]>((a, l, i) => (l === CIERRA ? [...a, i] : a), []);
  expect(abre.length, `debe haber UN marcador «${ABRE}»`).toBe(1);
  expect(cierra.length, `debe haber UN marcador «${CIERRA}»`).toBe(1);
  expect(cierra[0]).toBeGreaterThan(abre[0]);
  return lineas.slice(abre[0] + 1, cierra[0]).filter((l) => l !== "");
}

describe("la regla de la 0502: la que se ejecuta es la que se midió y la que se leyó", () => {
  const regla = {
    migracion: laRegla(leer(ARCHIVOS.migracion)),
    prueba: laRegla(leer(ARCHIVOS.prueba)),
    script: laRegla(leer(ARCHIVOS.script)),
  };

  it("la migración, la prueba 396 y el script llevan la MISMA regla", () => {
    expect(regla.prueba).toEqual(regla.migracion);
    expect(regla.script).toEqual(regla.migracion);
  });

  it("y no es una regla vacía: trae lo que la distingue", () => {
    const texto = regla.migracion.join("\n");
    for (const pieza of [
      "convenio_practicas", // de dónde salen las horas pactadas
      "anulado_at is null", // el anulado no cuenta
      "parametros_laborales", // la RMV se LEE, no se escribe a mano
      "least(b.horas, 30) / 30", // el piso proporcional del preprofesional
      "'sube'",
      "'cumple_jornada_reducida'",
      "'omitida_ingreso_posterior'",
      "cuenta_de_servicio",
    ]) {
      expect(texto, `falta «${pieza}»`).toContain(pieza);
    }
  });
});

describe("la 0502 y su script no llevan datos personales", () => {
  // CLAUDE.md: «Datos personales fuera de git». Un id de persona o un nombre
  // escrito acá, en una migración que alguien pega en producción, es justo lo que
  // se promete no hacer. La prueba 396 SÍ lleva ids, pero son de laboratorio y
  // no se miran.
  const UUID = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i;

  it.each([ARCHIVOS.migracion, ARCHIVOS.script])("%s no trae ningún uuid", (ruta) => {
    expect(leer(ruta)).not.toMatch(UUID);
  });
});
