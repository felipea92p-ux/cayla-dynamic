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

/**
 * Estado civil de la ficha personal.
 *
 * Las cuatro primeras son las que RENIEC imprime en el DNI. `conviviente` no es
 * un estado civil registral, pero la unión de hecho sí está reconocida en el
 * Perú (art. 326 del Código Civil) y es frecuente en el equipo: sin esa opción
 * la persona marca "soltera" y se pierde el dato real para contratos.
 *
 * La columna en base de datos sigue siendo `text` libre a propósito — hay
 * fichas antiguas escritas a mano y no se descartan (ver ETIQUETAS abajo).
 */
export const ESTADOS_CIVILES = [
  "soltera",
  "casada",
  "conviviente",
  "divorciada",
  "viuda",
] as const;
export type EstadoCivil = (typeof ESTADOS_CIVILES)[number];

/**
 * Grado de instrucción, con la escala del INEI para que los datos del equipo
 * sean comparables con estadísticas oficiales.
 *
 * Se distingue completa/incompleta en cada tramo superior: es la diferencia que
 * de verdad pesa en un contrato y la que se pierde con una lista corta.
 */
export const GRADOS_INSTRUCCION = [
  "sin_instruccion",
  "primaria_incompleta",
  "primaria_completa",
  "secundaria_incompleta",
  "secundaria_completa",
  "superior_tecnica_incompleta",
  "superior_tecnica_completa",
  "superior_universitaria_incompleta",
  "superior_universitaria_completa",
  "postgrado",
] as const;
export type GradoInstruccion = (typeof GRADOS_INSTRUCCION)[number];

/**
 * Vínculo familiar de un derechohabiente.
 *
 * Los cinco primeros son los que acepta el T-Registro para inscribir a alguien
 * ante EsSalud; los tres últimos existen porque el Seguro de Vida Ley
 * (D.Leg. 688) alcanza a ascendientes y hermanos menores cuando no hay cónyuge
 * ni descendientes. La misma tabla sirve para los dos propósitos, así que la
 * lista tiene que cubrir ambos.
 */
export const VINCULOS_DERECHOHABIENTE = [
  "conyuge",
  "conviviente",
  "hijo",
  "madre",
  "padre",
  "hermano",
  "otro",
] as const;
export type VinculoDerechohabiente = (typeof VINCULOS_DERECHOHABIENTE)[number];

/**
 * Regímenes pensionarios cargados en `tasas_pension` (migración 0114).
 *
 * Esta lista es solo para PINTAR el desplegable. La verdad vive en la tabla, y
 * `fn_set_regimen_pension` valida contra ella — así que si mañana entra una AFP
 * nueva, la función la acepta aunque esta constante todavía no la nombre.
 */
export const REGIMENES_PENSION = [
  "onp",
  "profuturo",
  "prima",
  "integra",
  "habitat",
] as const;
export type RegimenPension = (typeof REGIMENES_PENSION)[number];

/** Cada salida_X (excepto salida_otro que también exige motivo) debe cerrarse con su retorno_X correspondiente. */
export const PARES_SALIDA_RETORNO: Record<string, TipoMarca> = {
  salida_almuerzo: "retorno_almuerzo",
  salida_personal: "retorno_personal",
  salida_tramite: "retorno_tramite",
  salida_medico: "retorno_medico",
  salida_otro: "retorno_otro",
};
