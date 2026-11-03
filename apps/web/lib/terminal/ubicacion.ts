// ============================================================================
// ubicacion.ts — ¿está en tienda o en almacén? (lo que decide el terminal)
// ============================================================================
//
// QUÉ PROMETE
//   La respuesta que el terminal usa para ofrecer «Voy a almacén» o «Vuelvo a
//   tienda», para el renglón «En almacén desde 12:32 · vuelves 13:32» y para la
//   casilla de la lista. Funciones puras: sin red, sin IndexedDB, sin React —
//   por eso se prueban con vitest (tests/ubicacion-terminal.test.ts).
//
// QUÉ ASUME
//   La misma regla que `fn_ubicaciones_del_dia` (migración 0580), que es la que
//   leen Turnos y los reportes. Si cambia allá, cambia aquí:
//     · el tramo en almacén termina con el siguiente «tienda», con su salida
//       final, o con la vuelta prevista ya vencida;
//     · dos «almacen» seguidos que se tocan son un solo tramo.
//
// POR QUÉ NO ES UN MARCAJE
//   Ir al almacén no abre ni cierra la jornada y no cambia horas ni pago (0580).
//   Por eso nada de este archivo toca `MarcajeDelDia` salvo para LEER si ya
//   marcó su salida final.
// ============================================================================
import { TZ_LIMA, type MarcajeDelDia } from "@cayla-dynamic/shared";

export type Ubicacion = "tienda" | "almacen";

export interface CambioUbicacion {
  ubicacion: Ubicacion;
  /** ISO. La hora del terminal, como `timestamp_marca`. */
  timestamp: string;
  /** ISO, o null = «hasta que vuelva». Solo con «almacen». */
  vuelvePrevisto: string | null;
}

export interface EstadoUbicacion {
  enAlmacen: boolean;
  /** ISO: desde cuándo está en almacén (inicio del tramo). */
  desde?: string;
  /** ISO, o null si dijo «hasta que vuelva». */
  vuelve?: string | null;
}

/** Las cuatro respuestas a «¿Por cuánto tiempo?». `null` = hasta que vuelva. */
export const DURACIONES_ALMACEN: ReadonlyArray<{ etiqueta: string; minutos: number | null }> = [
  { etiqueta: "30 min", minutos: 30 },
  { etiqueta: "1 hora", minutos: 60 },
  { etiqueta: "2 horas", minutos: 120 },
  { etiqueta: "Hasta que vuelva", minutos: null },
];

const ms = (iso: string) => new Date(iso).getTime();

/** Un tramo en almacén: ISO desde, ISO hasta (null = sigue allí ahora). */
export interface TramoAlmacen {
  desde: string;
  hasta: string | null;
  /** ISO, la vuelta prevista del tramo abierto, o null si es «hasta que vuelva». */
  vuelve: string | null;
}

/**
 * LA REGLA de «¿dónde estuvo y dónde está?», hasta `ahora`. Es la misma de
 * `fn_ubicaciones_del_dia` (0580) y la usan el terminal y Turnos: una sola.
 *
 * Recorre los cambios en orden —los reales y, si se le pasan, los planificados
 * convertidos con `cambiosDelPlan`—. Lo que todavía no pasó no cuenta. Un
 * tramo se cierra con lo primero de: el siguiente «tienda», su vuelta prevista
 * ya vencida, o su salida final. Un «almacen» con el tramo abierto lo alarga
 * con la nueva vuelta (un doble toque es un tramo).
 */
export function tramosDelDia(
  cambios: readonly CambioUbicacion[],
  marcajesHoy: readonly MarcajeDelDia[],
  ahora: Date,
): TramoAlmacen[] {
  const t = ahora.getTime();
  const ordenados = cambios
    .filter((c) => ms(c.timestamp) <= t)
    .sort((a, b) => ms(a.timestamp) - ms(b.timestamp));
  const salidas = marcajesHoy.filter((m) => m.tipo === "salida_final").map((m) => ms(m.timestamp));
  const tramos: TramoAlmacen[] = [];
  type Abierto = { desde: string; vuelve: string | null; ultimo: string };
  let abierto = null as Abierto | null;

  // Cierra el tramo abierto en el primer corte que ocurra antes de `limite`.
  const cerrarSiCorresponde = (limite: number) => {
    if (!abierto) return;
    const salida = salidas.filter((s) => s > ms(abierto!.ultimo)).sort((a, b) => a - b)[0];
    const cortes = [abierto.vuelve ? ms(abierto.vuelve) : Infinity, salida ?? Infinity].filter((c) => c <= limite);
    if (cortes.length === 0) return;
    tramos.push({ desde: abierto.desde, hasta: new Date(Math.min(...cortes)).toISOString(), vuelve: abierto.vuelve });
    abierto = null;
  };

  for (const c of ordenados) {
    cerrarSiCorresponde(ms(c.timestamp));
    if (c.ubicacion === "almacen") {
      abierto = { desde: abierto?.desde ?? c.timestamp, vuelve: c.vuelvePrevisto, ultimo: c.timestamp };
    } else if (abierto) {
      tramos.push({ desde: abierto.desde, hasta: c.timestamp, vuelve: abierto.vuelve });
      abierto = null;
    }
  }
  cerrarSiCorresponde(t);
  const final = abierto as Abierto | null;
  if (final) tramos.push({ desde: final.desde, hasta: null, vuelve: final.vuelve });
  return tramos.filter((x) => x.hasta === null || ms(x.hasta) > ms(x.desde));
}

/** Dónde está ahora: el último tramo, si sigue abierto. */
export function ubicacionActual(
  cambios: readonly CambioUbicacion[],
  marcajesHoy: readonly MarcajeDelDia[],
  ahora: Date,
): EstadoUbicacion {
  const ultimo = tramosDelDia(cambios, marcajesHoy, ahora).at(-1);
  if (!ultimo || ultimo.hasta !== null) return { enAlmacen: false };
  return { enAlmacen: true, desde: ultimo.desde, vuelve: ultimo.vuelve };
}

/** «12:32», en la hora de Lima y en 24 h, como la maqueta. */
export function horaUbicacion(iso: string): string {
  return new Intl.DateTimeFormat("es-PE", {
    timeZone: TZ_LIMA,
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(new Date(iso));
}

/** ISO de la vuelta prevista, o null si es «hasta que vuelva». */
export function vueltaPrevista(ahora: Date, minutos: number | null): string | null {
  return minutos === null ? null : new Date(ahora.getTime() + minutos * 60_000).toISOString();
}

/** El renglón del menú: «En almacén desde 12:32 · vuelves 13:32». */
export function textoEstadoAlmacen(e: EstadoUbicacion): string | null {
  if (!e.enAlmacen || !e.desde) return null;
  const base = `En almacén desde ${horaUbicacion(e.desde)}`;
  return e.vuelve ? `${base} · vuelves ${horaUbicacion(e.vuelve)}` : base;
}

/** La línea bajo el nombre en la lista: «En almacén · vuelve 13:32». */
export function detalleCasillaAlmacen(e: EstadoUbicacion): string | null {
  if (!e.enAlmacen || !e.desde) return null;
  return e.vuelve ? `En almacén · vuelve ${horaUbicacion(e.vuelve)}` : `En almacén desde ${horaUbicacion(e.desde)}`;
}

// ── Lo planificado (0579, sesión de Turnos) ─────────────────────────────────
//
// Turnos planifica por día quién va al almacén (`puestos_planificados`). El
// terminal NO escribe nada con eso: solo lo dice al marcar la entrada («Hoy te
// toca almacén de 10:30 a 12:30») y lo usa para saber qué botón ofrecer. Lo que
// pasa de verdad sigue siendo lo que se registra: si lo planificado dice
// almacén y ella marca «Vuelvo a tienda», queda ese cambio real y lo
// planificado no se toca (decisión de Felipe, 2026-11-02).
//
// Por eso cada tramo planificado entra a `ubicacionActual` como si fuera un
// «Voy a almacén» a su hora de inicio, con su fin como vuelta prevista. Así la
// regla es una sola: lo último que pasó manda, sea lo planificado o lo real.

export interface TramoHoras {
  /** Hora decimal de Lima (10:30 → 10.5). */
  desde: number;
  hasta: number;
}

/**
 * Los tramos en almacén planificados para hoy, ya recortados a su turno.
 * `turno` null = no se sabe su horario: «todo el turno» queda abierto hasta su
 * salida final y los tramos van tal cual. Fuera del turno no cuentan.
 */
export function tramosPlanificados(
  plan: { todoElTurno: boolean; tramos: TramoHoras[] },
  turno: TramoHoras | null,
): { todoElTurno: boolean; tramos: TramoHoras[] } {
  if (plan.todoElTurno) return { todoElTurno: true, tramos: turno ? [turno] : [] };
  const tramos = turno
    ? plan.tramos
        .map((t) => ({ desde: Math.max(t.desde, turno.desde), hasta: Math.min(t.hasta, turno.hasta) }))
        .filter((t) => t.hasta > t.desde)
    : plan.tramos;
  return { todoElTurno: false, tramos: [...tramos].sort((a, b) => a.desde - b.desde) };
}

const hhmm = (dec: number): string => {
  const h = Math.floor(dec + 1e-9);
  const m = Math.round((dec - h) * 60);
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
};

/** «Hoy te toca almacén de 10:30 a 12:30», o null si hoy le toca piso. */
export function textoPlanDeHoy(plan: { todoElTurno: boolean; tramos: TramoHoras[] }): string | null {
  if (plan.todoElTurno) return "Hoy te toca almacén todo el turno";
  if (plan.tramos.length === 0) return null;
  const partes = plan.tramos.map((t) => `de ${hhmm(t.desde)} a ${hhmm(t.hasta)}`);
  const lista = partes.length === 1 ? partes[0] : `${partes.slice(0, -1).join(", ")} y ${partes[partes.length - 1]}`;
  return `Hoy te toca almacén ${lista}`;
}

/**
 * Lo planificado como cambios, para que `ubicacionActual` lo combine con lo
 * real. `medianocheIso` es el inicio del día en Lima (`rangoDelDiaLima().inicio`).
 * «Todo el turno» sin horario conocido empieza a medianoche y no tiene vuelta:
 * lo cierra un «Vuelvo a tienda» o su salida final.
 */
export function cambiosDelPlan(
  plan: { todoElTurno: boolean; tramos: TramoHoras[] },
  medianocheIso: string,
): CambioUbicacion[] {
  const base = new Date(medianocheIso).getTime();
  const iso = (dec: number) => new Date(base + Math.round(dec * 3_600_000)).toISOString();
  if (plan.todoElTurno && plan.tramos.length === 0) {
    return [{ ubicacion: "almacen", timestamp: iso(0), vuelvePrevisto: null }];
  }
  return plan.tramos.map((t) => ({ ubicacion: "almacen" as const, timestamp: iso(t.desde), vuelvePrevisto: iso(t.hasta) }));
}
