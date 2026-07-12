// Borra los marcajes de PRUEBA de Felipe del 11/07 (estuvo probando el terminal)
// para que pueda volver a marcar desde cero. Recalcula su jornada de ese día.
import { createClient } from "@supabase/supabase-js";
const s = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
const norm = (x) => x.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim();
const { data: personas } = await s.from("personas").select("id, nombres, apellidos");
const felipe = personas.find((x) => norm(`${x.nombres} ${x.apellidos}`).includes("felipe alvarez"));
const FECHA = "2026-07-11";
const ini = `${FECHA}T00:00:00-05:00`, fin = `${FECHA}T23:59:59-05:00`;
const { count } = await s.from("marcajes").select("id", { count: "exact", head: true })
  .eq("persona_id", felipe.id).gte("timestamp_marca", ini).lte("timestamp_marca", fin);
const { error } = await s.from("marcajes").delete()
  .eq("persona_id", felipe.id).gte("timestamp_marca", ini).lte("timestamp_marca", fin);
if (error) { console.log("error:", error.message); process.exit(1); }
await s.rpc("fn_recalcular_jornada", { p_persona_id: felipe.id, p_fecha: FECHA });
console.log(`Borrados ${count} marcajes de prueba de Felipe (${FECHA}). Ya puede marcar de nuevo.`);
