// ============================================================================
// seguros-archivos.ts — poner un PDF en una póliza (o en varias)
// ============================================================================
// QUÉ PROMETE
//   Las dos formas de dejar un archivo en una póliza, para que las usen la pantalla de
//   archivos y la lectura de PDF sin volver a escribirlas:
//     · `adjuntarArchivoAPoliza`: sube el archivo desde el navegador y lo registra.
//     · `copiarArchivoAPoliza`: lo copia DENTRO del almacén a otra póliza, sin volver a
//       subirlo. Es para la póliza colectiva (una fila por persona, un solo papel).
//   Migración 0528: `fn_seguro_adjuntar` y el bucket privado `polizas-seguro`.
//
// EL ARCHIVO VA PRIMERO (el molde de Archivo, 0503)
//   Se sube al bucket y recién después se registra. Si Storage cae, no queda ninguna fila; si el
//   registro falla después de subir, se intenta borrar el huérfano (la política lo permite porque
//   nadie lo usa). Nunca lanzan: devuelven el texto del fallo, para que quien llama lo muestre.
//
// POR QUÉ LA RUTA NO LLEVA EL NOMBRE
//   El PDF de una póliza se llama «Apellidos, Nombres, FOLA 24043267.pdf»: lleva un nombre de
//   persona. La ruta en el almacén es `<uuid>.<ext>` y nada más (la base lo exige); el nombre
//   original solo se guarda como dato. Cada fila de póliza tiene su PROPIO objeto en el almacén
//   (un índice único lo exige): por eso la copia a otra póliza es un objeto nuevo, no el mismo.
// ============================================================================
import type { ClienteCayla } from "@cayla-dynamic/database";
import { problemaDeArchivo, rutaNuevaArchivo } from "@/lib/admin/archivo";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { subirArchivoConProgreso } from "@/lib/subir-archivo";
import { BUCKET_SEGUROS, type TipoArchivoSeguro } from "./seguros";

export type ResultadoDeArchivo = { ok: true; ruta: string } | { ok: false; error: string };

/** Sube `archivo` a una póliza y lo registra. Devuelve su ruta en el almacén (para copiarla a otras) o el fallo. */
export async function adjuntarArchivoAPoliza(
  supabase: ClienteCayla,
  polizaId: string,
  tipo: TipoArchivoSeguro,
  archivo: File,
  alAvanzar: (pct: number) => void = () => {},
): Promise<ResultadoDeArchivo> {
  const problema = problemaDeArchivo(archivo);
  if (problema) return { ok: false, error: problema };

  const ruta = rutaNuevaArchivo(archivo.name, archivo.type, crypto.randomUUID());
  alAvanzar(0);
  const fallo = await subirArchivoConProgreso(supabase, BUCKET_SEGUROS, ruta, archivo, alAvanzar);
  if (fallo) return { ok: false, error: `El archivo no subió (${fallo}). Vuelve a intentarlo.` };

  const { error } = await supabase.rpc("fn_seguro_adjuntar", {
    p_poliza_id: polizaId, p_tipo: tipo, p_storage_path: ruta, p_nombre_archivo: archivo.name,
  });
  if (error) {
    // Subió y no se registró: se limpia el huérfano; si no se puede, queda suelto sin hacer daño
    // (nadie lo ve ni lo usa).
    await supabase.storage.from(BUCKET_SEGUROS).remove([ruta]);
    return { ok: false, error: mensajeDeError(error, "guardar") };
  }
  return { ok: true, ruta };
}

/**
 * Copia, dentro del almacén, un archivo que ya subió a OTRA póliza de la misma póliza colectiva y lo
 * registra en esta. Sin volver a subir los megas desde el navegador. Devuelve null si quedó, o el fallo.
 */
export async function copiarArchivoAPoliza(
  supabase: ClienteCayla,
  rutaOrigen: string,
  polizaId: string,
  tipo: TipoArchivoSeguro,
  nombreArchivo: string,
): Promise<string | null> {
  const extension = rutaOrigen.includes(".") ? rutaOrigen.split(".").pop() : "pdf";
  const destino = `${crypto.randomUUID()}.${extension}`;

  const { error: eCopia } = await supabase.storage.from(BUCKET_SEGUROS).copy(rutaOrigen, destino);
  if (eCopia) return `No se pudo copiar el archivo (${eCopia.message}).`;

  const { error } = await supabase.rpc("fn_seguro_adjuntar", {
    p_poliza_id: polizaId, p_tipo: tipo, p_storage_path: destino, p_nombre_archivo: nombreArchivo,
  });
  if (error) {
    await supabase.storage.from(BUCKET_SEGUROS).remove([destino]);
    return mensajeDeError(error, "guardar");
  }
  return null;
}
