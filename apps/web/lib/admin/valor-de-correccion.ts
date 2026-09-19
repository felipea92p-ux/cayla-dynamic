import { TZ_LIMA } from "@cayla-dynamic/shared";

/**
 * Cómo se lee, en el rastro de un caso, el valor de una corrección.
 *
 * QUÉ PROMETE. Que un instante se muestre en hora de Lima. `correcciones_auditoria`
 * guarda `valor_anterior` y `valor_nuevo` como texto tal como los devuelve
 * Postgres —«2026-09-05 19:28:31.621+00», en UTC—, y el rastro los imprimía
 * crudos: quien leía «19:29» veía cinco horas de más (en Lima eran las 14:29) y
 * podía discutir una corrección con la colaboradora con la hora equivocada.
 *
 * QUÉ NO HACE. Un valor que no es un instante con zona horaria (un nombre, un
 * número, un instante sin zona) se devuelve tal cual: no se adivina.
 */
const INSTANTE = /^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})(\.\d+)?(Z|[+-]\d{2}(?::?\d{2})?)$/;

export function valorDeCorreccion(valor: string | null): string {
  if (valor === null || valor === "") return "—";
  const m = INSTANTE.exec(valor);
  if (!m) return valor;
  const [, dia, hora, fraccion = "", zona] = m;
  // Safari no acepta «+00» ni más de tres decimales: se normaliza antes de leer.
  const ms = fraccion.slice(0, 4);
  const offset = zona === "Z" ? "Z" : zona.length === 3 ? `${zona}:00` : zona.length === 5 ? `${zona.slice(0, 3)}:${zona.slice(3)}` : zona;
  const fecha = new Date(`${dia}T${hora}${ms}${offset}`);
  if (Number.isNaN(fecha.getTime())) return valor;
  return new Intl.DateTimeFormat("es-PE", {
    timeZone: TZ_LIMA, day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false,
  }).format(fecha);
}
