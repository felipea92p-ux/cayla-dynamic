// ============================================================================
// jornada.ts — Los topes de jornada, en un solo sitio
// ============================================================================
// Están acá y no escritos a mano en cada pantalla por la misma razón que
// `permisos.ts` y `fecha-lima.ts`: son números que deciden si alguien está
// dentro o fuera de la ley, y no pueden tener dos versiones.
//
// La distinción entre los dos es lo que evita un pasivo, así que conviene
// tenerla clara antes de tocarlos:
//
//   MAXIMO_LEGAL_SEMANAL (48 h)  Tope constitucional (art. 25). Es la JORNADA
//                                ORDINARIA pactada en los contratos de CAYLA y
//                                declarada en el RIT. Pasarse de acá es
//                                infracción, no algo que se pueda pagar.
//
//   HORARIO_PROGRAMADO_SEMANAL   Lo que CAYLA efectivamente programa. Es una
//   (45 h)                       decisión de la empresa, revisable dentro de la
//                                jornada ordinaria, y NO es el umbral del
//                                sobretiempo.
//
// ⚠️ El sobretiempo se mide contra la jornada ORDINARIA (48), no contra el
// horario programado (45) — D.S. 007-2002-TR art. 9. Igualar estas dos
// constantes convertiría las horas 46 a 48 en sobretiempo con recargo del
// 25 % / 35 %, y hoy hay gente trabajando en ese rango.
//
// Si cambian, hay que cambiar a la vez: los contratos, el RIT (art. de jornada,
// v3.2) y la política salarial publicada. Los cuatro dicen lo mismo a propósito.
// ============================================================================

/** Tope constitucional y jornada ordinaria pactada. Pasarse es infracción. */
export const MAXIMO_LEGAL_SEMANAL = 48;

/** Lo que CAYLA programa. Por debajo del tope, por decisión de la empresa. */
export const HORARIO_PROGRAMADO_SEMANAL = 45;

/**
 * Recargo del sobretiempo sobre el valor de la hora ordinaria
 * (D.S. 007-2002-TR art. 10). Las dos primeras horas al 25 %, el resto al 35 %.
 */
export const RECARGO_SOBRETIEMPO = {
  /** Horas a las que aplica el primer tramo. */
  horasPrimerTramo: 2,
  primerTramo: 0.25,
  tramoSiguiente: 0.35,
} as const;

/**
 * Cuántas horas de una semana exceden la jornada ordinaria.
 * Devuelve 0 cuando no hay exceso — nunca un negativo.
 */
export function excesoSobreJornada(horasSemana: number): number {
  return Math.max(0, horasSemana - MAXIMO_LEGAL_SEMANAL);
}

// ── Descanso semanal ────────────────────────────────────────────────────────
// El D. Leg. 713 art. 1 da derecho a 24 horas consecutivas de descanso «en cada
// semana». Y el Informe 027-2021-MTPE/14 de la Dirección General de Trabajo
// —criterio VINCULANTE para la administración laboral— aclara qué es «semana»:
//
//   «la semana debe ser entendida como el período o ciclo de siete días,
//    indistintamente si dichos siete días se corresponden con los que se
//    ordenan cronológicamente en los calendarios: lunes a domingo»
//
// La diferencia no es teórica. Con semana calendario y descanso rotativo se
// puede cumplir «un descanso por semana» y encadenar doce días: descansar el
// lunes de una semana y el domingo de la siguiente. Cada semana cuadra, la
// persona trabajó doce días seguidos. Medido en CAYLA el 2026-08-08: 30 rachas
// desde enero, la peor de 20 días.
//
// Por eso el tope se cuenta en DÍAS CONSECUTIVOS y no por semana calendario.

/** Días seguidos que se pueden trabajar. El siguiente tiene que ser descanso. */
export const MAXIMO_DIAS_SIN_DESCANSO = 6;

/**
 * Cuántos días seguidos lleva trabajados una persona, contando hacia atrás desde
 * `hasta`. Devuelve 0 si ese día no trabajó — la racha se cortó, que es lo que
 * hace un descanso.
 *
 * `fechas` son los días CON horas marcadas, en formato ISO (YYYY-MM-DD). El
 * orden no importa. Vacaciones, permisos y descansos simplemente no están en la
 * lista, y por eso cortan la racha.
 */
export function diasSeguidosTrabajados(fechas: readonly string[], hasta: string): number {
  const set = new Set(fechas);
  if (!set.has(hasta)) return 0;
  let dias = 0;
  // Se cuenta en UTC a propósito: son fechas civiles (YYYY-MM-DD), no instantes.
  // Restar días sobre una fecha local cruzaría mal el cambio de día en Lima.
  const cursor = new Date(`${hasta}T00:00:00Z`);
  while (set.has(cursor.toISOString().slice(0, 10))) {
    dias++;
    cursor.setUTCDate(cursor.getUTCDate() - 1);
  }
  return dias;
}

/**
 * Las horas de la ventana de 7 días consecutivos MÁS CARGADA que termina dentro
 * del rango mirado. Devuelve la ventana y sus horas, o `null` si no hay datos.
 *
 * Por qué una ventana móvil y no la semana de lunes a domingo: el mismo Informe
 * 027-2021-MTPE/14 dice que la semana, «para los efectos de la determinación del
 * tiempo de trabajo», es un ciclo de siete días y no el que ordena el calendario.
 *
 * La diferencia se ve con doce días seguidos de 8 h. Partidos en semanas de
 * calendario dan 48 y 48 —ninguna se pasa— pero cualquier ventana de siete días
 * de esa racha suma 56. Medir por calendario deja pasar justo el caso que hay
 * que ver.
 */
export function ventanaMasCargada(
  dias: readonly { fecha: string; horas: number }[],
  desde: string,
  hasta: string,
): { fin: string; horas: number } | null {
  const porFecha = new Map<string, number>();
  for (const d of dias) porFecha.set(d.fecha, (porFecha.get(d.fecha) ?? 0) + d.horas);

  let mejor: { fin: string; horas: number } | null = null;
  const cursor = new Date(`${desde}T00:00:00Z`);
  const tope = new Date(`${hasta}T00:00:00Z`);
  while (cursor <= tope) {
    const fin = cursor.toISOString().slice(0, 10);
    // La ventana es el día y los seis anteriores: siete días consecutivos.
    let suma = 0;
    const atras = new Date(cursor);
    for (let i = 0; i < 7; i++) {
      suma += porFecha.get(atras.toISOString().slice(0, 10)) ?? 0;
      atras.setUTCDate(atras.getUTCDate() - 1);
    }
    if (mejor === null || suma > mejor.horas) mejor = { fin, horas: suma };
    cursor.setUTCDate(cursor.getUTCDate() + 1);
  }
  return mejor;
}
