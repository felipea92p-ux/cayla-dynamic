// CUÁNTOS DÍAS FALTAN — contados AL ENVIAR, no al generar la fila.
//
// PROMETE: los días entre HOY (Lima) y la fecha de vencimiento que trae el
// payload de la alerta. Es una resta de fechas de calendario, sin horas.
// ASUME: `hoy` llega como `2026-10-25` (lo da `hoyLima()` de
// `@cayla-dynamic/shared`; esta función no lo calcula para poder probarse con
// cualquier día) y la fecha del payload como `2026-11-05`, que es como Postgres
// serializa un `date` dentro de un jsonb.
//
// POR QUÉ. Las migraciones 0356/0357 guardan en el payload `dias_restantes` y
// `dias_para_vencer` calculados cuando se GENERA la fila. El cron de correo es
// diario y una fila fallida se reintenta hasta tres DÍAS después: un correo que
// salió el día 3 seguía diciendo «vence en 12 días» cuando ya eran 9. La
// fecha, en cambio, no envejece. Por eso se recalcula contra hoy al enviar, y
// el número del payload queda solo como respaldo si la fecha falta o no parsea.

const RE_FECHA = /^(\d{4})-(\d{2})-(\d{2})$/;
const MS_POR_DIA = 86_400_000;

/** `2026-10-25` → día absoluto (UTC, sin horas). null si no es una fecha de calendario real. */
function diaAbsoluto(fecha: unknown): number | null {
  if (typeof fecha !== "string") return null;
  const m = RE_FECHA.exec(fecha.trim());
  if (!m) return null;
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  const t = Date.UTC(y, mo - 1, d);
  const v = new Date(t);
  // Date.UTC "arregla" 2026-02-31 a marzo; una fecha inventada no debe pasar.
  if (v.getUTCFullYear() !== y || v.getUTCMonth() !== mo - 1 || v.getUTCDate() !== d) return null;
  return Math.round(t / MS_POR_DIA);
}

/** Días de `hoy` a `fecha`: 0 = hoy mismo, negativo = ya pasó. null si alguna no parsea. */
export function diasHasta(fecha: unknown, hoy: string): number | null {
  const f = diaAbsoluto(fecha);
  const h = diaAbsoluto(hoy);
  if (f === null || h === null) return null;
  return f - h;
}

/**
 * Los días que debe decir el correo: los de la FECHA contra hoy; si la fecha
 * falta o no parsea, el número que trajo el payload (como se hacía antes);
 * si tampoco hay, null.
 */
export function diasAlEnviar(fecha: unknown, diasDelPayload: unknown, hoy: string): number | null {
  const calculados = diasHasta(fecha, hoy);
  if (calculados !== null) return calculados;
  const n = typeof diasDelPayload === "number" ? diasDelPayload : typeof diasDelPayload === "string" && diasDelPayload.trim() !== "" ? Number(diasDelPayload) : NaN;
  return Number.isFinite(n) ? Math.trunc(n) : null;
}

/**
 * «vence en 12 días», «vence mañana», «vence hoy», «venció ayer», «venció hace
 * 3 días». Con null (no hay fecha ni número) no inventa un plazo: «vence pronto».
 * `verbo` es lo que va en el asunto; `plazo` es el complemento solo (para el
 * cuerpo, donde la fecha ya va escrita aparte).
 */
export function fraseDePlazo(dias: number | null): { verbo: "vence" | "venció"; plazo: string | null; frase: string } {
  if (dias === null) return { verbo: "vence", plazo: null, frase: "vence pronto" };
  if (dias === 0) return { verbo: "vence", plazo: "hoy", frase: "vence hoy" };
  if (dias === 1) return { verbo: "vence", plazo: "mañana", frase: "vence mañana" };
  if (dias > 1) return { verbo: "vence", plazo: `en ${dias} días`, frase: `vence en ${dias} días` };
  if (dias === -1) return { verbo: "venció", plazo: "ayer", frase: "venció ayer" };
  return { verbo: "venció", plazo: `hace ${-dias} días`, frase: `venció hace ${-dias} días` };
}
