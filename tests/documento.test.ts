// ============================================================================
// documento.test.ts — la regla del documento, y que la pantalla y la base
// digan lo mismo (0513)
// ============================================================================
// La regla vive dos veces a propósito: en `packages/shared/src/documento.ts`
// para avisar ANTES de escribir, y en `fn_documento_forma_valida` (0513) porque
// la base es la que manda. Dos copias de una regla se separan solas con el
// tiempo, así que la segunda mitad de este archivo lee la migración y exige que
// sus tres patrones sean los mismos que los de la pantalla.
// ============================================================================
import { describe, expect, it } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";
import {
  FORMA_DOCUMENTO, TIPOS_DOCUMENTO, errorDeDocumento, normalizarDocumento,
} from "@cayla-dynamic/shared";

describe("errorDeDocumento — la forma de cada tipo", () => {
  it("DNI: exactamente 8 dígitos, con el cero adelante", () => {
    expect(errorDeDocumento("dni", "01234567")).toBeNull();
    expect(errorDeDocumento("dni", "1234567")).toMatch(/8 dígitos/);
    expect(errorDeDocumento("dni", "123456789")).toMatch(/8 dígitos/);
    expect(errorDeDocumento("dni", "1234567A")).toMatch(/8 dígitos/);
  });
  it("carné de extranjería: de 9 a 12, letras o números", () => {
    expect(errorDeDocumento("ce", "001234567")).toBeNull();
    expect(errorDeDocumento("ce", "AB1234567890")).toBeNull();
    expect(errorDeDocumento("ce", "12345678")).toMatch(/9 a 12/);
    expect(errorDeDocumento("ce", "1234567890123")).toMatch(/9 a 12/);
  });
  it("pasaporte / PTP: de 6 a 12, letras o números", () => {
    expect(errorDeDocumento("pasaporte", "AB1234")).toBeNull();
    expect(errorDeDocumento("pasaporte", "ab-123 456")).toBeNull();   // se normaliza antes de medir
    expect(errorDeDocumento("pasaporte", "AB123")).toMatch(/6 a 12/);
  });
  it("sin tipo o sin número, dice qué falta", () => {
    expect(errorDeDocumento("", "12345678")).toMatch(/tipo/);
    expect(errorDeDocumento("dni", "   ")).toMatch(/Falta el número/);
  });
});

describe("normalizarDocumento — como lo guarda la base", () => {
  it("sin espacios, puntos ni guiones, y en mayúsculas", () => {
    expect(normalizarDocumento(" 4070-0010 ")).toBe("40700010");
    expect(normalizarDocumento("ab-123 456")).toBe("AB123456");
    expect(normalizarDocumento("12.345.678")).toBe("12345678");
  });
});

describe("la pantalla y la base dicen lo mismo", () => {
  const dir = path.join(__dirname, "..", "supabase", "migrations");
  // La versión vigente de la regla es la ÚLTIMA migración que la define.
  const migraciones = readdirSync(dir).filter((f) => f.endsWith(".sql")).sort();
  const definiciones = migraciones.filter((f) =>
    /function\s+(public\.)?fn_documento_forma_valida\s*\(/i.test(readFileSync(path.join(dir, f), "utf8")));
  const vigente = definiciones.at(-1);

  it("existe una migración que define la regla", () => {
    expect(vigente).toBeDefined();
  });

  for (const tipo of TIPOS_DOCUMENTO) {
    it(`el patrón de «${tipo}» es el mismo en la base`, () => {
      const sql = readFileSync(path.join(dir, vigente as string), "utf8");
      const m = sql.match(new RegExp(`when '${tipo}'\\s+then p_numero ~ '([^']+)'`));
      expect(m, `la ${vigente} no tiene la rama de «${tipo}»`).not.toBeNull();
      expect(m![1]).toBe(FORMA_DOCUMENTO[tipo].source);
    });
  }

  it("el comparador detecta una diferencia (se prueba con un caso que DEBE fallar)", () => {
    const sqlFalso = "when 'dni' then p_numero ~ '^[0-9]{7}$'";
    const m = sqlFalso.match(/when 'dni'\s+then p_numero ~ '([^']+)'/);
    expect(m![1]).not.toBe(FORMA_DOCUMENTO.dni.source);
  });
});
