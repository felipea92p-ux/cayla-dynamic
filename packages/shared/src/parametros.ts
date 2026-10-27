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

/**
 * Un parámetro cuya unidad es «fecha» guarda el día como entero AAAAMMDD (20261026): el catálogo
 * solo conoce números y abrirlo a otro tipo tocaría la puerta que protege los de plata (0557). La
 * pantalla lo dibuja y lo pide como fecha; la base valida que sea un día real al leerlo.
 */
export const UNIDAD_FECHA = "fecha";

export function esUnidadFecha(unidad: string): boolean {
  return unidad === UNIDAD_FECHA;
}

/** 20261026 → «2026-10-26». `null` si no es un día que exista (20261340, 20260230). */
export function fechaDeEntero(n: number): string | null {
  if (!Number.isInteger(n) || n < 10000101 || n > 99991231) return null;
  const t = String(n);
  const y = Number(t.slice(0, 4)), m = Number(t.slice(4, 6)), d = Number(t.slice(6, 8));
  const f = new Date(Date.UTC(y, m - 1, d));
  if (f.getUTCFullYear() !== y || f.getUTCMonth() !== m - 1 || f.getUTCDate() !== d) return null;
  return `${t.slice(0, 4)}-${t.slice(4, 6)}-${t.slice(6, 8)}`;
}

/** «2026-10-26» → 20261026. `null` si no es una fecha escrita así o no existe. */
export function enteroDeFecha(iso: string): number | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(iso)) return null;
  const n = Number(iso.replace(/-/g, ""));
  return fechaDeEntero(n) === iso ? n : null;
}

/** 20261026 → «26/10/2026»; si no es un día real, el número tal cual (no se esconde un dato raro). */
export function textoDeFechaEntera(n: number): string {
  const iso = fechaDeEntero(n);
  if (!iso) return String(n);
  const [y, m, d] = iso.split("-");
  return `${d}/${m}/${y}`;
}

export type ResultadoValidacion = { ok: true; valor: number } | { ok: false; mensaje: string };

/**
 * ¿El texto del campo es un valor aceptable? Acepta coma o punto decimal; no
 * acepta nada que no sea un número ni, en un entero, nada con decimales.
 */
export function validarValorParametro(p: LimitesParametro, texto: string): ResultadoValidacion {
  if (esUnidadFecha(p.unidad)) return validarFechaParametro(p, texto);
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

/** El campo de fecha entrega «2026-10-26»; se guarda como entero y se acota con los mismos límites. */
function validarFechaParametro(p: LimitesParametro, texto: string): ResultadoValidacion {
  const limpio = texto.trim();
  if (limpio === "") return { ok: false, mensaje: "Elige la fecha." };
  const valor = enteroDeFecha(limpio);
  if (valor === null) return { ok: false, mensaje: "Elige una fecha que exista." };
  const { valor_min: min, valor_max: max } = p;
  if ((min !== null && valor < min) || (max !== null && valor > max)) {
    if (min !== null && max !== null) return { ok: false, mensaje: `Va del ${textoDeFechaEntera(min)} al ${textoDeFechaEntera(max)}.` };
    return {
      ok: false,
      mensaje: min !== null ? `Tiene que ser el ${textoDeFechaEntera(min)} o después.` : `Tiene que ser el ${textoDeFechaEntera(max as number)} o antes.`,
    };
  }
  return { ok: true, valor };
}

/** «3 días», «1 día», «4 horas»: la unidad en singular cuando el valor es 1. */
export function valorConUnidad(valor: number, unidad: string): string {
  if (esUnidadFecha(unidad)) return textoDeFechaEntera(valor);
  const unica = unidad.endsWith("s") && Math.abs(valor) === 1 ? unidad.slice(0, -1) : unidad;
  return `${valor} ${unica}`;
}

/** «3 → 5 días»: un cambio dicho en una línea. */
export function describirCambioDeParametro(anterior: number, nuevo: number, unidad: string): string {
  if (esUnidadFecha(unidad)) return `${textoDeFechaEntera(anterior)} → ${textoDeFechaEntera(nuevo)}`;
  return `${anterior} → ${valorConUnidad(nuevo, unidad)}`;
}
