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
// Felipe rehízo la escala completa. Solo colibrí se queda en la RMV; a partir de
// cayla cada rango declara algo más, y los rangos altos BAJAN respecto de la
// escala anterior (archicaylo de 2,670 a 1,500; oráculo de 1,810 a 1,440).
//
// Esa bajada es deliberada y está asumida: reduce la CTS, la gratificación, las
// vacaciones y la pensión futura de quien ya estaba en esos rangos, porque las
// cuatro se calculan sobre lo declarado. Se compensa con los conceptos no
// remunerativos (movilidad, educación, bono).
//
// ── SI CAMBIA LA RMV ────────────────────────────────────────────────────────
//
// TODO lo que esté por debajo de la RMV nueva tiene que subir o queda bajo el
// mínimo legal, y son CUATRO sitios que se mueven juntos —no hay uno que los
// arrastre a los otros—:
//   1. `parametros_laborales`, clave `rmv` (la versionada; la lee la planilla
//      para el piso de EsSalud). Se cierra la fila vieja y se abre otra.
//   2. `asignaciones_salario` + `personas.sueldo_base_legal` de cada integrante
//      (el sueldo que se paga y la base que se declara), por
//      `fn_fijar_base_declarada`.
//   3. `categorias_laborales.salario_declarado`, que es lo que publica la
//      Política salarial.
//   4. ESTE archivo, y la constante RMV de `tests/reglas-negocio.test.ts`.
// Y cuando sube la RMV sube también la asignación familiar (10 %, Ley 25129
// art. 1), en `parametros_laborales` Y en `configuracion.asignacion_familiar`
// (la lee la liquidación por cese, sin fechas).
//
// LA RMV DE HOY: S/ 1,230 desde el 2026-10-01 (D.S. 015-2026-TR, publicado el
// 2026-09-28 en El Peruano). Es la PRIMERA de dos etapas: el decreto la lleva a
// S/ 1,300, y la segunda (+S/ 70) la fijará OTRO decreto supremo en el primer
// semestre de 2027, sin fecha. Esa segunda etapa NO está construida y nada en el
// sistema avisa cuando salga. Cuando salga, colibrí, cayla Y support (1,260 <
// 1,300) vuelven a quedar bajo el piso y hay que rehacer los cuatro sitios de
// arriba, con la asignación en S/ 130. La prueba «ninguna base declarada cae por
// debajo de la RMV vigente» es el recordatorio: se pone roja en cuanto se
// actualice la constante RMV del test.
//
// La escala del 2026-10-01 es la más barata que mantiene el orden: colibrí 1,230
// (la RMV) · cayla 1,245 · support 1,260 (ya cumplía, no se toca) · aurora 1,360
// · oráculo 1,440 · archicaylo 1,500. La asignación por educación NO se sube ni
// se iguala «para compensar»: la base cumple sola. Migración 0501.
//
// Los códigos tienen que coincidir con el CHECK de la migración 0019
// (`asignaciones_salario.rango`) y con la lista de `fn_fijar_base_declarada`
// (migración 0128).
//
// ── LA VERDAD DE ESTA LISTA VIVE EN `categorias_laborales` ──────────────────
//
// Esto es una constante SOLO para pintar el desplegable de Equipo sin esperar a
// que vuelva una consulta. El catálogo real es la tabla `categorias_laborales`
// (migración 0140), que es de donde sale el cuadro de categorías que se publica
// al equipo, con propósito, funciones, requisitos y criterio de cada nivel.
//
// Si las dos se separan, gana la tabla. La prueba 139 compara el CHECK de la
// base contra esa tabla, así que una categoría nueva que no llegue acá se nota
// en el desplegable, no en la planilla.
//
// ── POR QUÉ ACÁ NO ESTÁ EL TECHO DE EDUCACIÓN ───────────────────────────────
//
// Había un campo `topeEducacion` con los techos de cada rango. Se borró el
// 2026-08-06 y no por limpieza: no lo llamaba nadie, y era una copia vieja. La
// 0140 le quitó el techo a «caylo» en la tabla y esta copia se quedó diciendo
// que tenía 180. La pantalla de política salarial ya lee los techos de
// `topes_educacion_rango`, que es donde se editan.
//
// ── Y POR QUÉ YA NO ESTÁ «CAYLO» ────────────────────────────────────────────
//
// Era el mismo nivel que «cayla» —misma base, mismo techo— con otro nombre. Dos
// nombres para un nivel es cómo se produce que uno de los dos se olvide: la 0140
// retiró caylo del catálogo pero el desplegable lo siguió ofreciendo, y como en
// la tabla ya no tenía techo, el candado de educación pagaba sin límite (con un
// comprobante de S/727: S/545.25 en vez de S/180). Lo cerró la migración 0178.
// Un rango es un nivel, no un género.

export interface Rango {
  codigo: string;
  label: string;
  /** Monto que se declara en el PLAME y que el sistema paga. Editable por persona. */
  baseDeclarada: number;
  orden: number;
}

// El `orden` es el mismo de `categorias_laborales.orden`. Si acá dijera otro, el
// desplegable ordenaría los niveles distinto de como los lee el equipo en su
// política salarial.
export const RANGOS: Rango[] = [
  { codigo: "colibri", label: "Colibrí", baseDeclarada: 1230, orden: 1 },
  { codigo: "cayla", label: "Cayla", baseDeclarada: 1245, orden: 2 },
  { codigo: "support", label: "Support", baseDeclarada: 1260, orden: 3 },
  { codigo: "aurora", label: "Aurora", baseDeclarada: 1360, orden: 4 },
  { codigo: "oraculo", label: "Oráculo", baseDeclarada: 1440, orden: 5 },
  { codigo: "archicaylo", label: "ArchiCayla", baseDeclarada: 1500, orden: 6 },
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
