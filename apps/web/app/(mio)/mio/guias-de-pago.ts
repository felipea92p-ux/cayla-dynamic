// ============================================================================
// guias-de-pago.ts — las guías de «Boletas», «Movilidad» y «Educación»
// (2026-10-19)
// ============================================================================
// Escritas contra lo que cada pantalla HACE, y por eso difieren del borrador de
// la maqueta, que suponía otra cosa:
//   · «Boletas» muestra las boletas OFICIALES que entrega el contador, una por
//     periodo pagado, y deja firmarlas. El cálculo del periodo que corre NO está
//     aquí: está en Resumen, «Cómo va tu pago».
//   · «Movilidad» no es un pacto que se acepte: es la DECLARACIÓN DE RUTA y gasto
//     de transporte. El monto nunca lo escribe la persona: lo calcula el sistema
//     con la tarifa de su sede.
//   · «Educación» no recibe comprobantes de pago: lleva el estado de la
//     CONSTANCIA de estudios de cada apoyo y manda a la pantalla donde se sube,
//     se renueva o se solicita.
//
// Las anclas `data-tour` están puestas a mano: la de «Boletas» en
// `boletas/boletas-mias.tsx`, la de «Movilidad» en `page.tsx` y la de
// «Educación» en `educacion/resumen.tsx`. El PRIMER paso de cada guía es lo único
// que existe siempre; los demás dependen de que haya datos y se saltan solos.
// ============================================================================

import type { PasoRecorrido } from "@/lib/use-recorrido-guiado";

export const PASOS_GUIA_BOLETAS: readonly PasoRecorrido[] = [
  { selector: '[data-tour="mio-boletas-seccion"]', titulo: "Tus boletas oficiales",
    texto: "Son las que entrega el contador, una por periodo pagado. El cálculo del periodo que corre no está aquí: está en Resumen, en «Cómo va tu pago»." },
  { selector: '[data-tour="mio-boletas-por-firmar"]', titulo: "Cuando una espera tu firma",
    texto: "El aviso sale arriba de la lista. Ábrela y fírmala con la firma que ya tienes guardada; firmar deja constancia de que la recibiste." },
  { selector: '[data-tour="mio-boletas-lista"]', titulo: "Una tarjeta por periodo",
    texto: "«Ver» abre la boleta y «Descargar PDF» la guarda; firmada, el PDF lleva tu firma. Si algo no cuadra, avisa a Desarrollo Organizacional: un dato mal registrado se corrige y se anota con su motivo." },
];

export const PASOS_GUIA_MOVILIDAD: readonly PasoRecorrido[] = [
  { selector: '[data-tour="mio-movilidad-seccion"]', titulo: "Tu declaración de ruta",
    texto: "Dice si ya la firmaste, si toca renovarla o si te falta. Lo que se te paga lo calcula el sistema con la tarifa de tu sede: tú no escribes ningún monto." },
  { selector: '[data-tour="mio-movilidad-ir"]', titulo: "Leerla, completarla y firmarla",
    texto: "Ahí está la hoja: la lees, completas lo que falta y la firmas en pantalla, con el mismo valor que el escaneo. Ya firmada y al día queda fija; si algo cambió de verdad, pides una revisión con un motivo." },
];

export const PASOS_GUIA_EDUCACION: readonly PasoRecorrido[] = [
  { selector: '[data-tour="mio-educacion-seccion"]', titulo: "Tu apoyo educativo",
    texto: "Una línea por estudio, con el estado de su constancia y, si hay plazo, cuándo vence. Sin estudio activo te dice cuál terminó, o que aún no tienes ninguno." },
  { selector: '[data-tour="mio-educacion-ir"]', titulo: "La pantalla de tus constancias",
    texto: "Desde aquí vas a donde subes tu constancia de estudios, renuevas el apoyo o lo solicitas, según tu caso." },
];
