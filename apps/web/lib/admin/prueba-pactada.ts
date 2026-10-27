/**
 * EL PERIODO DE PRUEBA QUE SE ELIGE EN EL FORMULARIO DE EQUIPO (0556), EN LO QUE LA PANTALLA NECESITA SABER.
 *
 * QUÉ PROMETE. Pasar entre lo que se ve —tres opciones: la ley, un periodo menor, sin prueba— y lo que
 * guarda la base (`personas.prueba_pactada_dias`: null, 1–89 o 0), y validar lo tecleado ANTES de escribir
 * nada. La que manda es `fn_set_prueba_pactada`; esto solo evita un viaje en balde y explica el rechazo.
 *
 * QUÉ NO HACE. No calcula fechas (eso es `finDelPeriodoPactado`, packages/shared) ni decide quién puede
 * pactar. Y no es un permiso: acortar la prueba es renunciar a un derecho de CAYLA, por eso pide motivo.
 */

import { DIAS_PRUEBA_PACTADA_MAX } from "@cayla-dynamic/shared";

export type ModoPrueba = "ley" | "menor" | "sin";

export interface PruebaDelForm {
  modo: ModoPrueba;
  /** Lo tecleado en «días»; solo cuenta con modo «menor». */
  dias: string;
  motivo: string;
}

export type PruebaLeida =
  | { ok: true; dias: number | null; motivo: string }
  | { ok: false; mensaje: string };

/** De lo guardado a lo que se ve: null = la ley, 0 = sin prueba, N = menor. */
export function pruebaDeLoGuardado(pactado: number | null | undefined): { modo: ModoPrueba; dias: string } {
  if (pactado === null || pactado === undefined) return { modo: "ley", dias: "" };
  if (pactado === 0) return { modo: "sin", dias: "" };
  return { modo: "menor", dias: String(pactado) };
}

/** De lo que se ve a lo que se guarda, con su validación. */
export function leerPruebaDelForm(f: PruebaDelForm): PruebaLeida {
  if (f.modo === "ley") return { ok: true, dias: null, motivo: f.motivo.trim() };
  const motivo = f.motivo.trim();
  if (motivo.length < 3) {
    return { ok: false, mensaje: "Escribe por qué se pacta un periodo de prueba distinto del de la ley: queda en el historial." };
  }
  if (f.modo === "sin") return { ok: true, dias: 0, motivo };
  const t = f.dias.trim();
  if (!/^\d+$/.test(t)) return { ok: false, mensaje: "Escribe los días del periodo de prueba, en número entero." };
  const n = Number(t);
  if (n < 1 || n > DIAS_PRUEBA_PACTADA_MAX) {
    return { ok: false, mensaje: `El periodo de prueba menor va de 1 a ${DIAS_PRUEBA_PACTADA_MAX} días. De tres meses para arriba rige la ley.` };
  }
  return { ok: true, dias: n, motivo };
}
