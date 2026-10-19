// ============================================================================
// capa-activa.ts — qué se le pone delante a una persona al abrir un módulo
// ============================================================================
// QUÉ PROMETE · dado lo que se sabe de una persona y un módulo de «Lo mío»,
//               UNA sola respuesta: qué capa va ahora —términos de uso,
//               términos del módulo o guía— o ninguna. Nunca dos.
// QUÉ ASUME   · que quien llama ya leyó las aceptaciones y las pasa tal cual:
//               `null` en cualquier campo es «todavía no sé», y NO es «no hay
//               nada pendiente». Esa diferencia es todo el motivo de este
//               archivo.
//
// EL ORDEN, que es la regla de negocio:
//     1. términos de uso      (una vez, antes de cualquier módulo)
//     2. términos del módulo  (la primera vez que se entra a ese módulo)
//     3. guía del módulo      (solo cuando lo anterior ya está resuelto)
//
// POR QUÉ EXISTE. Hasta el 2026-10-19 la guía de Resumen arrancaba en cuanto
// la pantalla tenía a la persona cargada, sin mirar nada más; lo demás que se
// le pedía —los acuses de ley, el consentimiento del DNI— salía por su lado.
// Cada capa se decidía sola, y dos capas decididas por separado se pisan. Con
// una sola función que contesta por todas, no hay forma de que dos salgan a la
// vez: la respuesta es un valor, no un evento que se puede llegar tarde.
//
// QUÉ HACE CON LO QUE NO SABE (Vogels: la lectura de la base puede fallar).
// Si no se sabe si aceptó los términos, NO se muestra la guía —sería mostrar
// lo que va después de algo que quizá está pendiente— y tampoco se bloquea nada:
// el módulo funciona y se vuelve a preguntar en la próxima carga. Se degrada
// callando, no inventando un «ya aceptó» ni un «falta».
//
// LO QUE NO ES. No dice cómo se dibuja cada capa ni dónde se guarda lo que la
// persona aceptó: las aceptaciones con constancia viven en la base y los avisos
// y la guía en el navegador, y de eso se encarga quien llama.
// ============================================================================

export type Capa = "terminos_de_uso" | "terminos_del_modulo" | "guia";

/**
 * Los términos del módulo, según cuánto pesan (ver docs de la maqueta):
 *  · `aceptacion_pendiente` — con casilla y constancia guardada; BLOQUEA el módulo.
 *  · `aviso_pendiente`      — un «Entendido» sin constancia; se puede dejar para después.
 *  · `sin_terminos`         — el módulo no tiene (o todavía no se ha redactado).
 *  · `resueltos`            — ya aceptó esta versión, o ya vio el aviso.
 */
export type EstadoTerminosModulo =
  | "sin_terminos"
  | "aceptacion_pendiente"
  | "aviso_pendiente"
  | "resueltos";

export type EstadoGuia = "sin_guia" | "pendiente" | "hecha";

export interface EstadoDeCapas {
  /** ¿Aceptó los términos de uso vigentes? `null` = todavía no se sabe. */
  terminosDeUso: boolean | null;
  terminosDelModulo: EstadoTerminosModulo | null;
  guiaDelModulo: EstadoGuia | null;
}

/** La capa que corresponde ahora, o `null` si ninguna (o si todavía no se sabe). */
export function capaActiva(e: EstadoDeCapas): Capa | null {
  if (e.terminosDeUso === null) return null;
  if (e.terminosDeUso === false) return "terminos_de_uso";

  if (e.terminosDelModulo === null) return null;
  if (e.terminosDelModulo === "aceptacion_pendiente" || e.terminosDelModulo === "aviso_pendiente") {
    return "terminos_del_modulo";
  }

  if (e.guiaDelModulo === "pendiente") return "guia";
  return null;
}

/**
 * ¿El módulo no se puede ver todavía? Solo en dos casos acordados: los
 * términos de uso sin aceptar, y un módulo cuyos términos exigen aceptación.
 * Un aviso, una guía o una lectura que falló NUNCA bloquean: una persona que
 * entra a resolver algo urgente no paga por un aviso que no pudo cargar.
 */
export function bloqueaElModulo(e: EstadoDeCapas): boolean {
  if (e.terminosDeUso === false) return true;
  return e.terminosDeUso === true && e.terminosDelModulo === "aceptacion_pendiente";
}
