import type { ClienteCayla } from "@cayla-dynamic/database";
import { comprimirImagen } from "./comprimir-imagen";

/**
 * Todo lo compartido por la foto del DNI: dónde vive, cómo se llama su archivo
 * y cuánto se comprime antes de subirla. Ver la migración 0401 para por qué el
 * bucket es PRIVADO (a diferencia de `fotos-perfil`) y por qué la ficha guarda
 * una ruta y no una URL.
 */
export const BUCKET_SOLICITUDES_PERFIL = "solicitudes-perfil";

/**
 * Las dos caras, con el nombre de su columna en `datos_personales`.
 *
 * Sí es una lista escrita a mano, y sí, la regla de la casa dice que no. La
 * excepción está razonada: un DNI peruano tiene dos caras y eso no se gestiona
 * desde ninguna pantalla — no es un catálogo, es la forma del documento. Lo
 * que SÍ vive en la base (`catalogo_campos_perfil.columnas`) son los nombres
 * de columna, y son estos mismos: si algún día dejan de coincidir, la
 * migración manda y esto se corrige.
 */
export const CARAS_DNI = [
  { clave: "anverso", columna: "foto_dni_anverso_ruta", etiqueta: "Anverso", ayuda: "El lado de tu foto" },
  { clave: "reverso", columna: "foto_dni_reverso_ruta", etiqueta: "Reverso", ayuda: "El lado de la dirección" },
] as const;

export type CaraDni = (typeof CARAS_DNI)[number]["clave"];

/**
 * 1600 px de lado mayor y no los 480 del retrato: un DNI hay que poder LEERLO
 * —el número, el nombre, la fecha de caducidad—, y a 480 px eso se convierte en
 * una mancha. A 1600 px una foto de celular baja de ~4 MB a ~400 KB, que es lo
 * que hace que subir dos caras desde la conexión de una tienda no sea una
 * espera muda de un minuto.
 */
const LADO_MAYOR_DNI_PX = 1600;
const CALIDAD_DNI = 0.85;

export async function comprimirFotoDni(archivo: File): Promise<Blob> {
  return comprimirImagen(archivo, LADO_MAYOR_DNI_PX, CALIDAD_DNI);
}

/**
 * Ruta nueva para una cara. Va bajo `solicitud/<persona_id>/` porque es lo
 * único que aceptan la política del bucket y `fn_crear_solicitud_perfil`.
 *
 * Lleva sufijo de tiempo y no un nombre fijo, por el mismo motivo que la foto
 * de perfil (0381) y por uno más de la 0401: una ruta ya aprobada queda
 * CONGELADA —nadie puede sobrescribirla—, así que reusar el nombre haría que
 * la segunda subida rebotara contra la política en vez de crear una versión
 * nueva.
 */
export function rutaNuevaCaraDni(personaId: string, cara: CaraDni): string {
  const sufijo = `${Date.now()}-${Math.round(Math.random() * 1e6)}`;
  return `solicitud/${personaId}/dni-${cara}-${sufijo}.jpg`;
}

/**
 * URL temporal para mostrar una imagen del bucket privado. Cinco minutos, los
 * mismos que usa /admin/bandeja para los adjuntos de una solicitud: alcanza
 * para mirarla y no deja un enlace vivo dando vueltas.
 */
export async function urlFirmadaSolicitudPerfil(
  supabase: ClienteCayla,
  ruta: string,
): Promise<string | null> {
  const { data } = await supabase.storage.from(BUCKET_SOLICITUDES_PERFIL).createSignedUrl(ruta, 300);
  return data?.signedUrl ?? null;
}
