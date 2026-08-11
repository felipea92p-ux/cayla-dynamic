/**
 * Imprime el Reglamento Interno de Trabajo a PDF, con encabezado y pie propios.
 *
 * POR QUÉ NO BASTA `chrome --print-to-pdf`
 *   Esa forma imprime el pie DEL NAVEGADOR —ruta del archivo, fecha y hora de
 *   impresión— o ninguno. Un documento que se presenta ante la Autoridad de
 *   Trabajo no puede llevar impresa la ruta de una carpeta de esta Mac, y sin
 *   pie se queda sin numeración, que en 100 páginas no es un adorno: es lo que
 *   permite citar «página 47» y que la otra parte llegue al mismo sitio.
 *
 *   La numeración «X de Y» solo la da el protocolo de Chrome, con
 *   `Page.printToPDF` y sus plantillas. CSS no puede: los recuadros de margen
 *   de la especificación de medios paginados no están implementados en Chrome.
 *
 * POR QUÉ SIN DEPENDENCIAS
 *   Node 24 trae WebSocket incorporado, así que se habla con Chrome
 *   directamente. Añadir Puppeteer al repositorio por un documento que se
 *   genera de vez en cuando sería pagar 300 MB por una llamada.
 *
 * USO
 *   node scripts/reglamento-a-pdf.mjs                              → el Reglamento
 *   node scripts/reglamento-a-pdf.mjs manual-procedimiento-disciplinario
 *   node scripts/reglamento-a-pdf.mjs --todos                      → los seis
 *
 *   El argumento es el nombre del archivo en `docs/`, sin extensión. El .html
 *   tiene que existir ya: lo genera `reglamento-a-html.py`.
 *
 * DE DÓNDE SALE EL PIE DE PÁGINA
 *   Del propio HTML — su <title> y su línea de versión— y no de una constante
 *   escrita aquí. Un pie escrito a mano sobrevive a los cambios del documento
 *   sin avisar, y es justo el sitio donde nadie lo mira: seis documentos
 *   distintos habrían salido todos rotulados «Reglamento Interno de Trabajo,
 *   versión 4.0».
 */
import { spawn } from "node:child_process";
import { writeFileSync, readFileSync, existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const RAIZ = dirname(dirname(fileURLToPath(import.meta.url)));

const PREDETERMINADO = "reglamento-interno-de-trabajo";
const TODOS = [
  PREDETERMINADO,
  "manual-procedimiento-disciplinario",
  "politica-prevencion-hostigamiento-sexual",
  "resolucion-designacion-hostigamiento",
  "formato-queja-hostigamiento-sexual",
  "cargo-recepcion-reglamento",
];

const args = process.argv.slice(2).filter((a) => !a.startsWith("-"));
const SLUGS = process.argv.includes("--todos")
  ? TODOS
  : [(args[0] ?? PREDETERMINADO).replace(/\.html?$|\.md$/, "")];

const CHROME = [
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/Applications/Chromium.app/Contents/MacOS/Chromium",
  "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
].find(existsSync);

if (!CHROME) {
  console.error("No encuentro Chrome. Sin él no hay numeración de páginas.");
  process.exit(1);
}
const FALTAN = SLUGS.filter((s) => !existsSync(join(RAIZ, "docs", `${s}.html`)));
if (FALTAN.length) {
  console.error(`Falta el HTML de: ${FALTAN.join(", ")}.`);
  console.error(`Corre antes: python3 scripts/reglamento-a-html.py --todos`);
  process.exit(1);
}

// El estilo va EN LA PLANTILLA: Chrome las renderiza en un documento aparte que
// no hereda ni una regla del CSS de la página.
const ESTILO =
  "font-family: -apple-system, 'Helvetica Neue', Arial, sans-serif;" +
  "font-size: 7.5pt; color: #805c4c; width: 100%;" +
  "padding: 0 20mm; -webkit-print-color-adjust: exact;";

const ENCABEZADO = `<div style="${ESTILO} text-align: right; letter-spacing:.04em;">
  CAYLA S.A.C. &middot; RUC N.&deg; 20605964550
</div>`;

/** El rótulo del pie sale del HTML que se va a imprimir, no de una constante.
 *  El <title> da el nombre y la línea de versión da la vigencia; si el
 *  documento no declara versión —el formato de queja, por ejemplo— el pie se
 *  queda solo con el nombre en vez de heredar la del Reglamento. */
function pieDe(html) {
  const t = html.match(/<title>([\s\S]*?)<\/title>/);
  const nombre = (t ? t[1] : "Documento").replace(/\s+—\s+CAYLA S\.A\.C\.\s*$/, "").trim();
  const v = html.match(/<p class="version">([\s\S]*?)<\/p>/);
  const version = v ? v[1].replace(/<[^>]+>/g, "").trim() : "";
  const izquierda = version ? `${nombre} &middot; ${version}` : nombre;
  return `<div style="${ESTILO} display:flex; justify-content:space-between; gap:10mm;">
  <span style="overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">${izquierda}</span>
  <span style="white-space:nowrap;">P&aacute;gina <span class="pageNumber"></span> de <span class="totalPages"></span></span>
</div>`;
}

const puerto = 9333 + (process.pid % 500);
const chrome = spawn(CHROME, [
  "--headless=new",
  `--remote-debugging-port=${puerto}`,
  "--disable-gpu",
  "--no-first-run",
  "--user-data-dir=/tmp/cayla-rit-chrome",
], { stdio: "ignore" });

const esperar = (ms) => new Promise((r) => setTimeout(r, ms));

/** El endpoint tarda unas décimas en levantar; se reintenta en vez de dormir a
 *  ciegas. Y se abre una PESTAÑA: el objetivo del navegador no tiene el dominio
 *  `Page`, así que conectarse a él da «Page.enable wasn't found». */
async function endpoint(url) {
  for (let i = 0; i < 60; i++) {
    try {
      const r = await fetch(`http://127.0.0.1:${puerto}/json/new?${encodeURIComponent(url)}`,
                            { method: "PUT" });
      const j = await r.json();
      if (j.webSocketDebuggerUrl) return j.webSocketDebuggerUrl;
    } catch { /* aún no levanta */ }
    await esperar(250);
  }
  throw new Error("Chrome no abrió una pestaña de depuración.");
}

function cliente(url) {
  const ws = new WebSocket(url);
  let id = 0;
  const pendientes = new Map();
  const eventos = new Map();
  ws.addEventListener("message", (e) => {
    const m = JSON.parse(e.data);
    if (m.id && pendientes.has(m.id)) {
      const { ok, mal } = pendientes.get(m.id);
      pendientes.delete(m.id);
      m.error ? mal(new Error(m.error.message)) : ok(m.result);
    } else if (m.method && eventos.has(m.method)) {
      eventos.get(m.method)();
      eventos.delete(m.method);
    }
  });
  return {
    lista: new Promise((r) => ws.addEventListener("open", r)),
    envia: (method, params = {}) =>
      new Promise((ok, mal) => {
        const i = ++id;
        pendientes.set(i, { ok, mal });
        ws.send(JSON.stringify({ id: i, method, params }));
      }),
    espera: (method) => new Promise((r) => eventos.set(method, r)),
    cierra: () => ws.close(),
  };
}

try {
  for (const slug of SLUGS) {
    const html = join(RAIZ, "docs", `${slug}.html`);
    const pdf = join(RAIZ, "docs", `${slug}.pdf`);
    const destino = `file://${resolve(html)}`;
    // Una pestaña por documento, y se cierra al terminar. Reutilizar una sola
    // dejaba las tipografías de la anterior en caché — cómodo, pero el día que
    // dos documentos usen fuentes distintas el segundo saldría con las del
    // primero y nadie lo notaría hasta tenerlo impreso.
    const c = cliente(await endpoint(destino));
    await c.lista;
    await c.envia("Page.enable");
    const cargado = c.espera("Page.loadEventFired");
    await c.envia("Page.navigate", { url: destino });
    await cargado;
    // Las tipografías van incrustadas en base64 y tardan un instante en aplicarse.
    // Sin esta pausa el PDF sale con la tipografía de reserva y no se nota hasta
    // que alguien lo abre.
    await esperar(2500);

    const { data } = await c.envia("Page.printToPDF", {
      printBackground: true,
      displayHeaderFooter: true,
      headerTemplate: ENCABEZADO,
      footerTemplate: pieDe(readFileSync(html, "utf8")),
      paperWidth: 8.27,   // A4
      paperHeight: 11.69,
      marginTop: 0.86,
      marginBottom: 0.82,
      marginLeft: 0.79,
      marginRight: 0.79,
      preferCSSPageSize: false,
    });
    writeFileSync(pdf, Buffer.from(data, "base64"));
    c.cierra();

    const paginas = (Buffer.from(data, "base64").toString("latin1")
      .match(/\/Type\s*\/Page[^s]/g) || []).length;
    console.log(`\u2192 docs/${slug}.pdf`);
    console.log(`   ${paginas} p\u00e1ginas \u00b7 ${(Buffer.byteLength(data, "base64") / 1048576).toFixed(1)} MB`);
  }
} finally {
  chrome.kill();
}
