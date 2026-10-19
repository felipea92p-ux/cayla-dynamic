// ============================================================================
// guias-de-seguimiento.ts — las guías de «Objetivos», «Reportes» e «Historial»
// (2026-10-19)
// ============================================================================
// Escritas contra lo que cada pantalla HACE, con las palabras que la propia
// pantalla ya usa. Lo que se comprobó:
//   · «Objetivos» es de SOLO LECTURA: los acuerda y los marca tu líder de
//     equipo. Y desde la migración 0171 los objetivos NO pagan: ninguna guía
//     de aquí habla de dinero ni de premios.
//   · «Reportes» promete una cosa muy concreta —«la persona reportada nunca
//     sabrá que fuiste tú»— y la guía repite ESA frase, no otra: una guía que
//     prometiera más que la pantalla sería una promesa nueva sobre un tema
//     delicado. Lo de tipo sexual y el riesgo ahora van por un camino aparte, y
//     eso también lo dice la pantalla.
//   · «Historial» no es lo que ya pasó con las faltas: son los CAMBIOS que
//     alguien aplicó a tu registro (un marcaje, tu horario…), cada uno con su
//     motivo, y tus últimos periodos sin montos.
//
// Las anclas `data-tour` están puestas a mano: la de «Objetivos» y «Tus últimos
// periodos» en `page.tsx`, la de «Reportes» en `reportes/reportes-mios.tsx` y la
// de «Cambios a tu registro» en `cambios-mios.tsx`. El PRIMER paso de cada guía
// es lo único que existe siempre.
// ============================================================================

import type { PasoRecorrido } from "@/lib/use-recorrido-guiado";

export const PASOS_GUIA_OBJETIVOS: readonly PasoRecorrido[] = [
  { selector: '[data-tour="mio-objetivos-seccion"]', titulo: "Tus objetivos del mes",
    texto: "Los acuerda contigo tu líder de equipo. Aquí solo ves el avance: no se marcan desde esta pantalla." },
  { selector: '[data-tour="mio-objetivos-lista"]', titulo: "Cuáles están cumplidos",
    texto: "Cada objetivo con su marca, y arriba cuántos van. Los marca tu líder de equipo cuando los conversan; si crees que alguno ya está, díselo." },
];

export const PASOS_GUIA_REPORTES: readonly PasoRecorrido[] = [
  { selector: '[data-tour="mio-reportes-seccion"]', titulo: "Contar algo",
    texto: "Puedes contar algo que pasó con el equipo, con la empresa o con una clienta, proponer una mejora o hacerle una consulta a tu líder. Lo lee solo quien lo gestiona, y la persona reportada nunca sabrá que fuiste tú." },
  { selector: '[data-tour="mio-reportes-nuevo"]', titulo: "Un reporte nuevo",
    texto: "El formulario te guía por pasos. Si es algo de tipo sexual, o hay un riesgo para alguien ahora, lo marcas arriba: va por un camino aparte y con plazos propios." },
  { selector: '[data-tour="mio-reportes-lista"]', titulo: "En qué va cada uno",
    texto: "Cada reporte con su código y su estado. Ves si te respondieron y, si aún no, hasta cuándo te responden a más tardar." },
];

export const PASOS_GUIA_HISTORIAL: readonly PasoRecorrido[] = [
  { selector: '[data-tour="mio-historial-cambios"]', titulo: "Cambios a tu registro",
    texto: "Cuando alguien corrige un marcaje tuyo, tu horario u otro dato de tu registro, queda anotado aquí con el motivo. Ábrelo para ver cada cambio." },
  { selector: '[data-tour="mio-historial-periodos"]', titulo: "Tus últimos periodos",
    texto: "Días trabajados, horas y tardanzas de cada periodo, sin montos: para el pago está tu boleta." },
];
