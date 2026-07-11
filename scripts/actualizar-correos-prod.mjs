// Actualiza correos de contacto del roster en producción.
// Los datos personales viven en scripts/datos-privados/correos.json (EXCLUIDO del repo):
//   { "Nombres Apellidos": "correo@ejemplo.com", ... }
// Opcionalmente actualiza también el correo de LOGIN (auth) de una persona:
//   node scripts/actualizar-correos-prod.mjs --login "Carlos Espejo"
import { createClient } from "@supabase/supabase-js";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error("Faltan SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY.");
  process.exit(1);
}

const rutaCorreos = join(dirname(fileURLToPath(import.meta.url)), "datos-privados", "correos.json");
let CORREOS;
try {
  CORREOS = JSON.parse(readFileSync(rutaCorreos, "utf8"));
} catch {
  console.error(`No se pudo leer ${rutaCorreos}. Crea ese archivo (no se sube al repo).`);
  process.exit(1);
}

const loginPara = (() => {
  const i = process.argv.indexOf("--login");
  return i >= 0 ? process.argv[i + 1] : null;
})();

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

async function main() {
  const { data: personas, error } = await supabase
    .from("personas")
    .select("id, nombres, apellidos, auth_user_id");
  if (error) throw error;

  let actualizados = 0;
  const sinCorreo = [];
  for (const p of personas) {
    const clave = `${p.nombres} ${p.apellidos}`;
    const correo = CORREOS[clave];
    if (!correo) {
      sinCorreo.push(clave);
      continue;
    }
    const { error: upError } = await supabase.from("personas").update({ email: correo }).eq("id", p.id);
    if (upError) throw new Error(`actualizando ${clave}: ${upError.message}`);
    actualizados++;

    if (loginPara === clave) {
      if (!p.auth_user_id) throw new Error(`${clave} no tiene login (auth_user_id nulo)`);
      const { error: authError } = await supabase.auth.admin.updateUserById(p.auth_user_id, {
        email: correo,
        email_confirm: true,
      });
      if (authError) throw new Error(`actualizando login de ${clave}: ${authError.message}`);
      console.log(`Login de ${clave} actualizado a ${correo} (misma contraseña).`);
    }
  }

  console.log(`Correos de contacto cargados: ${actualizados}/${personas.length}`);
  if (sinCorreo.length) console.log(`Sin correo aún: ${sinCorreo.join(", ")}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
