// «Cambiar con una compañera» — el intercambio del turno de un día entre dos compañeras (0592).
//
// QUÉ PROMETE
//   Las palabras y los estados de un cambio en un solo sitio, para «Lo mío ·
//   Mis turnos» (ella propone, la compañera contesta), «Disponibilidad del
//   equipo» (la líder aprueba) y la Bandeja. Las reglas de verdad —mismo día,
//   misma sede, mismo largo, la foto de los dos turnos— viven en la base.

import { diaMes } from "@/lib/disponibilidad";

export type EstadoCambio = "propuesto" | "aceptado" | "rechazado" | "aprobado" | "no_aprobado" | "retirado";

/** Una fila de `fn_turno_cambios_mios()`: vista desde quien pregunta. */
export interface MiCambio {
  id: string;
  fecha: string;
  soy: "solicitante" | "companera";
  otra_nombre: string;
  mi_entrada: string;
  mi_salida: string;
  otra_entrada: string;
  otra_salida: string;
  estado: EstadoCambio;
  comentario: string | null;
  respuesta_companera: string | null;
  respuesta: string | null;
  lo_propuso_su_lider: boolean;
  creado_at: string;
  contestado_at: string | null;
  resuelto_at: string | null;
}

/** Una fila de `turno_cambios` para el panel. */
export interface CambioEquipo {
  id: string;
  fecha: string;
  solicitante_id: string;
  companera_id: string;
  propuesto_por: string;
  pedido_id: string | null;
  sol_entrada: string;
  sol_salida: string;
  comp_entrada: string;
  comp_salida: string;
  comentario: string | null;
  estado: EstadoCambio;
  creado_at: string;
  contestado_at: string | null;
  respuesta_companera: string | null;
}

export const COLUMNAS_CAMBIO =
  "id, fecha, solicitante_id, companera_id, propuesto_por, pedido_id, sol_entrada, sol_salida, comp_entrada, comp_salida, comentario, estado, creado_at, contestado_at, respuesta_companera";

export const hhmm = (t: string) => t.slice(0, 5);
export const tramo = (e: string, s: string) => `${hhmm(e)}–${hhmm(s)}`;

/** ¿Sigue vivo? Lo demás ya terminó. */
export const estaVivo = (e: EstadoCambio) => e === "propuesto" || e === "aceptado";

/** «Tu turno del 12 nov: 08:30–14:30 por el de Ana (14:00–20:00)». */
export function resumenCambio(c: Pick<MiCambio, "fecha" | "mi_entrada" | "mi_salida" | "otra_entrada" | "otra_salida" | "otra_nombre">): string {
  return `${diaMes(c.fecha)}: tu ${tramo(c.mi_entrada, c.mi_salida)} por el ${tramo(c.otra_entrada, c.otra_salida)} de ${c.otra_nombre}`;
}

/** En qué está, dicho a ella. */
export function estadoParaElla(c: Pick<MiCambio, "estado" | "soy" | "lo_propuso_su_lider">): string {
  switch (c.estado) {
    case "propuesto":
      return c.soy === "companera" ? "Te lo piden: ¿aceptas?" : "Esperando a tu compañera";
    case "aceptado":
      return "Tu compañera aceptó. Falta que lo apruebe tu líder de equipo";
    case "aprobado":
      return "Aprobado: ya está en tu turno";
    case "rechazado":
      return c.soy === "companera" ? "No lo aceptaste" : "Tu compañera no pudo";
    case "no_aprobado":
      return "Tu líder de equipo no lo aprobó";
    case "retirado":
      return "Retirado";
  }
}

/** El título de la Bandeja cuando ya terminó. */
export function tituloResultado(c: Pick<MiCambio, "fecha" | "estado">): string {
  const dia = diaMes(c.fecha);
  switch (c.estado) {
    case "aprobado": return `Cambio de turno del ${dia}: aprobado`;
    case "rechazado": return `Cambio de turno del ${dia}: tu compañera no pudo`;
    case "no_aprobado": return `Cambio de turno del ${dia}: no se aprobó`;
    default: return `Cambio de turno del ${dia}`;
  }
}
