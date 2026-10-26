// ============================================================================
// Versión del despliegue — para avisar «hay una versión nueva» sin recargar solos
// ============================================================================
//
// QUÉ PROMETE
//   Que una pestaña abierta con una versión vieja de Dynamic se entere de que
//   Vercel ya publicó otra, y se lo diga a la persona (components/
//   aviso-version-nueva.tsx). Nada más: NO recarga nada por su cuenta.
//
// POR QUÉ NO RECARGA SOLA
//   Quien tiene el panel abierto puede estar a medio escribir un descargo, una
//   corrección o una simulación de planilla. Recargar en silencio se lo lleva.
//   El aviso solo informa; la persona elige cuándo («Actualizar ahora» / «Más
//   tarde»).
//
// DE DÓNDE SALE EL NÚMERO DE VERSIÓN
//   `VERCEL_DEPLOYMENT_ID` (`dpl_…`): es distinto en CADA despliegue y Vercel lo
//   da tanto al construir como al ejecutar. Se hornea en el navegador al
//   construir (`next.config.ts` → `NEXT_PUBLIC_VERSION_DESPLIEGUE`) y el
//   servidor lo devuelve en `/api/version`. Si los dos difieren, la pestaña es
//   de un despliegue anterior. No se usó el hash del commit porque un
//   despliegue por CLI desde un worktree puede no traerlo, y porque un
//   redespliegue del mismo commit con otras variables también es «otra versión».
//
// SE ROMPE SI
//   · Fuera de Vercel (`pnpm dev`, un `next start` local) no hay id: la versión
//     de la página queda vacía y el aviso se apaga entero — ni consulta ni
//     muestra. Es a propósito: un aviso que no puede comparar no inventa nada.
//   · Con «Skew Protection» activa en Vercel, una pestaña vieja queda fijada a
//     SU despliegue, y si la consulta a `/api/version` también se fija,
//     contestaría siempre la versión vieja y el aviso nunca saltaría. El fallo
//     es silencioso y solo hacia el lado seguro (no avisar), nunca hacia el de
//     avisar de más. Se comprueba una vez con un despliegue real: ver
//     docs/estado.md.
// ============================================================================

/** La versión con que se construyó ESTA página. Vacía fuera de Vercel. */
export const VERSION_DE_ESTA_PAGINA: string = process.env.NEXT_PUBLIC_VERSION_DESPLIEGUE ?? "";

/** Cada cuánto se pregunta mientras la pestaña está a la vista. Además se pregunta al volver a ella. */
export const CADA_CUANTO_MS = 3 * 60 * 1000;

/**
 * ¿La versión que dice el servidor es otra distinta de la de esta página?
 * Cualquier cosa que no sea un texto no vacío —una respuesta rota, un `null`,
 * un servidor sin id— NO es una versión nueva: ante la duda no se avisa.
 */
export function hayVersionNueva(deEstaPagina: string, delServidor: unknown): delServidor is string {
  if (!deEstaPagina) return false;
  if (typeof delServidor !== "string") return false;
  const v = delServidor.trim();
  return v.length > 0 && v !== deEstaPagina;
}
