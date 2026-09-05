/**
 * Qué consultas de una pantalla no contestaron, con el nombre de lo que
 * alimentan — no el de la RPC.
 *
 * POR QUÉ EXISTE. Varias pantallas de admin lanzan sus consultas en un
 * `Promise.all` y destructuran solo `data`, tirando el `error`. Cuando una falla
 * no pasa nada visible: la tabla se pinta con lo que quedó, que suele ser cero.
 * En la Hoja de sede eso salía impreso —el equipo entero en «Días 0 · 0h 00m»
 * con el botón de PDF habilitado— y un cero no es la ausencia de un dato: es una
 * afirmación, dice que esa persona no trabajó.
 *
 * Vive aquí y no dentro de la pantalla para poder probarlo: la promesa que hay
 * que defender es que un fallo se NOMBRE, y esa es la parte que no se ve al
 * mirar la pantalla funcionando bien.
 *
 * El nombre que se pasa es el de la COLUMNA, no el de la consulta. Quien lee el
 * aviso está a punto de firmar el papel, no de depurar.
 */
export interface ConsultaVigilada {
  /** Lo que devolvió Supabase en `error`. Cualquier valor no nulo cuenta como fallo. */
  error: unknown;
  /** Qué queda incompleto si esta falla. En minúscula: se concatena en una frase. */
  que: string;
}

/**
 * Devuelve los nombres de lo que no se pudo traer, en el orden en que se
 * declararon. Vacío es el caso normal — y `[]` es la respuesta correcta cuando
 * todo fue bien, no `null`: quien llama pregunta por la longitud.
 */
export function loQueNoSePudo(consultas: ConsultaVigilada[]): string[] {
  return consultas.filter((c) => Boolean(c.error)).map((c) => c.que);
}

/**
 * ¿Se puede entregar este papel?
 *
 * Separado de la lista a propósito: la pantalla decide qué hacer con el aviso
 * —dónde ponerlo, de qué color— pero la respuesta a «¿esto se imprime?» es una
 * sola y no debería reescribirse en cada pantalla que imprima algo.
 *
 * `cargado` entra en la cuenta porque imprimir a medio cargar produce el mismo
 * papel en ceros por otra vía.
 */
export function sePuedeEntregar(cargado: boolean, faltantes: string[]): boolean {
  return cargado && faltantes.length === 0;
}
