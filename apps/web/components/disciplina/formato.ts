// Cómo se escriben las fechas en Disciplina. Vivían como funciones sueltas al
// principio de `admin/disciplina/page.tsx`; con el panel del caso las usan dos
// archivos, y dos copias de «cómo se pinta una fecha» terminan diciendo dos
// fechas distintas para el mismo día.

import { TZ_LIMA } from "@cayla-dynamic/shared";

/** Fecha plana (`2026-09-02`) como `02-set.`. Se formatea en UTC para que no se
 *  corra un día por la zona horaria del navegador. */
export function fechaCorta(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "short", timeZone: "UTC" })
    .format(new Date(Date.UTC(y, m - 1, d)));
}

/** Un instante como `26-ago., 02:36 p. m.` en hora de Lima. Nunca cierra una
 *  frase: termina en «p. m.» y un punto detrás se lee «p. m..». */
export function selloLima(iso: string): string {
  const d = new Date(iso);
  if (isNaN(d.getTime())) return iso;
  return new Intl.DateTimeFormat("es-PE", {
    timeZone: TZ_LIMA, day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit", hour12: true,
  }).format(d);
}

/** Suma días a una fecha plana, en calendario. */
export function addDias(iso: string, n: number): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}

/** El último día del mes de una fecha plana (`2026-09-01` → `2026-09-30`). */
export function ultimoDiaDelMes(iso: string): string {
  const [y, m] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m, 0)).toISOString().slice(0, 10);
}
