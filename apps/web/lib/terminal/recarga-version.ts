// ============================================================================
// recarga-version.ts — el terminal se pone al día solo cuando sale una versión
// ============================================================================
//
// QUÉ PROMETE
//   Que la Mac mini de una sede cargue la versión nueva de Dynamic sin que nadie
//   tenga que recargarla a mano (Felipe, 2026-11-03: «quiero que el terminal se
//   actualice de manera automática si es que se realizan cambios»). Antes de
//   esto, una pestaña del terminal podía quedarse días con el código viejo: lo
//   que se publicaba en `main` no llegaba a la sede hasta un reinicio.
//
// POR QUÉ EL TERMINAL SÍ RECARGA SOLO (y el panel no)
//   `components/aviso-version-nueva.tsx` NUNCA recarga solo: en el panel alguien
//   puede estar escribiendo algo que no guardó, y por eso avisa y espera. En el
//   terminal no hay nada a medio escribir que viva en la pantalla: cada marca y
//   cada cambio de ubicación se guarda en IndexedDB ANTES de enviarse
//   (`encolarMarcaje`, `encolarCambio`), y una recarga no lo toca. Lo único que
//   no se puede interrumpir es a una persona marcando. De ahí las tres
//   condiciones de `puedeRecargar`.
//
// QUÉ USA
//   La misma pregunta del panel: `/api/version` contra la versión con la que se
//   construyó esta página (`lib/version-despliegue.ts`). Una sola fuente.
// ============================================================================

/** Cuánto tiempo sin que nadie toque el terminal antes de recargar. */
export const SEGUNDOS_QUIETO_PARA_RECARGAR = 60;

/**
 * ¿Se puede recargar AHORA? Solo si hay versión nueva, el terminal está en la
 * lista de nombres (nadie a medio marcar), no hay un envío en curso, y nadie lo
 * tocó en el último minuto: así no se recarga en la cara de quien se acerca.
 */
export function puedeRecargar(e: {
  hayVersionNueva: boolean;
  pantalla: string;
  enviando: boolean;
  msDesdeUltimoToque: number;
}): boolean {
  return (
    e.hayVersionNueva &&
    e.pantalla === "lista" &&
    !e.enviando &&
    e.msDesdeUltimoToque >= SEGUNDOS_QUIETO_PARA_RECARGAR * 1000
  );
}
