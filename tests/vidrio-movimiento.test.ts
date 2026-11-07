// ============================================================================
// vidrio-movimiento.test.ts — las animaciones del panel, encendidas o quietas
// ============================================================================
// Es el botón «Animaciones» de Retail (ADR-0625 de Retail, Felipe 2026-11-07): el panel arranca quieto, el botón lo enciende y lo recuerda en
// el aparato, y el sistema operativo que pide menos movimiento gana siempre. Aquí se prueban las reglas puras, el trozo del guion que pone el
// atributo antes de pintar, y que nadie vuelva a preguntar `matchMedia` por su cuenta: esa pieza no vería el botón.
// ============================================================================

import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import {
  alternarMovimiento,
  ATRIBUTO_MOVIMIENTO,
  CLAVE_MOVIMIENTO,
  GUION_MOVIMIENTO,
  MOVIMIENTO_POR_DEFECTO,
  quedaQuieto,
  resolverMovimiento,
  textosDelBotonMovimiento,
} from "../apps/web/lib/vidrio-movimiento";
import { guionVidrioAntesDePintar } from "../apps/web/lib/vidrio";

describe("las reglas", () => {
  it("arranca quieto, como Retail", () => {
    expect(MOVIMIENTO_POR_DEFECTO).toBe("quieto");
  });

  it("lo guardado ausente o corrupto es quieto; lo válido se respeta", () => {
    expect(resolverMovimiento("vivo")).toBe("vivo");
    expect(resolverMovimiento("quieto")).toBe("quieto");
    for (const raro of [null, undefined, "", "VIVO", "on", true, 1, {}]) expect(resolverMovimiento(raro)).toBe("quieto");
  });

  it("alternar va y vuelve", () => {
    expect(alternarMovimiento("quieto")).toBe("vivo");
    expect(alternarMovimiento(alternarMovimiento("quieto"))).toBe("quieto");
  });

  it("el aparato que pide menos movimiento gana siempre; si no, manda el botón; sin botón (terminal), solo el aparato", () => {
    expect(quedaQuieto("vivo", false)).toBe(false);
    expect(quedaQuieto("quieto", false)).toBe(true);
    expect(quedaQuieto("vivo", true)).toBe(true);
    expect(quedaQuieto("quieto", true)).toBe(true);
    expect(quedaQuieto(null, false)).toBe(false);
    expect(quedaQuieto(null, true)).toBe(true);
  });

  it("el nombre del botón no cambia; el título dice qué hará el clic", () => {
    expect(textosDelBotonMovimiento("quieto")).toEqual({ etiqueta: "Animaciones", titulo: "Encender las animaciones" });
    expect(textosDelBotonMovimiento("vivo")).toEqual({ etiqueta: "Animaciones", titulo: "Apagar las animaciones" });
  });
});

function correr(guion: string, ruta: string, almacen: { getItem: (k: string) => string | null }): Record<string, string> {
  const atributos: Record<string, string> = {};
  const documento = {
    documentElement: { setAttribute: (k: string, v: string) => void (atributos[k] = v) },
    querySelector: () => null,
  };
  const ventana = { location: { pathname: ruta }, matchMedia: () => ({ matches: true }) };
  new Function("document", "localStorage", "location", "matchMedia", guion)(documento, almacen, ventana.location, ventana.matchMedia);
  return atributos;
}

describe("el guion antes de pintar", () => {
  it("lee la clave del botón y pone el atributo que lee el CSS", () => {
    const pedidas: string[] = [];
    const atributos = correr(GUION_MOVIMIENTO, "/admin/dashboard", { getItem: (k) => (pedidas.push(k), "vivo") });
    expect(atributos[ATRIBUTO_MOVIMIENTO]).toBe("vivo");
    expect(pedidas).toEqual([CLAVE_MOVIMIENTO]);
  });

  it("sin nada guardado, corrupto o sin almacenamiento: quieto, y siempre deja un valor puesto", () => {
    expect(correr(GUION_MOVIMIENTO, "/admin", { getItem: () => null })[ATRIBUTO_MOVIMIENTO]).toBe("quieto");
    expect(correr(GUION_MOVIMIENTO, "/admin", { getItem: () => "VIVO" })[ATRIBUTO_MOVIMIENTO]).toBe("quieto");
    const bloqueado = { getItem: (): string | null => { throw new Error("bloqueado"); } };
    expect(correr(GUION_MOVIMIENTO, "/admin", bloqueado)[ATRIBUTO_MOVIMIENTO]).toBe("quieto");
  });

  it("el guion del vidrio lo pone en el panel y en Lo mío, y nunca en el terminal", () => {
    const guion = guionVidrioAntesDePintar({ panel: true, terminal: true });
    expect(guion).not.toBeNull();
    const nada = { getItem: () => null };
    expect(correr(guion!, "/admin/dashboard", nada)[ATRIBUTO_MOVIMIENTO]).toBe("quieto");
    expect(correr(guion!, "/mio", nada)[ATRIBUTO_MOVIMIENTO]).toBe("quieto");
    expect(correr(guion!, "/terminal/marcar", nada)[ATRIBUTO_MOVIMIENTO]).toBeUndefined();
  });
});

describe("el CSS que aquieta", () => {
  const css = readFileSync(join(__dirname, "../apps/web/app/estilos/vidrio/movimiento.css"), "utf8");
  const bloque = css.slice(css.indexOf("ANIMACIONES ENCENDIDAS O QUIETAS"));

  it("existe, va al final del archivo y cuelga solo del panel quieto", () => {
    expect(bloque.length).toBeGreaterThan(0);
    expect(css.lastIndexOf("@keyframes")).toBeLessThan(css.indexOf("ANIMACIONES ENCENDIDAS O QUIETAS"));
    const selectores = [...bloque.matchAll(/^\s*(:root[^{,]*)[,{]/gm)].map((m) => m[1].trim());
    expect(selectores.length).toBeGreaterThan(0);
    for (const s of selectores) expect(s.startsWith(':root[data-vidrio="panel"][data-movimiento="quieto"]')).toBe(true);
  });

  it("salva las señales de espera: el colibrí de «Guardando…» y el hilo y el anillo del loader llevan data-senal", () => {
    const boton = readFileSync(join(__dirname, "../apps/web/components/ui/boton.tsx"), "utf8");
    const cargando = readFileSync(join(__dirname, "../apps/web/components/cargando.tsx"), "utf8");
    expect(boton).toMatch(/data-senal className="colibri aletea/);
    expect(cargando).toMatch(/data-senal className="colibri aletea/);
    expect(cargando).toMatch(/data-senal className="vidrio-espera-hilo/);
    expect(cargando).toMatch(/<circle data-senal/);
  });
});

// Toda pieza que anima desde JavaScript pregunta `prefiereQuieto()`: una pregunta suelta a `matchMedia` no vería el botón.
describe("una sola pregunta por el movimiento", () => {
  const raiz = join(__dirname, "../apps/web");
  const PERMITIDOS = new Set(["lib/vidrio-movimiento.ts"]);
  function archivos(dir: string): string[] {
    return readdirSync(join(raiz, dir)).flatMap((n) => {
      const rel = `${dir}/${n}`;
      if (n === "node_modules" || n.startsWith(".")) return [];
      if (statSync(join(raiz, rel)).isDirectory()) return archivos(rel);
      return /\.(ts|tsx)$/.test(n) && !/\.test\.tsx?$/.test(n) ? [rel] : [];
    });
  }

  it("nadie fuera de lib/vidrio-movimiento.ts pregunta matchMedia por el movimiento reducido", () => {
    const sueltos = ["app", "components", "lib"]
      .flatMap(archivos)
      .filter((f) => !PERMITIDOS.has(f))
      .filter((f) => /matchMedia\s*(\?\.)?\(\s*["'`]\(prefers-reduced-motion|["'`]\(prefers-reduced-motion:\s*reduce\)["'`]/.test(readFileSync(join(raiz, f), "utf8")));
    expect(sueltos, "Usa prefiereQuieto() de lib/vidrio-movimiento.ts").toEqual([]);
  });
});
