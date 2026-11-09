import { createTerminalSupabaseClient } from "@cayla-dynamic/database";
import { conTope } from "./tope-de-red";

/**
 * ¿Está la hora de esta Mac donde debería?
 *
 * `marcajes.timestamp_marca` —el dato del que cuelga a qué día se paga, si hubo
 * tardanza y cuántas horas se trabajaron— lo pone ESTE navegador con el reloj de
 * ESTA Mac. Hasta el 2026-08-12 nadie lo verificaba: una Mac adelantada media
 * hora convertía una entrada puntual en una tardanza de treinta minutos, y no
 * dejaba rastro. El número entra perfecto; solo que es de otro momento.
 *
 * NO BLOQUEA NADA, y es la decisión de Felipe: medir y avisar. Un terminal que
 * se niega a registrar porque su reloj está corrido deja a la sede sin poder
 * fichar, y perder una marca real es peor que tener una con la hora movida —
 * la hora se corrige después con rastro; la marca que no existe, no.
 */

/**
 * A partir de cuántos segundos se avisa.
 *
 * DOS MINUTOS, y el número sale de cómo se mide una tardanza: por MINUTO, sin
 * tolerancia (`fn_recalcular_jornada`). Un desfase de dos minutos ya puede
 * inventar o borrar una tardanza de dos minutos, que es exactamente el orden de
 * magnitud de las que este sistema registra de verdad — la de Keyla del 3 de
 * agosto fue de dos.
 *
 * Más abajo sería ruido: un reloj sincronizado por NTP baila segundos, y un
 * aviso que sale todos los días se deja de mirar a la semana.
 */
export const DESFASE_AVISO_SEG = 120;

/**
 * A partir de cuántos se dice que el DÍA puede estar mal.
 *
 * Una hora todavía mueve horas y tardanzas dentro del mismo día. Pasadas varias,
 * un marcaje de la noche puede caer del otro lado de la medianoche de Lima y
 * pagarse en otra jornada — que es un error de otra naturaleza y hay que
 * nombrarlo distinto.
 */
export const DESFASE_GRAVE_SEG = 3600;

const CLAVE_CACHE = "cayla.desfase_reloj";

export interface MedidaDesfase {
  /** Segundos: positivo si esta Mac va ADELANTADA respecto del servidor. */
  segundos: number;
  /** Cuándo se midió, en hora de esta Mac (solo para saber si está rancia). */
  medidoEn: string;
}

/**
 * Mide el desfase contra el servidor, descontando la ida y vuelta.
 *
 * La resta cruda `servidor - local` incluiría el viaje de la petición y daría un
 * desfase falso proporcional a lo lenta que esté la red — en una sede con mala
 * conexión, un aviso permanente por un reloj perfecto. Se estima como lo hace
 * NTP: se supone que el servidor contestó a mitad de camino.
 *
 *     local_equivalente = t0 + (t1 - t0) / 2
 *     desfase           = local_equivalente - servidor
 *
 * Con eso, media hora de reloj corrido se sigue viendo como media hora, y medio
 * segundo de latencia se queda en un cuarto de segundo de error.
 *
 * NUNCA LANZA. Sin red devuelve null y quien llama se queda con la última
 * medida buena: un corte de internet no es una noticia sobre el reloj.
 */
export async function medirDesfase(): Promise<MedidaDesfase | null> {
  try {
    const cliente = createTerminalSupabaseClient();
    const t0 = Date.now();
    // El casteo del nombre: `packages/database/src/types.ts` es un archivo
    // GENERADO y no conoce todavía `fn_ahora_servidor` (0230). Regenerarlo hoy
    // cambia los argumentos opcionales de `string | null` a `string | undefined`
    // y rompe tres pantallas — está medido y anotado en docs/estado.md como una
    // migración de tipos aparte.
    const llamada = cliente.rpc("fn_ahora_servidor" as never) as unknown as
      PromiseLike<{ data: string | null; error: unknown }>;
    const respuesta = await conTope(llamada, null);
    const t1 = Date.now();
    if (!respuesta || respuesta.error || !respuesta.data) return null;

    const servidorMs = new Date(respuesta.data).getTime();
    if (!Number.isFinite(servidorMs)) return null;

    const localEquivalente = t0 + (t1 - t0) / 2;
    const medida: MedidaDesfase = {
      segundos: Math.round((localEquivalente - servidorMs) / 1000),
      medidoEn: new Date().toISOString(),
    };
    try {
      window.localStorage.setItem(CLAVE_CACHE, JSON.stringify(medida));
    } catch {
      // Sin almacén local se pierde entre recargas y no pasa nada: se vuelve a
      // medir al arrancar. No es motivo para no avisar ahora.
    }
    return medida;
  } catch {
    return null;
  }
}

/**
 * La última medida guardada, para que el aviso esté en pantalla desde el primer
 * segundo y no solo después de la primera medición del día.
 *
 * Un reloj corrido no se arregla solo al recargar la página; que el aviso
 * desaparezca al reiniciar el terminal sería justo el comportamiento que
 * convierte un problema permanente en uno intermitente y por tanto invisible.
 */
export function leerDesfaseCacheado(): MedidaDesfase | null {
  try {
    const crudo = window.localStorage.getItem(CLAVE_CACHE);
    if (!crudo) return null;
    const m = JSON.parse(crudo) as MedidaDesfase;
    return typeof m?.segundos === "number" ? m : null;
  } catch {
    return null;
  }
}

/** Cómo se dice un desfase en la pantalla de una sede, no en un log. */
export function textoDesfase(segundos: number): string {
  const abs = Math.abs(segundos);
  const adelantada = segundos > 0;
  const cuanto =
    abs >= 3600
      ? `${Math.round(abs / 3600)} h`
      : abs >= 120
        ? `${Math.round(abs / 60)} min`
        : `${abs} s`;
  return `El reloj de esta Mac va ${cuanto} ${adelantada ? "ADELANTADO" : "ATRASADO"}`;
}
