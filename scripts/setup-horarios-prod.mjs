// Carga horarios (para tardanzas) SOLO de LIM y AQP, vigentes desde julio 2026.
// Regla de tardanza: la hora de entrada programada ES el límite (0 tolerancia):
// cualquier minuto después de esa hora cuenta como tardanza.
// hora_salida es solo referencia para el auto-cierre (estimada; ajustar luego).
// Tras cargar, recalcula las jornadas de julio para que la tardanza aparezca.
// Los horarios por persona viven en scripts/datos-privados/horarios-prod.json
// (EXCLUIDO del repo).
import { createClient } from "@supabase/supabase-js";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const BASE = process.env.SUPABASE_URL, SVC = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!BASE || !SVC) { console.error("Faltan SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY."); process.exit(1); }
const s = createClient(BASE, SVC, { auth: { persistSession: false } });

// horarios por persona (nombre exacto en la BD). vigente_desde/hasta en fechas Lima.
// Un tramo con vigente_hasta null = el vigente actual.
const rutaHorarios = join(dirname(fileURLToPath(import.meta.url)), "datos-privados", "horarios-prod.json");
let HORARIOS;
try {
  HORARIOS = JSON.parse(readFileSync(rutaHorarios, "utf8"));
} catch {
  console.error(`No se pudo leer ${rutaHorarios}. Crea ese archivo (no se sube al repo).`);
  process.exit(1);
}

async function main() {
  const { data: personas } = await s.from("personas").select("id, nombres, apellidos");
  const idPorNombre = new Map(personas.map((p) => [`${p.nombres} ${p.apellidos}`, p.id]));

  const afectados = [];
  for (const [nombre, tramos] of Object.entries(HORARIOS)) {
    const pid = idPorNombre.get(nombre);
    if (!pid) { console.log(`  (no encontrado: ${nombre})`); continue; }
    // limpiar horarios previos de esta persona (idempotente)
    await s.from("horarios_asignados").delete().eq("persona_id", pid);
    for (const t of tramos) {
      const { error } = await s.from("horarios_asignados").insert({
        persona_id: pid, vigente_desde: t.desde, vigente_hasta: t.hasta,
        hora_entrada: t.entrada, hora_salida: t.salida,
      });
      if (error) throw new Error(`${nombre}: ${error.message}`);
    }
    afectados.push({ pid, nombre });
    console.log(`  ${nombre}: ${tramos.map((t) => `${t.entrada} (desde ${t.desde})`).join(" · ")}`);
  }

  // recalcular jornadas de julio de los afectados (el trigger no se dispara al cambiar horario)
  console.log("\nRecalculando tardanzas de julio…");
  for (const { pid } of afectados) {
    const { data: js } = await s.from("jornadas").select("fecha").eq("persona_id", pid).gte("fecha", "2026-07-01");
    for (const j of js ?? []) {
      const { error } = await s.rpc("fn_recalcular_jornada", { p_persona_id: pid, p_fecha: j.fecha });
      if (error) throw new Error(`recalc ${pid} ${j.fecha}: ${error.message}`);
    }
  }
  console.log("Listo.");
}

main().catch((e) => { console.error(e); process.exit(1); });
