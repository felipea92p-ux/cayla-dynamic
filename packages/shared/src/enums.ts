/**
 * NO hay lista de sedes acá, y es a propósito.
 *
 * Hasta agosto de 2026 vivía aquí un `SEDES = ["TRU","LIM","AQP"]` que ya era
 * falso: faltaba Central (CCO). Desde la migración 0063 las sedes se crean y se
 * apagan desde /admin/sedes, así que cualquier lista escrita a mano queda
 * desactualizada la próxima vez que se abra una tienda. Las sedes se leen de la
 * tabla `sedes`, siempre.
 */

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
 * Regímenes pensionarios cargados en `tasas_pension` (migraciones 0114 y 0328).
 *
 * Esta lista es solo para PINTAR el desplegable. La verdad vive en la tabla, y
 * `fn_cambiar_regimen_pension` valida contra ella — así que si mañana entra una
 * AFP nueva, la función la acepta aunque esta constante todavía no la nombre.
 *
 * (La 0261 la había cableado en un `array[...]` dentro de la función y la 0277
 * la devolvió a la tabla. `fn_set_regimen_pension`, que es quien cumplía esta
 * promesa antes, está retirada desde la 0277: escribía solo la columna, y desde
 * la 0261 la planilla lee el tramo vigente.)
 */
export const REGIMENES_PENSION = [
  "onp",
  // ⇩ CAMBIO 0328 ⇩ CADA AFP APARECE DOS VECES, Y ES A PROPÓSITO.
  //
  // La ley reconoce dos esquemas de comisión y cobran distinto:
  //
  //   comisión MIXTA  · 0 % sobre el sueldo desde febrero de 2023. La AFP cobra
  //     su comisión contra el saldo del fondo, no por la boleta. Se retiene
  //     11.37 % (10 % de aporte + 1.37 % de prima), igual en las cuatro.
  //   comisión SOBRE FLUJO · la AFP cobra su comisión del sueldo. Se retiene
  //     entre 12.84 % y 13.06 % según la AFP.
  //
  // La mixta va PRIMERA en cada par porque es el caso normal: quien se afilió
  // al SPP desde 2013 está en mixta obligatoriamente (Ley 29903), y en flujo
  // solo siguen quienes ya estaban afiliados antes y pidieron quedarse.
  //
  // Hasta la 0328 solo existía el esquema de flujo, así que a quien estaba en
  // mixta se le retenía cada mes una comisión que su AFP no le cobra. Lo
  // encontró el contador el 2026-08-31.
  "profuturo_mixta",
  "profuturo",
  "prima_mixta",
  "prima",
  "integra_mixta",
  "integra",
  "habitat_mixta",
  "habitat",
  // Ya percibe pensión de jubilación, así que NO aporta (0190). Va en la lista
  // a propósito: si no se pudiera elegir, la única forma de expresarlo sería
  // dejar el campo vacío — y un campo vacío se lee como «falta completar esto».
  "jubilada",
] as const;
export type RegimenPension = (typeof REGIMENES_PENSION)[number];

/**
 * Por qué terminó el vínculo. La verdad vive en el CHECK
 * `personas_motivo_cese_valido` (0086, ampliado por la 0143); esta lista es para
 * pintar el desplegable y para que el tipo no deje escribir un valor que la base
 * va a rechazar.
 *
 * No es una etiqueta administrativa: es lo que lee quien arma la liquidación y
 * quien contesta una inspección dos años después. Por eso `fin_contrato` existe
 * aparte de `despido` — un plazo que vence no exige carta de preaviso ni descargo,
 * y llamarlo despido obliga a sostener un expediente que nunca hubo (ver la 0143).
 *
 * `por_revisar` no es un motivo: es el marcador que dejó el backfill de la 0086
 * para quien no se pudo deducir. La pantalla de Equipo lo pinta en ámbar para
 * que se note que falta, en vez de dejarlo pasar por una causa más.
 */
export const MOTIVOS_CESE = [
  "renuncia",
  "fin_contrato",
  "fin_periodo_prueba",
  "fin_servicio_rxh",
  "fin_convenio_practicas",
  "mutuo_acuerdo",
  "despido",
  "por_revisar",
] as const;
export type MotivoCese = (typeof MOTIVOS_CESE)[number];

/** Cada salida_X (excepto salida_otro que también exige motivo) debe cerrarse con su retorno_X correspondiente. */
export const PARES_SALIDA_RETORNO: Record<string, TipoMarca> = {
  salida_almuerzo: "retorno_almuerzo",
  salida_personal: "retorno_personal",
  salida_tramite: "retorno_tramite",
  salida_medico: "retorno_medico",
  salida_otro: "retorno_otro",
};

/**
 * La escala disciplinaria del RIT art. 7 sobre el D.S. 003-97-TR art. 25, en
 * orden. El sistema llega hasta `imputacion` y ahí se detiene: el despido se
 * decide después de leer los descargos (art. 31) y no lo genera ninguna
 * función.
 *
 * ⚠️ Esto son NOMBRES, no la regla. Qué escalón le toca hoy a una persona lo
 * responde `fn_tardanza_escalon` en la base (migración 0200), que es el único
 * sitio donde vive la escala. Escribir aquí un umbral en números sería la
 * segunda copia que la 0200 existió para borrar.
 */
export const NIVELES_DISCIPLINARIOS = [
  "verbal",
  "amonestacion",
  "suspension",
  "imputacion",
  "despido",
] as const;
export type NivelDisciplinario = (typeof NIVELES_DISCIPLINARIOS)[number];
