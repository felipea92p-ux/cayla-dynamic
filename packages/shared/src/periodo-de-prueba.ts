// ============================================================================
// periodo-de-prueba.ts — el periodo de prueba como CONDICIÓN del contrato
// ============================================================================
// QUÉ PROMETE  ·  dos respuestas que antes no tenían dueño:
//                 1. ¿hasta cuándo es el periodo de prueba de esta persona?
//                 2. ¿esta persona lleva menos de N días calendario desde su
//                    ingreso, a la fecha de un día dado? (el aviso de feriado)
// QUÉ ASUME    ·  fechas de Lima como texto `2026-10-26`. Nada de zonas horarias:
//                 la fecha de ingreso es un día del calendario, no un instante.
// QUÉ NO HACE  ·  no cierra nada, no da de baja a nadie y no toca un sol de
//                 lo que se paga. Dynamic avisa; decide una persona.
//
// ── POR QUÉ EXISTE ──────────────────────────────────────────────────────────
// Hasta el 2026-10-26 «prueba» era un TIPO DE VÍNCULO: tres días trabajados sin
// contrato y sin alta, y «si pasa, recién ahí se hace el contrato». La ley
// peruana no tiene ese vínculo. El periodo de prueba es una cláusula DENTRO de un
// contrato de trabajo (art. 10 del D.S. 003-97-TR): tres meses durante los
// cuales no hay protección contra el despido arbitrario, y nada más. Quien
// trabaja se registra desde el primer día; probarlo es decidir, dentro de esos
// tres meses, si se queda. Por eso «prueba» deja de ser un vínculo y pasa a ser
// una fecha derivada del ingreso.
//
// ── POR QUÉ LA FECHA SE DERIVA Y NO SE GUARDA ───────────────────────────────
// Guardar «prueba hasta» obligaría a mantenerlo cuando se corrige el ingreso.
// El ingreso es la fuente de verdad (igual que los marcajes lo son de las
// jornadas), así que el fin de la prueba sale de ahí cada vez que se pregunta.
//
// ── UNA SOLA CUENTA, LA DEL CONTRATO ────────────────────────────────────────
// El fin de la prueba es el mismo día del mes final: ingreso 19/10 → 19/01. Es
// la cuenta que ya imprime la cláusula TERCERA de los contratos («dicho período
// culmina el …», `finDelPeriodoDePrueba`, que ahora delega aquí). Una pantalla
// que dijera 18/01 mientras el contrato dice 19/01 daría dos versiones de la
// misma fecha legal. Si el día de cumplimiento cuenta dentro o fuera de la
// prueba lo confirma el área legal; hasta entonces, las alertas de decisión (no
// esta función) deben pedir decidir con unos días de margen.
//
// ── POR QUÉ DÍAS CALENDARIO PARA EL AVISO DE FERIADO ────────────────────────
// Se decidió con Felipe (2026-10-26): «días calendario desde el ingreso». Los
// días trabajados no existen todavía cuando se arma el horario de una semana
// que viene, y el aviso tiene que saltar ANTES de poner el turno.
// ============================================================================

/** Meses del periodo de prueba que fija la ley (art. 10, D.S. 003-97-TR). */
export const MESES_PRUEBA_LEY = 3;

/** Tope de un periodo de prueba pactado en días: de tres meses para arriba rige la ley (migración 0556). */
export const DIAS_PRUEBA_PACTADA_MAX = 89;

/** Días calendario desde el ingreso durante los que un feriado trabajado se avisa. Es política, no ley. */
export const DIAS_AVISO_FERIADO_DEFECTO = 15;

const DIA_MS = 86_400_000;
const ISO = /^\d{4}-\d{2}-\d{2}$/;

function aMs(fecha: string): number | null {
  if (!ISO.test(fecha)) return null;
  const [y, m, d] = fecha.split("-").map(Number);
  const ms = Date.UTC(y, m - 1, d);
  const f = new Date(ms);
  // Rechaza 2026-02-30: Date lo "corrige" al mes siguiente y la cuenta saldría corrida.
  return f.getUTCFullYear() === y && f.getUTCMonth() === m - 1 && f.getUTCDate() === d ? ms : null;
}

function deMs(ms: number): string {
  const f = new Date(ms);
  const p2 = (n: number) => String(n).padStart(2, "0");
  return `${f.getUTCFullYear()}-${p2(f.getUTCMonth() + 1)}-${p2(f.getUTCDate())}`;
}

/** Suma (o resta) días calendario a una fecha `AAAA-MM-DD`. `null` si la fecha no existe. */
export function sumarDiasFecha(fecha: string, dias: number): string | null {
  const ms = aMs(fecha);
  return ms === null ? null : deMs(ms + dias * DIA_MS);
}

/**
 * Suma meses a una fecha. Si el mes final no tiene ese día, cae en el último día
 * de ese mes (31 de enero + 1 mes = 28 de febrero). `null` si la fecha no existe.
 */
export function sumarMesesFecha(fecha: string, meses: number): string | null {
  const ms = aMs(fecha);
  if (ms === null) return null;
  const f = new Date(ms);
  const total = f.getUTCFullYear() * 12 + f.getUTCMonth() + meses;
  const y = Math.floor(total / 12);
  const m = total - y * 12;
  const ultimo = new Date(Date.UTC(y, m + 1, 0)).getUTCDate();
  return deMs(Date.UTC(y, m, Math.min(f.getUTCDate(), ultimo)));
}

/** Días calendario entre dos fechas (`hasta - desde`). `null` si alguna no existe. */
export function diasEntreFechas(desde: string, hasta: string): number | null {
  const a = aMs(desde);
  const b = aMs(hasta);
  return a === null || b === null ? null : Math.round((b - a) / DIA_MS);
}

export interface PeriodoDePrueba {
  /** El día en que se cumplen los meses de prueba: el mismo día del mes final (como imprime el contrato). */
  fin: string;
  /** `hoy` todavía no pasó de `fin` (el propio día de `fin` cuenta como en curso). */
  enCurso: boolean;
  /** Días que faltan para `fin`. 0 = hoy es el día. Negativo = ya pasó. */
  diasRestantes: number;
}

/**
 * El día en que se cumplen los meses de prueba de quien ingresó en `fechaIngreso`
 * (art. 10 del D.S. 003-97-TR). Meses de calendario, no 90 días: la ley cuenta
 * meses. `null` si la fecha no existe. Es la ÚNICA cuenta: el contrato, Equipo y
 * las alertas preguntan aquí.
 */
export function finDelPeriodoDePruebaDe(fechaIngreso: string, meses: number = MESES_PRUEBA_LEY): string | null {
  return sumarMesesFecha(fechaIngreso, meses);
}

/**
 * El periodo de prueba de quien ingresó en `fechaIngreso`, mirado desde `hoy`.
 * `null` si falta el ingreso o no es una fecha: sin ingreso no se inventa una
 * prueba, y un aviso que no sale es mejor que uno equivocado.
 */
export function periodoDePrueba(
  fechaIngreso: string | null | undefined,
  hoy: string,
  meses: number = MESES_PRUEBA_LEY,
): PeriodoDePrueba | null {
  if (!fechaIngreso) return null;
  const fin = finDelPeriodoDePruebaDe(fechaIngreso, meses);
  const restantes = fin === null ? null : diasEntreFechas(hoy, fin);
  if (fin === null || restantes === null) return null;
  return { fin, enCurso: restantes >= 0, diasRestantes: restantes };
}

/**
 * ¿A `fecha` esta persona lleva MENOS de `umbral` días calendario desde su
 * ingreso? El día del ingreso cuenta 0, así que con 15 el último día que avisa
 * es el día 14. Antes del ingreso devuelve `false`: quien todavía no empezó no
 * trabaja ese feriado. Sin ingreso legible devuelve `false` también.
 */
export function esIngresoReciente(
  fechaIngreso: string | null | undefined,
  fecha: string,
  umbral: number = DIAS_AVISO_FERIADO_DEFECTO,
): boolean {
  if (!fechaIngreso) return false;
  const antiguedad = diasEntreFechas(fechaIngreso, fecha);
  return antiguedad !== null && antiguedad >= 0 && antiguedad < umbral;
}

/**
 * El fin de la prueba de una persona según lo que se pactó (`personas.prueba_pactada_dias`, 0556):
 *   · `null`/`undefined` → rige la ley: tres meses desde el ingreso.
 *   · `0` → sin periodo de prueba: no hay fin que decir (`null`).
 *   · `N` (1–89) → N días calendario; el plazo por días excluye el día del ingreso y
 *     cuenta el del vencimiento (art. 183 del Código Civil): 1/10 + 30 días = 31/10.
 * Un valor fuera de 0–89 o no entero se trata como «rige la ley»: la base ya lo rechaza, y un
 * dato raro que apaga la etiqueta de golpe sería peor que mostrar el plazo ordinario.
 */
export function finDelPeriodoPactado(fechaIngreso: string, pactadoDias: number | null | undefined): string | null {
  if (pactadoDias === 0) return null;
  const valido = pactadoDias != null && Number.isInteger(pactadoDias) && pactadoDias > 0 && pactadoDias <= DIAS_PRUEBA_PACTADA_MAX;
  return valido ? sumarDiasFecha(fechaIngreso, pactadoDias) : finDelPeriodoDePruebaDe(fechaIngreso);
}

/** Como `periodoDePrueba`, pero respetando lo pactado con la persona. `null` si no hay prueba o no hay ingreso legible. */
export function periodoDePruebaPactado(
  fechaIngreso: string | null | undefined,
  hoy: string,
  pactadoDias: number | null | undefined,
): PeriodoDePrueba | null {
  if (!fechaIngreso) return null;
  const fin = finDelPeriodoPactado(fechaIngreso, pactadoDias);
  const restantes = fin === null ? null : diasEntreFechas(hoy, fin);
  if (fin === null || restantes === null) return null;
  return { fin, enCurso: restantes >= 0, diasRestantes: restantes };
}

/**
 * La ETIQUETA «en periodo de prueba» que muestra el panel. Distinta del periodo legal: el
 * periodo es una cláusula del contrato de cada persona; la etiqueta es un rótulo de la
 * pantalla que decide CAYLA, y solo alcanza a quien ingresó en `desde` o después
 * (Parámetros: «prueba_etiqueta_desde», 0557, por defecto el día en que se activó).
 * `desde` null/undefined = sin corte (nadie queda fuera por antigüedad del sistema).
 * Devuelve el periodo solo mientras está en curso; `null` si no corresponde rotular.
 * Solo rotula: no cambia ningún pago ni ningún derecho de la persona.
 */
export function etiquetaPeriodoDePrueba(
  fechaIngreso: string | null | undefined,
  hoy: string,
  opciones: { pactadoDias?: number | null; desde?: string | null } = {},
): PeriodoDePrueba | null {
  if (!fechaIngreso) return null;
  if (opciones.desde && ISO.test(opciones.desde) && fechaIngreso < opciones.desde) return null; // ISO: el orden de texto es el de fechas
  const p = periodoDePruebaPactado(fechaIngreso, hoy, opciones.pactadoDias);
  return p && p.enCurso ? p : null;
}

/** «19/01/2027», o vacío si no hay periodo que decir. */
export function textoPeriodoDePrueba(p: PeriodoDePrueba | null): string {
  if (!p) return "";
  const [y, m, d] = p.fin.split("-");
  return `${d}/${m}/${y}`;
}
