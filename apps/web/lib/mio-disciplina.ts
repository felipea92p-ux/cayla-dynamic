// ─────────────────────────────────────────────────────────────────────────────
// Disciplina vista por la persona, en «Lo mío» (entrega 4).
//
// Módulo puro (sin React ni Supabase), para poder probarlo sin levantar nada.
// La verdad vive en la base —`fn_mi_disciplina` (0516) y
// `fn_mi_cuenta_de_tardanzas` (0517)—; esto solo ordena, pagina y dice con
// palabras lo que ya está decidido allá. Decidido el 2026-10-06 mirando el
// prototipo `docs/disciplina-mio-prototipo-2026-10-06.html`.
// ─────────────────────────────────────────────────────────────────────────────

import { NIVEL_DISCIPLINARIO_LABELS, nombreDelMesLima } from "@cayla-dynamic/shared";

/** Un documento de la persona, tal como lo entrega `fn_mi_disciplina` (sin el relato). */
export interface DocMio {
  id: string;
  correlativo: string | null;
  nivel: string;
  tipo_causal: string;
  /** Enviado a su Info y sin recibir, o ya entregado. */
  estado: "por_recibir" | "entregado";
  medio_entrega: string | null;
  entregado_at: string | null;
  enviado_a_info_at: string | null;
  periodo_desde: string | null;
  periodo_hasta: string | null;
  falta: { numeral: string; literal: string; rotulo: string | null; gravedad: string } | null;
  abierto_at: string | null;
  leido_at: string | null;
  firma_confirmada_at: string | null;
  rechazo_firma_at: string | null;
  /** Lo entregado en papel que todavía pesa y no firmó: pide «Lo leí». */
  requiere_lectura: boolean;
  vigente_hasta: string | null;
  cancelado: boolean;
}

/** Lo que devuelve `fn_mi_cuenta_de_tardanzas`, o null si a la persona no se le mide. */
export interface CuentaMia {
  mes: string;
  tardanzas_mes: number;
  minimo: number | null;
  nivel_siguiente: string;
}

/** Cuántos documentos se ven por página. El mismo número que «Cambios a tu registro». */
export const POR_PAGINA = 10;

// ── Qué pide atención ────────────────────────────────────────────────────────

/** Entregado en papel, pide «Lo leí» y todavía no lo dio. */
export const porLeer = (d: DocMio): boolean => d.requiere_lectura && !d.leido_at;

/** Lo que la persona tiene que hacer algo con: recibir lo enviado a su Info, o leer lo entregado en papel. */
export const pideAtencion = (d: DocMio): boolean => d.estado === "por_recibir" || porLeer(d);

/** Cuántos piden atención: el número del menú y el de la tarjeta del Resumen. */
export const cuantosPiden = (docs: readonly DocMio[]): number => docs.filter(pideAtencion).length;

/**
 * ¿Pesa este documento hoy? Una amonestación o una suspensión pesan doce meses
 * desde su entrega (56.1); una imputación o una carta de despido no caducan
 * como antecedente. La llamada verbal no es sanción ni antecedente (54.2).
 */
export function pesa(d: DocMio): boolean {
  if (d.estado !== "entregado") return false;
  if (d.nivel === "verbal") return false;
  if (d.nivel === "amonestacion" || d.nivel === "suspension") return !d.cancelado;
  return true;
}

/**
 * ¿Sale el mensaje de aliento? Decidido el 2026-10-06: cuando no hay nada
 * vigente ni por recibir. Quien tuvo una amonestación hace dos años lo vuelve a
 * ver —el Reglamento ya se la canceló (56.7) y lo viejo queda como «ya no
 * pesa»—. Y quien tiene algo por leer no lo ve: no es momento de un chiste.
 */
export function hayAliento(docs: readonly DocMio[]): boolean {
  return !docs.some((d) => pideAtencion(d) || pesa(d));
}

// ── Orden y páginas ──────────────────────────────────────────────────────────

/**
 * Lo que pide atención va primero, sea de la fecha que sea: si estuviera
 * mezclado por fecha, una amonestación por leer podría quedar en la página 2
 * detrás de actas viejas. El resto, de la más reciente a la más vieja.
 */
export function ordenarParaLaPersona(docs: readonly DocMio[]): DocMio[] {
  const fecha = (d: DocMio) => Date.parse(d.entregado_at ?? d.enviado_a_info_at ?? "") || 0;
  return [...docs].sort((a, b) => {
    const pa = pideAtencion(a) ? 0 : 1;
    const pb = pideAtencion(b) ? 0 : 1;
    if (pa !== pb) return pa - pb;
    return fecha(b) - fecha(a) || a.id.localeCompare(b.id);
  });
}

export interface Pagina<T> {
  items: T[];
  /** Base 0. */
  pagina: number;
  paginas: number;
  total: number;
  /** «1–10 de 23»: desde y hasta, base 1. */
  desde: number;
  hasta: number;
}

/** La página `n` (base 0) de una lista, de a `tamano`. Una página fuera de rango se acerca a la última. */
export function paginar<T>(items: readonly T[], n: number, tamano: number = POR_PAGINA): Pagina<T> {
  const total = items.length;
  const paginas = Math.max(1, Math.ceil(total / tamano));
  const pagina = Math.min(Math.max(0, Math.floor(n)), paginas - 1);
  const inicio = pagina * tamano;
  return {
    items: items.slice(inicio, inicio + tamano), pagina, paginas, total,
    desde: total === 0 ? 0 : inicio + 1, hasta: Math.min(inicio + tamano, total),
  };
}

// ── Cómo se llama cada documento ─────────────────────────────────────────────

const CAUSAL_MIO: Record<string, string> = { tardanza: "tardanzas", falta: "inasistencias", conducta: "conducta" };

/** «Amonestación escrita · conducta». */
export function tituloDe(d: Pick<DocMio, "nivel" | "tipo_causal">): string {
  const nivel = (NIVEL_DISCIPLINARIO_LABELS as Record<string, string>)[d.nivel] ?? d.nivel;
  return `${nivel} · ${CAUSAL_MIO[d.tipo_causal] ?? d.tipo_causal}`;
}

/** Lo que se ve de reojo debajo del título: la falta por su nombre corto, o la causal a secas. */
export function queFaltaEs(d: Pick<DocMio, "falta" | "tipo_causal">): string {
  if (d.falta) return d.falta.rotulo ?? `${d.falta.numeral} ${d.falta.literal})`;
  return d.tipo_causal === "tardanza" ? "Tardanzas reiteradas" : d.tipo_causal === "falta" ? "Inasistencia injustificada" : "";
}

// ── El mensaje de aliento ────────────────────────────────────────────────────

/**
 * Dieciséis para empezar, escritos para leerse sin importar cómo le fue ayer a
 * quien los lee: ninguno afirma nada sobre su puntualidad ni su conducta. Los
 * más cálidos —el 5, el 10 y el 15— son los que la usuaria quedó en revisar.
 * Viven en el código y no en una tabla: se cambian dos veces al año, y una
 * pantalla de edición costaría más que eso.
 */
export const MENSAJES_DE_ALIENTO: readonly string[] = [
  "Todo en orden por aquí. No tienes nada pendiente de leer.",
  "Pantalla tranquila hoy: sin llamados y sin documentos.",
  "Nada que leer, nada que firmar. Que sea un día ligero.",
  "Aquí no hay noticias, y en esta pantalla eso es buena noticia.",
  "Tu legajo disciplinario no tiene nada vigente. Gracias por cuidar al equipo y a las clientas.",
  "Sin pendientes. Tómate un cafecito: te lo mereces.",
  "Cero papeles hoy. Hasta Desarrollo Organizacional lo celebra.",
  "Todo en calma. Si algo no te queda claro, pregúntale a tu líder de equipo o a Desarrollo Organizacional.",
  "Una pantalla vacía es una pantalla feliz.",
  "Sin llamados de atención y sin documentos por leer. ¡Buen trabajo, equipo!",
  "Hoy no hay nada para ti aquí. Aprovecha el día.",
  "Nada pendiente. Y pedir ayuda a tiempo también es parte del buen trabajo.",
  "Todo al día. Esta pantalla te avisará si algo cambia.",
  "Silencio en Disciplina: lo mejor que puede pasar.",
  "Sin novedades en tu legajo. Los detalles que cuidas son los que hacen grande a CAYLA.",
  "Hoy esta pantalla descansa. Tú también puedes.",
];

/** FNV-1a de 32 bits: simple, estable y sin dependencias. */
function huella(texto: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < texto.length; i++) {
    h ^= texto.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

/**
 * El mensaje de hoy para esta persona: el mismo todo el día —no cambia cada
 * vez que abre la pantalla— y distinto de un día al otro. `salto` es el «ver
 * otro mensaje», que solo mueve la pantalla y no se guarda.
 */
export function mensajeDeAliento(personaId: string, hoy: string, salto = 0): string {
  const n = MENSAJES_DE_ALIENTO.length;
  return MENSAJES_DE_ALIENTO[(huella(`${personaId}|${hoy}`) + Math.max(0, salto)) % n];
}

// ── «Cómo vas este mes» ──────────────────────────────────────────────────────

const PASO: Record<string, { texto: string; norma: string }> = {
  amonestacion: { texto: "una amonestación escrita", norma: "19.2 b" },
  suspension: { texto: "una suspensión sin goce de haber", norma: "19.2 c o d" },
  imputacion: { texto: "una imputación de cargos", norma: "19.2 e" },
};

const tardanzas = (n: number) => `${n} ${n === 1 ? "tardanza" : "tardanzas"}`;

/** Lo que se dice si alguna tardanza se justifica. RIT 18.1 y 18.2. */
const SI_SE_JUSTIFICA =
  "Si alguna se justifica —salud, transporte, una citación—, pídele a tu líder de equipo que la justifique " +
  "dentro de las 48 horas siguientes a tu regreso (RIT 18.2).";

export interface ComoVas {
  /** «Llevas 2 tardanzas en octubre.» */
  titulo: string;
  /** El resto, con la norma y el aviso de que no es automático. */
  detalle: string;
  /** Cuántas casillas se pintan y cuántas están llenas. */
  casillas: { de: number; llenas: number } | null;
}

/**
 * Cómo se lo decimos. Tono neutro y siempre en condicional: Dynamic avisa y
 * previene, nunca sanciona (RIT 52.9), así que jamás «te corresponde», sino
 * «la Empresa podría». Null si no hay nada que decir.
 */
export function textoComoVas(c: CuentaMia | null): ComoVas | null {
  if (!c || c.minimo === null) return null;
  const mes = nombreDelMesLima(c.mes);
  const paso = PASO[c.nivel_siguiente];
  if (!paso) return null;
  const casillas = { de: Math.min(Math.max(c.minimo, 1), 6), llenas: Math.min(c.tardanzas_mes, Math.min(Math.max(c.minimo, 1), 6)) };

  if (c.tardanzas_mes === 0) {
    return { titulo: `No llevas tardanzas en ${mes}.`, detalle: "", casillas };
  }
  if (c.tardanzas_mes < c.minimo) {
    return {
      titulo: `Llevas ${tardanzas(c.tardanzas_mes)} en ${mes}.`,
      detalle:
        `Con ${c.minimo}, la Empresa podría emitir ${paso.texto} (RIT ${paso.norma}); no es automático (52.9). ` + SI_SE_JUSTIFICA,
      casillas,
    };
  }
  return {
    titulo: `Llevas ${tardanzas(c.tardanzas_mes)} en ${mes}.`,
    detalle:
      `Es el número a partir del cual la Empresa puede emitir ${paso.texto} (RIT ${paso.norma}). ` +
      `La decisión es siempre de una persona, no del sistema (52.9). ` + SI_SE_JUSTIFICA,
    casillas,
  };
}
