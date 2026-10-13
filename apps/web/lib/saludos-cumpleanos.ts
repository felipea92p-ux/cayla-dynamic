/**
 * El saludo de cumpleaños de Info (/mio): los 16 mensajes y cuándo se muestra.
 *
 * POR QUÉ EXISTE. El 2026-10-13 Daniel Ruiz cumplía en octubre y no vio nada en
 * su Info ni en su Bandeja, mientras Desarrollo Organizacional (DO) sí veía su
 * bono como pendiente. La tarjeta del bono solo aparecía si el bono le
 * correspondía (`mostrarBonoEnInfo`), así que a quien la base le contesta
 * `no_aplica` —hoy, una practicante— el sistema no le decía nada en el mes de
 * su cumpleaños. El saludo se separa del bono a propósito: saludar no depende
 * de si hay plata de por medio, y el bono sigue decidiéndolo la base.
 *
 * QUÉ NO VA ACÁ. Ni montos ni la palabra «bono»: el saludo le aparece también a
 * quien no tiene bono, y no puede prometerle nada que la base después le niegue.
 * `tests/saludos-cumpleanos.test.ts` lo vigila.
 */

import type { MiBono } from "./mi-bono";

/** Dieciséis, ni uno más ni uno menos: lo pidió Cayla el 2026-10-13. */
export const SALUDOS_CUMPLEANOS: readonly string[] = [
  "El equipo entero celebra que estés aquí. Que este mes te traiga todo lo que llevas tiempo esperando.",
  "Gracias por todo lo que pones en cada jornada. Este mes es tuyo: disfrútalo sin apuro.",
  "Cada sede es mejor porque tú estás en ella. ¡Feliz cumpleaños!",
  "Que este nuevo año te encuentre con salud, con ganas y con la gente que quieres cerca.",
  "Detrás de cada prenda que sale hay manos como las tuyas. Este mes te toca a ti recibir el cariño.",
  "Un año más de aprender, crecer y compartir. Nos alegra mucho que lo vivas con nosotros.",
  "Que no te falten motivos para sonreír, ni este mes ni los once que vienen.",
  "Celebrarte es fácil: haces que el trabajo se sienta en equipo. ¡Muchas felicidades!",
  "Que este año te traiga nuevos retos, de los que se disfrutan y de los que se aprenden.",
  "No hay pendiente más importante que celebrarte. ¡Feliz mes de cumpleaños!",
  "Gracias por tu paciencia, tu esfuerzo y tu buena energía. Este mes, todo eso vuelve a ti.",
  "Que la vida te devuelva multiplicado todo lo bueno que compartes con el equipo.",
  "Brindamos por ti, por lo que has logrado y por todo lo que todavía viene.",
  "Un cumpleaños es una buena excusa para recordarte lo mucho que vales para CAYLA.",
  "Que cada día de este mes tenga algo pequeño que te alegre. Te lo mereces.",
  "De parte de todo el equipo: ¡feliz cumpleaños! Que sea un gran año para ti.",
];

/** Cada cuánto cambia el mensaje solo, en milisegundos. Lento a propósito: se tiene que poder leer entero. */
export const SALUDO_CADA_MS = 9000;

/**
 * ¿Es su mes de cumpleaños? Desde el día 1 hasta el último, sin importar el
 * estado del bono: también para `no_aplica`, que es justamente el caso que se
 * quedaba en silencio. `mes_cumpleanos` lo manda `fn_mi_bono_cumpleanos` en
 * todos sus estados menos `sin_fecha`, donde no hay fecha que leer.
 */
export function esMesDeCumpleanos(b: MiBono | null | undefined, hoy: string): boolean {
  return b?.mes_cumpleanos != null && b.mes_cumpleanos === Number(hoy.slice(5, 7));
}

/**
 * Con qué mensaje arranca. Por el día del mes, para que dos visitas en días
 * distintos no abran siempre con el mismo, y dos personas que entran el mismo
 * día vean el mismo (nada al azar: lo que se ve tiene que poder reproducirse).
 */
export function saludoInicial(hoy: string): number {
  return (Number(hoy.slice(8, 10)) - 1) % SALUDOS_CUMPLEANOS.length;
}
