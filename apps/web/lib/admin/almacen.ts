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
import type { MarcajeDelDia } from "@cayla-dynamic/shared";
import { cambiosDelPlan, tramosDelDia, type CambioUbicacion } from "../terminal/ubicacion";

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

export const aDecimal = (hm: string): number => {
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

// ----------------------------------------------------------------------------
// Lo real del terminal (0580), junto al plan, para la vista Día (2026-11-03)
// ----------------------------------------------------------------------------
// Decidido con Felipe el 2026-11-03: la Integrada sigue mostrando SOLO el plan
// (es la herramienta para planificar la semana); la vista Día muestra el plan
// y lo que marcaron en el terminal, y su cobertura cuenta lo real hasta ahora
// y el plan de ahí en adelante.
//
// «¿Dónde estuvo?» NO se decide aquí: lo decide `tramosDelDia`, de
// lib/terminal/ubicacion.ts, que es la regla del terminal y de
// fn_ubicaciones_del_dia (0580). Lo planificado entra como cambios con
// `cambiosDelPlan`, igual que en el terminal: un «Vuelvo a tienda» real corta
// el plan desde esa hora y un «Voy a almacén» real siempre cuenta. Así la
// pantalla y el terminal no pueden decir cosas distintas de la misma persona.
// Lo único que agrega este archivo es lo que el terminal no necesita: lo que
// TODAVÍA NO PASÓ (el plan que empieza después de ahora, y hasta dónde se
// estira el tramo abierto) y pasar todo a horas decimales.
// ----------------------------------------------------------------------------

/** La hora decimal del día (desde su medianoche de Lima) de un instante ISO. */
function decimalDelDia(iso: string, medianocheIso: string): number {
  return (new Date(iso).getTime() - new Date(medianocheIso).getTime()) / 3_600_000;
}

/** Une tramos que se cruzan o se tocan y los recorta a [desde, hasta). */
function unirYRecortar(tramos: TramoDecimal[], limite: TramoDecimal): TramoDecimal[] {
  const recortados = tramos
    .map((t) => ({ desde: Math.max(t.desde, limite.desde), hasta: Math.min(t.hasta, limite.hasta) }))
    .filter((t) => t.hasta > t.desde)
    .sort((a, b) => a.desde - b.desde);
  const unidos: TramoDecimal[] = [];
  for (const t of recortados) {
    const ultimo = unidos[unidos.length - 1];
    if (ultimo && t.desde <= ultimo.hasta + 1e-9) ultimo.hasta = Math.max(ultimo.hasta, t.hasta);
    else unidos.push({ ...t });
  }
  return unidos;
}

export function almacenConLoReal(args: {
  /** El plan del día ya recortado a su turno: `tramosEnAlmacen(puesto, turno)`. */
  plan: TramoDecimal[];
  /** Los cambios reales de ese día (cambios_ubicacion sin anular). */
  cambios: readonly CambioUbicacion[];
  /** Sus marcajes de ese día: de aquí solo cuenta la salida final, que cierra un tramo abierto. */
  marcajes: readonly MarcajeDelDia[];
  /** El inicio del día en Lima: `rangoDelDiaLima(fecha).inicio`. */
  medianocheIso: string;
  ahora: Date;
  /** Su turno ese día, en horas decimales. */
  turno: TramoDecimal;
}): {
  /** Lo que cuenta para la cobertura: lo real (con el plan como si hubiera pasado) hasta ahora, y el plan después. */
  cobertura: TramoDecimal[];
  /** Solo lo marcado en el terminal, hasta ahora. Para dibujarlo aparte del plan. */
  marcado: TramoDecimal[];
} {
  const { plan, cambios, marcajes, medianocheIso, ahora, turno } = args;
  const aDec = (iso: string) => decimalDelDia(iso, medianocheIso);
  const ahoraDec = aDec(ahora.toISOString());

  // Hasta ahora: la regla del terminal, con lo planificado como cambios.
  const combinados = tramosDelDia([...cambios, ...cambiosDelPlan({ todoElTurno: false, tramos: plan }, medianocheIso)], marcajes, ahora);
  // El tramo abierto sigue hasta su vuelta prevista (que todavía no venció: si
  // no, tramosDelDia ya lo habría cerrado) o, con «hasta que vuelva», hasta el
  // fin de su turno.
  const pasado = combinados.map((t) => ({
    desde: aDec(t.desde),
    hasta: t.hasta !== null ? aDec(t.hasta) : t.vuelve !== null ? aDec(t.vuelve) : turno.hasta,
  }));
  // Lo que todavía no empezó es solo plan. Un tramo planificado que ya empezó
  // está en `pasado`, cortado o no por lo real: no se resucita su resto.
  const futuro = plan.filter((t) => t.desde > ahoraDec);

  const marcado = tramosDelDia(cambios, marcajes, ahora).map((t) => ({
    desde: aDec(t.desde),
    hasta: t.hasta !== null ? aDec(t.hasta) : ahoraDec,
  }));

  return {
    cobertura: unirYRecortar([...pasado, ...futuro], turno),
    marcado: unirYRecortar(marcado, { desde: 0, hasta: 24 }),
  };
}
