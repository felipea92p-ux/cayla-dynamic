// Fotos para enseñarle una pantalla a Felipe, y sus láminas. Datos inventados: el candado de `motor/sesion.mjs` no deja salir de esta computadora.
//
//   node tema/fotos.mjs --salida /ruta --anchos 1440,375 --temas claro,oscuro --caso turnos=do=/admin/turnos --caso "turnos-dia=do=/admin/turnos|tab:Día"
//   node tema/fotos.mjs --lamina salida.png --ancho-celda 480 --columnas 4 --alto-max 900 foto1.png foto2.png
//
// Tras «|» va qué tocar antes de la foto, separado por «;»: «tab:Nombre» o «boton:Nombre» tocan un botón, «texto:Algo» toca lo que diga eso, «campo:Texto de ayuda=lo escrito» escribe. Con «--viewport» la foto es lo
// que se ve, no la página entera. `--base-url` apunta a otra construcción: así salen los «antes», con el interruptor apagado en otro puerto.

import { mkdirSync } from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import { porClave } from "./cuentas.mjs";
import { abrirContexto, abrirNavegador, API_POR_DEFECTO, APP_POR_DEFECTO, exigirDynamic } from "./motor/sesion.mjs";

const pedir = createRequire(import.meta.url);
const sharp = createRequire(pedir.resolve("next/package.json"))("sharp");

function leerArgumentos(argv) {
  const a = { casos: [], anchos: [1440], temas: ["claro"], base: APP_POR_DEFECTO, sueltos: [], viewport: false, anchoCelda: 480, columnas: 4, altoMax: 0 };
  for (let i = 0; i < argv.length; i++) {
    const x = argv[i];
    if (x === "--caso") a.casos.push(argv[++i]);
    else if (x === "--salida") a.salida = argv[++i];
    else if (x === "--anchos") a.anchos = argv[++i].split(",").map(Number);
    else if (x === "--temas") a.temas = argv[++i].split(",");
    else if (x === "--base-url") a.base = argv[++i];
    else if (x === "--viewport") a.viewport = true;
    else if (x === "--lamina") a.lamina = argv[++i];
    else if (x === "--ancho-celda") a.anchoCelda = Number(argv[++i]);
    else if (x === "--columnas") a.columnas = Number(argv[++i]);
    else if (x === "--alto-max") a.altoMax = Number(argv[++i]);
    else if (x.startsWith("--")) throw new Error(`No sé qué es «${x}».`);
    else a.sueltos.push(x);
  }
  return a;
}

async function hacerLamina(a) {
  const G = 14, ROT = 24;
  const celdas = [];
  for (const f of a.sueltos) {
    const m = await sharp(f).metadata();
    const recorte = a.altoMax ? Math.min(m.height, a.altoMax) : m.height;
    const input = await sharp(f).extract({ left: 0, top: 0, width: m.width, height: recorte }).resize(a.anchoCelda, null).png().toBuffer();
    celdas.push({ f, input, alto: Math.round((a.anchoCelda * recorte) / m.width) });
  }
  const filas = [];
  for (let i = 0; i < celdas.length; i += a.columnas) filas.push(celdas.slice(i, i + a.columnas));
  const altos = filas.map((c) => Math.max(...c.map((x) => x.alto)));
  const W = G + a.columnas * (a.anchoCelda + G);
  const H = G + altos.reduce((s, x) => s + x + ROT + G, 0);
  const capas = [];
  let y = G;
  filas.forEach((fila, k) => {
    fila.forEach((c, i) => {
      const x = G + i * (a.anchoCelda + G);
      const nombre = path.basename(c.f, ".png").replace(/&/g, "&amp;");
      capas.push({ input: Buffer.from(`<svg width="${a.anchoCelda}" height="${ROT}"><text x="1" y="17" font-family="Helvetica" font-size="14" font-weight="600" fill="#5a4f47">${nombre}</text></svg>`), left: x, top: y });
      capas.push({ input: c.input, left: x, top: y + ROT });
    });
    y += altos[k] + ROT + G;
  });
  await sharp({ create: { width: W, height: H, channels: 3, background: "#d8d2c8" } }).composite(capas).png().toFile(a.lamina);
  console.log(path.basename(a.lamina), W, H);
}

async function tocar(p, accion) {
  for (const paso of accion.split(";")) {
    if (paso.startsWith("tab:") || paso.startsWith("boton:")) {
      await p.getByRole("button", { name: paso.slice(paso.indexOf(":") + 1) }).first().click({ timeout: 5000 });
      await p.waitForTimeout(1400);
    } else if (paso.startsWith("texto:")) {
      await p.getByText(paso.slice(6), { exact: false }).first().click({ timeout: 5000 });
      await p.waitForTimeout(1200);
    } else if (paso.startsWith("campo:")) {
      const [ayuda, texto] = paso.slice(6).split("=");
      await p.getByPlaceholder(ayuda).first().fill(texto, { timeout: 5000 });
      await p.waitForTimeout(700);
    } else throw new Error(`No sé hacer «${paso}».`);
  }
}

const a = leerArgumentos(process.argv.slice(2));
if (a.lamina) {
  await hacerLamina(a);
} else {
  if (!a.salida || a.casos.length === 0) throw new Error("Faltan --salida y al menos un --caso.");
  mkdirSync(a.salida, { recursive: true });
  await exigirDynamic(a.base);
  const navegador = await abrirNavegador();
  const fuera = new Set();
  for (const tema of a.temas) {
    for (const ancho of a.anchos) {
      for (const caso of a.casos) {
        const [nombre, clave, ...resto] = caso.split("=");
        const rutaYAccion = resto.join("=");
        const [ruta, accion] = rutaYAccion.split("|");
        const ctx = await abrirContexto(navegador, porClave(clave), { baseUrl: a.base, apiUrl: API_POR_DEFECTO, tema, viewport: { width: ancho, height: ancho > 800 ? 900 : 812 }, fuera });
        const p = await ctx.newPage();
        await p.emulateMedia({ reducedMotion: "reduce" });
        const errores = [];
        p.on("pageerror", (e) => errores.push(String(e).slice(0, 160)));
        p.on("console", (m) => {
          if (m.type() === "error" && /hydrat/i.test(m.text())) errores.push(`HIDRATACIÓN ${m.text().slice(0, 140)}`);
        });
        await p.goto(a.base + ruta, { waitUntil: "networkidle", timeout: 120000 }).catch(() => {});
        await p.waitForTimeout(2000);
        await p.addStyleTag({ content: "nextjs-portal{display:none!important}" }).catch(() => {});
        let nota = "";
        if (accion) await tocar(p, accion).catch((e) => { nota = `NO PUDE: ${String(e).split("\n")[0].slice(0, 90)}`; });
        const lado = await p.evaluate(() => document.documentElement.scrollWidth - innerWidth);
        const signos = await p.evaluate(() => document.querySelectorAll(".vidrio-cabecera .ayuda-cab-q").length);
        await p.screenshot({ path: path.join(a.salida, `${nombre}-${tema}-${ancho}.png`), fullPage: !a.viewport });
        console.log(nombre, tema, ancho, "lado", lado, "signos", signos, nota, errores.join(" | "));
        await ctx.close();
      }
    }
  }
  await navegador.close();
}
