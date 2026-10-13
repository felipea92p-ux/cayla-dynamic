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
 * En qué punto del día está una persona — para PINTARLO, no para decidir qué
 * marca le toca (eso sigue siendo `determinarSiguienteAccion`, y es la única que
 * manda).
 *
 * Se DERIVA de los marcajes y nunca se guarda aparte: dos fuentes de verdad
 * sobre dónde está alguien acaban contradiciéndose, y la pantalla le diría a
 * una persona «Laborando» mientras el terminal le ofrece «Volver».
 *
 * Mismas ramas, en el mismo orden, que `determinarSiguienteAccion` — y por eso
 * `tests/estado-presencia.test.ts` comprueba, secuencia por secuencia, que las
 * dos responden lo mismo:
 *   sin entrada         ↔ ofrece «entrada»
 *   termino             ↔ día cerrado
 *   refrigerio / pausa  ↔ ofrece el retorno de esa salida
 *   laborando           ↔ ofrece elegir cómo salir
 *
 * «Pausa» es cualquier salida temporal que NO sea refrigerio (trámite, médico,
 * personal, otra): el refrigerio tiene su propio estado porque es el caso más
 * frecuente y es el que más se mira.
 *
 * No sabe nada del horario: «libre hoy» o «entra a las 14:00» necesitan
 * `jornada-esperada.ts` y viven en el terminal (`lib/terminal/presencia.ts`).
 */
export type EstadoPresencia =
  | { estado: "sin_entrada" }
  | {
      estado: "laborando";
      /**
       * ISO de la PRIMERA entrada del día. Se conserva aunque haya salido y vuelto:
       * si la pantalla dijera solo «desde las 13:45» —la hora del regreso—, parecería
       * que llegó a las 13:45, o sea tarde, y la mañana trabajada desaparecería.
       */
      entrada: string;
      /**
       * El último regreso, solo si lo ÚLTIMO que hizo fue volver de una salida.
       * Lleva la hora de la salida de la que volvió —no solo la del regreso—: «volvió
       * 13:45» a secas no dice de cuándo a cuándo estuvo fuera. Cada regreso se
       * empareja con SU salida (el trámite de la tarde, no el refrigerio de la mañana).
       * `salio` falta solo si los datos están incompletos (un regreso sin su salida).
       */
      regreso?: { volvio: string; salio?: string };
    }
  | { estado: "refrigerio"; desde: string }
  | { estado: "pausa"; /** El tipo de la salida (`salida_tramite`…). */ motivo: TipoMarca; desde: string }
  | { estado: "termino"; /** ISO de la salida final. */ a: string };

export type ClaveEstadoPresencia = EstadoPresencia["estado"];

export function estadoPresencia(marcajesHoy: MarcajeDelDia[]): EstadoPresencia {
  const ordenados = [...marcajesHoy].sort((a, b) => a.timestamp.localeCompare(b.timestamp));
  const ultimo = ordenados[ordenados.length - 1];

  if (!ordenados.some((m) => m.tipo === "entrada")) return { estado: "sin_entrada" };

  // Igual que la máquina: CUALQUIER salida final cierra el día, no solo si es
  // la última marca (las anuladas ya no llegan acá).
  const final = [...ordenados].reverse().find((m) => m.tipo === "salida_final");
  if (final) return { estado: "termino", a: final.timestamp };

  if (ultimo.tipo in PARES_SALIDA_RETORNO) {
    return ultimo.tipo === "salida_almuerzo"
      ? { estado: "refrigerio", desde: ultimo.timestamp }
      : { estado: "pausa", motivo: ultimo.tipo, desde: ultimo.timestamp };
  }

  // Llegó acá: tiene entrada, no cerró, y no está en una salida abierta. Lo
  // último que hizo es la entrada misma o el regreso de una salida.
  const entrada = ordenados.find((m) => m.tipo === "entrada")!;
  if (ultimo.tipo === "entrada") return { estado: "laborando", entrada: entrada.timestamp };

  // La salida de la que acaba de volver: la última marca ANTERIOR del tipo que
  // este regreso cierra (`salida_tramite` ↔ `retorno_tramite`…).
  const salidaDeEsteRegreso = Object.keys(PARES_SALIDA_RETORNO).find((k) => PARES_SALIDA_RETORNO[k] === ultimo.tipo);
  const salio = [...ordenados]
    .slice(0, -1)
    .reverse()
    .find((m) => m.tipo === salidaDeEsteRegreso);
  return {
    estado: "laborando",
    entrada: entrada.timestamp,
    regreso: salio ? { volvio: ultimo.timestamp, salio: salio.timestamp } : { volvio: ultimo.timestamp },
  };
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
