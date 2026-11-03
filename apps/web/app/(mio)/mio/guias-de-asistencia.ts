// ============================================================================
// guias-de-asistencia.ts — las guías de «Mis días», «Mis turnos» y «Vacaciones
// y permisos» (2026-10-19)
// ============================================================================
// Los textos dicen lo que cada pantalla HACE, no lo que haría otra. Tres cosas
// que se comprobaron contra la pantalla antes de escribirlas, porque el borrador
// de la maqueta decía otra:
//   · «Vacaciones y permisos» solo deja PEDIR vacaciones. Un permiso o un
//     descanso médico no se piden aquí: los registra quien corresponde, y esta
//     pantalla muestra lo que consta y avisa si falta el documento.
//   · Las vacaciones las aprueba Desarrollo Organizacional, no el líder de
//     equipo; la pantalla lo dice así, y la guía también.
//   · «Mis días» no dice si algo es sanción: muestra lo que pasó cada día y deja
//     pedir que se revise uno.
//
// Las anclas `data-tour` están puestas a mano en `page.tsx`, en estas tres
// secciones. El PRIMER paso de cada guía es lo único que existe siempre: los
// demás pueden no estar (sin datos, o si algo no se pudo traer) y se saltan solos.
// ============================================================================

import type { PasoRecorrido } from "@/lib/use-recorrido-guiado";

export const PASOS_GUIA_DIAS: readonly PasoRecorrido[] = [
  { selector: '[data-tour="mio-dias-filtro"]', titulo: "El tramo que miras",
    texto: "Abre en tus últimos 30 días. «Periodo de pago» te lleva al tramo con el que se te paga, para que lo cuadres con tu boleta." },
  { selector: '[data-tour="mio-dias-cifras"]', titulo: "Cada número, con su «de cuánto»",
    texto: "Días trabajados, horas, promedio y tardanzas, siempre frente a lo que te tocaba. Un cero en tardanzas puede ser puntualidad o que no había horario que comparar: el pie lo dice." },
  { selector: '[data-tour="mio-dias-mes"]', titulo: "Tu mes, un cuadrito por día",
    texto: "Toca un día para ver qué te tocaba y a qué hora entraste y saliste. Si algo no cuadra, ahí mismo puedes pedir que se revise ese día." },
];

export const PASOS_GUIA_TURNOS: readonly PasoRecorrido[] = [
  { selector: '[data-tour="mio-turnos-seccion"]', titulo: "Tu semana",
    texto: "Lo que te toca de lunes a domingo. Puedes mirar la semana anterior, esta y la próxima. Lo que de verdad marcaste está en «Mis días»." },
  { selector: '[data-tour="mio-turnos-total"]', titulo: "Las horas de la semana",
    texto: "El total, comparado con tu horario de siempre. Si una semana tiene más o menos horas, aquí te lo dice." },
  { selector: '[data-tour="mio-turnos-semana"]', titulo: "Cada día",
    texto: "Entrada, salida, horas y refrigerio. Si trabajas en piso o en almacén, también. «Cambia de tu horario» marca los días que tu líder de equipo armó distinto." },
  { selector: '[data-tour="mio-turnos-cambios"]', titulo: "Cambios a tu horario",
    texto: "Lo que cambió en tu horario, tus turnos, tu puesto, tu jornada o tu disponibilidad en los últimos tres meses." },
  { selector: '[data-tour="mio-turnos-feriados"]', titulo: "Los próximos feriados",
    texto: "Para que los tengas presentes al planear tus días." },
];

export const PASOS_GUIA_DISPONIBILIDAD: readonly PasoRecorrido[] = [
  { selector: '[data-tour="mio-disponibilidad-seccion"]', titulo: "Mi disponibilidad",
    texto: "Dices qué días u horas no puedes trabajar. Va a tu líder de equipo; hasta que la aprueba, tus turnos siguen igual." },
  { selector: '[data-tour="mio-disponibilidad-editor"]', titulo: "Cómo se marca",
    texto: "Cada día lo marcas con un toque: puedo, prefiero no, no puedo o por horas. «No puedo» es firme; «prefiero no» se intenta respetar, pero si falta gente te puede tocar. Los atajos llenan la semana de un toque. Abajo ves en palabras lo que elegiste." },
];

export const PASOS_GUIA_AUSENCIAS: readonly PasoRecorrido[] = [
  { selector: '[data-tour="mio-ausencias-pedir"]', titulo: "Pedir vacaciones",
    texto: "Si te corresponden, eliges el rango y avisas. Las aprueba Desarrollo Organizacional, no tu líder de equipo, y abajo ves cómo va cada pedido." },
  { selector: '[data-tour="mio-ausencias-lista"]', titulo: "Lo que consta de ti",
    texto: "Tus permisos, descansos y vacaciones. «Falta el documento» te avisa a tiempo: sin él, ese permiso no cuenta igual. Los permisos y descansos los registra quien corresponde; si presentaste algo que no aparece, avísale a tu líder de equipo." },
];
