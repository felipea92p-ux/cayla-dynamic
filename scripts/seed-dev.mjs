// Seed de datos de prueba para desarrollo local — NO usar contra producción.
// Requiere `supabase start` corriendo y las env vars SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY
// (ver `supabase status` para obtener estos valores localmente).
import { createClient } from "@supabase/supabase-js";
import bcrypt from "bcryptjs";

const SUPABASE_URL = process.env.SUPABASE_URL ?? "http://127.0.0.1:54321";
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SERVICE_ROLE_KEY) {
  console.error("Falta SUPABASE_SERVICE_ROLE_KEY. Corre: supabase status -o env y expórtala.");
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const SEDES = ["TRU", "LIM", "AQP"];
const PIN_DEFAULT = "1234";
const TERMINAL_PASSWORD = "terminal-dev-1234";
const ADMIN_PASSWORD = "admin-dev-1234";
const ROLES_CON_LOGIN_ADMIN = ["admin", "lider_do", "supervisor_sede"];

async function crearUsuarioAuth(email, password) {
  const { data, error } = await supabase.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });
  if (error) throw new Error(`creando usuario ${email}: ${error.message}`);
  return data.user.id;
}

async function main() {
  const pinHash = await bcrypt.hash(PIN_DEFAULT, 10);

  const { data: sedesRows, error: sedesError } = await supabase.from("sedes").select("id, codigo");
  if (sedesError) throw sedesError;
  const sedeIdPorCodigo = Object.fromEntries(sedesRows.map((s) => [s.codigo, s.id]));

  console.log("Creando terminales (uno por sede)…");
  const terminalesPorSede = {};
  for (const codigo of SEDES) {
    const email = `terminal-${codigo.toLowerCase()}@cayla.dev`;
    const authUserId = await crearUsuarioAuth(email, TERMINAL_PASSWORD);
    const { data: terminal, error } = await supabase
      .from("terminales")
      .insert({
        sede_id: sedeIdPorCodigo[codigo],
        nombre_dispositivo: `Terminal ${codigo} (dev)`,
        auth_user_id: authUserId,
      })
      .select()
      .single();
    if (error) throw error;
    terminalesPorSede[codigo] = terminal;
    console.log(`  ${codigo}: ${email} / ${TERMINAL_PASSWORD} (terminal_id=${terminal.id})`);
  }

  console.log("Creando personas de prueba…");
  const personasSeed = [
    { nombres: "Felipe", apellidos: "Founder", sede: "TRU", rol: "admin" },
    { nombres: "Ana", apellidos: "Supervisora TRU", sede: "TRU", rol: "supervisor_sede" },
    { nombres: "Bruno", apellidos: "Integrante TRU", sede: "TRU", rol: "integrante" },
    { nombres: "Carla", apellidos: "Integrante TRU", sede: "TRU", rol: "integrante" },
    { nombres: "Diego", apellidos: "Supervisor LIM", sede: "LIM", rol: "supervisor_sede" },
    { nombres: "Elena", apellidos: "Integrante LIM", sede: "LIM", rol: "integrante" },
    { nombres: "Franco", apellidos: "Supervisor AQP", sede: "AQP", rol: "supervisor_sede" },
    { nombres: "Gaby", apellidos: "Integrante AQP", sede: "AQP", rol: "integrante" },
  ];

  for (const p of personasSeed) {
    let authUserId = null;
    let emailLogin = null;
    if (ROLES_CON_LOGIN_ADMIN.includes(p.rol)) {
      emailLogin = `${p.nombres.toLowerCase()}@cayla.dev`;
      authUserId = await crearUsuarioAuth(emailLogin, ADMIN_PASSWORD);
    }

    const { data: persona, error } = await supabase
      .from("personas")
      .insert({
        nombres: p.nombres,
        apellidos: p.apellidos,
        sede_base_id: sedeIdPorCodigo[p.sede],
        rol: p.rol,
        pin_hash: pinHash,
        auth_user_id: authUserId,
      })
      .select()
      .single();
    if (error) throw error;

    await supabase.from("horarios_asignados").insert({
      persona_id: persona.id,
      vigente_desde: "2026-01-01",
      hora_entrada: "09:00",
      hora_salida: "18:00",
    });

    await supabase.from("tarifas_hora").insert({
      persona_id: persona.id,
      vigente_desde: "2026-01-01",
      tarifa_hora_soles: 15.0,
    });

    const loginInfo = emailLogin ? ` — login ${emailLogin} / ${ADMIN_PASSWORD}` : "";
    console.log(`  ${p.nombres} ${p.apellidos} (${p.rol}, ${p.sede}) — PIN ${PIN_DEFAULT}${loginInfo}`);
  }

  console.log("\nListo. Todas las personas de prueba usan el PIN 1234.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
