// Lee las pestañas por persona del archivo de horarios de TRU y crea un turno
// por día (hora de entrada = primer bloque ocupado; salida = último bloque).
// Solo desde julio 2026 (tardanzas de este mes en adelante).
// El mapeo pestaña -> "Nombres Apellidos" vive en
// scripts/datos-privados/tab-a-persona-tru.json (EXCLUIDO del repo).
//
// Uso: SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
//      node scripts/migracion-historica/importar-turnos-tru.mjs <archivo.xlsx> [--commit]
import { createClient } from "@supabase/supabase-js";
import XLSX from "xlsx";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const [archivo, ...flags] = process.argv.slice(2);
const COMMIT = flags.includes("--commit");
const DESDE = "2026-07-01";
if (!archivo) { console.error("Falta el archivo .xlsx"); process.exit(1); }
const BASE = process.env.SUPABASE_URL, SVC = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!BASE || !SVC) { console.error("Faltan SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY."); process.exit(1); }
const s = createClient(BASE, SVC, { auth: { persistSession: false } });

const rutaTabAPersona = join(dirname(fileURLToPath(import.meta.url)), "..", "datos-privados", "tab-a-persona-tru.json");
let TAB_A_PERSONA;
try {
  TAB_A_PERSONA = JSON.parse(readFileSync(rutaTabAPersona, "utf8"));
} catch {
  console.error(`No se pudo leer ${rutaTabAPersona}. Crea ese archivo (no se sube al repo).`);
  process.exit(1);
}
const pad = (n) => String(n).padStart(2, "0");
const hhmm = (s) => {
  const v = String(s ?? "").trim();
  if (!v.includes(":")) return null;
  const [h, m] = v.split(":");
  if (h === "" || m === undefined || m === "") return null;
  return `${pad(h)}:${pad(m)}`;
};
function fechaISO(dmy) { const [d, m, y] = String(dmy).split("/").map(Number); return `${y}-${pad(m)}-${pad(d)}`; }

async function main() {
  const { data: personas } = await s.from("personas").select("id, nombres, apellidos");
  const idPorNombre = new Map(personas.map((p) => [`${p.nombres} ${p.apellidos}`, p.id]));
  const wb = XLSX.readFile(archivo);

  const turnos = [];
  for (const [tab, nombre] of Object.entries(TAB_A_PERSONA)) {
    if (!wb.SheetNames.includes(tab)) { console.log(`  (sin pestaña: ${tab})`); continue; }
    const pid = idPorNombre.get(nombre);
    if (!pid) { console.log(`  (no en BD: ${nombre})`); continue; }
    const rows = XLSX.utils.sheet_to_json(wb.Sheets[tab], { header: 1, raw: false, defval: "" });
    const fechas = rows[0].slice(2); // col 2+ = fechas
    for (let c = 0; c < fechas.length; c++) {
      const col = c + 2;
      const fecha = fechaISO(fechas[c]);
      if (!fechas[c] || fecha < DESDE) continue;
      let entrada = null, salida = null;
      for (let r = 2; r < rows.length; r++) {
        const ocupado = String(rows[r][col] ?? "").trim() !== "";
        if (ocupado) {
          const ini = hhmm(rows[r][0]), fin = hhmm(rows[r][1]);
          if (!entrada && ini) entrada = ini; // inicio del primer bloque válido
          if (fin) salida = fin;              // fin del último bloque válido
        }
      }
      if (entrada) turnos.push({ persona_id: pid, fecha, hora_entrada: entrada, hora_salida: salida });
    }
    console.log(`  ${nombre}: ${turnos.filter((t) => t.persona_id === pid).length} turnos`);
  }

  console.log(`\n${COMMIT ? "IMPORTANDO" : "ENSAYO"} — ${turnos.length} turnos (desde ${DESDE})`);
  if (!COMMIT) { console.log("(agrega --commit para escribir)"); return; }

  // upsert turnos
  for (let i = 0; i < turnos.length; i += 500) {
    const { error } = await s.from("turnos").upsert(turnos.slice(i, i + 500), { onConflict: "persona_id,fecha" });
    if (error) throw error;
  }
  // recalcular jornadas afectadas
  const afectadas = [...new Set(turnos.map((t) => `${t.persona_id}|${t.fecha}`))];
  for (const k of afectadas) {
    const [pid, fecha] = k.split("|");
    const { error } = await s.rpc("fn_recalcular_jornada", { p_persona_id: pid, p_fecha: fecha });
    if (error) throw error;
  }
  console.log(`Listo: ${turnos.length} turnos, ${afectadas.length} jornadas recalculadas.`);
}

main().catch((e) => { console.error(e); process.exit(1); });
