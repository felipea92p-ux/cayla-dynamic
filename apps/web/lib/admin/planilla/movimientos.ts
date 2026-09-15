// Lo que se elige al registrar un bono o un descuento en Planilla. Salió de
// `admin/planilla/page.tsx` el 2026-09-15, cuando el formulario se mudó al
// panel de la persona.
//
// "vacaciones", "otros", "gratificacion", "cts" y "bonificacion_extraordinaria"
// NO son tipos nuevos en la base: son categorías sobre un movimiento que suma,
// igual que un bono. La aritmética de la planilla no cambia — para restar,
// siempre Descuento. El MONTO de gratificación/CTS/bonificación lo calcula
// `fn_grati_cts_periodo` para el periodo que contiene la fecha de pago legal.

export type ClaseMov = "bono" | "descuento" | "vacaciones" | "gratificacion" | "cts" | "bonificacion_extraordinaria" | "otros";

export const CLASE_A_TIPO: Record<ClaseMov, "bono" | "descuento"> = {
  bono: "bono", descuento: "descuento", vacaciones: "bono", gratificacion: "bono", cts: "bono",
  bonificacion_extraordinaria: "bono", otros: "bono",
};

export const CLASE_A_CATEGORIA: Record<ClaseMov, string | null> = {
  bono: null, descuento: null, vacaciones: "vacaciones", gratificacion: "gratificacion", cts: "cts",
  bonificacion_extraordinaria: "bonificacion_extraordinaria", otros: "otros",
};

// Nombres LEGALES, revertido el 2026-07-28 por decisión de Felipe. Antes decían
// «Bono Gratitud» y «Bono Comprometidos»: la gratificación y la CTS son
// derechos de ley, no liberalidades, y llamarlas bono ante SUNAFIL se lee como
// intento de ocultar un pago obligatorio.
export const CLASE_LABEL: Record<ClaseMov, string> = {
  bono: "Bono", descuento: "Descuento", vacaciones: "Vacaciones", gratificacion: "Gratificación", cts: "CTS",
  bonificacion_extraordinaria: "Bonificación 9% (Ley 30334)", otros: "Otros",
};

export const CLASE_PLACEHOLDER: Record<ClaseMov, string> = {
  bono: "ej. reconocimiento del mes",
  descuento: "ej. adelanto quincenal",
  vacaciones: "ej. Vacaciones 22–28 jul 2026",
  gratificacion: "el sistema lo calcula",
  cts: "el sistema lo calcula",
  bonificacion_extraordinaria: "el sistema lo calcula",
  otros: "ej. reintegro",
};

export interface MovForm {
  tipo: ClaseMov;
  concepto: string;
  monto: string;
  /** CAMBIO 0305 — De qué periodo YA PAGADO viene esta corrección. Vacío es lo
   *  normal: el movimiento es de este mes y no corrige nada. */
  origen: string;
}

export const MOV_FORM_VACIO: MovForm = { tipo: "bono", concepto: "", monto: "", origen: "" };
