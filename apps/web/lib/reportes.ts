import type { ClienteCayla } from "@cayla-dynamic/database";
import { TZ_LIMA } from "@cayla-dynamic/shared";
import { mensajeDeError } from "./admin/mensaje-error";
import { compartirMientrasVuela } from "./compartir-mientras-vuela";

/**
 * REPORTES — lo que «Lo mío» y su Bandeja comparten (docs/plan-reportes.md).
 *
 * QUIÉN DECIDE QUÉ
 *   Quién puede leer un reporte, a quién le toca, qué plazos corren y si se
 *   puede enviar lo decide la BASE (0483 y 0488). Lo de aquí es lo que la
 *   pantalla necesita para no hacer esperar a nadie por un error obvio y para
 *   hablar en palabras: qué vía corresponde a lo que se marcó, qué falta en el
 *   formulario, y cómo se dice una fecha de vencimiento. Si la base dice otra
 *   cosa, gana la base: su mensaje se muestra tal cual.
 *
 * POR QUÉ UN ARCHIVO APARTE
 *   El globito del menú de /mio, la pestaña «Reportes» y la Bandeja preguntan lo
 *   mismo —«¿qué me respondieron que no leí?»—. Se lee UNA vez
 *   (`traerMisReportes`) y `contarSinLeer` cuenta, igual que las boletas.
 */

export type TipoReporte = "persona" | "empresa" | "clienta" | "idea" | "consulta";
export type ViaReporte = "reclamo" | "convivencia" | "titulo_x";
export type EstadoReporte = "recibido" | "en_revision" | "cerrado";
export type EsperaReporte = "que_se_sepa" | "conversar" | "que_cambie" | "que_se_actue";

export const TIPOS_REPORTE: readonly { valor: TipoReporte; titulo: string; ayuda: string }[] = [
  { valor: "persona", titulo: "Una persona del equipo", ayuda: "Un trato, un conflicto, algo que se repite." },
  { valor: "empresa", titulo: "La empresa", ayuda: "Un proceso, turnos, la sede, herramientas, condiciones." },
  { valor: "clienta", titulo: "Una clienta", ayuda: "Algo que pasó atendiendo. No pedimos sus datos." },
  { valor: "idea", titulo: "Una idea de mejora", ayuda: "Algo que haría mejor el trabajo o la tienda." },
  { valor: "consulta", titulo: "Una consulta a mi líder", ayuda: "Una pregunta sobre tu trabajo. Te responden por escrito." },
];

export const ESPERAS: readonly { valor: EsperaReporte; titulo: string; ayuda: string }[] = [
  { valor: "que_se_sepa", titulo: "Que se sepa", ayuda: "Quiero que quede registrado." },
  { valor: "conversar", titulo: "Conversar", ayuda: "Que alguien hable con nosotras." },
  { valor: "que_cambie", titulo: "Que cambie algo", ayuda: "Un proceso, un turno, una regla." },
  { valor: "que_se_actue", titulo: "Que se actúe", ayuda: "Que se tomen medidas." },
];

/** El título de un reporte en la lista: lo que se eligió en el paso 1, o el camino que tomó. */
export function tituloDeReporte(tipo: string, via: string): string {
  if (via === "titulo_x") return "Queja de hostigamiento sexual";
  switch (tipo) {
    case "persona": return "Sobre una compañera o compañero";
    case "empresa": return "Sobre la empresa";
    case "clienta": return "Sobre una clienta";
    case "idea": return "Idea de mejora";
    case "consulta": return "Consulta a mi líder";
    default: return "Reporte";
  }
}

/** Cómo se nombra un caso en el panel: su camino en el Reglamento. */
export function etiquetaDeVia(via: string, tipo: string): string {
  if (via === "titulo_x") return "Título X · hostigamiento sexual";
  if (via === "convivencia") return "Convivencia · 43-A";
  if (tipo === "consulta") return "Consulta a la líder · 43-B";
  if (tipo === "idea") return "Idea de mejora · 43-B";
  return "Reclamo · 43-B";
}

export function etiquetaDeEstado(estado: string): { texto: string; variante: "neutral" | "informativo" | "positivo" } {
  if (estado === "cerrado") return { texto: "Cerrado", variante: "positivo" };
  if (estado === "en_revision") return { texto: "En revisión", variante: "informativo" };
  return { texto: "Recibido", variante: "neutral" };
}

/**
 * La vía sale de lo que se marcó, no de una elección aparte. Mismas reglas que
 * `fn_reporte_crear`: el Título X gana siempre; el maltrato o el acoso entre
 * personas es convivencia (43-A); todo lo demás es consulta, reclamo o
 * sugerencia (43-B).
 */
export function viaDeReporte(p: { tituloX: boolean; tipo: TipoReporte; maltrato: boolean }): ViaReporte {
  if (p.tituloX) return "titulo_x";
  if (p.tipo === "persona" && p.maltrato) return "convivencia";
  return "reclamo";
}

export interface BorradorReporte {
  tituloX: boolean;
  tipo: TipoReporte | null;
  maltrato: boolean;
  relato: string;
  fechaHecho: string;
  sedeId: string;
  involucradas: string[];
  testigos: string[];
}

/**
 * Lo primero que falta, dicho para quien lo va a leer, o null si se puede
 * enviar. Es la misma lista que valida la base; aquí solo evita un viaje.
 * `paso` limita la revisión a lo que ya se vio, para no reclamar en el paso 1
 * algo que se pide en el 3.
 */
export function faltaEnReporte(b: BorradorReporte, hoy: string, paso = 4): string | null {
  if (!b.tipo) return "Elige sobre qué es.";
  if (b.tituloX && !(b.tipo === "persona" || b.tipo === "clienta")) {
    return "Una queja de hostigamiento sexual es sobre una persona o una clienta.";
  }
  if (paso < 2) return null;
  if (b.relato.trim().length === 0) return "Cuenta qué pasó.";
  if (paso < 3) return null;
  if (!b.fechaHecho) return "Falta la fecha del hecho.";
  if (b.fechaHecho > hoy) return "La fecha del hecho no puede ser futura.";
  if (!b.sedeId) return "Elige la sede donde pasó.";
  if (b.tipo === "persona" && !b.tituloX && b.involucradas.length === 0) return "Elige a la persona sobre la que reportas.";
  if (b.involucradas.some((x) => b.testigos.includes(x))) return "Una persona no puede ser involucrada y testigo a la vez.";
  return null;
}

/** «el lunes 12 de octubre» — el día en Lima en que vence un plazo. */
export function fechaEnPalabras(iso: string): string {
  return new Intl.DateTimeFormat("es-PE", {
    timeZone: TZ_LIMA, weekday: "long", day: "numeric", month: "long",
  }).format(new Date(iso)).replace(",", "");
}

/** Una fila de `fn_reportes_mios()`. */
export interface FilaMiReporte {
  id: string;
  codigo: string;
  tipo: string;
  via: string;
  estado: string;
  creado_at: string;
  cerrado_at: string | null;
  cierre_texto: string | null;
  respuesta_vence_at: string | null;
  mensajes: number;
  ultimo_mensaje_at: string | null;
  sin_leer: number;
}

export async function traerMisReportes(supabase: ClienteCayla): Promise<{ filas: FilaMiReporte[]; error: string | null }> {
  const { data, error } = await compartirMientrasVuela("fn_reportes_mios", async () => await supabase.rpc("fn_reportes_mios"));
  if (error) return { filas: [], error: mensajeDeError(error, "leer tus reportes") };
  return { filas: (data ?? []) as FilaMiReporte[], error: null };
}

/** Cuántos reportes tienen algo que ella todavía no leyó: el globito del menú. */
export function contarSinLeer(filas: readonly FilaMiReporte[]): number {
  return filas.filter((f) => f.sin_leer > 0).length;
}

const EXTENSIONES: Record<string, string> = {
  "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp",
  "image/heic": "heic", "image/heif": "heif", "application/pdf": "pdf",
};

/** Los formatos que acepta el bucket `reportes` (0483). */
export const TIPOS_DE_ADJUNTO = Object.keys(EXTENSIONES);

/**
 * La ruta de un adjunto: `<reporte>/<uuid>.<ext>`. Es la única forma que dejan
 * subir las políticas del bucket; cualquier otra devuelve «sin permiso».
 */
export function rutaDeAdjunto(reporteId: string, mimetype: string, uuid: string = crypto.randomUUID()): string | null {
  const ext = EXTENSIONES[mimetype];
  return ext ? `${reporteId}/${uuid}.${ext}` : null;
}

/** Por qué alguien gestiona un caso: lo que devuelve `fn_reporte_motivo` (0483). */
export type MotivoCaso = "lider" | "do" | "gerencia" | "investigadora";

export interface AccionesCaso {
  escribir: boolean;
  enRevision: boolean;
  anotar: boolean;
  /** Las acciones que se ofrecen al registrar algo: en el Título X no hay mediación (48.14). */
  tiposDeAccion: readonly ("conversacion" | "mediacion" | "cambio_proceso" | "otra")[];
  reclasificar: boolean;
  escalar: boolean;
  medida: boolean;
  cerrar: boolean;
  /** Si no se puede cerrar, por qué: se muestra junto al botón apagado. */
  porQueNoCierra: string | null;
  derivar: boolean;
  indiciosDelito: boolean;
  avisarFecha: boolean;
}

/**
 * Qué botones muestra la ficha de un caso. Es el cuadro «QUIÉN HACE QUÉ» del
 * encabezado de la 0488 visto desde la pantalla: solo decide qué se OFRECE.
 * Quien decide de verdad es la base, y si dice otra cosa su mensaje se muestra.
 */
export function accionesDelCaso(c: {
  motivo: MotivoCaso;
  via: string;
  estado: string;
  gestiona: string | null;
  informeRegistrado: boolean;
  respuestaPendiente: boolean;
}): AccionesCaso {
  const abierto = c.estado !== "cerrado";
  const decide = c.motivo === "do" || c.motivo === "gerencia";
  const tituloX = c.via === "titulo_x";
  const puedeCerrarPorVia = c.via === "reclamo" ? c.motivo !== "investigadora" : decide;
  let porQueNoCierra: string | null = null;
  if (!abierto) porQueNoCierra = "Ya está cerrado.";
  else if (!puedeCerrarPorVia) {
    porQueNoCierra = c.motivo === "investigadora"
      ? "Quien investiga propone; decide Desarrollo Organizacional (48.1)."
      : "En convivencia cierra Desarrollo Organizacional, con la respuesta escrita del 43-A.6.";
  } else if (tituloX && !c.informeRegistrado) porQueNoCierra = "Falta el informe de quien investiga (49.7).";
  return {
    escribir: true,
    enRevision: abierto && c.estado === "recibido",
    anotar: abierto,
    tiposDeAccion: tituloX ? ["cambio_proceso", "otra"] : ["conversacion", "mediacion", "cambio_proceso", "otra"],
    reclasificar: abierto && (!tituloX || decide),
    escalar: abierto && (c.gestiona === "lider" || c.gestiona === "do") && c.motivo !== "investigadora",
    medida: abierto && decide && c.via !== "reclamo",
    cerrar: porQueNoCierra === null,
    porQueNoCierra,
    derivar: decide,
    indiciosDelito: decide && tituloX,
    avisarFecha: abierto && c.via === "reclamo" && c.motivo !== "investigadora" && c.respuestaPendiente,
  };
}

export const RESULTADOS_CIERRE: readonly { valor: string; texto: string }[] = [
  { valor: "resuelto", texto: "Resuelto" },
  { valor: "confirmado", texto: "Se confirmaron los hechos" },
  { valor: "no_confirmado", texto: "No se confirmaron los hechos" },
  { valor: "sin_accion", texto: "Sin acción" },
  { valor: "derivado_disciplinario", texto: "Derivado a disciplina" },
];

export const NOMBRE_ACCION: Record<string, string> = {
  conversacion: "Conversación", mediacion: "Mediación", cambio_proceso: "Cambio de proceso", otra: "Otra actuación",
};

export const NOMBRE_EVENTO: Record<string, string> = {
  creado: "Recibido", acuse: "Acuse de recibo", estado: "En revisión", reclasificado: "Cambió de vía",
  escalado: "Escalado", accion: "Actuación", medida: "Medida de protección", plazo: "Plazo cumplido",
  derivado_expediente: "Enlazado a disciplina", cerrado: "Cerrado", lectura: "Abierto",
};
