// ============================================================================
// cobertura-hoja-sede.ts — cuándo la Hoja de sede NO mide la cobertura de hoy
// ============================================================================
// QUÉ PROMETE · dado qué día es HOY para la sede (`diaDeLaSede`, de
//               jornada-esperada.ts) y en qué estado está cada integrante,
//               decir si el recuadro «Hoy» apaga su línea de cobertura
//               («Líderes en piso 0 / meta 1 · faltan 1») en vez de pintarla.
// QUÉ ASUME   · que `dia` salió de `diaDeLaSedeDe` —nunca de una cuenta propia— y
//               que cada estado sale de `jornadas.estado` de HOY, o «sin_marcar»
//               si esa persona no tiene fila de hoy.
//
// POR QUÉ EXISTE (2026-09-20). Central tiene meta de 1 líder el domingo, pero el
// domingo nadie de Central tiene turno: trabaja de lunes a sábado. La Hoja de
// sede decía «faltan 1» en rojo por una falta que ninguna asistencia podía
// arreglar, porque a nadie le tocaba ir — y esta hoja es la que se IMPRIME, se
// firma y se lleva a la sede: el rojo queda escrito en papel. El Dashboard,
// Incidencias y Turnos ya tenían el mismo problema; los cuatro se corrigieron con
// una sola pregunta (`diaDeLaSede`) para que ninguno pueda contestar distinto.
//
// Vive acá y no dentro de `admin/reporte-sede/page.tsx` porque una página de Next
// solo puede exportar la página, y la promesa que hay que defender —«no se
// silencia una alarma sin una respuesta real de que hoy descansan»— se prueba sin
// abrir un navegador.
//
// LOS FALSOS POSITIVOS SON EL PEOR ERROR, PERO AQUÍ HAY DOS LADOS. Acusar de falta
// a quien no le tocaba es el más caro; callar una falta real, el más silencioso.
// Por eso «apagada» pide TRES cosas a la vez, y cualquier duda deja la línea como
// estaba:
//   1 · la sede tiene al menos UNA respuesta real de descanso (`no_trabaja`), o es un
//       feriado en que nadie tiene turno (`feriado_sin_confirmar`: por su horario base
//       les tocaría, pero la base no lo exige sin un turno, y no se sabe si la sede
//       abre). Si todos están «sin_horario» (un tramo venció, sede nueva, equipo
//       vacío) es «no se sabe», y «no se sabe» no autoriza a callar nada;
//   2 · nadie ha iniciado jornada hoy — quien viene en su día libre y marca hizo
//       abrir la sede, y ahí la meta vuelve a medirse;
//   3 · el rango de la hoja incluye hoy: si termina antes, la consulta de jornadas
//       nunca trajo las de hoy, y «nadie marcó» sería un cero inventado.
// ============================================================================

import { metaDelDiaTexto } from "@/lib/admin/asistencia-hoy";
import { SEDE_SIN_TURNOS, type DiaDeLaSede } from "@/lib/admin/jornada-esperada";

export interface OpcionesCoberturaApagada {
  /**
   * La respuesta de la sede para hoy. `null` = no se pudo preguntar (falló la
   * consulta de turnos u horarios): es «no se sabe», igual que `sin_horario`.
   */
  dia: DiaDeLaSede | null;
  /** El estado de hoy de cada integrante del equipo: «sin_marcar» o el de su jornada. */
  estadosHoy: readonly string[];
  /** ¿El rango de fechas de la hoja incluye hoy? Ver el punto 3 de arriba. */
  rangoIncluyeHoy: boolean;
}

/**
 * ¿El rango elegido llega hasta hoy? Es la condición 3 de arriba, dicha una sola
 * vez: la hoja la usa para decidir si pregunta por los turnos de hoy y para
 * decidir si apaga la línea, y las dos tienen que coincidir. Son fechas ISO, que
 * se comparan bien como texto.
 */
export function hojaIncluyeHoy(desde: string, hasta: string, hoy: string): boolean {
  return desde <= hoy && hoy <= hasta;
}

/**
 * ¿Se apaga la línea de cobertura del recuadro «Hoy»? Solo con una respuesta real
 * de que hoy nadie trabaja —o de un feriado en que nadie tiene turno— Y sin que nadie
 * haya iniciado jornada.
 *
 * Un equipo vacío nunca la apaga: `every` sobre una lista vacía es verdadero, y
 * «nadie marcó» dicho de nadie no es una afirmación.
 */
export function coberturaDeHoyApagada({ dia, estadosHoy, rangoIncluyeHoy }: OpcionesCoberturaApagada): boolean {
  if (!rangoIncluyeHoy) return false;
  if (dia !== "no_trabaja" && dia !== "feriado_sin_confirmar") return false;
  return estadosHoy.length > 0 && estadosHoy.every((e) => e === "sin_marcar");
}

/**
 * Lo que dice la hoja en lugar de la línea de cobertura apagada. Corto y sin
 * instrucciones: es un papel que se firma. Un feriado sin turnos NO dice «a nadie le
 * tocaba»: por su horario les tocaría, y lo que no se sabe es si la sede abre.
 */
export function textoCoberturaApagada(dia: DiaDeLaSede | null): { titulo: string; detalle: string } {
  return dia === "feriado_sin_confirmar"
    ? { titulo: "Feriado", detalle: "Sin turnos armados: no se sabe si la sede abre hoy." }
    : { titulo: SEDE_SIN_TURNOS, detalle: "Hoy a nadie del equipo le tocaba trabajar." };
}

/**
 * «Meta de hoy: 4 operativas y 1 líder.», o null si hoy no hay meta. Para la línea
 * gris que acompaña al «Sin turnos» cuando la sede SÍ tiene una meta cargada: dice
 * qué meta es, sin pintarla como faltante.
 *
 * Toma la más alta de las dos de operativas (mañana o tarde), igual que el
 * Dashboard (`metaOpDelDia`): con la sede sin turnos no hay un «tramo actual» que
 * elegir, y la meta del día es la mayor. La concordancia es la de `metaDelDiaTexto`,
 * una sola para las dos pantallas.
 */
export function textoMetaDeHoy(metaMan: number, metaTar: number, metaLideres: number): string | null {
  const texto = metaDelDiaTexto({ metaOpDelDia: Math.max(metaMan, metaTar), metaEnc: metaLideres });
  return texto ? `Meta de hoy: ${texto}.` : null;
}
