// ============================================================================
// revision-turnos.ts — qué pasa si un día que ya corrió vuelve al horario base
// ============================================================================
// QUÉ PROMETE · la frase que Revisión de Turnos muestra ANTES de quitar el turno
//               de un día que ya se midió: a qué hora marcó y qué esperaba el
//               horario base, en hechos.
// QUÉ ASUME   · que la jornada se recalcula contra el horario base al quitar el
//               turno (fn_quitar_turno → fn_recalcular_jornada) y que eso solo
//               lo frena un periodo PAGADO, no uno abierto.
//
// Por qué existe (2026-09-26): el panel lista turnos desde el inicio del periodo
// abierto, así que casi todas sus filas son pasadas. Diana, viernes 11 de
// septiembre: turno 13:45, horario base 07:45. «Usar el horario base» quitaba el
// turno sin preguntar, y si entró a las 13:45 —la hora que le habían dado— su
// jornada pasaba a medirse contra las 07:45: seis horas de tardanza que no tuvo.
// Con un turno de DESCANSO es peor: el día vuelve a ser laborable y sin marcaje.
//
// A veces es justo lo que hay que hacer (un espejo viejo que venía causando la
// tardanza falsa al revés), así que no se bloquea: se muestra.
//
// Solo aritmética de horas. Si la diferencia termina en tardanza, en falta o en
// nada lo decide fn_recalcular_jornada (tolerancias, feriados, vacaciones), y
// esta frase no vuelve a escribir esa regla: por eso dice «puede».
// ============================================================================

export interface DiaParaRevisar {
  /** «vie 11», para la frase. */
  etiqueta: string;
  /** El turno como se muestra: «13:45–19:45» o «descanso». */
  turnoTxt: string;
  /** El horario base como se muestra. */
  baseTxt: string;
  /** Entrada del turno (null = el turno era descanso). */
  turnoEntrada: string | null;
  /** Entrada del horario base ese día (null = ese día el horario base es descanso). */
  baseEntrada: string | null;
  /** Hora de Lima a la que marcó su entrada ese día, o null si no marcó. */
  marco: string | null;
}

const minutos = (hm: string) => {
  const [h, m] = hm.split(":").map(Number);
  return (h ?? 0) * 60 + (m ?? 0);
};

function duracion(min: number): string {
  const a = Math.abs(min);
  return a >= 60 ? `${Math.floor(a / 60)} h ${a % 60} min` : `${a} min`;
}

export function consecuenciaDeUsarBase(d: DiaParaRevisar): string {
  const dia = `El ${d.etiqueta} ya se midió contra su turno (${d.turnoTxt}).`;
  if (!d.baseEntrada) {
    return `${dia} Con el horario base ese día era descanso: lo que trabajó se medirá contra un día sin horario.`;
  }
  if (!d.marco) {
    return d.turnoEntrada === null
      ? `${dia} Con el horario base le tocaba trabajar (${d.baseTxt}) y no tiene marcaje de entrada: puede quedar como falta.`
      : `${dia} No tiene marcaje de entrada; con el horario base le tocaba ${d.baseTxt}.`;
  }
  const diff = minutos(d.marco) - minutos(d.baseEntrada);
  const rel =
    diff > 0 ? `${duracion(diff)} después de la entrada del horario base (${d.baseEntrada}): puede quedar como tardanza`
    : diff < 0 ? `${duracion(diff)} antes de la entrada del horario base (${d.baseEntrada})`
    : "justo a la entrada del horario base";
  return `${dia} Marcó a las ${d.marco}: ${rel}.`;
}
