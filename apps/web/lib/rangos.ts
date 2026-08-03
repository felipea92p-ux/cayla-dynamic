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
// ── COLIBRÍ Y CAYLA DECLARAN LO MISMO, Y ES A PROPÓSITO ─────────────────────
//
// Los dos en 1,130, que es la RMV (D.S. 006-2024-TR). En la planilla cobran
// igual; la diferencia entre los dos rangos vive en los conceptos. Decisión de
// Felipe del 2026-08-03. Consecuencia asumida: alguien de cayla que no estudia
// cobra lo mismo que alguien de colibrí.
//
// ── SI CAMBIA LA RMV ────────────────────────────────────────────────────────
//
// Colibrí y cayla están clavados en el piso legal. Cuando se publique el decreto
// que sube la RMV a S/1,300 (anunciado el 28/07/2026, sin norma al 2026-08-03),
// estos dos montos tienen que subir con ella o quedan por debajo del mínimo.
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
  orden: number;
}

export const RANGOS: Rango[] = [
  { codigo: "colibri", label: "Colibrí", baseDeclarada: 1130, orden: 1 },
  { codigo: "cayla", label: "Cayla", baseDeclarada: 1130, orden: 2 },
  { codigo: "caylo", label: "Caylo", baseDeclarada: 1130, orden: 3 },
  { codigo: "support", label: "Support", baseDeclarada: 1290, orden: 4 },
  { codigo: "aurora", label: "Aurora", baseDeclarada: 1500, orden: 5 },
  { codigo: "oraculo", label: "Oráculo", baseDeclarada: 1810, orden: 6 },
  { codigo: "archicaylo", label: "ArchiCaylo", baseDeclarada: 2670, orden: 7 },
];

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
