// ============================================================================
// locaciones.ts — lo que la pestaña «Recibo por honorarios» decide para dibujar
// ============================================================================
// QUÉ PROMETE
//   Las palabras, los colores y las bandas de los estados que devuelven
//   `fn_locaciones_tablero` y `fn_locaciones_listar` (migración 0610), y el
//   bucket de los escaneos. Sin React ni Supabase: se prueba con vitest
//   (`tests/locaciones.test.ts`).
//
// QUÉ NO DECIDE
//   Cuál es el estado de cada persona o de cada contrato. Eso lo dice la base
//   (vencido, vence pronto, cuántos días le quedan): si la pantalla lo
//   recalculara, habría dos respuestas a la misma pregunta.
//
// POR QUÉ NO DICE «LOCADOR» EN PANTALLA
//   Es la palabra del Código Civil para quien presta un servicio por
//   honorarios, y nadie en una sede la usa. En pantalla se dice «recibo por
//   honorarios» o «RxH»; «locación de servicios» solo aparece donde se nombra
//   el contrato, que se llama así.
// ============================================================================
import { sumarDias } from "@/lib/mi-semana";
import { sumarMeses } from "@/lib/admin/seguros";
import { TIPO_VINCULO_LABEL, type TipoVinculo } from "@cayla-dynamic/shared";

/** El bucket privado de los escaneos firmados (0610). */
export const BUCKET_LOCACION = "contratos-locacion";

/** Una fila de `fn_locaciones_tablero`: una persona por honorarios, con su cobertura. */
export interface FilaTableroLocacion {
  persona_id: string;
  persona: string;
  sede: string;
  /** Qué es hoy: `rxh`, otro `tipo_vinculo`, o `cesada`. Solo importa en `abierta_sin_rxh`. */
  vinculo_actual: string;
  contrato_id: string | null;
  servicio: string | null;
  fecha_inicio: string | null;
  cubierto_hasta: string | null;
  dias_restantes: number | null;
  n_contratos: number;
  estado: EstadoPersonaLocacion;
}

/** Una fila de `fn_locaciones_listar`: un contrato, con su estado ya resuelto. */
export interface ContratoLocacion {
  id: string;
  persona_id: string;
  persona: string;
  servicio: string;
  fecha_inicio: string;
  fecha_fin: string;
  fecha_firma: string;
  storage_path: string;
  nombre_archivo: string;
  mime: string;
  bytes: number;
  estado: EstadoContratoLocacion;
  registrado_por_nombre: string | null;
  registrado_at: string;
  terminado_el: string | null;
  terminado_motivo: string | null;
  terminado_por_nombre: string | null;
  anulado_at: string | null;
  anulado_motivo: string | null;
  anulado_por_nombre: string | null;
}

export type EstadoPersonaLocacion =
  | "abierta_sin_rxh" | "vencido" | "sin_contrato" | "por_vencer" | "por_empezar" | "vigente";
export type EstadoContratoLocacion = "en_curso" | "por_empezar" | "concluido" | "terminado" | "anulado";

type Variante = "neutral" | "alerta" | "advertencia" | "positivo" | "informativo";

/**
 * Cómo se nombra y se pinta el estado de una persona. Ninguno va en rojo: en
 * Contratos el rojo es solo del art. 77, que vuelve indefinido un contrato de
 * TRABAJO por ley, y aquí no aplica. El color nunca va solo: lleva su palabra.
 */
export const ESTADO_PERSONA: Record<EstadoPersonaLocacion, { texto: string; variante: Variante }> = {
  abierta_sin_rxh: { texto: "Locación abierta", variante: "advertencia" },
  vencido: { texto: "Vencido", variante: "advertencia" },
  sin_contrato: { texto: "Sin contrato", variante: "neutral" },
  por_vencer: { texto: "Vence pronto", variante: "advertencia" },
  por_empezar: { texto: "Por empezar", variante: "informativo" },
  vigente: { texto: "Vigente", variante: "positivo" },
};

export const ESTADO_CONTRATO: Record<EstadoContratoLocacion, { texto: string; variante: Variante }> = {
  en_curso: { texto: "En curso", variante: "positivo" },
  por_empezar: { texto: "Por empezar", variante: "informativo" },
  concluido: { texto: "Concluido", variante: "neutral" },
  terminado: { texto: "Terminado antes", variante: "neutral" },
  anulado: { texto: "Anulado", variante: "neutral" },
};

/** Las bandas de la pestaña, en el orden en que se leen: lo que urge primero. */
export type BandaLocacion = "abierta" | "sin_cubrir" | "pronto" | "al_dia";

export const BANDAS_LOCACION: readonly { clave: BandaLocacion; titulo: string; ayuda: string }[] = [
  {
    clave: "abierta",
    titulo: "Ya no cobra por honorarios",
    ayuda: "Pasó a otro vínculo o ya cesó, y su locación sigue abierta: termínala con el último día en que valió.",
  },
  {
    clave: "sin_cubrir",
    titulo: "Trabaja sin contrato vigente",
    ayuda: "No tiene contrato registrado, o el último ya terminó. Es lo primero que falta resolver.",
  },
  {
    clave: "pronto",
    titulo: "Vence pronto",
    ayuda: "Termina en los próximos 60 días y no hay otro registrado que siga.",
  },
  {
    clave: "al_dia",
    titulo: "Al día",
    ayuda: "Con contrato vigente, o con uno firmado que empieza pronto.",
  },
];

export function bandaLocacion(estado: EstadoPersonaLocacion): BandaLocacion {
  if (estado === "abierta_sin_rxh") return "abierta";
  if (estado === "vencido" || estado === "sin_contrato") return "sin_cubrir";
  if (estado === "por_vencer") return "pronto";
  return "al_dia";
}

/** Cuántas personas piden algo hoy: el número rojo de la pestaña. */
export function cuantasParaAtender(filas: readonly FilaTableroLocacion[]): number {
  return filas.filter((f) => bandaLocacion(f.estado) !== "al_dia").length;
}

/** «Hoy está en Planilla», «Ya cesó»: lo que la persona es hoy, para la fila que ya no es RxH. */
export function textoVinculoActual(vinculo: string): string {
  if (vinculo === "cesada") return "Ya cesó";
  const etiqueta = TIPO_VINCULO_LABEL[vinculo as TipoVinculo];
  return etiqueta ? `Hoy está en ${etiqueta}` : "Ya no cobra por honorarios";
}

/** Cuántos meses dura, por defecto, un contrato nuevo. Se ve y se cambia en un clic. */
export const MESES_POR_DEFECTO = 6;

/**
 * Las fechas con que NACE el formulario de registrar (regla de la casa: una
 * fecha cuyo vacío bloquea el envío no arranca en blanco). Si la persona está
 * cubierta hasta una fecha futura, lo más probable es la renovación: empieza
 * al día siguiente. Si no, empieza hoy. Se firma hoy.
 */
export function fechasSugeridas(
  f: Pick<FilaTableroLocacion, "cubierto_hasta">,
  hoy: string,
): { inicio: string; fin: string; firma: string } {
  const inicio = f.cubierto_hasta && f.cubierto_hasta >= hoy ? sumarDias(f.cubierto_hasta, 1) : hoy;
  return { inicio, fin: sumarDias(sumarMeses(inicio, MESES_POR_DEFECTO), -1), firma: hoy };
}

/** «Venció hace 3 días», «Vence en 12 días», «Vence hoy». `null` cuando no hay contrato. */
export function textoPlazo(f: Pick<FilaTableroLocacion, "estado" | "dias_restantes">): string | null {
  const d = f.dias_restantes;
  if (d === null || f.estado === "sin_contrato") return null;
  if (d < 0) return d === -1 ? "Venció ayer" : `Venció hace ${-d} días`;
  if (d === 0) return "Vence hoy";
  return d === 1 ? "Vence mañana" : `Vence en ${d} días`;
}
