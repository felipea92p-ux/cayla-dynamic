// CONTRATOS — el nombre con el que se guarda el PDF del contrato que está ABIERTO en el visor.
//
// POR QUÉ VIVE APARTE (2026-11-17). Hasta hoy el título salía de la persona elegida en el GENERADOR
// (`personaId`), no del documento abierto. Abrir «Ver / imprimir» desde el archivo no toca el generador,
// así que todo contrato que se descargaba de ahí se guardaba con el nombre de quien había quedado elegida
// allá: Felipe bajó el de Pepe y el de Luis, y los dos salieron como «Carla … — Contrato de trabajo».
// Es justo el error que `useTituloDocumento` existe para evitar —mandarle a alguien el papel de otra
// persona—, solo que con un nombre equivocado en vez de uno genérico, que es peor: se cree.
//
// La regla ahora: el título se calcula UNA vez, cuando se abre el documento, con los datos de ESE
// contrato, y viaja pegado a su texto. No hay un segundo estado que se pueda quedar atrás.
//
// La fecha de inicio va en el nombre porque una misma persona tiene varios: su ingreso, cada renovación,
// cada adendum. Sin ella, la tercera renovación de alguien se guarda encima de la segunda.

import { fechaLargaLima } from "@cayla-dynamic/shared";

/**
 * Cómo se llama el papel según su tipo. Un convenio de prácticas NO es un contrato de trabajo
 * (Ley 28518: las modalidades formativas no generan relación laboral) y un adendum modifica uno que ya
 * existe: nombrarlos «Contrato de trabajo» sería decir en el archivo algo que el papel no dice.
 * Un tipo que no está acá (uno nuevo de la base) cae en «Contrato de trabajo»: es lo que decía antes.
 */
const DOCUMENTO_POR_TIPO: Record<string, string> = {
  nuevo: "Contrato de trabajo",
  renovacion: "Renovación de contrato",
  indefinido: "Contrato de trabajo indefinido",
  adendum: "Adendum al contrato",
  convenio_practicas: "Convenio de prácticas",
};

/**
 * `Luis Pérez Rojas — Renovación de contrato — 01 de setiembre de 2026`.
 *
 * `persona` llega ya armada («Nombres Apellidos»): así la entrega `fn_contratos_listar` y así la arma
 * el generador. Sin nombre devuelve `null`, que `useTituloDocumento` entiende como «no toques el
 * título»: mejor el nombre del sitio que el de otra persona.
 */
export function nombreDelPdfDeContrato(c: {
  persona: string | null | undefined;
  tipo: string;
  fechaInicio: string | null | undefined;
}): string | null {
  const nombre = c.persona?.trim();
  if (!nombre) return null;
  const documento = DOCUMENTO_POR_TIPO[c.tipo] ?? "Contrato de trabajo";
  const desde = c.fechaInicio && /^\d{4}-\d{2}-\d{2}$/.test(c.fechaInicio) ? fechaLargaLima(c.fechaInicio) : null;
  return [nombre, documento, desde].filter(Boolean).join(" — ");
}
