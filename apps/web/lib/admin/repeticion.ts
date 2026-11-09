// ============================================================================
// repeticion.ts — La repetición de un día cerrado (Turnos · Día, 2026-11-03)
// ============================================================================
// PROMETE: dado lo que se marcó de verdad un día (marcajes del terminal y
//          tramos en almacén), decir en qué estaba cada persona a una hora
//          concreta —por llegar, en piso, en almacén, en refrigerio, en pausa o
//          ya salió—, cuántas había en piso en el peor momento de cada hora, y
//          cuánta gente pedía la venta de esa hora.
// ASUME:   que quién «cuenta» en piso ya lo decidió `cuentaEnCobertura` (llega
//          hecho en `cuenta`), y que los tramos en almacén ya los resolvió la
//          regla del terminal (`almacenConLoReal`, almacen.ts). Esto no vuelve a
//          decidir ninguna de las dos cosas.
// NO HACE: leer la base, ni juzgar a nadie. Dice «llegó 08:34 · plan 08:30», no
//          «llegó tarde»: las tardanzas tienen su propia pantalla y sus reglas, y
//          Dynamic avisa, nunca sanciona.
//
// POR QUÉ el estado sale de `estadoPresencia` (packages/shared) y no de una
// cuenta propia: es la misma máquina que usa el terminal para decidir qué botón
// ofrecer. Cortar los marcajes en el instante t y preguntarle a ella es la única
// forma de que la repetición y el terminal digan lo mismo de la misma persona.
// ============================================================================
import { estadoPresencia, horaLima, type MarcajeDelDia } from "@cayla-dynamic/shared";
import type { CambioUbicacion } from "@/lib/terminal/ubicacion";
import { aDecimal, almacenConLoReal, tramosEnAlmacen, type PuestoDelDia, type TramoDecimal } from "./almacen";

export type EstadoEnElMomento = "por_llegar" | "piso" | "almacen" | "refrigerio" | "pausa" | "salio";

export interface PersonaRepeticion {
  id: string;
  nombre: string;
  /** Cuenta contra la meta de operativas en piso. */
  cuenta: boolean;
  lider: boolean;
  /** Sus marcajes de ese día, sin anulados. */
  marcajes: readonly MarcajeDelDia[];
  /** Sus tramos en almacén ese día, en horas decimales (la regla del terminal). */
  almacen: readonly TramoDecimal[];
  /** Su turno planificado, en horas decimales; null si ese día no le tocaba. */
  plan: TramoDecimal | null;
}

/** Hasta dónde llega el día en Turnos (su línea va de 7 a 21): un turno sin hora de salida dura hasta aquí. */
export const FIN_DE_LA_LINEA = 21;

/** El turno que le tocaba, en horas decimales, como lo dibuja Turnos. null si ese día no le tocaba. */
export function planDelDia(esperado: { trabaja: boolean; entrada: string | null; salida: string | null }): TramoDecimal | null {
  if (!esperado.trabaja || !esperado.entrada) return null;
  return { desde: aDecimal(esperado.entrada), hasta: esperado.salida ? aDecimal(esperado.salida) : FIN_DE_LA_LINEA };
}

/**
 * Quiénes estuvieron un día ya cerrado y dónde, como los repite Turnos. Lo usan la repetición del día (Turnos ·
 * Día) y la tendencia de Inicio «Gente en piso frente a la venta»: así las dos dicen lo mismo de la misma hora.
 *
 * El almacén de quien tenía turno es lo marcado en el terminal más su plan, como si hubiera pasado (decisión de
 * Felipe, 2026-11-03: `almacenConLoReal`); el de quien vino sin turno, solo lo marcado. Quien no tenía turno ni
 * marcó no está.
 */
export function personasDelDiaCerrado(args: {
  personas: readonly { id: string; nombre: string; cuenta: boolean; lider: boolean }[];
  medianocheIso: string;
  ahora: Date;
  planDe: (personaId: string) => TramoDecimal | null;
  puestoDe: (personaId: string) => PuestoDelDia;
  cambiosDe: (personaId: string) => readonly CambioUbicacion[];
  marcajesDe: (personaId: string) => readonly MarcajeDelDia[];
}): PersonaRepeticion[] {
  const { personas, medianocheIso, ahora, planDe, puestoDe, cambiosDe, marcajesDe } = args;
  return personas.flatMap((p) => {
    const marcajes = marcajesDe(p.id);
    const plan = planDe(p.id);
    if (!plan && marcajes.length === 0) return [];
    const real = almacenConLoReal({
      plan: plan ? tramosEnAlmacen(puestoDe(p.id), plan) : [],
      turno: plan ?? { desde: 0, hasta: 24 },
      cambios: cambiosDe(p.id),
      marcajes,
      medianocheIso,
      ahora,
    });
    return [{ id: p.id, nombre: p.nombre, cuenta: p.cuenta, lider: p.lider, marcajes, almacen: plan ? real.cobertura : real.marcado, plan }];
  });
}

const ms = (iso: string) => new Date(iso).getTime();
const instante = (medianocheIso: string, t: number) => ms(medianocheIso) + Math.round(t * 3_600_000);

/** En qué estaba una persona a la hora decimal `t` de ese día. */
export function estadoEnElMomento(p: Pick<PersonaRepeticion, "marcajes" | "almacen">, t: number, medianocheIso: string): EstadoEnElMomento {
  const corte = instante(medianocheIso, t);
  const e = estadoPresencia(p.marcajes.filter((m) => ms(m.timestamp) <= corte));
  switch (e.estado) {
    case "sin_entrada": return "por_llegar";
    case "termino": return "salio";
    case "refrigerio": return "refrigerio";
    case "pausa": return "pausa";
    default: return p.almacen.some((a) => a.desde <= t && t < a.hasta) ? "almacen" : "piso";
  }
}

/**
 * Cuánta gente pedía la venta de una hora: las compras divididas por el ritmo
 * (compras por hora que atiende una persona), redondeado hacia arriba, y nunca
 * menos que el mínimo de la tienda. null si no se sabe cuánto se vendió.
 */
export function ventaPedia(compras: number | null, p: { ritmo: number; minimo: number }): number | null {
  if (compras === null || !(p.ritmo > 0)) return null;
  return Math.max(p.minimo, Math.ceil(compras / p.ritmo - 1e-9));
}

const CUARTOS = [0.125, 0.375, 0.625, 0.875];

/** Operativas en piso en el peor cuarto de la hora `hora` (la misma regla de la Integrada). */
export function enPisoEnLaHora(personas: readonly PersonaRepeticion[], hora: number, medianocheIso: string): number {
  return Math.min(
    ...CUARTOS.map((c) => personas.filter((p) => p.cuenta && estadoEnElMomento(p, hora + c, medianocheIso) === "piso").length),
  );
}

export interface FilaColumna {
  persona: PersonaRepeticion;
  /** Lo que se dice al lado del nombre: «llegó 08:34 · plan 08:30». */
  detalle: string;
}

const hhmm = (dec: number) => {
  const h = Math.floor(dec + 1e-9);
  return `${String(h).padStart(2, "0")}:${String(Math.round((dec - h) * 60)).padStart(2, "0")}`;
};

/** La última marca de un tipo hasta el instante, o null. */
function ultimaHasta(marcajes: readonly MarcajeDelDia[], tipos: readonly string[], corte: number): MarcajeDelDia | null {
  return [...marcajes]
    .filter((m) => tipos.includes(m.tipo) && ms(m.timestamp) <= corte)
    .sort((a, b) => ms(b.timestamp) - ms(a.timestamp))[0] ?? null;
}

/** Más de esto (en horas) entre lo marcado y lo planificado, y se muestra el plan al lado. */
const DIFERENCIA_QUE_SE_DICE = 5 / 60;

/**
 * Las columnas de la repetición en el instante `t`: quién está en cada estado,
 * con su detalle. `cerrado` = el día ya terminó (se dice «sin marca de
 * entrada» en vez de «entra a las …» a quien nunca marcó).
 */
export function columnasEnElMomento(
  personas: readonly PersonaRepeticion[],
  t: number,
  medianocheIso: string,
  cerrado: boolean,
): Record<EstadoEnElMomento, FilaColumna[]> {
  const col: Record<EstadoEnElMomento, FilaColumna[]> = { por_llegar: [], piso: [], almacen: [], refrigerio: [], pausa: [], salio: [] };
  const corte = instante(medianocheIso, t);
  for (const p of personas) {
    const est = estadoEnElMomento(p, t, medianocheIso);
    const entrada = p.marcajes.filter((m) => m.tipo === "entrada").sort((a, b) => ms(a.timestamp) - ms(b.timestamp))[0];
    let detalle = "";
    if (est === "por_llegar") {
      if (entrada) detalle = `entra ${horaLima(entrada.timestamp)}`;
      else if (cerrado) detalle = p.plan ? `sin marca de entrada · plan ${hhmm(p.plan.desde)}` : "sin marca de entrada";
      else detalle = p.plan ? `plan ${hhmm(p.plan.desde)}` : "";
    } else if (est === "salio") {
      const fin = ultimaHasta(p.marcajes, ["salida_final"], corte)!;
      const real = (ms(fin.timestamp) - ms(medianocheIso)) / 3_600_000;
      detalle = `salió ${horaLima(fin.timestamp)}`;
      if (p.plan && Math.abs(real - p.plan.hasta) > DIFERENCIA_QUE_SE_DICE) detalle += ` · plan ${hhmm(p.plan.hasta)}`;
    } else if (est === "refrigerio" || est === "pausa") {
      const s = ultimaHasta(p.marcajes, ["salida_almuerzo", "salida_personal", "salida_tramite", "salida_medico", "salida_otro"], corte);
      detalle = s ? `desde ${horaLima(s.timestamp)}` : "";
    } else {
      const real = entrada ? (ms(entrada.timestamp) - ms(medianocheIso)) / 3_600_000 : null;
      detalle = entrada ? `llegó ${horaLima(entrada.timestamp)}` : "";
      if (real !== null && p.plan && Math.abs(real - p.plan.desde) > DIFERENCIA_QUE_SE_DICE) detalle += ` · plan ${hhmm(p.plan.desde)}`;
      if (est === "almacen") {
        const a = p.almacen.find((x) => x.desde <= t && t < x.hasta);
        if (a) detalle = `en almacén ${hhmm(a.desde)}–${hhmm(a.hasta)}`;
      }
    }
    col[est].push({ persona: p, detalle });
  }
  for (const k of Object.keys(col) as EstadoEnElMomento[]) {
    col[k].sort((a, b) => Number(b.persona.lider) - Number(a.persona.lider) || a.persona.nombre.localeCompare(b.persona.nombre, "es"));
  }
  return col;
}

export interface HoraDelDiaReal {
  hora: number;
  enPiso: number;
  compras: number | null;
  pedia: number | null;
}

/** Las horas que se dibujan: de la primera entrada (o plan) a la última salida (o plan), enteras. */
export function horasDeLaRepeticion(personas: readonly PersonaRepeticion[], medianocheIso: string): number[] {
  const marcas = personas.flatMap((p) => p.marcajes.map((m) => (ms(m.timestamp) - ms(medianocheIso)) / 3_600_000));
  const planes = personas.flatMap((p) => (p.plan ? [p.plan.desde, p.plan.hasta] : []));
  const todas = [...marcas, ...planes].filter((x) => x >= 0 && x <= 24);
  if (todas.length === 0) return [];
  const desde = Math.floor(Math.min(...todas)), hasta = Math.ceil(Math.max(...todas));
  return Array.from({ length: Math.max(0, hasta - desde) }, (_, i) => desde + i);
}

/** El día completo, hora por hora: en piso (peor momento), compras y lo que pedía la venta. */
export function diaCompletoReal(args: {
  personas: readonly PersonaRepeticion[];
  medianocheIso: string;
  /** Compras por hora entera (8 → de 08:00 a 09:00); null si no se pudieron leer. */
  comprasDe: ((hora: number) => number) | null;
  parametros: { ritmo: number; minimo: number } | null;
}): HoraDelDiaReal[] {
  const { personas, medianocheIso, comprasDe, parametros } = args;
  return horasDeLaRepeticion(personas, medianocheIso).map((hora) => {
    const compras = comprasDe ? comprasDe(hora) : null;
    return {
      hora,
      enPiso: enPisoEnLaHora(personas, hora, medianocheIso),
      compras,
      pedia: parametros ? ventaPedia(compras, parametros) : null,
    };
  });
}

export interface ResumenReal {
  totalCompras: number | null;
  /** Horas en que hubo menos gente en piso de la que pedía la venta. */
  horasConFalta: number;
  /** La hora con más compras por persona en piso (la más cargada), si hubo venta. */
  masCargada: { hora: number; comprasPorPersona: number } | null;
}

export function resumenReal(horas: readonly HoraDelDiaReal[]): ResumenReal {
  const conVenta = horas.filter((h) => h.compras !== null);
  const totalCompras = conVenta.length ? conVenta.reduce((a, h) => a + (h.compras ?? 0), 0) : null;
  let masCargada: ResumenReal["masCargada"] = null;
  for (const h of conVenta) {
    if (!h.compras) continue;
    const r = h.compras / Math.max(1, h.enPiso);
    if (!masCargada || r > masCargada.comprasPorPersona + 1e-9) masCargada = { hora: h.hora, comprasPorPersona: Math.round(r * 10) / 10 };
  }
  return {
    totalCompras,
    horasConFalta: horas.filter((h) => h.pedia !== null && h.enPiso < h.pedia).length,
    masCargada,
  };
}
