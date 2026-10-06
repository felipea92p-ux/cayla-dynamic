// ============================================================================
// documento.ts — Qué documento de identidad acepta Dynamic, y con qué forma
// ============================================================================
// Hasta el 2026-10-06 `personas.documento` era un número suelto: el alta no lo
// pedía y la corrección aceptaba «8 a 12 letras o números» sin saber de qué.
// Por eso alguien escribió un DNI dentro del apellido (0512), y por eso el
// único freno determinista contra registrar dos veces a la misma persona —el
// índice único de documento— no actuaba sobre las altas.
//
// Desde la 0513 cada documento lleva su TIPO, y el tipo decide la forma:
//
//   · DNI                        exactamente 8 dígitos (con el cero adelante
//                                que traen los de generación anterior)
//   · Carné de extranjería       de 9 a 12 letras o números (el actual tiene 9;
//                                los antiguos llegan a 12 con letras)
//   · Pasaporte / PTP            de 6 a 12 letras o números (varía por país;
//                                el PTP/CPP tiene 9)
//
// Decidido con Felipe el 2026-10-06. La base tiene LA MISMA regla en
// `fn_documento_forma_valida` (0513), que usan el candado de la tabla, el alta
// y la corrección. `tests/documento.test.ts` compara las dos mitades: si se
// cambia aquí, se cambia allá.
// ============================================================================

export const TIPOS_DOCUMENTO = ["dni", "ce", "pasaporte"] as const;
export type TipoDocumento = (typeof TIPOS_DOCUMENTO)[number];

export const TIPO_DOCUMENTO_LABEL: Record<TipoDocumento, string> = {
  dni: "DNI",
  ce: "Carné de extranjería",
  pasaporte: "Pasaporte / PTP",
};

/** La forma de cada tipo. Mismo texto que la 0513: lo vigila la prueba. */
export const FORMA_DOCUMENTO: Record<TipoDocumento, RegExp> = {
  dni: /^[0-9]{8}$/,
  ce: /^[0-9A-Z]{9,12}$/,
  pasaporte: /^[0-9A-Z]{6,12}$/,
};

/** Lo que se le dice a quien lo escribe mal: el largo exacto, no «inválido». */
export const AYUDA_DOCUMENTO: Record<TipoDocumento, string> = {
  dni: "El DNI tiene exactamente 8 dígitos.",
  ce: "El carné de extranjería tiene de 9 a 12 letras o números.",
  pasaporte: "El pasaporte o PTP tiene de 6 a 12 letras o números.",
};

export function esTipoDocumento(valor: unknown): valor is TipoDocumento {
  return typeof valor === "string" && (TIPOS_DOCUMENTO as readonly string[]).includes(valor);
}

/**
 * Cómo se guarda: sin espacios ni guiones y en mayúsculas. La base hace lo
 * mismo (`upper(regexp_replace(…))`), así que «ab-123 456» y «AB123456» son el
 * mismo pasaporte y el índice único los ve iguales.
 */
export function normalizarDocumento(numero: string): string {
  return numero.replace(/[\s.-]/g, "").toUpperCase();
}

/** `null` si está bien; si no, la frase que dice qué falta. */
export function errorDeDocumento(tipo: TipoDocumento | "", numero: string): string | null {
  if (!esTipoDocumento(tipo)) return "Elige el tipo de documento.";
  const limpio = normalizarDocumento(numero);
  if (limpio === "") return `Falta el número de ${TIPO_DOCUMENTO_LABEL[tipo]}.`;
  return FORMA_DOCUMENTO[tipo].test(limpio) ? null : AYUDA_DOCUMENTO[tipo];
}
