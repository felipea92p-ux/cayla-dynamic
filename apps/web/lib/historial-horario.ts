// «Historial de horario» — qué le cambió a cada quien en su horario, en una sola línea de tiempo.
//
// QUÉ PROMETE
//   Juntar en una lista, de lo más reciente a lo más viejo, todo lo que movió
//   el horario de una persona: su horario base, el turno de un día, piso o
//   almacén, su jornada y su disponibilidad. Cada entrada dice qué cambió,
//   de qué a qué, qué día afecta (si es de un día), cuándo se hizo y quién.
//
// DE DÓNDE SALE (no se escribe nada nuevo)
//   · `correcciones_auditoria`, que ya guardan las puertas de cada cosa:
//       horarios_asignados              fn_set_horario_semanal (0440, 0447)
//       turnos.horario                  fn_set_turno / fn_set_descanso / fn_quitar_turno (0298, 0327)
//       turnos.puesto                   fn_set_almacen_del_dia (0579)
//       personas.jornada_semanal_horas  fn_set_jornada (0584)
//     Su RLS ya es la que hace falta: cada quien lo suyo, la líder su sede, DO todo.
//   · `disponibilidades` (0584): cada envío es una fila que no se pisa, así que
//     ella misma es el historial — enviada, aprobada, conversada, retirada.
//   · Qué dice cada cambio en palabras NO se escribe acá: es `describirCambio`
//     (lib/admin/historial-correcciones.ts), el mismo de Correcciones y de
//     «Cambios a tu registro». Acá solo se elige, se ordena y se fecha.
//
// EL DÍA QUE AFECTA
//   Un turno o un puesto es de UN día, pero la auditoría no lo guarda en una
//   columna: va dentro del motivo que arma la función («Turno del 12/11/2026 …»,
//   «Puesto del 12/11/2026 …»). Se lee de ahí; si el texto no lo trae, la
//   entrada sale sin día en vez de inventarlo.

import { rotuloDeCampo } from "@cayla-dynamic/shared";
import { describirCambio, type Auditoria } from "@/lib/admin/historial-correcciones";
import { desdeBloques, diaMes, resumenEnPalabras, type Bloque } from "@/lib/disponibilidad";

export type TipoCambio = "horario" | "turno" | "puesto" | "jornada" | "disponibilidad";

/** Qué campo de la auditoría es de qué tipo. Los demás campos no son de horario. */
export const CAMPOS_DE_HORARIO: Record<string, Exclude<TipoCambio, "disponibilidad">> = {
  horarios_asignados: "horario",
  "turnos.horario": "turno",
  "turnos.puesto": "puesto",
  "personas.jornada_semanal_horas": "jornada",
};

export const TIPOS: readonly { valor: TipoCambio; label: string }[] = [
  { valor: "horario", label: "Horario base" },
  { valor: "turno", label: "Turno de un día" },
  { valor: "puesto", label: "Piso o almacén" },
  { valor: "jornada", label: "Jornada" },
  { valor: "disponibilidad", label: "Disponibilidad" },
];

export interface FilaAuditoria extends Auditoria {
  persona_id: string;
}

export interface FilaDisponibilidad {
  id: string;
  persona_id: string;
  tipo: "total" | "parcial";
  estado: "enviada" | "aprobada" | "conversar" | "reemplazada" | "retirada";
  vigente_desde: string;
  vigente_hasta: string | null;
  horario_fijo: boolean;
  registrada_por: string;
  creada_at: string;
  resuelta_por: string | null;
  resuelta_at: string | null;
  respuesta: string | null;
  disponibilidad_bloques: Bloque[];
}

export interface EntradaHistorial {
  /** Único en la lista. */
  clave: string;
  personaId: string;
  tipo: TipoCambio;
  /** Cuándo se hizo el cambio (instante). */
  cuando: string;
  /** El día que afecta, AAAA-MM-DD, si es de un día. */
  dia: string | null;
  accion: string;
  detalle: string;
  /** Id de quien lo hizo; null si fue la propia persona (enviar o retirar su disponibilidad). */
  quien: string | null;
  /** El motivo escrito, cuando lo hay y dice algo más que la frase de la función. */
  motivo: string | null;
}

/** «Turno del 12/11/2026 …» → «2026-11-12». */
export function diaDelMotivo(motivo: string | null | undefined): string | null {
  const m = (motivo ?? "").match(/^(?:Turno|Puesto) del (\d{2})\/(\d{2})\/(\d{4})/);
  return m ? `${m[3]}-${m[2]}-${m[1]}` : null;
}

const horasTexto = (v: string | null) => (v === null || v === "" ? "sin registrar" : `${Number(v)} h`);

export function desdeAuditoria(f: FilaAuditoria): EntradaHistorial | null {
  const tipo = CAMPOS_DE_HORARIO[f.campo_modificado];
  if (!tipo) return null;
  const base = { clave: `a-${f.id}`, personaId: f.persona_id, tipo, cuando: f.corregido_at, quien: f.corregido_por };
  if (tipo === "jornada") {
    // fn_set_jornada guarda «<motivo de DO> — No cambia su pago: …»: se muestra lo que escribió DO.
    return {
      ...base, dia: null, accion: rotuloDeCampo(f.campo_modificado),
      detalle: `Pasa de ${horasTexto(f.valor_anterior)} a ${horasTexto(f.valor_nuevo)} por semana`,
      motivo: f.motivo.split(" — ")[0]?.trim() || null,
    };
  }
  const d = describirCambio(f);
  // horarios_asignados lleva el motivo que escribió quien lo cambió; turnos y puesto llevan la frase de la función.
  return {
    ...base, dia: diaDelMotivo(f.motivo), accion: d.accion, detalle: d.detalle,
    motivo: tipo === "horario" ? f.motivo || null : null,
  };
}

/** Un envío de disponibilidad son hasta dos momentos: cuando se mandó y cuando se resolvió. */
export function desdeDisponibilidad(d: FilaDisponibilidad, quien: "tu" | "ella" = "ella"): EntradaHistorial[] {
  const lo = d.tipo === "total"
    ? (quien === "tu" ? "Puedes cualquier día y hora." : "Puede cualquier día y hora.")
    : (() => { const { semana, excepciones } = desdeBloques(d.disponibilidad_bloques); return resumenEnPalabras(semana, excepciones, quien).join(" "); })();
  const vigencia = `Desde el ${diaMes(d.vigente_desde)}${d.vigente_hasta ? ` hasta el ${diaMes(d.vigente_hasta)}` : ""}.`;
  const porOtra = d.registrada_por !== d.persona_id;
  const out: EntradaHistorial[] = [];
  out.push({
    clave: `d-${d.id}-envio`, personaId: d.persona_id, tipo: "disponibilidad", cuando: d.creada_at, dia: null,
    accion: porOtra ? "Disponibilidad registrada por DO" : "Disponibilidad enviada",
    detalle: `${lo} ${vigencia}`, quien: porOtra ? d.registrada_por : null, motivo: null,
  });
  if (d.resuelta_at && d.resuelta_por && !(porOtra && d.estado === "aprobada" && d.resuelta_por === d.registrada_por)) {
    out.push({
      clave: `d-${d.id}-resuelta`, personaId: d.persona_id, tipo: "disponibilidad", cuando: d.resuelta_at, dia: null,
      accion: d.estado === "conversar" ? "Disponibilidad: pidió conversarla" : "Disponibilidad aprobada",
      detalle: d.estado === "conversar" ? `«${d.respuesta ?? ""}»` : `${lo}${d.horario_fijo ? " Con horario fijo." : ""}`,
      quien: d.resuelta_por, motivo: null,
    });
  }
  if (d.estado === "retirada") {
    // La tabla no guarda cuándo se retiró: se fecha con el envío, que es lo único cierto.
    out[0] = { ...out[0], accion: "Disponibilidad enviada y luego retirada" };
  }
  return out;
}

/** Todo junto, de lo más reciente a lo más viejo; los empates, por clave (estable). */
export function armarHistorial(
  auditoria: FilaAuditoria[], disponibilidades: FilaDisponibilidad[], quien: "tu" | "ella" = "ella",
): EntradaHistorial[] {
  const todas = [
    ...auditoria.map(desdeAuditoria).filter((e): e is EntradaHistorial => e !== null),
    ...disponibilidades.flatMap((d) => desdeDisponibilidad(d, quien)),
  ];
  return todas.sort((a, b) => b.cuando.localeCompare(a.cuando) || b.clave.localeCompare(a.clave));
}
