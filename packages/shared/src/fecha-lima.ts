/**
 * CUÁNDO ES HOY EN PERÚ — el único lugar donde se decide.
 *
 * El servidor de Vercel corre en UTC y la Mac mini de la sede corre en la hora
 * que tenga puesta. Ninguno de los dos sabe por su cuenta cuándo empieza el día
 * en Lima, y ese corte no es cosmético: decide a qué día se le carga un marcaje,
 * o sea a qué día se le pagan las horas. A las 7pm de Lima ya es el día
 * siguiente en UTC.
 *
 * Hasta agosto de 2026 esto estaba escrito 32 veces en 22 archivos, con cuatro
 * nombres distintos para la misma función (`fechaLimaHoy`, `hoyLima`,
 * `fechaHoyLima`…). Bastaba con que una copia se escribiera distinta para que
 * dos pantallas discreparan sobre qué día es hoy.
 *
 * Perú no tiene horario de verano desde 1994, así que el desfase es -05:00 fijo.
 * Aun así se usa `Intl` con la zona horaria y no un "-5" a mano: si algún día
 * cambia, cambia acá y en ningún otro sitio.
 */

export const TZ_LIMA = "America/Lima";

/** El día de hoy en Lima, como `2026-08-04` (el formato que entiende Postgres). */
export function hoyLima(): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: TZ_LIMA }).format(new Date());
}

/** Cualquier instante, como fecha de Lima `2026-08-04`. */
export function fechaLima(cuando: Date | string): string {
  const d = typeof cuando === "string" ? new Date(cuando) : cuando;
  return new Intl.DateTimeFormat("en-CA", { timeZone: TZ_LIMA }).format(d);
}

/**
 * Los dos extremos de un día de Lima, en formato timestamp, para filtrar
 * marcajes: `.gte(inicio).lte(fin)`.
 *
 * El fin es `23:59:59.999` y no las `00:00` del día siguiente a propósito: los
 * filtros de este sistema usan `lte` (inclusivo), y con un tope abierto un
 * marcaje de medianoche exacta caería en los dos días.
 */
export function rangoDelDiaLima(fecha: string = hoyLima()): { inicio: string; fin: string } {
  return { inicio: `${fecha}T00:00:00-05:00`, fin: `${fecha}T23:59:59.999-05:00` };
}

/** El primer y el último día del mes de una fecha de Lima, como `2026-08-01` / `2026-08-31`. */
export function rangoDelMesLima(fecha: string = hoyLima()): { inicio: string; fin: string } {
  const [y, m] = fecha.split("-").map(Number);
  const ultimoDia = new Date(y, m, 0).getDate();
  const p2 = (n: number) => String(n).padStart(2, "0");
  return { inicio: `${y}-${p2(m)}-01`, fin: `${y}-${p2(m)}-${p2(ultimoDia)}` };
}

/** El primero del mes en curso en Lima, como `2026-08-01`. */
export function primeroDeMesLima(): string {
  return rangoDelMesLima().inicio;
}

/** El año en curso en Lima. */
export function anioLima(): number {
  return Number(hoyLima().slice(0, 4));
}

/** La hora de Lima ahora mismo, como `14:35` (para mostrar en pantalla). */
export function horaLima(cuando: Date | string = new Date()): string {
  const d = typeof cuando === "string" ? new Date(cuando) : cuando;
  return new Intl.DateTimeFormat("es-PE", {
    timeZone: TZ_LIMA, hour: "2-digit", minute: "2-digit", hour12: false,
  }).format(d);
}

/**
 * La hora de Lima como número decimal (14:15 → 14.25).
 *
 * Es la forma en que Turnos, Dashboard y Reporte de sede comparan contra el
 * corte mañana/tarde. Vivía duplicada entre esas tres pantallas.
 */
export function horaDecimalLima(cuando: Date | string = new Date()): number {
  const d = typeof cuando === "string" ? new Date(cuando) : cuando;
  const p = new Intl.DateTimeFormat("en-GB", {
    timeZone: TZ_LIMA, hour: "2-digit", minute: "2-digit", hour12: false,
  }).formatToParts(d);
  const h = Number(p.find((x) => x.type === "hour")?.value ?? 0) % 24;
  const min = Number(p.find((x) => x.type === "minute")?.value ?? 0);
  return h + min / 60;
}
