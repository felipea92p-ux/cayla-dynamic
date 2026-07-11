import type { TipoMarca } from "./enums";

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
