/**
 * Qué decir en Correcciones cuando el día tiene la salida que puso el auto-cierre.
 *
 * QUÉ PROMETE. Responde, para las marcas de un día, las tres preguntas que la
 * pantalla tiene que contestar igual que la base desde la 0605:
 *   1. Si se agrega una salida final, ¿la del sistema se retira sola, o la base
 *      lo va a rechazar porque DO ya la confirmó?
 *   2. ¿El día ya quedó con dos salidas finales activas (los días de antes de la
 *      0605)? Y en ese caso, ¿cuál se está pagando?
 *   3. ¿Se puede pulsar «Confirmar» sobre la del sistema, o ya hay otra salida?
 *
 * DE DÓNDE SALE LA REGLA. De la 0605 (fn_agregar_marcaje y
 * fn_confirmar_auto_cierre), que a su vez copia la 0320 del terminal. La base
 * es la que decide: esto solo evita que la pantalla ofrezca algo que la base va
 * a rechazar, o que pase algo sin que se diga.
 *
 * QUÉ NO HACE. No sabe de periodos pagados ni de expedientes formales: esos
 * rechazos los sigue diciendo la base con su propio mensaje.
 */

export interface MarcaDelDia {
  id: string;
  tipo: string;
  origen: string;
  estado_revision: string;
  anulada_at: string | null;
  timestamp_marca: string;
}

const esSalidaFinalActiva = (m: MarcaDelDia) => m.tipo === "salida_final" && m.anulada_at === null;
const esDelSistema = (m: MarcaDelDia) => m.origen === "auto_cierre";

/** La salida final que puso el auto-cierre y sigue activa, si la hay. */
export function salidaDelSistema(marcas: MarcaDelDia[]): MarcaDelDia | null {
  return marcas.find((m) => esSalidaFinalActiva(m) && esDelSistema(m)) ?? null;
}

export type AvisoAlAgregar =
  | { clase: "se_retira"; sistema: MarcaDelDia }
  | { clase: "confirmada"; sistema: MarcaDelDia };

/**
 * Qué pasa si se agrega una marca de tipo `tipo` a este día. null = nada especial.
 * Solo una salida final toca la del sistema; cualquier otra marca la deja como está.
 */
export function avisoAlAgregar(tipo: string, marcas: MarcaDelDia[]): AvisoAlAgregar | null {
  if (tipo !== "salida_final") return null;
  const sistema = salidaDelSistema(marcas);
  if (!sistema) return null;
  return sistema.estado_revision === "revisada"
    ? { clase: "confirmada", sistema }
    : { clase: "se_retira", sistema };
}

export interface DosSalidas {
  sistema: MarcaDelDia;
  otra: MarcaDelDia;
  /** La que paga hoy fn_recalcular_jornada: la más tardía. */
  pagada: MarcaDelDia;
}

/**
 * El día de antes de la 0605 que quedó con la salida del sistema y otra salida
 * final, las dos activas. null si no es el caso.
 */
export function dosSalidasFinales(marcas: MarcaDelDia[]): DosSalidas | null {
  const sistema = salidaDelSistema(marcas);
  if (!sistema) return null;
  const otras = marcas
    .filter((m) => esSalidaFinalActiva(m) && m.id !== sistema.id)
    .sort((a, b) => Date.parse(b.timestamp_marca) - Date.parse(a.timestamp_marca));
  const otra = otras[0];
  if (!otra) return null;
  const pagada = Date.parse(otra.timestamp_marca) >= Date.parse(sistema.timestamp_marca) ? otra : sistema;
  return { sistema, otra, pagada };
}

/** ¿Se puede confirmar esta marca del sistema? No, si el día ya tiene otra salida final. */
export function sePuedeConfirmar(marca: MarcaDelDia, marcas: MarcaDelDia[]): boolean {
  return !marcas.some((m) => esSalidaFinalActiva(m) && m.id !== marca.id);
}
