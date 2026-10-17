/**
 * EDUCACIÓN POR MESES, POR PERSONA Y POR SEDE — la cuenta detrás de la pantalla.
 *
 * PROMETE: contestar, sin tocar la base ni el navegador, cuatro preguntas que la
 *   pantalla de Educación se hace a cada rato:
 *     1. ¿Qué meses se dibujan? (los últimos N, terminando en el mes que
 *        corresponde, con «ver más» hacia atrás)
 *     2. ¿Cuál es la fila de cada persona? Una por PERSONA E INSTITUCIÓN: si el
 *        mismo estudio se registró dos veces —el caso real de Duolingo, del 01/08
 *        al 28/08 y del 29/08 al 28/09—, es UNA línea con sus meses seguidos.
 *     3. ¿Qué dice cada casilla de la cuadrícula? La constancia que RECIBIÓ ese mes.
 *     4. ¿Qué filas pasan los filtros, y cuánto suma cada sede?
 * ASUME: las filas de `fn_educacion_situacion` (una por estudio) y las de
 *   `fn_educacion_entregas` (una por constancia). Las dos ya vienen filtradas por
 *   permiso desde la base: acá nadie decide quién ve qué.
 * NO HACE: no calcula el estado de ninguna constancia —lo contesta la base—, no
 *   toca lo que se paga y no escribe nada.
 *
 * ── DECISIONES YA TOMADAS (Felipe, 2026-10-16) — no se reabren ──────────────
 * · «Mes» = mes CALENDARIO de la fecha de pago, que es lo que dice el papel y
 *   lo que ya usaba el filtro «Pago». El periodo de planilla (29 al 28) sigue
 *   siendo del plazo, no de la etiqueta de una columna.
 * · Un mes sin constancia muestra «—». NUNCA se inventa una falta: Dynamic
 *   avisa, no sanciona, y acusar de falta a quien no debía es el peor error. Lo
 *   vencido ya lo dice el estado que calcula la base. Lo único que la casilla
 *   distingue es «el estudio aún no existía / ya había terminado ese mes»
 *   (`fueraDeVigencia`), que es un hecho de las fechas y no una inferencia.
 * · Una fila por persona e institución. Si una persona paga el estudio de su hijo
 *   en la misma institución que el suyo, NO se mezclan: el beneficiario entra en
 *   la clave.
 *
 * SE ROMPE SI: se agrega un filtro en `pasaFiltros` y no en `FILTROS_VACIOS` /
 * `filtrosAUrl` (el enlace dejaría de reproducir la pantalla), o si alguien
 * decide que «falta» se calcula acá: ese cálculo ya existe en la base y tener dos
 * es el defecto que CLAUDE.md prohíbe para «qué le tocaba trabajar ese día».
 */

import type { EstadoConstancia, TipoConstancia } from "@cayla-dynamic/shared";
import { TIPOS_CONSTANCIA } from "@cayla-dynamic/shared";
import type { GrupoEducacion } from "./educacion-grupos";
import { grupoDeEstudio } from "./educacion-grupos";
import type { Entrega, EntregaDeFamilia, Situacion } from "./educacion-tipos";

// ── MESES ────────────────────────────────────────────────────────────────────

export const MESES_CORTOS = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "set", "oct", "nov", "dic"] as const;

/** "2026-09-30" → "2026-09". Aritmética de texto: no hay huso horario que equivocar. */
export const mesDe = (iso: string): string => iso.slice(0, 7);

/** "2026-11" + 3 → "2027-02". */
export function sumarMeses(mes: string, n: number): string {
  const [anio, m] = mes.split("-").map(Number);
  const total = anio * 12 + (m - 1) + n;
  return `${Math.floor(total / 12)}-${String((total % 12) + 1).padStart(2, "0")}`;
}

/** Cuántos meses hay de `desde` a `hasta`: 0 si es el mismo, 3 de «2026-07» a «2026-10». */
export const mesesEntre = (desde: string, hasta: string): number =>
  (Number(hasta.slice(0, 4)) - Number(desde.slice(0, 4))) * 12 + Number(hasta.slice(5, 7)) - Number(desde.slice(5, 7));

/** "2026-09" → { corto: "set", anio: "2026" }. */
export function etiquetaMes(mes: string): { corto: string; anio: string } {
  return { corto: MESES_CORTOS[Number(mes.slice(5, 7)) - 1] ?? mes, anio: mes.slice(0, 4) };
}

/** "2026-09" → "set 2026". */
export const mesLargo = (mes: string): string => {
  const e = etiquetaMes(mes);
  return `${e.corto} ${e.anio}`;
};

/** Cuántos meses se dibujan al abrir, y cuántos se suman con «ver más». */
export const MESES_INICIALES = 6;
export const MESES_POR_PASO = 6;
/** Una cuadrícula de una o dos columnas no se lee como una línea de tiempo. */
const MESES_MINIMOS = 3;

export interface VentanaDeMeses {
  /** De más antiguo a más reciente: así se lee una línea de tiempo. */
  meses: string[];
  /** Hay meses anteriores con datos que todavía no se dibujan. */
  hayMas: boolean;
}

/**
 * Los meses que se dibujan. Terminan en el mes de hoy, o en el último mes con
 * constancia si es posterior (alguien ya envió el pago del mes que viene: no se
 * esconde a la derecha). Empiezan `cuantos` meses antes, pero nunca antes del
 * primer mes con datos —seis columnas casi vacías son ruido— y nunca menos de
 * `MESES_MINIMOS`.
 */
export function ventanaDeMeses(
  hoy: string,
  mesesConDatos: readonly string[],
  cuantos: number,
): VentanaDeMeses {
  const actual = mesDe(hoy);
  const ultimo = mesesConDatos.reduce((m, x) => (x > m ? x : m), actual);
  const primero = mesesConDatos.reduce((m, x) => (x < m ? x : m), actual);
  const piso = sumarMeses(ultimo, -(Math.max(cuantos, MESES_MINIMOS) - 1));
  let inicio = piso > primero ? piso : primero;
  const minimo = sumarMeses(ultimo, -(MESES_MINIMOS - 1));
  if (inicio > minimo) inicio = minimo;
  const meses: string[] = [];
  for (let m = inicio; m <= ultimo; m = sumarMeses(m, 1)) meses.push(m);
  return { meses, hayMas: inicio > primero };
}

/**
 * Los meses «con datos» que deciden hasta dónde llega la línea de tiempo: los de las constancias
 * recibidas y los de INICIO de cada estudio. Un estudio que empieza en el futuro no cuenta —lo
 * pondría como último mes y empujaría el de hoy fuera de la ventana—; solo las constancias que ya
 * llegaron pueden estirarla hacia la derecha.
 */
export function mesesConDatosDeLaVentana(
  hoy: string,
  entregas: readonly Entrega[],
  estudios: readonly { desde: string }[],
): string[] {
  const actual = mesDe(hoy);
  return [...mesesConConstancia(entregas), ...estudios.map((e) => mesDe(e.desde)).filter((m) => m <= actual)];
}

/**
 * La ventana, abierta hasta el mes que pida un filtro de fecha: el «mes del pago» o el «desde» del
 * rango libre. Sin eso, quien filtra por «ago» o por «desde el 1/7» vería la lista recortada pero
 * la cuadrícula mostrando otros seis meses, sin la columna que pidió.
 */
export function ventanaParaFiltros(
  hoy: string,
  mesesConDatos: readonly string[],
  cuantos: number,
  f: Pick<Filtros, "mes" | "desde">,
): VentanaDeMeses {
  const v = ventanaDeMeses(hoy, mesesConDatos, cuantos);
  const pedido = f.mes || f.desde.slice(0, 7);
  if (pedido && pedido < v.meses[0]) {
    return ventanaDeMeses(hoy, mesesConDatos, mesesEntre(pedido, v.meses[v.meses.length - 1]) + 1);
  }
  return v;
}

// ── ESTUDIOS: UNA FILA POR PERSONA E INSTITUCIÓN ─────────────────────────────

/** Lo que pide acción primero; después, por persona. Igual al orden de siempre. */
export const PRIORIDAD_ESTADO: Record<EstadoConstancia, number> = {
  pendiente_revision: 0, vencida: 1, por_vencer: 2, rechazada: 3, falta_enviar: 4, sin_calendario: 5, al_dia: 6,
};

const norm = (s: string): string =>
  s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim().replace(/\s+/g, " ");

/** Una fila de la pantalla: todos los tramos de una persona en una institución. */
export interface Estudio {
  clave: string;
  persona_id: string;
  persona: string;
  sede: string;
  rango: string;
  institucion: string;
  beneficiario: string;
  beneficiario_nombre: string | null;
  /** Por fecha de inicio, de más antiguo a más reciente. */
  tramos: Situacion[];
  /** El tramo que habla por la fila: el que más atención pide entre los que siguen en curso. */
  actual: Situacion;
  // Los tres de abajo hacen que un Estudio entre donde entra una Situación en
  // `grupoDeEstudio` y `estadoParaMostrar` (que piden `estado_constancia` y `aprobadas`).
  estado_constancia: EstadoConstancia;
  /** Las del tramo en curso (o del que habla, si todos terminaron): «al día» exige respaldo del tramo VIGENTE. */
  aprobadas: number;
  vigencia: Situacion["vigencia"];
  desde: string;
  hasta: string;
}

function claveDeEstudio(s: Situacion): string {
  const quien = s.beneficiario === "hijo" ? `hijo:${norm(s.beneficiario_nombre ?? "")}` : "yo";
  return `${s.persona_id}|${norm(s.institucion)}|${quien}`;
}

/**
 * El tramo que habla por la fila. Entre los que siguen en curso, el de estado más
 * urgente —así un problema de un tramo no se esconde detrás de otro «al día»—; si
 * todos terminaron, el que terminó más tarde.
 */
function tramoRepresentante(tramos: Situacion[]): Situacion {
  const enCurso = tramos.filter((t) => t.vigencia !== "terminada");
  if (enCurso.length > 0) {
    return [...enCurso].sort(
      (a, b) =>
        PRIORIDAD_ESTADO[a.estado_constancia] - PRIORIDAD_ESTADO[b.estado_constancia] ||
        b.vigente_hasta.localeCompare(a.vigente_hasta),
    )[0];
  }
  return [...tramos].sort(
    (a, b) => b.vigente_hasta.localeCompare(a.vigente_hasta) || b.vigente_desde.localeCompare(a.vigente_desde),
  )[0];
}

/** Lo que un tramo YA TERMINADO sigue debiendo y no puede esconderse detrás del tramo que sigue en curso. */
const PENDIENTE_DE_UN_TRAMO_TERMINADO = new Set<EstadoConstancia>(["pendiente_revision", "vencida", "rechazada"]);

/**
 * El estado que dice la fila. Es el del tramo que habla por ella, salvo que un tramo ya terminado
 * tenga una constancia sin resolver —por revisar, vencida o rechazada—: eso no se esconde detrás de
 * un «Al día» del tramo nuevo. Sin esto, la misma fila contaba en la tarjeta «Pendientes de revisión»
 * (que mira todos los tramos) y se pintaba «Al día» y caía en otra pestaña.
 */
function estadoDeLaFila(tramos: Situacion[], actual: Situacion): EstadoConstancia {
  let estado = actual.estado_constancia;
  for (const t of tramos) {
    if (t === actual || t.vigencia !== "terminada") continue;
    if (PENDIENTE_DE_UN_TRAMO_TERMINADO.has(t.estado_constancia) && PRIORIDAD_ESTADO[t.estado_constancia] < PRIORIDAD_ESTADO[estado]) {
      estado = t.estado_constancia;
    }
  }
  return estado;
}

export function agruparEstudios(situaciones: readonly Situacion[]): Estudio[] {
  const porClave = new Map<string, Situacion[]>();
  for (const s of situaciones) {
    const k = claveDeEstudio(s);
    const lista = porClave.get(k);
    if (lista) lista.push(s); else porClave.set(k, [s]);
  }
  const estudios: Estudio[] = [];
  for (const [clave, lista] of porClave) {
    const tramos = [...lista].sort(
      (a, b) => a.vigente_desde.localeCompare(b.vigente_desde) || a.vigente_hasta.localeCompare(b.vigente_hasta),
    );
    const actual = tramoRepresentante(tramos);
    // «Al día» exige que el tramo EN CURSO tenga respaldo: las constancias de un ciclo ya cerrado no
    // tapan que el tramo nuevo todavía no tiene ninguna. Si todos terminaron, cuentan las del que habla.
    const enCurso = tramos.filter((t) => t.vigencia !== "terminada");
    estudios.push({
      clave,
      persona_id: actual.persona_id,
      persona: actual.persona,
      sede: actual.sede,
      rango: actual.rango,
      institucion: actual.institucion,
      beneficiario: actual.beneficiario,
      beneficiario_nombre: actual.beneficiario_nombre,
      tramos,
      actual,
      estado_constancia: estadoDeLaFila(tramos, actual),
      aprobadas: (enCurso.length > 0 ? enCurso : [actual]).reduce((t, x) => t + x.aprobadas, 0),
      vigencia: actual.vigencia,
      desde: tramos[0].vigente_desde,
      hasta: tramos.reduce((m, x) => (x.vigente_hasta > m ? x.vigente_hasta : m), tramos[0].vigente_hasta),
    });
  }
  return estudios.sort(
    (a, b) =>
      PRIORIDAD_ESTADO[a.estado_constancia] - PRIORIDAD_ESTADO[b.estado_constancia] ||
      a.persona.localeCompare(b.persona) || a.institucion.localeCompare(b.institucion),
  );
}

export const familiasDe = (e: Estudio): string[] => e.tramos.map((t) => t.familia_id);

/** Los tramos que HOY se están pagando. La misma condición que el total del encabezado. */
const sePagaHoy = (t: Situacion, hoy: string): boolean => t.paga && t.vigente_desde <= hoy;

/**
 * Cuánto se le paga hoy por este estudio. Suma los tramos que se pagan —si el
 * mismo estudio quedó registrado dos veces a la vez, la planilla paga las dos, y
 * esta cifra tiene que decir lo mismo que la planilla—. Si ninguno se paga, el
 * monto del tramo que habla por la fila, para que la columna no diga «S/ 0.00».
 */
export function montoMensual(e: Estudio, hoy: string): { monto: number; seEstaPagando: boolean } {
  const pagando = e.tramos.filter((t) => sePagaHoy(t, hoy));
  if (pagando.length === 0) return { monto: Number(e.actual.monto), seEstaPagando: false };
  return { monto: pagando.reduce((t, x) => t + Number(x.monto), 0), seEstaPagando: true };
}

// ── CASILLAS: LA CONSTANCIA DE CADA MES ──────────────────────────────────────

export type EstadoCasilla = "pendiente" | "aprobada" | "rechazada" | "vacia";

export interface Casilla {
  mes: string;
  /** La constancia que habla por el mes; null si no se recibió ninguna. */
  principal: EntregaDeFamilia | null;
  estado: EstadoCasilla;
  /** Cuántas constancias más hay ese mes (una corrección, una matrícula aparte). */
  otras: number;
  /** El estudio no existía todavía ese mes, o ya había terminado. Un hecho de fechas, no una falta. */
  fueraDeVigencia: boolean;
}

/** Pendiente pide acción, aprobada es la que respalda el mes, rechazada es la última opción. */
const PESO_CASILLA: Record<string, number> = { pendiente: 0, aprobada: 1, rechazada: 2 };

/** Las constancias retiradas por la integrante no cuentan como recibidas. */
const cuentaComoRecibida = (e: Entrega): boolean => e.estado !== "retirada";

export function casillasDeEstudio(
  estudio: Estudio,
  entregas: readonly EntregaDeFamilia[],
  meses: readonly string[],
): Casilla[] {
  // Una rechazada que la integrante ya corrigió (otra constancia dice reemplazarla) no habla por su
  // mes aunque la corrección traiga OTRA fecha de pago: quedaría en rojo para siempre.
  const corregidas = new Set(entregas.filter(cuentaComoRecibida).map((e) => e.reemplaza_a).filter((id): id is string => !!id));
  return meses.map((mes) => {
    const delMes = entregas
      .filter((e) => cuentaComoRecibida(e) && mesDe(e.fecha_pago) === mes && !(e.estado === "rechazada" && corregidas.has(e.id)))
      .sort(
        (a, b) =>
          PESO_CASILLA[a.estado] - PESO_CASILLA[b.estado] ||
          b.enviada_at.localeCompare(a.enviada_at) || b.id.localeCompare(a.id),
      );
    const principal = delMes[0] ?? null;
    return {
      mes,
      principal,
      estado: principal ? (principal.estado as EstadoCasilla) : "vacia",
      otras: Math.max(0, delMes.length - 1),
      fueraDeVigencia: !estudio.tramos.some((t) => mesDe(t.vigente_desde) <= mes && mesDe(t.vigente_hasta) >= mes),
    };
  });
}

/**
 * Todas las constancias del estudio, en el orden en que se recorren con las
 * flechas del visor: por mes de pago y, dentro del mes, por envío. Las retiradas
 * van también —quien audita las quiere ver—, marcadas por su propio estado.
 */
export function entregasEnOrden(entregas: readonly EntregaDeFamilia[]): EntregaDeFamilia[] {
  return [...entregas].sort(
    (a, b) => a.fecha_pago.localeCompare(b.fecha_pago) || a.enviada_at.localeCompare(b.enviada_at) || a.id.localeCompare(b.id),
  );
}

/** Los meses en que hay alguna constancia recibida, para decidir hasta dónde llega la línea de tiempo. */
export function mesesConConstancia(entregas: readonly Entrega[]): string[] {
  return Array.from(new Set(entregas.filter(cuentaComoRecibida).map((e) => mesDe(e.fecha_pago)))).sort();
}

// ── FILTROS ──────────────────────────────────────────────────────────────────

export type Tarjeta = "pendientes" | "por_vencer" | "vencidas" | "rechazadas" | "pagos";
export type VigenciaFiltro = "activas" | "terminada" | "todas";
export type QuienEstudia = "" | "trabajador" | "hijo";

export interface Filtros {
  buscar: string;
  sede: string;
  /** "2026-09": estudios con una constancia cuyo pago cae en ese mes. */
  mes: string;
  estado: EstadoConstancia | "";
  institucion: string;
  vigencia: VigenciaFiltro;
  liquidadas: boolean;
  quien: QuienEstudia;
  tipo: TipoConstancia | "";
  revisor: string;
  /** Rango libre de fechas de pago. Excluyente con `mes`: son dos formas de decir lo mismo. */
  desde: string;
  hasta: string;
  tarjeta: Tarjeta | null;
  grupo: GrupoEducacion | null;
}

export const FILTROS_VACIOS: Filtros = {
  buscar: "", sede: "", mes: "", estado: "", institucion: "", vigencia: "activas", liquidadas: false,
  quien: "", tipo: "", revisor: "", desde: "", hasta: "", tarjeta: null, grupo: null,
};

export interface ContextoDeFiltros {
  liquidadas: ReadonlySet<string>;
  familiasConPendiente: ReadonlySet<string>;
  /** null mientras las constancias todavía se están trayendo: los filtros que dependen de ellas no se aplican. */
  entregasPorFamilia: ReadonlyMap<string, EntregaDeFamilia[]> | null;
  /**
   * Los estudios cuyas constancias NO se pudieron leer. Ausentes del mapa no quiere decir «sin
   * constancias»: quiere decir «no se sabe», y un estudio que no se sabe nunca se esconde por un filtro
   * que mira constancias.
   */
  familiasSinLeer: ReadonlySet<string>;
  /** `?persona=<id>`: manda sobre todo lo demás (ADR 0003). */
  personaPedida: string | null;
}

export function entregasDeEstudio(
  e: Estudio,
  porFamilia: ReadonlyMap<string, EntregaDeFamilia[]> | null,
): EntregaDeFamilia[] {
  if (!porFamilia) return [];
  return e.tramos.flatMap((t) => porFamilia.get(t.familia_id) ?? []);
}

/** ¿Hay algún filtro puesto distinto del de siempre? */
export function hayFiltros(f: Filtros): boolean {
  return (Object.keys(FILTROS_VACIOS) as (keyof Filtros)[]).some((k) => f[k] !== FILTROS_VACIOS[k]);
}

/**
 * ¿Esta constancia cumple los filtros que miran constancias (mes, rango de fechas,
 * tipo, quién revisó)? Es la misma pregunta para la lista, el CSV y el ZIP: si cada
 * uno la escribiera aparte, el cuadro descargado dejaría de coincidir con lo que se ve.
 */
export function entregaPasaFiltros(x: Entrega, f: Filtros, ignorar: readonly (keyof Filtros)[] = []): boolean {
  const aplica = (k: keyof Filtros) => !ignorar.includes(k);
  if (aplica("mes") && f.mes && mesDe(x.fecha_pago) !== f.mes) return false;
  if (aplica("desde") && f.desde && x.fecha_pago < f.desde) return false;
  if (aplica("hasta") && f.hasta && x.fecha_pago > f.hasta) return false;
  if (aplica("tipo") && f.tipo && x.tipo !== f.tipo) return false;
  if (aplica("revisor") && f.revisor && x.revisada_por !== f.revisor) return false;
  return true;
}

/**
 * Todos los filtros MENOS los que se piden ignorar. Así cada chip de sede y cada
 * pestaña cuenta lo que mostraría al abrirla: «AQP 3» no puede decir 3 si, al
 * tocarlo, aparecen 2 porque la sede misma se estaba filtrando.
 */
export function pasaFiltros(
  e: Estudio,
  f: Filtros,
  ctx: ContextoDeFiltros,
  ignorar: readonly (keyof Filtros)[] = [],
): boolean {
  const aplica = (k: keyof Filtros) => !ignorar.includes(k);
  if (ctx.personaPedida) return e.persona_id === ctx.personaPedida;
  // Lo que espera la revisión de DO NUNCA se esconde por un valor que nadie eligió: ni «vigentes y por
  // empezar» ni «sin personas liquidadas» son filtros puestos por quien mira, son lo que trae la pantalla.
  // Si una constancia de un estudio terminado o de una persona liquidada queda esperando, tiene que verse.
  const esperaRevision = e.tramos.some((t) => ctx.familiasConPendiente.has(t.familia_id));
  if (!f.liquidadas && ctx.liquidadas.has(e.persona_id) && !esperaRevision) return false;

  if (aplica("tarjeta") && f.tarjeta) {
    const t = e.tramos;
    if (f.tarjeta === "pendientes" && !t.some((x) => ctx.familiasConPendiente.has(x.familia_id))) return false;
    if (f.tarjeta === "por_vencer" && e.estado_constancia !== "por_vencer") return false;
    if (f.tarjeta === "vencidas" && e.estado_constancia !== "vencida") return false;
    if (f.tarjeta === "rechazadas" && e.estado_constancia !== "rechazada") return false;
    if (f.tarjeta === "pagos" && !t.some((x) => x.pago_proximo)) return false;
  }
  if (aplica("buscar") && f.buscar.trim() && !norm(e.persona).includes(norm(f.buscar))) return false;
  if (aplica("sede") && f.sede && e.sede !== f.sede) return false;
  if (aplica("estado") && f.estado && e.estado_constancia !== f.estado) return false;
  if (aplica("institucion") && f.institucion && e.institucion !== f.institucion) return false;
  if (aplica("vigencia")) {
    if (f.vigencia === "activas" && e.vigencia === "terminada" && !esperaRevision) return false;
    if (f.vigencia === "terminada" && e.vigencia !== "terminada") return false;
  }
  if (aplica("quien") && f.quien) {
    const esHijo = e.beneficiario === "hijo";
    if (f.quien === "hijo" && !esHijo) return false;
    if (f.quien === "trabajador" && esHijo) return false;
  }

  // Los que miran dentro de las constancias esperan a que lleguen: sin ellas no
  // se puede decir que un estudio NO cumple, así que no se esconde a nadie.
  const sinLeer = e.tramos.some((t) => ctx.familiasSinLeer.has(t.familia_id));
  if (ctx.entregasPorFamilia && !sinLeer && (["mes", "tipo", "revisor", "desde", "hasta"] as const).some((k) => aplica(k) && f[k])) {
    // UNA MISMA constancia tiene que cumplirlo todo: «matrícula en setiembre» no se
    // cumple con una matrícula de agosto y una cuota de setiembre.
    const mias = entregasDeEstudio(e, ctx.entregasPorFamilia).filter(cuentaComoRecibida);
    if (!mias.some((x) => entregaPasaFiltros(x, f, ignorar))) return false;
  }

  if (aplica("grupo") && f.grupo && f.grupo !== "sin_solicitar" && grupoDeEstudio(e) !== f.grupo) return false;
  return true;
}

// ── CONTEOS Y SEDES ──────────────────────────────────────────────────────────

export interface ConteoTarjetas {
  pendientes: number;
  por_vencer: number;
  vencidas: number;
  rechazadas: number;
  pagos: number;
  sinCalendario: number;
}

/** Las cinco tarjetas de arriba, contadas sobre las MISMAS filas que se dibujan. */
export function conteoTarjetas(estudios: readonly Estudio[], familiasConPendiente: ReadonlySet<string>): ConteoTarjetas {
  const c: ConteoTarjetas = { pendientes: 0, por_vencer: 0, vencidas: 0, rechazadas: 0, pagos: 0, sinCalendario: 0 };
  for (const e of estudios) {
    if (e.tramos.some((t) => familiasConPendiente.has(t.familia_id))) c.pendientes += 1;
    if (e.estado_constancia === "por_vencer") c.por_vencer += 1;
    if (e.estado_constancia === "vencida") c.vencidas += 1;
    if (e.estado_constancia === "rechazada") c.rechazadas += 1;
    if (e.tramos.some((t) => t.pago_proximo)) c.pagos += 1;
    if (e.estado_constancia === "sin_calendario" && e.vigencia !== "terminada") c.sinCalendario += 1;
  }
  return c;
}

export interface ResumenDeSede {
  sede: string;
  estudios: Estudio[];
  personas: number;
  /** Estudios con algo que se está pagando hoy. */
  pagando: number;
  /** Lo que suman al mes los estudios que se pagan hoy. */
  montoMensual: number;
  porRevisar: number;
  vencidas: number;
  rechazadas: number;
}

/**
 * Una sede por bloque, de la A a la Z por código. El orden no se escribe a mano
 * (regla 3 de CLAUDE.md: las sedes salen de los datos); el alfabético es el único
 * que no inventa una jerarquía entre sedes.
 */
export function resumenPorSede(
  estudios: readonly Estudio[],
  hoy: string,
  familiasConPendiente: ReadonlySet<string>,
): ResumenDeSede[] {
  const porSede = new Map<string, Estudio[]>();
  for (const e of estudios) {
    const l = porSede.get(e.sede);
    if (l) l.push(e); else porSede.set(e.sede, [e]);
  }
  return [...porSede.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([sede, lista]) => {
      const m = lista.map((e) => montoMensual(e, hoy));
      return {
        sede,
        estudios: lista,
        personas: new Set(lista.map((e) => e.persona_id)).size,
        pagando: m.filter((x) => x.seEstaPagando).length,
        montoMensual: m.filter((x) => x.seEstaPagando).reduce((t, x) => t + x.monto, 0),
        porRevisar: lista.filter((e) => e.tramos.some((t) => familiasConPendiente.has(t.familia_id))).length,
        vencidas: lista.filter((e) => e.estado_constancia === "vencida").length,
        rechazadas: lista.filter((e) => e.estado_constancia === "rechazada").length,
      };
    });
}

/** Las sedes que existen, de los datos: nunca una lista escrita a mano. */
export const sedesDe = (estudios: readonly Estudio[]): string[] =>
  Array.from(new Set(estudios.map((e) => e.sede))).sort((a, b) => a.localeCompare(b));

// ── EL ENLACE: toda la pantalla cabe en la dirección ─────────────────────────

/**
 * Los filtros que viajan en la dirección. NO viajan la búsqueda de texto ni las
 * tarjetas/pestañas: lo primero es de esta visita (ver `use-filtro-guardado.ts`,
 * que dice por qué), y lo segundo es una forma de mirar, no un recorte de datos.
 * Sí viajan los que definen QUÉ conjunto se está mirando, para poder pasarle a
 * alguien «las constancias de AQP en setiembre» como un enlace.
 */
const CLAVES_EN_URL = [
  "sede", "mes", "estado", "institucion", "vigencia", "quien", "tipo", "revisor", "desde", "hasta", "grupo",
] as const satisfies readonly (keyof Filtros)[];

/** Todo lo que `filtrosAUrl` puede escribir, para que la pantalla borre lo suyo sin tocar `?persona=` y compañía. */
export const CLAVES_DE_URL: readonly string[] = [...CLAVES_EN_URL, "liquidadas"];

const ESTADOS_VALIDOS = ["pendiente_revision", "rechazada", "sin_calendario", "al_dia", "vencida", "por_vencer", "falta_enviar"];
const GRUPOS_VALIDOS = ["al_dia", "por_revisar", "por_completar", "en_falta", "sin_solicitar"];

export function filtrosAUrl(f: Filtros): string {
  const p = new URLSearchParams();
  for (const k of CLAVES_EN_URL) {
    const v = f[k];
    if (v && v !== FILTROS_VACIOS[k]) p.set(k, String(v));
  }
  if (f.liquidadas) p.set("liquidadas", "1");
  return p.toString();
}

/** Lee lo que `filtrosAUrl` escribió, descartando lo que ya no tiene sentido (un estado que no existe). */
export function filtrosDeUrl(p: { get(k: string): string | null }): Filtros {
  const f: Filtros = { ...FILTROS_VACIOS };
  f.sede = p.get("sede") ?? "";
  const mes = p.get("mes") ?? "";
  f.mes = /^\d{4}-(0[1-9]|1[0-2])$/.test(mes) ? mes : "";
  const estado = p.get("estado") ?? "";
  f.estado = ESTADOS_VALIDOS.includes(estado) ? (estado as EstadoConstancia) : "";
  f.institucion = p.get("institucion") ?? "";
  const vig = p.get("vigencia");
  f.vigencia = vig === "terminada" || vig === "todas" ? vig : "activas";
  const quien = p.get("quien");
  f.quien = quien === "hijo" || quien === "trabajador" ? quien : "";
  const tipo = p.get("tipo") ?? "";
  f.tipo = (TIPOS_CONSTANCIA as readonly string[]).includes(tipo) ? (tipo as TipoConstancia) : "";
  f.revisor = p.get("revisor") ?? "";
  const fecha = (k: string) => (/^\d{4}-\d{2}-\d{2}$/.test(p.get(k) ?? "") ? (p.get(k) as string) : "");
  f.desde = fecha("desde");
  f.hasta = fecha("hasta");
  // `mes` y el rango libre son excluyentes: si el enlace trae los dos, manda el mes.
  if (f.mes) { f.desde = ""; f.hasta = ""; }
  const grupo = p.get("grupo") ?? "";
  f.grupo = GRUPOS_VALIDOS.includes(grupo) ? (grupo as GrupoEducacion) : null;
  f.liquidadas = p.get("liquidadas") === "1";
  return f;
}
