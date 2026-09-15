// La evidencia de un caso disciplinario, leída de la asistencia TAL COMO ESTÁ
// HOY: la jornada de cada día, si la tardanza se levantó, si hay una ausencia
// registrada que lo cubre.
//
// POR QUÉ EXISTE: un borrador guarda sus hechos como una foto al generarse
// (`hechos`: fecha y minutos). Si después alguien corrige la marca, levanta la
// tardanza o registra un descanso médico, el semáforo se recalcula solo, pero
// el borrador no se entera y se puede firmar igual con un día que ya no vale
// (auditoría del 2026-09-15, fase 3). Comparar la foto contra hoy es la única
// forma de verlo hasta que la base lo frene al firmar (lote 3 del rediseño).
//
// LO QUE NO HACE: decidir si alguien alcanza un umbral. El número que manda es
// el de `fn_tardanzas_resumen`; esto explica día por día de dónde sale. Las
// faltas sin documento no se listan día por día a propósito: saber qué día le
// TOCABA trabajar a alguien en 180 días es la cascada de `fn_faltas_resumen`,
// y escribirla otra vez acá sería la copia que CLAUDE.md prohíbe.

import type { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { horaLima } from "@cayla-dynamic/shared";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import {
  estadoHoyFalta, estadoHoyTardanza, horaEsperada,
  type DiaAsistencia, type DocDisciplina, type EstadoHoy,
} from "./disciplina";

type Cliente = ReturnType<typeof createAdminSupabaseClient>;

export interface FilaEvidencia {
  fecha: string;
  esperada: string;
  marco: string;
  /** Los minutos que quedaron en el documento; null si no hay documento o es falta. */
  minutosCitados: number | null;
  minutosHoy: number | null;
  hoy: EstadoHoy;
}

export interface Evidencia {
  filas: FilaEvidencia[];
  /** Cuántos días citados ya no se sostienen hoy. 0 si no se pudo leer. */
  noCuentan: number;
  /** Si algo no se pudo leer. Con fallo, la columna «Hoy» no está verificada. */
  fallo: string | null;
}

interface AusenciaRango { tipo: string; fecha_inicio: string; fecha_fin: string | null }

interface Asistencia {
  dias: Map<string, DiaAsistencia>;
  levantadas: Set<string>;
  ausencias: AusenciaRango[];
  fallo: string | null;
}

async function leerAsistencia(
  sb: Cliente, personaId: string, desde: string, hasta: string, soloConTardanza: boolean,
): Promise<Asistencia> {
  const jornadas = (columnas: string) => {
    let q = sb.from("jornadas").select(columnas).eq("persona_id", personaId).gte("fecha", desde).lte("fecha", hasta);
    if (soloConTardanza) q = q.gt("minutos_tarde", 0);
    return q.order("fecha");
  };
  // `horario_aplicado` llegó con la 0446. Si esta base todavía no la tiene
  // (42703 = columna inexistente), se pide sin ella: la hora esperada sale
  // «—» y el resto de la evidencia sigue valiendo.
  let j = await jornadas("fecha, entrada_ts, minutos_tarde, horario_aplicado");
  if (j.error?.code === "42703") j = await jornadas("fecha, entrada_ts, minutos_tarde");

  const [lev, aus] = await Promise.all([
    sb.from("tardanzas_justificadas").select("fecha").eq("persona_id", personaId).gte("fecha", desde).lte("fecha", hasta),
    sb.from("ausencias").select("tipo, fecha_inicio, fecha_fin").eq("persona_id", personaId)
      .is("anulada_at", null).lte("fecha_inicio", hasta).or(`fecha_fin.gte.${desde},fecha_fin.is.null`),
  ]);

  const primerError = j.error ?? lev.error ?? aus.error;
  const dias = ((j.data ?? []) as unknown as DiaAsistencia[]).map((d) => ({ ...d, horario_aplicado: d.horario_aplicado ?? null }));
  return {
    dias: new Map(dias.map((d) => [d.fecha, d])),
    levantadas: new Set(((lev.data ?? []) as { fecha: string }[]).map((x) => x.fecha)),
    ausencias: (aus.data ?? []) as AusenciaRango[],
    fallo: primerError ? mensajeDeError(primerError, "leer la asistencia") : null,
  };
}

function ausenciaDelDia(ausencias: AusenciaRango[], fecha: string, nombres: Map<string, string>): string | null {
  const a = ausencias.find((x) => x.fecha_inicio <= fecha && (x.fecha_fin ?? x.fecha_inicio) >= fecha);
  return a ? (nombres.get(a.tipo) ?? "Ausencia registrada") : null;
}

/**
 * Los días que OTROS documentos firmados o entregados de la misma causal ya
 * citan, con el número del documento. Es el non bis in idem día por día que
 * aplica `fn_tardanza_ya_documentada` (0311); acá solo para rotularlo.
 */
function diasYaDocumentados(docs: readonly DocDisciplina[], personaId: string, causal: string, excluirId?: string): Map<string, string> {
  const m = new Map<string, string>();
  for (const d of docs) {
    if (d.persona_id !== personaId || d.tipo_causal !== causal || d.id === excluirId) continue;
    if (d.estado !== "firmado" && d.estado !== "entregado") continue;
    for (const h of Array.isArray(d.hechos) ? d.hechos : []) m.set(h.fecha, d.correlativo ?? "un documento firmado");
  }
  return m;
}

function fila(dia: DiaAsistencia | undefined, fecha: string, minutosCitados: number | null, hoy: EstadoHoy): FilaEvidencia {
  return {
    fecha,
    esperada: horaEsperada(dia),
    marco: dia?.entrada_ts ? horaLima(dia.entrada_ts) : "sin marca",
    minutosCitados,
    minutosHoy: dia?.minutos_tarde ?? null,
    hoy,
  };
}

/** Los hechos de un documento, cada uno con lo que dice hoy la asistencia. */
export async function evidenciaDeDocumento(
  sb: Cliente, doc: DocDisciplina, docs: readonly DocDisciplina[], nombresAusencia: Map<string, string>,
): Promise<Evidencia> {
  const hechos = Array.isArray(doc.hechos) ? doc.hechos : [];
  if (hechos.length === 0 || (doc.tipo_causal !== "tardanza" && doc.tipo_causal !== "falta")) {
    return { filas: [], noCuentan: 0, fallo: null };
  }
  const fechas = hechos.map((h) => h.fecha).sort();
  const a = await leerAsistencia(sb, doc.persona_id, fechas[0], fechas[fechas.length - 1], false);
  const documentados = diasYaDocumentados(docs, doc.persona_id, doc.tipo_causal, doc.id);

  const filas = hechos.map((h) => {
    const dia = a.dias.get(h.fecha);
    const ausencia = ausenciaDelDia(a.ausencias, h.fecha, nombresAusencia);
    const hoy = doc.tipo_causal === "tardanza"
      ? estadoHoyTardanza({
          dia, minutosCitados: h.minutos, levantada: a.levantadas.has(h.fecha),
          documentadaEn: documentados.get(h.fecha) ?? null, ausencia,
        })
      : estadoHoyFalta({ dia, ausencia });
    return fila(dia, h.fecha, h.minutos ?? null, hoy);
  });
  // Con un fallo de lectura no se afirma que algo dejó de contar: sin datos,
  // «no figura tardanza» sería una conclusión inventada.
  return { filas, noCuentan: a.fallo ? 0 : filas.filter((f) => !f.hoy.cuenta).length, fallo: a.fallo };
}

/**
 * Las tardanzas de una persona en un mes, para revisar ANTES de generar: cada
 * día con minutos, rotulado con lo que lo deja fuera (levantada, ya
 * documentada, más de tres horas) o «Cuenta».
 */
export async function evidenciaDeTardanzasDelMes(
  sb: Cliente, personaId: string, desde: string, hasta: string,
  docs: readonly DocDisciplina[], nombresAusencia: Map<string, string>,
): Promise<Evidencia> {
  const a = await leerAsistencia(sb, personaId, desde, hasta, true);
  const documentados = diasYaDocumentados(docs, personaId, "tardanza");
  // El corte de lo ya sancionado (0311): todo día hasta el fin del periodo del
  // último documento ENTREGADO ya no se vuelve a contar, aunque ese documento
  // no lo cite uno por uno.
  const corte = docs
    .filter((d) => d.persona_id === personaId && d.tipo_causal === "tardanza" && d.estado === "entregado" && d.periodo_hasta)
    .sort((x, y) => (y.periodo_hasta ?? "").localeCompare(x.periodo_hasta ?? ""))[0];

  const filas = [...a.dias.values()].map((dia) => {
    const antesDelCorte = corte?.periodo_hasta && dia.fecha <= corte.periodo_hasta
      ? (corte.correlativo ?? "un documento entregado") : null;
    const hoy = estadoHoyTardanza({
      dia, levantada: a.levantadas.has(dia.fecha),
      documentadaEn: documentados.get(dia.fecha) ?? antesDelCorte,
      ausencia: ausenciaDelDia(a.ausencias, dia.fecha, nombresAusencia),
    });
    return fila(dia, dia.fecha, null, hoy);
  });
  return { filas, noCuentan: filas.filter((f) => !f.hoy.cuenta).length, fallo: a.fallo };
}
