// Cómo se muestra una sede. Una sola función, para todas las pantallas.
//
// QUÉ PROMETE
//   Que el Taller de Lima y la Tienda de Lima nunca se lean igual: el rótulo
//   sale del TIPO de la sede y de su CIUDAD, que son datos de la tabla `sedes`
//   (0099 y 0279), no de una lista escrita a mano por código. Una sede nueva
//   creada desde /admin/sedes se rotula sola, sin tocar esta función.
//
// QUÉ ASUME
//   Que quien llama trae `codigo`, `nombre`, `tipo` y `ciudad` tal como vienen
//   de la tabla. `ciudad` puede ser null: solo la llenan por SQL y Central la
//   tiene vacía a propósito (0282, «Central no es un local, es una
//   clasificación»).
//
// POR QUÉ EL CÓDIGO VIAJA APARTE
//   El código es la llave de la que cuelgan la planilla y la tarifa de
//   movilidad; no se cambia y no describe nada. Si en una ciudad abren dos
//   tiendas, el título sale igual en las dos —«Tienda · Trujillo»— y lo único
//   que las separa es el código. Por eso `texto` lo lleva siempre. Cuando esa
//   colisión exista de verdad, entra la columna `zona` (decisión de
//   2026-09-19: «cuando haga falta»), no un sufijo dentro del código.
//
// Sin React ni Supabase: se prueba con vitest sin levantar nada.

export const TIPOS_SEDE = ["central", "taller", "tienda"] as const;
export type TipoSede = (typeof TIPOS_SEDE)[number];

/** Cómo se dice cada tipo de local en pantalla. */
export const TIPO_SEDE_LABELS: Record<TipoSede, string> = {
  central: "Central",
  taller: "Taller",
  tienda: "Tienda",
};

export interface SedeParaRotular {
  codigo: string;
  nombre: string;
  /** `string | null` y no `TipoSede`: la base lo garantiza con un check (0099),
   *  pero esta función se queda total aunque llegue algo raro. */
  tipo: string | null;
  ciudad?: string | null;
}

export interface EtiquetaDeSede {
  /** «Taller · Lima», «Tienda · Trujillo», «Central». Nunca vacío. */
  titulo: string;
  /** La llave de la sede, tal cual. */
  codigo: string;
  /** Para un desplegable o un CSV: «Tienda · Trujillo (TRU)». Único mientras
   *  los códigos lo sean, aunque dos sedes compartan título. */
  texto: string;
}

function esTipoSede(t: string | null): t is TipoSede {
  return (TIPOS_SEDE as readonly string[]).includes(t ?? "");
}

export function etiquetaDeSede(s: SedeParaRotular): EtiquetaDeSede {
  const codigo = s.codigo.trim();
  const ciudad = s.ciudad?.trim() ?? "";
  const nombre = s.nombre.trim();
  // Lo que se muestra cuando no se puede armar «Tipo · Ciudad»: el nombre que
  // alguien escribió en /admin/sedes, y si tampoco hay, el código. Nunca vacío.
  const respaldo = nombre || codigo;

  // Una sede `central` no tiene ciudad propia (0282) y por eso no se rotula
  // «Central · algo»: se queda con su nombre. No se le pone la palabra
  // «Central» a secas porque puede haber más de una — en producción están
  // CCO («Central») y OTRU («Oficina TRU»), las dos de tipo central, y un
  // rótulo fijo las habría vuelto idénticas.
  const rotulaPorCiudad = esTipoSede(s.tipo) && s.tipo !== "central" && ciudad !== "";
  const titulo = rotulaPorCiudad ? `${TIPO_SEDE_LABELS[s.tipo as TipoSede]} · ${ciudad}` : respaldo;

  return { titulo, codigo, texto: `${titulo} (${codigo})` };
}
