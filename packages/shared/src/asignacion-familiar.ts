/**
 * Los S/113 de asignación familiar se deciden en un campo y se declaran en otro.
 *
 * ── EL PROBLEMA QUE ESTA PIEZA VIGILA ───────────────────────────────────────
 *
 * Hay DOS campos, en DOS tablas, para la misma pregunta —«¿tiene hijos menores
 * a su cargo?»— y nada los mantiene de acuerdo:
 *
 *   personas.con_hijos            lo escribe la pantalla de EQUIPO y es el que
 *                                 DECIDE EL PAGO: `fn_planilla_calcular` hace
 *                                 `case when pe.con_hijos then … else 0 end`.
 *
 *   datos_personales.hijos_menores  lo escribe la pantalla de DATOS PERSONALES
 *                                 y es el que SALE EN EL PADRÓN que va al
 *                                 contador para el T-Registro.
 *
 * Ninguna migración menciona los dos a la vez. Ninguna pantalla escribe los dos.
 * Que hoy coincidan en las 21 personas de planilla —medido el 2026-08-10— es
 * mérito de quien los ha ido llenando a mano, no del sistema.
 *
 * ── POR QUÉ NO SE FUSIONAN Y YA ─────────────────────────────────────────────
 *
 * Porque uno de los dos alimenta el cálculo de planilla, y tocar eso exige
 * auditoría empírica contra Postgres en `BEGIN … ROLLBACK`, no un `update`
 * bienintencionado. Mientras tanto, lo barato y sin riesgo es DECIRLO: quien
 * mira la ficha ve que las dos mitades no concuerdan y decide.
 *
 * ── POR QUÉ CADA CASO ES UN CASO ────────────────────────────────────────────
 *
 * No son «un desacuerdo»: son tres situaciones que se arreglan en pantallas
 * distintas y cuestan cosas distintas. Una le debe plata a una persona; otra
 * deja a la empresa declarando lo contrario de lo que paga.
 */

/** Qué le pasa a esta persona entre lo que se le paga y lo que se declara. */
export type DesacuerdoAsignacion =
  /** Las dos mitades dicen lo mismo, o no hay con qué compararlas. */
  | "ninguno"
  /** Se le paga, y la ficha declara que NO tiene hijos menores. */
  | "paga_y_declara_que_no"
  /** La ficha declara que sí, y no se le está pagando. Es plata que se le debe. */
  | "declara_y_no_cobra"
  /** Se le paga, y la ficha no dice nada: el padrón saldrá con «SIN DATO». */
  | "paga_y_la_ficha_calla";

/**
 * Compara las dos mitades.
 *
 * @param paga    `personas.con_hijos` — el que decide el abono. `undefined`
 *                significa que NO SE PUDO CARGAR, y entonces no se concluye
 *                nada: un fallo de red no puede convertirse en un aviso contra
 *                cada persona del equipo. Es distinto de `false`.
 * @param declara `datos_personales.hijos_menores` — el que sale en el padrón.
 *                `null`/`undefined` es «nadie ha llenado la ficha», que NO es
 *                lo mismo que «declaró que no».
 */
export function desacuerdoAsignacionFamiliar(
  paga: boolean | undefined,
  declara: boolean | null | undefined,
): DesacuerdoAsignacion {
  // Sin el campo que paga no hay comparación posible. Callarse es lo correcto.
  if (paga === undefined) return "ninguno";

  if (paga === true && declara === false) return "paga_y_declara_que_no";
  if (paga === false && declara === true) return "declara_y_no_cobra";
  if (paga === true && (declara === null || declara === undefined)) {
    return "paga_y_la_ficha_calla";
  }

  // Queda: los dos true, los dos false, y `paga=false` con la ficha en blanco.
  // Ese último no es un desacuerdo — no se le paga y no se declara nada, que es
  // exactamente lo que corresponde a quien no tiene hijos menores. Avisar ahí
  // pondría un ⚠ en casi todo el equipo y enseñaría a ignorar los avisos.
  return "ninguno";
}
