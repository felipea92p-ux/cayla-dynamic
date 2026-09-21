// ============================================================================
// feriado-de-hoy.ts — ¿esta fecha está en la tabla `feriados`?
// ============================================================================
// QUÉ PROMETE · dado un día (ISO, Lima), decir si es feriado.
// QUÉ ASUME   · que la tabla `feriados` es global y sin sede: un feriado lo es para las
//               cuatro sedes. Que una sede abra o no ese día NO se sabe desde aquí —es la
//               pregunta que el Dashboard le hace a quien lo mira (`feriadoSinConfirmar`)—.
// SI FALLA    · `esFeriado: false` y `fallo: true`. Ojo con la dirección: «no se pudo
//               mirar» se lee como «no es feriado», y eso deja la alarma como estaba
//               (roja), que es hacia donde debe caer una duda. No hace falta un aviso en
//               pantalla: fallar aquí no apaga ninguna alarma, solo deja de suavizarla.
//
// Volumen: una fila por PK, una consulta por refresco (cada 30 s). Ni índice ni caché.
// ============================================================================
import type { ClienteCayla } from "@cayla-dynamic/database";

export interface FeriadoDeHoy {
  esFeriado: boolean;
  /** La consulta falló: «no se pudo mirar», NO «no es feriado». */
  fallo: boolean;
}

export async function traerSiEsFeriado(supabase: ClienteCayla, fecha: string): Promise<FeriadoDeHoy> {
  const { data, error } = await supabase.from("feriados").select("fecha").eq("fecha", fecha).maybeSingle();
  if (error) return { esFeriado: false, fallo: true };
  return { esFeriado: data !== null, fallo: false };
}
