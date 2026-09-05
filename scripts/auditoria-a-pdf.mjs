/**
 * Imprime un informe de auditoría (HTML) a PDF con numeración de página real.
 *
 * Generalización de reglamento-a-pdf.mjs para documentos que NO viven en
 * docs/ (una auditoría es un entregable puntual, no un documento del
 * repositorio — ver CLAUDE.md: "el PDF no vive en el repo"). Misma técnica,
 * sin dependencias nuevas: Node 24 trae WebSocket incorporado, así que se
 * habla con Chrome headless directo por su protocolo de depuración en vez de
 * instalar Puppeteer por un documento que se genera de vez en cuando.
 *
 * USO
 *   node scripts/auditoria-a-pdf.mjs <entrada.html> [salida.pdf]
 *   Si se omite <salida.pdf>, se escribe junto a la entrada con extensión .pdf
 *
 * DE DÓNDE SALE EL PIE DE PÁGINA
 *   Del <title> del propio HTML — igual que reglamento-a-pdf.mjs, para que un
 *   documento nuevo no herede un rótulo escrito a mano en este script.
 */
import { spawn } from "node:child_process";
import { writeFileSync, readFileSync, existsSync } from "node:fs";
import { resolve, extname } from "node:path";

const [, , ENTRADA, SALIDA_ARG] = process.argv;

if (!ENTRADA) {
  console.error("Uso: node scripts/auditoria-a-pdf.mjs <entrada.html> [salida.pdf]");
  process.exit(1);
}
const html = resolve(ENTRADA);
if (!existsSync(html)) {
  console.error(`No existe: ${html}`);
  process.exit(1);
}
const pdf = resolve(SALIDA_ARG ?? html.replace(new RegExp(`${extname(html)}$`), ".pdf"));

const CHROME = [
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/Applications/Chromium.app/Contents/MacOS/Chromium",
  "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
].find(existsSync);

if (!CHROME) {
  console.error("No encuentro Chrome. Sin él no hay numeración de páginas.");
  process.exit(1);
}

const ESTILO =
  "font-family: -apple-system, 'Helvetica Neue', Arial, sans-serif;" +
  "font-size: 7.5pt; color: #805c4c; width: 100%;" +
  "padding: 0 20mm; -webkit-print-color-adjust: exact;";

function pieDe(htmlTexto) {
  const t = htmlTexto.match(/<title>([\s\S]*?)<\/title>/);
  const nombre = (t ? t[1] : "Informe").trim();
  return `<div style="${ESTILO} display:flex; justify-content:space-between; gap:10mm;">
  <span style="overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">${nombre}</span>
  <span style="white-space:nowrap;">P&aacute;gina <span class="pageNumber"></span> de <span class="totalPages"></span></span>
</div>`;
}

const puerto = 9433 + (process.pid % 500);
const chrome = spawn(CHROME, [
  "--headless=new",
  `--remote-debugging-port=${puerto}`,
  "--disable-gpu",
  "--no-first-run",
  "--user-data-dir=/tmp/cayla-auditoria-chrome",
], { stdio: "ignore" });

const esperar = (ms) => new Promise((r) => setTimeout(r, ms));

async function endpoint(url) {
  for (let i = 0; i < 60; i++) {
    try {
      const r = await fetch(`http://127.0.0.1:${puerto}/json/new?${encodeURIComponent(url)}`, { method: "PUT" });
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
  const destino = `file://${html}`;
  const c = cliente(await endpoint(destino));
  await c.lista;
  await c.envia("Page.enable");
  const cargado = c.espera("Page.loadEventFired");
  await c.envia("Page.navigate", { url: destino });
  await cargado;
  await esperar(600);

  const { data } = await c.envia("Page.printToPDF", {
    printBackground: true,
    displayHeaderFooter: true,
    headerTemplate: "<div></div>",
    footerTemplate: pieDe(readFileSync(html, "utf8")),
    paperWidth: 8.27,
    paperHeight: 11.69,
    marginTop: 0.5,
    marginBottom: 0.7,
    marginLeft: 0.6,
    marginRight: 0.6,
    preferCSSPageSize: false,
  });
  writeFileSync(pdf, Buffer.from(data, "base64"));
  c.cierra();

  const paginas = (Buffer.from(data, "base64").toString("latin1").match(/\/Type\s*\/Page[^s]/g) || []).length;
  console.log(`→ ${pdf}`);
  console.log(`   ${paginas} páginas · ${(Buffer.byteLength(data, "base64") / 1048576).toFixed(1)} MB`);
} finally {
  chrome.kill();
}
