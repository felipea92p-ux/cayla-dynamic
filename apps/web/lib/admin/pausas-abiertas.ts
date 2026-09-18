// ============================================================================
// pausas-abiertas.ts — de dónde sale «desde cuándo» está en pausa cada persona
// ============================================================================
// QUÉ PROMETE · dadas las personas que la base ya marcó «en pausa» hoy, devolver
//               qué salida tienen abierta y desde cuándo (ver `pausaAbiertaDe`).
// QUÉ ASUME   · que le pasan SOLO ids de personas en pausa: no filtra ni decide
//               quién lo está. Lee marcajes NO anulados de hoy (Lima).
// SI FALLA    · `fallo: true` y el mapa vacío. Que la consulta falle NO significa
//               «nadie tiene pausa abierta»: significa «no se pudo mirar», y la
//               pantalla tiene que decirlo en vez de mostrar a todos sin hora como
//               si fuera lo normal. Igual que `ausenciasNoRespondieron`.
//
// Volumen: una consulta por refresco (cada 30 s) y solo si hay alguien en pausa.
// Hoy son ≤ ~10 personas × ≤ ~6 marcas del día ≈ 60 filas. Con 10 veces más
// gente seguirían siendo unos cientos: no hace falta índice, caché ni RPC.
// ============================================================================
import type { ClienteCayla } from "@cayla-dynamic/database";
import { hoyLima, rangoDelDiaLima } from "@cayla-dynamic/shared";
import { pausaAbiertaDe, type MarcaDePausa, type PausaAbierta } from "./asistencia-hoy";

export interface PausasAbiertas {
  /** Persona → su pausa abierta. Solo están de quienes se pudo saber. */
  porPersona: Map<string, PausaAbierta>;
  /** La consulta falló: «no se pudo mirar», NO «nadie tiene pausa». */
  fallo: boolean;
}

export async function traerPausasAbiertas(
  supabase: ClienteCayla,
  personaIds: string[],
  hoy: string = hoyLima(),
): Promise<PausasAbiertas> {
  if (personaIds.length === 0) return { porPersona: new Map(), fallo: false };

  // `anulada_at is null`: una marca anulada no existió (se anulan, no se borran).
  // Desde las 00:00 de hoy: la jornada de hoy no puede traer marcas de antes —las
  // que cruzan la medianoche cuelgan de la fecha de AYER y no llegan hasta acá.
  const { data, error } = await supabase
    .from("marcajes")
    .select("persona_id, tipo, timestamp_marca")
    .in("persona_id", personaIds)
    .is("anulada_at", null)
    .gte("timestamp_marca", rangoDelDiaLima(hoy).inicio)
    .order("timestamp_marca");
  if (error) return { porPersona: new Map(), fallo: true };

  const marcasPorPersona = new Map<string, MarcaDePausa[]>();
  for (const m of data ?? []) {
    const marcas = marcasPorPersona.get(m.persona_id) ?? [];
    marcas.push({ tipo: m.tipo, timestamp_marca: m.timestamp_marca });
    marcasPorPersona.set(m.persona_id, marcas);
  }

  const porPersona = new Map<string, PausaAbierta>();
  for (const [personaId, marcas] of marcasPorPersona) {
    const pausa = pausaAbiertaDe(marcas);
    if (pausa) porPersona.set(personaId, pausa);
  }
  return { porPersona, fallo: false };
}
