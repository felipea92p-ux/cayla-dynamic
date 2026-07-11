// Carga el roster real de CAYLA al proyecto Supabase de producción.
// Se corre UNA sola vez. Genera PIN aleatorio único por persona y los imprime
// (guardar esa salida — los PIN se almacenan solo como hash bcrypt).
import { createClient } from "@supabase/supabase-js";
import bcrypt from "bcryptjs";
import crypto from "node:crypto";

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error("Faltan SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY.");
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

// email solo para quienes entran al panel de administración
const ROSTER = [
  // TRU
  { nombres: "Felipe", apellidos: "Alvarez", sede: "TRU", rol: "admin", email: "felipe.a92p@gmail.com" },
  { nombres: "Janis", apellidos: "Revilla", sede: "TRU", rol: "supervisor_sede" },
  { nombres: "Chiara", apellidos: "Flores", sede: "TRU", rol: "supervisor_sede" },
  { nombres: "Danitza", apellidos: "Gutiérrez", sede: "TRU", rol: "supervisor_sede" },
  { nombres: "Keyla", apellidos: "Ramos", sede: "TRU", rol: "integrante" },
  { nombres: "Dayana", apellidos: "Quispe", sede: "TRU", rol: "integrante" },
  { nombres: "Melany", apellidos: "Enriquez", sede: "TRU", rol: "integrante" },
  { nombres: "Diana", apellidos: "Palacios", sede: "TRU", rol: "integrante" },
  { nombres: "Danixa", apellidos: "Valverde", sede: "TRU", rol: "integrante" },
  { nombres: "Angie", apellidos: "Chavez", sede: "TRU", rol: "integrante" },
  { nombres: "Alessandra", apellidos: "Valdiviezo", sede: "TRU", rol: "integrante" },
  // AQP
  { nombres: "Carlos", apellidos: "Espejo", sede: "AQP", rol: "admin", email: "carlos.espejo@cayla.dev" },
  { nombres: "Sandra", apellidos: "Ramirez", sede: "AQP", rol: "supervisor_sede" },
  { nombres: "Estefany", apellidos: "Gómez", sede: "AQP", rol: "supervisor_sede" },
  { nombres: "Paola", apellidos: "Cahuana", sede: "AQP", rol: "integrante" },
  { nombres: "Mateo", apellidos: "Zarate", sede: "AQP", rol: "integrante" },
  { nombres: "Sasha", apellidos: "Fernandez", sede: "AQP", rol: "integrante" },
  { nombres: "Luana", apellidos: "Rodriguez", sede: "AQP", rol: "integrante" },
  // LIM
  { nombres: "Raquel", apellidos: "Ticona", sede: "LIM", rol: "supervisor_sede" },
  { nombres: "Joselyn", apellidos: "Gavilan", sede: "LIM", rol: "integrante" },
  { nombres: "Judith", apellidos: "Pillaca", sede: "LIM", rol: "integrante" },
];

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
