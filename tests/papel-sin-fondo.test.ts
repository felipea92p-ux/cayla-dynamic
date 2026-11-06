// ============================================================================
// papel-sin-fondo.test.ts — El fondo crema de la pantalla no llega al papel
// ============================================================================
// `globals.css` pone `print-color-adjust: exact` en el `body` para que los
// acentos de un documento salgan siempre. Eso se hereda: cualquier contenedor
// con fondo también se imprime, aunque quien imprime tenga «gráficos de fondo»
// apagado. `background: #fff` en el `body` no lo tapa, porque un contenedor de
// adentro pinta encima.
//
// Medido el 2026-11-06 en PDF A4: el certificado de trabajo salía con 73.6 % de
// la página en crema, y seguía igual aunque se le quitara el fondo a la tarjeta
// de la vista previa, porque el marco del panel pintaba el mismo crema por
// debajo. Las dos capas tienen que irse juntas, y por eso se vigilan juntas.
// Lo vigilado es el código fuente: las pruebas no abren un navegador.
// ============================================================================
import { describe, expect, it } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";

const RAIZ = path.resolve(__dirname, "..");
const WEB = path.join(RAIZ, "apps/web");

function archivosTsx(dir: string): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    if (e.name === "node_modules" || e.name === ".next") return [];
    const ruta = path.join(dir, e.name);
    if (e.isDirectory()) return archivosTsx(ruta);
    return e.name.endsWith(".tsx") ? [ruta] : [];
  });
}

const clasesDe = (fuente: string) => [...fuente.matchAll(/className="([^"]*)"/g)].map((m) => m[1]);
const tieneClase = (clases: string, nombre: string) => clases.split(/\s+/).includes(nombre);

describe("el papel sale sobre blanco", () => {
  it("el marco del panel no pinta su crema al imprimir: está detrás de todos los papeles del panel", () => {
    const fuente = readFileSync(path.join(WEB, "app/(admin)/layout.tsx"), "utf8");
    const marco = clasesDe(fuente).filter((c) => tieneClase(c, "bg-crema"));
    expect(marco.length).toBeGreaterThan(0);
    for (const clases of marco) expect(tieneClase(clases, "print:bg-transparent")).toBe(true);
  });

  it("una vista previa que se imprime tampoco: la tarjeta que se suelta al imprimir suelta también su fondo", () => {
    // `print:max-h-none` es lo que hace que una tarjeta de vista previa se quede en el papel con todo su alto.
    const faltan: string[] = [];
    let vistasPrevias = 0;
    for (const archivo of [...archivosTsx(path.join(WEB, "app")), ...archivosTsx(path.join(WEB, "components"))]) {
      for (const clases of clasesDe(readFileSync(archivo, "utf8"))) {
        if (!tieneClase(clases, "print:max-h-none") || !tieneClase(clases, "bg-crema")) continue;
        vistasPrevias++;
        if (!tieneClase(clases, "print:bg-transparent")) faltan.push(path.relative(RAIZ, archivo));
      }
    }
    // Liquidaciones, Contratos y los dos visores de Documentación. Si un día son cero, esta prueba ya no vigila nada.
    expect(vistasPrevias).toBeGreaterThanOrEqual(4);
    expect(faltan).toEqual([]);
  });
});
