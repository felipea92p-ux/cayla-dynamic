/**
 * LAS CONSTANCIAS DE EDUCACIÓN SE TRAEN POR MESES — la mitad pura de la carga.
 *
 * PROMETE: que la pantalla de Educación pida solo los meses que necesita —los que dibuja, los que pide
 *   un filtro o una descarga, y la historia entera solo del estudio que se abre en el visor—, en UNA
 *   consulta por tramo de meses y no una por estudio, y que lo ya traído no se vuelva a pedir.
 * ASUME: lee `educacion_entregas` directo, con sus tablas hijas incrustadas. El permiso lo pone la base
 *   igual que en `fn_educacion_entregas` (0525): las políticas de lectura de `educacion_entregas`,
 *   `asignaciones_educacion`, `educacion_entrega_archivos` y `educacion_entrega_meses` piden lo mismo
 *   que esa función —`fn_es_admin_o_lider()` o que sea de la persona—, así que se ven exactamente las
 *   mismas filas. Lo único que la función agrega es el NOMBRE de quien envió, revisó, aprobó y
 *   revirtió, y solo para DO; esta pantalla es de DO (`puedeVerPlanilla`) y la política de `personas`
 *   deja a DO leerlos.
 * NO HACE: no habla con Supabase (eso es `use-constancias-por-meses.ts`), no decide qué dice cada
 *   casilla (`educacion-meses.ts`) ni calcula estados (la base).
 *
 * ── POR QUÉ YA NO SE PIDE `fn_educacion_entregas` EN LA CUADRÍCULA ─────────
 * Se pide por estudio, con TODA su historia. Medido el 2026-10-17 en la base local con 60 estudios de
 * 18 meses: al abrir, 60 peticiones y 1 077 constancias (~812 KB) para dibujar seis columnas. Pedirla
 * por meses habría exigido una función nueva —y pegarla antes de fusionar—; la tabla, con las mismas
 * políticas, ya lo permite con filtros de rango: una petición de 348 constancias para esos seis meses.
 * La función sigue siendo la del panel de cada estudio y la de «Lo mío».
 *
 * ── UN MES ESTÁ «TRAÍDO» CUANDO ESTÁN TODAS LAS CONSTANCIAS QUE HABLAN DE ÉL ──
 * · las pagadas ese mes (`fecha_pago`), y
 * · las adelantadas que lo CUBREN aunque se pagaran antes (`cubre_desde`/`cubre_hasta`, 0529): un pago
 *   del 28 de julio que cubre agosto a diciembre habla de noviembre.
 * Las dos van en el mismo `or` (`filtroDelRango`). Cada adelantada trae TODOS sus meses cubiertos, no
 * solo los del tramo: la franja dice «ago–dic, S/ X de S/ total» y con la mitad de las filas mentiría.
 * Y cada rechazada trae si otra constancia ya la corrigió (`corregida`), porque la corrección puede
 * traer fecha de OTRO mes, todavía sin traer, y la rechazada quedaría en rojo.
 *
 * SE ROMPE SI: `fn_educacion_entregas` cambia lo que devuelve y `entregaDeFila` no (el visor diría
 * otra cosa que el panel del estudio), o si se toca la política de lectura de una de esas tablas sin
 * mirar esta pantalla.
 */

import type { EstadoEntrega, MotivoRechazo, TipoConstancia } from "@cayla-dynamic/shared";
import type { CoberturaMes, Filtros } from "./educacion-meses";
import { mesDe, sumarMeses } from "./educacion-meses";
import type { Entrega, EntregaDeFamilia } from "./educacion-tipos";

// ── TRAMOS DE MESES ──────────────────────────────────────────────────────────

/** Un tramo de meses, con los dos extremos adentro: «2026-05» a «2026-10». */
export interface RangoDeMeses {
  desde: string;
  hasta: string;
}

/** Los extremos abiertos: «desde el 1/7» no tiene techo; «tipo: matrícula» mira toda la historia. */
export const SIN_PISO = "0000-01";
export const SIN_TECHO = "9999-12";
export const TODA_LA_HISTORIA: RangoDeMeses = { desde: SIN_PISO, hasta: SIN_TECHO };

// `sumarMeses` sobre un extremo abierto daría «10000-01», que como texto va ANTES de «9999-12».
const tras = (m: string): string => (m >= SIN_TECHO ? SIN_TECHO : sumarMeses(m, 1));
const antes = (m: string): string => (m <= SIN_PISO ? SIN_PISO : sumarMeses(m, -1));

/** Los tramos ordenados, sin solaparse: dos que se tocan («ene–mar» y «abr–jun») son uno solo. */
export function unirRangos(rangos: readonly RangoDeMeses[]): RangoDeMeses[] {
  const orden = rangos.filter((r) => r.desde <= r.hasta).sort((a, b) => a.desde.localeCompare(b.desde));
  const unidos: RangoDeMeses[] = [];
  for (const r of orden) {
    const ultimo = unidos[unidos.length - 1];
    if (ultimo && r.desde <= tras(ultimo.hasta)) {
      if (r.hasta > ultimo.hasta) ultimo.hasta = r.hasta;
    } else {
      unidos.push({ ...r });
    }
  }
  return unidos;
}

/** Lo que falta traer de `pedido`, sabiendo lo ya traído: cero, uno o varios tramos. */
export function rangosQueFaltan(traidos: readonly RangoDeMeses[], pedido: RangoDeMeses): RangoDeMeses[] {
  const faltan: RangoDeMeses[] = [];
  let desde = pedido.desde;
  for (const r of unirRangos(traidos)) {
    if (r.hasta < desde) continue;
    if (r.desde > pedido.hasta) break;
    if (r.desde > desde) faltan.push({ desde, hasta: antes(r.desde) });
    if (r.hasta >= pedido.hasta) return faltan;
    desde = tras(r.hasta);
  }
  if (desde <= pedido.hasta) faltan.push({ desde, hasta: pedido.hasta });
  return faltan;
}

export const rangoCubierto = (traidos: readonly RangoDeMeses[], pedido: RangoDeMeses): boolean =>
  rangosQueFaltan(traidos, pedido).length === 0;

export const mesCubierto = (traidos: readonly RangoDeMeses[], mes: string): boolean =>
  traidos.some((r) => r.desde <= mes && mes <= r.hasta);

/**
 * Qué meses de constancias hacen falta para aplicar los filtros que miran constancias (`pasaFiltros`).
 * null: ninguno puesto. «Matrícula» o «quién revisó» sin fecha miran toda la historia, y entonces se
 * trae entera: es lo que se pidió, y un filtro que mirara solo lo cargado escondería a quien no debe.
 */
export function rangoDeLosFiltros(f: Pick<Filtros, "mes" | "desde" | "hasta" | "tipo" | "revisor">): RangoDeMeses | null {
  if (f.mes) return { desde: f.mes, hasta: f.mes };
  if (f.desde || f.hasta) return { desde: f.desde ? mesDe(f.desde) : SIN_PISO, hasta: f.hasta ? mesDe(f.hasta) : SIN_TECHO };
  if (f.tipo || f.revisor) return TODA_LA_HISTORIA;
  return null;
}

/**
 * El `or` de PostgREST que trae un tramo: las pagadas dentro, o las adelantadas que cubren algún mes de
 * él. null = toda la historia, sin filtro. Una constancia que no es adelantada tiene `cubre_*` en null,
 * y la comparación con null nunca es verdadera: solo entra por su fecha de pago.
 */
export function filtroDelRango(r: RangoDeMeses): string | null {
  const pagadas: string[] = [];
  const cubiertas: string[] = [];
  if (r.desde !== SIN_PISO) {
    pagadas.push(`fecha_pago.gte.${r.desde}-01`);
    cubiertas.push(`cubre_hasta.gte.${r.desde}-01`);
  }
  if (r.hasta !== SIN_TECHO) {
    pagadas.push(`fecha_pago.lt.${sumarMeses(r.hasta, 1)}-01`);
    cubiertas.push(`cubre_desde.lte.${r.hasta}-01`);
  }
  if (pagadas.length === 0) return null;
  return `and(${pagadas.join(",")}),and(${cubiertas.join(",")})`;
}

// ── UNA FILA DE LA TABLA → UNA CONSTANCIA COMO LA DEVUELVE `fn_educacion_entregas` ─

const NOMBRE = "nombres,apellidos";

/** Lo que se pide de cada constancia. Las mismas columnas que `fn_educacion_entregas` (0525), más lo de 0529. */
export const SELECT_CONSTANCIAS = [
  "id,asignacion_id,fecha_pago,tipo,proxima_fecha_pago,nota,estado,origen,enviada_at,revisada_at,retirada_at",
  "motivo_categoria,motivo_comentario,reemplaza_a,aprobada_at,aprobacion_revertida_at",
  // `!inner` para poder pedir por estudio (`asignacion.familia_id`), igual que el `join` de la función.
  "asignacion:asignaciones_educacion!inner(familia_id)",
  "archivos:educacion_entrega_archivos(id,storage_path,nombre,tipo_mime,bytes,orden)",
  "meses:educacion_entrega_meses(mes,monto,origen,motivo)",
  `enviador:personas!educacion_entregas_enviada_por_fkey(${NOMBRE})`,
  `revisor:personas!educacion_entregas_revisada_por_fkey(${NOMBRE})`,
  `aprobador:personas!educacion_entregas_aprobada_por_fkey(${NOMBRE})`,
  `revertidor:personas!educacion_entregas_aprobacion_revertida_por_fkey(${NOMBRE})`,
  // Las constancias que dicen reemplazar a esta (la misma tabla, por `reemplaza_a`).
  "correcciones:educacion_entregas!reemplaza_a(estado)",
].join(",");

interface Nombre { nombres: string; apellidos: string }

/** Una fila tal como llega de `SELECT_CONSTANCIAS`. */
export interface FilaDeConstancia {
  id: string;
  asignacion_id: string;
  fecha_pago: string;
  tipo: TipoConstancia;
  proxima_fecha_pago: string | null;
  nota: string | null;
  estado: EstadoEntrega;
  origen: Entrega["origen"];
  enviada_at: string;
  revisada_at: string | null;
  retirada_at: string | null;
  motivo_categoria: MotivoRechazo | null;
  motivo_comentario: string | null;
  reemplaza_a: string | null;
  aprobada_at: string | null;
  aprobacion_revertida_at: string | null;
  asignacion: { familia_id: string } | null;
  archivos: { id: string; storage_path: string; nombre: string; tipo_mime: string | null; bytes: number | null; orden: number }[] | null;
  meses: { mes: string; monto: number; origen: CoberturaMes["origen"]; motivo: string | null }[] | null;
  enviador: Nombre | null;
  revisor: Nombre | null;
  aprobador: Nombre | null;
  revertidor: Nombre | null;
  correcciones: { estado: string }[] | null;
}

const nombre = (p: Nombre | null): string | null => (p ? `${p.nombres} ${p.apellidos}` : null);

/**
 * La fila, con la forma de `fn_educacion_entregas`: los nombres como «Nombres Apellidos», los archivos
 * por `orden` y luego `id`. Aparte, los meses que cubre (si es adelantada) y si ya la corrigieron.
 */
export function constanciaDeFila(f: FilaDeConstancia): { entrega: EntregaDeFamilia; meses: CoberturaMes[]; corregida: boolean } {
  const familia_id = f.asignacion?.familia_id ?? "";
  const entrega: EntregaDeFamilia = {
    id: f.id, asignacion_id: f.asignacion_id, familia_id, fecha_pago: f.fecha_pago, tipo: f.tipo,
    proxima_fecha_pago: f.proxima_fecha_pago, nota: f.nota, estado: f.estado, origen: f.origen,
    enviada_at: f.enviada_at, enviada_por: nombre(f.enviador),
    revisada_at: f.revisada_at, revisada_por: nombre(f.revisor),
    retirada_at: f.retirada_at, motivo_categoria: f.motivo_categoria, motivo_comentario: f.motivo_comentario,
    reemplaza_a: f.reemplaza_a,
    archivos: [...(f.archivos ?? [])]
      .sort((a, b) => a.orden - b.orden || a.id.localeCompare(b.id))
      .map((a) => ({ id: a.id, ruta: a.storage_path, nombre: a.nombre, tipo_mime: a.tipo_mime, bytes: a.bytes })),
    aprobada_at: f.aprobada_at, aprobada_por: nombre(f.aprobador),
    revertida_at: f.aprobacion_revertida_at, revertida_por: nombre(f.revertidor),
  };
  const meses = [...(f.meses ?? [])]
    .sort((a, b) => a.mes.localeCompare(b.mes))
    .map((m) => ({ entrega_id: f.id, familia_id, mes: m.mes, monto: Number(m.monto), origen: m.origen, motivo: m.motivo }));
  const corregida = f.estado === "rechazada" && (f.correcciones ?? []).some((c) => c.estado !== "retirada");
  return { entrega, meses, corregida };
}

// ── LO YA TRAÍDO ─────────────────────────────────────────────────────────────

export interface ConstanciasTraidas {
  entregas: ReadonlyMap<string, EntregaDeFamilia>;
  /** Los meses que cubre cada adelantada, por id de constancia. */
  coberturas: ReadonlyMap<string, readonly CoberturaMes[]>;
  /** Las rechazadas que otra constancia (no retirada) ya corrigió. */
  corregidas: ReadonlySet<string>;
  /** Los tramos de meses traídos enteros. */
  rangos: readonly RangoDeMeses[];
  /** Los estudios (familias) con TODA su historia traída: los que se abrieron en el visor. */
  familias: ReadonlySet<string>;
}

export const NADA_TRAIDO: ConstanciasTraidas = {
  entregas: new Map(), coberturas: new Map(), corregidas: new Set(), rangos: [], familias: new Set(),
};

/**
 * Suma filas recién llegadas a lo ya traído. Una constancia que ya estaba se REEMPLAZA: la nueva es la
 * que dice cómo está ahora (alguien la aprobó entre una consulta y otra). `que` dice qué quedó completo.
 */
export function sumarConstancias(
  t: ConstanciasTraidas,
  filas: readonly FilaDeConstancia[],
  que: { rango?: RangoDeMeses; familias?: readonly string[] },
): ConstanciasTraidas {
  const entregas = new Map(t.entregas);
  const coberturas = new Map(t.coberturas);
  const corregidas = new Set(t.corregidas);
  for (const fila of filas) {
    const { entrega, meses, corregida } = constanciaDeFila(fila);
    entregas.set(entrega.id, entrega);
    if (meses.length > 0) coberturas.set(entrega.id, meses); else coberturas.delete(entrega.id);
    if (corregida) corregidas.add(entrega.id); else corregidas.delete(entrega.id);
  }
  return {
    entregas, coberturas, corregidas,
    rangos: que.rango ? unirRangos([...t.rangos, que.rango]) : t.rangos,
    familias: que.familias ? new Set([...t.familias, ...que.familias]) : t.familias,
  };
}

/** ¿Está toda la historia de este estudio? La del visor, o porque ya se trajo TODA la historia. */
export const familiaCompleta = (t: ConstanciasTraidas, familia: string): boolean =>
  t.familias.has(familia) || rangoCubierto(t.rangos, TODA_LA_HISTORIA);

/** Por estudio, en el orden de `fn_educacion_entregas`: pago más reciente primero, luego envío, luego id. */
export function constanciasPorFamilia(t: ConstanciasTraidas): Map<string, EntregaDeFamilia[]> {
  const porFamilia = new Map<string, EntregaDeFamilia[]>();
  for (const e of t.entregas.values()) {
    const l = porFamilia.get(e.familia_id);
    if (l) l.push(e); else porFamilia.set(e.familia_id, [e]);
  }
  for (const l of porFamilia.values()) {
    l.sort((a, b) => b.fecha_pago.localeCompare(a.fecha_pago) || b.enviada_at.localeCompare(a.enviada_at) || b.id.localeCompare(a.id));
  }
  return porFamilia;
}

/** El tramo de meses de una ventana: del primero al último que se dibuja. */
export const rangoDeLaVentana = (meses: readonly string[]): RangoDeMeses | null =>
  meses.length > 0 ? { desde: meses[0], hasta: meses[meses.length - 1] } : null;

/** «may 2026 a oct 2026», para decir qué no se pudo traer. */
export function textoDelRango(r: RangoDeMeses, mesLargo: (m: string) => string): string {
  if (r.desde === SIN_PISO && r.hasta === SIN_TECHO) return "toda la historia";
  if (r.desde === SIN_PISO) return `hasta ${mesLargo(r.hasta)}`;
  if (r.hasta === SIN_TECHO) return `desde ${mesLargo(r.desde)}`;
  return r.desde === r.hasta ? mesLargo(r.desde) : `${mesLargo(r.desde)} a ${mesLargo(r.hasta)}`;
}

// ── PÁGINAS ──────────────────────────────────────────────────────────────────

/** Lo que devuelve un pedido de una página: el builder de supabase-js, que es «thenable». */
export type Pagina<T> = PromiseLike<{ data: T[] | null; error: { message: string } | null; count?: number | null }>;

/** Filas por página: el `max_rows` de Supabase. Si el de la base fuera menor, el conteo lo nota. */
export const FILAS_POR_PAGINA = 1000;

/**
 * Todas las filas de un pedido, página por página. PostgREST corta cada respuesta en `max_rows` SIN
 * avisar: medido el 2026-10-17, una consulta de 1 077 constancias devolvió 1 000 con un `200` y nada
 * más. Una pantalla con muchas personas pasaría ese número en un solo tramo de seis meses, y las que
 * faltaran se dibujarían como «sin constancia». Por eso la primera página pide el conteo exacto y se
 * sigue pidiendo hasta llegar a él. null = alguna página falló: «no se sabe», nunca «no hay».
 */
export async function todasLasPaginas<T>(
  pedir: (desde: number, hasta: number) => Pagina<T>,
  porPagina = FILAS_POR_PAGINA,
): Promise<T[] | null> {
  const filas: T[] = [];
  let total: number | null = null;
  for (;;) {
    const { data, error, count } = await pedir(filas.length, filas.length + porPagina - 1);
    if (error) return null;
    if (total === null) total = count ?? null;
    const pagina = data ?? [];
    filas.push(...pagina);
    // Sin conteo, se para con la primera página incompleta. Con conteo, solo al llegar al total.
    if (pagina.length === 0 || (total === null ? pagina.length < porPagina : filas.length >= total)) return filas;
  }
}
