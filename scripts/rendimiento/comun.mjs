/**
 * Piezas comunes de los tres escáneres de rendimiento (`arboles.mjs`, `ui.mjs`, `observabilidad.mjs`). Traídos de CAYLA Retail el
 * 2026-11-06; lo que cambió: Dynamic tiene tres superficies (`SUPERFICIES`) y no un solo grupo `(app)`.
 *
 * Usan el compilador de TypeScript (AST) y no expresiones regulares: contar `if` anidados o saber si un `await` está dentro de un
 * `Promise.all` con texto plano da falsos positivos en cada comentario o cadena. TypeScript ya es dependencia del repo; si no se
 * encuentra (un worktree sin `pnpm install`), se dice con claridad en vez de caer a una heurística que mienta.
 */
import { createRequire } from "node:module";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const RAIZ = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
export const WEB = join(RAIZ, "apps", "web");

/** Los grupos de rutas de Dynamic. Una pantalla vive en uno de los tres; el orden es solo de lectura. */
export const SUPERFICIES = ["(admin)", "(mio)", "(terminal)"];

/** Todas las `page.tsx` de las tres superficies. */
export const paginasDeLaApp = () => SUPERFICIES.flatMap((g) => listarFuentes(join(WEB, "app", g))).filter((f) => f.endsWith("/page.tsx"));

let _ts = null;
/** Carga `typescript` desde el worktree, desde `apps/web` o desde el checkout principal (los worktrees comparten node_modules a veces). */
export function cargarTS() {
  if (_ts) return _ts;
  const principal = resolve(RAIZ, "..", "..", "..");
  const candidatos = [WEB, RAIZ, join(principal, "apps", "web"), principal];
  for (const base of candidatos) {
    try {
      _ts = createRequire(join(base, "package.json"))("typescript");
      return _ts;
    } catch {
      /* siguiente candidato */
    }
  }
  throw new Error("No encuentro `typescript`. Corre `pnpm install` en el repo (los escáneres leen el AST, no adivinan por texto).");
}

/** Todos los .ts/.tsx bajo `dir`, sin pruebas, sin node_modules ni .next. */
export function listarFuentes(dir, { incluirPruebas = false } = {}) {
  const salida = [];
  const recorrer = (d) => {
    if (!existsSync(d)) return;
    for (const e of readdirSync(d, { withFileTypes: true })) {
      if (e.name === "node_modules" || e.name === ".next" || e.name.startsWith(".")) continue;
      const ruta = join(d, e.name);
      if (e.isDirectory()) recorrer(ruta);
      else if (/\.(ts|tsx)$/.test(e.name) && !e.name.endsWith(".d.ts") && (incluirPruebas || !/\.(test|casos)\./.test(e.name))) salida.push(ruta);
    }
  };
  recorrer(dir);
  return salida.sort();
}

export const leer = (ruta) => readFileSync(ruta, "utf8");

/** Parsea un texto TS/TSX a su AST (con padres puestos, para poder subir). */
export function parsear(texto, nombre = "archivo.tsx") {
  const ts = cargarTS();
  const kind = nombre.endsWith(".tsx") ? ts.ScriptKind.TSX : ts.ScriptKind.TS;
  return ts.createSourceFile(nombre, texto, ts.ScriptTarget.Latest, true, kind);
}

/** Línea (1-based) de un nodo. */
export const lineaDe = (sf, nodo) => sf.getLineAndCharacterOfPosition(nodo.getStart(sf)).line + 1;

/** Ruta relativa al repo, con `/`. */
export const rel = (ruta) => ruta.replace(RAIZ + "/", "");

/** Lee `--clave valor` y `--bandera` de argv. */
export function leerArgs(argv) {
  const o = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith("--")) { o._.push(a); continue; }
    const k = a.slice(2);
    const sig = argv[i + 1];
    if (sig !== undefined && !sig.startsWith("--")) { o[k] = sig; i++; } else o[k] = true;
  }
  return o;
}

/** Tabla markdown simple. */
export function tabla(cabeceras, filas) {
  const l = (c) => `| ${c.join(" | ")} |`;
  return [l(cabeceras), l(cabeceras.map(() => "---")), ...filas.map(l)].join("\n");
}
