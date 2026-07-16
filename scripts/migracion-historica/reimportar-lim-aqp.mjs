// Re-importa las horas CORREGIDAS de LIM y AQP desde las hojas nuevas de Dynamic.
// Reemplaza el histórico (origen='import_historico') de esas dos sedes por lo corregido.
//
// Reglas acordadas con Felipe:
//   - Las hojas son la fuente de la verdad para LIM y AQP (TRU no se toca).
//   - HOY (2026-07-11): 2 personas de AQP van por el TERMINAL nuevo
//     → se EXCLUYEN de la hoja de hoy (para no duplicar con el terminal).
//     Sus nombres (si hace falta identificarlas de nuevo) están en
//     scripts/datos-privados/roster.json.
//   - Para el resto, HOY manda la hoja: si el terminal ya tiene marca de HOY de esa
//     persona Y la hoja también, la hoja reemplaza (se borra la del terminal de hoy).
//   - Si alguien tiene marca de HOY en el terminal pero NO en la hoja, se conserva
//     la del terminal (usó el sistema nuevo directo).
//
// Uso:
//   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node reimportar-lim-aqp.mjs [--commit]
// Sin --commit = ENSAYO: no cambia nada, solo reporta qué haría.

import { createClient } from "@supabase/supabase-js";
import XLSX from "xlsx";
import crypto from "node:crypto";

const HOJAS_DIR =
  process.env.HOJAS_DIR ||
  "/private/tmp/claude-502/-Users-felipealvarez-Library-Mobile-Documents-com-apple-CloudDocs-INVESTMENTS/6029f165-1209-4394-adb1-0ba9d1d1a943/scratchpad/hojas-nuevas";
// Sedes y archivos configurables por entorno. Por defecto LIM/AQP (hoja-2 AQP, hoja-3 LIM);
// para TRU: SEDES=TRU ARCHIVOS=hoja-1.xlsx
const ARCHIVOS = (process.env.ARCHIVOS || "hoja-2.xlsx,hoja-3.xlsx").split(",");
const SEDES = (process.env.SEDES || "LIM,AQP").split(",");
const HOY = "2026-07-11";
// Hoy la hoja manda para todos los que la tienen (decisión revisada con Felipe: en el día
// de transición el terminal salió tarde/roto, la hoja es la fuente correcta). Quien no
// tiene dato en la hoja hoy conserva su terminal de forma natural.
const TERMINAL_HOY = new Set([]); // nadie se excluye de la hoja de hoy
const COMMIT = process.argv.includes("--commit");

const URL = process.env.SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!URL || !KEY) { console.error("Faltan SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY."); process.exit(1); }
const s = createClient(URL, KEY, { auth: { persistSession: false } });

const pad = (n) => String(n).padStart(2, "0");
const norm = (x) => x.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/\s+/g, " ").trim();
function serialAISO(serial) {
  const d = XLSX.SSF.parse_date_code(serial);
  const fecha = `${d.y}-${pad(d.m)}-${pad(d.d)}`;
  return { iso: `${fecha}T${pad(d.H)}:${pad(d.M)}:${pad(Math.round(d.S) % 60)}-05:00`, fecha };
}
// client_uuid DETERMINÍSTICO → re-correr es idempotente (no duplica).
function uuidDet(personaId, iso, tipo) {
  const h = crypto.createHash("sha256").update(`${personaId}|${iso}|${tipo}`).digest("hex");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20, 32)}`;
}
// Mapea la secuencia cruda E/S de un día a marcajes del esquema nuevo (igual que el import original).
function mapearDia(marks) {
  const ordenados = [...marks].sort((a, b) => a.iso.localeCompare(b.iso));
  const seq = [];
  for (const m of ordenados) {
    if (seq.length && seq[seq.length - 1].reg === m.reg) continue; // colapsa doble marcado
    seq.push(m);
  }
  while (seq.length && seq[0].reg === "S") seq.shift(); // quita salidas iniciales
  if (seq.length === 0) return [];
  const out = [];
  for (let i = 0; i < seq.length; i++) {
    const m = seq[i], ultimo = i === seq.length - 1;
    if (i === 0) out.push({ tipo: "entrada", iso: m.iso });
    else if (m.reg === "S") out.push({ tipo: ultimo ? "salida_final" : "salida_almuerzo", iso: m.iso });
    else out.push({ tipo: "retorno_almuerzo", iso: m.iso });
  }
  return out;
}

async function main() {
  // 1) sedes y personas de LIM/AQP
  const { data: sedes } = await s.from("sedes").select("id, codigo");
  const sedeIdPorCodigo = Object.fromEntries(sedes.map((x) => [x.codigo, x.id]));
  const idsSede = new Set(SEDES.map((c) => sedeIdPorCodigo[c]));

  const { data: personas } = await s.from("personas").select("id, nombres, apellidos, sede_base_id, estado");
  const infoPorNombre = new Map();
  const idInfo = new Map();
  for (const p of personas) {
    const codigo = Object.keys(sedeIdPorCodigo).find((c) => sedeIdPorCodigo[c] === p.sede_base_id);
    const info = { id: p.id, sedeId: p.sede_base_id, codigo, nombre: `${p.nombres} ${p.apellidos}`, estado: p.estado };
    infoPorNombre.set(norm(`${p.nombres} ${p.apellidos}`), info);
    idInfo.set(p.id, info);
  }
  const esLimAqp = (info) => info && idsSede.has(info.sedeId);

  // 2) parsear hojas (AQP + LIM), agrupar por persona/día, solo gente de LIM/AQP
  const porPersonaDia = new Map(); // id|fecha -> {personaId, fecha, marks:[]}
  const noEncontrados = new Set();
  for (const archivo of ARCHIVOS) {
    const wb = XLSX.readFile(`${HOJAS_DIR}/${archivo}`);
    const tab = wb.SheetNames.includes("DynamicTime") ? "DynamicTime" : wb.SheetNames[0];
    const rows = XLSX.utils.sheet_to_json(wb.Sheets[tab], { header: 1, raw: true, defval: "" });
    for (let i = 1; i < rows.length; i++) {
      const serial = rows[i][0], nombre = rows[i][1], reg = rows[i][2];
      if (typeof serial !== "number" || !nombre || (reg !== "Entrada" && reg !== "Salida")) continue;
      const info = infoPorNombre.get(norm(String(nombre)));
      if (!info) { noEncontrados.add(String(nombre).trim()); continue; }
      if (!esLimAqp(info)) continue; // seguridad: solo LIM/AQP
      const { iso, fecha } = serialAISO(serial);
      // HOY: Carlos y Estefany van por terminal → excluir de la hoja
      if (fecha === HOY && TERMINAL_HOY.has(norm(info.nombre))) continue;
      const clave = `${info.id}|${fecha}`;
      if (!porPersonaDia.has(clave)) porPersonaDia.set(clave, { personaId: info.id, fecha, marks: [] });
      porPersonaDia.get(clave).marks.push({ iso, reg: reg === "Entrada" ? "E" : "S" });
    }
  }

  // 3) construir marcajes a insertar
  const aInsertar = [];
  const fechasAfectadas = new Set(); // personaId|fecha
  for (const { personaId, fecha, marks } of porPersonaDia.values()) {
    const info = idInfo.get(personaId);
    for (const mk of mapearDia(marks)) {
      aInsertar.push({
        client_uuid: uuidDet(personaId, mk.iso, mk.tipo),
        persona_id: personaId, sede_id: info.sedeId,
        tipo: mk.tipo, timestamp_marca: mk.iso, origen: "import_historico",
      });
    }
    fechasAfectadas.add(`${personaId}|${fecha}`);
  }

  // 4) estado actual en prod
  const idsLimAqp = [...idInfo.values()].filter(esLimAqp).map((i) => i.id);
  const { count: histActual } = await s.from("marcajes")
    .select("id", { count: "exact", head: true })
    .in("persona_id", idsLimAqp).eq("origen", "import_historico");

  const inicioHoy = `${HOY}T00:00:00-05:00`, finHoy = `${HOY}T23:59:59-05:00`;
  const { data: termHoy } = await s.from("marcajes")
    .select("id, persona_id, tipo, timestamp_marca, origen")
    .in("persona_id", idsLimAqp).gte("timestamp_marca", inicioHoy).lte("timestamp_marca", finHoy)
    .eq("origen", "terminal");
  const termHoyPorPersona = new Map();
  for (const m of termHoy ?? []) {
    if (!termHoyPorPersona.has(m.persona_id)) termHoyPorPersona.set(m.persona_id, []);
    termHoyPorPersona.get(m.persona_id).push(m);
  }
  const hojaHoyPorPersona = new Set([...porPersonaDia.values()].filter((d) => d.fecha === HOY).map((d) => d.personaId));

  // 5) REPORTE
  console.log(`\n===== ${COMMIT ? "IMPORTACIÓN REAL" : "ENSAYO (no cambia nada)"} — LIM + AQP =====`);
  console.log(`Personas LIM/AQP: ${idsLimAqp.length}`);
  console.log(`Marcajes import_historico existentes (LIM/AQP) a BORRAR: ${histActual}`);
  console.log(`Marcajes a INSERTAR desde hojas corregidas: ${aInsertar.length}`);
  console.log(`Días persona/fecha afectados (a recalcular): ${fechasAfectadas.size}`);
  if (noEncontrados.size) console.log(`\n(nombres en hoja que NO están en el roster actual — ignorados: ${[...noEncontrados].sort().join(", ")})`);

  console.log(`\n--- HOY ${HOY} — decisión por persona ---`);
  const todosHoy = new Set([...hojaHoyPorPersona, ...termHoyPorPersona.keys()]);
  for (const pid of todosHoy) {
    const info = idInfo.get(pid);
    const enHoja = hojaHoyPorPersona.has(pid);
    const enTerm = termHoyPorPersona.has(pid);
    const esTerminalHoy = TERMINAL_HOY.has(norm(info.nombre));
    let accion;
    if (esTerminalHoy) accion = "CONSERVA terminal (hoja de hoy excluida)";
    else if (enHoja && enTerm) accion = `REEMPLAZA: borra ${termHoyPorPersona.get(pid).length} del terminal → usa la hoja`;
    else if (enHoja && !enTerm) accion = "usa la hoja";
    else if (!enHoja && enTerm) accion = "CONSERVA terminal (no hay dato en la hoja hoy)";
    console.log(`  ${info.codigo} · ${info.nombre}: hoja=${enHoja?"sí":"no"} terminal=${enTerm?"sí":"no"} → ${accion}`);
  }

  if (!COMMIT) { console.log(`\n(ENSAYO: nada cambió. Agrega --commit para aplicar.)`); return; }

  // 6) COMMIT
  console.log(`\nAplicando…`);
  // 6a) borrar import_historico de LIM/AQP
  const { error: eDel } = await s.from("marcajes").delete().in("persona_id", idsLimAqp).eq("origen", "import_historico");
  if (eDel) throw eDel;
  // 6a-bis) borrar auto_cierre y admin_correccion viejos de LIM/AQP (subproductos del
  // import anterior, en días que las hojas corregidas ya reemplazan). Recalcular sus días.
  const { data: obsoletos } = await s.from("marcajes").select("persona_id, timestamp_marca")
    .in("persona_id", idsLimAqp).in("origen", ["auto_cierre", "admin_correccion"]);
  for (const m of obsoletos ?? []) {
    const f = new Intl.DateTimeFormat("en-CA", { timeZone: "America/Lima" }).format(new Date(m.timestamp_marca));
    fechasAfectadas.add(`${m.persona_id}|${f}`);
  }
  const { error: eObs } = await s.from("marcajes").delete()
    .in("persona_id", idsLimAqp).in("origen", ["auto_cierre", "admin_correccion"]);
  if (eObs) throw eObs;
  // 6b) borrar terminal de HOY donde la hoja reemplaza (no Carlos/Estefany)
  const idsBorrarTermHoy = [...todosHoy].filter((pid) => {
    const info = idInfo.get(pid);
    return !TERMINAL_HOY.has(norm(info.nombre)) && hojaHoyPorPersona.has(pid) && termHoyPorPersona.has(pid);
  });
  if (idsBorrarTermHoy.length) {
    const { error } = await s.from("marcajes").delete()
      .in("persona_id", idsBorrarTermHoy).gte("timestamp_marca", inicioHoy).lte("timestamp_marca", finHoy).eq("origen", "terminal");
    if (error) throw error;
  }
  // 6c) insertar hojas (idempotente por client_uuid determinístico)
  for (let i = 0; i < aInsertar.length; i += 500) {
    const { error } = await s.from("marcajes").upsert(aInsertar.slice(i, i + 500), { onConflict: "client_uuid", ignoreDuplicates: true });
    if (error) throw error;
  }
  // 6d) recalcular jornadas afectadas (hojas + los días de terminal que borramos hoy)
  for (const pid of idsBorrarTermHoy) fechasAfectadas.add(`${pid}|${HOY}`);
  let ok = 0;
  for (const clave of fechasAfectadas) {
    const [pid, fecha] = clave.split("|");
    const { error } = await s.rpc("fn_recalcular_jornada", { p_persona_id: pid, p_fecha: fecha });
    if (error) throw error;
    ok++;
  }
  console.log(`\nListo. Insertados ${aInsertar.length} marcajes, ${ok} jornadas recalculadas.`);
}

main().catch((e) => { console.error(e); process.exit(1); });
