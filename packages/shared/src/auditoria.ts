// ============================================================================
// auditoria.ts — qué dice cada `campo_modificado` de correcciones_auditoria
// ============================================================================
// QUÉ PROMETE · que una fila del libro de correcciones se lea igual en toda
//               pantalla: de qué tema es (marcajes, horario, contrato…), cómo
//               se llama en español y, si es una marca apartada, cómo terminó.
// QUÉ ASUME   · que `campo_modificado` es el texto que escribió alguna función
//               de la base. La lista de abajo se compara contra los `insert`
//               de las migraciones en tests/auditoria-campos.test.ts: un campo
//               nuevo sin clasificar rompe esa prueba, no la pantalla.
//
// POR QUÉ EXISTE. El libro nació para los marcajes (0009) y desde la 0119 lo
// usan más de sesenta campos de una docena de temas. Correcciones tenía una
// lista de 7 y /mio otra de 8, y se contradecían: `tipo` y
// `auto_cierre_confirmado` —que SÍ son correcciones de marcaje— salían en
// Correcciones como «otro sistema» con el nombre crudo de la columna. Y una
// marca apartada resuelta como «improcedente» (el día se paga como falta) se
// leía «quedó pendiente de revisión manual», lo contrario de lo ocurrido.
//
// Sin React ni Supabase: se prueba con vitest sin levantar nada.
// ============================================================================

export type TemaAuditoria =
  | "marcaje" | "horario" | "contrato" | "documento" | "educacion"
  | "persona" | "liquidacion" | "otro";

/** Los campos que escriben las puertas de marcaje: lo que esta pantalla corrige. */
export const CAMPOS_DE_MARCAJE: readonly string[] = [
  "timestamp_marca", "tipo", "marcaje_agregado", "marcaje_anulado",
  "marcaje_reactivado", "marcaje_eliminado", "auto_cierre_confirmado",
  "auto_cierre_reemplazado", "marca_apartada", "dia_reabierto_desde_terminal",
];

/** Cómo se dice cada tema, para el aviso «+N cambios de …». */
export const TEMA_AUDITORIA_LABELS: Record<TemaAuditoria, string> = {
  marcaje: "marcajes",
  horario: "horario",
  contrato: "contrato",
  documento: "documentos",
  educacion: "educación",
  persona: "datos de la persona",
  liquidacion: "liquidación",
  otro: "otros cambios",
};

const PREFIJOS: readonly (readonly [string, TemaAuditoria])[] = [
  ["personas.", "persona"],
  ["datos_personales.", "persona"],
  ["asignaciones_regimen_pension.", "persona"],
  ["turnos.", "horario"],
  ["horarios_asignados", "horario"],
  ["horario_", "horario"],
  ["tramo_", "horario"],
  ["contrato_", "contrato"],
  ["documento_", "documento"],
  ["educacion_", "educacion"],
  ["liquidacion_", "liquidacion"],
  ["salario_", "liquidacion"],
  ["reactivacion_", "liquidacion"],
  ["bono_", "persona"],
];

// Campos sueltos que no comparten prefijo con nadie.
const EXACTOS: Record<string, TemaAuditoria> = {
  cargo: "persona",
  rango: "persona",
  descuentos_vivos_tras_anular: "liquidacion",
};

export function temaDeCampo(campo: string): TemaAuditoria {
  if (CAMPOS_DE_MARCAJE.includes(campo)) return "marcaje";
  if (EXACTOS[campo]) return EXACTOS[campo];
  return PREFIJOS.find(([p]) => campo.startsWith(p))?.[1] ?? "otro";
}

export function esCampoDeMarcaje(campo: string): boolean {
  return CAMPOS_DE_MARCAJE.includes(campo);
}

const ROTULOS: Record<string, string> = {
  timestamp_marca: "Hora corregida",
  tipo: "Tipo de marca corregido",
  marcaje_agregado: "Marcaje agregado",
  marcaje_anulado: "Marcaje anulado",
  marcaje_reactivado: "Marcaje reactivado",
  marcaje_eliminado: "Marcaje eliminado",
  auto_cierre_confirmado: "Salida del auto-cierre confirmada",
  auto_cierre_reemplazado: "Salida final repuesta",
  marca_apartada: "Marca apartada",
  dia_reabierto_desde_terminal: "Día reabierto desde el terminal",
  "turnos.horario": "Turno cambiado",
  horarios_asignados: "Horario cambiado",
};

/** El nombre en español de un campo; si no lo conoce, el crudo sin guiones bajos. */
export function rotuloDeCampo(campo: string): string {
  return ROTULOS[campo] ?? campo.replaceAll("_", " ").replaceAll(".", " · ");
}

/**
 * Cómo terminó una marca que el terminal apartó. Lo escribe
 * `fn_marca_apartada_resolver` (0304/0376) en `valor_nuevo`.
 *
 * `improcedente` pesa: no se registra ningún marcaje y el día se paga como si
 * la persona no hubiera venido. Por eso el texto lo dice sin adornos.
 */
export const RESOLUCION_MARCA_APARTADA: Record<string, string> = {
  repuesta: "se registró después, con su hora original",
  improcedente: "se declaró improcedente: no se registró ningún marcaje",
};
