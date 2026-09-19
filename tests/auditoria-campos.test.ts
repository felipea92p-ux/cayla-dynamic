// ============================================================================
// auditoria-campos.test.ts — el vocabulario de la auditoría contra la base
// ============================================================================
// El libro `correcciones_auditoria` lo escriben más de sesenta campos. Si una
// migración agrega uno nuevo y nadie le pone tema, Correcciones lo pinta como
// el nombre crudo de la columna. Esta prueba lee los `insert` de las
// migraciones y falla con el nombre del campo huérfano.
// ============================================================================
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import {
  CAMPOS_DE_MARCAJE, RESOLUCION_MARCA_APARTADA, esCampoDeMarcaje, rotuloDeCampo, temaDeCampo,
} from "@cayla-dynamic/shared";

const DIR = join(__dirname, "..", "supabase", "migrations");

/** Separa una lista de valores SQL por comas de primer nivel (fuera de comillas y paréntesis). */
function partirValores(s: string): string[] {
  const out: string[] = [];
  let prof = 0, comillas = false, actual = "";
  for (const c of s) {
    if (c === "'") comillas = !comillas;
    if (!comillas) {
      if (c === "(") prof++;
      else if (c === ")") prof--;
      else if (c === "," && prof === 0) { out.push(actual.trim()); actual = ""; continue; }
    }
    actual += c;
  }
  out.push(actual.trim());
  return out;
}

/** Cada literal que alguna migración escribe como `campo_modificado`. */
function camposEscritosPorLasMigraciones(): Set<string> {
  const campos = new Set<string>();
  const patron = /insert\s+into\s+(?:public\.)?correcciones_auditoria\s*\(([^)]*)\)\s*(?:values|select)\s*(.*?);/gis;
  for (const f of readdirSync(DIR).filter((n) => n.endsWith(".sql"))) {
    const sql = readFileSync(join(DIR, f), "utf8");
    for (const m of sql.matchAll(patron)) {
      const cols = m[1].split(",").map((c) => c.trim());
      const idx = cols.indexOf("campo_modificado");
      if (idx < 0) continue;
      const resto = m[2].trim().replace(/^\(/, "");
      const literal = partirValores(resto)[idx]?.match(/^'([^']*)'/);
      if (literal) campos.add(literal[1]);
    }
  }
  return campos;
}

describe("vocabulario de la auditoría", () => {
  const escritos = camposEscritosPorLasMigraciones();

  it("lee los insert de las migraciones (si esto da 0, el lector se rompió, no la base)", () => {
    expect(escritos.size).toBeGreaterThan(40);
  });

  it("todo campo que alguna migración escribe tiene tema", () => {
    const huerfanos = [...escritos].filter((c) => temaDeCampo(c) === "otro").sort();
    // Si falla: agrega el campo a CAMPOS_DE_MARCAJE o un prefijo a PREFIJOS en
    // packages/shared/src/auditoria.ts, y un rótulo si se ve en pantalla.
    expect(huerfanos).toEqual([]);
  });

  it("todo campo de marcaje declarado existe de verdad en alguna migración", () => {
    const inventados = CAMPOS_DE_MARCAJE.filter((c) => !escritos.has(c));
    expect(inventados).toEqual([]);
  });

  it("`tipo` y `auto_cierre_confirmado` son correcciones de marcaje", () => {
    // Salían como «otro sistema» con el nombre crudo de la columna.
    expect(esCampoDeMarcaje("tipo")).toBe(true);
    expect(esCampoDeMarcaje("auto_cierre_confirmado")).toBe(true);
  });

  it("un cambio de horario o de contrato no es de marcaje", () => {
    expect(temaDeCampo("horarios_asignados")).toBe("horario");
    expect(temaDeCampo("contrato_generado")).toBe("contrato");
    expect(esCampoDeMarcaje("educacion_alta")).toBe(false);
  });

  it("un campo que no conoce se lee sin guiones bajos, nunca vacío", () => {
    expect(rotuloDeCampo("campo_nuevo_de_manana")).toBe("campo nuevo de manana");
  });

  it("una marca apartada declarada improcedente NO se lee como pendiente", () => {
    expect(RESOLUCION_MARCA_APARTADA.improcedente).toMatch(/improcedente/);
    expect(RESOLUCION_MARCA_APARTADA.improcedente).not.toMatch(/pendiente/);
  });
});
