import {
  CalendarClock, CalendarDays, Car, FileSignature, Gavel, GraduationCap, History, IdCard, LayoutDashboard,
  MessageSquareText, ReceiptText, ScrollText, ShieldCheck, Target, TreePalm, UserRound,
} from "lucide-react";
import type { GrupoDetalle } from "./secciones-de-menu";

// ============================================================================
// Las secciones de «Lo mío» (/mio), en el orden y los grupos en que se leen.
// ============================================================================

/** Las dieciséis secciones de la pantalla. Ver el comentario de `tab` en mio/page.tsx. */
export type Tab =
  | "resumen" | "dias" | "turnos" | "dni" | "seguro" | "datos" | "ausencias" | "contrato" | "boletas" | "movilidad"
  | "educacion" | "firma" | "objetivos" | "reportes" | "disciplina" | "historial";

/**
 * Las dieciséis, agrupadas.
 *
 * LOS GRUPOS (2026-10-06). Hasta ese día eran una sola lista, en el orden en que
 * se fueron agregando: «Mi DNI» y «Tus datos» quedaban entre «Mis turnos» y
 * «Vacaciones», y quien buscaba algo de su pago tenía que leer las catorce. Se
 * eligieron con un prototipo, mirando las opciones lado a lado:
 *
 *   · «Asistencia» y «Pago» son las MISMAS palabras que el menú del panel
 *     (`admin/nav-items.ts`) usa para esas ideas. Quien tiene las dos
 *     superficies no aprende dos nombres para lo mismo.
 *   · «Historial» va en Seguimiento y no en Asistencia, aunque guarde las
 *     correcciones a sus marcajes: junto a «Mis días» se leería como algo de
 *     todos los días.
 *   · «Disciplina» (2026-10-06, entrega 4 de las amonestaciones) también va en
 *     Seguimiento, antes de «Historial», y se lleva los memos que vivían ahí:
 *     «Historial» no decía que ahí estaba la disciplina, y quien quería saber
 *     cómo iba no tenía por qué buscar en la última sección del menú. Se eligió
 *     con un prototipo (`docs/disciplina-mio-prototipo-2026-10-06.html`).
 *     El ícono es el de «Disciplina» en el menú del panel.
 *   · «Resumen» va solo y sin título, arriba: es donde se aterriza.
 *   · «Mi seguro» (2026-10-17, migración 0530) va en Documentos, junto a Contrato,
 *     Firma y Mi DNI: lo que se viene a buscar es el PDF de su póliza. Es de TODO el
 *     equipo: cada quien ve el suyo —FOLA con su póliza, EsSalud por planilla…— y la
 *     base decide qué ve cada persona. Nació acotada a los practicantes y se abrió
 *     cuando Felipe hizo general el módulo de Seguros.
 *
 * Los grupos se pueden cerrar, como en el panel, y cada dispositivo se acuerda
 * de cuáles cerró (ver `useGruposCerrados`, con su propia memoria).
 *
 * LOS ICONOS no se eligieron sueltos: cada uno es el que el menú del panel ya
 * usa para esa misma idea — Turnos, Datos personales, Ausencias, Contratos,
 * Documentación, Objetivos —, así quien ve las dos superficies reconoce la
 * sección sin leer la etiqueta. Las cuatro que el panel no tiene así: «Mis días»
 * y «Historial», que no existen allá como pantalla, «Movilidad» (0423), que allá
 * es una sub-vista de Documentación y no una pantalla propia con su propio
 * ícono, y «Mis datos»: el panel junta ficha y DNI en una sola pantalla con
 * `IdCard`, y ese ícono ya lo usa acá «Mi DNI» — se le da uno propio para no
 * repetirlo dentro de la misma pantalla.
 *
 * «Mis datos» se llamaba «Tus datos» hasta el 2026-10-06. Era la única del menú
 * en segunda persona entre «Mis días», «Mis turnos» y «Mi DNI»: el menú habla
 * con la voz de quien elige (la pantalla se llama «Lo mío»); los títulos de
 * dentro de cada sección sí le hablan a ella, y por eso siguen en «tu/tus».
 *
 * LOS ALIAS son lo que alguien escribe en ⌘K cuando no sabe cómo se llama la
 * sección. Se buscan sin tildes; no hace falta escribir dos versiones.
 */
export const GRUPOS_MIO: readonly GrupoDetalle<Tab>[] = [
  { secciones: [
    { valor: "resumen", label: "Resumen", Icon: LayoutDashboard, alias: ["inicio"] },
  ] },
  { label: "Asistencia", secciones: [
    { valor: "dias", label: "Mis días", Icon: CalendarDays, alias: ["asistencia", "marcaje", "tardanza", "falta", "horas"] },
    { valor: "turnos", label: "Mis turnos", Icon: CalendarClock, alias: ["horario", "feriado"] },
    { valor: "ausencias", label: "Vacaciones y permisos", Icon: TreePalm, alias: ["descanso médico", "licencia"] },
  ] },
  { label: "Pago", secciones: [
    // Las boletas OFICIALES del contador (0482), no la boleta en vivo de
    // `/mio/boleta`. Icono de recibo: es lo que es, y no repite ninguno del menú.
    { valor: "boletas", label: "Boletas", Icon: ReceiptText, alias: ["sueldo", "pago", "planilla"] },
    { valor: "movilidad", label: "Movilidad", Icon: Car, alias: ["ruta", "pasaje", "transporte", "bono de movilidad"] },
    // Mismo ícono que «Educación» en el menú del panel (nav-items.ts).
    { valor: "educacion", label: "Educación", Icon: GraduationCap, alias: ["bono de educación", "estudios", "colegio", "comprobante"] },
  ] },
  { label: "Documentos", secciones: [
    { valor: "contrato", label: "Contrato", Icon: ScrollText },
    { valor: "firma", label: "Firma", Icon: FileSignature, alias: ["firmar"] },
    { valor: "dni", label: "Mi DNI", Icon: IdCard, alias: ["documento de identidad"] },
    // Los alias son lo que alguien escribiría sin saber cómo se llama: «fola» y «essalud» son los
    // seguros de hoy, «pacífico» la aseguradora de FOLA, «clínica» a donde va a usarlo.
    { valor: "seguro", label: "Mi seguro", Icon: ShieldCheck, alias: ["póliza", "fola", "essalud", "seguro", "salud", "clínica", "pacífico"] },
    { valor: "datos", label: "Mis datos", Icon: UserRound, alias: ["cuenta", "banco", "celular", "dirección", "emergencia", "ficha"] },
  ] },
  { label: "Seguimiento", secciones: [
    { valor: "objetivos", label: "Objetivos", Icon: Target, alias: ["metas"] },
    // Lo que contó y en qué va (0483/0488).
    { valor: "reportes", label: "Reportes", Icon: MessageSquareText, alias: ["contar", "queja"] },
    // Sus memos, el mensaje cuando no hay nada, la constancia de lectura y cómo va
    // con sus tardanzas este mes. Los alias son lo que alguien escribiría sin saber
    // que existe: «memo» y «amonestación» llegaban a Historial antes de esta sección.
    { valor: "disciplina", label: "Disciplina", Icon: Gavel, alias: ["memo", "amonestación", "llamada de atención", "sanción", "tardanza", "cómo voy", "legajo"] },
    { valor: "historial", label: "Historial", Icon: History, alias: ["correcciones", "cambios"] },
  ] },
];

/** Las dieciséis, en el orden del menú. */
export const TABS: readonly Tab[] = GRUPOS_MIO.flatMap((g) => g.secciones.map((s) => s.valor));

/** Si un texto que llegó de fuera (un `?tab=` de un enlace) es una sección que existe. */
export function esTab(t: string): t is Tab {
  return (TABS as readonly string[]).includes(t);
}
