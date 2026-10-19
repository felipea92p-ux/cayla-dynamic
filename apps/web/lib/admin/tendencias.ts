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
}
export interface ColumnaCosto {
  clave: string;
  /** «28 oct»: el día en que cierra el periodo, que es como se nombra («el de octubre»). */
  etiqueta: string;
  costo: number | null;
  /** El periodo en curso: se dibuja rayado y SIN monto, porque todavía no es un hecho. */
  enCurso: boolean;
  retroactivo: boolean;
  repagado: boolean;
}

const MESES_CORTOS = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];
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
      clave: p.periodo_id, etiqueta: etiquetaCierre(p.fecha_fin), costo: p.costo, enCurso: false,
      retroactivo: p.reconstruida, repagado: p.version > 1,
    }));
  const yaEsta = periodoEnCurso && porPeriodo.some((p) => p.fecha_ini === periodoEnCurso.fecha_ini);
  if (periodoEnCurso && !yaEsta) {
    cols.push({ clave: `en-curso-${periodoEnCurso.fecha_ini}`, etiqueta: etiquetaCierre(periodoEnCurso.fecha_fin), costo: null, enCurso: true, retroactivo: false, repagado: false });
  }
  return cols;
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
