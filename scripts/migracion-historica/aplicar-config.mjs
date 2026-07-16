// Ajustes de configuración pedidos por Felipe (una sola corrida):
//  - Reasignar sede base de una persona (ver detalle en el JSON privado).
//  - visible_todas_sedes = true para todos los activos → el selector de sede del
//    terminal puede mostrar cualquier sede desde cualquier dispositivo.
//  - Horarios provisionales para 2 personas de AQP, clonados de compañeras con
//    horario similar, vigentes desde 2026-07-12. Una persona queda flexible
//    (sin horario/tardanza).
// (El PIN ya estaba desactivado en las 3 sedes; no se toca.)
// Los nombres reales viven en scripts/datos-privados/aplicar-config-nombres.json
// (EXCLUIDO del repo).
//
// Uso: SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node aplicar-config.mjs
import { createClient } from "@supabase/supabase-js";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const s = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
const norm = (x) => x.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim();

const rutaNombres = join(dirname(fileURLToPath(import.meta.url)), "..", "datos-privados", "aplicar-config-nombres.json");
let NOMBRES;
try {
  NOMBRES = JSON.parse(readFileSync(rutaNombres, "utf8"));
} catch {
  console.error(`No se pudo leer ${rutaNombres}. Crea ese archivo (no se sube al repo).`);
  process.exit(1);
}

const { data: sedes } = await s.from("sedes").select("id, codigo");
const AQP = sedes.find((x) => x.codigo === "AQP").id;
const { data: personas } = await s.from("personas").select("id, nombres, apellidos, estado");
const pid = (n) => personas.find((p) => norm(`${p.nombres} ${p.apellidos}`) === norm(n)).id;

// 1) reasignar sede
{
  const { error } = await s.from("personas").update({ sede_base_id: AQP }).eq("id", pid(NOMBRES.felipeASedeAQP));
  console.log(`1) ${NOMBRES.felipeASedeAQP} → sede AQP ${error ? "ERROR " + error.message : "✓"}`);
}

// 2) visible_todas_sedes = true en todos los activos
{
  const { error, count } = await s.from("personas").update({ visible_todas_sedes: true }, { count: "exact" }).eq("estado", "activo");
  console.log(`2) visible_todas_sedes=true en ${count} activos ${error ? "ERROR " + error.message : "✓"}`);
}

// 3) horarios provisionales
async function clonarHorario(destino, modelo, horaEntrada) {
  const { data: mod } = await s.from("horarios_asignados")
    .select("hora_salida, almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horas_semana_objetivo")
    .eq("persona_id", pid(modelo)).order("vigente_desde", { ascending: false }).limit(1).maybeSingle();
  const row = {
    persona_id: pid(destino), vigente_desde: "2026-07-12", vigente_hasta: null, hora_entrada: horaEntrada,
    hora_salida: mod?.hora_salida ?? null,
    almuerzo_min_minutos: mod?.almuerzo_min_minutos ?? 45,
    almuerzo_max_minutos: mod?.almuerzo_max_minutos ?? 75,
    dias_laborables: mod?.dias_laborables ?? null,
    horas_semana_objetivo: mod?.horas_semana_objetivo ?? 45,
  };
  const { error } = await s.from("horarios_asignados").insert(row);
  console.log(`   ${destino}: entrada ${horaEntrada} desde 2026-07-12 ${error ? "ERROR " + error.message : "✓"}`);
}
console.log("3) Horarios provisionales:");
for (const c of NOMBRES.clones) {
  await clonarHorario(c.destino, c.modelo, c.horaEntrada);
}
console.log(`   ${NOMBRES.flexibleSinHorario}: SIN horario (flexible) ✓`);
