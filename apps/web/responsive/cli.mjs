#!/usr/bin/env node
// Verificación de responsive de Dynamic. Traída de CAYLA Retail; la guía está en `responsive/README.md`.
//
//   npx pnpm --filter @cayla-dynamic/web responsive:check dashboard
//   npx pnpm --filter @cayla-dynamic/web responsive:check dashboard bandeja mio marcar
//   npx pnpm --filter @cayla-dynamic/web responsive:check --module asistencia
//   npx pnpm --filter @cayla-dynamic/web responsive:check all
//
// Flags:
//   --module <id>        todas las pantallas de ese módulo
//   --base-url <url>     la app local (por defecto $TEMA_BASE_URL o http://localhost:3000)
//   --api-url <url>      la API local de Supabase (por defecto $TEMA_API_URL o http://127.0.0.1:55892)
//   --capturas-todas     además de las FAIL, una captura de cada caso que pasa
//   --headed             con una ventana de Chrome visible
//   --tolerancia <px>    tolerancia subpíxel (por defecto 1)
//   --salida <carpeta>   dónde escribir (por defecto responsive/.salida/<fecha>)
//
// Sale con 0 si todo cabe, con 1 si algo se sale o no se pudo abrir, y con 2 si la medición no vale: no es local, una sesión no entró, la app
// quiso hablar con otro Supabase, o no se pudo abrir ninguna pantalla.

import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { resolverSeleccion, TODAS_LAS_PANTALLAS, MODULOS } from "./pantallas/registro.mjs";
import { ejecutarVerificacion } from "./motor/ejecutor.mjs";
import { imprimirReporte, guardarReporte } from "./motor/reporte.mjs";
import { API_POR_DEFECTO, APP_POR_DEFECTO, exigirDynamic, exigirLocal, problemaDeRed } from "../tema/motor/sesion.mjs";

const AQUI = dirname(fileURLToPath(import.meta.url));

function parsearArgv(argv) {
  const opts = { ids: [], modulo: null, todas: false, baseURL: process.env.TEMA_BASE_URL || APP_POR_DEFECTO, apiURL: process.env.TEMA_API_URL || API_POR_DEFECTO, capturasTodas: false, headed: false, tolerancia: 1, salida: null };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--") continue;
    if (a === "--module" || a === "--modulo") opts.modulo = argv[++i];
    else if (a === "--base-url") opts.baseURL = argv[++i];
    else if (a === "--api-url") opts.apiURL = argv[++i];
    else if (a === "--capturas-todas") opts.capturasTodas = true;
    else if (a === "--headed") opts.headed = true;
    else if (a === "--tolerancia") opts.tolerancia = Number(argv[++i]);
    else if (a === "--salida") opts.salida = argv[++i];
    else if (a === "all" || a === "todas") opts.todas = true;
    else if (a === "--help" || a === "-h") {
      imprimirAyuda();
      process.exit(0);
    } else opts.ids.push(a);
  }
  opts.baseURL = String(opts.baseURL).replace(/\/$/, "");
  opts.apiURL = String(opts.apiURL).replace(/\/$/, "");
  return opts;
}

function imprimirAyuda() {
  console.log(`Pantallas: ${TODAS_LAS_PANTALLAS.map((p) => p.id).join(", ")}`);
  console.log(`Módulos: ${[...MODULOS.keys()].join(", ")}`);
  console.log("\nUso: npx pnpm --filter @cayla-dynamic/web responsive:check <pantalla...|--module <modulo>|all> [--base-url URL] [--capturas-todas] [--headed]");
}

async function main() {
  const opts = parsearArgv(process.argv.slice(2));
  if (!opts.ids.length && !opts.modulo && !opts.todas) {
    imprimirAyuda();
    process.exit(2);
  }
  exigirLocal(opts.baseURL, "La app");
  exigirLocal(opts.apiURL, "La API de Supabase");
  await exigirDynamic(opts.baseURL);

  const pantallas = resolverSeleccion({ ids: opts.ids, modulo: opts.modulo, todas: opts.todas });
  const seleccion = opts.todas ? "all" : opts.modulo ? `--module ${opts.modulo}` : opts.ids.join(" ");
  const dirSalida = opts.salida ? opts.salida : join(AQUI, ".salida", new Date().toISOString().replace(/[:.]/g, "-"));

  console.log(`Verificación de responsive: ${pantallas.length} pantalla(s) contra ${opts.baseURL}\nSalida: ${dirSalida}\n`);
  const { resultados, duracionMs, fuera } = await ejecutarVerificacion(pantallas, {
    baseURL: opts.baseURL,
    apiURL: opts.apiURL,
    dirSalida,
    capturasTodas: opts.capturasTodas,
    headed: opts.headed,
    tolerancia: opts.tolerancia,
  });

  const { exitoso } = imprimirReporte(resultados, { dirSalida });
  guardarReporte(resultados, { dirSalida, duracionMs, seleccion });
  console.log(`\nTiempo: ${(duracionMs / 1000).toFixed(1)}s · Reporte: ${join(dirSalida, "reporte.md")}`);

  const red = problemaDeRed(fuera);
  if (red) throw new Error(red);
  const perdidas = resultados.filter((r) => r.sesionPerdida);
  if (perdidas.length) throw new Error(`la sesión no valió en ${[...new Set(perdidas.map((r) => r.pantalla.id))].join(", ")}.`);
  if (resultados.every((r) => r.error)) throw new Error("no se pudo abrir ninguna pantalla, y eso no es un verde ni un rojo: es no haber medido.");
  process.exit(exitoso ? 0 : 1);
}

main().catch((e) => {
  console.error(`\nLa medición no vale: ${e.message}`);
  process.exit(2);
});
