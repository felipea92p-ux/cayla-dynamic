// «Tu semana» — lo que le toca a una colaboradora de lunes a domingo.
//
// QUÉ PROMETE
//   Responder «¿qué me toca esta semana?» con los siete días, el total de horas
//   contra su horario de siempre, la rotación (más mañanas o más tardes) y el
//   puesto del día (piso o almacén). Es la pregunta del FUTURO; «Mis días»
//   sigue respondiendo la del pasado («¿qué hice?») con lo marcado de verdad, y
//   no se mezclan: un turno que todavía no pasó no es una hora trabajada.
//
// QUÉ NO VUELVE A ESCRIBIR
//   «Qué le tocaba ese día» —turno del día → horario_por_dia → dias_laborables,
//   y cuánto refrigerio se descuenta— es `esperadoDelDia`
//   (lib/admin/jornada-esperada.ts). Acá solo se suma y se cuenta en palabras.
//
// CONTRA QUÉ SE COMPARA EL TOTAL (y por qué dice «tu horario» y no «tu jornada»)
//   Felipe decidió (2026-11-02) que la jornada —completa o parcial, y cuántas
//   horas— la fije DO en un campo propio de la persona. Ese campo todavía no
//   existe; llega con la migración de «Mi disponibilidad». Mientras tanto la
//   referencia es su HORARIO BASE de esa misma semana, sin los turnos puntuales,
//   y la pantalla lo dice así: «de tu horario». Es honesto pero limitado: solo
//   avisa cuando un turno puntual mueve horas respecto de su horario de siempre,
//   no cuando el horario de siempre está mal armado. El día que exista la
//   jornada, `referencia` cambia de fuente y la frase de «horario» a «jornada».
//
// EL PUESTO (piso o almacén)
//   Lo planificado vive en `puestos_planificados` (persona_id, fecha, desde,
//   hasta), de la sesión de Turnos: sin fila = piso; desde y hasta vacíos = todo
//   el turno en almacén; con horas = almacén en ese tramo. Si la tabla todavía no
//   existe o no se pudo leer, `puestos` llega en null y NO se muestra ningún
//   puesto: decir «Piso» sin saberlo sería afirmar algo que no se leyó.
//   Cómo se leen las filas y qué palabras se usan NO se escriben acá: son
//   `puestoDesdeFilas` y `textoPuesto` de lib/admin/almacen.ts, las mismas del
//   panel de Turnos y de `fn_puesto_texto` (0579).

import {
  esperadoDelDia, horarioVigente, fechasDelRango, dowDe,
  type Esperado, type HorarioTramo, type TurnoDia,
} from "@/lib/admin/jornada-esperada";
import { esPiso, puestoDesdeFilas, textoPuesto, type PuestoDelDia } from "@/lib/admin/almacen";

/** Una fila de `puestos_planificados` de esta persona. */
export interface PuestoFila {
  fecha: string;
  desde: string | null;
  hasta: string | null;
}

export interface DiaDeMiSemana {
  fecha: string;
  /** Lo que le toca: turno del día si lo hay, si no su horario. */
  esperado: Esperado;
  /** Lo que diría su horario base sin turnos puntuales: la referencia del total. */
  base: Esperado;
  /** Nombre del feriado, si lo es. */
  feriado: string | null;
  /** null = no se sabe (tabla ausente o ilegible) o ese día no trabaja. */
  puesto: PuestoDelDia | null;
}

export interface TotalDeSemana {
  horas: number;
  diasDeTrabajo: number;
  /** Suma del horario base de esos siete días; null si no hay horario base con qué comparar. */
  referencia: number | null;
}

// ── Fechas ───────────────────────────────────────────────────────────────────

/** Suma (o resta) días a una fecha ISO, sin pasar por la hora local del navegador. */
export function sumarDias(iso: string, n: number): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}

/** El lunes de la semana de esa fecha. La semana va de lunes a domingo. */
export function lunesDe(iso: string): string {
  const dow = dowDe(iso);               // 0 = domingo
  return sumarDias(iso, dow === 0 ? -6 : 1 - dow);
}

/** Los siete días, de lunes a domingo. */
export function semanaDe(lunes: string): string[] {
  return fechasDelRango(lunes, sumarDias(lunes, 6));
}

// ── Armar la semana ──────────────────────────────────────────────────────────

export function armarSemana(args: {
  lunes: string;
  turnos: Map<string, TurnoDia>;
  tramos: HorarioTramo[];
  feriados: Map<string, string>;
  /** null = no se sabe. Un array (aunque vacío) = la tabla se leyó. */
  puestos: PuestoFila[] | null;
}): DiaDeMiSemana[] {
  return semanaDe(args.lunes).map((fecha) => {
    const horario = horarioVigente(args.tramos, fecha);
    const esperado = esperadoDelDia(fecha, args.turnos.get(fecha) ?? null, horario);
    const base = esperadoDelDia(fecha, null, horario);
    const puesto = args.puestos && esperado.trabaja
      ? puestoDesdeFilas(args.puestos.filter((p) => p.fecha === fecha))
      : null;
    return { fecha, esperado, base, feriado: args.feriados.get(fecha) ?? null, puesto };
  });
}

export function totalDeSemana(dias: DiaDeMiSemana[]): TotalDeSemana {
  const horas = dias.reduce((s, d) => s + d.esperado.horas, 0);
  const hayBase = dias.some((d) => d.base.origen !== "sin_horario");
  return {
    horas,
    diasDeTrabajo: dias.filter((d) => d.esperado.trabaja).length,
    referencia: hayBase ? dias.reduce((s, d) => s + d.base.horas, 0) : null,
  };
}

// ── En palabras ──────────────────────────────────────────────────────────────

/** 45 → «45 h» · 7.25 → «7 h 15 min» · 0.5 → «30 min». */
export function textoHoras(horas: number): string {
  const min = Math.round(horas * 60);
  const h = Math.floor(min / 60);
  const m = min % 60;
  if (h === 0) return `${m} min`;
  return m === 0 ? `${h} h` : `${h} h ${m} min`;
}

/**
 * Si la semana cuadra con su horario, y si no, cuánto y en qué sentido. No dice
 * «tu líder lo está revisando»: nadie recibe ese aviso todavía, y prometerlo
 * sería falso. Dice a quién preguntarle.
 */
export function cuadreDeSemana(t: TotalDeSemana): { tono: "positivo" | "advertencia"; texto: string } | null {
  if (t.referencia === null) return null;
  const dif = t.horas - t.referencia;
  if (Math.abs(dif) < 1 / 60) return { tono: "positivo", texto: "Coincide con tu horario de siempre." };
  const cuanto = textoHoras(Math.abs(dif));
  return {
    tono: "advertencia",
    texto: `Esta semana tienes ${cuanto} ${dif < 0 ? "menos" : "más"} que tu horario de siempre. ` +
      "Si nadie te lo explicó, pregúntale a tu líder de equipo.",
  };
}

/**
 * El corte entre mañana y tarde para DESCRIBIR una semana, no para decidir
 * nada: un turno es «de mañana» si su punto medio cae antes de las 14:00.
 * No es un parámetro de negocio —no cambia ningún pago ni ninguna regla—, solo
 * la palabra que se le muestra a ella.
 */
const CORTE_MANANA_TARDE_MIN = 14 * 60;

function minutos(hhmm: string): number {
  const [h, m] = hhmm.split(":").map(Number);
  return h * 60 + (m || 0);
}

export type Inclinacion = "mananas" | "tardes" | "pareja";

/** ¿Esa semana hace más mañanas o más tardes? null si trabaja menos de dos días con horas. */
export function inclinacionDeSemana(dias: DiaDeMiSemana[]): Inclinacion | null {
  let mananas = 0;
  let tardes = 0;
  for (const d of dias) {
    const { trabaja, entrada, salida } = d.esperado;
    if (!trabaja || !entrada || !salida) continue;
    let fin = minutos(salida);
    const ini = minutos(entrada);
    if (fin <= ini) fin += 24 * 60;
    if ((ini + fin) / 2 < CORTE_MANANA_TARDE_MIN) mananas++;
    else tardes++;
  }
  if (mananas + tardes < 2) return null;
  return mananas > tardes ? "mananas" : tardes > mananas ? "tardes" : "pareja";
}

const PALABRA: Record<Exclude<Inclinacion, "pareja">, string> = { mananas: "más mañanas", tardes: "más tardes" };

/**
 * «Esta semana haces más tardes; la próxima, más mañanas.» Solo afirma lo que
 * los turnos cargados dicen: si la próxima todavía no tiene turnos, habla solo
 * de esta.
 */
export function textoRotacion(esta: Inclinacion | null, proxima: Inclinacion | null): string | null {
  if (!esta || esta === "pareja") return null;
  if (proxima && proxima !== "pareja" && proxima !== esta) {
    return `Esta semana haces ${PALABRA[esta]}; la próxima, ${PALABRA[proxima]}.`;
  }
  return `Esta semana haces ${PALABRA[esta]}.`;
}

/** La línea grande de la tarjeta del Resumen: «10:30–17:00 en piso» o «Descansas». */
export function hoyEnUnaLinea(dia: DiaDeMiSemana | undefined): string {
  if (!dia || !dia.esperado.trabaja) return "Descansas";
  const { entrada, salida } = dia.esperado;
  const horario = `${entrada}${salida ? `–${salida}` : ""}`;
  if (!dia.puesto) return horario;
  if (esPiso(dia.puesto)) return `${horario} en piso`;
  if (dia.puesto.todoElTurno) return `${horario} en almacén`;
  return `${horario} · ${textoPuesto(dia.puesto).toLowerCase()}`;
}
