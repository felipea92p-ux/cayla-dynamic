// ============================================================================
// locaciones-archivo.ts — registrar un contrato de locación firmado
// ============================================================================
// QUÉ PROMETE
//   Subir el escaneo del contrato desde el navegador y registrarlo con sus
//   datos, en ese orden. Migración 0610: `fn_locacion_registrar` y el bucket
//   privado `contratos-locacion`. Nunca lanza: devuelve el texto del fallo, para
//   que quien llama lo muestre.
//
// EL ARCHIVO VA PRIMERO (el molde de Archivo, 0503, y de Seguros, 0528)
//   Si el almacén no responde, la subida falla entera y no queda ninguna fila:
//   se reintenta. Si sube y el registro falla después (una fecha mal puesta),
//   se intenta borrar el huérfano —la política lo permite porque ningún
//   contrato lo usa—; si tampoco se puede, queda suelto sin hacer daño: nadie
//   lo ve ni lo usa.
//
// POR QUÉ LA RUTA NO LLEVA EL NOMBRE
//   El escaneo suele llamarse «Contrato locación Nombre Apellido DNI.pdf». En
//   el almacén la ruta es `<uuid>.<ext>` y nada más (la base lo exige); el
//   nombre original solo se guarda como dato.
// ============================================================================
import type { ClienteCayla } from "@cayla-dynamic/database";
import { problemaDeArchivo, rutaNuevaArchivo } from "@/lib/admin/archivo";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { subirArchivoConProgreso } from "@/lib/subir-archivo";
import { BUCKET_LOCACION } from "./locaciones";

export interface DatosContratoLocacion {
  personaId: string;
  servicio: string;
  fechaInicio: string;
  fechaFin: string;
  fechaFirma: string;
}

export async function registrarContratoLocacion(
  supabase: ClienteCayla,
  datos: DatosContratoLocacion,
  archivo: File,
  alAvanzar: (pct: number) => void = () => {},
): Promise<string | null> {
  const problema = problemaDeArchivo(archivo);
  if (problema) return problema;

  const ruta = rutaNuevaArchivo(archivo.name, archivo.type, crypto.randomUUID());
  alAvanzar(0);
  const fallo = await subirArchivoConProgreso(supabase, BUCKET_LOCACION, ruta, archivo, alAvanzar);
  if (fallo) return `El archivo no subió (${fallo}). Vuelve a intentarlo.`;

  const { error } = await supabase.rpc("fn_locacion_registrar", {
    p_persona_id: datos.personaId,
    p_servicio: datos.servicio,
    p_fecha_inicio: datos.fechaInicio,
    p_fecha_fin: datos.fechaFin,
    p_fecha_firma: datos.fechaFirma,
    p_storage_path: ruta,
    p_nombre_archivo: archivo.name,
  });
  if (error) {
    await supabase.storage.from(BUCKET_LOCACION).remove([ruta]);
    return mensajeDeError(error, "registrar el contrato");
  }
  return null;
}
