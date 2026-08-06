import type {
  EstadoCivil, GradoInstruccion, MotivoCese, RegimenPension, TipoMarca, VinculoDerechohabiente,
} from "./enums";

export const TIPO_MARCA_LABELS: Record<TipoMarca, string> = {
  entrada: "Entrada",
  salida_final: "Salida final",
  salida_almuerzo: "Salida a almuerzo",
  retorno_almuerzo: "Regreso de almuerzo",
  salida_personal: "Salida por asunto personal",
  retorno_personal: "Regreso de asunto personal",
  salida_tramite: "Salida por trámite",
  retorno_tramite: "Regreso de trámite",
  salida_medico: "Salida médica",
  retorno_medico: "Regreso médico",
  salida_otro: "Otra salida",
  retorno_otro: "Regreso",
};

/** Femenino primero, como el resto del sistema (integrante, colaboradora, encargada). */
export const ESTADO_CIVIL_LABELS: Record<EstadoCivil, string> = {
  soltera: "Soltera/o",
  casada: "Casada/o",
  conviviente: "Conviviente",
  divorciada: "Divorciada/o",
  viuda: "Viuda/o",
};

export const GRADO_INSTRUCCION_LABELS: Record<GradoInstruccion, string> = {
  sin_instruccion: "Sin instrucción",
  primaria_incompleta: "Primaria incompleta",
  primaria_completa: "Primaria completa",
  secundaria_incompleta: "Secundaria incompleta",
  secundaria_completa: "Secundaria completa",
  superior_tecnica_incompleta: "Superior técnica incompleta",
  superior_tecnica_completa: "Superior técnica completa",
  superior_universitaria_incompleta: "Superior universitaria incompleta",
  superior_universitaria_completa: "Superior universitaria completa",
  postgrado: "Postgrado",
};

export const VINCULO_DERECHOHABIENTE_LABELS: Record<VinculoDerechohabiente, string> = {
  conyuge: "Cónyuge",
  conviviente: "Conviviente",
  hijo: "Hija/o",
  madre: "Madre",
  padre: "Padre",
  hermano: "Hermana/o",
  otro: "Otro",
};

/**
 * Nombre de cada régimen y la tasa que descuenta hoy, para que el desplegable
 * diga cuánta plata mueve elegir uno y no solo su nombre. Las tasas son las de
 * la migración 0114 (aporte + comisión sobre flujo + prima).
 */
export const REGIMEN_PENSION_LABELS: Record<RegimenPension, string> = {
  onp: "ONP — Sistema Nacional (13.00 %)",
  profuturo: "AFP Profuturo (13.06 %)",
  prima: "AFP Prima (12.97 %)",
  integra: "AFP Integra (12.92 %)",
  habitat: "AFP Habitat (12.84 %)",
};

/**
 * Cómo se lee cada motivo de cese en pantalla.
 *
 * `por_revisar` se dice «sin registrar» a propósito: no es un motivo, es el
 * marcador del backfill de la 0086 para quien no se pudo deducir. Mostrarlo
 * como si fuera una causa lo daría por resuelto, y lo que hace falta es que se
 * note que a esa persona le falta el dato.
 */
export const MOTIVO_CESE_LABELS: Record<MotivoCese, string> = {
  renuncia: "Renunció",
  despido: "Despido",
  fin_contrato: "Terminó su contrato",
  fin_periodo_prueba: "No continuó tras el periodo de prueba",
  fin_servicio_rxh: "Terminó su servicio por recibo por honorarios",
  mutuo_acuerdo: "Mutuo acuerdo",
  por_revisar: "sin registrar",
};

/**
 * Etiqueta de un valor guardado, sea del catálogo o no.
 *
 * Las fichas anteriores a las listas cerradas tienen texto escrito a mano
 * ("Soltero", "sup. completa"…). Ese valor NO se descarta ni se reescribe solo:
 * se muestra tal cual hasta que alguien edite esa ficha y elija de la lista.
 * Perder el dato de alguien por no reconocer cómo se escribió es peor que
 * convivir un tiempo con dos formas de decir lo mismo.
 */
export function etiquetaDeCatalogo(
  valor: string | null | undefined,
  labels: Record<string, string>,
): string | null {
  if (!valor) return null;
  return labels[valor] ?? valor;
}
