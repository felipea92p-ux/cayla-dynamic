import { fechaLima, hoyLima } from "@cayla-dynamic/shared";
import { diasEntre, diaYMes } from "../bandeja-mia";

/**
 * EN QUÉ GRUPO DE URGENCIA CAE CADA PENDIENTE DE LA BANDEJA DEL PANEL.
 *
 * QUÉ PROMETE. Traduce lo que ya devuelven las RPC de la Bandeja a una sola
 * escala —Vencido / Hoy / Próximos / Sin plazo— y a un texto de plazo en
 * lenguaje de persona («Vence hoy», «Venció hace 6 días»). No decide QUÉ es un
 * pendiente: eso lo siguen decidiendo las mismas RPC y filtros de siempre
 * (ver bandeja/page.tsx y lib/admin/bandeja-equipo.ts). Solo lo ordena.
 *
 * QUÉ ASUME. Que las fechas que llegan ya son de Lima: `dias_para_vencer` lo
 * calcula la base con `fn_hoy_lima()`, y las fechas de calendario
 * (`fecha_inicio`, `vence_el`) no tienen hora. Los instantes (`pedida_at`) se
 * pasan a fecha de Lima con `fechaLima` antes de restar.
 *
 * POR QUÉ HAY TRES CLASES DE URGENCIA Y NO UNA (decisión de Felipe, 2026-09-15)
 *
 *   · Con fecha límite — Educación y el récord de vacaciones: el plazo manda.
 *   · Esperando tu respuesta — revisiones y cambios de perfil: no tienen
 *     vencimiento, así que se miden por lo que llevan esperando, y pasan a
 *     «Vencido» desde el día 8, el mismo umbral que la Bandeja ya usaba para su
 *     alarma de antigüedad.
 *   · Con riesgo ya corriendo — alguien que trabajó sin horario: si le cae un
 *     descanso médico en ese hueco se paga en cero, así que va a «Vencido».
 *
 * Y una excepción que es la razón de ser de este archivo: una SOLICITUD de
 * vacaciones no se mide por lo que lleva esperando sino por su FECHA DE INICIO.
 * Una pedida ayer que empieza hoy aprieta más que una pedida hace dos semanas
 * que empieza en noviembre.
 */

export type GrupoUrgencia = "vencido" | "hoy" | "proximo" | "sin_plazo";

export const GRUPOS_URGENCIA: readonly { clave: GrupoUrgencia; etiqueta: string; descripcion: string }[] = [
  { clave: "vencido", etiqueta: "Vencido", descripcion: "ya pasó su plazo, o el riesgo ya está corriendo" },
  { clave: "hoy", etiqueta: "Hoy", descripcion: "vence o empieza hoy" },
  { clave: "proximo", etiqueta: "Próximos", descripcion: "tiene fecha más adelante" },
  { clave: "sin_plazo", etiqueta: "Sin plazo", descripcion: "no tiene fecha límite" },
];

const RANGO: Record<GrupoUrgencia, number> = { vencido: 0, hoy: 1, proximo: 2, sin_plazo: 3 };

export interface Urgencia {
  grupo: GrupoUrgencia;
  /** Lo que se lee en la insignia: «Vence hoy», «Esperando 9 días». */
  plazo: string;
  /** Una línea chica debajo, o null: «el 9 de setiembre». */
  nota: string | null;
  /** Dentro del grupo, menor va primero: lo más vencido o lo que más espera. */
  orden: number;
}

/** Desde qué día de espera una respuesta pendiente cuenta como atrasada. */
export const DIAS_ESPERA_ATRASADA = 8;

/** «Vence hoy», «Vence mañana», «Vence en 12 días», «Venció hace 3 días». */
export function enDias(dias: number, verbo: { futuro: string; pasado: string }): string {
  if (dias < 0) {
    const n = -dias;
    return `${verbo.pasado} hace ${n} día${n === 1 ? "" : "s"}`;
  }
  if (dias === 0) return `${verbo.futuro} hoy`;
  if (dias === 1) return `${verbo.futuro} mañana`;
  return `${verbo.futuro} en ${dias} días`;
}

const VENCE = { futuro: "Vence", pasado: "Venció" };
const EMPIEZAN = { futuro: "Empiezan", pasado: "Empezaron" };

/**
 * Un estudio que la Bandeja tiene que tener presente, tal como lo contesta
 * `fn_educacion_situacion` (0450). Quién entra lo decide `esEducacionParaSaber`
 * (lib/admin/bandeja-equipo.ts); acá solo se ordena.
 */
export interface EstudioEducacion {
  estado_constancia: string;
  vigencia: string;
  plazo: string | null;
  fecha_pago_constancia: string | null;
  pago_proximo: boolean;
  dias_para_pago: number | null;
  proxima_fecha_pago: string | null;
}

/**
 * ⇩ CAMBIO 0450 ⇩ El plazo de un estudio se mide contra su CONSTANCIA, no contra
 * el fin de la asignación. Hasta la 0450 «vence en 0 días» era la vigencia del
 * beneficio —casi siempre una renovación normal— pintada con la misma urgencia
 * que un papel que falta. Ahora:
 *   · constancia vencida      → Vencido, desde el día de su plazo;
 *   · pago a la institución   → Hoy / Próximos, por la fecha del pago (el aviso
 *                               que DO pidió para tener el apoyo listo);
 *   · estudio sin calendario  → Sin plazo: no hay fecha contra la que medir.
 */
export function urgenciaEducacion(f: EstudioEducacion, hoy: string = hoyLima()): Urgencia {
  if (f.estado_constancia === "vencida") {
    const d = f.plazo ? diasEntre(hoy, f.plazo) : -1;
    return {
      grupo: "vencido",
      plazo: f.plazo ? enDias(d, VENCE) : "Constancia vencida",
      nota: f.fecha_pago_constancia ? `pago del ${diaYMes(f.fecha_pago_constancia)}` : null,
      orden: d,
    };
  }
  if (f.pago_proximo && f.dias_para_pago !== null) {
    const d = f.dias_para_pago;
    return {
      grupo: d === 0 ? "hoy" : "proximo",
      plazo: enDias(d, { futuro: "Paga", pasado: "Pagó" }),
      nota: f.proxima_fecha_pago ? `a su institución, el ${diaYMes(f.proxima_fecha_pago)}` : null,
      orden: d,
    };
  }
  return { grupo: "sin_plazo", plazo: "Sin calendario", nota: "falta saber cuándo paga", orden: 0 };
}

/** Qué se le dice a DO de ese estudio, y a qué lo lleva el botón. */
export function documentoEducacion(f: EstudioEducacion): { titulo: string; accion: string } {
  if (f.estado_constancia === "vencida") return { titulo: "Constancia de estudios vencida", accion: "Pedir constancia" };
  if (f.pago_proximo) return { titulo: "Pago de estudios en camino", accion: "Ver estudio" };
  return { titulo: "Estudio sin calendario de pagos", accion: "Fijar calendario" };
}

/** Una solicitud de vacaciones, por su fecha de inicio (ver el encabezado). */
export function urgenciaInicio(fechaInicio: string, hoy: string = hoyLima()): Urgencia {
  const d = diasEntre(hoy, fechaInicio);
  if (d < 0) return { grupo: "vencido", plazo: enDias(d, EMPIEZAN), nota: "y siguen sin aprobar", orden: d };
  if (d === 0) return { grupo: "hoy", plazo: "Empiezan hoy", nota: null, orden: 0 };
  return { grupo: "proximo", plazo: enDias(d, EMPIEZAN), nota: `el ${diaYMes(fechaInicio)}`, orden: d };
}

/** Lo que espera una respuesta, por cuánto lleva esperando. */
export function urgenciaEspera(pedidaAt: string, hoy: string = hoyLima()): Urgencia {
  const dias = Math.max(0, diasEntre(fechaLima(pedidaAt), hoy));
  const plazo = dias === 0 ? "Pedido hoy" : `Esperando ${dias} día${dias === 1 ? "" : "s"}`;
  if (dias >= DIAS_ESPERA_ATRASADA) {
    return { grupo: "vencido", plazo, nota: "más de una semana sin respuesta", orden: -dias };
  }
  return { grupo: "sin_plazo", plazo, nota: null, orden: -dias };
}

export interface RecordVacaciones {
  records_vencidos: number;
  dias_para_vencer: number;
  vence_el: string;
}

/** Un récord de vacaciones sin gozar (`fn_vacaciones_por_vencer`, 0297). */
export function urgenciaRecordVacaciones(v: RecordVacaciones): Urgencia {
  if (v.records_vencidos > 0 || v.dias_para_vencer < 0) {
    const n = v.records_vencidos;
    return {
      grupo: "vencido",
      plazo: n > 1 ? `${n} récords vencidos` : "Récord vencido",
      nota: "ya corre la indemnización",
      orden: Math.min(v.dias_para_vencer, 0) - n,
    };
  }
  if (v.dias_para_vencer === 0) return { grupo: "hoy", plazo: "Vence hoy", nota: null, orden: 0 };
  return { grupo: "proximo", plazo: enDias(v.dias_para_vencer, VENCE), nota: `el ${diaYMes(v.vence_el)}`, orden: v.dias_para_vencer };
}

export interface HuecoDeHorario {
  dias: number;
  primer_dia: string;
  nunca_tuvo_horario: boolean;
}

/** Días trabajados sin horario (`fn_personas_sin_horario_vigente`, 0385). El riesgo ya ocurrió. */
export function urgenciaSinHorario(h: HuecoDeHorario): Urgencia {
  return {
    grupo: "vencido",
    plazo: "Riesgo en curso",
    nota: h.nunca_tuvo_horario ? "nunca tuvo horario" : `desde el ${diaYMes(h.primer_dia)}`,
    orden: -h.dias,
  };
}

export interface LiquidacionVencida {
  dias_restantes: number;
  vence_el: string;
  total: number;
}

/**
 * Una liquidación pasada de plazo (`fn_liquidaciones_pendientes`, 0454). Igual
 * que `urgenciaSinHorario`: el riesgo ya ocurrió, así que no hay «hoy» ni
 * «próximo» posible — solo vencido. Decidido con Felipe el 2026-09-15: de las
 * cuatro señales que Liquidaciones podía mandar a la Bandeja (nueva pendiente,
 * próxima a vencer, vencida, cálculo cambió), solo esta cruza — las otras tres
 * duplican lo que la propia pantalla ya muestra sin agregar nada accionable.
 */
export function urgenciaLiquidacionVencida(l: LiquidacionVencida): Urgencia {
  const dias = -l.dias_restantes;
  return {
    grupo: "vencido",
    plazo: `Venció hace ${dias} día${dias === 1 ? "" : "s"}`,
    nota: `el ${diaYMes(l.vence_el)}`,
    orden: l.dias_restantes,
  };
}

/**
 * Alguien que ya cesó (decisión de Felipe, 2026-09-15): su pendiente no se
 * esconde —un papel que falta sigue faltando— pero deja de competir con lo
 * urgente de quien sigue trabajando. Mantiene su texto de plazo.
 */
export function conCese(u: Urgencia): Urgencia {
  return { ...u, grupo: "sin_plazo" };
}

/** Grupo, luego `orden`, luego persona; `clave` cierra como ancla para que dos llamadas den el mismo orden. */
export function compararPendientes(
  a: { urgencia: Urgencia; persona: string; clave: string },
  b: { urgencia: Urgencia; persona: string; clave: string },
): number {
  return RANGO[a.urgencia.grupo] - RANGO[b.urgencia.grupo]
    || a.urgencia.orden - b.urgencia.orden
    || a.persona.localeCompare(b.persona, "es")
    || (a.clave < b.clave ? -1 : a.clave > b.clave ? 1 : 0);
}

/**
 * El número del menú (nav.tsx) solo se recalculaba al cambiar de pantalla:
 * aprobar algo DENTRO de la Bandeja dejaba el 12 del menú intacto. Quien
 * resuelve algo avisa con este evento, y el menú vuelve a contar con el mismo
 * criterio de siempre (lib/admin/bandeja-equipo.ts).
 */
export const EVENTO_CAMBIO_BANDEJA = "dynamic:bandeja-cambio";

export function avisarCambioEnBandeja(): void {
  if (typeof window !== "undefined") window.dispatchEvent(new Event(EVENTO_CAMBIO_BANDEJA));
}
