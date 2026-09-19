import type { ClienteCayla } from "@cayla-dynamic/database";
import { BUCKET_BOLETAS } from "./boletas";

/**
 * PEDIR LAS HOJAS DE UNA BOLETA Y DEJARLAS LISTAS PARA MIRAR.
 *
 * PROMETE: para una versión de boleta devuelve sus hojas EN ORDEN, cada una con
 *   una URL firmada de `segundos` segundos. Nunca lanza: si algo falla, `error`
 *   trae un texto en español y `hojas` viene vacío.
 * ASUME: hay sesión abierta. Quién puede abrir qué lo decide la base —la función
 *   `fn_boleta_partes` y la política del bucket—, no esta función.
 * NO HACE: no descarga nada ni guarda el archivo; solo firma las direcciones.
 *
 * ── UN EFECTO QUE HAY QUE SABER ─────────────────────────────────────────────
 * Cuando quien llama es la DUEÑA de una boleta publicada y esta es su versión
 * vigente, `fn_boleta_partes` deja escrita en la base «la abrió por primera
 * vez» (0482). Es el ÚNICO camino que lo hace: por eso la pantalla de la
 * persona tiene que abrir sus hojas SIEMPRE por aquí, y no pidiendo la URL
 * directo al almacén. Cuando la llama DO mirando la de otra persona, no marca
 * nada: DO revisando no es la persona recibiendo.
 *
 * Esa marca prueba que se pidieron las hojas, no que se leyeron — y así se le
 * dice a quien la lea.
 *
 * ── SI EL ALMACÉN NO RESPONDE ───────────────────────────────────────────────
 * La marca ya quedó escrita antes de firmar. Es lo correcto: la persona sí pidió
 * su boleta y el sistema sí se la iba a dar. El mensaje le dice que lo intente
 * de nuevo, y como la marca es de la PRIMERA vez, reintentar no la corre.
 */
export type HojaFirmada = {
  orden: number;
  ruta: string;
  mime: string;
  bytes: number;
  url: string;
};

export async function hojasFirmadasDeVersion(
  supabase: ClienteCayla,
  versionId: string,
  segundos = 300,
): Promise<{ hojas: HojaFirmada[]; error: string | null }> {
  const { data, error } = await supabase.rpc("fn_boleta_partes", { p_version_id: versionId });
  if (error) return { hojas: [], error: error.message };
  const partes = [...(data ?? [])].sort((a, b) => a.orden - b.orden);
  if (partes.length === 0) return { hojas: [], error: "Esa boleta no tiene hojas." };

  const { data: firmadas, error: eFirma } = await supabase.storage
    .from(BUCKET_BOLETAS)
    .createSignedUrls(partes.map((p) => p.storage_path), segundos);
  if (eFirma || !firmadas) {
    return { hojas: [], error: "No pudimos abrir tu boleta ahora. Intenta de nuevo en unos minutos." };
  }

  const urlPorRuta = new Map(firmadas.map((f) => [f.path, f.signedUrl]));
  const hojas: HojaFirmada[] = [];
  for (const p of partes) {
    const url = urlPorRuta.get(p.storage_path);
    if (!url) return { hojas: [], error: "No pudimos abrir una de las hojas. Intenta de nuevo en unos minutos." };
    hojas.push({ orden: p.orden, ruta: p.storage_path, mime: p.mime, bytes: p.bytes, url });
  }
  return { hojas, error: null };
}

/**
 * Una URL que, al abrirse, DESCARGA el archivo con ese nombre en vez de mostrarlo.
 * `null` si no se pudo firmar.
 */
export async function urlDeDescarga(
  supabase: ClienteCayla,
  ruta: string,
  nombre: string,
  segundos = 60,
): Promise<string | null> {
  const { data, error } = await supabase.storage.from(BUCKET_BOLETAS).createSignedUrl(ruta, segundos, { download: nombre });
  if (error || !data) return null;
  return data.signedUrl;
}
