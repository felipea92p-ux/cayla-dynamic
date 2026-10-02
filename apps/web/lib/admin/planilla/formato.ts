// Formatos de fecha y horas de Planilla. Salieron de `admin/planilla/page.tsx`
// el 2026-09-15 porque dos boletas —la del panel y la de «Lo mío»— los
// importaban desde un archivo de página, y una página no es un módulo: cada
// cambio de la pantalla arriesgaba romper la boleta de otra superficie.
//
// Todo lo de acá trabaja sobre cadenas AAAA-MM-DD y aritmética en UTC, a
// propósito: una fecha de periodo no tiene hora, y convertirla a `Date` local
// es la forma clásica de que el 29 amanezca 28.

import { TZ_LIMA } from "@cayla-dynamic/shared";

export const MESES_LARGO = [
  "enero", "febrero", "marzo", "abril", "mayo", "junio",
  "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre",
];
const MESES_ABR = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];

/** "2026-07-28" → "28 jul" */
export function fechaCorta(iso: string): string {
  const [, m, d] = iso.split("-");
  return `${Number(d)} ${MESES_ABR[Number(m) - 1]}`;
}

/** "2026-07-14" → "14/07/2026" — el formato que llevan escrito los conceptos
 *  de «Ya le pagué aparte» y de un desembolso adelantado. */
export function isoADiaMesAnio(iso: string): string {
  const [y, m, d] = iso.split("-");
  return `${d}/${m}/${y}`;
}

/** "2026-06-15" → "15/06" */
export function fechaDiaMes(iso: string): string {
  const [, m, d] = iso.split("-");
  return `${d}/${m}`;
}

/** "2026-07-28" + 1 → "2026-07-29" */
export function sumarDias(iso: string, n: number): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}

/** Días entre dos fechas AAAA-MM-DD, contando los dos extremos. */
export function diasEntre(desde: string, hasta: string): number {
  const [y1, m1, d1] = desde.split("-").map(Number);
  const [y2, m2, d2] = hasta.split("-").map(Number);
  return Math.round((Date.UTC(y2, m2 - 1, d2) - Date.UTC(y1, m1 - 1, d1)) / 86_400_000) + 1;
}

/** timestamptz → "13 jul 2026" en Lima. */
export function fechaLargaLima(iso: string): string {
  return new Intl.DateTimeFormat("es-PE", {
    timeZone: TZ_LIMA, day: "numeric", month: "short", year: "numeric",
  }).format(new Date(iso));
}

/** Por qué un feriado NO le corresponde a esta persona, o null si sí le
 *  corresponde. El motivo lo decide la base (`fn_feriado_devengado_nucleo`):
 *  anterior a su ingreso, o —desde la 0505— posterior a su cese. Una sola
 *  redacción para la tabla, el panel y la boleta: antes la tabla y el panel
 *  escribían cada uno la suya, y solo sabían decir «anterior al ingreso». */
export function feriadoNoCorresponde(d: { antes_ingreso: boolean; despues_cese?: boolean }): string | null {
  if (d.antes_ingreso) return "no corresponde (anterior al ingreso)";
  if (d.despues_cese) return "no corresponde (posterior al cese)";
  return null;
}

export function fmtHoras(n: number): string {
  return `${n.toLocaleString("es-PE", { maximumFractionDigits: 2 })} h`;
}
