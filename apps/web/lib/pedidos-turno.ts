// «Este día no me calza» — el pedido de una colaboradora sobre un día con turno (0587).
//
// QUÉ PROMETE
//   Las palabras y las reglas de un pedido, en un solo sitio, para las dos
//   pantallas que lo pintan: «Lo mío · Mis turnos» (ella pide y ve en qué
//   está) y «Disponibilidad del equipo» (su líder o DO responde), más la
//   Bandeja (lib/bandeja-mia.ts), que le avisa la respuesta.
//
// LAS 48 HORAS
//   Las cuenta la base (`fn_turno_pedido_con_do`, 0587) y se repiten acá solo
//   para pintar sin una ida más al servidor. `tests/pedidos-turno.test.ts`
//   compara las dos: si alguien cambia una, la prueba se pone en rojo.

import { diaMes } from "@/lib/disponibilidad";
import { sumarDias } from "@cayla-dynamic/shared";

export type MotivoPedido = "estudios" | "hijos" | "salud" | "otro_trabajo" | "otro";
export type PropuestaPedido = "tarde" | "manana" | "no_puede";
export type EstadoPedido = "abierto" | "resuelto" | "retirado";
export type ResolucionPedido = "acepta" | "se_mantiene" | "cambio_companera" | "otro";

export const MOTIVOS: readonly { valor: MotivoPedido; label: string }[] = [
  { valor: "estudios", label: "Estudios" },
  { valor: "hijos", label: "Mis hijos" },
  { valor: "salud", label: "Salud" },
  { valor: "otro_trabajo", label: "Otro trabajo" },
  { valor: "otro", label: "Otro motivo" },
];

export const PROPUESTAS: readonly { valor: PropuestaPedido; label: string; ella: string }[] = [
  { valor: "tarde", label: "Puedo en la tarde", ella: "Puede en la tarde" },
  { valor: "manana", label: "Puedo en la mañana", ella: "Puede en la mañana" },
  { valor: "no_puede", label: "Ese día no puedo", ella: "Ese día no puede" },
];

/** Lo que puede contestar su líder o DO. `cambio_companera` llega con la entrega 4. */
export const RESOLUCIONES: readonly { valor: Exclude<ResolucionPedido, "cambio_companera">; label: string; pideTexto: boolean }[] = [
  { valor: "acepta", label: "Le calza: lo cambio en Turnos", pideTexto: false },
  { valor: "se_mantiene", label: "El turno se mantiene", pideTexto: true },
  { valor: "otro", label: "Otra solución", pideTexto: true },
];

/** Igual que `fn_turno_pedido_con_do` (0587). */
export const HORAS_PARA_DO = 48;
/** Igual que el tope de `fn_turno_pedido_crear` (0587): de hoy a 21 días. */
export const DIAS_ADELANTE = 21;
export const MAX_COMENTARIO = 300;
/** Igual que `fn_turno_pedido_responder`: «se mantiene» u «otro» explican por qué. */
export const MIN_RESPUESTA = 5;

export interface PedidoTurno {
  id: string;
  persona_id: string;
  fecha: string;
  motivo: MotivoPedido;
  propuesta: PropuestaPedido;
  comentario: string | null;
  estado: EstadoPedido;
  creado_at: string;
  resuelto_por: string | null;
  resuelto_at: string | null;
  resolucion: ResolucionPedido | null;
  respuesta: string | null;
}

export const COLUMNAS_PEDIDO =
  "id, persona_id, fecha, motivo, propuesta, comentario, estado, creado_at, resuelto_por, resuelto_at, resolucion, respuesta";

const etiqueta = <T extends string>(lista: readonly { valor: T; label: string }[], v: T) =>
  lista.find((x) => x.valor === v)?.label ?? v;

export const textoMotivo = (m: MotivoPedido) => etiqueta(MOTIVOS, m);

export function textoPropuesta(p: PropuestaPedido, quien: "tu" | "ella" = "tu"): string {
  const x = PROPUESTAS.find((y) => y.valor === p);
  return x ? (quien === "tu" ? x.label : x.ella) : p;
}

export function textoResolucion(r: ResolucionPedido | null): string {
  if (r === "cambio_companera") return "Cambio con una compañera";
  return r ? etiqueta(RESOLUCIONES, r) : "";
}

/** ¿Ya pasó a DO? Abierto y con 48 h o más sin respuesta. */
export function pasoADo(p: Pick<PedidoTurno, "estado" | "creado_at">, ahora: number = Date.now()): boolean {
  return p.estado === "abierto" && ahora - Date.parse(p.creado_at) >= HORAS_PARA_DO * 3600_000;
}

/** Cuánto le falta para pasar a DO, en horas enteras (0 si ya pasó). */
export function horasParaDo(p: Pick<PedidoTurno, "creado_at">, ahora: number = Date.now()): number {
  const resta = HORAS_PARA_DO * 3600_000 - (ahora - Date.parse(p.creado_at));
  return resta <= 0 ? 0 : Math.ceil(resta / 3600_000);
}

/** ¿Se puede pedir este día? De hoy a DIAS_ADELANTE. Mismo criterio que la base. */
export function sePuedePedir(fecha: string, hoy: string): boolean {
  return fecha >= hoy && fecha <= sumarDias(hoy, DIAS_ADELANTE);
}

/** «El 12 nov: puedo en la tarde · por estudios». */
export function resumenPedido(p: Pick<PedidoTurno, "fecha" | "motivo" | "propuesta">, quien: "tu" | "ella" = "tu"): string {
  return `El ${diaMes(p.fecha)}: ${textoPropuesta(p.propuesta, quien).toLowerCase()} · ${textoMotivo(p.motivo).toLowerCase()}`;
}

/** Qué se le dice a ella cuando le respondieron. */
export function tituloRespuesta(p: Pick<PedidoTurno, "fecha" | "resolucion">): string {
  const dia = diaMes(p.fecha);
  switch (p.resolucion) {
    case "acepta": return `Tu pedido del ${dia}: te lo cambian`;
    case "se_mantiene": return `Tu pedido del ${dia}: el turno se mantiene`;
    case "cambio_companera": return `Tu pedido del ${dia}: lo cambias con una compañera`;
    default: return `Tu pedido del ${dia}: te respondieron`;
  }
}

/** ¿La respuesta escrita alcanza para esta resolución? */
export function respuestaValida(r: ResolucionPedido, texto: string): boolean {
  const pide = RESOLUCIONES.find((x) => x.valor === r)?.pideTexto ?? true;
  return !pide || texto.trim().length >= MIN_RESPUESTA;
}
