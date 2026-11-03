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

/**
 * Dónde está ahora, según los cambios de hoy y sus marcas de hoy.
 *
 * Recorre los cambios en orden. Un tramo abierto se cierra antes del siguiente
 * cambio si su vuelta prevista ya había vencido; un «tienda» lo cierra; un
 * «almacen» lo abre o, si ya estaba abierto, lo alarga con la nueva vuelta.
 * Al final se cierra si venció la vuelta o si marcó su salida final después de
 * entrar al almacén.
 */
export function ubicacionActual(
  cambios: readonly CambioUbicacion[],
  marcajesHoy: readonly MarcajeDelDia[],
  ahora: Date,
): EstadoUbicacion {
  const ordenados = [...cambios].sort((a, b) => ms(a.timestamp) - ms(b.timestamp));
  type Tramo = { desde: string; vuelve: string | null; ultimo: string };
  let tramo = null as Tramo | null;

  for (const c of ordenados) {
    if (tramo && tramo.vuelve && ms(tramo.vuelve) <= ms(c.timestamp)) tramo = null;
    if (c.ubicacion === "almacen") {
      tramo = { desde: tramo?.desde ?? c.timestamp, vuelve: c.vuelvePrevisto, ultimo: c.timestamp };
    } else {
      tramo = null;
    }
  }

  const abierto = tramo;
  if (!abierto) return { enAlmacen: false };
  if (abierto.vuelve && ms(abierto.vuelve) <= ahora.getTime()) return { enAlmacen: false };
  const salio = marcajesHoy.some((m) => m.tipo === "salida_final" && ms(m.timestamp) > ms(abierto.ultimo));
  if (salio) return { enAlmacen: false };
  return { enAlmacen: true, desde: abierto.desde, vuelve: abierto.vuelve };
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
