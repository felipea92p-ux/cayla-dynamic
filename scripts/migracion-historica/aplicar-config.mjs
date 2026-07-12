// Ajustes de configuración pedidos por Felipe (una sola corrida):
//  - Felipe Alvarez → sede AQP (aparece en Arequipa, no en Trujillo).
//  - visible_todas_sedes = true para todos los activos → el selector de sede del
//    terminal puede mostrar cualquier sede desde cualquier dispositivo.
//  - Horarios provisionales: Claudia 10:45 (clon de Luana), Estefany 14:15 (clon de
//    Paola), vigentes desde 2026-07-12. Carlos queda flexible (sin horario/tardanza).
// (El PIN ya estaba desactivado en las 3 sedes; no se toca.)
//
// Uso: SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node aplicar-config.mjs
import { createClient } from "@supabase/supabase-js";

const s = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
const norm = (x) => x.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim();

const { data: sedes } = await s.from("sedes").select("id, codigo");
const AQP = sedes.find((x) => x.codigo === "AQP").id;
const { data: personas } = await s.from("personas").select("id, nombres, apellidos, estado");
const pid = (n) => personas.find((p) => norm(`${p.nombres} ${p.apellidos}`) === norm(n)).id;

// 1) Felipe → AQP
{
  const { error } = await s.from("personas").update({ sede_base_id: AQP }).eq("id", pid("Felipe Alvarez"));
  console.log(`1) Felipe Alvarez → sede AQP ${error ? "ERROR " + error.message : "✓"}`);
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
await clonarHorario("Claudia Solórzano", "Luana Rodriguez", "10:45");
await clonarHorario("Estefany Gómez", "Paola Cahuana", "14:15");
console.log("   Carlos Espejo: SIN horario (flexible) ✓");
