import type { ClienteCayla } from "@cayla-dynamic/database";
import { nombreDeArchivoSeguro } from "@cayla-dynamic/shared";
import { comprimirImagen } from "./comprimir-imagen";
import { subirArchivoConProgreso } from "./subir-archivo";
import { tipoDeArchivo } from "./tipos-archivo";

/**
 * SUBIR LOS ARCHIVOS DE UNA CONSTANCIA DE ESTUDIOS (0450).
 *
 * PROMETE: deja cada archivo en `educacion/<persona>/entregas/<entrega>/…` y
 *   devuelve sus rutas, o dice cuál falló y por qué. Nunca lanza.
 * ASUME: la entrega TODAVÍA NO EXISTE. La política del almacén solo deja
 *   escribir en esa carpeta mientras nadie haya llamado a
 *   `fn_educacion_enviar_entrega` con ese id.
 * NO HACE: no crea la entrega. Eso es un segundo paso, a propósito: si la
 *   subida se corta a la mitad no queda nada pendiente de revisión, y la
 *   pantalla reintenta con el MISMO id sin perder lo que ya subió.
 *
 * Lo usan el portal de la integrante y el panel de DO (cargar a nombre de
 * alguien), así que vive acá y no copiado en cada pantalla.
 */

export const BUCKET_COMPROBANTES = "comprobantes";

/**
 * 2000 px de lado mayor: una constancia hay que poder LEERLA —el monto, la
 * fecha, el nombre de la institución—, un poco más que un DNI (1600) porque
 * suele ser una hoja entera. Una foto de celular baja de ~4 MB a ~500 KB.
 */
const LADO_MAYOR_PX = 2000;
const CALIDAD = 0.85;

export interface ArchivoElegido {
  /** Estable entre renders: sirve de `key` y para quitarlo de la lista. */
  clave: string;
  archivo: File;
  /** URL local para la vista previa, o null si es un PDF. */
  vista: string | null;
  /** Ya subió en un intento anterior: no se vuelve a subir. */
  subido: { ruta: string; nombre: string } | null;
}

export function elegido(archivo: File): ArchivoElegido {
  const tipo = tipoDeArchivo(archivo.name, archivo.type);
  return {
    clave: `${archivo.name}-${archivo.size}-${archivo.lastModified}-${Math.round(Math.random() * 1e9)}`,
    archivo,
    // HEIC no se puede previsualizar fuera de Safari; se muestra el nombre.
    vista: tipo.startsWith("image/") && tipo !== "image/heic" ? URL.createObjectURL(archivo) : null,
    subido: null,
  };
}

/** Una foto se sube como JPG comprimido; un PDF, tal cual. */
async function preparar(archivo: File, orden: number): Promise<{ blob: File; nombreRuta: string }> {
  const tipo = tipoDeArchivo(archivo.name, archivo.type);
  if (tipo === "application/pdf") {
    return {
      blob: archivo.type === tipo ? archivo : new File([archivo], archivo.name, { type: tipo }),
      nombreRuta: `${orden}-${nombreDeArchivoSeguro(archivo.name, "pdf")}`,
    };
  }
  const jpg = await comprimirImagen(archivo, LADO_MAYOR_PX, CALIDAD);
  return {
    blob: new File([jpg], archivo.name.replace(/\.[^.]+$/, "") + ".jpg", { type: "image/jpeg" }),
    nombreRuta: `${orden}-${nombreDeArchivoSeguro(archivo.name, "jpg")}`,
  };
}

export type ResultadoSubida =
  | { ok: true; archivos: { ruta: string; nombre: string }[] }
  | { ok: false; clave: string; error: string };

/**
 * Sube en orden los que todavía no subieron. Marca cada uno en `alSubir` en
 * cuanto termina, para que un reintento no repita el trabajo ni el ancho de
 * banda de la tienda.
 */
export async function subirArchivosDeEntrega(
  supabase: ClienteCayla,
  personaId: string,
  entregaId: string,
  archivos: ArchivoElegido[],
  alAvanzar: (clave: string, pct: number) => void,
  alSubir: (clave: string, subido: { ruta: string; nombre: string }) => void,
): Promise<ResultadoSubida> {
  const listos: { ruta: string; nombre: string }[] = [];

  for (let i = 0; i < archivos.length; i++) {
    const a = archivos[i];
    if (a.subido) { listos.push(a.subido); continue; }

    let preparado: { blob: File; nombreRuta: string };
    try {
      preparado = await preparar(a.archivo, i + 1);
    } catch {
      return {
        ok: false, clave: a.clave,
        error: `No se pudo leer «${a.archivo.name}». Si es una foto de iPhone, ábrela en Fotos y compártela como JPG, o tómala con el botón «Tomar foto».`,
      };
    }

    const ruta = `educacion/${personaId}/entregas/${entregaId}/${preparado.nombreRuta}`;
    const error = await subirArchivoConProgreso(supabase, BUCKET_COMPROBANTES, ruta, preparado.blob,
      (pct) => alAvanzar(a.clave, pct));
    if (error) return { ok: false, clave: a.clave, error: `«${a.archivo.name}» no subió: ${error}` };

    const subido = { ruta, nombre: a.archivo.name };
    alSubir(a.clave, subido);
    listos.push(subido);
  }

  return { ok: true, archivos: listos };
}

/**
 * URL temporal de un archivo de constancia, para mostrarlo dentro de la
 * pantalla. Cinco minutos, como los adjuntos de la Bandeja: alcanza para
 * revisarla y no deja un enlace vivo dando vueltas.
 */
export async function urlDeConstancia(supabase: ClienteCayla, ruta: string): Promise<string | null> {
  const { data } = await supabase.storage.from(BUCKET_COMPROBANTES).createSignedUrl(ruta, 300);
  return data?.signedUrl ?? null;
}

/** "2026-10-05" → "05/10/2026". Aritmética de texto, sin huso horario. */
export function fechaCorta(iso: string | null | undefined): string {
  if (!iso) return "—";
  const [y, m, d] = iso.slice(0, 10).split("-");
  return `${d}/${m}/${y}`;
}
