// ============================================================================
// terminos-mios.ts — qué falta aceptar, visto desde «Lo mío» (parte pura)
// ============================================================================
// QUÉ PROMETE · convierte lo que se leyó (aceptaciones de la base, avisos del
//               navegador) y el catálogo de `terminos.ts` en el `EstadoDeCapas`
//               que `capaActiva` espera. Sin React, sin Supabase, sin navegador:
//               se prueba con vitest.
// QUÉ ASUME   · que quien llama ya sabe si pudo leer. `cargando` y `error` NO son
//               «no ha aceptado»: devuelven `null` en lo que dependía de esa
//               lectura, y `capaActiva` hace con eso lo que corresponde (no
//               mostrar la guía, no bloquear nada).
//
// QUÉ DICE CUANDO NO HAY NADA APROBADO. Con todos los textos en borrador no hay
// qué aceptar: `terminosDeUso` es `true`, `terminosDelModulo` es «sin_terminos»
// y la capa que sale es solo la guía —o ninguna—. Es decir, esta pieza no cambia
// NADA de lo que ve hoy una integrante hasta que alguien apruebe un texto.
// ============================================================================

import {
  TERMINOS, terminosVigentes,
  type EstadoDeCapas, type EstadoTerminosModulo, type TerminosModulo,
} from "@cayla-dynamic/shared";

/** Cómo salió la lectura de las aceptaciones de la base. */
export type LecturaAceptaciones = "cargando" | "error" | "lista";

/** La clave con que se identifica «este módulo, esta versión» — en el Set de la base y en el navegador. */
export function claveDeTerminos(t: Pick<TerminosModulo, "modulo" | "version">): string {
  return `${t.modulo}:${t.version}`;
}

/** La llave del navegador para un aviso ya visto. Va por módulo Y versión: una versión nueva lo vuelve a mostrar. */
export function llaveDeAviso(t: Pick<TerminosModulo, "modulo" | "version">): string {
  return `cayla-aviso-${t.modulo}-v${t.version}`;
}

/** ¿Hay algún texto aprobado? Si no, no hace falta ni leer la base: no hay nada que comparar. */
export function hayTerminosAprobados(catalogo: readonly TerminosModulo[] = TERMINOS): boolean {
  return catalogo.some((t) => t.estado === "aprobado");
}

export interface EntradaEstado {
  modulo: string;
  /** ¿Este módulo tiene una guía propia? Hoy solo «resumen». */
  tieneGuia: boolean;
  lecturaAceptaciones: LecturaAceptaciones;
  /** Claves (`modulo:version`) de lo que consta aceptado en la base. */
  aceptadas: ReadonlySet<string>;
  /** ¿Ya se leyó del navegador qué avisos se vieron? Antes de eso no se sabe. */
  avisosLeidos: boolean;
  /** Claves de los avisos ya vistos, o dejados para después en esta visita. */
  avisosVistos: ReadonlySet<string>;
  catalogo?: readonly TerminosModulo[];
}

export function estadoDeCapas(e: EntradaEstado): EstadoDeCapas {
  const catalogo = e.catalogo ?? TERMINOS;
  const uso = terminosVigentes("general", catalogo);
  // «general» en sí no tiene «términos del módulo»: son los mismos de uso.
  const modulo = e.modulo === "general" ? null : terminosVigentes(e.modulo, catalogo);

  let terminosDeUso: boolean | null;
  if (!uso) terminosDeUso = true;
  else if (e.lecturaAceptaciones !== "lista") terminosDeUso = null;
  else terminosDeUso = e.aceptadas.has(claveDeTerminos(uso));

  let terminosDelModulo: EstadoTerminosModulo | null;
  if (!modulo) {
    terminosDelModulo = "sin_terminos";
  } else if (modulo.peso === "aceptacion") {
    terminosDelModulo = e.lecturaAceptaciones !== "lista"
      ? null
      : e.aceptadas.has(claveDeTerminos(modulo)) ? "resueltos" : "aceptacion_pendiente";
  } else {
    // `aviso` y `constancia_propia`: no dejan fila en la base, viven en el navegador.
    terminosDelModulo = !e.avisosLeidos
      ? null
      : e.avisosVistos.has(claveDeTerminos(modulo)) ? "resueltos" : "aviso_pendiente";
  }

  return {
    terminosDeUso,
    terminosDelModulo,
    guiaDelModulo: e.tieneGuia ? "pendiente" : "sin_guia",
  };
}
