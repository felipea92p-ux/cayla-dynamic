// ============================================================================
// ventanas-beneficio.ts — a qué ventana del libro pertenece un pago
// ============================================================================
// QUÉ PROMETE · dado un beneficio y una fecha, el PERIODO que la contiene:
//               la ventana de `desembolsos_beneficios` (grati_s1, grati_s2,
//               cts_may, cts_nov, vacaciones), su año, desde, hasta y la fecha
//               legal de pago. Y el periodo inmediatamente anterior.
// QUÉ ASUME   · fechas ISO «AAAA-MM-DD», comparadas por texto (nunca
//               new Date(), que corre un día según la zona del navegador).
//
// ES LA MISMA CUENTA QUE HACEN LAS LIQUIDACIONES, y tiene que seguir siéndolo:
//   · CTS          → `fn_cts_trunca` (vigente: 0278). Ubica el periodo que
//                    contiene la fecha de cese —nov–abr, may–oct o nov–dic— y
//                    lo nombra por el mes del DEPÓSITO: nov–abr es `cts_may`
//                    del año en que termina; noviembre y diciembre ya son el
//                    `cts_may` del año SIGUIENTE.
//   · Gratificación→ `fn_grati_trunca_bruta` (0343) + `fn_grati_trunca` (0163):
//                    ene–jun es `grati_s1`, jul–dic es `grati_s2`, del mismo año.
//   · Vacaciones   → una sola ventana; `fn_vacaciones_truncas` (0341) suma el
//                    libro de todos los años, así que el año es el del pago.
//
// POR QUÉ EXISTE. El modal «Adelanto de beneficio» (0343) decidía la CTS con
// `mes <= 6 ? "cts_may" : "cts_nov"`, que es la regla de la GRATIFICACIÓN. Una
// CTS adelantada en junio quedaba anotada en la ventana que ya se depositó el
// 15/05 —negativo en Provisiones, y la liquidación restando de la ventana
// equivocada—, y una de diciembre quedaba en el noviembre del mismo año en vez
// del mayo siguiente. Medido en el Postgres local el 2026-09-15. Si mañana
// cambia la regla de una trunca, esta función cambia con ella: el libro que las
// dos leen es el mismo.
// ============================================================================

export type BeneficioDesembolso = "gratificacion" | "cts" | "vacaciones";
export type VentanaDesembolso = "grati_s1" | "grati_s2" | "cts_may" | "cts_nov" | "vacaciones";

export interface PeriodoDeBeneficio {
  beneficio: BeneficioDesembolso;
  ventana: VentanaDesembolso;
  /** El `anio` con que se anota en el libro: el del DEPÓSITO, no el del inicio. */
  anio: number;
  /** Primer y último día que acumula. null en vacaciones, que no tienen semestre. */
  desde: string | null;
  hasta: string | null;
  /** Fecha legal de pago o depósito. null en vacaciones. */
  pagoLegal: string | null;
}

const MESES_CORTOS = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];
const MESES = [
  "enero", "febrero", "marzo", "abril", "mayo", "junio",
  "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre",
];

function partes(fechaISO: string): { y: number; m: number } {
  const [y, m, d] = fechaISO.split("-").map(Number);
  if (!y || !m || !d || m < 1 || m > 12) throw new Error(`Fecha inválida: «${fechaISO}».`);
  return { y, m };
}

/** El periodo del beneficio que contiene la fecha. */
export function periodoQueContiene(beneficio: BeneficioDesembolso, fechaISO: string): PeriodoDeBeneficio {
  const { y, m } = partes(fechaISO);

  if (beneficio === "vacaciones") {
    return { beneficio, ventana: "vacaciones", anio: y, desde: null, hasta: null, pagoLegal: null };
  }

  if (beneficio === "gratificacion") {
    return m <= 6
      ? { beneficio, ventana: "grati_s1", anio: y, desde: `${y}-01-01`, hasta: `${y}-06-30`, pagoLegal: `${y}-07-15` }
      : { beneficio, ventana: "grati_s2", anio: y, desde: `${y}-07-01`, hasta: `${y}-12-31`, pagoLegal: `${y}-12-15` };
  }

  // CTS — los tres casos de fn_cts_trunca.
  if (m <= 4) {
    return { beneficio, ventana: "cts_may", anio: y, desde: `${y - 1}-11-01`, hasta: `${y}-04-30`, pagoLegal: `${y}-05-15` };
  }
  if (m <= 10) {
    return { beneficio, ventana: "cts_nov", anio: y, desde: `${y}-05-01`, hasta: `${y}-10-31`, pagoLegal: `${y}-11-15` };
  }
  return { beneficio, ventana: "cts_may", anio: y + 1, desde: `${y}-11-01`, hasta: `${y + 1}-04-30`, pagoLegal: `${y + 1}-05-15` };
}

/**
 * El periodo inmediatamente anterior. Existe para el caso que la fecha sola no
 * resuelve: una CTS pagada entre el 1 y el 15 de mayo puede ser del periodo
 * que empieza o el depósito atrasado del que terminó. Vacaciones no tiene
 * periodo anterior: devuelve el mismo.
 */
export function periodoAnterior(p: PeriodoDeBeneficio): PeriodoDeBeneficio {
  if (!p.desde) return p;
  const { y, m } = partes(p.desde);
  // `desde` siempre es el día 1; el día anterior es el último del mes previo.
  const diaAnterior = m === 1 ? `${y - 1}-12-31` : `${y}-${String(m - 1).padStart(2, "0")}-28`;
  return periodoQueContiene(p.beneficio, diaAnterior);
}

function mesAnio(iso: string, meses: string[]): string {
  const { y, m } = partes(iso);
  return `${meses[m - 1]} ${y}`;
}

/** "may–oct 2026" o "nov 2026–abr 2027". */
export function rangoDelPeriodo(p: PeriodoDeBeneficio): string {
  if (!p.desde || !p.hasta) return "";
  const a = partes(p.desde), b = partes(p.hasta);
  return a.y === b.y
    ? `${MESES_CORTOS[a.m - 1]}–${MESES_CORTOS[b.m - 1]} ${b.y}`
    : `${mesAnio(p.desde, MESES_CORTOS)}–${mesAnio(p.hasta, MESES_CORTOS)}`;
}

/** "CTS de noviembre 2026 (periodo may–oct 2026)" — cómo se le dice a una persona. */
export function nombreDelPeriodo(p: PeriodoDeBeneficio): string {
  if (p.beneficio === "vacaciones") return `vacaciones (${p.anio})`;
  const nombre = p.beneficio === "cts" ? "CTS" : "gratificación";
  return `${nombre} de ${mesAnio(p.pagoLegal!, MESES)} (periodo ${rangoDelPeriodo(p)})`;
}
