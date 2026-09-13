/**
 * CUÁL de tus contratos es «el tuyo», en un solo sitio.
 *
 * Una persona puede tener varias filas vivas en `contratos_generados`: el que
 * firmó en setiembre y la renovación que se generó ayer. La pantalla /mio/contrato
 * muestra UNO, y la Bandeja avisa de UNO — y tienen que ser el mismo papel. Si
 * cada una escribiera su propio `order by`, un día la Bandeja diría «te falta
 * firmar» sobre un contrato distinto del que la pantalla abre, y la persona
 * firmaría el que no era.
 *
 * El orden: el más recientemente generado; a igual generación, el que empieza
 * después; a igual inicio, el que termina después; y `id` al final como ANCLA
 * —es un uuid, no significa nada— para que la respuesta no dependa de en qué
 * orden Postgres decida leer la tabla. Ver CLAUDE.md, la familia de empates de
 * las 0386–0389.
 */

/** Lo mínimo que este módulo necesita de un query de PostgREST. */
interface Ordenable {
  order(columna: string, opciones: { ascending: boolean }): this;
}

/** Aplica, en orden, los cuatro criterios que deciden cuál es el contrato vigente. */
export function ordenarContratoVigente<T extends Ordenable>(q: T): T {
  return q
    .order("generado_at", { ascending: false })
    .order("fecha_inicio", { ascending: false })
    .order("fecha_fin", { ascending: false })
    .order("id", { ascending: false });
}
