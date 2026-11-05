#!/usr/bin/env node
// El vigilante de la familia: mira cada hora si Retail cambió algo de diseño que le toca a Dynamic. La Action solo llama a este archivo.
//
// PROMETE: compara lo que hay en Retail con las huellas de docs/familia/compartidos.json; si algo cambió, prepara el cambio en el disco de la
//          corrida, deja que corran las pruebas y mantiene UN solo aviso (un issue que se actualiza). No publica salvo que FAMILIA_PUBLICAR=si y se
//          cumplan las tres condiciones de `puedePublicar`.
// ASUME:   que Retail es público (se lee sin clave) y que recetas.css sigue siendo solo variables (si no, envolver-recetas.mjs lo rechaza y se avisa).
// SI FALLA: Retail caído es silencio y reintento a la hora siguiente; a las 24 h de seguir ciego avisa una sola vez. Un archivo que desaparece con
//          Retail arriba NO es una caída: se avisa enseguida, porque si no el vigilante quedaría ciego para siempre creyendo que todo está bien.
//
// Uso:
//   node scripts/familia/vigilante.mjs mirar [--seco]        lo corre la Action cada hora (--seco: lee y dice, sin escribir nada)
//   node scripts/familia/vigilante.mjs avisar                lo corre la Action después de las pruebas
//   node scripts/familia/vigilante.mjs tomar [viajan|piezas|todo] [--commit SHA]    lo corre una persona al llevar un cambio de Retail a Dynamic
//   node scripts/familia/vigilante.mjs revisar-tocados       sale con error si el disco tiene algo fuera de la lista
//
// Lo que toma una decisión son funciones puras con todo por parámetro; así tests/familia-vigilante.test.ts las prueba sin red.

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { appendFileSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { envolverRecetas, RecetaRechazada, revisarContraDynamic } from "./envolver-recetas.mjs";

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
export const RUTA_COMPARTIDOS = "docs/familia/compartidos.json";
const RUTA_DEUDA = "docs/familia/deuda.json";
const RUTA_CONTRATO = "docs/familia/contrato.json";
const RUTA_GLOBALS = "apps/web/app/globals.css";
const REPO_PROPIO = "felipea92p-ux/cayla-dynamic";
const MARCA = "cayla:familia-vigilante";
const TITULO = "Vigilante de la familia: hay una diferencia con Retail";
export const HORAS_ANTES_DE_AVISAR_CEGUERA = 24;

// Perú no cambia la hora en el año, así que UTC-5 fijo es exacto. La ventana se pasa de las ~21:00 de cierre, y termina a las 05:00 y no a las 06:00
// porque desde que se arma la fusión hasta que corren db-tests y ui-tests pasan varios minutos: lo que empieza a las 05:17 no debe aterrizar con
// gente marcando.
const HORAS_DE_UTC_A_PERU = 5;
const VENTANA = { abre: 22, cierra: 5 };

export const huella = (bytes) => `sha256:${createHash("sha256").update(bytes).digest("hex")}`;
const horaPeru = (ahora) => new Date(ahora.getTime() - HORAS_DE_UTC_A_PERU * 3_600_000).getUTCHours();
const textoPeru = (ahora) => `${new Date(ahora.getTime() - HORAS_DE_UTC_A_PERU * 3_600_000).toISOString().slice(0, 16).replace("T", " ")} (hora de Perú)`;
const fechaPeru = (ahora) => new Date(ahora.getTime() - HORAS_DE_UTC_A_PERU * 3_600_000).toISOString().slice(0, 10);
const formatoJson = (objeto) => `${JSON.stringify(objeto, null, 2)}\n`;

/** ¿Las tiendas ya cerraron? `true` entre las 22:00 y las 05:00 de Perú. */
export function fueraDeHorarioDeTienda(ahora) {
  const h = horaPeru(ahora);
  return h >= VENTANA.abre || h < VENTANA.cierra;
}

/** Las dos variables del repositorio. Lo que no sea exactamente el valor pedido cuenta como el lado seguro: vigilando y sin publicar. */
export function leerInterruptores(env) {
  const limpio = (v) => String(v ?? "").trim().toLowerCase();
  return { apagado: limpio(env.FAMILIA_VIGILANTE) === "apagado", publicar: limpio(env.FAMILIA_PUBLICAR) === "si" };
}

/** Las entradas de una carpeta de GitHub resumidas en una huella: cambia si se toca, se agrega o se borra cualquier archivo. */
export function huellaDeCarpeta(entradas, excepto = []) {
  const lineas = entradas
    .filter((e) => !excepto.includes(e.name))
    .map((e) => `${e.name} ${e.sha}`)
    .sort();
  return huella(lineas.join("\n"));
}

export class RetailNoResponde extends Error {}

async function pedir(fetcher, url, opciones = {}) {
  let res;
  try {
    res = await fetcher(url, { ...opciones, signal: AbortSignal.timeout(20_000) });
  } catch (e) {
    throw new RetailNoResponde(`${url}: ${e.message}`);
  }
  if (res.status === 404) return null;
  if (!res.ok) throw new RetailNoResponde(`${url}: HTTP ${res.status}`);
  return res;
}

/** Una respuesta cortada a la mitad o una página de error en vez de JSON también es «no responde»; no es un defecto de este script. */
async function cuerpoDe(res, como) {
  try {
    return await res[como]();
  } catch (e) {
    throw new RetailNoResponde(`respuesta ilegible: ${e.message}`);
  }
}

const cabecerasApi = (token) => ({
  Accept: "application/vnd.github+json",
  "User-Agent": "cayla-familia-vigilante",
  ...(token ? { Authorization: `Bearer ${token}` } : {}),
});

/** Todo lo que hace falta de Retail, en UN mismo commit para que un push a mitad de lectura no mezcle dos versiones. */
export async function leerRetail({ fetcher, compartidos, token, commit }) {
  const { repositorio, rama } = compartidos.origen;
  const api = `https://api.github.com/repos/${repositorio}`;
  let cabeza = commit;
  if (!cabeza) {
    const r = await pedir(fetcher, `${api}/commits/${rama}`, { headers: cabecerasApi(token) });
    if (!r) throw new RetailNoResponde(`${repositorio} no existe o dejó de ser público`);
    cabeza = (await cuerpoDe(r, "json")).sha;
    if (!cabeza) throw new RetailNoResponde("GitHub no devolvió el commit de Retail");
  }
  const archivos = {};
  for (const a of compartidos.viajan) {
    const r = await pedir(fetcher, `https://raw.githubusercontent.com/${repositorio}/${cabeza}/${a.retail}`);
    archivos[a.retail] = r ? Buffer.from(await cuerpoDe(r, "arrayBuffer")) : null;
  }
  const carpetas = {};
  for (const c of compartidos.se_miran) {
    const r = await pedir(fetcher, `${api}/contents/${c.retail}?ref=${cabeza}`, { headers: cabecerasApi(token) });
    carpetas[c.retail] = r ? await cuerpoDe(r, "json") : null;
  }
  return { cabeza, archivos, carpetas };
}

/** Compara lo leído contra las huellas. `viajan` se pueden tomar solos; `tareas` hay que hacerlas a mano; `frenos` impiden tomar nada de eso. */
export function detectar({ compartidos, lectura, contratoLocal }) {
  const viajan = [];
  const tareas = [];
  const frenos = [];
  for (const a of compartidos.viajan) {
    const bytes = lectura.archivos[a.retail];
    if (bytes === null) {
      frenos.push({ ruta: a.retail, tipo: "desaparecio", huella: "", texto: `\`${a.retail}\` ya no está en Retail: se movió o se borró. Hay que corregir docs/familia/compartidos.json.` });
      continue;
    }
    const ahora = huella(bytes);
    if (ahora === a.huella) continue;
    const contenido = bytes.toString("utf8");
    if (a.forma === "identica") {
      let version = NaN;
      try { version = JSON.parse(contenido).version; } catch { /* queda NaN y frena abajo */ }
      if (!(version >= contratoLocal.version)) {
        frenos.push({ ruta: a.retail, tipo: "retail-atras", huella: ahora, texto: `\`${a.retail}\` en Retail es la versión ${version} y Dynamic ya tiene la ${contratoLocal.version}. Falta pegarla en Retail; nunca se pisa una versión nueva con una vieja.` });
        continue;
      }
    }
    viajan.push({ ...a, antes: a.huella, ahora, contenido });
  }
  for (const c of compartidos.se_miran) {
    const lista = lectura.carpetas[c.retail];
    if (!Array.isArray(lista)) {
      frenos.push({ ruta: c.retail, tipo: "desaparecio", huella: "", texto: `La carpeta \`${c.retail}\` ya no está en Retail. Hay que corregir docs/familia/compartidos.json.` });
      continue;
    }
    const ahora = huellaDeCarpeta(lista, c.excepto);
    if (ahora !== c.huella) tareas.push({ retail: c.retail, excepto: c.excepto ?? [], tomada_de: c.tomada_de, antes: c.huella, ahora });
  }
  return { cabeza: lectura.cabeza, viajan, tareas, frenos };
}

/** Lo que cambió, resumido. No lleva el commit de Retail: un push que no toca estos archivos no debe parecer novedad. */
export function firmaDe(d) {
  const partes = [
    ...d.viajan.map((v) => `viaja|${v.retail}|${v.ahora}`),
    ...d.tareas.map((t) => `tarea|${t.retail}|${t.ahora}`),
    ...d.frenos.map((f) => `freno|${f.ruta}|${f.tipo}|${f.huella}`),
  ].sort();
  return huella(partes.join("\n"));
}

/**
 * Qué hacer en esta corrida. El caso que costaría caro: un cambio llega a las 14:00, las pruebas pasan, no se publica por el horario, y a las 22:00 la
 * firma es la misma. Sin `solo_faltaba_permiso` el vigilante diría «esto ya lo vi» y nunca lo publicaría.
 */
export function decidirCorrida({ deteccion, estado, interruptores, ahora }) {
  const hayAlgo = deteccion.viajan.length + deteccion.tareas.length + deteccion.frenos.length > 0;
  if (!hayAlgo) return { accion: "al-dia", firma: null };
  const firma = firmaDe(deteccion);
  const nueva = firma !== estado.firma;
  const yaEsHora = interruptores.publicar && fueraDeHorarioDeTienda(ahora) && estado.solo_faltaba_permiso === true && estado.publicada !== firma;
  if (!nueva && !yaEsHora) return { accion: "nada", firma };
  return { accion: deteccion.viajan.length > 0 ? "probar" : "escribir", firma };
}

/** Lo que Retail no respondió. Solo escribe al empezar la caída y una vez a las 24 h: en lo normal, cero escrituras y cero avisos. */
export function decidirCaida(estado, ahora) {
  if (!estado.caido_desde) return { estado: { ...estado, caido_desde: ahora.toISOString() }, escribir: true, avisar: false };
  const horas = (ahora.getTime() - new Date(estado.caido_desde).getTime()) / 3_600_000;
  if (horas >= HORAS_ANTES_DE_AVISAR_CEGUERA && !estado.ciego_avisado) return { estado: { ...estado, ciego_avisado: true }, escribir: true, avisar: true };
  return { estado, escribir: false, avisar: false };
}

const clavesConocidasDeDeuda = (disco) =>
  JSON.parse(disco.leer(RUTA_DEUDA)).deuda.filter((l) => l.clave.startsWith("claro:")).map((l) => `--color-${l.clave.slice("claro:".length)}`);

/** Aplica al disco lo que viaja. Devuelve lo que tocó y lo que frenó; el `compartidos` nuevo no lo escribe: decide quien llama. */
export function prepararCambio({ deteccion, compartidos, disco, cuando }) {
  const nuevo = structuredClone(compartidos);
  const tocados = new Set();
  const frenos = [];
  for (const v of deteccion.viajan) {
    if (v.forma === "envuelta") {
      try {
        const generado = envolverRecetas(v.contenido, { origen: `${compartidos.origen.repositorio}@${deteccion.cabeza} ${v.retail} (${v.ahora})` });
        const motivos = revisarContraDynamic(v.contenido, { cssDeDynamic: disco.leer(RUTA_GLOBALS), conocidas: clavesConocidasDeDeuda(disco) });
        if (motivos.length > 0) {
          frenos.push(...motivos.map((m) => ({ ruta: v.retail, tipo: "receta", huella: v.ahora, texto: `\`${v.retail}\`: ${m}.` })));
          continue;
        }
        if (v.en_el_arbol) {
          disco.escribir(v.dynamic, generado);
          tocados.add(v.dynamic);
        }
      } catch (e) {
        if (!(e instanceof RecetaRechazada)) throw e;
        frenos.push({ ruta: v.retail, tipo: "receta", huella: v.ahora, texto: `\`${v.retail}\`: ${e.message}` });
        continue;
      }
    } else {
      disco.escribir(v.dynamic, v.contenido);
      tocados.add(v.dynamic);
    }
    Object.assign(nuevo.viajan.find((a) => a.retail === v.retail), { huella: v.ahora, tomada_de: deteccion.cabeza, tomada_el: cuando });
    tocados.add(RUTA_COMPARTIDOS);
  }
  return { compartidos: nuevo, tocados: [...tocados], frenos };
}

/** Los archivos que se pueden tocar sin que nadie mire: los de la lista, y nada más. */
export function fueraDeLaLista(tocados, compartidos) {
  const permitidos = new Set([RUTA_COMPARTIDOS, ...compartidos.viajan.map((a) => a.dynamic)]);
  return tocados.filter((r) => !permitidos.has(r));
}

/**
 * Las tres condiciones, y antes de ellas el permiso. Junta TODOS los motivos en vez de cortar en el primero: el aviso los dice todos. Una tarea de pieza
 * pendiente no frena: un cambio de receta no necesita que la pieza de Retail también haya llegado a Dynamic.
 */
export function puedePublicar({ interruptores, tocados, compartidos, pruebas, frenos, ahora }) {
  const motivos = [];
  if (!interruptores.publicar) motivos.push({ clave: "variable", texto: "la publicación automática está apagada (FAMILIA_PUBLICAR)" });
  const fuera = fueraDeLaLista(tocados, compartidos);
  if (fuera.length > 0) motivos.push({ clave: "fuera-de-lista", texto: `tocó archivos fuera de la lista: ${fuera.join(", ")}` });
  if (tocados.length === 0) motivos.push({ clave: "nada", texto: "no hay ningún archivo que publicar" });
  if (pruebas !== "success") motivos.push({ clave: "pruebas", texto: `las pruebas no dieron verde (${pruebas})` });
  if (frenos.length > 0) motivos.push({ clave: "frenos", texto: "hay un freno sin resolver" });
  if (!fueraDeHorarioDeTienda(ahora)) motivos.push({ clave: "horario", texto: "las tiendas están abiertas (solo entre las 22:00 y las 05:00 de Perú)" });
  return { publicar: motivos.length === 0, motivos };
}

// ── El aviso: un solo issue, que guarda en su cuerpo lo que el vigilante necesita recordar ─────────────────────

async function apiPropia({ fetcher, token, repo }, metodo, ruta, cuerpo) {
  const res = await fetcher(`https://api.github.com/repos/${repo}${ruta}`, {
    method: metodo,
    headers: { ...cabecerasApi(token), ...(cuerpo ? { "Content-Type": "application/json" } : {}) },
    ...(cuerpo ? { body: JSON.stringify(cuerpo) } : {}),
    signal: AbortSignal.timeout(20_000),
  });
  if (!res.ok) throw new Error(`GitHub de Dynamic respondió ${res.status} a ${metodo} ${ruta}`);
  return res.json();
}

function leerEstado(cuerpo) {
  const m = new RegExp(`<!-- ${MARCA} (.*?) -->`).exec(cuerpo ?? "");
  if (!m) return {};
  try { return JSON.parse(m[1]); } catch { return {}; }
}

const sinEstado = (cuerpo) => (cuerpo ?? "").replace(new RegExp(`<!-- ${MARCA} .*? -->\\n*`), "");

/** El filtro por `creator` importa: el repositorio es público y cualquiera puede abrir un issue con este mismo texto. */
async function buscarAviso(propio) {
  const lista = await apiPropia(propio, "GET", `/issues?state=all&creator=${encodeURIComponent("github-actions[bot]")}&per_page=100`);
  const hallado = lista.find((i) => !i.pull_request && (i.body ?? "").includes(`<!-- ${MARCA} `));
  if (!hallado) return null;
  return { numero: hallado.number, abierto: hallado.state === "open", cuerpo: hallado.body, estado: leerEstado(hallado.body) };
}

async function guardarAviso({ propio, aviso, estado, cuerpo, abierto }) {
  const texto = `<!-- ${MARCA} ${JSON.stringify(estado)} -->\n\n${cuerpo}`;
  if (aviso) {
    await apiPropia(propio, "PATCH", `/issues/${aviso.numero}`, { body: texto, state: abierto ? "open" : "closed" });
    return aviso.numero;
  }
  const creado = await apiPropia(propio, "POST", "/issues", { title: TITULO, body: texto });
  if (!abierto) await apiPropia(propio, "PATCH", `/issues/${creado.number}`, { state: "closed" });
  return creado.number;
}

/** Qué archivos cambiaron en cada carpeta vigilada. Es un adorno: si GitHub no contesta, el aviso sale igual con el enlace. */
async function nombrarArchivos({ fetcher, token, compartidos, deteccion }) {
  const { repositorio } = compartidos.origen;
  const salida = [];
  for (const t of deteccion.tareas) {
    const copia = { ...t, archivos: null };
    if (t.tomada_de) {
      try {
        const r = await pedir(fetcher, `https://api.github.com/repos/${repositorio}/compare/${t.tomada_de}...${deteccion.cabeza}`, { headers: cabecerasApi(token) });
        const datos = r ? await r.json() : null;
        copia.archivos = (datos?.files ?? [])
          .map((f) => f.filename)
          .filter((n) => n.startsWith(`${t.retail}/`) && !t.excepto.includes(n.slice(t.retail.length + 1)));
      } catch { /* queda sin nombres */ }
    }
    salida.push(copia);
  }
  return salida;
}

/** Lo que lee una persona. Dice qué pasó y qué hacer, en ese orden. */
export function cuerpoDelAviso({ compartidos, deteccion, tareas, pruebas, publicacion, ahora }) {
  const { repositorio } = compartidos.origen;
  const corto = deteccion.cabeza.slice(0, 7);
  const partes = [`Hay una diferencia entre Retail y lo que Dynamic tomó la última vez. Visto en [\`${corto}\`](https://github.com/${repositorio}/commit/${deteccion.cabeza}), ${textoPeru(ahora)}.`];
  if (deteccion.viajan.length > 0) {
    const lineas = deteccion.viajan.map((v) => `- \`${v.retail}\`${v.tomada_de ? ` ([ver qué cambió](https://github.com/${repositorio}/compare/${v.tomada_de}...${deteccion.cabeza}))` : ""}`);
    const resultado = { success: "Con este cambio, las pruebas dan **verde**.", failure: "Con este cambio, las pruebas dan **rojo**: no se puede tomar sin arreglarlo." }[pruebas] ?? "Las pruebas no llegaron a correr.";
    partes.push(`## Lo que viaja solo\n\n${lineas.join("\n")}\n\n${resultado}`);
  }
  if (tareas.length > 0) {
    const lineas = tareas.map((t) => {
      const enlace = t.tomada_de ? ` ([ver qué cambió](https://github.com/${repositorio}/compare/${t.tomada_de}...${deteccion.cabeza}))` : "";
      if (!t.archivos?.length) return `- [ ] \`${t.retail}\`${enlace}`;
      const nombres = t.archivos.slice(0, 25).map((n) => `  - \`${n.slice(t.retail.length + 1)}\``).join("\n");
      const resto = t.archivos.length > 25 ? `\n  - y ${t.archivos.length - 25} más` : "";
      return `- [ ] \`${t.retail}\`${enlace}\n${nombres}${resto}`;
    });
    partes.push(`## Lo que no se puede copiar: es una tarea\n\nRetail arma estas piezas con otro código (Radix, sus propias clases). Si cambió cómo funcionan, hay que llevarlo a mano; si solo cambió el aspecto, la receta ya lo trae.\n\n${lineas.join("\n")}`);
  }
  if (deteccion.frenos.length > 0) partes.push(`## Lo que frena el viaje\n\n${deteccion.frenos.map((f) => `- ${f.texto}`).join("\n")}`);
  const modo = publicacion?.publicar
    ? "Se está publicando solo: pasó las tres condiciones."
    : `No se publica nada solo${publicacion?.motivos?.length ? `: ${publicacion.motivos.map((m) => m.texto).join("; ")}` : ""}.`;
  partes.push(`## Qué hacer\n\n${modo}\n\nPara llevarlo a Dynamic, una sesión corre \`node scripts/familia/vigilante.mjs tomar viajan\` (o \`tomar piezas\` cuando ya se atendieron las tareas), y el cambio sigue el camino de siempre. Este aviso se cierra solo cuando ya no hay diferencias.`);
  return partes.join("\n\n");
}

// ── Las órdenes. Todo lo de afuera (red, disco, reloj) entra por parámetro ─────────────────────

export function discoReal(raiz = RAIZ) {
  return {
    leer: (ruta) => readFileSync(join(raiz, ruta), "utf8"),
    escribir: (ruta, texto) => {
      mkdirSync(dirname(join(raiz, ruta)), { recursive: true });
      writeFileSync(join(raiz, ruta), texto);
    },
  };
}

async function callar({ propio, ahora, registrar }) {
  try {
    const aviso = await buscarAviso(propio);
    const d = decidirCaida(aviso?.estado ?? {}, ahora);
    if (d.escribir) {
      const base = sinEstado(aviso?.cuerpo) || "Por ahora no hay nada que hacer: este aviso guarda desde cuándo Retail no responde.";
      const cuerpo = d.avisar
        ? `**El vigilante lleva más de ${HORAS_ANTES_DE_AVISAR_CEGUERA} horas sin poder leer Retail** (desde ${textoPeru(new Date(d.estado.caido_desde))}). Mientras siga así, lo que cambie allá no llega a saberse. Lo primero a mirar: si \`felipea92p-ux/cayla-retail\` sigue siendo público.\n\n${base}`
        : base;
      await guardarAviso({ propio, aviso, estado: d.estado, cuerpo, abierto: d.avisar || aviso?.abierto === true });
    }
    return { accion: d.avisar ? "ciego" : "callar", salidas: { probar: "no" } };
  } catch (e) {
    // GitHub entero caído: tampoco es un motivo para hacer ruido.
    registrar(`Tampoco pude leer el aviso de Dynamic: ${e.message}`);
    return { accion: "callar", salidas: { probar: "no" } };
  }
}

export async function mirar({ fetcher, env, ahora, disco, seco = false, registrar = console.log }) {
  const interruptores = leerInterruptores(env);
  if (interruptores.apagado) {
    registrar("El vigilante está apagado (FAMILIA_VIGILANTE=apagado): no se mira nada.");
    return { accion: "apagado", salidas: { probar: "no" } };
  }
  const compartidos = JSON.parse(disco.leer(RUTA_COMPARTIDOS));
  const propio = { fetcher, token: env.GH_TOKEN, repo: env.GITHUB_REPOSITORY || REPO_PROPIO };

  let lectura;
  try {
    lectura = await leerRetail({ fetcher, compartidos, token: env.GH_TOKEN });
  } catch (e) {
    if (!(e instanceof RetailNoResponde)) throw e;
    registrar(`Retail no responde: ${e.message}. Se reintenta a la hora siguiente.`);
    return seco ? { accion: "callar", salidas: { probar: "no" } } : callar({ propio, ahora, registrar });
  }

  const aviso = seco ? null : await buscarAviso(propio);
  let estado = aviso?.estado ?? {};
  const volvio = Boolean(estado.caido_desde);
  if (volvio) {
    // Retail volvió. Si ya se había avisado la ceguera, se olvida la firma para que el aviso se reescriba sin ese párrafo.
    estado = { ...estado, caido_desde: null, ciego_avisado: false, firma: estado.ciego_avisado ? null : estado.firma };
  }
  const deteccion = detectar({ compartidos, lectura, contratoLocal: JSON.parse(disco.leer(RUTA_CONTRATO)) });
  const decision = decidirCorrida({ deteccion, estado, interruptores, ahora });
  registrar(`Retail en ${lectura.cabeza.slice(0, 7)}: viajan ${deteccion.viajan.length}, tareas ${deteccion.tareas.length}, frenos ${deteccion.frenos.length}. Decisión: ${decision.accion}.`);
  for (const f of deteccion.frenos) registrar(`  freno: ${f.texto}`);
  for (const v of deteccion.viajan) registrar(`  viaja: ${v.retail}`);
  for (const t of deteccion.tareas) registrar(`  tarea: ${t.retail}`);
  if (seco) return { accion: decision.accion, deteccion, salidas: { probar: "no" } };

  if (decision.accion === "al-dia") {
    if (aviso && (aviso.abierto || estado.firma || volvio)) {
      await guardarAviso({ propio, aviso, estado: {}, cuerpo: `Al día con Retail desde [\`${lectura.cabeza.slice(0, 7)}\`](https://github.com/${compartidos.origen.repositorio}/commit/${lectura.cabeza}), ${textoPeru(ahora)}.`, abierto: false });
    }
    return { accion: "al-dia", salidas: { probar: "no" } };
  }
  if (decision.accion === "nada") {
    if (volvio) await guardarAviso({ propio, aviso, estado, cuerpo: sinEstado(aviso.cuerpo), abierto: aviso.abierto });
    return { accion: "nada", salidas: { probar: "no" } };
  }

  if (decision.accion === "probar") {
    const prep = prepararCambio({ deteccion, compartidos, disco, cuando: fechaPeru(ahora) });
    if (prep.frenos.length === 0) {
      disco.escribir(RUTA_COMPARTIDOS, formatoJson(prep.compartidos));
      const sinContenido = { ...deteccion, viajan: deteccion.viajan.map(({ contenido, ...v }) => v) };
      const resultado = { firma: decision.firma, deteccion: sinContenido, estado, aviso: aviso ? { numero: aviso.numero } : null };
      writeFileSync(rutaDelResultado(env), JSON.stringify(resultado));
      return { accion: "probar", salidas: { probar: "si" } };
    }
    deteccion.frenos.push(...prep.frenos);
    deteccion.viajan = [];
  }

  const tareas = await nombrarArchivos({ fetcher, token: env.GH_TOKEN, compartidos, deteccion });
  const cuerpo = cuerpoDelAviso({ compartidos, deteccion, tareas, pruebas: null, publicacion: { publicar: false, motivos: [] }, ahora });
  // `decision.firma`, no la de ahora: si la receta se rechazó, a la hora siguiente la detección vuelve a ser la misma y no hay que repetir nada.
  await guardarAviso({ propio, aviso, estado: { ...estado, firma: decision.firma, pruebas: null, solo_faltaba_permiso: false }, cuerpo, abierto: true });
  return { accion: "escribir", salidas: { probar: "no" } };
}

export async function avisar({ fetcher, env, ahora, disco, resultado, tocados }) {
  const compartidos = JSON.parse(disco.leer(RUTA_COMPARTIDOS));
  const propio = { fetcher, token: env.GH_TOKEN, repo: env.GITHUB_REPOSITORY || REPO_PROPIO };
  const pruebas = env.PRUEBAS || "skipped";
  const { deteccion, firma } = resultado;
  const publicacion = puedePublicar({ interruptores: leerInterruptores(env), tocados, compartidos, pruebas, frenos: deteccion.frenos, ahora });
  const soloFaltabaPermiso = !publicacion.publicar && publicacion.motivos.every((m) => ["variable", "horario"].includes(m.clave));
  const estado = { ...resultado.estado, firma, pruebas, solo_faltaba_permiso: soloFaltabaPermiso, publicada: publicacion.publicar ? firma : (resultado.estado.publicada ?? null) };
  const tareas = await nombrarArchivos({ fetcher, token: env.GH_TOKEN, compartidos, deteccion });
  const cuerpo = cuerpoDelAviso({ compartidos, deteccion, tareas, pruebas, publicacion, ahora });
  const numero = await guardarAviso({ propio, aviso: resultado.aviso, estado, cuerpo, abierto: true });
  return { publicacion, salidas: { publicar: publicacion.publicar ? "si" : "no", commit: deteccion.cabeza, aviso: String(numero) } };
}

/** Lo que corre una persona (o la publicación) para llevar a Dynamic lo que Retail ya tiene. Con Retail caído falla: aquí sí hay alguien mirando. */
export async function tomar({ fetcher, env, disco, cuando, que = "todo", commit, registrar = console.log }) {
  const compartidos = JSON.parse(disco.leer(RUTA_COMPARTIDOS));
  const lectura = await leerRetail({ fetcher, compartidos, token: env.GH_TOKEN, commit });
  const deteccion = detectar({ compartidos, lectura, contratoLocal: JSON.parse(disco.leer(RUTA_CONTRATO)) });
  const frenos = [...deteccion.frenos];
  let nuevo = compartidos;
  if (que !== "piezas") {
    const prep = prepararCambio({ deteccion, compartidos, disco, cuando });
    nuevo = prep.compartidos;
    frenos.push(...prep.frenos);
    for (const r of prep.tocados) registrar(`tocado: ${r}`);
  }
  if (que !== "viajan") {
    for (const t of deteccion.tareas) {
      Object.assign(nuevo.se_miran.find((c) => c.retail === t.retail), { huella: t.ahora, tomada_de: lectura.cabeza, tomada_el: cuando });
      registrar(`vista: ${t.retail}`);
    }
  }
  disco.escribir(RUTA_COMPARTIDOS, formatoJson(nuevo));
  for (const f of frenos) registrar(`frenó: ${f.texto}`);
  return { frenos, cabeza: lectura.cabeza };
}

function rutaDelResultado(env) {
  return join(env.RUNNER_TEMP || tmpdir(), "familia-vigilante.json");
}

function tocadosEnElDisco() {
  const salida = execFileSync("git", ["status", "--porcelain", "--untracked-files=all"], { cwd: RAIZ, encoding: "utf8" });
  return salida.split("\n").filter(Boolean).map((l) => l.slice(3));
}

function emitir(env, salidas) {
  if (!env.GITHUB_OUTPUT) return;
  appendFileSync(env.GITHUB_OUTPUT, Object.entries(salidas).map(([k, v]) => `${k}=${v}\n`).join(""));
}

async function principal(argv, env) {
  const [orden, ...resto] = argv;
  const disco = discoReal();
  const ahora = new Date();
  if (orden === "mirar") {
    const seco = resto.includes("--seco") || env.SECO === "true";
    const r = await mirar({ fetcher: fetch, env, ahora, disco, seco });
    emitir(env, r.salidas);
    return 0;
  }
  if (orden === "avisar") {
    const resultado = JSON.parse(readFileSync(rutaDelResultado(env), "utf8"));
    const r = await avisar({ fetcher: fetch, env, ahora, disco, resultado, tocados: tocadosEnElDisco() });
    for (const m of r.publicacion.motivos) console.log(`No se publica: ${m.texto}`);
    emitir(env, r.salidas);
    return 0;
  }
  if (orden === "tomar") {
    const que = resto.find((a) => ["viajan", "piezas", "todo"].includes(a)) ?? "todo";
    const i = resto.indexOf("--commit");
    const r = await tomar({ fetcher: fetch, env, disco, cuando: fechaPeru(ahora), que, commit: i >= 0 ? resto[i + 1] : undefined });
    console.log(`Retail en ${r.cabeza}.`);
    return r.frenos.length > 0 ? 1 : 0;
  }
  if (orden === "revisar-tocados") {
    const fuera = fueraDeLaLista(tocadosEnElDisco(), JSON.parse(disco.leer(RUTA_COMPARTIDOS)));
    for (const r of fuera) console.error(`fuera de la lista: ${r}`);
    return fuera.length > 0 ? 1 : 0;
  }
  console.error("Uso: node scripts/familia/vigilante.mjs mirar [--seco] | avisar | tomar [viajan|piezas|todo] [--commit SHA] | revisar-tocados");
  return 2;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  principal(process.argv.slice(2), process.env).then(
    (codigo) => { process.exitCode = codigo; },
    (e) => { console.error(e.message); process.exitCode = 1; },
  );
}
