// ============================================================================
// almacen.ts — Piso o almacén, planificado por día (2026-11-02, migración 0579)
// ============================================================================
// PROMETE: leer el plan de un día (las filas de puestos_planificados), decir en
//          qué tramos del turno la persona está en almacén, validar los tramos
//          con las MISMAS reglas que fn_set_almacen_del_dia, sugerir un tramo
//          donde el piso aguanta sin ella, y armar lo que se le manda a la base.
// ASUME:   horas en decimal (08:30 → 8.5), como el resto de Turnos. El turno del
//          día ya lo resolvió la cascada de jornada-esperada.ts.
// NO HACE: leer la base ni decidir quién cuenta en piso (eso es
//          cuentaEnCobertura). Solo dice cuándo NO está en piso.
//
// Por qué la validación vive dos veces (aquí y en la función SQL): la base es
// la que manda y rechaza igual; esto existe para decirlo en la hoja ANTES de
// guardar, con las mismas palabras, en vez de mostrar el error de Postgres.
// Si se cambia una regla, se cambia en los dos lados: la prueba
// tests/almacen.test.ts lista las reglas que la 0579 hace cumplir.
// ============================================================================

export interface TramoDecimal {
  desde: number;
  hasta: number;
}

export interface PuestoDelDia {
  /** Todo el turno en almacén. */
  todoElTurno: boolean;
  /** Tramos en almacén, ordenados. Vacío y todoElTurno false = piso. */
  tramos: TramoDecimal[];
}

export const PISO: PuestoDelDia = { todoElTurno: false, tramos: [] };

/** Tope de tramos por día: el mismo de fn_set_almacen_del_dia. */
export const MAX_TRAMOS = 6;

const aDecimal = (hm: string): number => {
  const [h, m] = hm.split(":").map(Number);
  return (h ?? 0) + (m ?? 0) / 60;
};

export const aHHMM = (dec: number): string => {
  const h = Math.floor(dec + 1e-9);
  const m = Math.round((dec - h) * 60);
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
};

/** Las filas de puestos_planificados de UNA persona en UN día → su plan. */
export function puestoDesdeFilas(filas: { desde: string | null; hasta: string | null }[]): PuestoDelDia {
  if (filas.length === 0) return PISO;
  if (filas.some((f) => f.desde === null || f.hasta === null)) return { todoElTurno: true, tramos: [] };
  const tramos = filas
    .map((f) => ({ desde: aDecimal(f.desde!), hasta: aDecimal(f.hasta!) }))
    .sort((a, b) => a.desde - b.desde);
  return { todoElTurno: false, tramos };
}

export const esPiso = (p: PuestoDelDia): boolean => !p.todoElTurno && p.tramos.length === 0;

/**
 * En qué tramos de su turno está en almacén. «Todo el turno» es el turno
 * entero; un tramo que cae fuera del turno no cuenta (el turno pudo cambiar
 * después de planificar) y uno que lo cruza se recorta.
 */
export function tramosEnAlmacen(puesto: PuestoDelDia, turno: TramoDecimal): TramoDecimal[] {
  if (puesto.todoElTurno) return [{ desde: turno.desde, hasta: turno.hasta }];
  return puesto.tramos
    .map((t) => ({ desde: Math.max(t.desde, turno.desde), hasta: Math.min(t.hasta, turno.hasta) }))
    .filter((t) => t.hasta > t.desde);
}

/** El texto del plan: el mismo de fn_puesto_texto (0579), con el que se escribe el rastro. */
export function textoPuesto(p: PuestoDelDia): string {
  if (p.todoElTurno) return "Almacén todo el turno";
  if (p.tramos.length === 0) return "Piso";
  return "Almacén " + p.tramos.map((t) => `${aHHMM(t.desde)}–${aHHMM(t.hasta)}`).join(", ");
}

/**
 * Qué está mal en unos tramos, con las palabras de la base, o null si están
 * bien. Además de lo que la base exige, mira que caigan dentro del turno: eso
 * la base no lo puede saber (el turno se resuelve con la cascada), y un tramo
 * fuera del turno no movería nada.
 */
export function problemaDeTramos(tramos: TramoDecimal[], turno: TramoDecimal | null): string | null {
  if (tramos.length === 0) return "Agrega al menos un tramo, o elige «Piso».";
  if (tramos.length > MAX_TRAMOS) return `Son demasiados tramos para un día (máximo ${MAX_TRAMOS}).`;
  const orden = [...tramos].sort((a, b) => a.desde - b.desde);
  for (let i = 0; i < orden.length; i++) {
    const t = orden[i];
    if (!(t.hasta > t.desde)) return `El tramo de ${aHHMM(t.desde)} a ${aHHMM(t.hasta)} termina antes de empezar.`;
    if (i > 0 && t.desde < orden[i - 1].hasta) return `Dos tramos de almacén se cruzan a las ${aHHMM(t.desde)}.`;
    if (turno && (t.desde < turno.desde || t.hasta > turno.hasta)) {
      return `El tramo de ${aHHMM(t.desde)} a ${aHHMM(t.hasta)} cae fuera de su turno (${aHHMM(turno.desde)}–${aHHMM(turno.hasta)}).`;
    }
  }
  return null;
}

/** Lo que se le manda a fn_set_almacen_del_dia. */
export function argumentosDeGuardado(p: PuestoDelDia): { p_todo_el_turno: boolean; p_tramos: { desde: string; hasta: string }[] } {
  if (p.todoElTurno) return { p_todo_el_turno: true, p_tramos: [] };
  return {
    p_todo_el_turno: false,
    p_tramos: [...p.tramos].sort((a, b) => a.desde - b.desde).map((t) => ({ desde: aHHMM(t.desde), hasta: aHHMM(t.hasta) })),
  };
}

/**
 * Un tramo para mandarla al almacén sin dejar el piso corto: dentro de su
 * turno (y de la atención: no se sugiere antes de abrir ni en el cierre), del
 * largo pedido, donde en TODO momento quede al menos la meta sin ella. Entre
 * los que sirven, el de más holgura en su peor momento; si empatan, el más
 * temprano (estable). null si ninguno sirve: la pantalla lo dice con palabras.
 *
 * `enPisoSinElla(x)` y `metaEn(x)` los da la pantalla con su propia cuenta,
 * para que la sugerencia y el número de la casilla salgan de la misma regla.
 */
export function sugerirTramo(args: {
  turno: TramoDecimal;
  largo?: number;
  enPisoSinElla: (x: number) => number;
  metaEn: (x: number) => number;
  paso?: number;
}): TramoDecimal | null {
  const { turno, enPisoSinElla, metaEn } = args;
  const largo = args.largo ?? 2;
  const paso = args.paso ?? 0.25;
  let mejor: { t: TramoDecimal; holgura: number } | null = null;
  for (let d = turno.desde; d + largo <= turno.hasta + 1e-9; d += paso) {
    let peor = Infinity;
    for (let x = d + paso / 2; x < d + largo; x += paso) peor = Math.min(peor, enPisoSinElla(x) - metaEn(x));
    if (peor < 0) continue;
    if (!mejor || peor > mejor.holgura + 1e-9) mejor = { t: { desde: d, hasta: d + largo }, holgura: peor };
  }
  return mejor ? mejor.t : null;
}
