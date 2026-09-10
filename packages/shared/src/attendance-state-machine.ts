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
 * Lo que se sabe del RITMO de una persona, para afinar la sugerencia de salida
 * más allá de la regla fija de siempre. Ambos campos son horas decimales Lima
 * (13.5 = 13:30) y pueden faltar por separado — una persona nueva puede tener
 * horario asignado sin historial de refrigerio todavía, y viceversa.
 */
export interface EstadisticasSugerencia {
  /** Media de sus últimas salidas a refrigerio (≥3 muestras en 30 días), o null si no hay patrón. */
  horaMediaRefrigerio: number | null;
  /** Su hora de salida esperada HOY según horario asignado (jornada-esperada.ts), o null sin horario. */
  horaSalidaEsperada: number | null;
}

/**
 * Media de la hora del día (Lima) de una lista de marcajes de salida a
 * refrigerio. Exige al menos 3 muestras para hablar de "patrón" — con menos,
 * un solo día atípico decidiría la sugerencia entera.
 */
export function calcularHoraMediaRefrigerio(
  timestampsISO: string[],
): { media: number; muestras: number } | null {
  if (timestampsISO.length < 3) return null;
  const horas = timestampsISO.map((t) => horaDecimalLima(new Date(t)));
  const media = horas.reduce((a, b) => a + b, 0) / horas.length;
  return { media, muestras: horas.length };
}

const TOLERANCIA_HORAS = 0.5; // ±30 min

/**
 * Sugiere la salida PRINCIPAL a destacar según tres zonas horarias — para que
 * el terminal muestre una acción obvia en vez de un menú de 6 opciones
 * iguales. No cambia qué es válido (todas las salidas siguen permitidas por
 * fn_registrar_marcaje); solo qué se sugiere.
 *
 * Sin `estadisticas` (u omitiendo sus dos campos), el comportamiento es
 * IDÉNTICO al de siempre: regla fija de horario (11–16h Lima, ≥2h adentro)
 * para refrigerio, salida final en cualquier otro caso. La zona "neutra"
 * solo es alcanzable con datos reales de horario — ningún llamador existente
 * puede empezar a recibirla sin pasar el tercer argumento.
 *
 * Con `estadisticas`:
 *  - Si hay patrón de refrigerio (`horaMediaRefrigerio`): se confía en él por
 *    completo dentro de ±30 min — no se vuelve a probar la regla fija encima
 *    (mezclar los dos criterios sería la misma pregunta resuelta dos veces).
 *  - Si no hay patrón, sigue la regla fija de siempre.
 *  - Si ninguna de las dos aplicó: con horario asignado (`horaSalidaEsperada`),
 *    ya se sabe con certeza si toca salida final o si es demasiado pronto
 *    ("neutra" — ni refrigerio ni salida final tienen sentido ahora). Sin
 *    horario asignado, salida final sigue siendo el respaldo de siempre.
 */
export function sugerirSalidaPrincipal(
  marcajesHoy: MarcajeDelDia[],
  ahora: Date,
  estadisticas?: EstadisticasSugerencia,
): "salida_almuerzo" | "salida_final" | "neutra" {
  const yaAlmorzo = marcajesHoy.some((m) => m.tipo === "salida_almuerzo");
  const hora = horaDecimalLima(ahora);

  if (!yaAlmorzo) {
    if (estadisticas?.horaMediaRefrigerio != null) {
      if (Math.abs(hora - estadisticas.horaMediaRefrigerio) <= TOLERANCIA_HORAS) {
        return "salida_almuerzo";
      }
    } else {
      const entrada = marcajesHoy.find((m) => m.tipo === "entrada");
      const horasDentro = entrada ? (ahora.getTime() - new Date(entrada.timestamp).getTime()) / 3_600_000 : 0;
      if (Math.floor(hora) >= 11 && Math.floor(hora) < 16 && horasDentro >= 2) return "salida_almuerzo";
    }
  }

  if (estadisticas?.horaSalidaEsperada != null) {
    return hora >= estadisticas.horaSalidaEsperada - TOLERANCIA_HORAS ? "salida_final" : "neutra";
  }
  return "salida_final";
}
