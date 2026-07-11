export const SEDES = ["TRU", "LIM", "AQP"] as const;
export type SedeCodigo = (typeof SEDES)[number];

export const ROLES = ["integrante", "supervisor_sede", "lider_do", "admin"] as const;
export type Rol = (typeof ROLES)[number];

/**
 * Tipos de marcaje. Cada categoría de "salida temporal" tiene su par
 * salida_X / retorno_X — la única excepción es entrada/salida_final, que abren
 * y cierran la jornada del día.
 */
export const TIPOS_MARCA = [
  "entrada",
  "salida_final",
  "salida_almuerzo",
  "retorno_almuerzo",
  "salida_personal",
  "retorno_personal",
  "salida_tramite",
  "retorno_tramite",
  "salida_medico",
  "retorno_medico",
  "salida_otro",
  "retorno_otro",
] as const;
export type TipoMarca = (typeof TIPOS_MARCA)[number];

export const ORIGENES_MARCA = ["terminal", "admin_correccion", "auto_cierre", "import_historico"] as const;
export type OrigenMarca = (typeof ORIGENES_MARCA)[number];

export const ESTADOS_JORNADA = ["abierta", "en_pausa", "cerrada", "auto_cerrada_pendiente", "revisada"] as const;
export type EstadoJornada = (typeof ESTADOS_JORNADA)[number];

/** Cada salida_X (excepto salida_otro que también exige motivo) debe cerrarse con su retorno_X correspondiente. */
export const PARES_SALIDA_RETORNO: Record<string, TipoMarca> = {
  salida_almuerzo: "retorno_almuerzo",
  salida_personal: "retorno_personal",
  salida_tramite: "retorno_tramite",
  salida_medico: "retorno_medico",
  salida_otro: "retorno_otro",
};
