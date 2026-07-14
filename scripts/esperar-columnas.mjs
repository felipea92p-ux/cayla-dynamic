// Espera a que el API (PostgREST) reconozca las columnas nuevas de 0017/0018.
// La prueba de COLUMNA es fiable (a diferencia de las funciones). Sale 0 cuando ambas están.
import { createClient } from "@supabase/supabase-js";
const s = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY, { auth: { persistSession: false } });
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
async function ok() {
  for (const [t, c] of [["jornadas", "minutos_salida_temprana"], ["personas", "funcion"]]) {
    const { error } = await s.from(t).select(c).limit(1);
    if (/does not exist|schema cache/i.test(error?.message ?? "")) return false;
  }
  return true;
}
const MAX = 960; // ~8 h a 30s (ventana nocturna)
for (let i = 1; i <= MAX; i++) {
  if (await ok()) { console.log(`✅ LISTO — el API ya reconoce ambas columnas (intento ${i})`); process.exit(0); }
  if (i % 6 === 0) console.log(`intento ${i}/${MAX} — el API aún no las ve. Sigo esperando…`);
  await wait(30000);
}
console.log("⏳ El API sigue sin reconocerlas tras la ventana larga.");
process.exit(1);
