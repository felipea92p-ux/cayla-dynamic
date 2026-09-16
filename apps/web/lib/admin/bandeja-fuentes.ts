import type { ClienteCayla } from "@cayla-dynamic/database";
import {
  fechaLima, hoyLima, NIVEL_DISCIPLINARIO_LABELS, puedeGestionarCatalogos, puedeGestionarContratos,
  puedeOperarEquipo, puedeVerPlanilla, puedeVerSaludDeAlertas,
} from "@cayla-dynamic/shared";
import { diaYMes } from "../bandeja-mia";
import { formatSoles } from "../rangos";
import {
  etapaDelBorrador, pendientesDeEntregado, type Adjunto, type DocDisciplina,
} from "./disciplina";
import {
  compararPendientes, conCese, documentoEducacion, ESTADOS_CONTRATO_PENDIENTE, esFeriadoParaBandeja, sumarDias,
  urgenciaBono, urgenciaContrato, urgenciaDescargo, urgenciaDiaPorRevisar, urgenciaEducacion, urgenciaEspera,
  urgenciaFeriado, urgenciaInicio, urgenciaLiquidacionVencida, urgenciaRecordVacaciones, urgenciaSinHorario,
  type FilaContrato, type FilaFeriado, type PeriodoDePago, type Urgencia,
} from "./bandeja-urgencia";

/**
 * DE DÓNDE SALE CADA PENDIENTE DE LA BANDEJA — una sola vez para todo el panel.
 *
 * QUÉ PROMETE. `traerFuentesBandeja` pide, según el permiso de quien mira, las
 * mismas RPC que ya usa cada módulo; `armarPendientes` las convierte en UNA
 * lista con la forma que se pinta. La pantalla (`/admin/bandeja`), el número
 * del menú (`contarBandejaEquipoPendiente`) y el de cada persona en Equipo
 * (`listarPendientesPorPersona`) leen de aquí.
 *
 * POR QUÉ EXISTE (2026-09-15). Eran TRES copias de la misma lista de RPC y se
 * separaron dos veces en una semana: el menú nunca sumó las liquidaciones
 * vencidas, y Equipo siguió contando Educación con la consulta anterior a la
 * 0450. Con una sola lista, una fuente nueva entra a los tres lugares o a ninguno.
 *
 * QUÉ NO HACE. No inventa qué es un pendiente: cada fuente usa el criterio de
 * SU pantalla (Contratos, Correcciones, Documentación, Feriados, Disciplina…).
 * Donde esa pantalla se contradice o traería casos que no piden nada, está
 * escrito junto a la función de urgencia en `bandeja-urgencia.ts`.
 *
 * QUÉ ASUME. La base decide quién ve qué (RLS y guards). Los `puede*` de acá
 * solo evitan pedir lo que igual volvería vacío — y deciden qué categorías se
 * muestran, para no pintar «Al día» un módulo que esta persona no puede ver.
 */

// ── Módulos ─────────────────────────────────────────────────────────────────

/** De qué módulo viene cada pendiente. */
export type ModuloBandeja =
  | "contratos" | "correcciones" | "disciplina" | "documentacion" | "feriados"
  | "educacion" | "ausencias" | "horarios" | "datos_personales" | "liquidaciones";

/**
 * Los módulos que la Bandeja revisa, en el orden de sus tarjetas, y quién puede
 * ver cada uno. El permiso es el MISMO que usa la pantalla de ese módulo.
 */
export const MODULOS_BANDEJA: readonly { clave: ModuloBandeja; etiqueta: string; puedeVer: (rol: string | null | undefined) => boolean }[] = [
  { clave: "contratos", etiqueta: "Contratos", puedeVer: puedeGestionarContratos },
  { clave: "correcciones", etiqueta: "Correcciones", puedeVer: puedeOperarEquipo },
  { clave: "disciplina", etiqueta: "Disciplina", puedeVer: puedeOperarEquipo },
  { clave: "documentacion", etiqueta: "Documentación", puedeVer: puedeGestionarCatalogos },
  { clave: "feriados", etiqueta: "Feriados", puedeVer: puedeGestionarCatalogos },
  { clave: "educacion", etiqueta: "Educación", puedeVer: puedeVerPlanilla },
  { clave: "ausencias", etiqueta: "Ausencias", puedeVer: puedeOperarEquipo },
  { clave: "horarios", etiqueta: "Horarios", puedeVer: puedeOperarEquipo },
  { clave: "datos_personales", etiqueta: "Datos personales", puedeVer: puedeOperarEquipo },
  { clave: "liquidaciones", etiqueta: "Liquidaciones", puedeVer: puedeVerPlanilla },
];

export const ETIQUETA_MODULO = Object.fromEntries(MODULOS_BANDEJA.map((m) => [m.clave, m.etiqueta])) as Record<ModuloBandeja, string>;

export function modulosDeLaBandeja(rol: string | null | undefined): ModuloBandeja[] {
  return MODULOS_BANDEJA.filter((m) => m.puedeVer(rol)).map((m) => m.clave);
}

// ── Lo que devuelve cada fuente ─────────────────────────────────────────────

/** Un estudio tal como lo trae `fn_educacion_situacion` (0450), con lo que la Bandeja necesita. */
export interface FilaEducacionBandeja {
  familia_id: string;
  persona_id: string;
  persona: string;
  sede: string;
  institucion: string;
  vigencia: string;
  estado_constancia: string;
  fecha_pago_constancia: string | null;
  plazo: string | null;
  pago_proximo: boolean;
  proxima_fecha_pago: string | null;
  dias_para_pago: number | null;
}

/**
 * ¿Este estudio entra a la Bandeja? Constancia vencida, estudio vigente sin
 * calendario —el criterio de `fn_educacion_por_atender`— más los pagos a la
 * institución de los próximos días (ADR 0003, decisión 8).
 */
export function esEducacionParaSaber(f: FilaEducacionBandeja): boolean {
  return f.estado_constancia === "vencida"
    || (f.estado_constancia === "sin_calendario" && (f.vigencia === "vigente" || f.vigencia === "por_terminar"))
    || f.pago_proximo;
}

/** Una constancia de estudios esperando revisión (0450). UNA entrega = UN pendiente. */
export interface ItemEntregaEducacion {
  id: string; familia_id: string; persona_id: string; persona: string; sede: string;
  institucion: string; fecha_pago: string; enviada_at: string; archivos: number; es_reenvio: boolean;
}

/** Una integrante avisó que ya no va a pagar su estudio (0450). */
export interface ItemAvisoFinEducacion {
  id: string; familia_id: string; persona_id: string; persona: string; sede: string;
  institucion: string; motivo: string; creado_at: string;
}

/** Alguien pidió su propio apoyo educativo, sin tener todavía una asignación (0461). */
export interface ItemSolicitudEducacion {
  id: string; persona_id: string; persona: string; sede: string;
  institucion: string; costo_declarado: number; enviada_at: string;
}

/** Alguien que trabajó días que su horario no cubre (0385). */
export interface ItemSinHorario {
  persona_id: string; nombre: string; sede: string;
  dias: number; primer_dia: string; ultimo_dia: string;
  nunca_tuvo_horario: boolean;
}

export interface ItemVacacion {
  persona_id: string; persona: string; sede: string;
  records_vencidos: number; vence_el: string; dias_para_vencer: number;
}

/** Una fila de `fn_liquidaciones_pendientes` (0454), con lo que la Bandeja mira. */
export interface ItemLiquidacion {
  persona_id: string; persona: string; sede: string;
  fecha_cese: string; vence_el: string; dias_restantes: number; total: number;
  pagada: boolean; vencido: boolean;
}

/** Solo la liquidación vencida con dinero real en juego cruza a la Bandeja (decidido con Felipe, 2026-09-15). */
export function esLiquidacionParaBandeja(l: ItemLiquidacion): boolean {
  return !l.pagada && l.vencido && l.total > 0;
}

export interface ItemRevision {
  id: string; persona_id: string; nombre: string; sede: string;
  fecha: string; comentario: string; pedida_at: string;
}

/** Un pedido de revisión de una declaración de ruta (0425). `sede` puede venir null (left join). */
export interface ItemRevisionMovilidad {
  id: string; persona_id: string; nombre: string; sede: string | null;
  motivo: string; pedida_at: string;
}

/** Un pedido de revisión de un contrato ya generado (0427). */
export interface ItemRevisionContrato {
  id: string; persona_id: string; nombre: string; sede: string | null;
  motivo: string; pedida_at: string;
}

export interface ItemSolicitudVacacion {
  id: string; persona_id: string; nombre: string; sede: string;
  fecha_inicio: string; fecha_fin: string; dias: number;
  comentario: string | null; pedida_at: string;
}

/** Una propuesta de cambio de perfil por resolver (0399). */
export interface ItemSolicitudPerfil {
  id: string; persona_id: string; nombre: string; sede: string;
  campo: string; etiqueta: string;
  valor_anterior: Record<string, unknown>;
  valor_propuesto: Record<string, unknown>;
  rutas_adjuntas: string[];
  creada_at: string;
  /** Solo lo aprueba DO aunque la encargada lo vea (0405). */
  solo_do: boolean;
}

/** Una fila de `fn_contratos_tablero` (0386). Sale una por persona activa: solo entran las que piden algo. */
export interface ItemContrato extends FilaContrato {
  persona_id: string; persona: string; sede: string | null; tipo: string | null;
}

/** Un día con marcas por revisar (`fn_dias_por_revisar`, 0422). */
export interface ItemDiaPorRevisar {
  persona_id: string; nombre: string; sede: string; fecha: string;
  marcas: number; periodo_pagado: boolean; motivo: string | null;
}

/** Una marca que el terminal no pudo registrar y quedó apartada (`fn_marcas_apartadas`, 0422). */
export interface ItemMarcaApartada {
  id: string; persona_id: string; persona: string; sede: string; tipo: string;
  timestamp_cliente: string; fecha: string; ultimo_error: string | null; reportada_at: string;
}

/** Una fila de `fn_documentos_tablero` (0424), con lo que la Bandeja mira. */
export interface ItemDocumento {
  persona_id: string; persona: string; sede: string;
  estado: string; ruta_desfasada: boolean; bono_estado: string;
}

/** Qué pide una fila de Documentación: la ruta sin firmar o desfasada, y el bono del mes o ya pasado. */
export function pendientesDeDocumento(d: ItemDocumento): { ruta: "sin_ruta" | "desfasada" | null; bono: boolean } {
  return {
    ruta: d.estado === "sin_ruta" ? "sin_ruta" : d.estado === "ok" && d.ruta_desfasada ? "desfasada" : null,
    // `sin_fecha` no: la propia pantalla de Documentación lo deja en «nada que hacer» (BONO_PENDIENTE).
    bono: d.bono_estado === "este_mes" || d.bono_estado === "vencido",
  };
}

/** Un feriado trabajado (`fn_feriados_laborados`, 0419). */
export interface ItemFeriado extends FilaFeriado {
  persona_id: string; nombre: string; sede: string; feriado_nombre: string; fecha_descanso: string | null;
}

/** Qué le toca a un documento disciplinario, con la regla de `lib/admin/disciplina.ts`. */
export type PasoDisciplina = "comunicar" | "esperando" | "valorar" | "firmar" | "entregar" | "cargo" | "resolver" | "cargo_y_resolver";

export interface ItemDisciplina {
  id: string; persona_id: string; persona: string; sede: string; nivel: string;
  creado_at: string; firmado_at: string | null; entregado_at: string | null; descargo_vence_at: string | null;
  paso: PasoDisciplina;
}

/**
 * El paso que le toca a un documento disciplinario, o null si no pide nada.
 * No es una regla nueva: son `etapaDelBorrador` y `pendientesDeEntregado`, las
 * mismas que ordenan las pestañas de la pantalla de Disciplina.
 */
export function pasoDisciplina(d: DocDisciplina, adjuntos: readonly Adjunto[], exigeDescargo: boolean, ahora: Date = new Date()): PasoDisciplina | null {
  if (d.estado === "borrador") return etapaDelBorrador(d, exigeDescargo, ahora);
  if (d.estado === "firmado") return "entregar";
  if (d.estado === "entregado") {
    const p = pendientesDeEntregado(d, adjuntos);
    if (p.includes("cargo") && p.includes("resolver")) return "cargo_y_resolver";
    return p[0] ?? null;
  }
  return null;
}

/** Lo que devuelve `fn_alertas_despacho_resumen` (0362): lo que el despacho de correos NO va a resolver solo. */
export interface ResumenAlertas {
  despachables: number;
  atascadas: number;
  fallidas_definitivas: number;
  caducadas: number;
  ultimo_envio_at: string | null;
  motivos_definitivos: string[];
}

export interface FuentesBandeja {
  educacion: FilaEducacionBandeja[];
  entregasEducacion: ItemEntregaEducacion[];
  avisosFinEducacion: ItemAvisoFinEducacion[];
  solicitudesEducacion: ItemSolicitudEducacion[];
  vacaciones: ItemVacacion[];
  sinHorario: ItemSinHorario[];
  liquidacionesVencidas: ItemLiquidacion[];
  revisiones: ItemRevision[];
  revisionesMovilidad: ItemRevisionMovilidad[];
  revisionesContrato: ItemRevisionContrato[];
  solicitudesVacaciones: ItemSolicitudVacacion[];
  solicitudesPerfil: ItemSolicitudPerfil[];
  contratos: ItemContrato[];
  diasPorRevisar: ItemDiaPorRevisar[];
  marcasApartadas: ItemMarcaApartada[];
  /** El periodo de pago abierto hoy, para medir los días por revisar contra su cierre. */
  periodo: PeriodoDePago | null;
  documentos: ItemDocumento[];
  feriados: ItemFeriado[];
  disciplina: ItemDisciplina[];
  resumenAlertas: ResumenAlertas | null;
  /**
   * Módulos con al menos una consulta que falló. La pantalla NO los pinta
   * «Al día»: una lista vacía por un error dice «no hay nada», que es una
   * afirmación y no un hueco.
   */
  fallidas: ModuloBandeja[];
}

export const FUENTES_VACIAS: FuentesBandeja = {
  educacion: [], entregasEducacion: [], avisosFinEducacion: [], solicitudesEducacion: [], vacaciones: [], sinHorario: [],
  liquidacionesVencidas: [], revisiones: [], revisionesMovilidad: [], revisionesContrato: [],
  solicitudesVacaciones: [], solicitudesPerfil: [], contratos: [], diasPorRevisar: [], marcasApartadas: [],
  periodo: null, documentos: [], feriados: [], disciplina: [], resumenAlertas: null, fallidas: [],
};

/** Cuántos avisos por correo necesitan a una persona. Lo que se reintenta solo no cuenta. */
export function alertasConProblema(r: ResumenAlertas | null): number {
  return r ? r.atascadas + r.fallidas_definitivas + r.caducadas : 0;
}

// ── Cargar ──────────────────────────────────────────────────────────────────

/**
 * Hasta cuántos días por revisar se piden. `fn_dias_por_revisar` corta en su
 * límite ANTES de devolver (0422), y la pantalla de Correcciones pide 50: con
 * ese tope, la Bandeja contaría de menos justo en un mes malo.
 */
const LIMITE_DIAS_POR_REVISAR = 1000;

/** Hacia atrás cuánto se buscan feriados trabajados: el plazo del descanso (30 días) con margen para lo que ya se pasó. */
const DIAS_ATRAS_FERIADOS = 120;

/**
 * Pide todas las fuentes que este rol puede ver, en paralelo.
 *
 * Falla por sección, nunca entera: una consulta que falla deja su lista vacía,
 * anota el módulo en `fallidas` y avisa por `alFallar` (la pantalla lo muestra;
 * el menú lo calla, como el resto de sus contadores). Sin horario y la salud de
 * los correos siguen fallando en silencio incluso para la pantalla, como ya hacían.
 */
export async function traerFuentesBandeja(
  supabase: ClienteCayla,
  rol: string | null | undefined,
  alFallar: (que: string, error: unknown) => void = () => {},
  hoy: string = hoyLima(),
): Promise<FuentesBandeja> {
  const f: FuentesBandeja = { ...FUENTES_VACIAS, fallidas: [] };
  const tareas: PromiseLike<void>[] = [];
  const fallo = (modulo: ModuloBandeja, que: string, error: unknown, callado = false) => {
    if (!f.fallidas.includes(modulo)) f.fallidas.push(modulo);
    if (!callado) alFallar(que, error);
  };
  const pedir = <T,>(
    llamada: PromiseLike<{ data: unknown; error: unknown }>, modulo: ModuloBandeja, que: string,
    guardar: (xs: T[]) => void, callado = false,
  ) => {
    tareas.push(llamada.then(({ data, error }) => {
      if (error) { fallo(modulo, que, error, callado); return; }
      guardar(Array.isArray(data) ? (data as T[]) : []);
    }));
  };

  if (puedeVerPlanilla(rol)) {
    pedir<ItemEntregaEducacion>(supabase.rpc("fn_educacion_entregas_pendientes"), "educacion", "las constancias de educación", (xs) => { f.entregasEducacion = xs; });
    pedir<ItemAvisoFinEducacion>(supabase.rpc("fn_educacion_avisos_fin_pendientes"), "educacion", "los avisos de educación", (xs) => { f.avisosFinEducacion = xs; });
    pedir<ItemSolicitudEducacion>(supabase.rpc("fn_educacion_solicitudes_pendientes"), "educacion", "las solicitudes de apoyo educativo", (xs) => { f.solicitudesEducacion = xs; });
    pedir<FilaEducacionBandeja>(supabase.rpc("fn_educacion_situacion"), "educacion", "educación", (xs) => { f.educacion = xs.filter(esEducacionParaSaber); });
    pedir<ItemSolicitudVacacion>(supabase.rpc("fn_solicitudes_vacaciones", { p_solo_pendientes: true }), "ausencias", "solicitudes de vacaciones", (xs) => { f.solicitudesVacaciones = xs; });
    pedir<ItemLiquidacion>(supabase.rpc("fn_liquidaciones_pendientes"), "liquidaciones", "liquidaciones vencidas", (xs) => { f.liquidacionesVencidas = xs.filter(esLiquidacionParaBandeja); });
  }

  if (puedeOperarEquipo(rol)) {
    pedir<ItemVacacion>(supabase.rpc("fn_vacaciones_por_vencer", { p_dias: 60, p_as_of: null }), "ausencias", "vacaciones por vencer", (xs) => { f.vacaciones = xs; });
    pedir<ItemSinHorario>(supabase.rpc("fn_personas_sin_horario_vigente", { p_dias: 60 }), "horarios", "personas sin horario", (xs) => { f.sinHorario = xs; }, true);
    pedir<ItemRevision>(supabase.rpc("fn_revisiones_pedidas", { p_solo_pendientes: true }), "correcciones", "revisiones pedidas", (xs) => { f.revisiones = xs; });
    pedir<ItemSolicitudPerfil>(supabase.rpc("fn_solicitudes_perfil_pendientes"), "datos_personales", "solicitudes de perfil", (xs) => { f.solicitudesPerfil = xs; });
    pedir<ItemDiaPorRevisar>(supabase.rpc("fn_dias_por_revisar", { p_limite: LIMITE_DIAS_POR_REVISAR }), "correcciones", "días por revisar", (xs) => { f.diasPorRevisar = xs; });
    pedir<ItemMarcaApartada>(supabase.rpc("fn_marcas_apartadas"), "correcciones", "marcas apartadas", (xs) => { f.marcasApartadas = xs; });
    // El periodo que se va a pagar. LEÍDO, nunca calculado: va del 29 al 28 y
    // eso vive en la tabla. Sin él, los días por revisar quedan «Sin plazo».
    tareas.push(
      supabase.from("periodos_planilla").select("fecha_ini, fecha_fin")
        .lte("fecha_ini", hoy).gte("fecha_fin", hoy).maybeSingle()
        .then(({ data }) => { f.periodo = (data as PeriodoDePago | null) ?? null; }),
    );
    tareas.push(traerDisciplina(supabase, fallo).then((xs) => { f.disciplina = xs; }));
  }

  if (puedeGestionarCatalogos(rol)) {
    pedir<ItemRevisionMovilidad>(supabase.rpc("fn_movilidad_revisiones_pedidas", { p_solo_pendientes: true }), "documentacion", "revisiones de movilidad pedidas", (xs) => { f.revisionesMovilidad = xs; });
    pedir<ItemDocumento>(supabase.rpc("fn_documentos_tablero"), "documentacion", "la documentación", (xs) => {
      f.documentos = xs.filter((d) => { const p = pendientesDeDocumento(d); return p.ruta !== null || p.bono; });
    });
    pedir<ItemFeriado>(
      supabase.rpc("fn_feriados_laborados", { p_desde: sumarDias(hoy, -DIAS_ATRAS_FERIADOS), p_hasta: hoy }),
      "feriados", "los feriados trabajados", (xs) => { f.feriados = xs.filter(esFeriadoParaBandeja); },
    );
  }

  if (puedeGestionarContratos(rol)) {
    pedir<ItemRevisionContrato>(supabase.rpc("fn_contrato_revisiones_pedidas", { p_solo_pendientes: true }), "contratos", "revisiones de contrato pedidas", (xs) => { f.revisionesContrato = xs; });
    pedir<ItemContrato>(supabase.rpc("fn_contratos_tablero"), "contratos", "los contratos", (xs) => {
      f.contratos = xs.filter((c) => ESTADOS_CONTRATO_PENDIENTE.has(c.estado));
    });
  }

  if (puedeVerSaludDeAlertas(rol)) {
    tareas.push(supabase.rpc("fn_alertas_despacho_resumen").then(({ data, error }) => {
      f.resumenAlertas = error || !data ? null : (data as unknown as ResumenAlertas);
    }));
  }

  await Promise.all(tareas);
  return f;
}

/**
 * Los documentos disciplinarios que piden algo. No hay RPC que los liste con
 * su sede: la pantalla de Disciplina lee la tabla y cruza la sede por su lado,
 * y esto hace lo mismo. La RLS de la tabla ya le da a la encargada solo su sede.
 */
async function traerDisciplina(
  supabase: ClienteCayla,
  fallo: (modulo: ModuloBandeja, que: string, error: unknown) => void,
): Promise<ItemDisciplina[]> {
  const [docs, cfg] = await Promise.all([
    supabase.from("expediente_disciplinario")
      .select("id, persona_id, nivel, estado, creado_at, firmado_at, entregado_at, cargos_comunicados_at, descargo_vence_at, descargo_acogido, resuelto_at")
      .in("estado", ["borrador", "firmado", "entregado"]),
    supabase.from("configuracion").select("valor").eq("clave", "disciplina_descargo_previo").maybeSingle(),
  ]);
  if (docs.error) { fallo("disciplina", "los documentos disciplinarios", docs.error); return []; }
  const filas = (docs.data ?? []) as unknown as DocDisciplina[];
  if (filas.length === 0) return [];
  // Mismo criterio que la pantalla: solo un `false` explícito apaga el descargo previo.
  const exigeDescargo = (cfg.data?.valor as unknown) !== false;

  const entregados = filas.filter((d) => d.estado === "entregado").map((d) => d.id);
  const personaIds = Array.from(new Set(filas.map((d) => d.persona_id)));
  const [adj, per, sed] = await Promise.all([
    entregados.length > 0
      ? supabase.from("expediente_adjuntos").select("documento_id, tipo").in("documento_id", entregados)
      : Promise.resolve({ data: [], error: null }),
    supabase.from("personas").select("id, nombres, apellidos, sede_base_id").in("id", personaIds),
    supabase.from("sedes").select("id, codigo"),
  ]);
  if (adj.error || per.error) { fallo("disciplina", "los documentos disciplinarios", adj.error ?? per.error); return []; }

  const adjuntosDe = new Map<string, Adjunto[]>();
  for (const a of (adj.data ?? []) as unknown as Adjunto[]) {
    adjuntosDe.set(a.documento_id, [...(adjuntosDe.get(a.documento_id) ?? []), a]);
  }
  const codigoSede = new Map(((sed.data ?? []) as { id: string; codigo: string }[]).map((s) => [s.id, s.codigo] as const));
  const personas = new Map(((per.data ?? []) as { id: string; nombres: string; apellidos: string; sede_base_id: string | null }[])
    .map((p) => [p.id, { nombre: `${p.nombres} ${p.apellidos}`, sede: (p.sede_base_id && codigoSede.get(p.sede_base_id)) || "—" }] as const));

  const ahora = new Date();
  const items: ItemDisciplina[] = [];
  for (const d of filas) {
    const paso = pasoDisciplina(d, adjuntosDe.get(d.id) ?? [], exigeDescargo, ahora);
    const p = personas.get(d.persona_id);
    if (!paso || !p) continue;
    items.push({
      id: d.id, persona_id: d.persona_id, persona: p.nombre, sede: p.sede, nivel: d.nivel,
      creado_at: d.creado_at, firmado_at: d.firmado_at, entregado_at: d.entregado_at, descargo_vence_at: d.descargo_vence_at,
      paso,
    });
  }
  return items;
}

// ── Armar ───────────────────────────────────────────────────────────────────

/** Los tipos que llevan «Nuevo desde tu última visita» (bandeja_vistos, 0436/0450). */
export type TipoItemVisto =
  | "revision" | "revision_movilidad" | "revision_contrato"
  | "solicitud_vacacion" | "solicitud_perfil"
  | "entrega_educacion" | "aviso_fin_educacion" | "solicitud_educacion";

export type TipoPendiente =
  | TipoItemVisto | "educacion" | "vacaciones_por_vencer" | "sin_horario" | "liquidacion_vencida"
  | "contrato" | "dia_por_revisar" | "marca_apartada" | "documento_ruta" | "documento_bono" | "feriado" | "disciplina";

/**
 * Un pendiente, sea del tipo que sea. Quién, qué, dónde, de qué módulo, cuándo
 * y qué hacer ahora: las seis preguntas de una fila de la Bandeja.
 */
export interface Pendiente {
  clave: string;
  tipo: TipoPendiente;
  itemId: string;
  personaId: string | null;
  persona: string;
  sede: string;
  modulo: ModuloBandeja;
  titulo: string;
  detalle: string | null;
  urgencia: Urgencia;
  /** «aqui» se resuelve desplegando la fila; «afuera» lleva a su módulo. */
  resolucion: "aqui" | "afuera";
  /** Para «afuera»: el verbo y a dónde. */
  ir: { texto: string; href: string } | null;
  /** Para «aqui»: un enlace de contexto dentro del desplegable. */
  contexto: { texto: string; href: string } | null;
  nuevo: boolean;
  /** Fecha de cese ya cumplida, o null. */
  cesoEl: string | null;
}

/** «celular: 987654321 · direccion: Av. Uno 123». Una ruta de archivo se anuncia como imagen (0401). */
export function resumenValorPerfil(v: Record<string, unknown>): string {
  const entradas = Object.entries(v).filter(([, val]) => val !== null && val !== undefined && val !== "");
  if (entradas.length === 0) return "—";
  return entradas.map(([k, val]) => {
    if (typeof val === "string" && val.startsWith("solicitud/")) {
      return `${k.replace(/^foto_dni_|_ruta$/g, "")}: imagen adjunta`;
    }
    return `${k}: ${typeof val === "boolean" ? (val ? "Sí" : "No") : String(val)}`;
  }).join(" · ");
}

/** Un timestamptz → «3 de setiembre», en el día de Lima. */
export function diaLima(ts: string): string {
  return diaYMes(fechaLima(ts));
}

function rangoVacaciones(s: ItemSolicitudVacacion): string {
  const rango = s.fecha_inicio === s.fecha_fin
    ? `el ${diaYMes(s.fecha_inicio)}`
    : `del ${diaYMes(s.fecha_inicio)} al ${diaYMes(s.fecha_fin)}`;
  return `Vacaciones ${rango} · ${s.dias} día${s.dias === 1 ? "" : "s"}`;
}

function textoContrato(c: ItemContrato): { titulo: string; detalle: string | null; accion: string } {
  switch (c.estado) {
    case "desnaturalizado": return { titulo: "Marcó después del fin de su contrato", detalle: "Riesgo de desnaturalización (art. 77): puede considerarse indefinido", accion: "Ver contrato" };
    case "vencido": return { titulo: "Contrato vencido", detalle: null, accion: "Renovar contrato" };
    case "por_vencer": return { titulo: "Contrato por vencer", detalle: null, accion: "Preparar renovación" };
    case "sin_firmar": return { titulo: "Contrato pendiente de firma", detalle: null, accion: "Registrar firma" };
    case "tramite_pendiente":
      // Desde la 0470 este estado solo significa "falta la copia": comunicar
      // el contrato al MTPE ya no es trámite de nadie (D. Leg. 1246).
      return { titulo: "Falta entregar la copia del contrato", detalle: null, accion: "Registrar entrega" };
    default: return { titulo: "Sin contrato registrado", detalle: null, accion: "Registrar contrato" };
  }
}

/** Por qué Correcciones apartó un día (`motivo` de `fn_dias_por_revisar`, 0384). */
const MOTIVO_DIA: Record<string, string> = {
  secuencia_imposible: "Marcas en un orden imposible",
  auto_cierre_sin_confirmar: "Cierre automático sin confirmar",
  sello_sin_levantar: "Día marcado para revisar",
};

function textoDisciplina(d: ItemDisciplina, hoy: string): { titulo: string; accion: string; urgencia: Urgencia; href: string } {
  const nivel = (NIVEL_DISCIPLINARIO_LABELS as Record<string, string>)[d.nivel] ?? d.nivel;
  const entregar = "/admin/disciplina#entregados";
  switch (d.paso) {
    case "comunicar": return { titulo: `${nivel}: falta comunicar los cargos`, accion: "Comunicar cargos", urgencia: urgenciaEspera(d.creado_at, hoy), href: "/admin/disciplina" };
    case "esperando": return { titulo: `${nivel}: esperando el descargo`, accion: "Ver expediente", urgencia: d.descargo_vence_at ? urgenciaDescargo(d.descargo_vence_at, hoy) : urgenciaEspera(d.creado_at, hoy), href: "/admin/disciplina" };
    case "valorar": return { titulo: `${nivel}: descargo por valorar`, accion: "Valorar descargo", urgencia: urgenciaEspera(d.descargo_vence_at ?? d.creado_at, hoy), href: "/admin/disciplina" };
    case "firmar": return { titulo: `${nivel} lista para firmar`, accion: "Firmar", urgencia: urgenciaEspera(d.creado_at, hoy), href: "/admin/disciplina" };
    case "entregar": return { titulo: `${nivel} firmada, sin entregar`, accion: "Registrar entrega", urgencia: urgenciaEspera(d.firmado_at ?? d.creado_at, hoy), href: entregar };
    case "cargo": return { titulo: `${nivel} entregada, sin cargo firmado`, accion: "Subir cargo", urgencia: urgenciaEspera(d.entregado_at ?? d.creado_at, hoy), href: entregar };
    case "resolver": return { titulo: `${nivel}: falta resolver`, accion: "Resolver", urgencia: urgenciaEspera(d.entregado_at ?? d.creado_at, hoy), href: entregar };
    default: return { titulo: `${nivel}: falta el cargo y resolver`, accion: "Completar", urgencia: urgenciaEspera(d.entregado_at ?? d.creado_at, hoy), href: entregar };
  }
}

/**
 * Todas las fuentes en una lista, ordenada por urgencia.
 *
 * `ceses` y `vistos` son opcionales porque el contador no los necesita: quién
 * cesó cambia el GRUPO de un pendiente, no si cuenta; y «Nuevo» no cambia nada
 * del número.
 */
export function armarPendientes(
  f: FuentesBandeja,
  { hoy = hoyLima(), ceses = new Map<string, string>(), vistos = new Set<string>() }:
    { hoy?: string; ceses?: Map<string, string>; vistos?: Set<string> } = {},
): Pendiente[] {
  const lista: Pendiente[] = [];
  const agregar = (p: Omit<Pendiente, "cesoEl" | "nuevo">, visto?: TipoItemVisto) => {
    const cese = p.personaId ? ceses.get(p.personaId) : undefined;
    const cesoEl = cese && cese <= hoy ? cese : null;
    lista.push({
      ...p,
      cesoEl,
      urgencia: cesoEl ? conCese(p.urgencia) : p.urgencia,
      nuevo: visto ? !vistos.has(`${visto}:${p.itemId}`) : false,
    });
  };

  for (const r of f.revisiones) {
    agregar({
      clave: `revision:${r.id}`, tipo: "revision", itemId: r.id, personaId: r.persona_id,
      persona: r.nombre, sede: r.sede, modulo: "correcciones",
      titulo: `Pidió revisar su ${diaYMes(r.fecha)}`, detalle: `«${r.comentario}»`,
      urgencia: urgenciaEspera(r.pedida_at, hoy), resolucion: "aqui", ir: null,
      contexto: { texto: "Abrir ese día en Correcciones", href: `/admin/correcciones?persona=${r.persona_id}&fecha=${r.fecha}` },
    }, "revision");
  }
  for (const r of f.revisionesMovilidad) {
    agregar({
      clave: `revision_movilidad:${r.id}`, tipo: "revision_movilidad", itemId: r.id, personaId: r.persona_id,
      persona: r.nombre, sede: r.sede ?? "—", modulo: "documentacion",
      titulo: "Pidió revisar su declaración de ruta", detalle: `«${r.motivo}»`,
      urgencia: urgenciaEspera(r.pedida_at, hoy), resolucion: "aqui", ir: null,
      contexto: { texto: "Abrir su ruta en Documentación", href: `/admin/documentacion?persona=${r.persona_id}` },
    }, "revision_movilidad");
  }
  for (const r of f.revisionesContrato) {
    agregar({
      clave: `revision_contrato:${r.id}`, tipo: "revision_contrato", itemId: r.id, personaId: r.persona_id,
      persona: r.nombre, sede: r.sede ?? "—", modulo: "contratos",
      titulo: "Pidió revisar su contrato", detalle: `«${r.motivo}»`,
      urgencia: urgenciaEspera(r.pedida_at, hoy), resolucion: "aqui", ir: null,
      contexto: { texto: "Abrir su contrato en Contratos", href: `/admin/contratos?persona=${r.persona_id}` },
    }, "revision_contrato");
  }
  for (const s of f.solicitudesVacaciones) {
    agregar({
      clave: `solicitud_vacacion:${s.id}`, tipo: "solicitud_vacacion", itemId: s.id, personaId: s.persona_id,
      persona: s.nombre, sede: s.sede, modulo: "ausencias",
      titulo: rangoVacaciones(s),
      detalle: s.comentario ? `«${s.comentario}» · pedidas el ${diaLima(s.pedida_at)}` : `Pedidas el ${diaLima(s.pedida_at)}`,
      urgencia: urgenciaInicio(s.fecha_inicio, hoy), resolucion: "aqui", ir: null, contexto: null,
    }, "solicitud_vacacion");
  }
  for (const s of f.solicitudesPerfil) {
    const n = s.rutas_adjuntas.length;
    agregar({
      clave: `solicitud_perfil:${s.id}`, tipo: "solicitud_perfil", itemId: s.id, personaId: s.persona_id,
      persona: s.nombre, sede: s.sede, modulo: "datos_personales",
      titulo: `Cambio de ${s.etiqueta.toLowerCase()}`,
      detalle: n > 0 ? `Con ${n} documento${n === 1 ? "" : "s"} adjunto${n === 1 ? "" : "s"}` : resumenValorPerfil(s.valor_propuesto),
      urgencia: urgenciaEspera(s.creada_at, hoy), resolucion: "aqui", ir: null,
      contexto: { texto: "Ver su ficha", href: `/admin/personas/${s.persona_id}` },
    }, "solicitud_perfil");
  }
  // ⇩ 0450 ⇩ UNA entrega = UN pendiente, y su botón abre ESA entrega.
  for (const e of f.entregasEducacion) {
    agregar({
      clave: `entrega_educacion:${e.id}`, tipo: "entrega_educacion", itemId: e.id, personaId: e.persona_id,
      persona: e.persona, sede: e.sede, modulo: "educacion",
      titulo: e.es_reenvio ? "Constancia educativa corregida, pendiente de revisión" : "Constancia educativa pendiente de revisión",
      detalle: `${e.institucion} · pago del ${diaYMes(e.fecha_pago)} · ${e.archivos} archivo${e.archivos === 1 ? "" : "s"} · enviada el ${diaLima(e.enviada_at)}`,
      urgencia: urgenciaEspera(e.enviada_at, hoy), resolucion: "afuera",
      ir: { texto: "Revisar", href: `/admin/educacion?entrega=${e.id}` }, contexto: null,
    }, "entrega_educacion");
  }
  for (const a of f.avisosFinEducacion) {
    agregar({
      clave: `aviso_fin_educacion:${a.id}`, tipo: "aviso_fin_educacion", itemId: a.id, personaId: a.persona_id,
      persona: a.persona, sede: a.sede, modulo: "educacion",
      titulo: "Avisó que ya no va a pagar su estudio", detalle: `${a.institucion} · «${a.motivo}»`,
      urgencia: urgenciaEspera(a.creado_at, hoy), resolucion: "afuera",
      ir: { texto: "Decidir el cierre", href: `/admin/educacion?familia=${a.familia_id}` }, contexto: null,
    }, "aviso_fin_educacion");
  }
  // ⇩ 0461 ⇩ Pidió su propio apoyo: todavía no hay ninguna asignación ni
  // familia a la que colgar el enlace, así que abre la solicitud directo.
  for (const s of f.solicitudesEducacion) {
    agregar({
      clave: `solicitud_educacion:${s.id}`, tipo: "solicitud_educacion", itemId: s.id, personaId: s.persona_id,
      persona: s.persona, sede: s.sede, modulo: "educacion",
      titulo: "Solicitud de apoyo educativo pendiente de revisión",
      detalle: `${s.institucion} · costo declarado ${formatSoles(s.costo_declarado)}`,
      urgencia: urgenciaEspera(s.enviada_at, hoy), resolucion: "afuera",
      ir: { texto: "Revisar", href: `/admin/educacion?solicitud=${s.id}` }, contexto: null,
    }, "solicitud_educacion");
  }
  for (const e of f.educacion) {
    const doc = documentoEducacion(e);
    agregar({
      clave: `educacion:${e.familia_id}`, tipo: "educacion", itemId: e.familia_id, personaId: e.persona_id,
      persona: e.persona, sede: e.sede, modulo: "educacion",
      titulo: doc.titulo, detalle: e.institucion,
      urgencia: urgenciaEducacion(e, hoy), resolucion: "afuera",
      ir: { texto: doc.accion, href: `/admin/educacion?familia=${e.familia_id}` }, contexto: null,
    });
  }
  for (const v of f.vacaciones) {
    agregar({
      clave: `vacaciones_por_vencer:${v.persona_id}`, tipo: "vacaciones_por_vencer", itemId: v.persona_id,
      personaId: v.persona_id, persona: v.persona, sede: v.sede, modulo: "ausencias",
      titulo: v.records_vencidos > 0 ? "Récord de vacaciones vencido sin gozar" : "Récord de vacaciones por vencer",
      detalle: `Vence el ${diaYMes(v.vence_el)} · hay que programarle sus días`,
      urgencia: urgenciaRecordVacaciones(v), resolucion: "afuera",
      ir: { texto: "Programar vacaciones", href: "/admin/ausencias" }, contexto: null,
    });
  }
  for (const h of f.sinHorario) {
    const dias = `${h.dias} día${h.dias === 1 ? "" : "s"}`;
    agregar({
      clave: `sin_horario:${h.persona_id}`, tipo: "sin_horario", itemId: h.persona_id, personaId: h.persona_id,
      persona: h.nombre, sede: h.sede, modulo: "horarios",
      titulo: h.nunca_tuvo_horario ? `Trabajó ${dias} y nunca se le cargó horario` : `Trabajó ${dias} sin horario`,
      detalle: `${h.nunca_tuvo_horario ? "" : `Del ${diaYMes(h.primer_dia)} al ${diaYMes(h.ultimo_dia)}. `}Esos días no miden tardanza, y una licencia que caiga ahí se paga en cero.`,
      urgencia: urgenciaSinHorario(h), resolucion: "afuera",
      ir: { texto: "Asignar horario", href: "/admin/horarios" }, contexto: null,
    });
  }
  for (const l of f.liquidacionesVencidas) {
    agregar({
      clave: `liquidacion_vencida:${l.persona_id}`, tipo: "liquidacion_vencida", itemId: l.persona_id,
      personaId: l.persona_id, persona: l.persona, sede: l.sede, modulo: "liquidaciones",
      titulo: "Liquidación pasada de plazo",
      detalle: `Cesó el ${diaYMes(l.fecha_cese)} · ${formatSoles(l.total)} por pagar`,
      urgencia: urgenciaLiquidacionVencida(l), resolucion: "afuera",
      ir: { texto: "Revisar", href: `/admin/liquidaciones?persona=${l.persona_id}` }, contexto: null,
    });
  }
  for (const c of f.contratos) {
    const t = textoContrato(c);
    agregar({
      clave: `contrato:${c.persona_id}`, tipo: "contrato", itemId: c.persona_id, personaId: c.persona_id,
      persona: c.persona, sede: c.sede ?? "—", modulo: "contratos",
      titulo: t.titulo, detalle: t.detalle,
      urgencia: urgenciaContrato(c, hoy), resolucion: "afuera",
      ir: { texto: t.accion, href: `/admin/contratos?persona=${c.persona_id}` }, contexto: null,
    });
  }
  for (const d of f.diasPorRevisar) {
    const n = d.marcas;
    agregar({
      clave: `dia_por_revisar:${d.persona_id}:${d.fecha}`, tipo: "dia_por_revisar", itemId: `${d.persona_id}:${d.fecha}`,
      personaId: d.persona_id, persona: d.nombre, sede: d.sede, modulo: "correcciones",
      titulo: `${(d.motivo && MOTIVO_DIA[d.motivo]) || "Día por revisar"}: ${diaYMes(d.fecha)}`,
      detalle: `${n} marca${n === 1 ? "" : "s"} por revisar`,
      urgencia: urgenciaDiaPorRevisar(d.fecha, d.periodo_pagado, f.periodo, hoy), resolucion: "afuera",
      ir: { texto: "Revisar día", href: `/admin/correcciones?persona=${d.persona_id}&fecha=${d.fecha}` }, contexto: null,
    });
  }
  for (const m of f.marcasApartadas) {
    agregar({
      clave: `marca_apartada:${m.id}`, tipo: "marca_apartada", itemId: m.id, personaId: m.persona_id,
      persona: m.persona, sede: m.sede, modulo: "correcciones",
      titulo: `Marca apartada del ${diaYMes(m.fecha)}`,
      detalle: m.ultimo_error ? `El terminal no pudo registrarla: ${m.ultimo_error}` : "El terminal no pudo registrarla",
      urgencia: urgenciaDiaPorRevisar(m.fecha, false, f.periodo, hoy), resolucion: "afuera",
      ir: { texto: "Revisar marca", href: `/admin/correcciones?persona=${m.persona_id}&fecha=${m.fecha}` }, contexto: null,
    });
  }
  for (const d of f.documentos) {
    const p = pendientesDeDocumento(d);
    if (p.ruta) {
      agregar({
        clave: `documento_ruta:${d.persona_id}`, tipo: "documento_ruta", itemId: d.persona_id, personaId: d.persona_id,
        persona: d.persona, sede: d.sede, modulo: "documentacion",
        titulo: p.ruta === "sin_ruta" ? "Declaración de ruta sin firmar" : "Declaración de ruta con tarifa desfasada",
        detalle: p.ruta === "sin_ruta" ? "Sin ella, la movilidad paga impuestos y descuentos" : "Se firmó con otro monto: hay que volver a firmarla",
        urgencia: { grupo: "sin_plazo", plazo: p.ruta === "sin_ruta" ? "Sin firmar" : "Desfasada", nota: null, orden: 0 },
        resolucion: "afuera",
        ir: { texto: "Pedir firma", href: `/admin/documentacion?persona=${d.persona_id}` }, contexto: null,
      });
    }
    if (p.bono) {
      agregar({
        clave: `documento_bono:${d.persona_id}`, tipo: "documento_bono", itemId: d.persona_id, personaId: d.persona_id,
        persona: d.persona, sede: d.sede, modulo: "documentacion",
        titulo: "Bono de cumpleaños sin constancia firmada", detalle: null,
        urgencia: urgenciaBono(d.bono_estado, hoy), resolucion: "afuera",
        ir: { texto: "Registrar constancia", href: `/admin/documentacion?persona=${d.persona_id}` }, contexto: null,
      });
    }
  }
  for (const x of f.feriados) {
    agregar({
      clave: `feriado:${x.persona_id}:${x.fecha_feriado}`, tipo: "feriado", itemId: `${x.persona_id}:${x.fecha_feriado}`,
      personaId: x.persona_id, persona: x.nombre, sede: x.sede, modulo: "feriados",
      titulo: `Trabajó el feriado del ${diaYMes(x.fecha_feriado)}`,
      detalle: x.no_compensa_porque
        ? `El descanso registrado no compensa: ${x.no_compensa_porque}`
        : `Descanso sustitutorio acordado${x.fecha_descanso ? ` para el ${diaYMes(x.fecha_descanso)}` : ""}, sin otorgar`,
      urgencia: urgenciaFeriado(x, hoy), resolucion: "afuera",
      ir: { texto: "Revisar descanso", href: "/admin/feriados" }, contexto: null,
    });
  }
  for (const d of f.disciplina) {
    const t = textoDisciplina(d, hoy);
    agregar({
      clave: `disciplina:${d.id}`, tipo: "disciplina", itemId: d.id, personaId: d.persona_id,
      persona: d.persona, sede: d.sede, modulo: "disciplina",
      titulo: t.titulo, detalle: null,
      urgencia: t.urgencia, resolucion: "afuera",
      ir: { texto: t.accion, href: t.href }, contexto: null,
    });
  }
  return lista.sort(compararPendientes);
}

/**
 * El número del ítem «Bandeja» del menú: exactamente las filas que se pintan,
 * más los avisos por correo con problema. Sale de la MISMA lista, así que no
 * puede discrepar de la pantalla.
 */
export function contarPendientesBandeja(f: FuentesBandeja, hoy: string = hoyLima()): number {
  return armarPendientes(f, { hoy }).length + alertasConProblema(f.resumenAlertas);
}

/**
 * Los mismos pendientes agrupados por persona, con una etiqueta legible por
 * cada uno — para el aviso «N pendientes» de Equipo. Los avisos por correo no
 * tienen persona y no entran.
 */
export function pendientesPorPersona(f: FuentesBandeja, hoy: string = hoyLima()): Map<string, string[]> {
  const mapa = new Map<string, string[]>();
  for (const p of armarPendientes(f, { hoy })) {
    if (!p.personaId) continue;
    const lista = mapa.get(p.personaId) ?? [];
    lista.push(`${ETIQUETA_MODULO[p.modulo]}: ${p.titulo}`);
    mapa.set(p.personaId, lista);
  }
  return mapa;
}
