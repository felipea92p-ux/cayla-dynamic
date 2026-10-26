import { TZ_LIMA } from "@cayla-dynamic/shared";

/**
 * Cómo se dicen las cifras y las horas en las pantallas de Educación.
 *
 * Salieron de `page.tsx` cuando el visor de constancias, la cuadrícula y el panel
 * empezaron a necesitar las mismas dos: si cada pieza escribe la suya, una dice
 * «S/ 104.25» y otra «S/104,25», y quien audita se pregunta si son dos montos.
 */

export const soles = (n: number): string =>
  `S/ ${Number(n).toLocaleString("es-PE", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

/** «03/10/2026 · 14:05», en hora de Lima. Un instante sin valor se dice «—». */
export function fechaHora(ts: string | null): string {
  if (!ts) return "—";
  const f = new Intl.DateTimeFormat("es-PE", {
    timeZone: TZ_LIMA, day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit", hour12: false,
  }).formatToParts(new Date(ts));
  const p = (t: string) => f.find((x) => x.type === t)?.value ?? "";
  return `${p("day")}/${p("month")}/${p("year")} · ${p("hour")}:${p("minute")}`;
}
