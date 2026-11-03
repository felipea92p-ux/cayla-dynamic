// «Mi disponibilidad» — las reglas, sin React ni Supabase.
//
// QUÉ PROMETE
//   Pasar de lo que la colaboradora toca en pantalla (una semana tipo de 7
//   días, cada uno «puedo / no puedo / prefiero no / solo algunas horas», más
//   fechas puntuales) a los BLOQUES que guarda la 0584, y de vuelta; decirlo
//   en palabras; aplicar los atajos; y medir cuántas horas le quedan libres
//   contra su jornada.
//
// QUÉ ASUME
//   · El modelo es el de la 0584: un bloque es de un día de la semana (0 =
//     domingo) o de una fecha; sin horas = todo el día; las horas van de media
//     en media hora; «no_puede» o «prefiere_no». Si la base cambia una regla,
//     cambia acá también (validarSemana espeja los CHECK y el EXCLUDE).
//   · La VENTANA de la sede (fn_sede_ventana_semanal) es contra lo que se miden
//     las horas libres: de la entrada más temprana a la salida más tarde del
//     equipo, cada día.
//   · Mañana y tarde se cortan a las 14:00, el mismo corte de «Tu semana»
//     (CORTE_MANANA_TARDE en lib/mi-semana.ts). Son atajos, no el modelo.

import { CORTE_MANANA_TARDE } from "@/lib/mi-semana";

export type EstadoBloque = "no_puede" | "prefiere_no";

/** Una fila de disponibilidad_bloques, como viaja a fn_disponibilidad_enviar. */
export interface Bloque {
  dia_semana?: number;
  fecha?: string;
  desde: string | null;
  hasta: string | null;
  estado: EstadoBloque;
}

export interface Tramo {
  desde: string;
  hasta: string;
  estado: EstadoBloque;
}

export type ModoDia = "puede" | "no_puede" | "prefiere_no" | "horas";

export interface DiaTipo {
  modo: ModoDia;
  /** Solo cuando modo = "horas". */
  tramos: Tramo[];
}

/** 0 = domingo … 6 = sábado. */
export type SemanaTipo = Record<number, DiaTipo>;

/** Una fecha puntual: todo el día o unas horas. */
export interface Excepcion {
  fecha: string;
  desde: string | null;
  hasta: string | null;
  estado: EstadoBloque;
}

export interface Ventana {
  dia: number;
  abre: string;
  cierra: string;
}

export type Motivo = "estudios" | "hijos" | "salud" | "otro_trabajo" | "otro";

export const MOTIVOS: readonly { valor: Motivo; label: string }[] = [
  { valor: "estudios", label: "Estudios" },
  { valor: "hijos", label: "Hijos" },
  { valor: "salud", label: "Salud" },
  { valor: "otro_trabajo", label: "Otro trabajo" },
  { valor: "otro", label: "Otro" },
];

/** De lunes a domingo, como se lee una semana en la tienda. */
export const ORDEN_DIAS = [1, 2, 3, 4, 5, 6, 0] as const;

export const NOMBRE_DIA = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"];
const PLURAL_DIA = ["domingos", "lunes", "martes", "miércoles", "jueves", "viernes", "sábados"];
const MESES = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "set", "oct", "nov", "dic"];

// ── Horas ────────────────────────────────────────────────────────────────────

export function aMinutos(hhmm: string): number {
  const [h, m] = hhmm.slice(0, 5).split(":").map(Number);
  return h * 60 + (m || 0);
}

function aHora(min: number): string {
  return `${String(Math.floor(min / 60)).padStart(2, "0")}:${String(min % 60).padStart(2, "0")}`;
}

/** Las horas que se pueden elegir: de 06:00 a 24:00, de media en media hora. */
export function opcionesHora(): string[] {
  const out: string[] = [];
  for (let m = 6 * 60; m <= 24 * 60; m += 30) out.push(aHora(m));
  return out;
}

const redondeoAbajo = (min: number) => Math.floor(min / 30) * 30;
const redondeoArriba = (min: number) => Math.ceil(min / 30) * 30;

// ── Semana tipo ↔ bloques ────────────────────────────────────────────────────

export function semanaVacia(): SemanaTipo {
  const s: SemanaTipo = {};
  for (let d = 0; d < 7; d++) s[d] = { modo: "puede", tramos: [] };
  return s;
}

/** Los bloques guardados → lo que se dibuja. */
export function desdeBloques(bloques: Bloque[]): { semana: SemanaTipo; excepciones: Excepcion[] } {
  const semana = semanaVacia();
  const excepciones: Excepcion[] = [];
  for (const b of bloques) {
    const desde = b.desde ? b.desde.slice(0, 5) : null;
    const hasta = b.hasta ? b.hasta.slice(0, 5) : null;
    if (b.fecha) {
      excepciones.push({ fecha: b.fecha, desde, hasta, estado: b.estado });
    } else if (b.dia_semana !== undefined && b.dia_semana !== null) {
      const dia = semana[b.dia_semana];
      if (!desde || !hasta) {
        dia.modo = b.estado;
        dia.tramos = [];
      } else {
        dia.modo = "horas";
        dia.tramos.push({ desde, hasta, estado: b.estado });
      }
    }
  }
  for (const d of Object.values(semana)) d.tramos.sort((a, b) => a.desde.localeCompare(b.desde));
  excepciones.sort((a, b) => a.fecha.localeCompare(b.fecha) || (a.desde ?? "").localeCompare(b.desde ?? ""));
  return { semana, excepciones };
}

/** Lo que se dibuja → los bloques que se envían. */
export function aBloques(semana: SemanaTipo, excepciones: Excepcion[]): Bloque[] {
  const out: Bloque[] = [];
  for (const d of ORDEN_DIAS) {
    const dia = semana[d];
    if (dia.modo === "no_puede" || dia.modo === "prefiere_no") {
      out.push({ dia_semana: d, desde: null, hasta: null, estado: dia.modo });
    } else if (dia.modo === "horas") {
      for (const t of dia.tramos) out.push({ dia_semana: d, desde: t.desde, hasta: t.hasta, estado: t.estado });
    }
  }
  for (const e of excepciones) out.push({ fecha: e.fecha, desde: e.desde, hasta: e.hasta, estado: e.estado });
  return out;
}

export function semanaSinRestricciones(semana: SemanaTipo): boolean {
  return ORDEN_DIAS.every((d) => semana[d].modo === "puede" || (semana[d].modo === "horas" && semana[d].tramos.length === 0));
}

// ── Atajos ───────────────────────────────────────────────────────────────────

export type Atajo = "solo_mananas" | "solo_tardes" | "no_domingos" | "puedo_todo";

export const ATAJOS: readonly { valor: Atajo; label: string }[] = [
  { valor: "solo_mananas", label: "Solo mañanas" },
  { valor: "solo_tardes", label: "Solo tardes" },
  { valor: "no_domingos", label: "No domingos" },
  { valor: "puedo_todo", label: "Puedo todo" },
];

/**
 * «Solo mañanas» = no puedo desde las 14:00 hasta que cierra; «Solo tardes» =
 * no puedo desde que abre hasta las 14:00. El día que la sede no abre (no hay
 * ventana) no se toca. Sin ventana conocida se usa 06:00–24:00, el rango del
 * selector, para que el atajo nunca deje un hueco sin marcar.
 */
export function aplicarAtajo(semana: SemanaTipo, atajo: Atajo, ventana: Ventana[]): SemanaTipo {
  if (atajo === "puedo_todo") return semanaVacia();
  const s: SemanaTipo = structuredClone(semana);
  if (atajo === "no_domingos") {
    s[0] = { modo: "no_puede", tramos: [] };
    return s;
  }
  const corte = aMinutos(CORTE_MANANA_TARDE);
  const hayVentana = ventana.length > 0;
  for (const d of ORDEN_DIAS) {
    const v = ventana.find((x) => x.dia === d);
    if (hayVentana && !v) continue;
    const abre = v ? redondeoAbajo(aMinutos(v.abre)) : 6 * 60;
    const cierra = v ? Math.min(24 * 60, redondeoArriba(aMinutos(v.cierra))) : 24 * 60;
    const [ini, fin] = atajo === "solo_mananas" ? [corte, cierra] : [abre, corte];
    if (fin <= ini) {
      s[d] = { modo: "puede", tramos: [] };
      continue;
    }
    s[d] = { modo: "horas", tramos: [{ desde: aHora(ini), hasta: aHora(fin), estado: "no_puede" }] };
  }
  return s;
}

// ── Validar (espeja los CHECK y el EXCLUDE de la 0584) ───────────────────────

export function validar(semana: SemanaTipo, excepciones: Excepcion[]): string | null {
  const revisar = (tramos: { desde: string | null; hasta: string | null }[], donde: string): string | null => {
    const conHoras = tramos.filter((t) => t.desde && t.hasta) as { desde: string; hasta: string }[];
    for (const t of conHoras) {
      if (aMinutos(t.hasta) <= aMinutos(t.desde)) return `${donde}: el tramo de ${t.desde} a ${t.hasta} termina antes de empezar.`;
      if (aMinutos(t.desde) % 30 !== 0 || aMinutos(t.hasta) % 30 !== 0) return `${donde}: las horas van de media en media hora.`;
    }
    const orden = [...conHoras].sort((a, b) => aMinutos(a.desde) - aMinutos(b.desde));
    for (let i = 1; i < orden.length; i++) {
      if (aMinutos(orden[i].desde) < aMinutos(orden[i - 1].hasta)) return `${donde}: dos tramos se cruzan. Júntalos en uno.`;
    }
    if (tramos.some((t) => !t.desde) && tramos.length > 1) return `${donde}: «todo el día» no se junta con tramos.`;
    return null;
  };
  for (const d of ORDEN_DIAS) {
    const dia = semana[d];
    if (dia.modo === "horas") {
      const e = revisar(dia.tramos, `El ${NOMBRE_DIA[d]}`);
      if (e) return e;
    }
  }
  const porFecha = new Map<string, Excepcion[]>();
  for (const x of excepciones) porFecha.set(x.fecha, [...(porFecha.get(x.fecha) ?? []), x]);
  for (const [fecha, xs] of porFecha) {
    const e = revisar(xs, `El ${diaMes(fecha)}`);
    if (e) return e;
  }
  return null;
}

// ── Horas libres contra la jornada ───────────────────────────────────────────

/**
 * Cuántas horas a la semana le quedan disponibles dentro de la ventana de la
 * sede, descontando solo lo que NO PUEDE (prefiere no = sigue disponible). No
 * resta refrigerios: es una cota, no un horario. null si no hay ventana.
 */
export function horasDisponibles(semana: SemanaTipo, ventana: Ventana[]): number | null {
  if (ventana.length === 0) return null;
  let min = 0;
  for (const v of ventana) {
    const abre = aMinutos(v.abre);
    const cierra = aMinutos(v.cierra);
    if (cierra <= abre) continue;
    const dia = semana[v.dia] ?? { modo: "puede", tramos: [] };
    if (dia.modo === "no_puede") continue;
    let libre = cierra - abre;
    if (dia.modo === "horas") {
      for (const t of dia.tramos) {
        if (t.estado !== "no_puede") continue;
        const ini = Math.max(abre, aMinutos(t.desde));
        const fin = Math.min(cierra, aMinutos(t.hasta));
        if (fin > ini) libre -= fin - ini;
      }
    }
    min += Math.max(0, libre);
  }
  return min / 60;
}

/** El aviso contra la jornada, o null si alcanza o no se puede medir. */
export function avisoDeHoras(libres: number | null, jornada: number | null, quien: "tu" | "ella" = "tu"): string | null {
  if (libres === null || jornada === null || libres >= jornada) return null;
  const h = (x: number) => (Number.isInteger(x) ? `${x} h` : `${x.toFixed(1).replace(".", ",")} h`);
  return quien === "tu"
    ? `Con lo que marcaste quedan ${h(libres)} disponibles a la semana y tu jornada es de ${h(jornada)}. Tu líder de equipo lo va a conversar contigo.`
    : `Con lo que marcó quedan ${h(libres)} disponibles a la semana y su jornada es de ${h(jornada)}.`;
}

// ── En palabras ──────────────────────────────────────────────────────────────

export function diaMes(iso: string): string {
  const [, m, d] = iso.split("-").map(Number);
  return `${d} ${MESES[m - 1]}`;
}

function lista(xs: string[]): string {
  if (xs.length <= 1) return xs.join("");
  return `${xs.slice(0, -1).join(", ")} y ${xs[xs.length - 1]}`;
}

/**
 * «No puedes: los martes de 08:30 a 14:00 y los domingos todo el día.
 *  Prefieres no: los sábados de 18:00 a 20:00. Además: el 15 nov no puedes de
 *  16:00 a 20:00.» — o «Puedes cualquier día y hora.» si no hay nada.
 */
export function resumenEnPalabras(semana: SemanaTipo, excepciones: Excepcion[], quien: "tu" | "ella" = "tu"): string[] {
  const verbo = (e: EstadoBloque) =>
    e === "no_puede" ? (quien === "tu" ? "No puedes" : "No puede") : quien === "tu" ? "Prefieres no" : "Prefiere no";
  const partes: Record<EstadoBloque, string[]> = { no_puede: [], prefiere_no: [] };
  for (const d of ORDEN_DIAS) {
    const dia = semana[d];
    if (dia.modo === "no_puede" || dia.modo === "prefiere_no") {
      partes[dia.modo].push(`los ${PLURAL_DIA[d]} todo el día`);
    } else if (dia.modo === "horas") {
      for (const e of ["no_puede", "prefiere_no"] as const) {
        const ts = dia.tramos.filter((t) => t.estado === e).map((t) => `de ${t.desde} a ${t.hasta}`);
        if (ts.length) partes[e].push(`los ${PLURAL_DIA[d]} ${lista(ts)}`);
      }
    }
  }
  const lineas: string[] = [];
  for (const e of ["no_puede", "prefiere_no"] as const) {
    if (partes[e].length) lineas.push(`${verbo(e)}: ${lista(partes[e])}.`);
  }
  if (excepciones.length) {
    const xs = excepciones.map((x) =>
      `el ${diaMes(x.fecha)} ${verbo(x.estado).toLowerCase()} ${x.desde && x.hasta ? `de ${x.desde} a ${x.hasta}` : "todo el día"}`);
    lineas.push(`Además: ${lista(xs)}.`);
  }
  if (lineas.length === 0) lineas.push(quien === "tu" ? "Puedes cualquier día y hora." : "Puede cualquier día y hora.");
  return lineas;
}
