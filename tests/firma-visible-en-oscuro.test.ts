import { describe, expect, it } from "vitest";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";

// Una firma es tinta oscura sobre fondo transparente: en modo oscuro da 1.00:1 y desaparece (medido en el memo real
// el 2026-11-05). Esta prueba cuida que ninguna imagen de firma nazca sin su recuadro y que el recuadro no salga al papel.

const WEB = join(import.meta.dirname, "..", "apps", "web");

function tsx(dir: string): string[] {
  return readdirSync(dir).flatMap((nombre) => {
    const ruta = join(dir, nombre);
    if (statSync(ruta).isDirectory()) return nombre === "node_modules" || nombre === ".next" ? [] : tsx(ruta);
    return ruta.endsWith(".tsx") ? [ruta] : [];
  });
}

// Estas ya pintan su propio papel claro alrededor de la firma; no necesitan la clase.
const CON_PAPEL_PROPIO = new Set([
  "components/boletas/constancia-de-firma.tsx", // recuadro de --color-crema-fija
  "components/boletas/modal-firmar-boleta.tsx", // recuadro de --color-crema-fija
  "components/boletas/hoja-constancia-boleta.tsx", // recuadro de --color-crema-fija
  "app/(admin)/admin/personas/[id]/FirmaEditor.tsx", // vista previa en bg-white: simula el papel del memo
]);

const css = readFileSync(join(WEB, "app", "globals.css"), "utf8");

describe("la firma se ve en modo oscuro", () => {
  it("toda imagen de una firma lleva firma-tinta", () => {
    const sueltas: string[] = [];
    for (const ruta of [...tsx(join(WEB, "app")), ...tsx(join(WEB, "components"))]) {
      const nombre = relative(WEB, ruta);
      if (CON_PAPEL_PROPIO.has(nombre)) continue;
      readFileSync(ruta, "utf8").split("\n").forEach((linea, i) => {
        const esFirma = /<img\b/.test(linea) && /firma|imagen\b/i.test(linea);
        if (esFirma && !linea.includes("firma-tinta") && !linea.includes("${")) sueltas.push(`${nombre}:${i + 1}`);
      });
    }
    expect(sueltas).toEqual([]);
  });

  it("el recuadro existe en los dos bloques de oscuro y usa el color que no cambia con el tema", () => {
    const veces = css.match(/--firma-fondo: var\(--color-crema-fija\);/g) ?? [];
    expect(veces).toHaveLength(2);
  });

  it("en claro no pinta nada: la variable no está definida fuera de oscuro y su respaldo es transparente", () => {
    expect(css).toMatch(/background: var\(--firma-fondo, transparent\);/);
    const tema = css.slice(css.indexOf("@theme"), css.indexOf("/* ── Modo oscuro"));
    expect(tema).not.toContain("--firma-fondo");
  });

  it("al imprimir se apaga: en el papel, la firma va directo sobre la hoja", () => {
    const impresion = css.slice(css.indexOf("@media print"));
    expect(impresion).toContain("--firma-fondo: transparent;");
  });

  it("la firma del contrato, que se guarda como HTML, también entra por su selector", () => {
    expect(css).toMatch(/\.firma-tinta,\s*\.contrato \.linea img \{/);
  });
});
