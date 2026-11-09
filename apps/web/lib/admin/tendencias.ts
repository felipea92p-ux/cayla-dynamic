// TENDENCIAS DEL DASHBOARD — de cada serie, qué número sale y qué NO se dice.
//
// Funciones PURAS: reciben lo que ya devolvieron la base y devuelven lo que el dibujo necesita. Viven
// aquí y no en el componente para poder probar con vitest las reglas que protegen a alguien:
//
//   · Casos: un número solo se muestra si hay al menos `MINIMO_CASOS` detrás. Con ~30 personas, «1 caso de
//     convivencia en abril» identifica a quien lo escribió. Y el total NO se muestra: con el total y las barras
//     visibles se podría restar y descubrir lo que se ocultó. Las categorías chicas se juntan en «Otras».
//     Título X (acoso sexual) nunca se separa: no aparece en las barras, ni siquiera dentro de «Otras».
//   · Puntualidad: por sede y por día de la semana, nunca por persona. Una celda con menos de
//     `MINIMO_LLEGADAS` llegadas no se pinta: un solo día de una sola persona movería el color.
//   · Lo que no se midió se dice aparte, no se grafica como cero: una semana sin días esperados no es 100 %
//     ni 0 %, es «sin dato»; la semana en curso se marca parcial.

import type { FilaCasoResumen } from "@/lib/admin/casos-resumen";
import { TIPOS_REPORTE } from "@/lib/reportes";
import { codigoDeMotivo } from "@/lib/admin/motivo-falta";

export const MINIMO_CASOS = 5;
export const MINIMO_LLEGADAS = 20;
/** Cuántos minutos después de la hora cuenta como «tarde» en el gráfico (la base no tiene tolerancia). */
export const UMBRAL_TARDE_MIN = 5;

// ── Casos ────────────────────────────────────────────────────────────────────

export interface BarrasCasos {
  barras: { clave: string; etiqueta: string; total: number }[];
  /** Cuántas categorías se juntaron en «Otras» por ser chicas. */
  juntadas: number;
  /** Falso si no queda NINGUNA barra que mostrar: se dice «no hay suficientes casos». */
  hayQueMostrar: boolean;
}

export function barrasDeCasos(filas: readonly FilaCasoResumen[], minimo = MINIMO_CASOS): BarrasCasos {
  const porTipo = new Map<string, number>();
  for (const f of filas) {
    if (f.via === "titulo_x") continue; // nunca se separa ni se cuenta aquí
    porTipo.set(f.tipo, (porTipo.get(f.tipo) ?? 0) + 1);
  }
  const grandes = [...porTipo.entries()].filter(([, n]) => n >= minimo);
  const chicas = [...porTipo.entries()].filter(([, n]) => n < minimo);
  const barras = grandes
    .map(([tipo, total]) => ({ clave: tipo, etiqueta: TIPOS_REPORTE.find((t) => t.valor === tipo)?.titulo ?? tipo, total }))
    .sort((a, b) => b.total - a.total);
  const sumaChicas = chicas.reduce((s, [, n]) => s + n, 0);
  // «Otras» solo se muestra si JUNTAS llegan al mínimo; si no, seguirían identificando a alguien.
  if (sumaChicas >= minimo) barras.push({ clave: "otras", etiqueta: "Otras categorías", total: sumaChicas });
  return { barras, juntadas: chicas.length, hayQueMostrar: barras.length > 0 };
}

// ── Costo de planilla ────────────────────────────────────────────────────────

export interface PeriodoCosto {
  periodo_id: string;
  fecha_ini: string;
  fecha_fin: string;
  costo: number;
  version: number;
  reconstruida: boolean;
  /** Cuántas personas entraron a ese periodo (0323). Opcional: explica por qué un mes cuesta más que otro. */
  personas?: number;
}
export interface ColumnaCosto {
  clave: string;
  /** «28 oct»: el día en que cierra el periodo, que es como se nombra («el de octubre»). */
  etiqueta: string;
  /** Las fechas reales del periodo, leídas de la base: no todos van del 29 al 28 (hubo uno que cerró el 27 sep). */
  fechaIni: string;
  fechaFin: string;
  personas: number | null;
  costo: number | null;
  /** El periodo en curso: se dibuja rayado y SIN monto, porque todavía no es un hecho. */
  enCurso: boolean;
  retroactivo: boolean;
  repagado: boolean;
}

export const MESES_CORTOS = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];
export function etiquetaCierre(fechaFin: string): string {
  const [, m, d] = fechaFin.split("-").map(Number);
  return `${d} ${MESES_CORTOS[m - 1]}`;
}

/** De más viejo a más nuevo. `periodoEnCurso` es el que está abierto hoy (puede no estar entre los pagados). */
export function columnasDeCosto(
  porPeriodo: readonly PeriodoCosto[],
  periodoEnCurso: { periodo_id?: string; fecha_ini: string; fecha_fin: string } | null,
): ColumnaCosto[] {
  const cols: ColumnaCosto[] = [...porPeriodo]
    .sort((a, b) => (a.fecha_ini < b.fecha_ini ? -1 : 1))
    .map((p) => ({
      clave: p.periodo_id, etiqueta: etiquetaCierre(p.fecha_fin), fechaIni: p.fecha_ini, fechaFin: p.fecha_fin,
      personas: p.personas ?? null, costo: p.costo, enCurso: false,
      retroactivo: p.reconstruida, repagado: p.version > 1,
    }));
  const yaEsta = periodoEnCurso && porPeriodo.some((p) => p.fecha_ini === periodoEnCurso.fecha_ini);
  if (periodoEnCurso && !yaEsta) {
    cols.push({
      clave: `en-curso-${periodoEnCurso.fecha_ini}`, etiqueta: etiquetaCierre(periodoEnCurso.fecha_fin),
      fechaIni: periodoEnCurso.fecha_ini, fechaFin: periodoEnCurso.fecha_fin, personas: null,
      costo: null, enCurso: true, retroactivo: false, repagado: false,
    });
  }
  return cols;
}

type ColumnaPagada = ColumnaCosto & { costo: number };

export interface ResumenCosto {
  /** El último periodo YA PAGADO: el que está en curso no tiene monto, así que nunca es la cifra grande. */
  ultima: ColumnaPagada | null;
  anterior: ColumnaPagada | null;
  /** En soles, contra el pagado anterior. null si no hay con qué comparar. */
  diferencia: number | null;
  /** Lo mismo en %, redondeado a entero. null si no hay anterior o el anterior costó 0. */
  variacionPct: number | null;
}

/** La cifra que encabeza el gráfico compacto de costo: el último periodo pagado frente al anterior. */
export function resumenCosto(columnas: readonly ColumnaCosto[]): ResumenCosto {
  const pagadas = columnas.filter((c): c is ColumnaPagada => !c.enCurso && c.costo !== null);
  const ultima = pagadas.at(-1) ?? null;
  const anterior = pagadas.at(-2) ?? null;
  if (!ultima || !anterior) return { ultima, anterior, diferencia: null, variacionPct: null };
  const diferencia = Math.round((ultima.costo - anterior.costo) * 100) / 100;
  return { ultima, anterior, diferencia, variacionPct: anterior.costo > 0 ? Math.round((diferencia / anterior.costo) * 100) : null };
}

// ── Asistencia por sede, semana y día ────────────────────────────────────────

/** Una fila de `fn_asistencia_serie` (0534). */
export interface FilaAsistencia {
  sede_codigo: string;
  semana: string;
  dia_semana: number;
  dias_trabajados: number;
  faltas: number;
  offsets: number[];
}

export interface PuntoSemana {
  semana: string;
  trabajados: number;
  faltas: number;
  /** null = no había días esperados esa semana: «sin dato», no 100 %. */
  pct: number | null;
  /** La semana que todavía no terminó: se dibuja hueca. */
  parcial: boolean;
}

/** `hoy` es YYYY-MM-DD en Lima; una semana es parcial si su domingo todavía no pasó. */
export function asistenciaSemanal(filas: readonly FilaAsistencia[], hoy: string, sede: string | null): PuntoSemana[] {
  const porSemana = new Map<string, { t: number; f: number }>();
  for (const r of filas) {
    if (sede && r.sede_codigo !== sede) continue;
    const a = porSemana.get(r.semana) ?? { t: 0, f: 0 };
    a.t += r.dias_trabajados; a.f += r.faltas;
    porSemana.set(r.semana, a);
  }
  return [...porSemana.entries()]
    .sort((a, b) => (a[0] < b[0] ? -1 : 1))
    .map(([semana, { t, f }]) => ({
      semana, trabajados: t, faltas: f,
      pct: t + f > 0 ? Math.round((t / (t + f)) * 1000) / 10 : null,
      parcial: sumarDias(semana, 6) >= hoy,
    }));
}

type SemanaMedida = PuntoSemana & { pct: number };

export interface ResumenAsistencia {
  /** La última semana COMPLETA con dato. La parcial no encabeza: un lunes con una falta la mostraría en 80 %. */
  ultima: SemanaMedida | null;
  /**
   * De todas las semanas completas, ponderado por días: Σ trabajados ÷ Σ (trabajados + faltas). No es el
   * promedio de los porcentajes —una semana con 4 días esperados pesaría lo mismo que una con 120—.
   */
  promedio: number | null;
  /** La semana completa más baja; si empatan, la más reciente (la que alguien todavía recuerda). */
  minima: SemanaMedida | null;
  semanas: number;
}

export function resumenAsistencia(puntos: readonly PuntoSemana[]): ResumenAsistencia {
  const completas = puntos.filter((p): p is SemanaMedida => p.pct !== null && !p.parcial);
  if (completas.length === 0) return { ultima: null, promedio: null, minima: null, semanas: 0 };
  const t = completas.reduce((s, p) => s + p.trabajados, 0);
  const e = completas.reduce((s, p) => s + p.trabajados + p.faltas, 0);
  const minima = completas.reduce((m, p) => (p.pct <= m.pct ? p : m));
  return { ultima: completas.at(-1)!, promedio: Math.round((t / e) * 1000) / 10, minima, semanas: completas.length };
}

// ── Días perdidos, por motivo ────────────────────────────────────────────────
//
// La asistencia (arriba) solo mira los días SIN motivo: un descanso médico no la baja, así que puede decir 99 %
// mientras se pierde el 5 % de los días. Esto cuenta todo lo que se perdió y separa por qué.
//
// La fuente es `fn_faltas` (0414): una fila por cada día que a alguien le TOCABA trabajar (la cascada turno →
// horario por día → días laborables) y no vino, con su motivo. Son días laborables, no de calendario: un descanso
// médico de 15 días no cuenta los domingos de quien no trabaja domingo. Mide a la misma gente que la asistencia
// (en planilla o practicante, sin sueldo fijo) con los mismos permisos (la líder de equipo, su sede).

/** Una fila de `fn_faltas`. `motivo` null = no hay nada que lo justifique. */
export interface FilaFalta {
  persona_id: string;
  sede: string;
  fecha: string;
  justificada: boolean | null;
  motivo: string | null;
}

/** Motivos de fn_faltas que no son un día perdido: un descanso planificado o compensado, o una sanción. */
export const MOTIVOS_QUE_NO_SE_PIERDEN: ReadonlySet<string> = new Set(["vacaciones", "descanso_sustitutorio", "suspension"]);
/** La clave de los días sin motivo. */
export const SIN_JUSTIFICAR = "sin_justificar";
/** La clave de los motivos que se juntan por chicos. */
export const OTROS_MOTIVOS = "otros";
/** Cuántos motivos se dibujan por separado; el resto va junto en «Otros motivos». */
export const MOTIVOS_A_LA_VISTA = 3;

export interface MesPerdido {
  /** YYYY-MM */
  mes: string;
  /** El periodo elegido o el día de hoy cortan el mes: sus días no se comparan con los de un mes entero. */
  parcial: boolean;
  perdidos: number;
  trabajados: number;
  /** perdidos ÷ (trabajados + perdidos), con un decimal. null si ese mes no hubo días que mirar. */
  pct: number | null;
}
export interface MotivoPerdido {
  clave: string;
  /** Un número por cada mes de `meses`, en el mismo orden. */
  dias: number[];
  total: number;
}
export interface DiasPerdidos {
  meses: MesPerdido[];
  /** De más días a menos; «Otros motivos», si hace falta, al final. */
  motivos: MotivoPerdido[];
}

/** El lunes de `semana` más el día de la semana (0 = domingo, como `extract(dow)`): la fecha exacta. */
export function fechaDeSemana(semana: string, diaSemana: number): string {
  return sumarDias(semana, (diaSemana + 6) % 7);
}

/**
 * `desde` es el primer día del periodo elegido y `hoy` la fecha de Lima: lo de hoy todavía no es un hecho, así que
 * el último día que se mira es ayer, como en la asistencia.
 */
export function diasPerdidosPorMes(
  faltas: readonly FilaFalta[],
  asistencia: readonly FilaAsistencia[],
  desde: string,
  hoy: string,
  sede: string | null,
): DiasPerdidos {
  const hasta = sumarDias(hoy, -1);
  if (hasta < desde) return { meses: [], motivos: [] };
  const claves: string[] = [];
  for (let m = desde.slice(0, 7); m <= hasta.slice(0, 7); m = mesSiguiente(m)) claves.push(m);
  const indice = new Map(claves.map((m, i) => [m, i]));

  const trabajados = claves.map(() => 0);
  for (const r of asistencia) {
    if (sede && r.sede_codigo !== sede) continue;
    const f = fechaDeSemana(r.semana, r.dia_semana);
    const i = f >= desde && f <= hasta ? indice.get(f.slice(0, 7)) : undefined;
    if (i !== undefined) trabajados[i] += r.dias_trabajados;
  }

  const porMotivo = new Map<string, number[]>();
  for (const f of faltas) {
    if (sede && f.sede !== sede) continue;
    if (f.motivo && MOTIVOS_QUE_NO_SE_PIERDEN.has(f.motivo)) continue;
    const i = f.fecha >= desde && f.fecha <= hasta ? indice.get(f.fecha.slice(0, 7)) : undefined;
    if (i === undefined) continue;
    const clave = f.motivo ? codigoDeMotivo(f.motivo) : SIN_JUSTIFICAR;
    const fila = porMotivo.get(clave) ?? claves.map(() => 0);
    fila[i] += 1;
    porMotivo.set(clave, fila);
  }

  const todos = [...porMotivo.entries()]
    .map(([clave, dias]) => ({ clave, dias, total: dias.reduce((s, n) => s + n, 0) }))
    .sort((a, b) => b.total - a.total || a.clave.localeCompare(b.clave));
  // Más de MOTIVOS_A_LA_VISTA + 1 motivos: los primeros por separado y el resto junto. Si sobra uno solo, se
  // muestra con su nombre: «Otros motivos» con un único motivo adentro escondería un nombre que cabía.
  const motivos = todos.length <= MOTIVOS_A_LA_VISTA + 1
    ? todos
    : [
        ...todos.slice(0, MOTIVOS_A_LA_VISTA),
        todos.slice(MOTIVOS_A_LA_VISTA).reduce<MotivoPerdido>(
          (acc, m) => ({ clave: OTROS_MOTIVOS, dias: acc.dias.map((n, i) => n + m.dias[i]), total: acc.total + m.total }),
          { clave: OTROS_MOTIVOS, dias: claves.map(() => 0), total: 0 },
        ),
      ];

  const meses = claves.map((mes, i): MesPerdido => {
    const perdidos = todos.reduce((s, m) => s + m.dias[i], 0);
    const base = trabajados[i] + perdidos;
    return {
      mes,
      parcial: `${mes}-01` < desde || finDeMes(mes) > hasta,
      perdidos,
      trabajados: trabajados[i],
      pct: base > 0 ? Math.round((perdidos / base) * 1000) / 10 : null,
    };
  });
  // «Desde enero» en un sistema que empezó a medir en julio: los meses de antes no son meses en cero, son meses
  // sin medir. No se dibujan.
  const primero = meses.findIndex((m) => m.pct !== null);
  if (primero < 0) return { meses: [], motivos: [] };
  return {
    meses: meses.slice(primero),
    motivos: motivos.map((m) => ({ ...m, dias: m.dias.slice(primero) })),
  };
}

function mesSiguiente(mes: string): string {
  const [y, m] = mes.split("-").map(Number);
  return m === 12 ? `${y + 1}-01` : `${y}-${String(m + 1).padStart(2, "0")}`;
}
function finDeMes(mes: string): string {
  return sumarDias(`${mesSiguiente(mes)}-01`, -1);
}

function sumarDias(iso: string, n: number): string {
  const [y, m, d] = iso.split("-").map(Number);
  const f = new Date(Date.UTC(y, m - 1, d + n));
  return f.toISOString().slice(0, 10);
}

/** Percentil con interpolación lineal sobre una lista YA ordenada. */
export function percentil(ordenada: readonly number[], p: number): number | null {
  if (ordenada.length === 0) return null;
  const pos = (ordenada.length - 1) * p;
  const lo = Math.floor(pos), hi = Math.ceil(pos);
  return ordenada[lo] + (ordenada[hi] - ordenada[lo]) * (pos - lo);
}

export interface LlegadaSede {
  sede: string;
  n: number;
  /** null si hay menos de MINIMO_LLEGADAS llegadas: no se dibuja un punto con tres datos. */
  mediana: number | null;
  p25: number | null;
  p75: number | null;
}

export function llegadaPorSede(filas: readonly FilaAsistencia[], minimo = MINIMO_LLEGADAS): LlegadaSede[] {
  const porSede = new Map<string, number[]>();
  for (const r of filas) {
    const a = porSede.get(r.sede_codigo) ?? [];
    a.push(...r.offsets);
    porSede.set(r.sede_codigo, a);
  }
  return [...porSede.entries()]
    .map(([sede, lista]) => {
      const o = [...lista].sort((a, b) => a - b);
      const ok = o.length >= minimo;
      return { sede, n: o.length, mediana: ok ? percentil(o, 0.5) : null, p25: ok ? percentil(o, 0.25) : null, p75: ok ? percentil(o, 0.75) : null };
    })
    .sort((a, b) => a.sede.localeCompare(b.sede));
}

export interface CeldaCalor {
  /** 0 = domingo … 6 = sábado, como `extract(dow)`. */
  dia: number;
  /** null = la celda no se pinta (pocas llegadas o día sin trabajo). */
  pctTarde: number | null;
  llegadas: number;
  /** «sin trabajo»: nadie de la sede llegó ese día de la semana en todo el periodo. */
  sinTrabajo: boolean;
}

/** Una fila por sede, siete celdas (lunes primero). */
export function calorTardanza(filas: readonly FilaAsistencia[], minimo = MINIMO_LLEGADAS, umbral = UMBRAL_TARDE_MIN): { sede: string; celdas: CeldaCalor[] }[] {
  const sedes = new Map<string, Map<number, { trab: number; ofs: number[] }>>();
  for (const r of filas) {
    const dias = sedes.get(r.sede_codigo) ?? new Map<number, { trab: number; ofs: number[] }>();
    const a = dias.get(r.dia_semana) ?? { trab: 0, ofs: [] };
    a.trab += r.dias_trabajados; a.ofs.push(...r.offsets);
    dias.set(r.dia_semana, a);
    sedes.set(r.sede_codigo, dias);
  }
  const ORDEN = [1, 2, 3, 4, 5, 6, 0];
  return [...sedes.entries()]
    .sort((a, b) => a[0].localeCompare(b[0]))
    .map(([sede, dias]) => ({
      sede,
      celdas: ORDEN.map((dia): CeldaCalor => {
        const a = dias.get(dia);
        if (!a || a.trab === 0) return { dia, pctTarde: null, llegadas: 0, sinTrabajo: true };
        const n = a.ofs.length;
        const tarde = a.ofs.filter((o) => o >= umbral).length;
        return { dia, pctTarde: n >= minimo ? Math.round((tarde / n) * 100) : null, llegadas: n, sinTrabajo: false };
      }),
    }));
}
