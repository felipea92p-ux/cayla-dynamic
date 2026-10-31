// ============================================================================
// parametros.ts — los números del sistema que se cambian desde «Parámetros» (0552)
// ============================================================================
// QUÉ PROMETE · el vocabulario y la validación de lo que se teclea, en funciones
//               puras: cómo se llama cada CLASE de parámetro y si un texto
//               escrito en el campo es un valor aceptable para uno concreto.
// QUÉ ASUME   · que el catálogo (nombre, unidad, mínimo, máximo, entero o
//               decimal) lo trae la base (`fn_parametros_listar`): aquí no se
//               repite ninguno de esos números.
// QUÉ NO HACE · no decide quién puede cambiar qué (eso es `puedeCambiarParametro`
//               en permisos.ts) ni escribe nada. Y NO sustituye a la base: la
//               validación de acá solo evita un viaje de ida y vuelta; la que
//               manda es la de `fn_parametro_cambiar` y su trigger, que valen por
//               cualquier camino.
//
// Sin React ni Supabase: se prueba con vitest sin levantar nada.
// ============================================================================

/**
 * La clase decide quién lo toca y con qué cuidado (0552):
 *   · operativo — lo decide DO; rige desde que se cambia.
 *   · plata     — mueve un pago: exige vigencia y vista previa (rebanada 2).
 *   · normativo — ley o RIT: solo la dirección, y solo si el catálogo lo declara
 *                 editable (hoy ninguno lo es).
 */
export type ClaseParametro = "operativo" | "plata" | "normativo";

export const CLASES_PARAMETRO: readonly ClaseParametro[] = ["operativo", "plata", "normativo"];

export const ETIQUETA_CLASE_PARAMETRO: Record<ClaseParametro, string> = {
  operativo: "Operativo",
  plata: "Mueve un pago",
  normativo: "Fijado por norma",
};

/** Lo que el catálogo dice de un parámetro y la validación necesita. */
export interface LimitesParametro {
  nombre: string;
  unidad: string;
  tipo_valor: "entero" | "decimal";
  valor_min: number | null;
  valor_max: number | null;
}

export type ResultadoValidacion = { ok: true; valor: number } | { ok: false; mensaje: string };

/**
 * ¿El texto del campo es un valor aceptable? Acepta coma o punto decimal; no
 * acepta nada que no sea un número ni, en un entero, nada con decimales.
 */
export function validarValorParametro(p: LimitesParametro, texto: string): ResultadoValidacion {
  const limpio = texto.trim().replace(",", ".");
  if (limpio === "") return { ok: false, mensaje: "Escribe el valor nuevo." };
  // Solo dígitos con un punto opcional: `Number("1e3")` o `Number("0x10")` no son lo que una persona quiso decir.
  if (!/^-?\d+(\.\d+)?$/.test(limpio)) return { ok: false, mensaje: "Escribe solo un número." };
  const valor = Number(limpio);
  if (p.tipo_valor === "entero" && !Number.isInteger(valor)) {
    return { ok: false, mensaje: "Tiene que ser un número entero." };
  }
  const { valor_min: min, valor_max: max } = p;
  if ((min !== null && valor < min) || (max !== null && valor > max)) {
    if (min !== null && max !== null) return { ok: false, mensaje: `Va de ${min} a ${max} ${p.unidad}.` };
    return {
      ok: false,
      mensaje: min !== null ? `Tiene que ser de ${min} ${p.unidad} o más.` : `Tiene que ser de ${max} ${p.unidad} o menos.`,
    };
  }
  return { ok: true, valor };
}

/** «3 días», «1 día», «4 horas»: la unidad en singular cuando el valor es 1. */
export function valorConUnidad(valor: number, unidad: string): string {
  const unica = unidad.endsWith("s") && Math.abs(valor) === 1 ? unidad.slice(0, -1) : unidad;
  return `${valor} ${unica}`;
}

/** «3 → 5 días»: un cambio dicho en una línea. */
export function describirCambioDeParametro(anterior: number, nuevo: number, unidad: string): string {
  return `${anterior} → ${valorConUnidad(nuevo, unidad)}`;
}

/**
 * Quién puede cambiar un parámetro, dicho para una persona (0571). Recibe la lista
 * `roles_cambia` de la fila: una sola entrada es la dirección; dos son la
 * dirección y Desarrollo Organizacional (los únicos roles que entran a
 * Parámetros). Lista vacía = la base aún no trae la columna: no se afirma nada.
 */
export function etiquetaQuienCambia(roles: readonly string[] | null | undefined): string | null {
  if (!roles || roles.length === 0) return null;
  return roles.length === 1 ? "Lo cambia: la dirección" : "Lo cambian: la dirección y Desarrollo Organizacional";
}
