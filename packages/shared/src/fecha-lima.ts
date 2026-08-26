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

/**
 * El nombre del mes de una fecha de Lima, en minúscula: `2026-08-04` → «agosto».
 *
 * Va acá y no en la pantalla que lo necesita porque ya se estaba escribiendo
 * suelto en `admin/disciplina`, y un mes escrito de dos formas es la misma
 * clase de problema que dos versiones del corte del día: la carta cita el mes
 * y la pantalla lo nombra, y tienen que decir lo mismo.
 *
 * Se formatea con `timeZone: "UTC"` sobre una fecha construida a mediodía UTC
 * a propósito: la cadena `2026-08-04` YA es una fecha de Lima resuelta, así que
 * volver a aplicarle la zona la correría un día hacia atrás.
 */
export function nombreDelMesLima(fecha: string = hoyLima()): string {
  const [y, m] = fecha.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { month: "long", timeZone: "UTC" })
    .format(new Date(Date.UTC(y, m - 1, 1)))
    .toLocaleLowerCase("es-PE");
}

/** Lo mismo, con la inicial en mayúscula, para abrir un título o una frase. */
export function nombreDelMesLimaTitulo(fecha: string = hoyLima()): string {
  const n = nombreDelMesLima(fecha);
  return n.charAt(0).toLocaleUpperCase("es-PE") + n.slice(1);
}

/**
 * Los primeros de los últimos `cuantos` meses en Lima, del más reciente al más
 * viejo: `["2026-08-01", "2026-07-01", …]`.
 *
 * Existe para el selector de mes de Disciplina, que necesita ofrecer el mes en
 * curso y los anteriores porque el art. 19.4 del Reglamento permite emitir un
 * documento por hechos de un mes ya cerrado.
 *
 * Doce por defecto, y el número no es redondo por gusto: es el horizonte del
 * propio numeral 19.1 c), que mide el antecedente en los doce meses anteriores
 * al hecho. Más atrás, el documento seguiría siendo emitible pero ya no habría
 * antecedente vivo que graduara su escalón.
 *
 * La aritmética va sobre año y mes como enteros, sin pasar por `Date`, porque
 * restarle un mes a un 31 con `setMonth` cae en el mes equivocado.
 */
export function mesesRecientesLima(cuantos = 12, fecha: string = hoyLima()): string[] {
  const [y, m] = fecha.split("-").map(Number);
  const p2 = (n: number) => String(n).padStart(2, "0");
  return Array.from({ length: cuantos }, (_, i) => {
    const total = y * 12 + (m - 1) - i;
    return `${Math.floor(total / 12)}-${p2((total % 12) + 1)}-01`;
  });
}
