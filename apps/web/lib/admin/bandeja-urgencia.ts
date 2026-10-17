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

// ── Seguros (0528) ──────────────────────────────────────────────────────────
// Los números salen de `lib/admin/seguros.ts` (la regla de quién tiene hueco y de
// qué es «por vencer» vive allí, con su prueba); acá solo se ordenan.

const SE_QUEDA_SIN_SEGURO = { futuro: "Se queda sin seguro", pasado: "Se quedó sin seguro" };
const PRIMA_VENCE = { futuro: "La prima vence", pasado: "La prima venció" };

/**
 * Un practicante sin póliza que cubra hoy. El riesgo YA corre —no hay «hoy» ni
 * «próximo» posible—, así que va a «Vencido»: una persona sin ningún seguro es
 * infracción por sí sola (Ley 28518, art. 52.5). Entre dos huecos manda el más
 * largo: quien nunca tuvo póliza antes que quien la perdió ayer.
 */
export function urgenciaSeguroSinPoliza(
  motivo: "nunca" | "vencida" | "aun_no_empieza" | null,
  diasDesdeQueVencio: number | null,
): Urgencia {
  if (motivo === "vencida" && diasDesdeQueVencio !== null) {
    return {
      grupo: "vencido",
      plazo: diasDesdeQueVencio === 0 ? "Dejó de cubrir hoy" : `Dejó de cubrir hace ${diasDesdeQueVencio} día${diasDesdeQueVencio === 1 ? "" : "s"}`,
      nota: "y hoy no tiene seguro",
      orden: -diasDesdeQueVencio,
    };
  }
  if (motivo === "aun_no_empieza") {
    return { grupo: "vencido", plazo: "Sin seguro hoy", nota: "la póliza registrada todavía no empieza", orden: 0 };
  }
  return { grupo: "vencido", plazo: "Sin póliza", nota: "nunca tuvo una registrada", orden: -10_000 };
}

/** Cubierta hoy, pero se queda sin seguro en `dias` y nada empalma. `hasta` es la fecha EXCLUSIVA. */
export function urgenciaSeguroPorVencer(dias: number, hasta: string): Urgencia {
  return {
    grupo: dias <= 0 ? "hoy" : "proximo",
    plazo: enDias(dias, SE_QUEDA_SIN_SEGURO),
    nota: `el ${diaYMes(hasta)}`,
    orden: dias,
  };
}

/**
 * El papeleo de una póliza (prima, firma, factura). Manda la prima, que es lo
 * único con plazo: con mora la cobertura se suspende sola a los 30 días
 * (convenio de pago, cláusula quinta). Firma y factura no tienen fecha límite.
 */
export function urgenciaSeguroPapeleo(
  prima: { estado: string; dias: number | null; venceEl: string | null } | null,
  pasos: readonly string[],
): Urgencia {
  if (prima && pasos.includes("pagada")) {
    const d = prima.dias ?? 0;
    if (prima.estado === "suspendida") {
      return { grupo: "vencido", plazo: "Cobertura suspendida", nota: "por más de 30 días de mora", orden: d };
    }
    if (prima.estado === "en_mora") {
      return { grupo: "vencido", plazo: enDias(d, PRIMA_VENCE), nota: "la cobertura se suspende a los 30 días de mora", orden: d };
    }
    if (prima.estado === "por_vencer") {
      return { grupo: d === 0 ? "hoy" : "proximo", plazo: enDias(d, PRIMA_VENCE), nota: prima.venceEl ? `el ${diaYMes(prima.venceEl)}` : null, orden: d };
    }
    return { grupo: "sin_plazo", plazo: "Prima por pagar", nota: prima.venceEl ? `vence el ${diaYMes(prima.venceEl)}` : "sin fecha de vencimiento", orden: 0 };
  }
  return { grupo: "sin_plazo", plazo: pasos.includes("firmada") ? "Sin firmar" : "Sin factura", nota: null, orden: 0 };
}

// ── Fuentes sumadas el 2026-09-15 (Contratos, Correcciones, Documentación,
//    Feriados, Disciplina). Cada una se mide contra SU plazo real, nunca contra
//    uno inventado para la Bandeja. ─────────────────────────────────────────

/** `2026-09-15` + 30 → `2026-10-15`, por partes y en UTC: sin el huso del navegador. */
export function sumarDias(fecha: string, dias: number): string {
  const [y, m, d] = fecha.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + dias)).toISOString().slice(0, 10);
}

const PLAZO = { futuro: "Plazo vence", pasado: "Plazo venció" };

/** Lo que la Bandeja lee de una fila de `fn_contratos_tablero` (0386). */
export interface FilaContrato {
  estado: string;
  dias_restantes: number | null;
  fecha_fin_contrato: string | null;
  copia_entregada_at: string | null;
  comunicado_mtpe_at: string | null;
  copia_vence: string | null;
  mtpe_vence: string | null;
  dias_marcados_despues: number;
}

/**
 * Qué estados de un contrato piden a alguien. Son los que la pantalla de
 * Contratos pinta en «pendientes», MENOS `sin_vencimiento`: esa pantalla lo
 * cuenta a la vez como pendiente y como vigente (su pestaña «Vigentes» lo
 * junta con `ok`), así que no se trae una contradicción a la Bandeja. Si un
 * contrato a plazo sin fecha de fin resulta ser un problema real, se agrega
 * aquí con su propio texto — no se infiere.
 */
export const ESTADOS_CONTRATO_PENDIENTE: ReadonlySet<string> = new Set([
  "desnaturalizado", "vencido", "por_vencer", "sin_contrato", "sin_firmar", "tramite_pendiente",
]);

export function urgenciaContrato(c: FilaContrato, hoy: string = hoyLima()): Urgencia {
  switch (c.estado) {
    case "desnaturalizado": {
      const n = c.dias_marcados_despues;
      // Primero de todo el grupo: es el único que ya puede haber cambiado el
      // tipo de contrato por ley (art. 77 del D.S. 003-97-TR).
      return { grupo: "vencido", plazo: "Riesgo art. 77", nota: `marcó ${n} día${n === 1 ? "" : "s"} sin contrato vigente`, orden: -100000 - n };
    }
    case "vencido":
      return {
        grupo: "vencido",
        plazo: c.dias_restantes !== null ? enDias(c.dias_restantes, VENCE) : "Contrato vencido",
        nota: c.fecha_fin_contrato ? `el ${diaYMes(c.fecha_fin_contrato)}` : null,
        orden: c.dias_restantes ?? -1,
      };
    case "por_vencer": {
      const d = c.dias_restantes ?? 0;
      return { grupo: d === 0 ? "hoy" : "proximo", plazo: enDias(d, VENCE), nota: c.fecha_fin_contrato ? `el ${diaYMes(c.fecha_fin_contrato)}` : null, orden: d };
    }
    case "tramite_pendiente": {
      // Desde la 0470, `tramite_pendiente` solo significa "falta la copia" —
      // comunicar el contrato al MTPE ya no es trámite de nadie (D. Leg.
      // 1246), así que el plazo que importa es siempre el de la copia (5
      // días desde el inicio de la prestación).
      const limite = c.copia_vence;
      if (!limite) return { grupo: "sin_plazo", plazo: "Trámite pendiente", nota: null, orden: 0 };
      const d = diasEntre(hoy, limite);
      return { grupo: d < 0 ? "vencido" : d === 0 ? "hoy" : "proximo", plazo: enDias(d, PLAZO), nota: `el ${diaYMes(limite)}`, orden: d };
    }
    case "sin_firmar":
      return { grupo: "sin_plazo", plazo: "Sin firmar", nota: null, orden: 0 };
    default:
      return { grupo: "sin_plazo", plazo: "Sin contrato", nota: null, orden: 0 };
  }
}

export interface PeriodoDePago { fecha_ini: string; fecha_fin: string }

const CIERRA = { futuro: "Periodo cierra", pasado: "Periodo cerró" };

/**
 * Un día (o una marca) por revisar en Correcciones. Su plazo es el cierre del
 * periodo que lo paga: después de pagado, corregirlo exige reabrir el periodo.
 */
export function urgenciaDiaPorRevisar(
  fecha: string, periodoPagado: boolean, periodo: PeriodoDePago | null, hoy: string = hoyLima(),
): Urgencia {
  if (periodoPagado) {
    return { grupo: "vencido", plazo: "Periodo ya pagado", nota: "hay que reabrirlo para corregir", orden: diasEntre(hoy, fecha) };
  }
  if (periodo && fecha < periodo.fecha_ini) {
    return { grupo: "vencido", plazo: "Su periodo ya cerró", nota: `día ${diaYMes(fecha)}`, orden: diasEntre(hoy, fecha) };
  }
  if (periodo && fecha <= periodo.fecha_fin) {
    const d = diasEntre(hoy, periodo.fecha_fin);
    return {
      grupo: d <= 0 ? "hoy" : "proximo",
      plazo: d <= 0 ? "Periodo cierra hoy" : enDias(d, CIERRA),
      nota: `el ${diaYMes(periodo.fecha_fin)}`,
      orden: d,
    };
  }
  return { grupo: "sin_plazo", plazo: "Por revisar", nota: null, orden: diasEntre(hoy, fecha) };
}

/**
 * La constancia del bono de cumpleaños (`bono_estado` de `fn_documentos_tablero`).
 * `este_mes` se cierra el último día del mes; `vencido` ya cumplió sin cargo.
 */
export function urgenciaBono(estado: string, hoy: string = hoyLima()): Urgencia {
  if (estado === "vencido") return { grupo: "vencido", plazo: "Cumpleaños pasado", nota: "sin cargo firmado", orden: -1 };
  const [y, m] = hoy.split("-").map(Number);
  const finDeMes = new Date(Date.UTC(y, m, 0)).toISOString().slice(0, 10);
  const d = diasEntre(hoy, finDeMes);
  return { grupo: d === 0 ? "hoy" : "proximo", plazo: "Cumple este mes", nota: `cargo antes del ${diaYMes(finDeMes)}`, orden: d };
}

/**
 * Plazo del descanso sustitutorio de un feriado trabajado: el trigger
 * `fn_dcs_validar_dia_laborable` (0238) exige un motivo escrito si se da más
 * de 30 días después del feriado.
 */
export const DIAS_PLAZO_DESCANSO_SUSTITUTORIO = 30;

export interface FilaFeriado { fecha_feriado: string; estado: string | null; no_compensa_porque: string | null }

/**
 * Qué feriado trabajado pide a alguien. NO todo el que no tiene descanso: por
 * ley eso es normal y se paga la sobretasa, así que traerlos llenaría la
 * Bandeja de casos que no piden nada. Solo dos:
 *   · un descanso acordado (PENDIENTE) que todavía no se da, contra su plazo;
 *   · un descanso registrado que NO compensa (`no_compensa_porque`).
 */
export function esFeriadoParaBandeja(f: FilaFeriado): boolean {
  return f.estado !== "OTORGADO" && (f.no_compensa_porque !== null || f.estado === "PENDIENTE");
}

export function urgenciaFeriado(f: FilaFeriado, hoy: string = hoyLima()): Urgencia {
  if (f.no_compensa_porque) {
    return { grupo: "vencido", plazo: "No compensa", nota: "el descanso registrado no sirve", orden: -1000 };
  }
  const limite = sumarDias(f.fecha_feriado, DIAS_PLAZO_DESCANSO_SUSTITUTORIO);
  const d = diasEntre(hoy, limite);
  return { grupo: d < 0 ? "vencido" : d === 0 ? "hoy" : "proximo", plazo: enDias(d, PLAZO), nota: `descanso hasta el ${diaYMes(limite)}`, orden: d };
}

/**
 * Un caso de Reportes (0488): su plazo es el del Reglamento que vence antes
 * (`fn_reportes_bandeja` ya lo elige). Un caso URGENTE sube a «Hoy» aunque su
 * plazo sea más adelante: quien lo marcó dijo que hay un riesgo ahora.
 */
export function urgenciaCaso(
  c: { proximo_vence_at: string | null; proximo_plazo: string | null; urgente: boolean },
  hoy: string = hoyLima(),
): Urgencia {
  if (!c.proximo_vence_at) {
    return { grupo: c.urgente ? "hoy" : "sin_plazo", plazo: c.urgente ? "Urgente" : "Sin plazo", nota: null, orden: 0 };
  }
  const d = diasEntre(hoy, fechaLima(c.proximo_vence_at));
  const grupo: GrupoUrgencia = d < 0 ? "vencido" : d === 0 || c.urgente ? "hoy" : "proximo";
  return {
    grupo,
    plazo: c.urgente && d > 0 ? `Urgente · ${enDias(d, VENCE).toLowerCase()}` : enDias(d, VENCE),
    nota: c.proximo_plazo ? c.proximo_plazo.charAt(0).toLowerCase() + c.proximo_plazo.slice(1) : null,
    orden: c.urgente ? d - 1000 : d,
  };
}

/** Un borrador disciplinario esperando el descargo de la persona: su plazo es el del descargo. */
export function urgenciaDescargo(venceAt: string, hoy: string = hoyLima()): Urgencia {
  const d = diasEntre(hoy, fechaLima(venceAt));
  return {
    grupo: d <= 0 ? "hoy" : "proximo",
    plazo: d <= 0 ? "Descargo vence hoy" : enDias(d, { futuro: "Descargo vence", pasado: "Descargo venció" }),
    nota: "esperando a la persona",
    orden: d,
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
