// El papel que sale de cada documento: lo que importa que no cambie nunca. Toma el documento como lo vería la impresora, cuenta sus páginas en un PDF de verdad, y compara dos tomas.
//
//   node tema/papel.mjs --salida /ruta --base-url http://localhost:3100       toma todos los documentos de esa construcción
//   node tema/papel.mjs --comparar /ruta/antes /ruta/ahora                    los compara: mismas páginas y mismos píxeles, o dice dónde no
//   node tema/papel.mjs --salida /ruta --con-inventados --solo a,b            los que el entorno local no trae de fábrica: entran por un rato (papel-inventados.sql) y al terminar se borran
//
// Un documento que depende de un dato (un memo, unos cargos) se busca en su lista: si el entorno local no lo tiene, se dice, no se da por bueno. Y si dice «hojas 0», ahí no se
// llegó a ningún papel: la toma no prueba nada de ese documento.

import { spawnSync } from "node:child_process";
import { mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import { porClave } from "./cuentas.mjs";
import { abrirContexto, abrirNavegador, API_POR_DEFECTO, APP_POR_DEFECTO, exigirDynamic, problemaDeRed } from "./motor/sesion.mjs";

const pedir = createRequire(import.meta.url);
const sharp = createRequire(pedir.resolve("next/package.json"))("sharp");

/** Busca en una lista el primer enlace a un documento. */
const enlaceDe = (lista, prefijo) => async (p, base) => {
  await p.goto(base + lista, { waitUntil: "networkidle", timeout: 90000 }).catch(() => {});
  await p.waitForTimeout(1500);
  const href = await p.evaluate((x) => document.querySelector(`a[href^="${x}"]`)?.getAttribute("href") ?? null, prefijo);
  return href;
};

let idMemo = null;

/** La base local, la de scripts/local: lo único contra lo que corre esto. */
function psqlLocal(sql) {
  const r = spawnSync("psql", ["-q", "-At", "-v", "ON_ERROR_STOP=1"], {
    input: sql,
    encoding: "utf8",
    env: { ...process.env, PGHOST: "127.0.0.1", PGPORT: process.env.TEMA_PG_PUERTO || "55890", PGUSER: "postgres", PGDATABASE: "postgres" },
  });
  if (r.status !== 0) throw new Error(r.stderr);
  return r.stdout.trim();
}

const ARCHIVO_INVENTADOS = new URL("./papel-inventados.sql", import.meta.url);
function ponerInventados() {
  psqlLocal(readFileSync(ARCHIVO_INVENTADOS, "utf8").split("-- ---------- BORRAR ----------")[0]);
}
function quitarInventados() {
  const parte = readFileSync(ARCHIVO_INVENTADOS, "utf8").split("-- ---------- BORRAR ----------")[1];
  psqlLocal(parte.replace(/^-- /gm, ""));
}

const NORMA = "00000000-0000-4000-8000-0000000000a1";
const CARGOS = "00000000-0000-4000-8000-0000000000a2";
async function abrirLaLiquidacion(p) {
  await p.getByRole("button", { name: /^Revisar/ }).first().click({ timeout: 6000 });
  await p.waitForTimeout(2000);
}
const clic = (nombre) => async (p) => {
  await p.getByRole("button", { name: nombre }).first().click({ timeout: 6000 });
  await p.waitForTimeout(1000);
};

export const DOCUMENTOS = [
  { nombre: "boleta-mia", cuenta: "integrante", ruta: "/mio/boleta" },
  { nombre: "contrato-mio", cuenta: "integrante", ruta: "/mio/contrato" },
  { nombre: "bono-mio", cuenta: "integrante", ruta: "/mio/cumpleanos", tocar: async (p) => { await p.getByRole("button", { name: "Ver mi constancia firmada" }).click({ timeout: 5000 }); await p.waitForTimeout(900); } },
  { nombre: "movilidad-mia", cuenta: "integrante", ruta: "/mio/movilidad" },
  {
    nombre: "memo-mio",
    cuenta: "integrante",
    buscar: async (p, base) => {
      const href = await enlaceDe("/mio?tab=disciplina", "/mio/memo/")(p, base);
      idMemo = href?.split("/").pop() ?? null;
      return href;
    },
  },
  {
    nombre: "boleta-planilla",
    cuenta: "do",
    buscar: async () => {
      return `/admin/planilla/boleta?periodo=${psqlLocal("select id from periodos_planilla order by fecha_ini desc limit 1")}&persona=${psqlLocal("select id from personas where nombres = 'Ana' and apellidos = 'Torres Ruiz'")}`;
    },
  },
  { nombre: "hoja-de-sede", cuenta: "do", ruta: "/admin/reporte-sede" },
  { nombre: "politica", cuenta: "do", ruta: "/admin/politica-salarial" },
  { nombre: "memo-disciplina", cuenta: "do", buscar: async () => (idMemo ? `/admin/disciplina/memo/${idMemo}` : null) },
  { nombre: "contrato-visor", cuenta: "do", ruta: "/admin/contratos", tocar: async (p) => { await p.getByRole("button", { name: "Más acciones" }).first().click({ timeout: 5000 }).catch(() => p.locator("button:has-text('⋯'), button:has-text('•••')").first().click({ timeout: 4000 })); await p.waitForTimeout(300); await p.getByRole("menuitem", { name: /imprimir/i }).first().click({ timeout: 4000 }); await p.waitForTimeout(1500); } },
  { nombre: "documentacion", cuenta: "do", ruta: "/admin/documentacion", tocar: async (p) => {
      // El lote se vacía en cuanto el diálogo de impresión vuelve. Sin ese diálogo, un error aquí corta esa limpieza y deja a la vista lo que se iba a imprimir.
      await p.evaluate(() => { window.print = () => { throw new Error("la toma del papel"); }; });
      await p.getByRole("button", { name: /Imprimir pendientes/ }).first().click({ timeout: 5000 });
      await p.waitForTimeout(1500);
    } },
  {
    nombre: "liquidacion",
    cuenta: "do",
    ruta: "/admin/liquidaciones",
    tocar: async (p) => {
      await abrirLaLiquidacion(p);
      await clic("Imprimir hoja para firmar")(p);
    },
  },
  {
    nombre: "certificado-de-trabajo",
    cuenta: "do",
    ruta: "/admin/liquidaciones",
    tocar: async (p) => {
      await abrirLaLiquidacion(p);
      await clic("Certificado de trabajo")(p);
    },
  },
  {
    nombre: "constancia-de-cese",
    cuenta: "do",
    ruta: "/admin/liquidaciones",
    tocar: async (p) => {
      await abrirLaLiquidacion(p);
      await clic("Constancia de cese")(p);
    },
  },
  {
    nombre: "documentacion-hoja",
    cuenta: "do",
    ruta: "/admin/documentacion",
    tocar: async (p) => {
      await clic("+ Generar documento")(p);
      await p.getByRole("dialog").getByRole("button").filter({ hasNotText: /Cancelar|Cerrar/ }).last().click({ timeout: 6000 });
      await p.waitForTimeout(1200);
    },
  },
  { nombre: "constancias-politica", cuenta: "do", ruta: "/admin/politica-salarial/constancias" },
  { nombre: "constancias-norma", cuenta: "do", ruta: `/admin/normas/${NORMA}/constancias` },
  { nombre: "cargos-disciplina", cuenta: "do", ruta: `/admin/disciplina/cargos/${CARGOS}` },
  { nombre: "cargos-mios", cuenta: "integrante", ruta: `/mio/cargos/${CARGOS}` },
  {
    nombre: "constancia-boleta",
    cuenta: "do",
    buscar: async () => `/admin/planilla/boletas?periodo=${psqlLocal("select id from periodos_planilla order by fecha_ini desc limit 1")}`,
    tocar: async (p) => {
      // El entorno local no guarda archivos: la foto de la boleta se responde aquí, para llegar a la hoja que va debajo de ella.
      const foto = await sharp({ create: { width: 600, height: 800, channels: 3, background: "#e9e4da" } }).png().toBuffer();
      const cabeceras = { "access-control-allow-origin": "*", "access-control-allow-headers": "*" };
      await p.route("**/storage/v1/object/sign/**", (r) => {
        const m = r.request().method();
        if (m === "OPTIONS") return r.fulfill({ status: 204, headers: cabeceras });
        if (m === "POST") {
          const rutas = JSON.parse(r.request().postData() ?? "{}").paths ?? [];
          return r.fulfill({ headers: cabeceras, json: rutas.map((ruta) => ({ error: null, path: ruta, signedURL: `/object/sign/boletas/${ruta}?token=inventado` })) });
        }
        return r.fulfill({ headers: cabeceras, contentType: "image/png", body: foto });
      });
      await p.getByRole("button", { name: "Ver boleta firmada" }).first().click({ timeout: 6000 });
      await p.waitForTimeout(1200);
    },
  },
];

function leerArgumentos(argv) {
  const a = { base: APP_POR_DEFECTO, temas: ["claro"], pantalla: false };
  for (let i = 0; i < argv.length; i++) {
    const x = argv[i];
    if (x === "--salida") a.salida = argv[++i];
    else if (x === "--base-url") a.base = argv[++i];
    else if (x === "--comparar") a.comparar = [argv[++i], argv[++i]];
    else if (x === "--pantalla") a.pantalla = true;
    else if (x === "--temas") a.temas = argv[++i].split(",");
    else if (x === "--solo") a.solo = argv[++i].split(",");
    else if (x === "--ancho") a.ancho = Number(argv[++i]);
    else if (x === "--con-inventados") a.inventados = true;
    else throw new Error(`No sé qué es «${x}».`);
  }
  return a;
}

const paginasDe = (pdf) => (pdf.toString("latin1").match(/\/Type\s*\/Page[^s]/g) ?? []).length;

async function tomar(a) {
  mkdirSync(a.salida, { recursive: true });
  await exigirDynamic(a.base);
  const navegador = await abrirNavegador();
  const fuera = new Set();
  const donde = path.join(a.salida, "paginas.json");
  let paginas = {};
  try {
    paginas = JSON.parse(readFileSync(donde, "utf8"));
  } catch {
    // Primera toma en esta carpeta.
  }
  for (const doc of DOCUMENTOS) {
    if (a.solo && !a.solo.includes(doc.nombre)) continue;
    for (const tema of a.temas) {
      const ctx = await abrirContexto(navegador, porClave(doc.cuenta), { baseUrl: a.base, apiUrl: API_POR_DEFECTO, tema, viewport: { width: a.ancho ?? 1200, height: (a.ancho ?? 1200) < 700 ? 812 : 1000 }, fuera });
      const p = await ctx.newPage();
      await p.emulateMedia({ reducedMotion: "reduce" });
      await p.clock.setFixedTime(new Date("2026-11-05T15:00:00-05:00"));
      let ruta = doc.ruta;
      if (doc.buscar) ruta = await doc.buscar(p, a.base);
      if (!ruta) {
        console.log(doc.nombre, tema, "NO HAY en este entorno");
        await ctx.close();
        continue;
      }
      await p.goto(a.base + ruta, { waitUntil: "networkidle", timeout: 120000 }).catch(() => {});
      await p.waitForTimeout(2500);
      await p.addStyleTag({ content: "nextjs-portal{display:none!important}" }).catch(() => {});
      if (doc.tocar) await doc.tocar(p).catch((e) => console.log(doc.nombre, "no pude abrirlo:", String(e).split("\n")[0].slice(0, 80)));
      const hojas = await p.evaluate(() => document.querySelectorAll(".hoja").length);
      if (a.pantalla) await p.screenshot({ path: path.join(a.salida, `${doc.nombre}-${tema}-pantalla.png`), fullPage: true });
      await p.emulateMedia({ media: "print", reducedMotion: "reduce" });
      await p.waitForTimeout(250);
      await p.screenshot({ path: path.join(a.salida, `${doc.nombre}-${tema}-impreso.png`), fullPage: true });
      const pdf = await p.pdf({ format: "A4", preferCSSPageSize: true, printBackground: true });
      paginas[`${doc.nombre}-${tema}`] = paginasDe(pdf);
      console.log(doc.nombre, tema, "hojas", hojas, "páginas", paginas[`${doc.nombre}-${tema}`], ruta.slice(0, 60));
      await ctx.close();
    }
  }
  await navegador.close();
  writeFileSync(donde, JSON.stringify(paginas, null, 1));
  const problema = problemaDeRed(fuera);
  if (problema) throw new Error(problema);
}

async function comparar([x, y]) {
  let malos = 0, iguales = 0;
  const px = JSON.parse(readFileSync(path.join(x, "paginas.json"), "utf8"));
  const py = JSON.parse(readFileSync(path.join(y, "paginas.json"), "utf8"));
  for (const k of Object.keys(px)) {
    if (px[k] !== py[k]) {
      malos++;
      console.log(`${k}: páginas ${px[k]} y ${py[k]}`);
    }
  }
  for (const f of readdirSync(x).filter((n) => n.endsWith("-impreso.png")).sort()) {
    const a = await sharp(path.join(x, f)).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
    let b;
    try {
      b = await sharp(path.join(y, f)).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
    } catch {
      malos++;
      console.log(`${f}: falta en la segunda toma`);
      continue;
    }
    if (a.info.width !== b.info.width || a.info.height !== b.info.height) {
      malos++;
      console.log(`${f}: tamaños ${a.info.width}x${a.info.height} y ${b.info.width}x${b.info.height}`);
      continue;
    }
    let n = 0, m = 0, y0 = 1e9, y1 = -1;
    for (let i = 0; i < a.data.length; i += 4) {
      const d = Math.max(Math.abs(a.data[i] - b.data[i]), Math.abs(a.data[i + 1] - b.data[i + 1]), Math.abs(a.data[i + 2] - b.data[i + 2]));
      if (d > 2) {
        n++;
        m = Math.max(m, d);
        const fila = Math.floor(i / 4 / a.info.width);
        y0 = Math.min(y0, fila);
        y1 = Math.max(y1, fila);
      }
    }
    if (n === 0) iguales++;
    else {
      malos++;
      console.log(`${f}: ${n} píxeles distintos, hasta ${m}/255, entre las filas ${y0} y ${y1}`);
    }
  }
  console.log(`${iguales} papeles idénticos · ${malos} diferencias`);
  process.exit(malos ? 1 : 0);
}

const a = leerArgumentos(process.argv.slice(2));
if (a.comparar) await comparar(a.comparar);
else if (a.inventados) {
  try {
    ponerInventados();
    await tomar(a);
  } finally {
    if (!process.env.TEMA_DEJAR_INVENTADOS) quitarInventados();
  }
} else await tomar(a);
