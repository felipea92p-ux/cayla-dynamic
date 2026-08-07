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
