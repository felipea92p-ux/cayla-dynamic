// ============================================================================
// El color de un día: el cuadrito de Asistencia (Horas) y el de «Lo mío», en un solo lugar
// ============================================================================
//
// QUÉ PROMETE
//   colorDelDia(estado, minutosTarde): las clases con que se pinta el cuadrito de un día, según su `EstadoDia`.
//   colorTardanza(minutos): la tardanza en tres intensidades, porque siete minutos y dos horas no son la misma noticia.
//
// QUÉ ASUME
//   Que el cuadrito se pinta sobre `bg-papel`, como en Horas. Los contrastes de abajo se midieron contra ese fondo, con los hex de
//   globals.css y la fórmula de WCAG 2.x, y el piso es el de un elemento que no es texto: 3:1 (WCAG 1.4.11).
//   Lo mío lo pinta sobre el fondo de la página (crema), un punto más oscuro en claro. Medido el 2026-11-09: en claro, ámbar/65 da 2.98:1
//   y taupe/70 2.90:1, en el límite (con la copia vieja eran 2.04 y 1.40); en oscuro todo pasa, de 3.19 a 4.73:1.
//
// DECIDÍ: una sola escala para la persona y para su líder. Que las dos vean el mismo día del mismo color es lo que les deja hablar de él
//   sin traducirse una a la otra.
// DESCARTÉ: dejar una copia en cada pantalla. Así estaba hasta el 2026-11-09, y Lo mío —cuyo comentario prometía «los mismos colores que
//   el panel»— se había quedado con la escala anterior a dos correcciones de Horas: la tardanza grave con un filtro que en oscuro se lee
//   al revés, y tres tonos por debajo de 3:1.
// SE ROMPE SI: alguien pinta la intensidad con un filtro (`brightness-…`) o con la claridad del token: en oscuro los tokens se aclaran, así
//   que «más oscuro» se acerca al fondo en vez de saltar (lo vigila tests/color-del-dia.test.ts).
// ============================================================================

import type { EstadoDia } from "./jornada-esperada";

// Una tardanza de este tamaño ya no es «llegó justo»: cambia el color del cuadro. No es un umbral legal ni sanciona nada — es cuándo se ve
// distinto.
export const TARDANZA_SERIA_MIN = 15;
export const TARDANZA_GRAVE_MIN = 60;

/** Las muestras de una leyenda salen de la misma escala: una leyenda escrita a mano es la tercera copia. */
export const MUESTRA = {
  tardanza: [colorTardanza(0), colorTardanza(TARDANZA_SERIA_MIN), colorTardanza(TARDANZA_GRAVE_MIN)],
  dia: (estado: EstadoDia) => colorDelDia(estado, 0),
};

export function colorTardanza(minutos: number): string {
  // La grave lleva un anillo, no un oscurecido. Era "bg-ambar brightness-75": un filtro que siempre oscurece funciona sobre --color-ambar en
  // claro (ya oscuro) y se INVIERTE en oscuro (un dorado claro): ahí "más oscuro" se acerca al fondo y la de veinte minutos brillaba más
  // que la de dos horas. El anillo no depende de qué tan claro sea el token en cada tema, así que apunta igual en los dos.
  if (minutos >= TARDANZA_GRAVE_MIN) return "bg-ambar ring-2 ring-inset ring-rojo-profundo";
  if (minutos >= TARDANZA_SERIA_MIN) return "bg-ambar";
  // Era /45: 2.09:1 en claro y 2.34:1 en oscuro. /65 llega a ~3.0:1 en los dos temas sin acercarse a "tardanza seria".
  return "bg-ambar/65";
}

export function colorDelDia(estado: EstadoDia, minutosTarde: number): string {
  switch (estado) {
    case "falta": return "bg-rojo";
    case "revisar": return "border border-dashed border-taupe bg-papel";
    case "tarde": return colorTardanza(minutosTarde);
    // Era /20: 1.34:1 en claro, 1.29:1 en oscuro. /75 llega a ~3:1 en oscuro (el más exigente de los dos) sin cambiar el resto de la escala.
    case "justificada": return "bg-rojo/75";
    case "ok": return "bg-verde";
    case "extra": return "bg-verde/45 ring-1 ring-inset ring-verde";
    // Era /25: 1.42:1 en claro, 1.51:1 en oscuro. /70 llega a ~3:1 en claro (el más exigente) — auditoría UX/UI del 2026-09-14.
    case "sin_marca": return "bg-taupe/70";
    case "descanso": return "bg-sand";
    case "sin_horario": return "bg-sand/40";
    case "futuro": return "border border-sand";
  }
}
