// Migra las fotos que hoy están sueltas como enlaces de Google Drive
// (datos_personales.foto_profesional_url — "enlaces de Google Drive (por
// ahora)", ver la migración 0061) hacia el sistema real de foto de perfil
// (0381): las descarga, las sube al bucket público «fotos-perfil» con el
// mismo recorte/calidad que usa el navegador, y las enlaza con
// fn_actualizar_foto_perfil.
//
// Se corre a mano, UNA vez, con las credenciales de producción:
//
//   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node scripts/migrar-fotos-perfil-desde-drive.mjs
//
// Antes: `pnpm install` (agrega `sharp`, que este script usa para convertir
// cualquier formato que venga de Drive al JPEG que exige el bucket — ver
// 0381 para por qué el bucket solo acepta ese formato).
//
// Para probar con una sola persona antes de correrlo con las ~20:
//
//   ... node scripts/migrar-fotos-perfil-desde-drive.mjs --solo <persona_id>
//
// POR QUÉ foto_profesional_url Y NO foto_dni_url NI foto_personal_url
//   Decisión de Felipe (2026-09-08). foto_dni_url es un documento de
//   identidad y no puede terminar en un bucket público bajo ninguna
//   circunstancia — este script no la toca. Si más adelante la fuente
//   correcta resulta ser foto_personal_url, cambiar la constante de abajo y
//   volver a correr es seguro: no borra nada y cada persona puede
//   reemplazar su propia foto después desde «Lo mío» de todas formas.
const COLUMNA_FUENTE = "foto_profesional_url";
//
// QUÉ NO HACE
//   No borra ni toca datos_personales — las columnas Drive quedan intactas,
//   así que esto se puede volver a correr sin perder nada si algo falla a
//   mitad de camino. No falla la corrida entera si UNA foto falla: la anota
//   en el resumen final y sigue con la siguiente.

import { createClient } from "@supabase/supabase-js";
import sharp from "sharp";
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error("Faltan SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY.");
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

// Mismos parámetros que apps/web/lib/foto-perfil.ts (comprimirFotoPerfil),
// para que una foto migrada se vea igual que una subida a mano desde «Lo mío».
const LADO_MAYOR_PX = 480;
const CALIDAD_JPEG = 85;

const soloIdx = process.argv.indexOf("--solo");
const soloPersonaId = soloIdx !== -1 ? process.argv[soloIdx + 1] : null;

function idDeDrive(url) {
  const m = url.match(/[?&]id=([^&]+)/) ?? url.match(/\/d\/([^/]+)/);
  return m ? m[1] : null;
}

async function descargarDeDrive(url) {
  const id = idDeDrive(url);
  if (!id) throw new Error(`no se pudo leer el id de Drive en: ${url}`);

  const directa = `https://drive.google.com/uc?export=download&id=${id}`;
  const res = await fetch(directa, { redirect: "follow" });
  if (!res.ok) throw new Error(`Drive respondió ${res.status}`);

  const tipo = res.headers.get("content-type") ?? "";
  if (tipo.includes("text/html")) {
    throw new Error(
      "Drive devolvió una página HTML en vez de la imagen (¿el link dejó de ser público, o el archivo es demasiado grande?)",
    );
  }
  return Buffer.from(await res.arrayBuffer());
}

function recortarYComprimir(buffer) {
  return sharp(buffer)
    .rotate() // corrige orientación EXIF, igual que `imageOrientation: "from-image"` en el navegador
    .resize(LADO_MAYOR_PX, LADO_MAYOR_PX, { fit: "inside", withoutEnlargement: true })
    .jpeg({ quality: CALIDAD_JPEG })
    .toBuffer();
}

// libvips (lo que usa sharp) no siempre trae soporte de HEIC — el formato en el
// que Drive/Fotos de iPhone a veces guarda estas fotos viejas. `sips` es la
// herramienta de conversión que ya trae macOS: se usa solo como respaldo,
// cuando sharp no pudo leer el archivo directamente.
async function conRespaldoDeSips(original, errorOriginal) {
  const dir = mkdtempSync(join(tmpdir(), "cayla-foto-"));
  try {
    const origen = join(dir, "original");
    const destino = join(dir, "convertida.jpg");
    writeFileSync(origen, original);
    try {
      execFileSync("sips", ["-s", "format", "jpeg", origen, "--out", destino], { stdio: "pipe" });
    } catch {
      throw errorOriginal; // tampoco sips pudo — el error de sharp es el útil
    }
    return await recortarYComprimir(readFileSync(destino));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

async function migrarUna({ persona_id, url, nombre }) {
  const original = await descargarDeDrive(url);

  const jpeg = await recortarYComprimir(original).catch((e) => conRespaldoDeSips(original, e));

  const ruta = `perfil/${persona_id}/${Date.now()}.jpg`;

  const { error: errSubida } = await supabase.storage
    .from("fotos-perfil")
    .upload(ruta, jpeg, { contentType: "image/jpeg", upsert: false });
  if (errSubida) throw new Error(`Storage: ${errSubida.message}`);

  const { error: errRpc } = await supabase.rpc("fn_actualizar_foto_perfil", {
    p_persona_id: persona_id,
    p_foto_url: ruta,
  });
  if (errRpc) throw new Error(`fn_actualizar_foto_perfil: ${errRpc.message}`);

  console.log(`  → ${jpeg.length} bytes, ${ruta}`);
}

async function main() {
  const { data: filas, error: errDatos } = await supabase
    .from("datos_personales")
    .select(`persona_id, url:${COLUMNA_FUENTE}`)
    .not(COLUMNA_FUENTE, "is", null);
  if (errDatos) {
    console.error("No se pudo leer datos_personales:", errDatos.message);
    process.exit(1);
  }

  const idsAMigrar = soloPersonaId
    ? filas.filter((f) => f.persona_id === soloPersonaId)
    : filas;

  const { data: personas, error: errPersonas } = await supabase
    .from("personas")
    .select("id, nombres, apellidos")
    .in(
      "id",
      idsAMigrar.map((f) => f.persona_id),
    );
  if (errPersonas) {
    console.error("No se pudo leer personas:", errPersonas.message);
    process.exit(1);
  }
  const nombrePor = new Map(personas.map((p) => [p.id, `${p.nombres} ${p.apellidos}`]));

  console.log(`${idsAMigrar.length} foto(s) por migrar desde ${COLUMNA_FUENTE}.\n`);

  const resumen = { ok: [], error: [] };

  for (const fila of idsAMigrar) {
    const nombre = nombrePor.get(fila.persona_id) ?? fila.persona_id;
    console.log(`${nombre}…`);
    try {
      await migrarUna({ persona_id: fila.persona_id, url: fila.url, nombre });
      resumen.ok.push(nombre);
    } catch (e) {
      console.log(`  ❌ ${e.message}`);
      resumen.error.push({ nombre, motivo: e.message });
    }
  }

  console.log(`\n${resumen.ok.length} migrada(s), ${resumen.error.length} con error.`);
  if (resumen.error.length > 0) {
    console.log("\nCon error — revisar a mano:");
    for (const { nombre, motivo } of resumen.error) console.log(`  - ${nombre}: ${motivo}`);
  }
}

main();
