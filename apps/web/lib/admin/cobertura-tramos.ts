// ============================================================================
// cobertura-tramos.ts — «Mañana 2 de 3», «Tarde completo»: la cobertura de un día por tramo
// ============================================================================
// QUÉ PROMETE   · contestar, para un tramo del día (mañana: hasta las 14:15; tarde: desde las 14:15), cuántas personas lo
//                 cubren, contra cuántas pide la meta, y en qué estado queda: falta N · completo · sobra N · sin meta.
//                 Es lo que Turnos dice primero; la hora por hora queda debajo, a pedido.
// QUÉ ASUME     · que los turnos que llegan ya son los de UN grupo medido (las operativas, o los líderes): quién cuenta
//                 como qué se decide en `cobertura-equipo.ts`, no acá. Y que una persona «es del tramo» si trabaja
//                 al menos `HORAS_MINIMAS_EN_TRAMO` horas dentro de él — quien solo pasa media hora por la tarde no
//                 cubre la tarde.
// POR QUÉ AMBAS · el conteo de personas es lo que se entiende («2 de 3»), pero puede decir «completo» con un hueco de
//                 una hora en medio (tres personas, ninguna a las 12). Por eso, con el número ya completo, se mira
//                 además media hora por media hora: si EN MEDIO de lo cubierto hay menos gente que la meta, el tramo
//                 dice «con huecos» y no «completo». Las entradas escalonadas (una persona llega antes que otra) se
//                 toleran: sin eso casi todo tramo diría «con huecos» y el aviso se aprende a ignorar. Un «completo» que luego no se confirma hora por hora enseña a
//                 no creerle a la pantalla.
// QUÉ NO HACE   · no mide a quien no tiene meta puesta (dice «sin meta», nunca rojo ni verde) y no decide nada: avisa.
// ============================================================================

/** El corte entre mañana y tarde: las 14:15. Lo mismo que `CORTE_TARDE` de la pantalla de Turnos y de la meta. */
export const CORTE_TRAMO = 14.25;
/** Horas dentro del tramo para contar como persona de ese tramo. */
export const HORAS_MINIMAS_EN_TRAMO = 3;

export type Tramo = "manana" | "tarde";
export type EstadoTramo = "sin_meta" | "falta" | "completo" | "con_huecos" | "sobra";

export interface TurnoDecimal {
  id: string;
  /** Hora de entrada en decimal (9.5 = 09:30). */
  entrada: number;
  /** Hora de salida en decimal. */
  salida: number;
}

export interface ResumenTramo {
  /** Quiénes cuentan en el tramo (≥ 3 h dentro de él). */
  gente: TurnoDecimal[];
  n: number;
  meta: number;
  estado: EstadoTramo;
  /** Cuántas personas faltan (solo si `estado` es «falta»). */
  faltan: number;
  /** Cuántas sobran (solo si `estado` es «sobra»). */
  sobran: number;
}

export function limitesDelTramo(tramo: Tramo, inicioDia: number, finDia: number): [number, number] {
  return tramo === "manana" ? [inicioDia, CORTE_TRAMO] : [CORTE_TRAMO, finDia];
}

/** Horas que el turno pasa dentro de [desde, hasta]. */
export function horasEnTramo(t: TurnoDecimal, desde: number, hasta: number): number {
  return Math.max(0, Math.min(t.salida, hasta) - Math.max(t.entrada, desde));
}

export function personasDelTramo(turnos: TurnoDecimal[], tramo: Tramo, inicioDia: number, finDia: number): TurnoDecimal[] {
  const [a, b] = limitesDelTramo(tramo, inicioDia, finDia);
  return turnos.filter((t) => horasEnTramo(t, a, b) >= HORAS_MINIMAS_EN_TRAMO);
}

/** Lo que se tolera al entrar o salir escalonados: la primera y la última hora de lo cubierto no cuentan como hueco. */
export const HORA_DE_TOLERANCIA = 1;

/**
 * ¿Hay, en alguna media hora de lo cubierto del tramo, menos gente que la meta? Las entradas y salidas escalonadas son
 * normales (una persona llega 45 minutos antes que la otra), así que la primera y la última hora de lo cubierto no
 * cuentan: un hueco es lo que se abre EN MEDIO, o lo que dura más que esa tolerancia.
 */
export function hayHuecoDentroDelTramo(turnos: TurnoDecimal[], gente: TurnoDecimal[], tramo: Tramo, meta: number, inicioDia: number, finDia: number): boolean {
  if (meta <= 0 || gente.length === 0) return false;
  const [a, b] = limitesDelTramo(tramo, inicioDia, finDia);
  const desde = Math.max(a, Math.min(...gente.map((g) => g.entrada)));
  const hasta = Math.min(b, Math.max(...gente.map((g) => g.salida)));
  for (let h = desde; h < hasta; h += 0.5) {
    if (h < desde + HORA_DE_TOLERANCIA || h + 0.5 > hasta - HORA_DE_TOLERANCIA) continue;
    const cubren = turnos.filter((t) => t.entrada < h + 0.5 && t.salida > h).length;
    if (cubren < meta) return true;
  }
  return false;
}

export function resumenDelTramo(p: { turnos: TurnoDecimal[]; tramo: Tramo; meta: number; inicioDia: number; finDia: number }): ResumenTramo {
  const gente = personasDelTramo(p.turnos, p.tramo, p.inicioDia, p.finDia);
  const n = gente.length;
  const meta = Math.max(0, p.meta);
  if (meta === 0) return { gente, n, meta, estado: "sin_meta", faltan: 0, sobran: 0 };
  if (n < meta) return { gente, n, meta, estado: "falta", faltan: meta - n, sobran: 0 };
  if (n > meta) return { gente, n, meta, estado: "sobra", faltan: 0, sobran: n - meta };
  const hueco = hayHuecoDentroDelTramo(p.turnos, gente, p.tramo, meta, p.inicioDia, p.finDia);
  return { gente, n, meta, estado: hueco ? "con_huecos" : "completo", faltan: 0, sobran: 0 };
}

/**
 * Los líderes se miden aparte y con una meta PLANA todo el día (no hay tramo): cuántos tienen turno ese día contra la
 * meta. Sin meta no se mide; sin «con huecos» porque no hay una hora que comparar.
 */
export function resumenDeLideres(n: number, meta: number): Pick<ResumenTramo, "n" | "meta" | "estado" | "faltan" | "sobran"> {
  const m = Math.max(0, meta);
  if (m === 0) return { n, meta: m, estado: "sin_meta", faltan: 0, sobran: 0 };
  if (n < m) return { n, meta: m, estado: "falta", faltan: m - n, sobran: 0 };
  if (n > m) return { n, meta: m, estado: "sobra", faltan: 0, sobran: n - m };
  return { n, meta: m, estado: "completo", faltan: 0, sobran: 0 };
}
