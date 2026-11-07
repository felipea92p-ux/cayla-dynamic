#!/usr/bin/env node
/**
 * Escáner de OBSERVABILIDAD (skill `skill-evaluacion-observabilidad`).
 *
 * Dos niveles. (1) INFRAESTRUCTURA del repo: ¿existe algo que mida, registre y una peticiones? (2) HIGIENE por archivo, con AST:
 *   · rpc-descartada / rpc-ignora-error   una `.rpc(…)` cuyo resultado se descarta, o se lee `{ data }` sin `error` (la falla se vuelve «sin datos»);
 *   · catch-mudo        un `catch` vacío, o que solo hace `console.*` (se traga el error: no lo registra bien ni lo relanza);
 *   · console-suelto    `console.log/warn/error` en código de servidor: sin nivel ni campos ni correlación;
 *   · fetch-sin-tope    `fetch(` sin `signal` (si el proveedor se cuelga, la petición también);
 *   · dato-personal-en-log   un `console.*` cuyos argumentos nombran dni, ruc, teléfono, correo, nombre o dirección;
 *   · accion-sin-rastro una Server Action (`"use server"`) sin ninguna señal de registro (ni log ni `throw` ni retorno de error).
 *
 * QUÉ ASUME. «Observabilidad» es poder responder desde fuera «¿qué pasó y cuánto tardó?». La AUDITORÍA DE NEGOCIO (`correcciones_auditoria`,
 * `parametros_historial`) ya existe y NO cuenta como observabilidad técnica. Este escáner no sabe qué datos son sensibles de verdad: el nombre de
 * una variable es una pista. NO mide nada en producción (no hay con qué): lo dice la sección de infraestructura.
 *
 * USO   node scripts/rendimiento/observabilidad.mjs [--top 25] [--json] [--estricto]
 */
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { RAIZ, WEB, cargarTS, leer, leerArgs, lineaDe, listarFuentes, paginasDeLaApp, parsear, rel, tabla } from "./comun.mjs";

const PERSONAL = /\b(dni|ruc|tel[eé]fono|celular|correo|email|nombres?|apellidos?|direcci[oó]n|documento)\b/i;

/** Higiene de UN archivo (pura). */
export function analizarArchivo(texto, nombre = "x.ts") {
  const ts = cargarTS();
  const sf = parsear(texto, nombre);
  const hallazgos = [];
  const marca = (n, tipo, detalle = "") => hallazgos.push({ tipo, linea: lineaDe(sf, n), detalle });
  const esServidor = /^\s*["']use server["']/m.test(texto) || !/^\s*["']use client["']/m.test(texto);
  let usaLog = false;
  let hayThrowOError = false;

  /**
   * ¿Qué pasa con el resultado de una `.rpc(…)`? Devuelve `null` si el error se trata, o el tipo de hallazgo:
   *   rpc-descartada   `await supabase.rpc(…);` suelto: el resultado ni se mira (la falla es invisible);
   *   rpc-ignora-error `const { data } = await supabase.rpc(…)` sin `error`: una falla se confunde con «no hay datos».
   * Se da por tratado lo que el repo ya hace a propósito: pasarla como argumento a un envoltorio (`exigir(…)`, `firmar(…)`,
   * `guardar(…)`), devolverla, o leer `.error` / `throwOnError`.
   */
  const veredictoRpc = (llamada) => {
    // Sube por `.setHeader(…)`, `await`, paréntesis y `as`.
    let nodo = llamada;
    for (;;) {
      const p = nodo.parent;
      if (!p) return null;
      if (ts.isAwaitExpression(p) || ts.isParenthesizedExpression(p) || ts.isAsExpression(p) || ts.isNonNullExpression(p)) { nodo = p; continue; }
      if (ts.isPropertyAccessExpression(p) && p.expression === nodo) {
        if (/^(throwOnError|error|then|catch)$/.test(p.name.text)) return null; // `.then(({ error }) => …)` lo trata quien lo escribe
        if (p.parent && ts.isCallExpression(p.parent) && p.parent.expression === p) { nodo = p.parent; continue; }
        return null;
      }
      break;
    }
    const p = nodo.parent;
    if (ts.isCallExpression(p)) return null; // argumento de un envoltorio o de Promise.all([...]): lo trata quien lo recibe
    if (ts.isArrayLiteralExpression(p)) {
      // Elemento de `Promise.all([...])`: el patrón de desestructuración de la izquierda debe traer `error` en esa posición.
      const idx = p.elements.indexOf(nodo);
      const llamadaPadre = p.parent && ts.isCallExpression(p.parent) ? p.parent : null;
      let decl = llamadaPadre?.parent;
      while (decl && ts.isAwaitExpression(decl)) decl = decl.parent;
      if (decl && ts.isVariableDeclaration(decl) && ts.isArrayBindingPattern(decl.name)) {
        const el = decl.name.elements[idx];
        if (el && ts.isBindingElement(el) && ts.isObjectBindingPattern(el.name) && !el.name.elements.some((e) => (e.propertyName ?? e.name).getText(sf) === "error")) return "rpc-ignora-error";
      }
      return null;
    }
    if (ts.isExpressionStatement(p)) return "rpc-descartada";
    if (ts.isReturnStatement(p) || ts.isArrowFunction(p)) return null; // se devuelve tal cual: decide quien llama
    if (ts.isVariableDeclaration(p)) {
      if (ts.isObjectBindingPattern(p.name)) return p.name.elements.some((e) => (e.propertyName ?? e.name).getText(sf) === "error") ? null : "rpc-ignora-error";
      if (ts.isIdentifier(p.name)) return new RegExp(`\\b${p.name.text}\\.error\\b|\\bexigir\\(\\s*${p.name.text}\\b`).test(texto) ? null : "rpc-ignora-error";
    }
    return null;
  };

  const lee = (n) => {
    if (ts.isThrowStatement(n)) hayThrowOError = true;
    if (ts.isCallExpression(n)) {
      const f = n.expression.getText(sf);
      if (/^console\.(log|warn|error|info|debug)$/.test(f)) {
        usaLog = true;
        if (esServidor) marca(n, "console-suelto", f);
        const args = n.arguments.map((a) => a.getText(sf)).join(" ");
        if (PERSONAL.test(args)) marca(n, "dato-personal-en-log", args.slice(0, 50));
      }
      if (/(^|\.)logger\.|(^|\.)registrar(Evento|Error)\(/.test(f)) usaLog = true;
      if (f === "fetch" || /\.fetch$/.test(f)) {
        const opts = n.arguments[1];
        const conSignal = opts && ts.isObjectLiteralExpression(opts) && opts.properties.some((p) => p.name && p.name.getText(sf) === "signal");
        const url = n.arguments[0]?.getText(sf) ?? "";
        if (!conSignal && /https?:\/\//.test(url + (texto.includes("process.env") ? "" : ""))) marca(n, "fetch-sin-tope", url.slice(0, 50));
        else if (!conSignal && !/["'`]\//.test(url)) marca(n, "fetch-sin-tope", url.slice(0, 50)); // URL calculada: externa o interna, no se sabe
      }
      if (/\.rpc$/.test(f)) {
        const v = veredictoRpc(n);
        if (v) marca(n, v, f);
      }
    }
    if (ts.isCatchClause(n)) {
      const st = n.block.statements;
      const soloLog = st.length > 0 && st.every((s) => ts.isExpressionStatement(s) && /^console\./.test(s.expression.getText(sf)));
      const relanza = st.some((s) => ts.isThrowStatement(s) || ts.isReturnStatement(s));
      if (st.length === 0 || (soloLog && !relanza)) marca(n, "catch-mudo", st.length === 0 ? "vacío" : "solo console");
    }
    ts.forEachChild(n, lee);
  };
  lee(sf);

  if (/^\s*["']use server["']/m.test(texto) && !usaLog && !hayThrowOError && !/\berror\b/.test(texto)) marca(sf, "accion-sin-rastro");
  return hallazgos;
}

/** Nivel 1: ¿hay algo instalado que mida? Lectura de archivos y package.json. */
export function infraestructura() {
  const pkg = JSON.parse(readFileSync(join(WEB, "package.json"), "utf8"));
  const deps = { ...pkg.dependencies, ...pkg.devDependencies };
  const tiene = (re) => Object.keys(deps).filter((d) => re.test(d));
  const archivos = listarFuentes(join(WEB, "app")).concat(listarFuentes(join(WEB, "lib")));
  const hay = (re) => archivos.some((f) => re.test(rel(f)));
  const segmentos = paginasDeLaApp().length;
  const errorTsx = listarFuentes(join(WEB, "app")).filter((f) => f.endsWith("/error.tsx") || f.endsWith("/global-error.tsx")).length;
  const items = [
    ["Logger estructurado (`capturarError` en lib/errores.ts o un logger propio)", hay(/(^|\/)(logger|log|registro-eventos|observabilidad|errores)\.ts$/) ],
    ["APM / errores (Sentry, OpenTelemetry, Datadog…)", tiene(/sentry|opentelemetry|datadog|newrelic|highlight/).length > 0],
    ["`instrumentation.ts` (hook de Next para trazas)", existsSync(join(WEB, "instrumentation.ts")) || existsSync(join(WEB, "src", "instrumentation.ts"))],
    ["Core Web Vitals (web-vitals / Speed Insights / Analytics)", tiene(/web-vitals|speed-insights|@vercel\/analytics/).length > 0 || texto_contiene("useReportWebVitals")],
    ["`request_id` / correlación en peticiones", texto_contiene("x-request-id") || texto_contiene("request_id") && texto_contiene("proxy")],
    ["Límites de error por segmento", errorTsx >= Math.ceil(segmentos / 10)],
  ];
  function texto_contiene(s) { return archivos.some((f) => leer(f).includes(s)); }
  return { items: items.map(([que, ok]) => ({ que, ok })), segmentos, errorTsx };
}

export function escanear() {
  const archivos = [...listarFuentes(join(WEB, "app")), ...listarFuentes(join(WEB, "lib"))].filter((f) => !/\.(tsx)$/.test(f) || /actions|route/.test(f) || /\/page\.tsx$/.test(f));
  const todo = [];
  let rpcs = 0;
  for (const f of listarFuentes(join(WEB, "app")).concat(listarFuentes(join(WEB, "lib")), listarFuentes(join(WEB, "components")))) {
    const t = leer(f);
    rpcs += (t.match(/\.rpc\(/g) ?? []).length;
    for (const h of analizarArchivo(t, f)) todo.push({ archivo: rel(f), ...h });
  }
  void archivos;
  const porTipo = {};
  for (const h of todo) porTipo[h.tipo] = (porTipo[h.tipo] ?? 0) + 1;
  const porArchivo = {};
  for (const h of todo) porArchivo[h.archivo] = (porArchivo[h.archivo] ?? 0) + 1;
  return { infra: infraestructura(), llamadasRpc: rpcs, porTipo, hallazgos: todo, archivosConMasHallazgos: Object.entries(porArchivo).sort((a, b) => b[1] - a[1]) };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const a = leerArgs(process.argv.slice(2));
  const r = escanear();
  const top = Number(a.top ?? 15);
  if (a.json) console.log(JSON.stringify(r, null, 2));
  else {
    console.log("Observabilidad — infraestructura\n");
    console.log(tabla(["capacidad", "¿existe?"], r.infra.items.map((i) => [i.que, i.ok ? "sí" : "**NO**"])));
    console.log(`\n${r.llamadasRpc} llamadas \`.rpc(\`; ${r.infra.errorTsx} límites de error para ${r.infra.segmentos} pantallas\n\nHigiene por tipo:\n`);
    console.log(tabla(["tipo", "cantidad"], Object.entries(r.porTipo).sort((x, y) => y[1] - x[1]).map(([k, v]) => [k, v])));
    console.log("\nArchivos con más hallazgos:\n");
    console.log(tabla(["archivo", "hallazgos"], r.archivosConMasHallazgos.slice(0, top)));
  }
  if (a.estricto && r.hallazgos.length) process.exit(1);
}
