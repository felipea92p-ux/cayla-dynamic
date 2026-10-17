// ============================================================================
// educacion-adelantado.ts — cómo se reparte un pago adelantado entre sus meses
// ============================================================================
// QUÉ PROMETE · dado «de qué mes a qué mes» y el total (o el monto de cada mes),
//               sacar los meses calendario y lo que corresponde a cada uno, de
//               forma que la suma dé SIEMPRE el total.
// DECIDIDO POR FELIPE (2026-10-17) · meses calendario, ambos incluidos (agosto a
//               diciembre = 5); lo que ella corrige a mano se respeta y pide motivo;
//               el resto del total se reparte entre los meses que no tocó.
// QUÉ NO HACE · no valida contra la base: `fn_educacion_enviar_adelantado` (0529)
//               repite las reglas y gana. No toca React ni Supabase: se prueba con
//               vitest (tests/educacion-adelantado.test.ts).
// ============================================================================
import { mesDe, sumarMeses } from "@/lib/admin/educacion-meses";

export type OrigenMonto = "calculado" | "puesto" | "manual";

export interface MesDelPago {
  /** "2026-08" */
  mes: string;
  monto: number;
  origen: OrigenMonto;
  motivo: string | null;
}

export interface Correccion { monto: number; motivo: string }

/** Un pago adelantado cubre al menos dos meses y como mucho 24 (lo mismo que exige la base). */
export const MESES_MINIMOS_ADELANTADO = 2;
export const MESES_MAXIMOS_ADELANTADO = 24;

/** Los meses calendario de `desde` a `hasta`, ambos incluidos. Vacío si están al revés. */
export function mesesEntreIncluidos(desde: string, hasta: string): string[] {
  const r: string[] = [];
  for (let m = mesDe(desde); m <= mesDe(hasta) && r.length <= MESES_MAXIMOS_ADELANTADO; m = sumarMeses(m, 1)) r.push(m);
  return r;
}

/**
 * Reparte el pago. `sabe = "total"`: el total menos lo corregido, dividido entre los meses que no
 * se corrigieron; los céntimos que sobran van al último de ellos. `sabe = "cada"`: cada mes lleva
 * el monto que ella puso. En los dos casos, un mes corregido a mano manda.
 */
export function repartirPago(opts: {
  desde: string;
  hasta: string;
  sabe: "total" | "cada";
  total: number;
  cada: number;
  correcciones: Readonly<Record<string, Correccion>>;
}): MesDelPago[] {
  const meses = mesesEntreIncluidos(opts.desde, opts.hasta);
  if (opts.sabe === "cada") {
    return meses.map((mes) => {
      const c = opts.correcciones[mes];
      return c ? { mes, monto: c.monto, origen: "manual", motivo: c.motivo } : { mes, monto: opts.cada, origen: "puesto", motivo: null };
    });
  }
  const libres = meses.filter((m) => !opts.correcciones[m]);
  const fijado = meses.reduce((t, m) => t + (opts.correcciones[m] ? Math.round(opts.correcciones[m].monto * 100) : 0), 0);
  const resto = Math.max(0, Math.round(opts.total * 100) - fijado);
  const n = Math.max(1, libres.length);
  const base = Math.floor(resto / n), sobra = resto - base * n;
  const ultimo = libres[libres.length - 1];
  return meses.map((mes) => {
    const c = opts.correcciones[mes];
    if (c) return { mes, monto: c.monto, origen: "manual", motivo: c.motivo };
    return { mes, monto: (base + (mes === ultimo ? sobra : 0)) / 100, origen: "calculado", motivo: null };
  });
}

export const sumaDelPago = (meses: readonly MesDelPago[]): number =>
  Math.round(meses.reduce((t, x) => t + Math.round(x.monto * 100), 0)) / 100;

/** Lo que impide enviar, en el idioma de la pantalla; `null` = se puede. */
export function problemaDelPago(meses: readonly MesDelPago[], sabe: "total" | "cada", total: number): string | null {
  if (meses.length < MESES_MINIMOS_ADELANTADO) return "Un pago adelantado cubre al menos dos meses. Si es uno solo, elige «Un solo mes».";
  if (meses.length > MESES_MAXIMOS_ADELANTADO) return `Un pago adelantado cubre como máximo ${MESES_MAXIMOS_ADELANTADO} meses.`;
  if (meses.some((x) => !(x.monto >= 0))) return "Cada mes necesita su monto.";
  if (meses.some((x) => x.origen === "manual" && (x.motivo ?? "").trim().length < 3)) return "Escribe por qué corregiste el monto (al menos 3 letras).";
  const suma = sumaDelPago(meses);
  if (suma <= 0) return sabe === "total" ? "Escribe el total que pagaste." : "Escribe el monto de cada mes.";
  if (sabe === "total" && Math.abs(suma - total) > 0.004) return "Los meses que corregiste suman más que el total que pagaste. Revisa los montos.";
  return null;
}

/** Lo que se le manda a `fn_educacion_enviar_adelantado`: cada mes por su día 1. */
export const mesesParaLaBase = (meses: readonly MesDelPago[]) =>
  meses.map((x) => ({ mes: `${x.mes}-01`, monto: x.monto, origen: x.origen, ...(x.origen === "manual" ? { motivo: (x.motivo ?? "").trim() } : {}) }));
