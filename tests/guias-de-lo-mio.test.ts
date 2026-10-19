// ============================================================================
// guias-de-lo-mio.test.ts — las guías de «Lo mío» y sus anclas, comprobadas
// ============================================================================
// Una guía no falla ruidosamente: si el ancla `data-tour` de un paso está mal
// escrita, driver.js la «salta» (así está configurado a propósito, para los
// pasos que dependen de datos) y la guía se ve entera… menos ese paso. Un typo
// se confundiría con «esta persona no tiene ese dato». Por eso las anclas se
// comprueban aquí contra el código, y no a ojo.
//
// Se lee el TEXTO de los archivos y no se importan: las pantallas traen React,
// Supabase y medio panel, y esta prueba corre en node.
// ============================================================================
import { describe, it, expect } from "vitest";
import { readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { TABS } from "@/lib/mio-secciones";

const RAIZ = path.resolve(import.meta.dirname, "../apps/web/app/(mio)/mio");

function archivos(dir: string): string[] {
  return readdirSync(dir).flatMap((n) => {
    const ruta = path.join(dir, n);
    return statSync(ruta).isDirectory() ? archivos(ruta) : /\.(ts|tsx)$/.test(n) ? [ruta] : [];
  });
}
const TODOS = archivos(RAIZ);
const leer = (f: string) => readFileSync(f, "utf8");
const PAGE = leer(path.join(RAIZ, "page.tsx"));

/** Los archivos que DEFINEN pasos: los `guias-de-*.ts`, la pantalla de Disciplina y la de Resumen (en page.tsx). */
const DEFINEN_PASOS = TODOS.filter((f) => /guias-de-[a-z]+\.ts$/.test(f) || /disciplina-mia\.tsx$/.test(f) || f.endsWith("page.tsx") && f === path.join(RAIZ, "page.tsx"));

/** Secciones que no tienen guía A PROPÓSITO. Vacía: hoy las dieciséis la tienen. */
const SIN_GUIA_A_PROPOSITO: readonly string[] = [];

function selectoresCitados(): Array<{ archivo: string; ancla: string }> {
  const salida: Array<{ archivo: string; ancla: string }> = [];
  for (const f of DEFINEN_PASOS) {
    for (const m of leer(f).matchAll(/selector:\s*'\[data-tour="([a-z0-9-]+)"\]'/g)) {
      salida.push({ archivo: path.relative(RAIZ, f), ancla: m[1] });
    }
  }
  return salida;
}

/**
 * Las anclas que de verdad están puestas en la pantalla: `data-tour="x"` o la propiedad `dataTour="x"`.
 * NO cuentan las que aparecen dentro de un selector (`'[data-tour="x"]'`): es el texto del propio paso,
 * y contarlas haría que cualquier ancla se «encontrara» a sí misma. (La primera versión de esta prueba
 * lo hacía y no se ponía en rojo con nada; se descubrió rompiéndola a propósito.)
 */
function anclasPuestas(): Set<string> {
  const puestas = new Set<string>();
  for (const f of TODOS) {
    for (const m of leer(f).matchAll(/(?<!\[)(?:data-tour|dataTour)="([a-z0-9-]+)"/g)) puestas.add(m[1]);
  }
  return puestas;
}

describe("cada sección de «Lo mío» tiene su guía", () => {
  const bloque = PAGE.match(/const GUIAS_POR_SECCION[^=]*=\s*\{([\s\S]*?)\n\};/);

  it("el mapa de guías existe en page.tsx", () => {
    expect(bloque).not.toBeNull();
  });

  it("tiene exactamente las secciones del menú, menos las que se excluyeron a propósito", () => {
    const claves = [...(bloque?.[1] ?? "").matchAll(/^\s*([a-z]+):/gm)].map((m) => m[1]).sort();
    const esperadas = TABS.filter((t) => !SIN_GUIA_A_PROPOSITO.includes(t)).sort();
    expect(claves).toEqual(esperadas);
  });
});

describe("las anclas de los pasos existen", () => {
  const citados = selectoresCitados();
  const puestas = anclasPuestas();

  it("se encontraron los pasos de las dieciséis guías (si esto baja, cambió el formato y la prueba no vigila nada)", () => {
    // 16 guías con 2 o 3 pasos cada una: lejos de 0, y un piso que no se cae por quitar un paso.
    expect(citados.length).toBeGreaterThanOrEqual(35);
  });

  it("cada ancla que cita un paso está puesta en alguna pantalla — un typo la haría saltarse en silencio", () => {
    const sueltas = citados.filter((c) => !puestas.has(c.ancla)).map((c) => `${c.archivo}: ${c.ancla}`);
    expect(sueltas).toEqual([]);
  });

  it("dos pasos distintos no apuntan a la misma ancla dentro de una misma guía", () => {
    const porArchivo = new Map<string, string[]>();
    for (const c of citados) porArchivo.set(c.archivo, [...(porArchivo.get(c.archivo) ?? []), c.ancla]);
    for (const [archivo, anclas] of porArchivo) {
      expect(new Set(anclas).size, archivo).toBe(anclas.length);
    }
  });

  it("los nombres siguen el formato mio-<sección>-<qué>, con una sección real", () => {
    const secciones = new Set<string>([...TABS, "editar"]);
    for (const { ancla } of citados) {
      const m = ancla.match(/^mio-([a-z]+)-[a-z-]+$/);
      expect(m, ancla).not.toBeNull();
      expect(secciones.has(m![1]), ancla).toBe(true);
    }
  });
});
