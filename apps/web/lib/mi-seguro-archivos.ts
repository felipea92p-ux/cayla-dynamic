import type { ClienteCayla } from "@cayla-dynamic/database";
import { BUCKET_SEGUROS } from "./admin/seguros";

/**
 * GUARDAR UN PAPEL DE LA PÓLIZA EN EL EQUIPO DE LA PRACTICANTE.
 *
 * PROMETE: firma la dirección del archivo por `segundos` segundos con la orden de
 *   descargarlo con ese nombre, y dispara la descarga. Devuelve `null` si lo
 *   consiguió, o un texto en español si no. Nunca lanza.
 * ASUME: hay sesión abierta. Si el archivo es de quien lo pide lo decide la política
 *   de Storage de la 0530, no esta función: pedirle la firma a un archivo ajeno
 *   falla ahí.
 * NO HACE: no abre el archivo (eso es `abrirArchivoFirmado`, que lo deja en una
 *   pestaña nueva) ni lo recuerda en ninguna parte.
 *
 * Mismo camino que la descarga de Boletas (`urlDeDescarga`): la dirección firmada
 * lleva `download`, así que el almacén responde como adjunto y el navegador lo
 * guarda en vez de mostrarlo.
 */
export async function descargarArchivoDeSeguro(
  supabase: ClienteCayla,
  ruta: string,
  nombre: string,
  segundos = 60,
): Promise<string | null> {
  const { data, error } = await supabase.storage.from(BUCKET_SEGUROS).createSignedUrl(ruta, segundos, { download: nombre });
  if (error || !data) return "No pudimos descargar el archivo ahora. Intenta de nuevo en unos minutos.";
  const a = document.createElement("a");
  a.href = data.signedUrl;
  a.download = nombre;
  a.rel = "noopener";
  document.body.appendChild(a);
  a.click();
  a.remove();
  return null;
}
