// Crea los 3 terminales reales (TRU/LIM/AQP) en el proyecto Supabase de producción.
// Se corre UNA sola vez. Requiere SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY del proyecto real.
import { createClient } from "@supabase/supabase-js";
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

const SEDES = ["TRU", "LIM", "AQP"];
const NOMBRES_SEDE = { TRU: "Trujillo", LIM: "Lima", AQP: "Arequipa" };

function generarPassword() {
  return crypto.randomBytes(12).toString("base64url");
}

async function main() {
  const { data: sedesRows, error: sedesError } = await supabase.from("sedes").select("id, codigo");
  if (sedesError) throw sedesError;
  const sedeIdPorCodigo = Object.fromEntries(sedesRows.map((s) => [s.codigo, s.id]));

  console.log("Creando terminales reales…\n");
  for (const codigo of SEDES) {
    const email = `terminal-${codigo.toLowerCase()}@cayla.dev`;
    const password = generarPassword();

    const { data: authData, error: authError } = await supabase.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });
    if (authError) throw new Error(`creando usuario ${email}: ${authError.message}`);

    const { data: terminal, error } = await supabase
      .from("terminales")
      .insert({
        sede_id: sedeIdPorCodigo[codigo],
        nombre_dispositivo: `Terminal ${NOMBRES_SEDE[codigo]}`,
        auth_user_id: authData.user.id,
      })
      .select()
      .single();
    if (error) throw error;

    console.log(`${codigo} (${NOMBRES_SEDE[codigo]}):`);
    console.log(`  correo:      ${email}`);
    console.log(`  contraseña:  ${password}`);
    console.log(`  terminal_id: ${terminal.id}\n`);
  }

  console.log("Guarda estas credenciales — se usan UNA vez para vincular cada dispositivo físico en /terminal.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
