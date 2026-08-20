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
  domicilio: "Mza. Q, Lote 26, Urb. San Andrés, Trujillo, La Libertad",
} as const;

/** «CAYLA S.A.C. — RUC 20605964550», que es como se lee en un pie de documento. */
export function empresaConRuc(): string {
  return `${EMPRESA.nombre} — RUC ${EMPRESA.ruc}`;
}
