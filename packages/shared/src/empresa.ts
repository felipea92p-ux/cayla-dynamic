// ============================================================================
// empresa.ts — quién emite los documentos que CAYLA entrega
// ============================================================================
// QUÉ PROMETE  ·  una sola respuesta a «¿cómo se identifica la empresa?», para
//                 que la boleta, el contrato, el memo, las constancias y la
//                 política salarial no puedan decir cosas distintas.
// QUÉ ASUME    ·  nada que cambie a menudo. Si algún día CAYLA cambia de razón
//                 social o de domicilio, se cambia aquí y se acabó.
// QUÉ NO HACE  ·  no decide quién firma cada documento: eso depende del
//                 documento y de la competencia de quien lo suscribe, y vive
//                 en `fn_expediente_puede_suscribir` y en `escalafon.ts`.
//
// ── POR QUÉ EXISTE ──────────────────────────────────────────────────────────
// El 2026-08-19 una auditoría encontró que ni la boleta ni el detalle de
// servicios identifican al empleador. Al ir a arreglarlo aparecieron OCHO
// copias del RUC escritas a mano por el código —tres pantallas de constancias,
// el memo, la documentación, el generador de contratos y la política salarial—
// y ninguna sabía de las otras.
//
// Añadir la novena en la boleta habría sido justo lo que este repositorio ya
// aprendió a no hacer con los permisos y con el huso horario de Lima: cuando el
// mismo dato vive en muchos sitios, el día que cambie solo cambian algunos, y
// nadie se entera hasta que dos documentos firmados se contradicen.
//
// Es un dato de IDENTIDAD LEGAL, no de configuración: no se gestiona desde
// ninguna pantalla, no cambia por sede y no tiene versiones vigentes por fecha.
// Por eso es una constante del código y no una fila de una tabla — que es la
// otra regla de la casa, y esta es su excepción explicada.
// ============================================================================

export const EMPRESA = {
  nombre: "CAYLA S.A.C.",
  ruc: "20605964550",
  // EL DOMICILIO ES EL DE LOS CONTRATOS FIRMADOS, palabra por palabra.
  //
  // Nació aquí el 2026-08-19 en una forma resumida —«Urb. San Andrés,
  // Trujillo, La Libertad»— que no salía de ningún documento: no tenía ni un
  // solo consumidor. El único sitio del sistema que declara un domicilio es la
  // cláusula «DATOS DEL EMPLEADOR» del contrato de trabajo, y ahí dice «V
  // Etapa» y nombra distrito, provincia y departamento.
  //
  // Al unificar había que elegir cuál de las dos era la verdad, y no se puede
  // elegir la corta: le falta la etapa de la urbanización, que es parte de la
  // dirección y no adorno. Se toma la larga, que además deja el contrato
  // renderizado idéntico byte a byte al que ya se ha firmado.
  domicilio:
    "Mza. Q, Lote 26, Urb. San Andrés V Etapa, distrito de Trujillo, provincia de Trujillo, departamento de La Libertad",
} as const;

/**
 * «CAYLA S.A.C. — RUC 20605964550», la forma de un pie de documento.
 *
 * ⚠️ NO SIRVE PARA ADAPTAR UN DOCUMENTO QUE YA EXISTE. Cada papel que CAYLA
 * entrega escribe el RUC a su manera —la boleta «· RUC», las constancias y el
 * memo «· RUC N.°», el contrato «R.U.C. N.°»— y esas formas se respetaron una
 * por una al unificar el dato el 2026-08-19: se migró el VALOR, nunca el
 * formato. Cambiar el texto de un documento con acuses ya firmados es cambiar
 * lo que esas personas firmaron.
 *
 * Es para documentos NUEVOS, que todavía no tienen forma propia que respetar.
 */
export function empresaConRuc(): string {
  return `${EMPRESA.nombre} — RUC ${EMPRESA.ruc}`;
}
