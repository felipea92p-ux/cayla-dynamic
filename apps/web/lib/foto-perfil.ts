import type { ClienteCayla } from "@cayla-dynamic/database";
import { comprimirImagen } from "./comprimir-imagen";

/**
 * Todo lo compartido entre «Lo mío» (sube la foto) y el terminal (la muestra).
 * Ver la migración 0381 para por qué este bucket es público y por qué la
 * columna `personas.foto_url` guarda una RUTA relativa y no una URL absoluta.
 */
export const BUCKET_FOTOS_PERFIL = "fotos-perfil";

/** Lado mayor del thumbnail que de verdad se sube. La grilla del terminal lo
 * pinta pequeño, y comprimir en el navegador (en vez de subir la foto tal como
 * sale del celular) es lo que evita que cargar 20-30 fotos a la vez pese en la
 * Mac mini de la sede. */
const LADO_MAYOR_PX = 480;
const CALIDAD_JPEG = 0.85;

/**
 * Resuelve la URL pública a partir de la ruta guardada en `personas.foto_url`.
 * No hace ninguna llamada de red: `getPublicUrl` solo concatena la ruta con la
 * URL del proyecto ya conocida por el cliente.
 */
export function urlPublicaFotoPerfil(
  supabase: ClienteCayla,
  ruta: string | null | undefined,
): string | null {
  if (!ruta) return null;
  return supabase.storage.from(BUCKET_FOTOS_PERFIL).getPublicUrl(ruta).data.publicUrl;
}

/**
 * Nueva ruta para una subida. Lleva un sufijo de tiempo (no un nombre fijo) a
 * propósito: con un nombre fijo, reemplazar la foto reutilizaría la misma URL
 * y el navegador podría seguir sirviendo la versión vieja desde caché (ver el
 * porqué completo en la 0381).
 */
export function rutaNuevaFotoPerfil(personaId: string): string {
  return `perfil/${personaId}/${Date.now()}.jpg`;
}

/**
 * Redimensiona y comprime el retrato a JPEG en el propio navegador, ANTES de
 * subirlo. El canvas vive en `comprimir-imagen.ts` desde la 0401, cuando la
 * foto del DNI necesitó lo mismo con otro tamaño: acá solo quedan los dos
 * números que hacen que sea un retrato de grilla y no otra cosa.
 */
export async function comprimirFotoPerfil(archivo: File): Promise<Blob> {
  return comprimirImagen(archivo, LADO_MAYOR_PX, CALIDAD_JPEG);
}

/** Las iniciales que se muestran cuando todavía no hay foto. */
export function inicialesDe(nombres: string, apellidos: string): string {
  const a = nombres.trim().charAt(0);
  const b = apellidos.trim().charAt(0);
  return (a + b).toUpperCase() || "?";
}
