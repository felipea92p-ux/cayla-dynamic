// Lo que la pantalla de Disciplina decide sobre sus propios datos: en qué paso
// está un borrador, a qué pestaña va un documento, qué le falta a un
// entregado, y qué dice HOY la asistencia de un día que un documento cita.
//
// POR QUÉ EXISTE: hasta el rediseño de setiembre de 2026 todo esto vivía
// escrito dentro del JSX de `admin/disciplina/page.tsx` —la cascada del
// descargo en un ternario de cuatro ramas, «entregado sin cargo» calculado
// tres veces en la misma fila—, así que no se podía probar sin levantar el
// panel. Una pantalla que arma expedientes no puede depender de que alguien
// mire con cuidado.
//
// LO QUE ESTO NO ES: la regla disciplinaria. Quién alcanza un umbral, qué
// escalón le toca y qué hechos cuentan lo deciden `fn_tardanzas_resumen`,
// `fn_faltas_resumen` y los generadores de la base; la firma la valida
// `fn_expediente_firmar`. Acá solo se ORDENA lo que la base ya respondió y se
// DESCRIBE lo que la asistencia dice hoy. Si esto y la base discrepan, gana la
// base: lo peor que puede pasar es un letrero equivocado, nunca un documento.
//
// Sin React ni Supabase a propósito, igual que `jornada-esperada.ts`: así lo
// cubre `tests/disciplina.test.ts` en cada push.

import { NIVEL_DISCIPLINARIO_CORTO, fechaLima, hoyLima } from "@cayla-dynamic/shared";

// ── Tipos de lo que llega de la base ─────────────────────────────────────────

export type EstadoDocumento = "borrador" | "firmado" | "entregado" | "anulado" | "cerrado_sin_entrega";
/** Los tres papeles que pueden colgar de un documento (mig. 0206). */
export type TipoPapel = "cargo_firmado" | "acta_negativa" | "descargo";

export interface Hecho { fecha: string; minutos?: number }

/**
 * Una fila de `fn_tardanzas_resumen`. `umbral` nombra el escalón ALCANZADO
 * —amonestacion · suspension · imputacion— o `aviso` (le falta uno) o
 * `bloqueado` (imputación vigente). `minimo` es cuántas exige el escalón de
 * ESA persona: 3, 2 o 1 según su historial (mig. 0200, vigente 0311).
 */
export interface TardanzaRow {
  persona_id: string; nombre: string; sede: string; tardanzas_mes: number;
  umbral: string; sin_medir: number; minimo: number | null; nivel_siguiente: string;
}
/** Una fila de `fn_faltas_resumen` (vigente 0396). `en_30` es el MÁXIMO de
 *  cualquier ventana móvil de 30 días dentro de los 180, no «los últimos 30». */
export interface FaltaRow {
  persona_id: string; nombre: string; sede: string;
  consecutivas: number; en_30: number; en_180: number; nivel: string;
}

export interface Adjunto {
  id: string; documento_id: string; storage_path: string; tipo: TipoPapel;
  nota: string | null; subido_at: string;
}

export interface DocDisciplina {
  id: string; persona_id: string; tipo_causal: string; nivel: string; estado: EstadoDocumento;
  periodo_desde: string | null; periodo_hasta: string | null; hechos: Hecho[];
  suspension_dias: number | null; suspension_desde: string | null; suspension_hasta: string | null;
  suspension_fechas: string[] | null;
  /** Fecha de cese DECLARADA en la carta de despido (art. 32 LPCL, mig. 0205). */
  fecha_cese: string | null;
  resuelto_at: string | null; resuelto_resultado: string | null; resuelto_motivo: string | null; resuelto_por: string | null;
  cargos_comunicados_at: string | null; descargo_vence_at: string | null;
  descargo_acogido: string | null; descargo_valoracion: string | null;
  correlativo: string | null; creado_at: string; creado_por: string | null;
  firmante_id: string | null; firmado_at: string | null;
  entregado_at: string | null; entregado_por: string | null; medio_entrega: string | null;
  entrega_testigo_nombre: string | null;
  observacion: string | null;
}

// ── Borradores: en qué paso del art. 55.2 está ───────────────────────────────

/** Los niveles que pasan por el descargo previo del art. 55.2 del RIT. La
 *  imputación y el despido NO: siguen el procedimiento del art. 57, con el
 *  plazo del art. 31 de la LPCL, que es otro y más largo. */
export function esGradual(nivel: string): boolean {
  return nivel === "amonestacion" || nivel === "suspension";
}

export type EtapaBorrador = "comunicar" | "esperando" | "valorar" | "firmar";

/**
 * El paso que toca en un borrador. Es la misma cascada que exige la base desde
 * la 0212 —comunicar cargos, esperar el plazo, valorar el descargo, firmar—
 * y que la pantalla tenía escrita como un ternario dentro de la fila.
 *
 * `ahora` entra por parámetro para que la prueba no dependa del reloj. El
 * plazo se mira contra el reloj del navegador solo para PINTAR: quien decide
 * es la base, que rechaza la firma mientras el plazo no haya vencido.
 */
export function etapaDelBorrador(d: DocDisciplina, exigeDescargo: boolean, ahora: Date = new Date()): EtapaBorrador {
  if (!exigeDescargo || !esGradual(d.nivel)) return "firmar";
  if (d.cargos_comunicados_at === null) return "comunicar";
  if (d.descargo_vence_at !== null && new Date(d.descargo_vence_at) > ahora) return "esperando";
  if (d.descargo_acogido === null) return "valorar";
  return "firmar";
}

export const ETAPA_LABEL: Record<EtapaBorrador, string> = {
  comunicar: "Comunicar cargos",
  esperando: "Esperando descargo",
  valorar: "Valorar descargo",
  firmar: "Listo para firmar",
};

/** Las cuatro etapas en orden, para dibujar el avance. */
export const ETAPAS: readonly EtapaBorrador[] = ["comunicar", "esperando", "valorar", "firmar"];

// ── Documentos: qué les falta y en qué pestaña viven ─────────────────────────

export type Pestana = "revision" | "borradores" | "entregar" | "historial";

/** Si el documento tiene archivado el papel que prueba su entrega: el cargo
 *  firmado o el acta de negativa (que produce los mismos efectos, num. 55.4). */
export function tienePapelDeEntrega(adjuntos: readonly Adjunto[]): boolean {
  return adjuntos.some((a) => a.tipo === "cargo_firmado" || a.tipo === "acta_negativa");
}

export type PendienteDeEntregado = "cargo" | "resolver";

/**
 * Lo que un documento YA ENTREGADO todavía pide.
 *
 * Por esto «entregado» no es «cerrado»: una entrega sin el cargo archivado
 * depende de la palabra de quien la registró, y una imputación entregada sin
 * resolver hace que el semáforo pida la misma decisión durante doce meses.
 * Mientras pida algo, no pasa al historial.
 */
export function pendientesDeEntregado(d: DocDisciplina, adjuntos: readonly Adjunto[]): PendienteDeEntregado[] {
  if (d.estado !== "entregado") return [];
  const p: PendienteDeEntregado[] = [];
  if (!tienePapelDeEntrega(adjuntos)) p.push("cargo");
  if (d.nivel === "imputacion" && !d.resuelto_at) p.push("resolver");
  return p;
}

export function pestanaDelDocumento(d: DocDisciplina, adjuntos: readonly Adjunto[]): Exclude<Pestana, "revision"> {
  switch (d.estado) {
    case "borrador": return "borradores";
    case "firmado": return "entregar";
    case "entregado": return pendientesDeEntregado(d, adjuntos).length > 0 ? "entregar" : "historial";
    default: return "historial";
  }
}

// ── Detección: quién requiere revisión y quién solo se sigue ─────────────────

export type VarianteEstado = "neutral" | "alerta" | "advertencia" | "positivo" | "informativo";

export interface SituacionDeteccion {
  /** `alcanzo` requiere revisión; `seguimiento` se mira, pero no admite documento. */
  grupo: "alcanzo" | "seguimiento";
  etiqueta: string;
  variante: VarianteEstado;
  /** Si «Generar borrador» tiene alguna posibilidad de que la base lo acepte. */
  generable: boolean;
  /** Por qué no, dicho para quien lo va a leer. Null cuando se puede. */
  porQueNo: string | null;
}

/**
 * La situación de una fila del semáforo de tardanzas.
 *
 * Hasta el rediseño, el botón «Generar borrador» se ofrecía también en
 * «aviso» —le falta una— y la base lo rechazaba siempre (`fn_expediente_
 * generar_tardanza`, 0413: n < mínimo). Las tres filas del 2026-09-15 eran de
 * ese tipo. Un botón que solo puede dar error enseña a ignorar los errores.
 */
export function situacionTardanza(t: TardanzaRow, nombreMes: string, tieneBorrador: boolean): SituacionDeteccion {
  if (t.umbral === "bloqueado") {
    return {
      grupo: "seguimiento", etiqueta: "Imputación vigente · decide Gerencia", variante: "informativo", generable: false,
      porQueNo: "Ya tiene una imputación de cargos vigente. El siguiente paso es evaluar sus descargos (art. 31) y lo decide Gerencia, no el sistema.",
    };
  }
  if (t.tardanzas_mes === 0) {
    return {
      grupo: "seguimiento", etiqueta: `${t.sin_medir} sin medir`, variante: "neutral", generable: false,
      porQueNo: "Sus únicos días pasan de tres horas: no se puede imputar sobre una medición dudosa. Revisa su turno de esos días.",
    };
  }
  if (t.umbral === "aviso") {
    const falta = t.minimo !== null ? Math.max(t.minimo - t.tardanzas_mes, 1) : 1;
    return {
      grupo: "seguimiento", etiqueta: falta === 1 ? "Le falta 1" : `Le faltan ${falta}`, variante: "advertencia", generable: false,
      porQueNo: `Aún no llega a su umbral: lleva ${t.tardanzas_mes} en ${nombreMes} y su escalón exige ${t.minimo ?? "más"}.`,
    };
  }
  const nivel = NIVEL_DISCIPLINARIO_CORTO[t.umbral as keyof typeof NIVEL_DISCIPLINARIO_CORTO] ?? t.umbral;
  if (tieneBorrador) {
    return {
      grupo: "alcanzo", etiqueta: "Ya tiene borrador", variante: "informativo", generable: false,
      porQueNo: "Ya hay un borrador de tardanza pendiente para esta persona. Revísalo en Borradores antes de generar otro.",
    };
  }
  return { grupo: "alcanzo", etiqueta: `Alcanzó su umbral · ${nivel}`, variante: "alerta", generable: true, porQueNo: null };
}

/** Los umbrales graves del art. 25 h) que usa el semáforo de faltas. Solo para
 *  DIBUJAR el avance; la cuenta y el color los decide `fn_faltas_resumen`. */
export const UMBRAL_FALTAS = { consecutivas: 4, en_30: 6, en_180: 16 } as const;

/**
 * La situación de una fila del semáforo de faltas.
 *
 * Todas van a «requieren revisión»: el generador de faltas no exige umbral
 * (0390), así que cualquier fila admite borrador. Pero el semáforo no descuenta
 * lo ya sancionado —hallazgo de la auditoría del 2026-09-15—, así que alguien
 * con su memo entregado puede seguir acá. Por eso la etiqueta dice «revisar»
 * y no «sancionar».
 */
export function situacionFalta(f: FaltaRow, tieneBorrador: boolean): SituacionDeteccion {
  if (tieneBorrador) {
    return {
      grupo: "alcanzo", etiqueta: "Ya tiene borrador", variante: "informativo", generable: false,
      porQueNo: "Ya hay un borrador de faltas pendiente para esta persona. Revísalo en Borradores antes de generar otro.",
    };
  }
  return f.nivel === "rojo"
    ? { grupo: "alcanzo", etiqueta: "Umbral grave · art. 25 h)", variante: "alerta", generable: true, porQueNo: null }
    : { grupo: "alcanzo", etiqueta: "Patrón de faltas", variante: "advertencia", generable: true, porQueNo: null };
}

// ── Evidencia: qué dice HOY la asistencia de un día ──────────────────────────

/** Lo mínimo de `jornadas` que hace falta para describir un día. */
export interface DiaAsistencia {
  fecha: string;
  entrada_ts: string | null;
  minutos_tarde: number | null;
  /** La foto del horario con que se midió (mig. 0446). Null en jornadas
   *  anteriores a esa migración que no se volvieron a calcular. */
  horario_aplicado: { entrada?: string | null; es_descanso?: boolean | null } | null;
}

export interface EstadoHoy {
  /** Si ese día, tal como está hoy la asistencia, sostiene el hecho. */
  cuenta: boolean;
  etiqueta: string;
}

/** Tardanzas de más de tres horas: no suman al umbral (mig. 0189). */
export const TARDANZA_MEDIBLE_MAX_MIN = 180;

/**
 * Qué dice hoy la asistencia de un día citado como tardanza.
 *
 * El orden importa y copia el de `fn_tardanzas_resumen`: lo levantado y lo ya
 * documentado no cuentan aunque la marca siga tarde. Una ausencia registrada
 * NO excluye —la función de la base no la mira—, así que se avisa sin
 * descontarla: decir «no cuenta» ahí sería contradecir a la base.
 *
 * `minutosCitados` es lo que quedó en el documento. Si hoy la jornada dice
 * otro número, se muestra el de hoy: es la señal de que alguien corrigió la
 * marca después de generar.
 */
export function estadoHoyTardanza(opciones: {
  dia: DiaAsistencia | undefined;
  minutosCitados?: number;
  levantada: boolean;
  documentadaEn: string | null;
  ausencia: string | null;
}): EstadoHoy {
  const { dia, minutosCitados, levantada, documentadaEn, ausencia } = opciones;
  if (levantada) return { cuenta: false, etiqueta: "Tardanza levantada" };
  const m = dia?.minutos_tarde ?? null;
  if (m === null || m <= 0) return { cuenta: false, etiqueta: "Hoy no figura tardanza" };
  if (m > TARDANZA_MEDIBLE_MAX_MIN) return { cuenta: false, etiqueta: "Sin medir · más de 3 h" };
  if (documentadaEn) return { cuenta: false, etiqueta: `Ya documentada en ${documentadaEn}` };
  const distinto = minutosCitados !== undefined && minutosCitados !== m;
  if (ausencia) return { cuenta: true, etiqueta: `Cuenta · ese día figura ${ausencia.toLowerCase()}` };
  return { cuenta: true, etiqueta: distinto ? `Cuenta · hoy ${m}′` : "Cuenta" };
}

/**
 * Qué dice hoy la asistencia de un día citado como falta.
 *
 * Una ausencia registrada después (un descanso médico, unas vacaciones) sí la
 * deja de contar para `fn_faltas_resumen`, y una marca de entrada también.
 * Registrar una ausencia no revisa ningún expediente —hallazgo de la auditoría
 * del 2026-09-15—, así que esta es hoy la única forma de verlo.
 */
export function estadoHoyFalta(opciones: { dia: DiaAsistencia | undefined; ausencia: string | null }): EstadoHoy {
  const { dia, ausencia } = opciones;
  if (ausencia) return { cuenta: false, etiqueta: `Justificada · ${ausencia.toLowerCase()}` };
  if (dia?.entrada_ts) return { cuenta: false, etiqueta: "Hoy tiene marca de entrada" };
  if (dia?.horario_aplicado?.es_descanso) return { cuenta: false, etiqueta: "Hoy figura como descanso" };
  return { cuenta: true, etiqueta: "Sigue sin marca" };
}

/** La hora que se esperaba, tal como se midió. `—` si la jornada es anterior a
 *  la 0446 o no hubo jornada. */
export function horaEsperada(dia: DiaAsistencia | undefined): string {
  const e = dia?.horario_aplicado?.entrada;
  return e ? e.slice(0, 5) : "—";
}

// ── Antecedentes ─────────────────────────────────────────────────────────────

const DOCE_MESES_MS = 365 * 24 * 60 * 60 * 1000;

/**
 * Los documentos entregados de la misma causal en los doce meses previos a
 * `referencia` (un instante ISO). Solo los ENTREGADOS: el numeral 56.2 dice que
 * un documento firmado y no entregado no agrava ni es antecedente.
 *
 * Es para MOSTRAR. Qué escalón toca lo calcula la base, que además mira el
 * corte de lo ya sancionado; esto solo deja leer de dónde sale.
 */
export function antecedentesVigentes(
  docs: readonly DocDisciplina[], personaId: string, causal: string, referencia: string, excluirId?: string,
): DocDisciplina[] {
  const ref = Date.parse(referencia);
  return docs
    .filter((x) => x.persona_id === personaId && x.tipo_causal === causal && x.estado === "entregado"
      && x.id !== excluirId && x.entregado_at !== null
      && Date.parse(x.entregado_at) <= ref && Date.parse(x.entregado_at) >= ref - DOCE_MESES_MS)
    .sort((a, b) => Date.parse(b.entregado_at!) - Date.parse(a.entregado_at!));
}

// ── Historial: lo que hoy se guarda como texto en `observacion` ──────────────

export interface EventoObservacion {
  tipo: "anulado" | "reabierto" | "cerrado_sin_entrega" | "nota";
  /** `YYYY-MM-DD` tal como lo escribe la base, o null en una nota suelta. */
  fecha: string | null;
  texto: string;
}

const MARCAS: Record<string, EventoObservacion["tipo"]> = {
  "ANULADO": "anulado",
  "REABIERTO": "reabierto",
  "CERRADO SIN ENTREGA": "cerrado_sin_entrega",
};

/**
 * Separa lo que las funciones de la base agregan a `observacion` entre
 * corchetes —`[ANULADO 2026-07-30: motivo]`, `[REABIERTO …]`, `[CERRADO SIN
 * ENTREGA …]` (migs. 0058, 0131, 0412)— del resto del texto.
 *
 * Existe porque el expediente todavía no tiene una tabla de eventos (es el
 * lote 2 del rediseño) y ese texto es hoy el único rastro de esos actos. Lo
 * que no calza con ninguna marca se devuelve como nota, nunca se descarta.
 */
export function eventosDeObservacion(observacion: string | null): EventoObservacion[] {
  if (!observacion?.trim()) return [];
  const eventos: EventoObservacion[] = [];
  const patron = /\[(ANULADO|REABIERTO|CERRADO SIN ENTREGA)\s+(\d{4}-\d{2}-\d{2}):\s*([^\]]*)\]/g;
  const resto = observacion.replace(patron, (_, marca: string, fecha: string, texto: string) => {
    eventos.push({ tipo: MARCAS[marca], fecha, texto: texto.trim() });
    return "\n";
  });
  const nota = resto.split("\n").map((l) => l.trim()).filter(Boolean).join("\n");
  if (nota) eventos.unshift({ tipo: "nota", fecha: null, texto: nota });
  return eventos;
}

// ── Persona cesada ───────────────────────────────────────────────────────────

/**
 * Si todavía tiene sentido registrar una entrega de un documento firmado de
 * alguien que ya cesó: solo si pudo entregársele ANTES del cese, o sea si la
 * firma es del día del cese o anterior. Decisión del 2026-09-15.
 *
 * Hoy la base no lo exige (`fn_expediente_entregar` no mira a la persona; el
 * freno es el lote 3), así que esto es el letrero, no el candado.
 */
export function admiteEntregaAnteriorAlCese(d: DocDisciplina, fechaCese: string | null): boolean {
  if (d.estado !== "firmado" || !fechaCese || !d.firmado_at) return false;
  return fechaLima(d.firmado_at) <= fechaCese;
}

/** El último día que se puede declarar como entrega para una persona cesada. */
export function ultimoDiaDeEntrega(fechaCese: string): string {
  const hoy = hoyLima();
  return fechaCese < hoy ? fechaCese : hoy;
}

// ── Búsqueda ─────────────────────────────────────────────────────────────────

/** Para buscar «Quispe» escribiendo «quispe» y «Ramírez» escribiendo «ramirez». */
export function normalizarBusqueda(texto: string): string {
  return texto.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase().trim();
}
