import type { ClienteCayla } from "@cayla-dynamic/database";
import { TIPOS_REPORTE } from "@/lib/reportes";
import { mensajeDeError } from "@/lib/admin/mensaje-error";

/**
 * CASOS EN EL DASHBOARD — de dónde salen los números, qué NO incluyen.
 *
 * Una fila por reporte que quien mira YA gestiona (`fn_casos_resumen`, 0493):
 * el mes en que se creó, su sede, tipo, vía, estado y si tiene un plazo
 * vencido hoy. Nunca quién lo escribió, su código ni su relato — la base ni
 * siquiera los selecciona. Este archivo solo agrega esas filas para el
 * indicador «Casos» del Dashboard; no decide quién ve cuáles: eso ya lo
 * resolvió `fn_reporte_motivo` (0483) antes de que la fila llegue aquí.
 */

/** Una fila de `fn_casos_resumen()`. */
export interface FilaCasoResumen {
  mes: string;
  sede_id: string;
  sede_codigo: string;
  tipo: string;
  via: string;
  estado: string;
  vencido: boolean;
}

export interface ResumenCasos {
  total: number;
  abiertos: number;
  vencidos: number;
  cerrados: number;
  porCategoria: { tipo: string; etiqueta: string; total: number }[];
  porSede: { sedeCodigo: string; total: number; abiertos: number; cerrados: number; vencidos: number }[];
}

export async function traerResumenCasos(supabase: ClienteCayla, desde: string): Promise<{ filas: FilaCasoResumen[]; error: string | null }> {
  const { data, error } = await supabase.rpc("fn_casos_resumen", { p_desde: desde });
  if (error) return { filas: [], error: mensajeDeError(error, "traer el resumen de casos") };
  return { filas: (data ?? []) as FilaCasoResumen[], error: null };
}

/** La etiqueta del tipo tal como se muestra en «Nuevo reporte» y en Casos — una sola lista, en `reportes.ts`. */
function etiquetaDeTipo(tipo: string): string {
  return TIPOS_REPORTE.find((t) => t.valor === tipo)?.titulo ?? tipo;
}

/**
 * Agrega las filas de `fn_casos_resumen` para el indicador del Dashboard.
 * `porCategoria` sale ordenado de mayor a menor: es lo primero que alguien
 * mirando «qué categorías se eligen más» necesita, sin tener que leerlo.
 */
export function resumirCasos(filas: readonly FilaCasoResumen[]): ResumenCasos {
  const porCategoriaMapa = new Map<string, number>();
  const porSedeMapa = new Map<string, { sedeCodigo: string; total: number; abiertos: number; cerrados: number; vencidos: number }>();
  let abiertos = 0;
  let vencidos = 0;
  let cerrados = 0;

  for (const f of filas) {
    porCategoriaMapa.set(f.tipo, (porCategoriaMapa.get(f.tipo) ?? 0) + 1);

    const sede = porSedeMapa.get(f.sede_id) ?? { sedeCodigo: f.sede_codigo, total: 0, abiertos: 0, cerrados: 0, vencidos: 0 };
    sede.total += 1;
    const abierto = f.estado !== "cerrado";
    if (abierto) sede.abiertos += 1; else sede.cerrados += 1;
    if (f.vencido) sede.vencidos += 1;
    porSedeMapa.set(f.sede_id, sede);

    if (abierto) abiertos += 1; else cerrados += 1;
    if (f.vencido) vencidos += 1;
  }

  const porCategoria = [...porCategoriaMapa.entries()]
    .map(([tipo, total]) => ({ tipo, etiqueta: etiquetaDeTipo(tipo), total }))
    .sort((a, b) => b.total - a.total);
  const porSede = [...porSedeMapa.values()].sort((a, b) => b.total - a.total);

  return { total: filas.length, abiertos, vencidos, cerrados, porCategoria, porSede };
}
