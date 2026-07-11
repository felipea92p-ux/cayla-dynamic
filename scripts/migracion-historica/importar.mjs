// Importa el histórico de Dynamic (3 hojas .xlsx) al esquema nuevo.
// SOLO las personas del roster actual (roster-actual.json). Mapea Entrada/Salida
// crudas a la máquina de estados (entrada / salida_almuerzo+retorno_almuerzo / salida_final)
// y marca los días con patrón anómalo para revisión.
//
// Uso:
//   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
//   node scripts/migracion-historica/importar.mjs <carpetaXlsx> <YYYY-MM|todo> [--commit]
//
// Sin --commit hace un ENSAYO (no inserta; solo reporta). Con --commit inserta de verdad.
import { createClient } from "@supabase/supabase-js";
import XLSX from "xlsx";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dir = dirname(fileURLToPath(import.meta.url));
const [carpeta, mesArg, ...flags] = process.argv.slice(2);
const COMMIT = flags.includes("--commit");
if (!carpeta || !mesArg) {
  console.error("Uso: node importar.mjs <carpetaXlsx> <YYYY-MM|todo> [--commit]");
  process.exit(1);
}
const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SUPABASE_URL || !SERVICE) { console.error("Faltan SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY."); process.exit(1); }

const supabase = createClient(SUPABASE_URL, SERVICE, { auth: { persistSession: false } });
const roster = JSON.parse(readFileSync(join(__dir, "roster-actual.json"), "utf8"));
const norm = (s) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/\s+/g, " ").trim();
const rosterPorNombre = new Map(roster.map((p) => [norm(`${p.nombres} ${p.apellidos}`), p]));
const pad = (n) => String(n).padStart(2, "0");

// serial de Excel -> ISO Lima (-05:00), hora de pared exacta
function serialAISO(serial) {
  const d = XLSX.SSF.parse_date_code(serial);
  return { iso: `${d.y}-${pad(d.m)}-${pad(d.d)}T${pad(d.H)}:${pad(d.M)}:${pad(Math.round(d.S) % 60)}-05:00`, y: d.y, m: d.m, d: d.d };
}

// Lee las 3 hojas, filtra al mes, agrupa por persona/día
function leerMarcajesCrudos() {
  const porPersonaDia = new Map(); // clave: normNombre|YYYY-MM-DD -> {nombre, fecha, marks:[{ts,reg}]}
  for (const sede of ["TRU", "LIM", "AQP"]) {
    const wb = XLSX.readFile(join(carpeta, `${sede}.xlsx`));
    const rows = XLSX.utils.sheet_to_json(wb.Sheets["DynamicTime"], { header: 1, raw: true, defval: "" });
    for (let i = 1; i < rows.length; i++) {
      const serial = rows[i][0], nombre = rows[i][1], reg = rows[i][2];
      if (typeof serial !== "number" || !nombre || (reg !== "Entrada" && reg !== "Salida")) continue;
      const n = norm(nombre);
      if (!rosterPorNombre.has(n)) continue; // solo personas actuales
      const t = serialAISO(serial);
      if (mesArg !== "todo") {
        const [ay, am] = mesArg.split("-").map(Number);
        if (t.y !== ay || t.m !== am) continue;
      }
      const fecha = `${t.y}-${pad(t.m)}-${pad(t.d)}`;
      const clave = `${n}|${fecha}`;
      if (!porPersonaDia.has(clave)) porPersonaDia.set(clave, { normNombre: n, fecha, marks: [] });
      porPersonaDia.get(clave).marks.push({ ts: t.iso, reg: reg === "Entrada" ? "E" : "S" });
    }
  }
  return porPersonaDia;
}

// Mapea la secuencia cruda E/S de un día a marcajes del esquema nuevo.
// Devuelve { marcajes:[{tipo,ts}], anomalias:[...] }
function mapearDia(marks) {
  const anomalias = [];
  const ordenados = [...marks].sort((a, b) => a.ts.localeCompare(b.ts));
  // colapsar duplicados consecutivos del mismo tipo (doble marcado)
  const seq = [];
  for (const m of ordenados) {
    if (seq.length && seq[seq.length - 1].reg === m.reg) { anomalias.push(`doble ${m.reg}`); continue; }
    seq.push(m);
  }
  // quitar S iniciales (día que empieza con salida)
  while (seq.length && seq[0].reg === "S") { anomalias.push("empieza con Salida"); seq.shift(); }
  if (seq.length === 0) return { marcajes: [], anomalias: [...anomalias, "sin entrada válida"] };

  const marcajes = [];
  const terminaEnEntrada = seq[seq.length - 1].reg === "E";
  // seq ahora empieza en E. Recorremos.
  for (let i = 0; i < seq.length; i++) {
    const esUltimo = i === seq.length - 1;
    const m = seq[i];
    if (i === 0) { marcajes.push({ tipo: "entrada", ts: m.ts }); continue; }
    if (m.reg === "S") {
      marcajes.push({ tipo: esUltimo ? "salida_final" : "salida_almuerzo", ts: m.ts });
    } else { // E intermedia = regreso de una pausa
      marcajes.push({ tipo: "retorno_almuerzo", ts: m.ts });
    }
  }
  if (terminaEnEntrada) anomalias.push("no marcó salida final (jornada abierta)");
  return { marcajes, anomalias };
}

async function main() {
  // roster en la BD destino (por nombre normalizado)
  const { data: personasDB, error } = await supabase.from("personas").select("id, nombres, apellidos, sede_base_id");
  if (error) throw error;
  const idPorNombre = new Map(personasDB.map((p) => [norm(`${p.nombres} ${p.apellidos}`), p.id]));

  const dias = leerMarcajesCrudos();
  let totalMarcajes = 0, diasConAnomalia = 0, diasTotal = 0;
  const anomaliasPorPersona = new Map();
  const insertBuffer = [];

  for (const { normNombre, fecha, marks } of dias.values()) {
    const personaId = idPorNombre.get(normNombre);
    if (!personaId) continue; // no está en la BD destino
    diasTotal++;
    const { marcajes, anomalias } = mapearDia(marks);
    if (anomalias.length) {
      diasConAnomalia++;
      anomaliasPorPersona.set(normNombre, (anomaliasPorPersona.get(normNombre) || 0) + 1);
    }
    const sede = personasDB.find((p) => p.id === personaId).sede_base_id;
    for (const mk of marcajes) {
      totalMarcajes++;
      insertBuffer.push({
        client_uuid: crypto.randomUUID(), persona_id: personaId, sede_id: sede,
        tipo: mk.tipo, timestamp_marca: mk.ts, origen: "import_historico",
      });
    }
  }

  console.log(`\n=== ${COMMIT ? "IMPORTACIÓN" : "ENSAYO (no inserta)"} — mes: ${mesArg} ===`);
  console.log(`Días persona/fecha: ${diasTotal} | con alguna anomalía: ${diasConAnomalia} | marcajes a crear: ${totalMarcajes}`);
  if (anomaliasPorPersona.size) {
    console.log("Días con anomalías por persona (revisar):");
    [...anomaliasPorPersona.entries()].sort((a, b) => b[1] - a[1]).forEach(([n, c]) => console.log(`  ${n}: ${c} día(s)`));
  }

  if (COMMIT) {
    for (let i = 0; i < insertBuffer.length; i += 500) {
      const lote = insertBuffer.slice(i, i + 500);
      const { error: e } = await supabase.from("marcajes").insert(lote);
      if (e) throw new Error(`insertando lote ${i}: ${e.message}`);
    }
    console.log(`\nInsertados ${insertBuffer.length} marcajes. Las jornadas se calcularon por trigger.`);
  } else {
    console.log("\n(ENSAYO: no se insertó nada. Agrega --commit para importar de verdad.)");
  }
}

main().catch((e) => { console.error(e); process.exit(1); });
