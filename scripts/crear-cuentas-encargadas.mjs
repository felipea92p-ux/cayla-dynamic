// Crea las cuentas de login (Supabase Auth) para las encargadas/supervisoras que
// aún no tienen una, usando sus correos de scripts/datos-privados/correos.json, y
// las vincula a su persona (auth_user_id) para que el panel las reconozca con su
// rol y sede. Imprime email + contraseña temporal de cada una para que TÚ las
// distribuyas. Cada una puede cambiar su contraseña luego.
//
// Uso:
//   SUPABASE_URL="https://vovjyyiafkxteijimpuy.supabase.co" \
//   SUPABASE_SERVICE_ROLE_KEY="sb_secret_…" \
//   node scripts/crear-cuentas-encargadas.mjs
import { createClient } from "@supabase/supabase-js";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import crypto from "node:crypto";

const URL = process.env.SUPABASE_URL, SVC = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!URL || !SVC) { console.error("Faltan SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY."); process.exit(1); }
const s = createClient(URL, SVC, { auth: { persistSession: false } });
const __dir = dirname(fileURLToPath(import.meta.url));

const norm = (x) => x.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/\s+/g, " ").trim();

// correos.json -> mapa nombre normalizado -> email (soporta objeto o arreglo)
const raw = JSON.parse(readFileSync(join(__dir, "datos-privados", "correos.json"), "utf8"));
const pares = Array.isArray(raw) ? raw.map((e) => [e.nombre ?? e.name, e.correo ?? e.email ?? e.mail]) : Object.entries(raw);
const emailPorNombre = new Map(pares.map(([n, m]) => [norm(String(n)), String(m)]));

// contraseña temporal legible (sin caracteres ambiguos)
function pass() {
  const abc = "abcdefghijkmnpqrstuvwxyz", ABC = "ABCDEFGHJKLMNPQRSTUVWXYZ", num = "23456789";
  const pick = (set, n) => Array.from({ length: n }, () => set[crypto.randomInt(set.length)]).join("");
  return `${pick(ABC, 1)}${pick(abc, 5)}-${pick(num, 4)}`;
}

const { data: sedes } = await s.from("sedes").select("id, codigo");
const cod = (id) => sedes.find((x) => x.id === id)?.codigo ?? "—";
const { data: personas } = await s.from("personas").select("id, nombres, apellidos, rol, sede_base_id, auth_user_id");
const encargadas = personas.filter((p) => p.rol === "supervisor_sede" && !p.auth_user_id);

console.log(`\nEncargadas sin cuenta: ${encargadas.length}\n`);
const creadas = [];
for (const p of encargadas) {
  const nombre = `${p.nombres} ${p.apellidos}`;
  const email = emailPorNombre.get(norm(nombre));
  if (!email) { console.log(`  ⚠ ${nombre} (${cod(p.sede_base_id)}): SIN correo en correos.json — se omite`); continue; }
  const contrasena = pass();
  const { data: authData, error: e1 } = await s.auth.admin.createUser({ email, password: contrasena, email_confirm: true });
  if (e1) { console.log(`  ✗ ${nombre}: ${e1.message}`); continue; }
  const { error: e2 } = await s.from("personas").update({ auth_user_id: authData.user.id }).eq("id", p.id);
  if (e2) { console.log(`  ✗ ${nombre}: vinculado falló — ${e2.message}`); continue; }
  creadas.push({ nombre, sede: cod(p.sede_base_id), email, contrasena });
}

console.log(`\n===== CUENTAS CREADAS (${creadas.length}) — GUARDA ESTO =====`);
for (const c of creadas) console.log(`  ${c.nombre} [${c.sede}]\n     correo:      ${c.email}\n     contraseña:  ${c.contrasena}`);
console.log(`\nEntran en cayla-dynamic.vercel.app/admin/login — cada una ve solo su sede.`);
