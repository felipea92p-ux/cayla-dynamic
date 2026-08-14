import { isAuthRetryableFetchError } from "@supabase/supabase-js";

/**
 * Qué se puede concluir de lo que contestó `auth.getSession()`.
 *
 * POR QUÉ EXISTE. `getSession()` devuelve `session: null` en DOS situaciones que
 * no se parecen en nada, y el terminal las trataba igual:
 *
 *   · no hay ninguna sesión guardada  → `{ session: null, error: null }`
 *   · hay sesión, pero el token de acceso venció y el refresco NO PUDO SALIR
 *     → `{ session: null, error: AuthRetryableFetchError }`
 *
 * El segundo es una tienda con el internet parpadeando, o una Mac que despierta
 * antes que su Wi-Fi. Las credenciales siguen ahí —auth-js NO las borra cuando
 * el fallo es de red, solo cuando el servidor rechaza el refresh token—, pero la
 * pantalla mandaba a «Vincular este dispositivo» igual que si el terminal nunca
 * se hubiera vinculado. Desde fuera se ve como que «se desloguea solo a ratos»,
 * y llega justo cuando peor viene: en el arranque, y a la hora de marcar.
 *
 * El token de acceso dura una hora, así que esto puede tocar a cualquiera varias
 * veces al día sin que nadie toque nada.
 *
 * La regla, entonces: solo se manda a vincular cuando de verdad NO HAY con qué
 * marcar. Si no se pudo averiguar, el terminal sigue trabajando — la cola offline
 * guarda las marcas y las sube cuando el refresco vuelva a salir, que es
 * exactamente para lo que existe.
 */
export type VeredictoSesion = "vinculado" | "sin_vincular" | "no_se_pudo_saber";

/**
 * @param respuesta lo que contestó `getSession()`, o `null` si no contestó a
 *   tiempo (ver `tope-de-red.ts`).
 */
export function veredictoDeSesion(
  respuesta: { session: unknown | null; error: unknown } | null,
): VeredictoSesion {
  if (respuesta === null) return "no_se_pudo_saber";
  if (respuesta.session) return "vinculado";
  // Solo el fallo de RED deja la duda. Un rechazo del servidor —un refresh token
  // caducado o ya usado— sí borra las credenciales del disco: ahí no hay nada
  // que preservar y hay que volver a vincular de verdad.
  if (isAuthRetryableFetchError(respuesta.error)) return "no_se_pudo_saber";
  return "sin_vincular";
}
