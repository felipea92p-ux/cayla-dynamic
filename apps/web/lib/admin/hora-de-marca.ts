/**
 * La hora que se escribe a mano en Correcciones, convertida al instante que
 * guarda la base.
 *
 * Promete: devuelve `fecha` + hora con el desfase de Lima, o `null` si la hora
 * no es una hora completa. Nunca arma un instante con un pedazo vacío.
 *
 * Por qué existe (2026-11-13): el campo «Hora» mostraba «03:00 p.m.» y la
 * pantalla mandó `2026-11-13T:00-05:00`. El navegador entrega `""` mientras la
 * hora está a medio escribir (falta un segmento: hora, minutos o a. m./p. m.),
 * y a veces no vuelve a avisar cuando se completa. Antes ese vacío viajaba
 * hasta Postgres y volvía como «invalid input syntax for type timestamp», un
 * mensaje que nadie en una sede puede leer. Ahora se frena acá, con palabras.
 *
 * El desfase -05:00 es fijo: Perú no tiene horario de verano (ver fecha-lima.ts).
 */

const HORA = /^([01]\d|2[0-3]):([0-5]\d)(:[0-5]\d(\.\d+)?)?$/;

/** «HH:MM» si `valor` es una hora completa (acepta segundos y los descarta). */
export function horaCompleta(valor: string | null | undefined): string | null {
  const m = HORA.exec((valor ?? "").trim());
  return m ? `${m[1]}:${m[2]}` : null;
}

/** Instante ISO en hora de Lima, o `null` si la hora no está completa. */
export function instanteDeMarca(fecha: string, hora: string | null | undefined): string | null {
  const hhmm = horaCompleta(hora);
  if (!hhmm || !/^\d{4}-\d{2}-\d{2}$/.test(fecha)) return null;
  return `${fecha}T${hhmm}:00-05:00`;
}

export const AVISO_HORA_INCOMPLETA =
  "La hora no está completa. Escribe la hora, los minutos y a. m. o p. m., y vuelve a intentarlo.";
