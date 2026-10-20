// ============================================================================
// almuerzo.ts — cuándo salió a almorzar y cuándo volvió, a partir de las marcas
// ============================================================================
// QUÉ PROMETE   · dado un puñado de marcas `salida_almuerzo` / `retorno_almuerzo`, decir por persona y día cuándo salió, cuándo
//                 volvió y cuántos minutos fueron; y, con la hora de ahora, si sigue almorzando.
// QUÉ ASUME     · que las marcas ya vienen SIN las anuladas (`anulada_at is null`) y que el día es el día de LIMA de la marca
//                 (`fechaLima`), no el de UTC: una marca de las 19:00 de Lima ya es del día siguiente en UTC.
// POR QUÉ ASÍ   · solo cuenta el PRIMER almuerzo del día: la primera salida y el primer retorno que viene después. Un segundo
//                 par (rarísimo) sería otra pausa, y las pausas por trámite o médicas tienen sus propios tipos de marca.
//
// No tiene React ni Supabase: se prueba con vitest.
// ============================================================================
import { fechaLima } from "@cayla-dynamic/shared";

export const TIPOS_DE_ALMUERZO = ["salida_almuerzo", "retorno_almuerzo"] as const;

export interface MarcaDeAlmuerzo {
  persona_id: string;
  tipo: string;
  timestamp_marca: string;
}

export interface AlmuerzoDelDia {
  salioTs: string;
  /** Null si todavía no marcó el retorno. */
  volvioTs: string | null;
  /** Minutos entre salir y volver; null mientras no volvió. */
  minutos: number | null;
}

/** La llave de un día de una persona: `persona|AAAA-MM-DD` (día de Lima). */
export const llaveDia = (personaId: string, fecha: string) => `${personaId}|${fecha}`;

export function minutosEntre(desdeTs: string, hastaTs: string): number {
  return Math.round((new Date(hastaTs).getTime() - new Date(desdeTs).getTime()) / 60000);
}

export function almuerzosPorDia(marcas: readonly MarcaDeAlmuerzo[]): Map<string, AlmuerzoDelDia> {
  const porDia = new Map<string, MarcaDeAlmuerzo[]>();
  for (const m of marcas) {
    if (m.tipo !== "salida_almuerzo" && m.tipo !== "retorno_almuerzo") continue;
    const k = llaveDia(m.persona_id, fechaLima(new Date(m.timestamp_marca)));
    porDia.set(k, [...(porDia.get(k) ?? []), m]);
  }
  const salida = new Map<string, AlmuerzoDelDia>();
  for (const [k, ms] of porDia) {
    const orden = [...ms].sort((a, b) => a.timestamp_marca.localeCompare(b.timestamp_marca) || a.tipo.localeCompare(b.tipo));
    const sal = orden.find((m) => m.tipo === "salida_almuerzo");
    if (!sal) continue; // un retorno sin salida no es un almuerzo que se pueda medir
    const vol = orden.find((m) => m.tipo === "retorno_almuerzo" && m.timestamp_marca > sal.timestamp_marca);
    salida.set(k, {
      salioTs: sal.timestamp_marca,
      volvioTs: vol?.timestamp_marca ?? null,
      minutos: vol ? minutosEntre(sal.timestamp_marca, vol.timestamp_marca) : null,
    });
  }
  return salida;
}

export type EstadoDelDia = "trabajando" | "almorzando" | "termino";

/** Dónde va el día de alguien: terminó (hay salida final), almuerza (salió y no volvió) o trabaja. */
export function estadoDelDia(d: { salidaTs: string | null; almuerzo: AlmuerzoDelDia | null }): EstadoDelDia {
  if (d.salidaTs) return "termino";
  if (d.almuerzo && !d.almuerzo.volvioTs) return "almorzando";
  return "trabajando";
}

/** Minutos de almuerzo: los de verdad si volvió; si sigue almorzando, los que lleva hasta `ahoraTs`. Null si no almorzó. */
export function minutosDeAlmuerzo(a: AlmuerzoDelDia | null, ahoraTs: string): number | null {
  if (!a) return null;
  return a.minutos ?? Math.max(0, minutosEntre(a.salioTs, ahoraTs));
}

/**
 * ¿Se pasó del tiempo permitido? `permitido` sale del horario del día (`refrigerio_min`); si es 0 o no se conoce, NO se
 * compara: sin una vara no hay «se pasó», y decir lo contrario acusaría a alguien con un número inventado.
 */
export function sePaso(minutos: number | null, permitido: number | null): boolean {
  return minutos !== null && permitido !== null && permitido > 0 && minutos > permitido;
}

/** Horas trabajadas ANTES de salir a almorzar: de la entrada a la salida a almorzar, en horas. */
export function horasAntesDeAlmorzar(entradaTs: string | null, a: AlmuerzoDelDia | null): number | null {
  if (!entradaTs || !a) return null;
  return Math.max(0, minutosEntre(entradaTs, a.salioTs)) / 60;
}
