// ============================================================================
// rpc-estricto.ts — el freno que le faltaba a `supabase.rpc(...)`
// ============================================================================
//
// QUÉ ARREGLA
//   Hasta hoy, esto compilaba sin una sola queja:
//
//       await supabase.rpc("fn_expediente_generar_falta", {
//         p_persona_id: personaId,
//         p_inventado_xyz: 1,          // ← este parámetro no existe
//       })
//
//   El cliente SÍ está tipado con `SupabaseClient<Database>`, y la cadena de
//   tipos SÍ funciona: un nombre de función inventado falla, un parámetro
//   obligatorio que falta falla, y un tipo equivocado falla. Lo único que se
//   colaba —medido el 2026-08-26— era un parámetro DE MÁS.
//
// POR QUÉ SE COLABA
//   Por la forma de la firma de `rpc` en supabase-js (2.110.2):
//
//       rpc<FnName extends …, Args extends Schema['Functions'][FnName]['Args']>
//          (fn: FnName, args?: Args, …)
//
//   `Args` no es el tipo del parámetro: es un parámetro de tipo que se INFIERE
//   del objeto que le pasas. TypeScript solo revisa después que lo inferido
//   cumpla la restricción `extends …['Args']`, y esa es una comprobación de
//   asignabilidad normal — y en asignabilidad normal sobrar propiedades está
//   permitido. La comprobación de «propiedades en exceso» solo actúa cuando el
//   objeto literal se compara contra un tipo CONCRETO, y aquí nunca lo hace.
//
//   Se comprobó fijando el parámetro de tipo a mano: con
//   `supabase.rpc<"fn_expediente_generar_falta", { p_persona_id: string | null }>`
//   el mismo objeto falla con TS2353. Sin fijarlo, pasa.
//
// POR QUÉ IMPORTA
//   PostgREST resuelve qué función llamar por el conjunto EXACTO de nombres de
//   parámetros que recibe. Un parámetro de más o mal escrito no se ignora: la
//   llamada entera se rechaza con PGRST202 «Could not find the function …».
//   O sea que cada uno de estos es un botón que da error en producción, y solo
//   se descubre cuando alguien lo pulsa.
//
// QUÉ HACE
//   Reemplaza la firma de `rpc` por otra idéntica salvo en el parámetro `args`,
//   que pasa por `SinArgumentosDeMas`: cualquier clave que no exista en la
//   función declarada queda tipada como `never`, así que el objeto literal deja
//   de ser asignable y el typecheck falla.
//
//   El TIPO DE RETORNO no se reimplementa: se le pide al propio supabase-js con
//   una expresión de instanciación (`typeof rpcOriginal<F, A>`, TS 4.7+). Eso
//   importa porque calcularlo a mano exigiría copiar
//   `GetRpcFunctionFilterBuilderByArgs`, que no está exportado y que distingue
//   escalares, funciones que devuelven TABLE y las ocho que llevan
//   `SetofOptions`. Copiado, se desincronizaría en la primera actualización;
//   delegado, no hay nada que se pueda desincronizar.
//
// CÓMO SE COMPRUEBA QUE SIGUE ENCENDIDO
//   `rpc-estricto.prueba-de-tipos.ts`, al lado de este archivo. Si alguien
//   deshace este freno, esa prueba NO se queda callada: falla el typecheck.
// ============================================================================

import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "./types";

type Funciones = Database["public"]["Functions"];

/** Los nombres de función que existen de verdad en el esquema `public`. */
export type NombreFuncion = string & keyof Funciones;

/** El cliente tal cual lo entrega supabase-js, con su `rpc` permisivo. */
type ClienteBase = SupabaseClient<Database>;

/**
 * Solo existe para poder escribir `typeof rpcOriginal<F, A>` abajo. Nunca se
 * evalúa: `declare const` no genera código.
 */
declare const rpcOriginal: ClienteBase["rpc"];

/** Lo que devolvería la llamada original — calculado por supabase-js, no por nosotros. */
type RetornoRpc<F extends NombreFuncion, A extends Funciones[F]["Args"]> = ReturnType<
  typeof rpcOriginal<F, A>
>;

/**
 * Los nombres de parámetro que `F` acepta.
 *
 * Los dos condicionales están para que DISTRIBUYAN, y cada uno cubre una unión
 * distinta. Sin ellos `keyof (ArgsA | ArgsB)` daría las claves COMUNES a las
 * dos —a menudo `never`— y el freno rechazaría hasta las llamadas correctas.
 *
 *   · `F extends unknown` cubre que el NOMBRE sea una unión. Pasa cuando el
 *     sitio de llamada no lo escribe literal, como la pantalla de Disciplina:
 *     `const fn = tipo === "tardanza" ? "fn_…_tardanza" : "fn_…_falta"`.
 *
 *   · `Sobrecarga extends { Args: … }` cubre que la FUNCIÓN esté sobrecargada
 *     en SQL. `supabase gen types` las emite como una unión de bloques, y este
 *     esquema tiene tres: `fn_set_meta_cobertura` con `p_meta` y con
 *     `p_meta_manana`/`p_meta_tarde`, `fn_educacion_cerrar` con y sin
 *     `p_motivo`, y `fn_set_datos_personales`.
 *
 * En los dos casos el freno se afloja exactamente lo que la llamada renunció a
 * precisar, en vez de romperse: sigue rechazando el parámetro que no existe en
 * NINGUNA sobrecarga, que es el error que se quería cazar. De elegir cuál de
 * las sobrecargas encaja ya se ocupa la restricción de supabase-js.
 */
type ClavesDe<F extends NombreFuncion> = F extends unknown
  ? Funciones[F] extends infer Sobrecarga
    ? Sobrecarga extends { Args: infer A }
      ? keyof A
      : never
    : never
  : never;

/**
 * `A`, pero con cada clave que no esté en `Permitidas` tipada como `never`.
 *
 * Es la única forma de expresar «este objeto y NINGUNA clave más» en un sitio
 * donde el tipo se infiere: no se puede prohibir lo desconocido, pero sí se
 * puede envenenar lo que sobra.
 */
type SinArgumentosDeMas<A, Permitidas extends PropertyKey> = A & {
  [K in Exclude<keyof A, Permitidas>]: never;
};

/** Las opciones de `rpc`, copiadas tal cual de la firma original. */
type OpcionesRpc = {
  head?: boolean;
  get?: boolean;
  count?: "exact" | "planned" | "estimated";
};

/**
 * El cliente de Supabase de esta casa: idéntico al de la librería salvo que su
 * `rpc` no acepta parámetros que la función no declara.
 */
export interface ClienteCayla extends Omit<ClienteBase, "rpc"> {
  rpc<F extends NombreFuncion, A extends Funciones[F]["Args"] = never>(
    fn: F,
    args?: SinArgumentosDeMas<A, ClavesDe<F>>,
    options?: OpcionesRpc,
  ): RetornoRpc<F, A>;
}
