// La letra contra lo que de verdad tiene detrás. Lo que `tema:auditar` no puede: sobre vidrio y aurora solo suma colores planos, y su número no vale.
//
// Cómo mide: anota cada texto de la pantalla con su color, saca una captura SIN letras y compara ese color con los píxeles de su caja. Con movimiento reducido: nada a medio entrar.
//
//   node tema/pixeles.mjs --cuenta do --ancho 1440 --alto 900 --ruta /admin/turnos --ruta "/admin/dashboard|tab:Jornada" --ruta "/admin/sedes|Desactivar"
//
// Una ruta puede llevar, tras «|», qué tocar antes de medir:
//   «tab:Nombre»  toca el botón y mide toda la pantalla.
//   «Nombre»      toca el botón, y mide solo la hoja que se abre, a media altura (lo que pasa por detrás del pie de una hoja queda tapado y no se cuenta).
// Sale con código 1 si algo queda bajo 4.5:1, o 3:1 en letra grande.

import { createRequire } from "node:module";
import { porClave } from "./cuentas.mjs";
import { abrirContexto, abrirNavegador, API_POR_DEFECTO, APP_POR_DEFECTO, exigirDynamic, problemaDeRed } from "./motor/sesion.mjs";

const pedir = createRequire(import.meta.url);
const sharp = createRequire(pedir.resolve("next/package.json"))("sharp");

function leerArgumentos(argv) {
  const a = { rutas: [], cuenta: "do", ancho: 1440, alto: 900, temas: ["claro", "oscuro"], base: APP_POR_DEFECTO };
  for (let i = 0; i < argv.length; i++) {
    const x = argv[i];
    if (x === "--ruta") a.rutas.push(argv[++i]);
    else if (x === "--cuenta") a.cuenta = argv[++i];
    else if (x === "--ancho") a.ancho = Number(argv[++i]);
    else if (x === "--alto") a.alto = Number(argv[++i]);
    else if (x === "--temas") a.temas = argv[++i].split(",");
    else if (x === "--base-url") a.base = argv[++i];
    else throw new Error(`No sé qué es «${x}».`);
  }
  if (a.rutas.length === 0) throw new Error("Falta al menos una --ruta.");
  return a;
}

const lum = (c) => {
  const f = c.map((v) => {
    v /= 255;
    return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * f[0] + 0.7152 * f[1] + 0.0722 * f[2];
};
const contraste = (a, b) => {
  const x = lum(a), y = lum(b);
  return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
};

/** Corre dentro de la página: los textos visibles, con su color ya resuelto y su caja. */
function textosDeLaPagina() {
  const out = [];
  const lienzo = document.createElement("canvas").getContext("2d", { willReadFrequently: true });
  const aRgba = (s) => {
    lienzo.clearRect(0, 0, 1, 1);
    lienzo.fillStyle = "#000";
    lienzo.fillStyle = s;
    lienzo.fillRect(0, 0, 1, 1);
    const q = lienzo.getImageData(0, 0, 1, 1).data;
    return [q[0], q[1], q[2], q[3] / 255];
  };
  const pie = document.querySelector("[data-pie-hoja][data-hoja-corre]");
  const k = pie?.getBoundingClientRect();
  const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  let n;
  while ((n = w.nextNode())) {
    const t = n.textContent.trim();
    if (!t || t === "⁠") continue;
    const e = n.parentElement;
    if (!e || e.closest(".hoja, script, style, noscript, .sr-only, [aria-hidden='true'] svg")) continue;
    if (window.__solo && !e.closest(window.__solo)) continue;
    // Lo que queda dentro de un <details> cerrado no se ve, aunque el navegador le siga dando una caja.
    const plegado = e.closest("details:not([open])");
    if (plegado && !e.closest("summary")) continue;
    const c = getComputedStyle(e);
    if (c.visibility !== "visible" || c.display === "none") continue;
    const rg = document.createRange();
    rg.selectNodeContents(n);
    const r = rg.getBoundingClientRect();
    if (r.width < 2 || r.height < 2 || r.right < 0 || r.left > innerWidth) continue;
    if (pie && !pie.contains(e) && r.bottom > k.top && r.top < k.bottom) continue;
    let op = 1;
    for (let a = e; a; a = a.parentElement) op *= parseFloat(getComputedStyle(a).opacity);
    if (op < 0.1) continue;
    // Lo que un scroller o un recorte esconde no se lee, ni hay contra qué medirlo.
    const cx = r.left + r.width / 2, cy = r.top + r.height / 2;
    let oculto = false;
    for (let a = e; a && a !== document.body; a = a.parentElement) {
      const q = getComputedStyle(a);
      if (q.overflowX !== "visible" || q.overflowY !== "visible") {
        const m = a.getBoundingClientRect();
        if (cx < m.left || cx > m.right || cy < m.top || cy > m.bottom) {
          oculto = true;
          break;
        }
      }
    }
    if (oculto) continue;
    out.push({
      t: t.slice(0, 32),
      // Una hoja se mide con la foto de lo que se ve: en una foto de página entera el navegador cambia el alto de la ventana, y una hoja medida en vh se corre de donde se anotó.
      x: r.left + (window.__solo ? 0 : scrollX),
      y: r.top + (window.__solo ? 0 : scrollY),
      w: r.width,
      h: r.height,
      col: aRgba(c.color),
      op,
      tam: parseFloat(c.fontSize),
      peso: parseInt(c.fontWeight) || 400,
      dis: !!e.closest(":disabled, [aria-disabled='true']"),
      donde: `${e.tagName.toLowerCase()}.${(typeof e.className === "string" ? e.className : "").split(/\s+/).filter((x) => /^(text-|bg-|opacity|font-)/.test(x)).slice(0, 4).join(".")}`,
    });
  }
  return out;
}

const a = leerArgumentos(process.argv.slice(2));
const cuenta = porClave(a.cuenta);
if (!cuenta) throw new Error(`No existe la cuenta «${a.cuenta}».`);
await exigirDynamic(a.base);
const navegador = await abrirNavegador();
const fuera = new Set();
const malos = new Map();
let total = 0, pantallas = 0;

for (const tema of a.temas) {
  const ctx = await abrirContexto(navegador, cuenta, { baseUrl: a.base, apiUrl: API_POR_DEFECTO, tema, viewport: { width: a.ancho, height: a.alto }, fuera });
  const p = await ctx.newPage();
  await p.emulateMedia({ reducedMotion: "reduce" });
  for (const entrada of a.rutas) {
    const [ruta, accion] = entrada.split("|");
    await p.goto(a.base + ruta, { waitUntil: "networkidle", timeout: 90000 }).catch(() => {});
    await p.waitForTimeout(1300);
    await p.addStyleTag({ content: "nextjs-portal{display:none!important}" });
    if (accion?.startsWith("tab:")) {
      await p.getByRole("button", { name: accion.slice(4), exact: true }).first().click({ timeout: 6000 }).catch(() => console.log("NO PUDE", entrada));
      await p.waitForTimeout(1700);
    } else if (accion) {
      const exacto = p.getByRole("button", { name: accion, exact: true });
      await ((await exacto.count()) ? exacto : p.getByRole("button", { name: accion })).first().click({ timeout: 6000 }).catch(() => console.log("NO PUDE", entrada));
      await p.waitForTimeout(500);
      await p.evaluate(() => {
        window.__solo = "[role=dialog]";
        const h = document.querySelector("[data-hoja-vidrio] [role=dialog]");
        const c = h?.matches(".overflow-y-auto") ? h : h?.querySelector(":scope > .overflow-y-auto");
        if (c) c.scrollTop = (c.scrollHeight - c.clientHeight) / 2;
      });
      await p.waitForTimeout(200);
    }
    const textos = await p.evaluate(textosDeLaPagina);
    await p.addStyleTag({ content: "*,*::before,*::after{color:transparent!important;-webkit-text-fill-color:transparent!important;text-shadow:none!important;caret-color:transparent!important} svg,img{visibility:hidden!important} ::placeholder{color:transparent!important}" });
    await p.waitForTimeout(120);
    const soloHoja = await p.evaluate(() => Boolean(window.__solo));
    const { data, info } = await sharp(await p.screenshot({ fullPage: !soloHoja })).removeAlpha().raw().toBuffer({ resolveWithObject: true });
    const px = (x, y) => {
      const X = Math.min(info.width - 1, Math.max(0, Math.round(x))), Y = Math.min(info.height - 1, Math.max(0, Math.round(y)));
      const i = (Y * info.width + X) * 3;
      return [data[i], data[i + 1], data[i + 2]];
    };
    pantallas++;
    for (const u of textos) {
      if (u.dis) continue;
      total++;
      let peor = 99;
      for (const [fx, fy] of [[0.1, 0.5], [0.5, 0.5], [0.9, 0.5], [0.5, 0.15], [0.5, 0.85]]) {
        const f = px(u.x + u.w * fx, u.y + u.h * fy);
        const op = u.col[3] * u.op;
        const c = [0, 1, 2].map((i) => u.col[i] * op + f[i] * (1 - op));
        peor = Math.min(peor, contraste(c, f));
      }
      const umbral = u.tam >= 24 || (u.tam >= 18.66 && u.peso >= 700) ? 3 : 4.5;
      if (peor < umbral - 0.005) {
        const clave = `${tema} ${u.donde}`;
        const v = malos.get(clave) ?? { n: 0, peor: 99, ej: u.t, ruta: entrada };
        v.n++;
        if (peor < v.peor) Object.assign(v, { peor, ej: u.t, ruta: entrada });
        malos.set(clave, v);
      }
    }
  }
  await ctx.close();
}
await navegador.close();
const problema = problemaDeRed(fuera);
if (problema) throw new Error(problema);
const lista = [...malos.entries()].sort((x, y) => x[1].peor - y[1].peor);
console.log(`${a.cuenta} a ${a.ancho}: ${pantallas} pantallas, ${total} textos sobre píxeles reales · ${lista.reduce((s, [, v]) => s + v.n, 0)} bajo el mínimo`);
for (const [k, v] of lista.slice(0, 40)) console.log(v.peor.toFixed(2).padStart(6), String(v.n).padStart(4), k.slice(0, 80), `«${v.ej}»`, v.ruta);
process.exit(lista.length ? 1 : 0);
