// El inventario de pantallas y a qué módulo pertenece cada una. Las dos herramientas lo comparten.
//
// Nada de esto se escribe a mano si ya vive en otro sitio: las rutas salen de las carpetas de `app/` (cada `page.tsx` es una pantalla) y los
// grupos salen del menú real (`nav-items.ts`). Se lee el TEXTO de ese archivo porque importa íconos y solo existe compilado; una pantalla
// nueva en el menú entra sola a su módulo. `tests/medidores.test.ts` compara esta lectura contra el `GRUPOS` de verdad: si alguien le cambia
// la forma al archivo, esa prueba lo dice, en vez de que aquí aparezca un menú vacío en silencio.
//
// Las rutas con segmento dinámico ([id]) no se pueden abrir sin un dato real: se listan aparte y se miden con un escenario que sabe llegar.

import { readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, relative, sep } from "node:path";
import { fileURLToPath } from "node:url";

const APP = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "app");
const NAV_ITEMS = join(APP, "(admin)", "admin", "nav-items.ts");

/** Se ven sin sesión. `/terminal/vincular` es la entrada del terminal: una Mac mini todavía sin vincular. */
export const ENTRADA = ["/", "/admin/login", "/admin/olvide-clave", "/admin/nueva-clave", "/terminal/vincular"];

/** Solo redirigen: un `/admin` o un `/terminal` no dibujan nada que se pueda medir. */
const SOLO_REDIRIGEN = ["/admin", "/terminal"];

/** El plan de la obra saca «Documentos» de «Personas»: son los papeles por persona, con su estado de firma. */
const DOCUMENTOS = ["/admin/contratos", "/admin/documentacion", "/admin/seguros"];

const MODULO_DEL_GRUPO = {
  Asistencia: "asistencia",
  Personas: "personas",
  Pago: "pago",
  Publicaciones: "publicaciones",
  Reportes: "reportes",
  Empresa: "empresa-y-configuracion",
  Configuración: "empresa-y-configuracion",
};

function paginas(dir, salida = []) {
  for (const nombre of readdirSync(dir)) {
    const ruta = join(dir, nombre);
    if (statSync(ruta).isDirectory()) {
      if (dir === APP && nombre === "api") continue;
      paginas(ruta, salida);
    } else if (nombre === "page.tsx") salida.push(dirname(ruta));
  }
  return salida;
}

export function inventarioDeRutas() {
  const estaticas = [];
  const dinamicas = [];
  for (const carpeta of paginas(APP)) {
    const segmentos = relative(APP, carpeta).split(sep).filter(Boolean);
    const url = "/" + segmentos.filter((s) => !(s.startsWith("(") && s.endsWith(")"))).join("/");
    if (SOLO_REDIRIGEN.includes(url)) continue;
    (segmentos.some((s) => s.startsWith("[")) ? dinamicas : estaticas).push(url);
  }
  return { estaticas: estaticas.sort(), dinamicas: dinamicas.sort() };
}

/** Los grupos del menú, leídos del texto de `nav-items.ts`: `[{ label, hrefs }]`. */
export function leerMenu(texto = readFileSync(NAV_ITEMS, "utf8")) {
  const desde = texto.indexOf("export const GRUPOS");
  const hasta = texto.indexOf("\n];", desde);
  if (desde < 0 || hasta < 0) throw new Error("No encontré `export const GRUPOS` en nav-items.ts: ¿le cambiaron la forma?");
  const grupos = [];
  for (const linea of texto.slice(desde, hasta).split("\n")) {
    if (linea.trim().startsWith("//")) continue;
    const grupo = linea.match(/\{\s*(?:label:\s*"([^"]+)",\s*)?items:\s*\[/);
    if (grupo) grupos.push({ label: grupo[1], hrefs: [] });
    const href = linea.match(/\bhref:\s*"([^"]+)"/);
    if (href) grupos.at(-1).hrefs.push(href[1]);
  }
  if (!grupos.length) throw new Error("Leí nav-items.ts y no salió ningún grupo: ¿le cambiaron la forma?");
  return grupos;
}

const cuelgaDe = (ruta, base) => ruta === base || ruta.startsWith(`${base}/`);

/** El módulo de una ruta. Una sub-ruta cuelga del renglón del menú más específico, igual que el resaltado del propio menú. */
export function moduloDeRuta(ruta, menu = leerMenu()) {
  if (ENTRADA.includes(ruta)) return "entrada";
  if (cuelgaDe(ruta, "/mio")) return "lo-mio";
  if (cuelgaDe(ruta, "/terminal")) return "terminal";
  if (DOCUMENTOS.some((base) => cuelgaDe(ruta, base))) return "documentos";
  let mejor = null;
  for (const grupo of menu) {
    for (const href of grupo.hrefs) {
      if (cuelgaDe(ruta, href) && (!mejor || href.length > mejor.href.length)) mejor = { href, label: grupo.label };
    }
  }
  if (!mejor) return "fuera-del-menu";
  if (!mejor.label) return "inicio";
  return MODULO_DEL_GRUPO[mejor.label] ?? mejor.label.toLowerCase();
}
