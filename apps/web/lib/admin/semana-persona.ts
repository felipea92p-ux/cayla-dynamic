// ============================================================================
// semana-persona.ts — la semana de una persona en una línea por día (Correcciones)
// ============================================================================
// QUÉ PROMETE   · decir, para cada día de la semana de alguien, UNA frase corta y su tono: «Sin jornada», «8 h 03»,
//                 «25 min tarde» o «25 min · levantada». Es el navegador de días de Correcciones: se mira la semana y
//                 se salta al día que importa sin abrir el calendario.
// QUÉ ASUME     · la jornada de ese día YA calculada (`jornadas`) y, aparte, si DO levantó su tardanza
//                 (`tardanzas_justificadas`). No recalcula nada ni adivina qué le tocaba trabajar.
// QUÉ NO HACE   · no decide si faltó. «Sin jornada» es lo que hay —un descanso, una falta o un día sin marcar se ven igual
//                 en `jornadas`—, y esta pantalla no acusa: para eso están las faltas de Incidencias.
//                 Tampoco acusa por un día futuro: ahí dice «—».
// ============================================================================
import { JORNADA_ESTADO_LABELS, MINUTOS_MAXIMOS_TARDANZA_MEDIBLE, formatoMinutos } from "@cayla-dynamic/shared";

export type TonoDiaSemana = "tarde" | "ok" | "aviso" | "neutro";

export interface JornadaDeLaSemana {
  fecha: string;
  estado: string;
  horas_trabajadas: number | null;
  minutos_tarde: number | null;
}

export interface ResumenDiaSemana {
  texto: string;
  tono: TonoDiaSemana;
  /** La tardanza se tacha: DO la levantó. El texto sigue diciendo cuánto fue. */
  tachado: boolean;
  /** Palabra extra que acompaña a un texto tachado («levantada»). */
  nota?: string;
}

export function resumenDiaSemana(p: {
  fecha: string;
  hoy: string;
  jornada: JornadaDeLaSemana | null;
  levantada: boolean;
}): ResumenDiaSemana {
  const { jornada: j } = p;
  if (!j) {
    return p.fecha > p.hoy
      ? { texto: "—", tono: "neutro", tachado: false }
      : { texto: "Sin jornada", tono: "neutro", tachado: false };
  }
  const tarde = j.minutos_tarde ?? 0;
  if (tarde > MINUTOS_MAXIMOS_TARDANZA_MEDIBLE) {
    // Más de 3 h no es una medición confiable (RIT 17.5): no se llama tardanza hasta verificar el horario.
    return { texto: "Revisar horario", tono: "aviso", tachado: false };
  }
  if (tarde > 0 && p.levantada) {
    return { texto: formatoMinutos(tarde), tono: "neutro", tachado: true, nota: "levantada" };
  }
  if (tarde > 0) return { texto: `${formatoMinutos(tarde)} tarde`, tono: "tarde", tachado: false };
  if (j.horas_trabajadas != null) {
    return { texto: formatoMinutos(Math.round(j.horas_trabajadas * 60)), tono: "ok", tachado: false };
  }
  return { texto: JORNADA_ESTADO_LABELS[j.estado] ?? j.estado, tono: "neutro", tachado: false };
}
