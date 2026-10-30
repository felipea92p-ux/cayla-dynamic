// ============================================================================
// cabecera-misma-altura.test.ts — el sobretítulo de cada pantalla arranca a la misma altura
// ============================================================================
// El 2026-10-19 se vio que el «ASISTENCIA · LUNES…» de Incidencias, Correcciones y Turnos no coincidía: Correcciones
// arrancaba 4 px más arriba (`pt-5`), el Dashboard 8 px más abajo (`sm:p-8`) y Política salarial otros 8 (`py-8`). Al
// cambiar de pantalla el título «saltaba», y nadie lo había escrito como regla: cada pantalla traía su relleno.
//
// La regla: lo que envuelve a <CabeceraPagina> deja 24 px arriba (`p-6` o `pt-6`). Esta prueba lee el código —no hay
// navegador en juego, y exige la clase SIN prefijo de ancho (`sm:p-6` no basta: en celular arrancaría a otra altura)— y falla con el nombre de la pantalla que se salga.
// ============================================================================
import { readdirSync, readFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const RAIZ = join(__dirname, "../apps/web/app/(admin)/admin");
const RELLENO = /\b(?:p|pt|py)-\d+\b/;

function envolvente(src: string): string | null {
  const i = src.indexOf("<CabeceraPagina");
  if (i < 0) return null;
  // 1) el contenedor inmediato (los 300 caracteres anteriores) si lleva relleno propio…
  const antes = src.slice(Math.max(0, i - 300), i);
  const clases = [...antes.matchAll(/className="([^"]*)"/g)].map((m) => m[1]);
  const ultima = clases[clases.length - 1];
  if (ultima && RELLENO.test(ultima)) return ultima;
  // 2) …y si no, el último <main> que lo precede.
  const mains = [...src.slice(0, i).matchAll(/<main\s+className="([^"]*)"/g)].map((m) => m[1]);
  return mains.length ? mains[mains.length - 1] : null;
}

describe("la cabecera de cada pantalla arranca a la misma altura", () => {
  const pantallas = readdirSync(RAIZ, { withFileTypes: true })
    .filter((d) => d.isDirectory() && existsSync(join(RAIZ, d.name, "page.tsx")))
    .map((d) => ({ nombre: d.name, src: readFileSync(join(RAIZ, d.name, "page.tsx"), "utf8") }))
    .filter((p) => p.src.includes("<CabeceraPagina"));

  it("hay pantallas que revisar", () => {
    expect(pantallas.length).toBeGreaterThan(10);
  });

  for (const p of pantallas) {
    it(`${p.nombre}: 24 px arriba (p-6 o pt-6)`, () => {
      const clases = envolvente(p.src);
      expect(clases, `${p.nombre}: no se encontró el contenedor de la cabecera`).not.toBeNull();
      expect(clases, `${p.nombre}: el contenedor de la cabecera es «${clases}»`).toMatch(/(?<![:\w-])(?:p-6|pt-6)(?![\w-])/);
    });
  }
});
