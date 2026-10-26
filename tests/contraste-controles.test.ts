// ============================================================================
// contraste-controles.test.ts — el borde de un control y el texto de un error se leen
// ============================================================================
// El 2026-10-25 se midió que el borde de Campo, CampoSelect, AreaTexto y Boton «secundario» era `sand`
// (1.2:1 sobre crema/papel, contra el 3:1 que WCAG 1.4.11 pide para lo que identifica un control) y que el
// mensaje de error en `rojo` plano daba 4.28:1 sobre papel en modo oscuro (AA pide 4.5:1 en texto de 12 px). El
// alias `borde-control` existía desde el 2026-09-06 en globals.css y nadie lo pedía.
//
// Esta prueba lee dos cosas, sin navegador:
//   1. los valores de los tokens en globals.css (claro y oscuro) y calcula el contraste con la fórmula de WCAG;
//   2. que los componentes pidan esos tokens —y no los de antes—.
// Si alguien retona `taupe` o `rojo-profundo` y el par deja de cumplir, o si un control vuelve a `border-sand`,
// falla con el nombre del par o del archivo.
// ============================================================================
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const RAIZ = join(__dirname, "..");
const css = readFileSync(join(RAIZ, "apps/web/app/globals.css"), "utf8"); // con comentarios: aquí se leen valores, no clases
// Sin comentarios: la cabecera de campo.tsx CUENTA la historia («border vs border-sand») y no debe contar como una clase.
const leer = (ruta: string) =>
  readFileSync(join(RAIZ, ruta), "utf8").replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "");

/** Los `--color-*: #hex` de un bloque de CSS. */
function colores(bloque: string): Record<string, string> {
  const salida: Record<string, string> = {};
  for (const m of bloque.matchAll(/--color-([a-z-]+):\s*(#[0-9a-f]{6})/gi)) salida[m[1]] = m[2].toLowerCase();
  return salida;
}

// Claro = el bloque @theme; oscuro = el bloque `:root[data-tema="oscuro"]` (el de `prefers-color-scheme` repite los mismos valores).
const claro = colores(css.slice(css.indexOf("@theme {"), css.indexOf("@media (prefers-color-scheme: dark)")));
const oscuroInicio = css.indexOf(':root[data-tema="oscuro"] {');
const oscuro = { ...claro, ...colores(css.slice(oscuroInicio, css.indexOf("}", oscuroInicio))) };
const TEMAS = { claro, oscuro } as const;

function luminancia(hex: string): number {
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255).map((c) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4));
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
function contraste(a: string, b: string): number {
  const [x, y] = [luminancia(a), luminancia(b)].sort((p, q) => q - p);
  return (x + 0.05) / (y + 0.05);
}

describe("el borde de un control (WCAG 1.4.11: 3:1)", () => {
  it("`borde-control` sigue siendo un alias de `taupe`", () => {
    expect(css).toMatch(/--color-borde-control:\s*var\(--color-taupe\)/);
  });

  for (const [tema, c] of Object.entries(TEMAS)) {
    for (const fondo of ["crema", "papel", "hueso"]) {
      it(`${tema}: taupe sobre ${fondo} ≥ 3:1`, () => {
        expect(contraste(c.taupe, c[fondo])).toBeGreaterThanOrEqual(3);
      });
    }
    it(`${tema}: sand NO alcanza como borde de un control (por eso existe el alias)`, () => {
      expect(contraste(c.sand, c.crema)).toBeLessThan(3);
    });
  }
});

describe("el texto de un error (AA: 4.5:1)", () => {
  for (const [tema, c] of Object.entries(TEMAS)) {
    for (const fondo of ["crema", "papel"]) {
      it(`${tema}: rojo-profundo sobre ${fondo} ≥ 4.5:1`, () => {
        expect(contraste(c["rojo-profundo"], c[fondo])).toBeGreaterThanOrEqual(4.5);
      });
    }
  }
  it("oscuro: el `rojo` plano sobre papel NO alcanza (por eso el error va en rojo-profundo)", () => {
    expect(contraste(oscuro.rojo, oscuro.papel)).toBeLessThan(4.5);
  });
});

describe("los componentes piden esos tokens", () => {
  const campo = leer("apps/web/components/ui/campo.tsx");
  const area = leer("apps/web/components/ui/area-texto.tsx");
  const boton = leer("apps/web/components/ui/boton.tsx");
  const toast = leer("apps/web/components/toast.tsx");

  it("Campo y CampoSelect: borde de control, y el error lo REEMPLAZA", () => {
    expect(campo.match(/error \? "border-rojo" : "border-borde-control"/g)).toHaveLength(2);
    expect(campo).not.toMatch(/border-sand/);
    // Ni `border-sand` ni `error && "border-rojo"` (sumado) en las cadenas de clases.
    expect(campo).not.toMatch(/error && "border-rojo"/);
  });

  it("AreaTexto: el mismo borde y el mismo reemplazo", () => {
    expect(area).toMatch(/error \? "border-rojo" : "border-borde-control"/);
    expect(area).not.toMatch(/border-sand/);
  });

  it("Boton «secundario» usa borde-control", () => {
    expect(boton).toMatch(/secundario:\s*"[^"]*border-borde-control/);
  });

  it("los mensajes de error de los tres campos y el aviso de error van en rojo-profundo", () => {
    for (const [nombre, src] of [["campo", campo], ["area-texto", area]] as const) {
      expect(src, nombre).not.toMatch(/text-xs text-rojo[^-]/);
      expect(src, nombre).toMatch(/text-xs text-rojo-profundo/);
    }
    expect(toast).toMatch(/border-rojo\/30 text-rojo-profundo/);
  });
});

describe("Modal atrapa el foco y lo devuelve", () => {
  const modal = leer("apps/web/components/ui/modal.tsx");
  const hook = leer("apps/web/lib/use-foco-atrapado.ts");

  it("usa el mismo hook que Drawer y HojaInferior, sin enfocar el primer botón", () => {
    expect(modal).toMatch(/useFocoAtrapado\(\{/);
    expect(modal).toMatch(/enfocarPrimero:\s*false/);
  });

  it("captura quién tenía el foco ANTES del efecto que lo mueve", () => {
    const captura = modal.indexOf("disparador.current = document.activeElement");
    const hookUso = modal.indexOf("useFocoAtrapado({");
    const enfoqueCaja = modal.indexOf("ref.current?.focus()");
    expect(captura).toBeGreaterThan(-1);
    expect(captura).toBeLessThan(hookUso);
    expect(hookUso).toBeLessThan(enfoqueCaja);
  });

  it("respeta `bloqueado`: Escape no cierra mientras se guarda", () => {
    expect(modal).toMatch(/if \(!bloqueado\) onCerrar\(\)/);
  });

  it("el hook trata la propia caja como «el principio» de Shift+Tab", () => {
    expect(hook).toMatch(/document\.activeElement === caja\.current/);
  });
});
