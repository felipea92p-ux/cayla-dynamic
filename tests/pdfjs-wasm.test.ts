import { describe, it, expect } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";

/**
 * Los decodificadores `wasm` de pdf.js viven copiados en `apps/web/public/pdfjs/wasm/`.
 *
 * SIN ellos, un PDF escaneado en blanco y negro (JBIG2, CCITT) o con JPEG 2000 sale EN BLANCO en el
 * visor de constancias, sin ningún error: justo lo que es una constancia escaneada en el banco. Se
 * midió el 2026-10-16 con un PDF de prueba JPEG 2000 (hoja en blanco antes de copiarlos).
 *
 * Esta prueba existe por lo que pasa el día que alguien sube `pdfjs-dist` y no vuelve a copiarlos:
 * el `wasm` tiene que ser de la MISMA versión que la librería, y si no coincide, el escaneo sale en
 * blanco otra vez sin que nada falle. Aquí sí falla, en CI, antes de publicar.
 *
 * Si falla: `cp apps/web/node_modules/pdfjs-dist/wasm/{jbig2,openjpeg,qcms_bg}.wasm apps/web/public/pdfjs/wasm/`
 */
const raiz = path.resolve(import.meta.dirname, "..");
const copiados = path.join(raiz, "apps/web/public/pdfjs/wasm");
const instalados = path.join(raiz, "apps/web/node_modules/pdfjs-dist/wasm");

describe("decodificadores wasm de pdf.js", () => {
  it("están los tres que pdf.js pide para escaneos", () => {
    const wasm = readdirSync(copiados).filter((f) => f.endsWith(".wasm")).sort();
    expect(wasm).toEqual(["jbig2.wasm", "openjpeg.wasm", "qcms_bg.wasm"]);
  });

  it("son, byte por byte, los de la versión instalada de pdfjs-dist", () => {
    for (const f of ["jbig2.wasm", "openjpeg.wasm", "qcms_bg.wasm"]) {
      const copia = readFileSync(path.join(copiados, f));
      const original = readFileSync(path.join(instalados, f));
      expect(copia.equals(original), `${f} no coincide con node_modules/pdfjs-dist/wasm`).toBe(true);
    }
  });

  it("abrirPdf le dice a pdf.js dónde están", () => {
    const fuente = readFileSync(path.join(raiz, "apps/web/lib/admin/constancia-medios.ts"), "utf8");
    expect(fuente).toMatch(/getDocument\(\{[^}]*wasmUrl/);
  });
});
