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
 *
 * `tipoVinculo` es OPCIONAL y de solo un valor especial (0322): un practicante
 * no es "prestador de servicios" —esa palabra es de un locador— así que sin
 * este dato un practicante recibiría el nombre de un RxH, que es incorrecto
 * pero no peligroso (sigue sin llamarlo "boleta"). Con el dato, se corrige.
 */
export function nombreDelDocumentoDePago(
  enPlanilla: boolean | null | undefined,
  tipoVinculo?: string | null,
): string {
  if (tipoVinculo === "practicante") return "Constancia de subvención";
  return esPrestadorDeServicios(enPlanilla)
    ? "Detalle de servicios prestados"
    : "Boleta interna de pago";
}

/**
 * ¿A esta persona le corresponde tener CUSPP, y por lo tanto hay que pedírselo?
 *
 * Tres condiciones que se descartan por razones DISTINTAS, y por eso no se
 * funden en una:
 *
 *   · No está en planilla → el CUSPP identifica a un TRABAJADOR en el
 *     T-Registro, y una locadora no está en el T-Registro. Su afiliación, si la
 *     tiene, no pasa por CAYLA: desde la 0242 tampoco se le retiene aporte.
 *   · ONP → el sistema nacional no lleva cuentas individuales, así que no hay
 *     código que identificar.
 *   · Jubilada → ya percibe pensión y no aporta (0190).
 *   · Sin régimen cargado → todavía no se sabe. No se pide hasta saberlo, para
 *     no pedir un código que puede no existir.
 *
 * Vive acá y no en la pantalla de fichas porque son dos las que preguntan lo
 * mismo: el aviso de «ficha incompleta» y la exportación del padrón al contador.
 * Con la condición escrita dos veces, la exportación seguiría pidiéndole a una
 * locadora un código que la pantalla ya dejó de pedir.
 *
 * `enPlanilla` se lee con `esPrestadorDeServicios`, así que un campo que no
 * llegó NO exime a nadie: el defecto seguro es seguir pidiendo el CUSPP, no
 * dejar de pedírselo en silencio a las veinte personas que sí lo necesitan.
 */
export function leCorrespondeCuspp(
  enPlanilla: boolean | null | undefined,
  regimenPension: string | null | undefined,
): boolean {
  if (esPrestadorDeServicios(enPlanilla)) return false;
  const regimen = (regimenPension ?? "").trim();
  if (regimen === "" || regimen === "onp" || regimen === "jubilada") return false;
  return true;
}

/**
 * El máximo legal de horas semanales de una practicante, art. 44 Ley 28518.
 * 30h para preprofesional (mientras estudia, convenio tripartito con su
 * centro educativo), 48h para profesional (ya egresó). `null` cuando no es
 * practicante, o cuando lo es pero todavía no se le fijó la modalidad — en
 * ambos casos no hay contra qué avisar, y `null` (nunca un número inventado)
 * es lo que le dice a quien arma el horario que falta un dato, no que no
 * hay límite.
 */
export function maximoSemanalPracticante(
  tipoVinculo: string | null | undefined,
  modalidad: string | null | undefined,
): number | null {
  if (tipoVinculo !== "practicante") return null;
  if (modalidad === "preprofesional") return 30;
  if (modalidad === "profesional") return 48;
  return null;
}
