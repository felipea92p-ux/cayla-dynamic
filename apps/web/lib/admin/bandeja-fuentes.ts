import type { ClienteCayla } from "@cayla-dynamic/database";
import {
  fechaLima, hoyLima, puedeGestionarCatalogos, puedeGestionarContratos, puedeOperarEquipo, puedeVerPlanilla,
  puedeVerSaludDeAlertas,
} from "@cayla-dynamic/shared";
import { diaYMes } from "../bandeja-mia";
import { formatSoles } from "../rangos";
import {
  compararPendientes, conCese, documentoEducacion, urgenciaEducacion, urgenciaEspera, urgenciaInicio,
  urgenciaLiquidacionVencida, urgenciaRecordVacaciones, urgenciaSinHorario, type Urgencia,
} from "./bandeja-urgencia";

/**
 * DE DÓNDE SALE CADA PENDIENTE DE LA BANDEJA — una sola vez para todo el panel.
 *
 * QUÉ PROMETE. `traerFuentesBandeja` pide, según el permiso de quien mira, las
 * mismas RPC de siempre; `armarPendientes` las convierte en UNA lista con la
 * forma que se pinta. La pantalla (`/admin/bandeja`), el número del menú
 * (`contarBandejaEquipoPendiente`) y el de cada persona en Equipo
 * (`listarPendientesPorPersona`) leen de aquí.
 *
 * POR QUÉ EXISTE (2026-09-15). Hasta hoy eran TRES copias de la misma lista de
 * RPC: la pantalla, el contador y el mapa por persona. Se separaron dos veces
 * en una semana — el contador del menú nunca sumó las liquidaciones vencidas
 * que la pantalla sí mostraba, y Equipo siguió contando Educación con la
 * consulta de antes de la 0450. Con una sola lista, una fuente nueva entra a
 * los tres lugares o a ninguno.
 *
 * QUÉ ASUME. La base decide quién ve qué (RLS y guards). Los `puede*` de acá
 * solo evitan pedir lo que igual volvería vacío.
 */

// ── Lo que devuelve cada RPC ────────────────────────────────────────────────

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
 * institución de los próximos días: el aviso que DO pidió para tener el apoyo
 * listo (ADR 0003, decisión 8).
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

/**
 * De todo lo que trae Liquidaciones, solo la vencida con dinero real en juego
 * cruza a la Bandeja — decidido con Felipe el 2026-09-15 (ver
 * `urgenciaLiquidacionVencida`). Las demás ya las muestra su pantalla.
 */
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
  /** Solo lo aprueba DO aunque la encargada lo vea (0405). Lo dice `catalogo_campos_perfil.solo_do`. */
  solo_do: boolean;
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
  vacaciones: ItemVacacion[];
  sinHorario: ItemSinHorario[];
  liquidacionesVencidas: ItemLiquidacion[];
  revisiones: ItemRevision[];
  revisionesMovilidad: ItemRevisionMovilidad[];
  revisionesContrato: ItemRevisionContrato[];
  solicitudesVacaciones: ItemSolicitudVacacion[];
  solicitudesPerfil: ItemSolicitudPerfil[];
  resumenAlertas: ResumenAlertas | null;
}

export const FUENTES_VACIAS: FuentesBandeja = {
  educacion: [], entregasEducacion: [], avisosFinEducacion: [], vacaciones: [], sinHorario: [],
  liquidacionesVencidas: [], revisiones: [], revisionesMovilidad: [], revisionesContrato: [],
  solicitudesVacaciones: [], solicitudesPerfil: [], resumenAlertas: null,
};

/** Cuántos avisos por correo necesitan a una persona. Lo que se reintenta solo no cuenta. */
export function alertasConProblema(r: ResumenAlertas | null): number {
  return r ? r.atascadas + r.fallidas_definitivas + r.caducadas : 0;
}

// ── Cargar ──────────────────────────────────────────────────────────────────

/**
 * Pide todas las fuentes que este rol puede ver, en paralelo.
 *
 * Falla por sección, nunca entera: una RPC que falla o que todavía no existe en
 * esta base deja su lista vacía y avisa por `alFallar` (la pantalla lo muestra;
 * el menú lo calla, como el resto de sus contadores). `fn_personas_sin_horario_vigente`
 * y `fn_alertas_despacho_resumen` fallan en silencio incluso para la pantalla,
 * como ya hacían: una es un chequeo de datos, la otra de salud del cron.
 */
export async function traerFuentesBandeja(
  supabase: ClienteCayla,
  rol: string | null | undefined,
  alFallar: (que: string, error: unknown) => void = () => {},
): Promise<FuentesBandeja> {
  const f: FuentesBandeja = { ...FUENTES_VACIAS };
  const tareas: PromiseLike<void>[] = [];
  const lista = <T,>(data: unknown): T[] => (Array.isArray(data) ? (data as T[]) : []);
  const pedir = <T,>(llamada: PromiseLike<{ data: unknown; error: unknown }>, que: string, guardar: (xs: T[]) => void, callado = false) => {
    tareas.push(llamada.then(({ data, error }) => {
      if (error) { if (!callado) alFallar(que, error); return; }
      guardar(lista<T>(data));
    }));
  };

  if (puedeVerPlanilla(rol)) {
    pedir<ItemEntregaEducacion>(supabase.rpc("fn_educacion_entregas_pendientes"), "las constancias de educación", (xs) => { f.entregasEducacion = xs; });
    pedir<ItemAvisoFinEducacion>(supabase.rpc("fn_educacion_avisos_fin_pendientes"), "los avisos de educación", (xs) => { f.avisosFinEducacion = xs; });
    pedir<FilaEducacionBandeja>(supabase.rpc("fn_educacion_situacion"), "educación", (xs) => { f.educacion = xs.filter(esEducacionParaSaber); });
    pedir<ItemSolicitudVacacion>(supabase.rpc("fn_solicitudes_vacaciones", { p_solo_pendientes: true }), "solicitudes de vacaciones", (xs) => { f.solicitudesVacaciones = xs; });
    pedir<ItemLiquidacion>(supabase.rpc("fn_liquidaciones_pendientes"), "liquidaciones vencidas", (xs) => { f.liquidacionesVencidas = xs.filter(esLiquidacionParaBandeja); });
  }

  if (puedeOperarEquipo(rol)) {
    pedir<ItemVacacion>(supabase.rpc("fn_vacaciones_por_vencer", { p_dias: 60, p_as_of: null }), "vacaciones por vencer", (xs) => { f.vacaciones = xs; });
    pedir<ItemSinHorario>(supabase.rpc("fn_personas_sin_horario_vigente", { p_dias: 60 }), "personas sin horario", (xs) => { f.sinHorario = xs; }, true);
    pedir<ItemRevision>(supabase.rpc("fn_revisiones_pedidas", { p_solo_pendientes: true }), "revisiones pedidas", (xs) => { f.revisiones = xs; });
    pedir<ItemSolicitudPerfil>(supabase.rpc("fn_solicitudes_perfil_pendientes"), "solicitudes de perfil", (xs) => { f.solicitudesPerfil = xs; });
  }

  if (puedeGestionarCatalogos(rol)) {
    pedir<ItemRevisionMovilidad>(supabase.rpc("fn_movilidad_revisiones_pedidas", { p_solo_pendientes: true }), "revisiones de movilidad pedidas", (xs) => { f.revisionesMovilidad = xs; });
  }

  if (puedeGestionarContratos(rol)) {
    pedir<ItemRevisionContrato>(supabase.rpc("fn_contrato_revisiones_pedidas", { p_solo_pendientes: true }), "revisiones de contrato pedidas", (xs) => { f.revisionesContrato = xs; });
  }

  if (puedeVerSaludDeAlertas(rol)) {
    tareas.push(supabase.rpc("fn_alertas_despacho_resumen").then(({ data, error }) => {
      f.resumenAlertas = error || !data ? null : (data as unknown as ResumenAlertas);
    }));
  }

  await Promise.all(tareas);
  return f;
}

// ── Armar ───────────────────────────────────────────────────────────────────

/** Los tipos que llevan «Nuevo desde tu última visita» (bandeja_vistos, 0436/0450). */
export type TipoItemVisto =
  | "revision" | "revision_movilidad" | "revision_contrato"
  | "solicitud_vacacion" | "solicitud_perfil"
  | "entrega_educacion" | "aviso_fin_educacion";

export type TipoPendiente = TipoItemVisto | "educacion" | "vacaciones_por_vencer" | "sin_horario" | "liquidacion_vencida";

/** De qué módulo viene cada pendiente. */
export type ModuloBandeja =
  | "educacion" | "ausencias" | "correcciones" | "horarios" | "datos_personales"
  | "contratos" | "documentacion" | "liquidaciones";

export const ETIQUETA_MODULO: Record<ModuloBandeja, string> = {
  contratos: "Contratos",
  correcciones: "Correcciones",
  documentacion: "Documentación",
  educacion: "Educación",
  ausencias: "Ausencias",
  horarios: "Horarios",
  datos_personales: "Datos personales",
  liquidaciones: "Liquidaciones",
};

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
