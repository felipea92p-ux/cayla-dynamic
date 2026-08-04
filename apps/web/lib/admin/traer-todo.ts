// Trae TODAS las filas de una consulta, en lotes.
//
// QUÉ PROMETE: devuelve la lista completa, o un error. Nunca un subconjunto
// silencioso.
// QUÉ ASUME: que la consulta trae un orden estable (ver abajo, no es opcional).
// SE ROMPE SI: alguien escribe filas dentro del rango mientras se pagina — un
// lote podría repetir o saltar una fila. Para reportes de días ya cerrados no
// pasa; si algún día se pagina algo que se escribe en vivo, hay que releer.
//
// POR QUÉ EXISTE: PostgREST corta toda respuesta en `max_rows` (1000 en este
// proyecto) y devuelve 200 OK con las primeras N filas. supabase-js no reporta
// nada: `error` viene en null. El CSV de asistencia se descargaba entero, abría
// bien en Excel y simplemente terminaba antes — sin ninguna marca. Ese archivo
// es el que va al contador.
//
// EL ORDEN NO ES DECORATIVO. Paginar con `.range()` sobre una consulta sin
// `order` estable es peor que no paginar: Postgres no garantiza el mismo orden
// entre dos llamadas, así que un lote puede repetir filas y perder otras. Toda
// consulta que pase por acá debe ordenar por algo único (en `jornadas`,
// `fecha` + `persona_id`).

export const TAMANO_LOTE = 1000;

// Tope de seguridad: 200 lotes son 200 000 filas, ~25 años de asistencia de
// todo el equipo. Si se cruza, algo está mal en la consulta y es mejor decirlo
// que colgar el navegador en un bucle.
const MAX_LOTES = 200;

type Respuesta<T> = { data: T[] | null; error: { message: string } | null };

/**
 * @param hacerLote fábrica que construye la consulta para un tramo. Se llama
 *   una vez por lote: un query builder de supabase-js se consume al usarlo, no
 *   se puede reutilizar.
 */
export async function traerTodo<T>(
  hacerLote: (desde: number, hasta: number) => PromiseLike<Respuesta<T>>,
): Promise<Respuesta<T>> {
  const todas: T[] = [];

  for (let lote = 0; lote < MAX_LOTES; lote++) {
    const desde = lote * TAMANO_LOTE;
    const { data, error } = await hacerLote(desde, desde + TAMANO_LOTE - 1);

    if (error) return { data: null, error };

    const filas = data ?? [];
    todas.push(...filas);

    // Un lote incompleto es el final: no hay más filas que pedir.
    if (filas.length < TAMANO_LOTE) return { data: todas, error: null };
  }

  return {
    data: null,
    error: {
      message: `La consulta devolvió más de ${MAX_LOTES * TAMANO_LOTE} filas. No se entrega un resultado incompleto: acota el rango de fechas.`,
    },
  };
}
