// ============================================================================
// ritmo.ts — cuánto espera el terminal después de cada toque
// ============================================================================
//
// QUÉ PROMETE
//   Que desde que alguien elige qué marcar hasta que la lista queda libre para
//   la persona siguiente pasen unos DOS segundos más lo que tarde la base, y no
//   casi seis. Lo pidió Felipe el 2026-11-17: «cuando le doy a salir a
//   refrigerio o cualquier otro siento que tarda mucho, sería ideal bajar esa
//   espera a 2 segundos».
//
// QUÉ SE MIDIÓ ANTES DE TOCAR NADA (2026-11-17, en un navegador de verdad
// contra una base local, o sea sin la red de una sede: en producción se suma)
//   · Sin tocar «Confirmar ahora»: el «Listo» salía a los 3,4 s y la lista
//     volvía a los 5,8 s.
//   · Tocando «Confirmar ahora»: la lista volvía a los 2,9 s.
//   El envío a la base era 0,1 s de todo eso. La espera no era de la red ni de
//   la base: eran dos relojes puestos a mano, uno detrás del otro —3 s de
//   cuenta atrás y 2,5 s de cartel—, y durante el segundo la pantalla no le
//   servía a nadie: quien marcó ya se había ido y quien venía no podía tocar.
//
// QUÉ CAMBIA
//   1. La cuenta atrás baja de 3 s a 2 s. Sigue existiendo: es la única
//      ventana para arrepentirse, y en la entrada y los regresos —donde tocar
//      el nombre ya es la marca— es lo único que separa un dedo en la casilla
//      de al lado de una marca a nombre de otra persona.
//   2. El «Listo» deja de ocupar la pantalla. La lista vuelve en cuanto la base
//      contesta y la confirmación queda encima, como un aviso que no tapa las
//      casillas ni recibe toques: la persona siguiente marca sin esperar a que
//      se vaya.
//   3. La mala noticia NO se acorta. Un rechazo, una Mac sin vínculo o un
//      equipo sin configurar siguen ocupando la pantalla entera sus ocho
//      segundos: es lo único que la persona lee antes de irse.
//
// DECIDÍ: una ventana corta para cancelar y después nada que bloquee.
// DESCARTÉ:
//   · Quitar la cuenta atrás cuando la opción se eligió en el menú. Ahorra los
//     2 s, pero un toque equivocado entre «refrigerio» y «salida final» queda
//     marcado sin vuelta, y aquí una marca de más es plata mal pagada.
//   · Marcar al instante con un botón «Deshacer». Es lo que hacen los relojes
//     de ADP o UKG, pero ellos identifican a la persona con clave o tarjeta, y
//     deshacer exige anular una marca ya guardada desde el terminal: una
//     función nueva sobre lo que alimenta el pago. No se justifica para 2 s.
//   · Decir «Listo» antes de que la base conteste. El cartel solo dice «Listo»
//     cuando lo está; eso costó aprenderlo (ver `confirmarMarcaje`).
//
// SE ROMPE SI
//   Alguien sube `SEGUNDOS_CONFIRMACION` o vuelve a hacer que una buena noticia
//   ocupe la pantalla: la espera vuelve sin que nada falle. Lo vigila
//   `tests/terminal-ritmo.test.ts`.
// ============================================================================

/** Cuánto dura la cuenta atrás en la que todavía se puede cancelar una marca. */
export const SEGUNDOS_CONFIRMACION = 2;

/** Cuánto se queda el «Listo» sobre la lista. No bloquea: la lista ya está libre. */
export const SEGUNDOS_AVISO_LISTO = 4;

/**
 * Con una segunda línea que hay que leer («Hoy te toca almacén de … a …»), un
 * poco más. Antes esa línea tenía 2,5 s a pantalla completa; ahora tiene más
 * tiempo y no detiene a nadie.
 */
export const SEGUNDOS_AVISO_LISTO_CON_DETALLE = 6;

/**
 * Un rechazo se queda MÁS TIEMPO y a pantalla completa. Unos segundos bastan
 * para leer «Listo»; no bastan para leer que no quedó registrada, entenderlo y
 * decidir ir a buscar a la líder de equipo. El que trae mala noticia espera.
 */
export const SEGUNDOS_MENSAJE_ALERTA = 8;

export type TonoMensaje = "ok" | "alerta";

export interface PlanDeMensaje {
  /** `true`: ocupa la pantalla y nadie más puede marcar hasta que se vaya. */
  ocupaLaPantalla: boolean;
  /** Cuánto se queda a la vista. */
  segundos: number;
}

/**
 * Cómo se muestra el resultado de una marca: la buena noticia no detiene la
 * fila; la mala sí, y más tiempo. Es la única regla, y vale para todo lo que el
 * terminal confirma: una marca, un cambio a almacén o un día reabierto.
 */
export function planDeMensaje(tono: TonoMensaje, tieneDetalle: boolean): PlanDeMensaje {
  if (tono === "alerta") return { ocupaLaPantalla: true, segundos: SEGUNDOS_MENSAJE_ALERTA };
  return {
    ocupaLaPantalla: false,
    segundos: tieneDetalle ? SEGUNDOS_AVISO_LISTO_CON_DETALLE : SEGUNDOS_AVISO_LISTO,
  };
}
