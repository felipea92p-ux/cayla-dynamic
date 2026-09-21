// ============================================================================
// cobertura-turnos.ts — lo que Turnos le dice a quien arma la semana
// ============================================================================
// QUÉ PROMETE · convertir el resumen de cobertura de un día en la frase y el tono
//               con que se muestra, decidir de qué color se pinta una hora, y
//               decir cuándo un día simplemente no se labora (etiquetaSedeSinTurnos).
// QUÉ ASUME   · que la cobertura cuenta SOLO a un grupo —las personas de áreas
//               operativas, o los líderes de equipo—: «nadie» quiere decir
//               «nadie de ese grupo», nunca «nadie programado». La excepción es
//               etiquetaSedeSinTurnos, que sí habla de la sede entera: su primer
//               argumento sale de jornada-esperada.ts con TODAS las personas.
//
// Por qué existe (2026-09-18): Oficina TRU tiene cinco personas y todas están
// en áreas que no son operativas (Expansión y otras). Turnos las dibujaba
// —cinco barras, cada una con su turno— y aun así el día decía «sin turnos», y
// la franja de cobertura salía como un bloque café sólido de punta a punta,
// idéntico a «todo cubierto». Las dos cosas eran ciertas para el grupo medido
// (no hay ninguna operativa) y falsas para quien miraba la pantalla (sí hay
// turnos). La regla de que la cobertura solo cuenta áreas operativas estaba
// escrita al pie de la página; el resultado, en el encabezado de cada día.
// ============================================================================

import { SEDE_SIN_TURNOS, type DiaDeLaSede } from "@/lib/admin/jornada-esperada";

// «lideres» son los líderes de equipo (en el código se siguen llamando `esEncargada`,
// por historia: el rol es `supervisor_sede`; en pantalla es «líder de equipo»).
export type QuienSeMide = "operativas" | "lideres";

/** De qué tono se pinta la frase: rojo, gris neutro, o el color del porcentaje. */
export type TonoCobertura = "alerta" | "neutro" | "porcentaje";

export interface ResumenParaEtiqueta {
  quien: QuienSeMide;
  /** ¿Hay al menos una persona DEL GRUPO MEDIDO programada ese día? (no «alguien»). */
  hayGente: boolean;
  /** Hay gente del grupo, pero no hay meta contra la que medirla. */
  sinMeta: boolean;
  /** ¿Se puso una meta (> 0) para ese día? */
  hayMeta: boolean;
  /** Porcentaje cubierto (0–100). Solo importa si hay gente y hay meta. */
  pct: number;
}

// Cada grupo con su concordancia: «ninguna operativa» pero «ningún líder».
const SIN_NADIE: Record<QuienSeMide, { alerta: string; dato: string }> = {
  operativas: { alerta: "¡ninguna operativa programada!", dato: "sin operativas programadas" },
  lideres: { alerta: "¡ningún líder programado!", dato: "sin líderes programados" },
};

/**
 * La frase de cada día: «cubierto 75 %», «sin meta», o —cuando no hay nadie del
 * grupo— lo que de verdad pasa. Con meta puesta y nadie del grupo es una alerta
 * roja (alguien olvidó armar los turnos); sin meta, es solo un dato.
 *
 * Nunca dice «sin turnos»: ese día puede tener turnos de sobra, de personas que
 * este grupo no cuenta. Cuando de verdad no hay ninguno en toda la sede, eso lo
 * dice etiquetaSedeSinTurnos, que mira a la sede entera y no a un grupo.
 */
export function etiquetaCobertura(r: ResumenParaEtiqueta): { texto: string; tono: TonoCobertura } {
  const sinNadie = SIN_NADIE[r.quien];
  if (!r.hayGente && r.hayMeta) return { texto: sinNadie.alerta, tono: "alerta" };
  if (r.sinMeta) return { texto: "sin meta", tono: "neutro" };
  if (!r.hayGente) return { texto: sinNadie.dato, tono: "neutro" };
  return { texto: `cubierto ${r.pct}%`, tono: "porcentaje" };
}

// ----------------------------------------------------------------------------
// Un día en que la sede no se labora (2026-09-20)
// ----------------------------------------------------------------------------
// Central trabaja de lunes a sábado: el domingo nadie tiene turno y su meta de
// líderes es 0. Turnos decía, en gris, «sin operativas programadas» y «sin
// líderes programados» —dos frases que suenan a algo que salió mal cuando es
// exactamente lo esperado—, la misma falsa alarma que el Dashboard, Incidencias
// y la Hoja de sede daban ese día. Ahora los días así dicen UNA palabra, la de
// SEDE_SIN_TURNOS, igual en las cuatro pantallas.
//
// Solo se dice cuando se cumplen las DOS cosas:
//   1. A nadie de la sede le toca (`dia` ≠ «trabaja»). Cuenta la sede entera, no
//      el grupo medido: si una oficina tiene turnos, el día SÍ tiene turnos y
//      «sin operativas programadas» es el dato correcto (2026-09-18, arriba).
//   2. Las TRES metas del día valen 0 (mañana, tarde y líderes). Con cualquier
//      meta puesta y nadie programado los datos se contradicen, y en Turnos —la
//      pantalla donde se arma la semana— eso es que alguien olvidó armar los
//      turnos: sigue en rojo. El Dashboard, que no es donde se arma, lo baja a
//      ámbar «Meta sin turnos» y manda acá; acá no hay a dónde mandar.
//
// «sin_horario» (un tramo venció, sede nueva, equipo vacío) NO autoriza a callar
// una alarma —es «no se sabe», no «hoy no abre»—, pero con las tres metas en 0 no
// hay alarma que callar: la palabra gris solo dice lo que es cierto.
// ----------------------------------------------------------------------------

/** Las tres metas de un día de la semana: operativas de la mañana y de la tarde, y líderes. */
export interface MetasDelDia {
  manana: number;
  tarde: number;
  lideres: number;
}

/**
 * La palabra gris de un día en que la sede no se labora, o `null` si el día se
 * muestra como siempre (con `etiquetaCobertura`). `dia` es la respuesta de
 * `diaDeLaSedeDe` sobre TODAS las personas de la grilla.
 *
 * En la vista Día sale una sola vez en el encabezado, en lugar de las frases de
 * los dos grupos; en la vista Semana, una por tarjeta.
 */
export function etiquetaSedeSinTurnos(
  dia: DiaDeLaSede,
  metas: MetasDelDia,
): { texto: string; tono: TonoCobertura } | null {
  // Nombradas, no «todo lo que no sea `trabaja`»: una respuesta nueva de `diaDeLaSede`
  // no puede caer aquí y decir «Sin turnos» sin que alguien lo haya decidido.
  if (dia !== "no_trabaja" && dia !== "sin_horario") return null;
  if (metas.manana > 0 || metas.tarde > 0 || metas.lideres > 0) return null;
  return { texto: SEDE_SIN_TURNOS, tono: "neutro" };
}

// Rojo → Verde según qué tan cerca está de la meta; a partir de la meta queda
// verde sólido (el excedente ya no necesita más degradado).
//
// SIN META no hay contra qué medir, y se distingue de dos maneras. Con gente:
// taupe neutro (no rojo: el rojo sin significado solo mete ruido de alarma).
// Sin nadie: arena tenue —el mismo criterio que ya usaba la vista Integrada—,
// porque un bloque de taupe sólido de punta a punta, incluso en las horas en
// que no trabaja nadie, se lee como «todo cubierto» y no como «no se mide».
//
// `color-mix()` en vez de interpolar RGB a mano: así el navegador resuelve el
// color con los valores del tema activo en cada pintado (en oscuro esos tokens
// son otros, y el texto de encima sigue leyéndose). Medido el 2026-09-07:
// 4.70:1 a 6.26:1 contra el degradado completo.
export function colorCobertura(n: number, meta: number): string {
  if (meta <= 0) {
    return n > 0 ? "var(--color-taupe)" : "color-mix(in srgb, var(--color-sand) 35%, transparent)";
  }
  const ratioPct = Math.round(Math.min(n / meta, 1) * 100);
  return `color-mix(in oklab, var(--color-verde) ${ratioPct}%, var(--color-rojo))`;
}
