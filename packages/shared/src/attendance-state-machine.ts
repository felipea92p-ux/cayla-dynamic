import { PARES_SALIDA_RETORNO, type TipoMarca } from "./enums";
import { horaDecimalLima } from "./fecha-lima";

export interface MarcajeDelDia {
  tipo: TipoMarca;
  timestamp: string; // ISO
}

export type SiguienteAccion =
  | { modo: "unico"; tipo: Extract<TipoMarca, "entrada"> }
  | { modo: "unico"; tipo: TipoMarca /* retorno_* */; motivoRequerido: false }
  | {
      modo: "elegir_salida";
      opciones: Array<{ tipo: TipoMarca; motivoRequerido: boolean }>;
    }
  | { modo: "cerrado"; mensaje: string };

const OPCIONES_SALIDA: Array<{ tipo: TipoMarca; motivoRequerido: boolean }> = [
  { tipo: "salida_final", motivoRequerido: false },
  { tipo: "salida_almuerzo", motivoRequerido: false },
  { tipo: "salida_personal", motivoRequerido: false },
  { tipo: "salida_tramite", motivoRequerido: false },
  { tipo: "salida_medico", motivoRequerido: false },
  { tipo: "salida_otro", motivoRequerido: true },
];

/**
 * Determina la única acción válida (o el pequeño set de tipos de salida a
 * elegir) para una persona dado su historial de marcajes de HOY, ordenado
 * cronológicamente. Este es el corazón de la prevención de doble marcado:
 * el terminal nunca deja elegir "entrada" vs "salida" a mano, salvo el caso
 * inherente de "¿por qué salgo?" que solo la persona puede saber.
 *
 * Debe reflejar exactamente la lógica de fn_registrar_marcaje en Postgres
 * (supabase/migrations) — cualquier cambio aquí debe replicarse allá.
 */
export function determinarSiguienteAccion(marcajesHoy: MarcajeDelDia[]): SiguienteAccion {
  const ordenados = [...marcajesHoy].sort((a, b) => a.timestamp.localeCompare(b.timestamp));
  const ultimo = ordenados[ordenados.length - 1];

  const tieneEntrada = ordenados.some((m) => m.tipo === "entrada");
  if (!tieneEntrada) {
    return { modo: "unico", tipo: "entrada" };
  }

  const tieneSalidaFinal = ordenados.some((m) => m.tipo === "salida_final");
  if (tieneSalidaFinal) {
    return { modo: "cerrado", mensaje: "Ya registraste tu salida final de hoy." };
  }

  // ¿Hay una salida temporal abierta (sin su retorno correspondiente)? Si sí,
  // la única acción posible es ese retorno específico — sin ambigüedad.
  if (ultimo.tipo in PARES_SALIDA_RETORNO) {
    const retornoEsperado = PARES_SALIDA_RETORNO[ultimo.tipo];
    return { modo: "unico", tipo: retornoEsperado, motivoRequerido: false };
  }

  // Está "adentro": ya marcó entrada, no tiene salida temporal pendiente de
  // retorno, y no ha marcado salida final. Debe elegir qué tipo de salida.
  return { modo: "elegir_salida", opciones: OPCIONES_SALIDA };
}

/**
 * Sugiere la salida PRINCIPAL a destacar (refrigerio vs salida final) según la hora
 * local y si la persona ya almorzó hoy — para que el terminal muestre una acción
 * obvia en vez de un menú de 6 opciones iguales. No cambia qué es válido (todas las
 * salidas siguen permitidas por fn_registrar_marcaje); solo qué se sugiere.
 *
 *  - Si ya almorzó hoy → salida final.
 *  - Si es mediodía (11–16h Lima), lleva ≥2h adentro y aún no almorzó → refrigerio.
 *  - En cualquier otro caso (temprano, tarde, o turno corto) → salida final.
 */
export function sugerirSalidaPrincipal(
  marcajesHoy: MarcajeDelDia[],
  ahora: Date,
): "salida_almuerzo" | "salida_final" {
  if (marcajesHoy.some((m) => m.tipo === "salida_almuerzo")) return "salida_final";
  const entrada = marcajesHoy.find((m) => m.tipo === "entrada");
  const horasDentro = entrada ? (ahora.getTime() - new Date(entrada.timestamp).getTime()) / 3_600_000 : 0;
  const hora = Math.floor(horaDecimalLima(ahora));
  if (hora >= 11 && hora < 16 && horasDentro >= 2) return "salida_almuerzo";
  return "salida_final";
}
