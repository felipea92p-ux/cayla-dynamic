// ============================================================================
// vinculo.ts — a quién se le habla como trabajadora y a quién no
// ============================================================================
// QUÉ PROMETE  ·  responder, para una persona, si los documentos que CAYLA le
//                 emite deben hablarle como trabajadora (planilla) o como
//                 prestadora de un servicio (locación por honorarios).
// QUÉ ASUME    ·  recibe `en_planilla` tal como lo devuelve el SQL. Nada más:
//                 ni el rol, ni el sueldo fijo, ni si tiene horario.
// QUÉ NO HACE  ·  no decide plata. Los montos ya los deciden `fn_devenga` y
//                 `fn_planilla_calcular` (0196 y 0199). Esto decide PALABRAS.
//
// ── POR QUÉ ESTO NO VIVE EN CADA PANTALLA ───────────────────────────────────
// Porque son nueve las que lo necesitan —boleta, planilla, provisiones,
// liquidaciones, feriados, vacaciones, costos, ausencias, disciplina— y este
// repositorio ya tiene dos cicatrices del mismo corte: 35 copias de la misma
// condición de permiso y 32 del huso horario de Lima. La regla escrita en
// CLAUDE.md sale justo de ahí. Un `f.en_planilla === false` suelto en una
// pantalla es una decisión legal que nadie va a encontrar el día que cambie.
//
// ── POR QUÉ `=== false` Y NO `!en_planilla` ─────────────────────────────────
// `personas.en_planilla` es una columna GENERADA —`tipo_vinculo in
// ('planilla','prueba')`— así que en la base nunca es null. Pero el frontend de
// este proyecto se despliega por Vercel mientras el SQL lo pega Felipe a mano:
// hay ventanas en las que la pantalla nueva corre contra una base que todavía no
// manda el campo, y ahí llega `undefined`.
//
// Con `!en_planilla`, ese `undefined` convertiría a TODO EL MUNDO en locador de
// golpe: treinta personas recibirían un papel que les niega gratificación, CTS y
// vacaciones. Con `=== false`, un dato ausente deja los documentos exactamente
// como estaban. El defecto seguro es el de antes, nunca el nuevo.
// ============================================================================

/**
 * ¿A esta persona hay que hablarle como prestadora de servicios?
 *
 * `true` solo cuando la base dice explícitamente que NO está en planilla.
 * Un dato ausente o desconocido devuelve `false`: se le sigue hablando como
 * trabajadora, que es lo que se venía haciendo.
 */
export function esPrestadorDeServicios(enPlanilla: boolean | null | undefined): boolean {
  return enPlanilla === false;
}

/**
 * El nombre del documento que se le entrega cada periodo.
 *
 * Vive aquí y no en `labels.ts` porque no es una etiqueta de catálogo: es la
 * consecuencia directa de la regla de arriba, y las dos tienen que moverse
 * juntas. Si algún día se separan, alguien va a cambiar una sola.
 */
export function nombreDelDocumentoDePago(enPlanilla: boolean | null | undefined): string {
  return esPrestadorDeServicios(enPlanilla)
    ? "Detalle de servicios prestados"
    : "Boleta interna de pago";
}
