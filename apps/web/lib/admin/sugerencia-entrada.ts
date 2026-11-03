// ============================================================================
// sugerencia-entrada.ts — Lo que la propuesta de turnos lee, y lo que publica
// ============================================================================
// PROMETE: traducir lo que llega de la base a lo que pide el motor
//          (sugerencia-turnos.ts), y de vuelta: qué filas se mandan a
//          fn_publicar_semana (0586).
//            · la venta promedio de cada día de la semana y hora, de las últimas
//              4 semanas (decisión de Felipe, 2026-11-03);
//            · la disponibilidad aprobada (fn_disponibilidad_vigente, 0584) como
//              bloques y días de horario fijo;
//            · las ausencias (vacaciones, descansos médicos…) como días en que
//              no se la puede poner;
//            · las filas que cambian respecto de lo que ya hay.
// NO HACE: leer la base ni decidir nada del motor.
// ============================================================================
import type { Bloque, Propuesta, Turno } from "./sugerencia-turnos";

const ms = (fecha: string) => new Date(`${fecha}T12:00:00Z`).getTime();
const DIA = 86_400_000;
export const sumarDias = (fecha: string, n: number) => new Date(ms(fecha) + n * DIA).toISOString().slice(0, 10);
/** 0 = domingo … 6 = sábado, como `extract(dow)` y fn_sede_ventana_semanal. */
export const diaDeLaSemana = (fecha: string) => new Date(ms(fecha)).getUTCDay();

export const aMinutos = (hm: string): number => {
  const [h, m] = hm.split(":").map(Number);
  return (h ?? 0) * 60 + (m ?? 0);
};
export const aHHMM = (min: number) => `${String(Math.floor(min / 60)).padStart(2, "0")}:${String(min % 60).padStart(2, "0")}`;

/**
 * Las compras promedio de cada día de la semana y hora entre `desde` y `hasta`.
 * Divide por cuántas veces cae ese día de la semana en el rango —no por cuántos
 * tuvieron venta—: un lunes sin ninguna compra también es un lunes.
 */
export function promedioDeCompras(
  filas: readonly { fecha: string; hora: number; compras: number }[],
  desde: string,
  hasta: string,
): (dow: number, hora: number) => number {
  const veces = new Map<number, number>();
  for (let f = desde; f <= hasta; f = sumarDias(f, 1)) veces.set(diaDeLaSemana(f), (veces.get(diaDeLaSemana(f)) ?? 0) + 1);
  const suma = new Map<string, number>();
  for (const x of filas) {
    if (x.fecha < desde || x.fecha > hasta) continue;
    const k = `${diaDeLaSemana(x.fecha)}|${x.hora}`;
    suma.set(k, (suma.get(k) ?? 0) + x.compras);
  }
  return (dow, hora) => (suma.get(`${dow}|${hora}`) ?? 0) / Math.max(1, veces.get(dow) ?? 0);
}

export interface RestriccionesPersona {
  fijos: Set<string>;
  bloques: Record<string, Bloque[]>;
}

/** La disponibilidad aprobada, por persona: días de horario fijo y bloques por fecha (sin horas = todo el día). */
export function restriccionesDesdeDisponibilidad(
  filas: readonly { persona_id: string; fecha: string; desde: string | null; hasta: string | null; estado: string }[],
): Map<string, RestriccionesPersona> {
  const out = new Map<string, RestriccionesPersona>();
  for (const f of filas) {
    const r = out.get(f.persona_id) ?? { fijos: new Set<string>(), bloques: {} };
    if (f.estado === "horario_fijo") r.fijos.add(f.fecha);
    else if (f.estado === "no_puede" || f.estado === "prefiere_no") {
      const b: Bloque = {
        desde: f.desde ? aMinutos(f.desde) : 0,
        hasta: f.hasta ? aMinutos(f.hasta) : 24 * 60,
        estado: f.estado,
      };
      (r.bloques[f.fecha] ??= []).push(b);
    }
    out.set(f.persona_id, r);
  }
  return out;
}

/** Las ausencias (no anuladas) como días enteros de «no puede», por persona, dentro de las fechas pedidas. */
export function diasDeAusencia(
  filas: readonly { persona_id: string; fecha_inicio: string; fecha_fin: string; anulada: boolean }[],
  fechas: readonly string[],
): Map<string, Set<string>> {
  const out = new Map<string, Set<string>>();
  for (const a of filas) {
    if (a.anulada) continue;
    for (const f of fechas) {
      if (f >= a.fecha_inicio && f <= a.fecha_fin) {
        const s = out.get(a.persona_id) ?? new Set<string>();
        s.add(f);
        out.set(a.persona_id, s);
      }
    }
  }
  return out;
}

export interface FilaPublicar {
  persona_id: string;
  fecha: string;
  entrada: string | null;
  salida: string | null;
}

const igual = (a: Turno | null, b: Turno | null) =>
  (a === null && b === null) || (a !== null && b !== null && a.entrada === b.entrada && a.salida === b.salida);

/**
 * Qué se manda a publicar: solo los días que cambian. Con una excepción, la de
 * la 0586: si quien publica es una líder de equipo y su propio turno cambia,
 * va su semana COMPLETA —la base mide que sume su jornada— o, si no la suma, no
 * va nada suyo y se dice por qué.
 */
export function filasParaPublicar(args: {
  propuesta: Propuesta;
  actual: (personaId: string, fecha: string) => Turno | null;
  fechas: readonly string[];
  /** La persona que publica, si es líder de equipo (admin y Líder DO no tienen esta regla). */
  lider?: { id: string; jornada: number | null };
}): { filas: FilaPublicar[]; suyoFuera: string | null } {
  const { propuesta, actual, fechas, lider } = args;
  const filas: FilaPublicar[] = [];
  let suyoFuera: string | null = null;
  for (const [personaId, porFecha] of Object.entries(propuesta.turnos)) {
    const cambia = fechas.filter((f) => !igual(porFecha[f] ?? null, actual(personaId, f)));
    if (cambia.length === 0) continue;
    const comoFila = (f: string): FilaPublicar => {
      const t = porFecha[f] ?? null;
      return { persona_id: personaId, fecha: f, entrada: t ? aHHMM(t.entrada) : null, salida: t ? aHHMM(t.salida) : null };
    };
    if (lider && personaId === lider.id) {
      const r = propuesta.resumen[personaId];
      if (lider.jornada === null) { suyoFuera = "Tu turno no se publica: DO todavía no fija tu jornada."; continue; }
      if (!r || Math.abs(r.horas - lider.jornada) > 0.25) { suyoFuera = "Tu turno no se publica: con esta propuesta no suma tu jornada."; continue; }
      filas.push(...fechas.map(comoFila));
      continue;
    }
    filas.push(...cambia.map(comoFila));
  }
  return { filas, suyoFuera };
}
