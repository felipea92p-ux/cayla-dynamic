#!/usr/bin/env node
/**
 * Escáner de VELOCIDAD PERCIBIDA (skill `skill-optimizacion-ui-ux-perf`).
 *
 * Por cada `page.tsx` de las tres superficies de `apps/web/app` (`(admin)`, `(mio)`, `(terminal)`) dice, con evidencia de AST:
 *   · loading        si tiene `loading.tsx` PROPIO, si HEREDA el de un ancestro o si no tiene ninguno;
 *   · cascada        cuántos `await` seguidos e INCONDICIONALES hay fuera de `Promise.all` (cada uno suma su latencia a la anterior; un `await`
 *                    dentro de un `if` o un ternario no cuenta, ni abrir el cliente de Supabase ni `searchParams`; es una CANDIDATA:
 *                    si el segundo depende del primero, no se puede paralelizar);
 *   · streaming      si usa `<Suspense>` (la parte lenta puede llegar después de la rápida);
 *   · peso-cliente   archivos `"use client"` alcanzables desde la página (hasta 3 saltos de import) y sus líneas: es un proxy del JS que
 *                    viaja al navegador, no los bytes reales (para eso, `next build` + analizador de bundle);
 *   · modales-fijos  modales (`<Modal>`/`<ModalRuta>`) cargados siempre, sin `next/dynamic`;
 *   · img-cruda      `<img>` en lugar de `next/image`; img-sin-sizes: `next/image` con `fill` sin `sizes`;
 *   · optimismo      archivos cliente que llaman una acción/RPC y no usan `useTransition`/`useOptimistic` (informativo: ver abajo).
 *
 * QUÉ ASUME. Mide ESTRUCTURA, no milisegundos: nada de esto sustituye a medir (Core Web Vitals, tiempo de RPC; ver skill de observabilidad).
 * REGLAS DEL REPO QUE NO SE CONTRADICEN: «Cargando» es `<Cargando />` (`components/cargando.tsx`) y NO se propone actualización optimista
 * en marcajes, planilla, pagos ni firmas (todo-o-nada; el aviso de éxito sale después de que Postgres confirma). `optimismo` solo sugiere
 * candidatos de estado de interfaz (selección, filtros, marcar visto).
 *
 * USO   node scripts/rendimiento/ui.mjs [--ruta admin/horas] [--top 25] [--json] [--estricto]
 */
import { existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { RAIZ, WEB, cargarTS, leer, leerArgs, paginasDeLaApp, parsear, rel, tabla } from "./comun.mjs";

export const UMBRAL_CASCADA = 3;
export const UMBRAL_PESO_CLIENTE_LINEAS = 1500;
/** Cuántas pantallas deben alcanzar un archivo para llamarlo «compartido» (mismo criterio que /focus). */
export const UMBRAL_COMPARTIDO = 8;

/** Análisis de UN archivo (pura). `texto` es el código; `nombre` decide TS o TSX. */
export function analizarArchivo(texto, nombre = "x.tsx") {
  const ts = cargarTS();
  const sf = parsear(texto, nombre);
  const K = ts.SyntaxKind;
  const r = {
    cliente: /^\s*(\/\*[\s\S]*?\*\/\s*|\/\/.*\n\s*)*["']use client["']/.test(texto),
    suspense: false, imgCruda: 0, imgSinSizes: 0, modales: 0, dinamico: false, optimistaOk: false, llamaServidor: false,
    transition: false, cascada: 0, imports: [],
  };

  const dentroDePromiseAll = (n) => {
    for (let p = n.parent; p; p = p.parent) {
      if (ts.isCallExpression(p) && /Promise\.(all|allSettled)$/.test(p.expression.getText(sf))) return true;
      if (ts.isFunctionLike(p) && p !== n) return false;
    }
    return false;
  };

  // Esperas que no tocan la red: abrir el cliente de Supabase lee cookies; `searchParams`/`params` ya están resueltos por Next.
  const esEsperaBarata = (aw) => /^(createClient|cookies|headers|searchParams|params|props\.params|props\.searchParams)\b/.test(aw.expression.getText(sf).replace(/^await\s+/, "")) || /^(searchParams|params)$/.test(aw.expression.getText(sf));

  let mejorCascada = 0;
  const contarCascada = (bloque) => {
    if (!bloque || !ts.isBlock(bloque)) return;
    let n = 0;
    for (const s of bloque.statements) {
      let tieneAwait = false;
      const buscar = (x) => {
        if (ts.isAwaitExpression(x) && !dentroDePromiseAll(x) && !esEsperaBarata(x)) tieneAwait = true;
        // Lo que está dentro de un `if` o un ternario es CONDICIONAL (puede no ocurrir) o alternativo: no suma a la cascada fija.
        if (ts.isIfStatement(x)) { buscar(x.expression); return; }
        if (ts.isConditionalExpression(x)) { buscar(x.condition); return; }
        if (!ts.isFunctionLike(x) || x === s) ts.forEachChild(x, buscar);
      };
      buscar(s);
      if (tieneAwait) n++;
    }
    mejorCascada = Math.max(mejorCascada, n);
  };

  const visitar = (n) => {
    if (ts.isImportDeclaration(n) && ts.isStringLiteral(n.moduleSpecifier)) {
      const m = n.moduleSpecifier.text;
      r.imports.push(m);
      if (m === "next/dynamic") r.dinamico = true;
    }
    if (ts.isJsxOpeningElement(n) || ts.isJsxSelfClosingElement(n)) {
      const tag = n.tagName.getText(sf);
      if (tag === "Suspense") r.suspense = true;
      if (tag === "img") r.imgCruda++;
      if (tag === "Modal" || tag === "ModalRuta") r.modales++;
      if (tag === "Image") {
        const attrs = n.attributes.properties.map((p) => (ts.isJsxAttribute(p) ? p.name.getText(sf) : ""));
        if (attrs.includes("fill") && !attrs.includes("sizes")) r.imgSinSizes++;
      }
    }
    if (ts.isCallExpression(n)) {
      const f = n.expression.getText(sf);
      if (/^(useOptimistic)$/.test(f)) r.optimistaOk = true;
      if (/^(useTransition|startTransition)$/.test(f)) r.transition = true;
      if (/\.rpc$|^fetch$|^supabase\.rpc$/.test(f) || /\.rpc\b/.test(f)) r.llamaServidor = true;
    }
    if (ts.isFunctionDeclaration(n) || ts.isArrowFunction(n) || ts.isFunctionExpression(n)) contarCascada(n.body);
    ts.forEachChild(n, visitar);
  };
  visitar(sf);
  r.cascada = mejorCascada;
  // `"use server"` importado = acción de servidor llamada desde el cliente.
  if (r.imports.some((m) => /actions\//.test(m))) r.llamaServidor = true;
  return r;
}

const EXT = [".tsx", ".ts", "/index.tsx", "/index.ts"];
function resolverImport(desde, spec) {
  let base = null;
  if (spec.startsWith("@/")) base = join(WEB, spec.slice(2));
  else if (spec.startsWith(".")) base = resolve(dirname(desde), spec);
  if (!base) return null;
  for (const e of ["", ...EXT]) {
    const c = base + e;
    if (/\.(tsx?)$/.test(c) && existsSync(c)) return c;
  }
  return null;
}

/** `loading.tsx` propio / heredado / ninguno, subiendo por la ruta hasta `app/`. */
export function estadoLoading(rutaPage) {
  let d = dirname(rutaPage);
  const propio = existsSync(join(d, "loading.tsx"));
  if (propio) return "propio";
  const tope = join(WEB, "app");
  while (d.startsWith(tope) && d !== tope) {
    d = dirname(d);
    if (existsSync(join(d, "loading.tsx"))) return "hereda";
  }
  return "ninguno";
}

/** Archivos alcanzables desde la página (hasta `saltos` imports) y sus resúmenes. */
export function alcanzables(rutaPage, saltos = 3, cache = new Map()) {
  const vistos = new Map();
  const cola = [[rutaPage, 0]];
  while (cola.length) {
    const [f, s] = cola.shift();
    if (vistos.has(f)) continue;
    let info = cache.get(f);
    if (!info) {
      const texto = leer(f);
      info = { ...analizarArchivo(texto, f), lineas: texto.split("\n").length };
      cache.set(f, info);
    }
    vistos.set(f, info);
    if (s < saltos) for (const m of info.imports) { const g = resolverImport(f, m); if (g && !vistos.has(g)) cola.push([g, s + 1]); }
  }
  return vistos;
}

export function escanear({ ruta = null } = {}) {
  const paginas = paginasDeLaApp();
  const cache = new Map();
  const filas = [];
  // Un archivo que muchas pantallas comparten (Modal, el combo, la barra) no es «peso de esa pantalla»: se descuenta (como /focus).
  const usos = new Map();
  const alcPorPagina = new Map();
  for (const p of paginas) {
    const alc = alcanzables(p, 3, cache);
    alcPorPagina.set(p, alc);
    for (const f of alc.keys()) usos.set(f, (usos.get(f) ?? 0) + 1);
  }
  for (const p of paginas) {
    const url = "/" + rel(p).replace(/^apps\/web\/app\/\((admin|mio|terminal)\)\/?/, "").replace(/\/?page\.tsx$/, "");
    if (ruta && !url.includes(ruta)) continue;
    const alc = alcPorPagina.get(p);
    const propia = alc.get(p);
    let clientes = 0, lineasCliente = 0, modalesFijos = 0, imgCruda = 0, imgSinSizes = 0, optimismo = 0;
    for (const [f, i] of alc) {
      if (f !== p && (usos.get(f) ?? 0) >= UMBRAL_COMPARTIDO) continue;
      if (i.cliente) { clientes++; lineasCliente += i.lineas; }
      if (i.modales && !i.dinamico && i.cliente) modalesFijos += i.modales;
      imgCruda += i.imgCruda; imgSinSizes += i.imgSinSizes;
      if (i.cliente && i.llamaServidor && !i.transition && !i.optimistaOk) optimismo++;
    }
    const loading = estadoLoading(p);
    const banderas = [];
    // «hereda» NO es un problema: `app/loading.tsx` cubre lo que no trae el suyo. Solo se informa; la bandera es para «ninguno».
    if (loading === "ninguno") banderas.push("sin-loading");
    if (propia.cascada >= UMBRAL_CASCADA) banderas.push("cascada");
    if (!propia.suspense && propia.cascada >= 2) banderas.push("sin-streaming");
    if (lineasCliente >= UMBRAL_PESO_CLIENTE_LINEAS) banderas.push("peso-cliente");
    if (modalesFijos >= 2) banderas.push("modales-fijos");
    if (imgCruda) banderas.push("img-cruda");
    if (imgSinSizes) banderas.push("img-sin-sizes");
    if (propia.cliente) banderas.push("pagina-cliente");
    filas.push({
      ruta: url || "/", loading, cascada: propia.cascada, suspense: propia.suspense, archivosCliente: clientes, lineasCliente,
      modalesFijos, imgCruda, imgSinSizes, candidatosOptimismo: optimismo, banderas,
      puntaje: (loading === "ninguno" ? 6 : 0) + propia.cascada * 3 + Math.floor(lineasCliente / 500) + modalesFijos + imgCruda * 2 + (propia.cliente ? 5 : 0),
    });
  }
  return { paginas: filas.length, hallazgos: filas.filter((f) => f.banderas.length).sort((a, b) => b.puntaje - a.puntaje), todas: filas };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const a = leerArgs(process.argv.slice(2));
  const r = escanear({ ruta: a.ruta || null });
  const top = Number(a.top ?? 25);
  if (a.json) console.log(JSON.stringify(r, null, 2));
  else {
    console.log(`Velocidad percibida — ${r.paginas} pantallas, ${r.hallazgos.length} con banderas\n`);
    console.log(tabla(["ruta", "loading", "await seguidos", "cliente (arch/líneas)", "banderas"],
      r.hallazgos.slice(0, top).map((h) => [h.ruta, h.loading, h.cascada, `${h.archivosCliente}/${h.lineasCliente}`, h.banderas.join(", ")])));
  }
  if (a.estricto && r.hallazgos.length) process.exit(1);
}
