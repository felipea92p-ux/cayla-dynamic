// Carga el roster real de CAYLA al proyecto Supabase de producción.
// Se corre UNA sola vez. Genera PIN aleatorio único por persona y los imprime
// (guardar esa salida — los PIN se almacenan solo como hash bcrypt).
// El roster (nombres, sede, rol, email de quienes entran al panel) vive en
// scripts/datos-privados/roster.json (EXCLUIDO del repo).
import { createClient } from "@supabase/supabase-js";
import bcrypt from "bcryptjs";
import crypto from "node:crypto";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error("Faltan SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY.");
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const rutaRoster = join(dirname(fileURLToPath(import.meta.url)), "datos-privados", "roster.json");
let ROSTER;
try {
  ROSTER = JSON.parse(readFileSync(rutaRoster, "utf8"));
} catch {
  console.error(`No se pudo leer ${rutaRoster}. Crea ese archivo (no se sube al repo).`);
  process.exit(1);
}

function generarPinUnico(usados) {
  // evita PINs triviales y repetidos
  const triviales = new Set(["0000", "1111", "2222", "3333", "4444", "5555", "6666", "7777", "8888", "9999", "1234", "4321", "0123"]);
  let pin;
  do {
    pin = String(crypto.randomInt(0, 10000)).padStart(4, "0");
  } while (usados.has(pin) || triviales.has(pin));
  usados.add(pin);
  return pin;
}

function generarPassword() {
  return crypto.randomBytes(12).toString("base64url");
}

async function main() {
  const { data: existentes, error: exError } = await supabase.from("personas").select("id");
  if (exError) throw exError;
  if (existentes.length > 0) {
    console.error(`ABORTADO: ya existen ${existentes.length} personas en producción. Este script es de carga inicial única.`);
    process.exit(1);
  }

  const { data: sedesRows, error: sedesError } = await supabase.from("sedes").select("id, codigo");
  if (sedesError) throw sedesError;
  const sedeIdPorCodigo = Object.fromEntries(sedesRows.map((s) => [s.codigo, s.id]));

  const pinsUsados = new Set();
  const salidaPins = [];
  const salidaAdmins = [];

  for (const p of ROSTER) {
    const pin = generarPinUnico(pinsUsados);
    const pinHash = await bcrypt.hash(pin, 10);

    let authUserId = null;
    if (p.email) {
      const password = generarPassword();
      const { data: authData, error: authError } = await supabase.auth.admin.createUser({
        email: p.email,
        password,
        email_confirm: true,
      });
      if (authError) throw new Error(`creando login ${p.email}: ${authError.message}`);
      authUserId = authData.user.id;
      salidaAdmins.push({ nombre: `${p.nombres} ${p.apellidos}`, email: p.email, password });
    }

    const { error } = await supabase.from("personas").insert({
      nombres: p.nombres,
      apellidos: p.apellidos,
      sede_base_id: sedeIdPorCodigo[p.sede],
      rol: p.rol,
      pin_hash: pinHash,
      auth_user_id: authUserId,
    });
    if (error) throw new Error(`insertando ${p.nombres} ${p.apellidos}: ${error.message}`);

    salidaPins.push({ sede: p.sede, nombre: `${p.nombres} ${p.apellidos}`, rol: p.rol, pin });
  }

  console.log("=== PINs por persona (repartir individualmente) ===");
  for (const s of salidaPins) {
    console.log(`${s.sede} | ${s.nombre} | ${s.rol} | PIN: ${s.pin}`);
  }
  console.log("\n=== Logins del panel de administración ===");
  for (const a of salidaAdmins) {
    console.log(`${a.nombre} | ${a.email} | contraseña: ${a.password}`);
  }
  console.log(`\nListo: ${salidaPins.length} personas cargadas.`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
