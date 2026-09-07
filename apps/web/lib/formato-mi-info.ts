import { TZ_LIMA } from "@cayla-dynamic/shared";

// Formateadores de fecha/hora que usa «Mi info» (`/mio`) y sus componentes
// hijos (boleta, tendencia, horas de la semana, contratos por firmar).
// Vivían solo dentro de `page.tsx`; se sacan acá cuando un segundo archivo
// necesitó exactamente lo mismo, para no fundar una cuarta copia de "cuántas
// horas son 7.53" en este repo (ya hay varias con nombre `fmtHoras`/
// `comoReloj` repartidas en admin — esta no se suma a esa lista, la
// reemplaza para todo lo que cuelga de «Mi info»).

const MESES = [
  "enero", "febrero", "marzo", "abril", "mayo", "junio",
  "julio", "agosto", "setiembre", "octubre", "noviembre", "diciembre",
];

/** «2026-07-29» → «29 de julio». */
export function diaYMes(iso: string): string {
  const [, m, d] = iso.split("-");
  return `${Number(d)} de ${MESES[Number(m) - 1]}`;
}

/** 7.53 → «7h 32m». La gente cuenta en horas y minutos, no en decimales. */
export function comoReloj(horas: number): string {
  const total = Math.round(horas * 60);
  return `${Math.floor(total / 60)}h ${String(total % 60).padStart(2, "0")}m`;
}

export function comoMinutos(min: number): string {
  if (min < 60) return `${min} min`;
  return `${Math.floor(min / 60)}h ${String(min % 60).padStart(2, "0")}m`;
}

/** La hora de un marcaje, en Lima. Nunca `toLocaleTimeString` a secas: el huso
 *  del navegador no es el que decide a qué día pertenece una marca. */
export function hora(iso: string | null): string {
  if (!iso) return "—";
  return new Intl.DateTimeFormat("es-PE", {
    timeZone: TZ_LIMA, hour: "2-digit", minute: "2-digit", hour12: true,
  }).format(new Date(iso));
}

/** Fecha y hora de un timestamp, en Lima: «20 ago, 1:15 p. m.». */
export function fechaYHora(iso: string): string {
  return new Intl.DateTimeFormat("es-PE", {
    timeZone: TZ_LIMA, day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit", hour12: true,
  }).format(new Date(iso));
}
