#!/usr/bin/env node
/**
 * Auditoría de contraste de Dynamic: recorre cuenta × ruta × tema contra un servidor LOCAL ya levantado, mide el contraste de cada texto,
 * detecta manchas claras y velos que aclaran, y captura la pantalla. Traído de CAYLA Retail; ver `tema/README.md`.
 *
 *   npx pnpm --filter @cayla-dynamic/web tema:auditar --cuenta admin --ruta /admin/dashboard,/admin/bandeja
 *   npx pnpm --filter @cayla-dynamic/web tema:auditar --cuenta admin,integrante --modulo asistencia
 *   npx pnpm --filter @cayla-dynamic/web tema:auditar --listar
 *
 * Opciones
 *   --base-url <url>     la app local (por defecto $TEMA_BASE_URL o http://localhost:3000)
 *   --api-url <url>      la API local de Supabase (por defecto $TEMA_API_URL o http://127.0.0.1:55892)
 *   --cuenta <a,b|todas> claves de `tema/cuentas.mjs` (por defecto: admin)
 *   --ruta <a,b>         rutas exactas    --modulo <a,b>  las estáticas de esos módulos    --todas  todas las estáticas
 *                        (sin ninguna de las tres: la pantalla de inicio de cada cuenta)
 *   --escenarios         agrega los escenarios de las rutas elegidas    --escenario <id>  solo ese
 *   --ancho N --alto N   viewport (por defecto 1440×900; 375 para celular)
 *   --sin-claro          no mide el claro    --capturas-claro  también captura el claro    --espera <ms>  tras cargar (por defecto 1200)
 *   --salida <dir>       dónde escribir (por defecto tema/.salida/<fecha>)
 *   --listar             lista cuentas, rutas por módulo y escenarios, y sale
 *
 * Sale con 0 si no hay hallazgos, con 1 si los hay (en cualquiera de los dos temas) y con 2 si la medición no vale: el script se cayó, una
 * sesión no entró, la app quiso hablar con otro Supabase, o no se pudo medir ninguna pantalla. Solo corre contra localhost.
 */

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { CUENTAS, porClave } from "./cuentas.mjs";
import { escenariosDe, ESCENARIOS } from "./escenarios/registro.mjs";
import { abrirPantalla } from "./motor/pagina.mjs";
import { escribirReporte } from "./motor/reporte.mjs";
import { inventarioDeRutas, leerMenu, moduloDeRuta } from "./motor/rutas.mjs";
import { abrirContexto, abrirNavegador, API_POR_DEFECTO, APP_POR_DEFECTO, exigirDynamic, exigirLocal, problemaDeRed } from "./motor/sesion.mjs";

const AQUI = dirname(fileURLToPath(import.meta.url));
const ESCANER = readFileSync(join(AQUI, "motor", "escaner-en-pagina.js"), "utf8");

function leerArgs(argv) {
  const a = {};
  for (let i = 0; i < argv.length; i++) {
    if (!argv[i].startsWith("--") || argv[i] === "--") continue;
    const k = argv[i].slice(2);
    const siguiente = argv[i + 1];
    if (siguiente === undefined || siguiente.startsWith("--")) a[k] = true;
    else {
      a[k] = siguiente;
      i++;
    }
  }
  return a;
}
const lista = (v) => (typeof v === "string" ? v.split(",").map((s) => s.trim()).filter(Boolean) : []);
const slug = (s) => s.replace(/^\//, "").replace(/[^a-z0-9]+/gi, "-").replace(/^-|-$/g, "") || "inicio";

/** Un error que invalida la medición sale con 2: nunca con el 1 de «hay hallazgos», ni con el 0 de «está bien». */
function medicionInvalida(mensaje) {
  console.error(`\nLa medición no vale: ${mensaje}`);
  process.exit(2);
}

const args = leerArgs(process.argv.slice(2));
const baseUrl = String(args["base-url"] || process.env.TEMA_BASE_URL || APP_POR_DEFECTO).replace(/\/$/, "");
const apiUrl = String(args["api-url"] || process.env.TEMA_API_URL || API_POR_DEFECTO).replace(/\/$/, "");
const ancho = Number(args.ancho || 1440);
const alto = Number(args.alto || 900);
const esperaMs = Number(args.espera || 1200);
const { estaticas, dinamicas } = inventarioDeRutas();
const menu = leerMenu();

if (args.listar) {
  console.log(`Cuentas:\n${CUENTAS.map((c) => `  ${c.clave.padEnd(16)} ${c.descripcion}`).join("\n")}`);
  const porModulo = new Map();
  for (const r of estaticas) {
    const m = moduloDeRuta(r, menu);
    porModulo.set(m, [...(porModulo.get(m) ?? []), r]);
  }
  console.log(`\nRutas estáticas (${estaticas.length}) por módulo:`);
  for (const [m, rutas] of [...porModulo].sort()) console.log(`  ${m}\n    ${rutas.join("\n    ")}`);
  console.log(`\nRutas dinámicas (${dinamicas.length}, solo por escenario):\n  ${dinamicas.join("\n  ")}`);
  console.log(`\nEscenarios:\n${ESCENARIOS.map((e) => `  ${e.id.padEnd(24)} ${e.ruta}  ${e.nombre}${e.soloPorId ? "  (solo por id)" : ""}`).join("\n")}`);
  process.exit(0);
}

try {
  exigirLocal(baseUrl, "La app");
  exigirLocal(apiUrl, "La API de Supabase");
  await exigirDynamic(baseUrl);
} catch (e) {
  medicionInvalida(e.message);
}

const cuentas = args.cuenta === "todas" ? CUENTAS : lista(args.cuenta || "admin").map((c) => porClave(c) ?? medicionInvalida(`no existe la cuenta «${c}». Con --listar se ven.`));
let rutas = lista(args.ruta);
if (args.modulo) {
  const pedidos = lista(args.modulo);
  const conocidos = new Set(estaticas.map((r) => moduloDeRuta(r, menu)));
  for (const m of pedidos) if (!conocidos.has(m)) medicionInvalida(`no existe el módulo «${m}». Son: ${[...conocidos].sort().join(", ")}.`);
  rutas.push(...estaticas.filter((r) => pedidos.includes(moduloDeRuta(r, menu))));
}
if (args.todas) rutas = [...estaticas];
rutas = [...new Set(rutas)];

const cuando = new Date().toISOString().replace(/[-:T]/g, "").slice(0, 12);
const dirSalida = args.salida || join(AQUI, ".salida", `${cuando.slice(0, 8)}-${cuando.slice(8)}`);

/** Lo que se visita con esa cuenta: las rutas de su alcance, o su inicio si no se pidió ninguna; y sus escenarios, si se pidieron. */
function visitasDe(cuenta) {
  const propias = rutas.length ? rutas.filter(cuenta.alcance) : args.escenario ? [] : [cuenta.inicio];
  const v = propias.map((ruta) => ({ ruta, titulo: ruta, escenario: null }));
  if (args.escenarios || args.escenario) {
    const candidatas = new Set([...propias, ...(args.escenario ? ESCENARIOS.filter((e) => e.id === args.escenario && cuenta.alcance(e.ruta)).map((e) => e.ruta) : [])]);
    for (const ruta of candidatas) {
      for (const e of escenariosDe(ruta, cuenta.clave, ancho < 700)) {
        if (args.escenario ? e.id === args.escenario : !e.soloPorId) v.push({ ruta, titulo: `${ruta} · ${e.nombre}`, escenario: e });
      }
    }
  }
  return args.escenario ? v.filter((x) => x.escenario?.id === args.escenario) : v;
}

async function visitar(ctx, cuenta, visita, tema) {
  const pagina = await ctx.newPage();
  const errores = [];
  pagina.on("console", (m) => m.type() === "error" && !/favicon|Failed to load resource/.test(m.text()) && errores.push(m.text().slice(0, 200)));
  pagina.on("pageerror", (e) => errores.push("pageerror: " + String(e).slice(0, 200)));
  const res = { tema, estado: "ok", errores };
  try {
    const { ruta: final, termino } = await abrirPantalla(pagina, baseUrl + visita.ruta, { esperaMs });
    if (final !== visita.ruta) {
      res.estado = `redirige a ${final}`;
      // Una ruta de su alcance que la manda a una entrada: la sesión no valió. No es «sin acceso»: es que no se está midiendo lo que se cree.
      if (cuenta.correo && /\/(login|vincular)$/.test(final)) res.sesionPerdida = true;
      return res;
    }
    if (!termino) {
      res.estado = "seguía en «Cargando…»";
      return res;
    }
    if (visita.escenario) {
      try {
        await visita.escenario.preparar(pagina);
        if (visita.escenario.abre) await pagina.locator(visita.escenario.abre).first().waitFor({ state: "visible", timeout: 6000 });
      } catch (e) {
        res.estado = `el escenario falló o no abrió lo que dice abrir: ${String(e.message).split("\n")[0].slice(0, 100)}`;
        return res;
      }
    }
    // Una ruta se mide con una ventana TAN ALTA como la página (tope 4000 px): así todo el texto queda «en pantalla» y el fondo se lee por el
    // orden real de pintura. Un escenario (modal, cajón) se mide con el viewport normal: redimensionar podría cerrarlo.
    if (!visita.escenario) {
      const altoPagina = await pagina.evaluate(() => document.documentElement.scrollHeight);
      await pagina.setViewportSize({ width: ancho, height: Math.min(Math.max(altoPagina, alto), 4000) });
      await pagina.waitForTimeout(400);
    }
    await pagina.addScriptTag({ content: ESCANER });
    Object.assign(res, await pagina.evaluate(() => window.__temaEscanear()));
    // Si el tema no se aplicó se estaría midiendo dos veces el mismo, y lo «solo en oscuro» quedaría siempre en cero.
    if (res.tema !== tema) {
      res.estado = `pidió ${tema} y <html data-tema> dice «${res.tema}»`;
      return res;
    }
    if (tema === "oscuro" || args["capturas-claro"]) {
      const archivo = join("capturas", cuenta.clave, `${slug(visita.escenario ? `${visita.ruta}-${visita.escenario.id}` : visita.ruta)}.${tema}.png`);
      await pagina.screenshot({ path: join(dirSalida, archivo) });
      res.captura = archivo;
    }
  } catch (e) {
    // Un fallo en UNA visita no tumba toda la auditoría: queda anotado como pantalla sin medir.
    res.estado = `falló: ${String(e.message).split("\n")[0].slice(0, 110)}`;
  } finally {
    await visita.escenario?.limpiar?.(pagina).catch(() => {});
    await pagina.close().catch(() => {});
  }
  return res;
}

const fuera = new Set();
let navegador;
const visitas = [];
try {
  navegador = await abrirNavegador();
  for (const cuenta of cuentas) {
    const lote = visitasDe(cuenta);
    if (!lote.length) continue;
    const porTema = {};
    for (const tema of args["sin-claro"] ? ["oscuro"] : ["claro", "oscuro"]) {
      const ctx = await abrirContexto(navegador, cuenta, { baseUrl, apiUrl, tema, viewport: { width: ancho, height: alto }, fuera });
      porTema[tema] = [];
      for (const v of lote) {
        process.stdout.write(`  ${cuenta.clave} · ${tema} · ${v.titulo}\n`);
        porTema[tema].push(await visitar(ctx, cuenta, v, tema));
      }
      await ctx.close();
    }
    lote.forEach((v, i) => {
      const oscuro = porTema.oscuro[i];
      const claro = porTema.claro?.[i];
      const malo = [oscuro, claro].find((r) => r && r.estado !== "ok");
      visitas.push({
        cuenta: cuenta.clave,
        titulo: v.titulo,
        ruta: v.ruta,
        estado: malo ? malo.estado : "ok",
        sesionPerdida: !!(oscuro.sesionPerdida || claro?.sesionPerdida),
        errores: [...new Set([...oscuro.errores, ...(claro?.errores ?? [])])],
        captura: oscuro.captura,
        oscuro: oscuro.estado === "ok" ? oscuro : undefined,
        claro: claro?.estado === "ok" ? claro : undefined,
      });
    });
  }
} catch (e) {
  await navegador?.close().catch(() => {});
  medicionInvalida(e.message);
}
await navegador.close();

const { hallazgos, totales, md } = escribirReporte(dirSalida, visitas, { cuando: new Date().toLocaleString("es-PE"), baseUrl, ancho, alto, fuera: [...fuera] });
console.log(`\n${md.split("\n").filter((l) => l.startsWith("|") || l.startsWith("Base:") || l.startsWith("Contraste:")).join("\n")}`);
console.log(`\nReporte y capturas: ${dirSalida}`);

const red = problemaDeRed(fuera);
if (red) medicionInvalida(red);
const perdidas = visitas.filter((v) => v.sesionPerdida);
if (perdidas.length) medicionInvalida(`la sesión no valió en ${perdidas.map((v) => `${v.cuenta} · ${v.ruta}`).join(", ")}.`);
if (!totales.medidas) medicionInvalida("no se pudo medir ninguna pantalla, y cero hallazgos sin medir nada no es un verde.");
process.exit(hallazgos > 0 ? 1 : 0);
