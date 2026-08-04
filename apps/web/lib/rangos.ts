// Las bandas de CAYLA y la base que cada una declara.
//
// ── QUÉ ES ESTE NÚMERO ──────────────────────────────────────────────────────
//
// `baseDeclarada` es el monto que se declara en el PLAME por una persona de ese
// rango, y es TAMBIÉN lo que el sistema paga: va a los dos campos que intervienen
// en el cálculo —`asignaciones_salario.salario_mensual_soles` (que paga) y
// `personas.sueldo_base_legal` (que declara)—. Si quedaran distintos, la boleta
// mostraría un desglose que no corresponde a nada.
//
// Lo que la persona recibe de más se compone con conceptos NO remunerativos:
// movilidad supeditada a asistencia, asignación por educación y bono de
// cumpleaños. Esa parte no vive acá porque es por persona, no por rango.
//
// ── POR QUÉ NO HAY NINGÚN «TOPE» NI «MÁXIMO» EN ESTE ARCHIVO ────────────────
//
// Antes había un campo `salarioSugerido` con los montos 1,320 · 1,450 · 1,650 ·
// 1,890 · 2,250 · 3,000, que eran lo que cada rango *debería terminar
// recibiendo*. Se BORRARON a pedido de Felipe (2026-08-03), y la razón es
// defensiva: un número guardado que diga «esta persona debería recibir 1,450»
// es un número que puede contradecir lo que efectivamente cobró. Si no existe,
// no hay nada que contradiga nada.
//
// Esos montos hacían además un daño concreto: la pantalla de Equipo los
// pre-llenaba al elegir el rango, así que abrir la ficha de alguien que cobraba
// 1,130 y tocar el desplegable le saltaba el salario a 1,320 — un aumento de
// S/190 a un clic de distancia, sin que nadie lo pidiera.
//
// ── LA ESTRUCTURA DEL 2026-08-04 ────────────────────────────────────────────
//
// Felipe rehízo la escala completa. Solo colibrí se queda en la RMV (1,130); a
// partir de cayla cada rango declara algo más, y los rangos altos BAJAN respecto
// de la escala anterior (archicaylo de 2,670 a 1,500; oráculo de 1,810 a 1,440).
//
// Esa bajada es deliberada y está asumida: reduce la CTS, la gratificación, las
// vacaciones y la pensión futura de quien ya estaba en esos rangos, porque las
// cuatro se calculan sobre lo declarado. Se compensa con los conceptos no
// remunerativos (movilidad, educación, bono). Caylo va igualado a cayla.
//
// ── SI CAMBIA LA RMV ────────────────────────────────────────────────────────
//
// Colibrí está clavado en el piso legal (1,130). Se anunció el 28/07/2026 una
// subida a S/1,300, pero Felipe estima que la norma demora un año o más; cuando
// salga, TODO lo que esté por debajo de la RMV nueva —hoy colibrí, cayla, caylo
// y support— tiene que subir o queda bajo el mínimo. La prueba
// «ninguna base declarada cae por debajo de la RMV vigente» es el recordatorio:
// se pone roja en cuanto se actualice la constante RMV del test.
// La RMV del sistema vive versionada en `parametros_laborales` desde la 0116;
// este archivo hay que actualizarlo a mano.
//
// Los códigos tienen que coincidir con el CHECK de la migración 0019
// (`asignaciones_salario.rango`) y con la lista de `fn_fijar_base_declarada`
// (migración 0128).

export interface Rango {
  codigo: string;
  label: string;
  /** Monto que se declara en el PLAME y que el sistema paga. Editable por persona. */
  baseDeclarada: number;
  /**
   * TECHO mensual de la asignación por educación de ese rango — no un monto a pagar.
   * Cada persona cobra el 75% de la pensión que sostiene SU comprobante, y este
   * número es lo máximo que ese 75% puede llegar a ser. Ver la migración 0132.
   */
  topeEducacion: number;
  orden: number;
}

export const RANGOS: Rango[] = [
  { codigo: "colibri", label: "Colibrí", baseDeclarada: 1130, topeEducacion: 90, orden: 1 },
  { codigo: "cayla", label: "Cayla", baseDeclarada: 1185, topeEducacion: 180, orden: 2 },
  { codigo: "caylo", label: "Caylo", baseDeclarada: 1185, topeEducacion: 180, orden: 3 },
  { codigo: "support", label: "Support", baseDeclarada: 1260, topeEducacion: 270, orden: 4 },
  { codigo: "aurora", label: "Aurora", baseDeclarada: 1360, topeEducacion: 360, orden: 5 },
  { codigo: "oraculo", label: "Oráculo", baseDeclarada: 1440, topeEducacion: 420, orden: 6 },
  { codigo: "archicaylo", label: "ArchiCaylo", baseDeclarada: 1500, topeEducacion: 480, orden: 7 },
];

/** El techo de educación de ese rango. */
export function topeEducacionDe(codigo: string): number | undefined {
  return RANGOS.find((r) => r.codigo === codigo)?.topeEducacion;
}

export const RANGO_LABEL: Record<string, string> = Object.fromEntries(
  RANGOS.map((r) => [r.codigo, r.label]),
);

/** La base que declara ese rango. Se propone al elegirlo, y se puede pisar. */
export function baseDeclaradaDe(codigo: string): number | undefined {
  return RANGOS.find((r) => r.codigo === codigo)?.baseDeclarada;
}

export function formatSoles(n: number): string {
  return new Intl.NumberFormat("es-PE", {
    style: "currency",
    currency: "PEN",
    minimumFractionDigits: 2,
  }).format(n);
}
