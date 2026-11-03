// ============================================================================
// metas-cobertura.ts — la meta de cobertura por rangos de hora (0590)
// ============================================================================
// PROMETE: a partir de lo que devuelve `fn_metas_cobertura` (la meta que rige
//          cada fecha, ya resuelta en la base: la excepción más corta o la
//          predeterminada), contestar qué piden un día y una hora —personal y
//          líderes—, armar una meta desde lo que pide la venta (el sugerido) y
//          comparar las dos hora por hora.
// ASUME:   que la base ya eligió qué meta rige (aquí no se vuelve a decidir), y
//          que «lo que pide la venta» lo calcula `ventaPedia` (repeticion.ts,
//          compras ÷ ritmo con su mínimo, 0585).
// REGLA (Felipe, 2026-11-03): manda la meta. `null` = sin meta → manda lo que
//          pide la venta; `0` = aquí no se exige a nadie.
// NO HACE: leer la base ni pintar nada.
// ============================================================================

export interface RangoMeta {
  /** Hora de inicio en decimal (9.5 = 09:30). */
  desde: number;
  /** Hora de fin en decimal, sin incluir (24 = fin del día). */
  hasta: number;
  /** Personal que pide; null = sin meta (manda lo que pide la venta). */
  personal: number | null;
  /** Líderes que pide; null = sin meta. */
  lideres: number | null;
}

export interface MetaDelDia {
  fecha: string;
  rangos: RangoMeta[];
  /** De qué meta sale: la predeterminada o una excepción con su nombre. null si ese día no hay meta. */
  origen: { id: string; nombre: string; predeterminada: boolean } | null;
}

/** Una fila de fn_metas_cobertura. */
export interface FilaMeta {
  sede_id: string;
  fecha: string;
  desde_min: number;
  hasta_min: number;
  personal: number | null;
  lideres: number | null;
  periodo_id: string;
  periodo_nombre: string;
  es_predeterminada: boolean;
}

/** Las filas de fn_metas_cobertura de UNA sede → la meta de cada fecha. */
export function metasPorFecha(filas: readonly FilaMeta[]): Map<string, MetaDelDia> {
  const m = new Map<string, MetaDelDia>();
  for (const f of filas) {
    const dia = m.get(f.fecha) ?? {
      fecha: f.fecha, rangos: [],
      origen: { id: f.periodo_id, nombre: f.periodo_nombre, predeterminada: f.es_predeterminada },
    };
    dia.rangos.push({ desde: f.desde_min / 60, hasta: f.hasta_min / 60, personal: f.personal ?? null, lideres: f.lideres ?? null });
    m.set(f.fecha, dia);
  }
  for (const d of m.values()) d.rangos.sort((a, b) => a.desde - b.desde);
  return m;
}

/** El rango que rige a la hora decimal `h` (desde ≤ h < hasta), o null. */
export function rangoEn(rangos: readonly RangoMeta[], h: number): RangoMeta | null {
  return rangos.find((r) => r.desde <= h + 1e-9 && h < r.hasta - 1e-9) ?? null;
}

/** Cuánto personal pide la meta a la hora `h`: un número (0 incluido) o null si no hay meta ahí. */
export const personalEn = (rangos: readonly RangoMeta[], h: number): number | null => rangoEn(rangos, h)?.personal ?? null;

/** Cuántos líderes pide la meta a la hora `h`, o null. */
export const lideresEn = (rangos: readonly RangoMeta[], h: number): number | null => rangoEn(rangos, h)?.lideres ?? null;

/**
 * Lo que manda a la hora `h`: la meta si la hay (aunque sea 0); si no, lo que
 * pide la venta (`sugerido`, null si la sede no vende o no se pudo leer).
 */
export function pideEn(rangos: readonly RangoMeta[], h: number, sugerido: number | null): { n: number | null; de: "meta" | "venta" | null } {
  const meta = personalEn(rangos, h);
  if (meta !== null) return { n: meta, de: "meta" };
  if (sugerido !== null) return { n: sugerido, de: "venta" };
  return { n: null, de: null };
}

/** El mayor número de líderes que pide el día (para lo que todavía mide «un líder en piso» por día). */
export function lideresDelDia(rangos: readonly RangoMeta[]): number {
  return Math.max(0, ...rangos.map((r) => r.lideres ?? 0));
}

/** Las filas de varias sedes → sede → fecha → su meta. */
export function metasPorSedeYFecha(filas: readonly FilaMeta[]): Map<string, Map<string, MetaDelDia>> {
  const porSede = new Map<string, FilaMeta[]>();
  for (const f of filas) porSede.set(f.sede_id, [...(porSede.get(f.sede_id) ?? []), f]);
  return new Map([...porSede].map(([sede, fs]) => [sede, metasPorFecha(fs)]));
}

export const CORTE_MANANA_TARDE = 14.25; // 14:15, el corte de la 0039

/**
 * La meta de un día dicha como la decía la 0039 —mañana, tarde y líderes—, para
 * las pantallas que todavía cuentan así (Dashboard, Reporte de sede): el mayor
 * personal de los rangos que tocan la mañana y el de los que tocan la tarde. Sin
 * meta = 0, como antes.
 */
export function mananaTarde(rangos: readonly RangoMeta[]): { manana: number; tarde: number; lideres: number } {
  const max = (xs: (number | null)[]) => Math.max(0, ...xs.map((x) => x ?? 0));
  return {
    manana: max(rangos.filter((r) => r.desde < CORTE_MANANA_TARDE).map((r) => r.personal)),
    tarde: max(rangos.filter((r) => r.hasta > CORTE_MANANA_TARDE).map((r) => r.personal)),
    lideres: lideresDelDia(rangos),
  };
}

export interface HoraComparada {
  hora: number;
  meta: number | null;
  sugerido: number | null;
  /** meta − sugerido, si están los dos. */
  diferencia: number | null;
}

/** Hora por hora, entre `abre` y `cierra` (enteras): la meta, lo que pide la venta y la diferencia. */
export function compararHoraPorHora(
  rangos: readonly RangoMeta[],
  sugeridoDe: (hora: number) => number | null,
  abre: number,
  cierra: number,
): HoraComparada[] {
  const horas: HoraComparada[] = [];
  for (let h = Math.floor(abre); h < Math.ceil(cierra); h++) {
    // La meta de la hora es la del peor momento: si un rango cambia a media hora, el mayor.
    const enLaHora = [h, h + 0.25, h + 0.5, h + 0.75].map((x) => personalEn(rangos, x));
    const definidas = enLaHora.filter((x): x is number => x !== null);
    const meta = definidas.length ? Math.max(...definidas) : null;
    const sugerido = sugeridoDe(h);
    horas.push({ hora: h, meta, sugerido, diferencia: meta !== null && sugerido !== null ? meta - sugerido : null });
  }
  return horas;
}

/**
 * Una meta armada desde lo que pide la venta: las horas seguidas que piden lo
 * mismo se juntan en un rango. Los líderes se dejan como estaban en la meta de
 * ese día (la venta no dice cuántos líderes hacen falta); si no había, sin meta.
 */
export function rangosDesdeSugerido(
  sugeridoDe: (hora: number) => number | null,
  abre: number,
  cierra: number,
  lideresDe: (hora: number) => number | null = () => null,
): RangoMeta[] {
  const rangos: RangoMeta[] = [];
  for (let h = Math.floor(abre); h < Math.ceil(cierra); h++) {
    const n = sugeridoDe(h);
    if (n === null) continue;
    const l = lideresDe(h);
    const ultimo = rangos[rangos.length - 1];
    if (ultimo && ultimo.hasta === h && ultimo.personal === n && ultimo.lideres === l) ultimo.hasta = h + 1;
    else rangos.push({ desde: h, hasta: h + 1, personal: n, lideres: l });
  }
  return rangos;
}

/** ¿Se cruzan dos rangos de la lista? (La base lo impide igual; esto es para decirlo antes de guardar.) */
export function problemaDeRangos(rangos: readonly RangoMeta[]): string | null {
  const orden = [...rangos].sort((a, b) => a.desde - b.desde);
  for (const r of orden) {
    if (!(r.hasta > r.desde)) return "Un rango termina antes de empezar.";
    if (r.desde < 0 || r.hasta > 24) return "Un rango se sale del día.";
    if ((r.personal ?? 0) < 0 || (r.lideres ?? 0) < 0) return "No se piden números negativos.";
  }
  for (let i = 1; i < orden.length; i++) {
    if (orden[i].desde < orden[i - 1].hasta - 1e-9) return `Dos rangos se cruzan a las ${hhmm(orden[i].desde)}.`;
  }
  return null;
}

export const hhmm = (dec: number): string => {
  const h = Math.floor(dec + 1e-9);
  return `${String(h).padStart(2, "0")}:${String(Math.round((dec - h) * 60)).padStart(2, "0")}`;
};

/** Para guardar: la forma que pide fn_guardar_meta_cobertura. */
export function rangosParaGuardar(porDia: ReadonlyMap<number, readonly RangoMeta[]>) {
  return [...porDia].flatMap(([dia, rangos]) => rangos.map((r) => ({
    dia, desde_min: Math.round(r.desde * 60), hasta_min: Math.round(r.hasta * 60), personal: r.personal, lideres: r.lideres,
  })));
}
