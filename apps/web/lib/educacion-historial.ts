// ============================================================================
// educacion-historial.ts — cómo se dice cada hecho del historial de Educación
// ============================================================================
// QUÉ PROMETE · traducir una fila de `fn_educacion_historial` (0529) a «qué pasó»,
//               en castellano, para DO o para la propia integrante.
// QUÉ ASUME   · que las filas las escribieron las funciones de Educación: sus
//               valores (`aprobada`, `rechazada · ilegible`, fechas ISO) son los
//               que esas funciones ponen. Un campo que no se conoce se dice como
//               «Cambio en Educación» con su valor: nunca se esconde un hecho.
// POR QUÉ AQUÍ · lo usan tres pantallas —el historial general de DO, el de cada
//               estudio y el de «Lo mío»— y tienen que contar lo mismo. No toca
//               React ni Supabase: se prueba con vitest (tests/educacion-historial.test.ts).
// ============================================================================
import { MOTIVO_RECHAZO_LABELS, type MotivoRechazo } from "@cayla-dynamic/shared";
import { fechaCorta } from "@/lib/educacion";

/** Una fila de `fn_educacion_historial`. */
export interface HechoEducacion {
  ocurrio_at: string;
  persona_id: string;
  persona: string;
  sede: string;
  fuente: "auditoria" | "envio" | "retiro";
  campo: string | null;
  valor_anterior: string | null;
  valor_nuevo: string | null;
  /** Para la integrante solo viene el de una constancia (el motivo de un rechazo es para ella). */
  motivo: string | null;
  /** Quién lo hizo. Para la integrante, siempre null. */
  quien: string | null;
  entrega_id: string | null;
  cubre_desde: string | null;
  cubre_hasta: string | null;
}

export type TipoHecho = "solicitud" | "apoyo" | "envio" | "aprobada" | "rechazada" | "revertida" | "retiro";
export type Tono = "positivo" | "alerta" | "advertencia" | "informativo" | "neutral";

export const TIPOS_HECHO: { clave: TipoHecho; etiqueta: string }[] = [
  { clave: "solicitud", etiqueta: "Solicitudes" },
  { clave: "apoyo", etiqueta: "Altas y cambios del apoyo" },
  { clave: "envio", etiqueta: "Constancias enviadas" },
  { clave: "aprobada", etiqueta: "Aprobadas" },
  { clave: "rechazada", etiqueta: "Rechazadas" },
  { clave: "revertida", etiqueta: "Aprobaciones revertidas" },
  { clave: "retiro", etiqueta: "Retiradas" },
];

export interface HechoDicho {
  tipo: TipoHecho;
  titulo: string;
  detalle: string | null;
  tono: Tono;
}

/** "2026-08-01 a 2027-03-31" → "01/08/2026 a 31/03/2027". Las fechas ISO de la auditoría, legibles. */
export function fechasLegibles(t: string | null): string | null {
  if (!t) return t;
  return t.replace(/\b(\d{4}-\d{2}-\d{2})\b/g, (iso) => fechaCorta(iso));
}

const MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "setiembre", "octubre", "noviembre", "diciembre"];
/** "2026-08-01", "2026-12-01" → "agosto a diciembre 2026"; si cruza el año, los dos años. */
export function rangoDeMeses(desde: string, hasta: string): string {
  const [y1, m1] = desde.split("-").map(Number);
  const [y2, m2] = hasta.split("-").map(Number);
  return y1 === y2 ? `${MESES[m1 - 1]} a ${MESES[m2 - 1]} ${y2}` : `${MESES[m1 - 1]} ${y1} a ${MESES[m2 - 1]} ${y2}`;
}

const motivoDeRechazo = (vn: string): string => {
  const cat = vn.split("·")[1]?.trim() as MotivoRechazo | undefined;
  return (cat && MOTIVO_RECHAZO_LABELS[cat]) || "Rechazada";
};

/** Cómo se dice un hecho. `ella` = la propia integrante: le habla en segunda persona. */
export function decirHecho(h: HechoEducacion, vista: "do" | "ella"): HechoDicho {
  const ella = vista === "ella";
  const va = h.valor_anterior, vn = h.valor_nuevo ?? "";

  if (h.fuente === "envio") {
    const adelantado = h.cubre_desde && h.cubre_hasta ? rangoDeMeses(h.cubre_desde, h.cubre_hasta) : null;
    if (h.campo === "do") {
      return { tipo: "envio", tono: "informativo", titulo: ella ? "Desarrollo Organizacional cargó tu constancia" : "DO cargó una constancia a su nombre",
        detalle: adelantado ? `Pago adelantado: ${adelantado}. Queda aprobada al cargarla.` : "Queda aprobada al cargarla." };
    }
    if (h.campo === "migrada") {
      return { tipo: "envio", tono: "neutral", titulo: "Constancia cargada antes de la revisión", detalle: null };
    }
    return { tipo: "envio", tono: "informativo",
      titulo: adelantado ? (ella ? "Enviaste un pago adelantado" : "Envió un pago adelantado") : (ella ? "Enviaste tu constancia" : "Envió su constancia"),
      detalle: adelantado ? `Cubre ${adelantado}. Espera revisión.` : "Espera revisión." };
  }
  if (h.fuente === "retiro") {
    return { tipo: "retiro", tono: "neutral", titulo: ella ? "Retiraste tu constancia" : "Retiró su constancia", detalle: "Antes de que se revisara." };
  }

  switch (h.campo) {
    case "educacion_entrega":
      if (va === "aprobada" && vn.startsWith("rechazada")) {
        const texto = (h.motivo ?? "").replace(/^Aprobación revertida:\s*/, "");
        return { tipo: "revertida", tono: "advertencia",
          titulo: ella ? "Tu constancia aprobada pasó a rechazada" : "Aprobación revertida",
          detalle: `«${motivoDeRechazo(vn)}»${texto ? `: ${texto}` : ""}` };
      }
      if (vn === "aprobada") {
        return { tipo: "aprobada", tono: "positivo", titulo: ella ? "Tu constancia se aprobó" : "Constancia aprobada", detalle: null };
      }
      if (vn.startsWith("rechazada")) {
        return { tipo: "rechazada", tono: "alerta", titulo: ella ? "Tu constancia se rechazó" : "Constancia rechazada",
          detalle: `«${motivoDeRechazo(vn)}»${h.motivo ? `: ${h.motivo}` : ""}` };
      }
      break;
    case "educacion_solicitud":
      if (va === null) return { tipo: "solicitud", tono: "informativo", titulo: ella ? "Pediste tu apoyo" : "Pidió su apoyo", detalle: fechasLegibles(vn) };
      if (vn === "aprobada") return { tipo: "solicitud", tono: "positivo", titulo: ella ? "Tu solicitud se aprobó" : "Solicitud aprobada", detalle: null };
      if (vn === "rechazada") return { tipo: "solicitud", tono: "alerta", titulo: ella ? "Tu solicitud se rechazó" : "Solicitud rechazada", detalle: h.motivo };
      if (vn === "retirada") return { tipo: "solicitud", tono: "neutral", titulo: ella ? "Retiraste tu solicitud" : "Retiró su solicitud", detalle: null };
      break;
    case "educacion_alta":
      return { tipo: "apoyo", tono: "informativo", titulo: ella ? "Se registró tu apoyo" : "Apoyo registrado", detalle: fechasLegibles(vn) };
    case "educacion_datos":
      return { tipo: "apoyo", tono: "neutral", titulo: "Datos del apoyo corregidos", detalle: `${va ?? "—"} → ${vn}${!ella && h.motivo ? ` · «${h.motivo}»` : ""}` };
    case "educacion_nueva_vigencia":
    case "educacion_realineada":
      return { tipo: "apoyo", tono: "neutral", titulo: ella ? "Cambió el monto de tu apoyo" : "Cambio del monto del apoyo",
        detalle: `${fechasLegibles(va) ?? "—"} → ${fechasLegibles(vn)}${!ella && h.motivo ? ` · «${h.motivo}»` : ""}` };
    case "educacion_calendario":
      return { tipo: "apoyo", tono: "neutral", titulo: "Calendario de pagos", detalle: `${va ?? "—"} → ${vn}` };
    case "educacion_cierre":
      return { tipo: "apoyo", tono: "neutral", titulo: ella ? "Se cerró tu apoyo" : "Apoyo cerrado",
        detalle: `Último día: ${fechasLegibles(vn)}${!ella && h.motivo ? ` · «${h.motivo}»` : ""}` };
    case "educacion_cierre_por_cese":
      return { tipo: "apoyo", tono: "neutral", titulo: "Apoyos cerrados por cese", detalle: fechasLegibles(vn) };
  }
  return { tipo: "apoyo", tono: "neutral", titulo: "Cambio en Educación", detalle: fechasLegibles(vn || null) };
}
