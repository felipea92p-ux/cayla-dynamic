import type { ClienteCayla } from "@cayla-dynamic/database";
import { MESES_LARGO } from "./admin/planilla/formato";
import { esBoletaNueva } from "./boletas";

/**
 * LAS BOLETAS OFICIALES DE UNA PERSONA — lo que «Lo mío» y la Bandeja comparten.
 *
 * POR QUÉ UN ARCHIVO APARTE
 *   Tres sitios hacen la misma pregunta —«¿cuántas boletas nuevas tengo?»—: el
 *   globito del menú de /mio, la pestaña «Boletas» y la Bandeja. Si cada uno
 *   leyera y contara por su cuenta, el día que cambie qué es «nueva» el globito
 *   diría 1 mientras la Bandeja dice 0 (el defecto que `bandeja-mia.ts` ya
 *   describe). Aquí se lee UNA vez y `esBoletaNueva` (lib/boletas.ts) decide.
 *
 * QUÉ ASUME
 *   `fn_mis_boletas()` (0482) contesta solo por quien pregunta, sin excepción
 *   para DO: por eso no lleva filtro de persona.
 *
 * SI LA BASE NO RESPONDE
 *   `error` trae un texto en español y `filas` viene vacío. Quien lo llama decide
 *   qué decir: la pestaña lo dice en pantalla; el globito y la Bandeja NO inventan
 *   un «0 boletas nuevas» con eso.
 */

/** Una fila de `fn_mis_boletas()`: un periodo pagado de la persona, con su boleta si ya se publicó. */
export interface FilaMiBoleta {
  periodo_id: string;
  fecha_ini: string;
  fecha_fin: string;
  boleta_id: string | null;
  /** null = pagado pero sin publicar; 'publicada' | 'papel' en los demás casos. */
  estado: string | null;
  version_id: string | null;
  version_n: number | null;
  tipo: string | null;
  n_partes: number;
  bytes: number;
  /** Hubo una versión nueva que DO avisó. */
  actualizada: boolean;
  publicada_at: string | null;
  vista_at: string | null;
  recibida_at: string | null;
}

export async function traerMisBoletas(
  supabase: ClienteCayla,
): Promise<{ filas: FilaMiBoleta[]; error: string | null }> {
  const { data, error } = await supabase.rpc("fn_mis_boletas");
  if (error) return { filas: [], error: "No pudimos leer tus boletas. Vuelve a intentarlo en un momento." };
  return { filas: (data ?? []) as FilaMiBoleta[], error: null };
}

/** Cuántas boletas están publicadas y todavía sin abrir. */
export function contarBoletasNuevas(filas: readonly Pick<FilaMiBoleta, "estado" | "vista_at">[]): number {
  return filas.filter(esBoletaNueva).length;
}

/**
 * Cómo se llama un periodo: por el mes en que TERMINA. El periodo del 29 de
 * julio al 28 de agosto es «Agosto», igual que en Planilla y en la boleta en
 * vivo (`mes_etiqueta` sale de `fecha_fin`). Leído de la fecha, nunca de un
 * calendario de mes entero: los periodos van del 29 al 28.
 *
 * «septiembre» con p, como el resto de Planilla (`MESES_LARGO`).
 */
export function nombreDelPeriodo(fechaFin: string, opciones: { conAnio?: boolean; minuscula?: boolean } = {}): string {
  const { conAnio = true, minuscula = false } = opciones;
  const [anio, mes] = fechaFin.split("-");
  const nombre = MESES_LARGO[Number(mes) - 1] ?? "";
  const cabeza = minuscula ? nombre : `${nombre.charAt(0).toUpperCase()}${nombre.slice(1)}`;
  return conAnio ? `${cabeza} ${anio}` : cabeza;
}

/**
 * El nombre con el que se guarda una hoja: `Boleta-Agosto-2026.pdf`, o
 * `Boleta-Agosto-2026-2.jpg` cuando la boleta tiene varias hojas. Sin espacios
 * ni acentos, para que sobreviva a cualquier teléfono y a cualquier correo.
 */
export function nombreDeArchivoDeBoleta(fechaFin: string, posicion: number, total: number, extension: string): string {
  const base = `Boleta-${nombreDelPeriodo(fechaFin, { conAnio: false })}-${fechaFin.slice(0, 4)}`;
  const ext = extension.replace(/^\./, "").toLowerCase();
  return total > 1 ? `${base}-${posicion}.${ext}` : `${base}.${ext}`;
}
