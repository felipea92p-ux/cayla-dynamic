// ============================================================================
// educacion-ciclo.ts — las reglas puras de «Aprobadas del ciclo» (0525)
// ============================================================================
// QUÉ PROMETE · decidir qué ciclo de pago se muestra al entrar, cómo se rotula,
//               y si un rechazo está completo antes de llamar a la base.
// QUÉ ASUME   · que un ciclo es un periodo de planilla (29 → 28), tal como lo
//               guarda `periodos_planilla`: nunca se calcula un mes aquí.
// NO HACE     · no toca Supabase ni React, por eso se prueba con vitest
//               (tests/educacion-ciclo.test.ts). La base repite la validación
//               del rechazo y gana: la pantalla que se equivoca muestra un
//               botón que devuelve un error en castellano.
// ============================================================================
import { hoyLima, type MotivoRechazo } from "@cayla-dynamic/shared";
import { fechaCorta } from "@/lib/educacion";

export interface PeriodoCiclo {
  id: string;
  fecha_ini: string;
  fecha_fin: string;
  estado: string;
}

/** Cuántos ciclos hacia atrás se ofrecen. Un año de planilla. */
export const CICLOS_A_OFRECER = 13;

/**
 * El ciclo con el que se abre la lista: el que contiene hoy; si hoy cae en un
 * hueco entre periodos (todavía no se creó el siguiente), el más reciente que ya
 * empezó; y si ninguno empezó, el primero de la lista. `null` solo si no hay ninguno.
 */
export function cicloInicial(periodos: readonly PeriodoCiclo[], hoy: string = hoyLima()): string | null {
  if (periodos.length === 0) return null;
  const que = periodos.find((p) => p.fecha_ini <= hoy && hoy <= p.fecha_fin);
  if (que) return que.id;
  const ya = [...periodos].filter((p) => p.fecha_ini <= hoy).sort((a, b) => b.fecha_ini.localeCompare(a.fecha_ini));
  return (ya[0] ?? periodos[0]).id;
}

/** «29/09/2026 → 28/10/2026 · abierto». */
export function etiquetaCiclo(p: PeriodoCiclo): string {
  return `${fechaCorta(p.fecha_ini)} → ${fechaCorta(p.fecha_fin)} · ${p.estado === "pagado" ? "pagado" : "abierto"}`;
}

/**
 * Lo que falta para poder rechazar, en el idioma de la pantalla; `null` = completo.
 * Espeja `fn_educacion_resolver_entrega` y `fn_educacion_revertir_aprobacion`: el
 * motivo se elige, y el texto —obligatorio, sea cual sea el motivo— tiene al menos
 * 3 letras y NO tiene máximo.
 */
export function rechazoIncompleto(categoria: MotivoRechazo | "", comentario: string): string | null {
  if (!categoria) return "Elige el motivo del rechazo.";
  if (comentario.trim().length < 3) return "Escribe qué tiene que corregir: la integrante lo va a leer.";
  return null;
}
