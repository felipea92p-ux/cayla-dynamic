// ============================================================================
// borrador-semana.ts — el borrador de la semana (0593): comparar y «cumple»
// ============================================================================
// PROMETE:
//   · Pasar las filas de `turnos_borrador_dias` a la forma de la propuesta
//     (persona → fecha → turno o descanso), COMPLETANDO con lo que hoy tiene
//     cada persona los días que el borrador no trae: un día que falta nunca se
//     lee como descanso, que es lo que publicaría por error.
//   · Comparar dos semanas persona por persona —horas, días de trabajo y qué
//     días cambian—, que es lo que dibuja la comparativa Actual / Sugerido /
//     Borrador de Turnos.
//   · Decir si una semana «cumple» la jornada de la persona: la que fija DO
//     (0584), con el margen de 15 minutos de la 0586, más dos avisos que
//     Felipe pidió (2026-11-03): pasar de 48 h, el máximo legal, y un día de
//     menos de 4 h.
// ASUME:   que «lo que hoy tiene cada persona» lo resuelve la pantalla con
//          `jornada-esperada.ts` (turno del día → horario base); aquí llega ya
//          resuelto como una función.
// NO HACE: leer la base, decidir permisos ni pintar.
// ============================================================================
import type { Propuesta, Turno } from "./sugerencia-turnos";

/** Una fila de `turnos_borrador_dias` tal como llega de la base. */
export interface FilaDiaBorrador {
  persona_id: string;
  fecha: string;
  entrada: string | null;
  salida: string | null;
}

/** Persona → fecha → turno (o null = descansa). */
export type SemanaTurnos = Record<string, Record<string, Turno | null>>;

/** El margen con que se compara una semana con la jornada: un cuarto de hora, el de la 0586. */
export const MARGEN_JORNADA_H = 0.25;
/** El máximo legal semanal (art. 25 de la Constitución, pactado como semanal en CAYLA). */
export const MAXIMO_LEGAL_H = 48;
/** Por debajo de esto un día se marca: cuatro horas diarias es el umbral del tiempo parcial. */
export const MINIMO_DIA_H = 4;

const aMin = (hhmm: string): number => {
  const [h, m] = hhmm.split(":").map(Number);
  return h * 60 + (m || 0);
};
const aHHMM = (min: number): string => `${String(Math.floor(min / 60)).padStart(2, "0")}:${String(min % 60).padStart(2, "0")}`;

/**
 * Las filas del borrador → persona → fecha → turno. Para cada persona que
 * aparece, los días de la semana que el borrador no trae se completan con lo
 * que hoy tiene (`actual`): así el borrador solo cambia lo que dice cambiar.
 */
export function semanaDesdeBorrador(
  filas: readonly FilaDiaBorrador[],
  fechas: readonly string[],
  actual: (personaId: string, fecha: string) => Turno | null,
): SemanaTurnos {
  const s: SemanaTurnos = {};
  for (const f of filas) {
    (s[f.persona_id] ??= {})[f.fecha] = f.entrada && f.salida
      ? { entrada: aMin(f.entrada.slice(0, 5)), salida: aMin(f.salida.slice(0, 5)) }
      : null;
  }
  for (const [persona, porFecha] of Object.entries(s)) {
    for (const fecha of fechas) if (!(fecha in porFecha)) porFecha[fecha] = actual(persona, fecha);
  }
  return s;
}

/** La semana → las filas que pide `fn_turnos_borrador_guardar`: una por persona y fecha (todas: el borrador se guarda entero). */
export function filasParaGuardar(semana: SemanaTurnos, fechas: readonly string[]): FilaDiaBorrador[] {
  return Object.entries(semana).flatMap(([persona_id, porFecha]) =>
    fechas.map((fecha) => {
      const t = porFecha[fecha] ?? null;
      return { persona_id, fecha, entrada: t ? aHHMM(t.entrada) : null, salida: t ? aHHMM(t.salida) : null };
    }));
}

/** Horas netas de cada día trabajado (turno menos refrigerio, nunca negativo) y su total. */
export function horasNetas(
  porFecha: Readonly<Record<string, Turno | null>>,
  fechas: readonly string[],
  refrigerioMin: number,
): { total: number; porDia: { fecha: string; horas: number }[] } {
  const porDia = fechas.flatMap((fecha) => {
    const t = porFecha[fecha] ?? null;
    return t ? [{ fecha, horas: Math.max(0, t.salida - t.entrada - refrigerioMin) / 60 }] : [];
  });
  return { total: porDia.reduce((a, d) => a + d.horas, 0), porDia };
}

export type EstadoCumple = "cumple" | "faltan" | "sobra" | "sin_jornada";

export interface Cumple {
  estado: EstadoCumple;
  horas: number;
  jornada: number | null;
  /** horas − jornada (positivo = se pasa); null sin jornada. */
  diferencia: number | null;
  /** Pasa del máximo legal semanal. */
  pasa48: boolean;
  /** Fechas trabajadas con menos de 4 h netas. */
  diasCortos: string[];
}

/** ¿La semana cumple su jornada? Sin jornada fijada no hay contra qué medir: «sin_jornada», pero los avisos de 48 h y 4 h valen igual. */
export function cumpleJornada(horas: number, jornada: number | null, porDia: readonly { fecha: string; horas: number }[] = []): Cumple {
  const pasa48 = horas > MAXIMO_LEGAL_H + 1e-9;
  const diasCortos = porDia.filter((d) => d.horas > 0 && d.horas < MINIMO_DIA_H - 1e-9).map((d) => d.fecha);
  if (jornada === null) return { estado: "sin_jornada", horas, jornada, diferencia: null, pasa48, diasCortos };
  const diferencia = horas - jornada;
  const estado: EstadoCumple = Math.abs(diferencia) <= MARGEN_JORNADA_H + 1e-9 ? "cumple" : diferencia < 0 ? "faltan" : "sobra";
  return { estado, horas, jornada, diferencia, pasa48, diasCortos };
}

const coma = (n: number) => String(Math.round(n * 100) / 100).replace(".", ",");

/** «cumple 45 h» · «faltan 3 h de 45» · «se pasa 2 h de 45» · «45 h · sin jornada fijada». */
export function textoCumple(c: Cumple): string {
  if (c.estado === "sin_jornada") return `${coma(c.horas)} h · sin jornada fijada`;
  if (c.estado === "cumple") return `cumple ${coma(c.jornada!)} h`;
  const d = coma(Math.abs(c.diferencia!));
  return c.estado === "faltan" ? `faltan ${d} h de ${coma(c.jornada!)}` : `se pasa ${d} h de ${coma(c.jornada!)}`;
}

const igual = (a: Turno | null, b: Turno | null) =>
  (a === null && b === null) || (a !== null && b !== null && a.entrada === b.entrada && a.salida === b.salida);

export interface PersonaComparada {
  id: string;
  antes: { horas: number; dias: number };
  despues: { horas: number; dias: number };
  /** Fechas en que el turno de `despues` no es el de `antes`. */
  cambian: string[];
  cumple: Cumple;
}

/**
 * Persona por persona: lo de `antes` (lo publicado, o lo que hoy tiene) contra
 * lo de `despues` (la sugerencia o el borrador), con el «cumple» de `despues`.
 * Solo las personas que `despues` trae.
 */
export function compararSemanas(args: {
  fechas: readonly string[];
  antes: (personaId: string, fecha: string) => Turno | null;
  despues: SemanaTurnos;
  refrigerioMin: (personaId: string) => number;
  jornada: (personaId: string) => number | null;
}): PersonaComparada[] {
  const { fechas, antes, despues, refrigerioMin, jornada } = args;
  return Object.entries(despues).map(([id, porFecha]) => {
    const ref = refrigerioMin(id);
    const deAntes = Object.fromEntries(fechas.map((f) => [f, antes(id, f)]));
    const a = horasNetas(deAntes, fechas, ref);
    const d = horasNetas(porFecha, fechas, ref);
    return {
      id,
      antes: { horas: a.total, dias: a.porDia.length },
      despues: { horas: d.total, dias: d.porDia.length },
      cambian: fechas.filter((f) => !igual(porFecha[f] ?? null, deAntes[f])),
      cumple: cumpleJornada(d.total, jornada(id), d.porDia),
    };
  });
}

/**
 * Lo que necesita `filasParaPublicar` de una semana que no salió del motor (el
 * borrador): sus turnos y, para el turno propio de la líder, sus horas netas.
 */
export function comoPropuesta(
  semana: SemanaTurnos,
  fechas: readonly string[],
  refrigerioMin: (personaId: string) => number,
): Pick<Propuesta, "turnos" | "resumen"> {
  const resumen: Propuesta["resumen"] = {};
  for (const [id, porFecha] of Object.entries(semana)) {
    const h = horasNetas(porFecha, fechas, refrigerioMin(id));
    resumen[id] = { horas: h.total, dias: h.porDia.length, objetivo: h.total };
  }
  return { turnos: semana, resumen };
}

/**
 * ¿El error dice que la tabla del borrador no existe? Es lo que pasa mientras
 * la 0593 no está pegada: la pantalla esconde el borrador en vez de fallar.
 */
export const esTablaInexistente = (e: { code?: string } | null): boolean =>
  e !== null && (e.code === "42P01" || e.code === "PGRST205" || e.code === "PGRST200");

/** Las filas de una semana para guardarlas: solo los días que todavía no llegan, y nadie a quien no le corresponde horario. */
export function filasDelBorradorParaGuardar(
  semana: SemanaTurnos,
  fechas: readonly string[],
  hoy: string,
  conHorario: (personaId: string) => boolean,
): FilaDiaBorrador[] {
  const futuras = fechas.filter((f) => f > hoy);
  const soloConHorario: SemanaTurnos = Object.fromEntries(Object.entries(semana).filter(([id]) => conHorario(id)));
  return filasParaGuardar(soloConHorario, futuras);
}
