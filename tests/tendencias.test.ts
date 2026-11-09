import { describe, expect, it } from "vitest";
import {
  asistenciaSemanal, barrasDeCasos, calorTardanza, columnasDeCosto, etiquetaCierre, llegadaPorSede, percentil,
  resumenAsistencia, resumenCosto, type FilaAsistencia, type PuntoSemana,
} from "../apps/web/lib/admin/tendencias";
import type { FilaCasoResumen } from "../apps/web/lib/admin/casos-resumen";

const caso = (tipo: string, via = "reclamo"): FilaCasoResumen => ({
  mes: "2026-10-01", sede_id: "s", sede_codigo: "TRU", tipo, via, estado: "recibido", vencido: false,
});
const veces = (n: number, tipo: string, via?: string) => Array.from({ length: n }, () => caso(tipo, via));

describe("barrasDeCasos — nunca un número que identifique a alguien", () => {
  it("muestra una categoría solo si llega al mínimo", () => {
    const r = barrasDeCasos([...veces(6, "persona"), ...veces(2, "clienta")]);
    expect(r.barras.map((b) => b.clave)).toEqual(["persona"]);
  });
  it("junta las chicas en «Otras» solo si JUNTAS llegan al mínimo", () => {
    const r = barrasDeCasos([...veces(6, "persona"), ...veces(3, "clienta"), ...veces(3, "idea")]);
    expect(r.barras.map((b) => [b.clave, b.total])).toEqual([["persona", 6], ["otras", 6]]);
    const sin = barrasDeCasos([...veces(6, "persona"), ...veces(2, "clienta"), ...veces(1, "idea")]);
    expect(sin.barras.map((b) => b.clave)).toEqual(["persona"]); // 3 juntas < 5: seguirían identificando
  });
  it("Título X no aparece ni separado ni dentro de «Otras»", () => {
    const r = barrasDeCasos([...veces(9, "persona", "titulo_x"), ...veces(1, "persona")]);
    expect(r.hayQueMostrar).toBe(false);
    const r2 = barrasDeCasos([...veces(5, "persona"), ...veces(4, "empresa", "titulo_x")]);
    expect(r2.barras).toEqual([{ clave: "persona", etiqueta: "Una persona del equipo", total: 5 }]);
  });
  it("sin casos suficientes dice que no hay qué mostrar", () => {
    expect(barrasDeCasos([]).hayQueMostrar).toBe(false);
    expect(barrasDeCasos(veces(4, "persona")).hayQueMostrar).toBe(false);
  });
});

describe("columnasDeCosto", () => {
  const p = (ini: string, fin: string, costo: number, extra = {}) => ({ periodo_id: ini, fecha_ini: ini, fecha_fin: fin, costo, version: 1, reconstruida: false, ...extra });
  it("ordena de más viejo a más nuevo y marca retroactivo y repagado", () => {
    const c = columnasDeCosto([p("2026-09-29", "2026-10-28", 200), p("2026-08-29", "2026-09-28", 100, { reconstruida: true, version: 2 })], null);
    expect(c.map((x) => x.etiqueta)).toEqual(["28 sep", "28 oct"]);
    expect(c[0]).toMatchObject({ retroactivo: true, repagado: true, costo: 100 });
  });
  it("el periodo en curso va sin monto y rayado", () => {
    const c = columnasDeCosto([p("2026-08-29", "2026-09-28", 100)], { fecha_ini: "2026-09-29", fecha_fin: "2026-10-28" });
    expect(c.at(-1)).toMatchObject({ enCurso: true, costo: null, etiqueta: "28 oct" });
  });
  it("si el periodo en curso ya está pagado no se duplica", () => {
    const c = columnasDeCosto([p("2026-09-29", "2026-10-28", 200)], { fecha_ini: "2026-09-29", fecha_fin: "2026-10-28" });
    expect(c).toHaveLength(1);
    expect(c[0].enCurso).toBe(false);
  });
  it("etiquetaCierre nombra el día de cierre", () => expect(etiquetaCierre("2026-12-28")).toBe("28 dic"));
  it("lleva las fechas reales y cuántas personas entraron, para explicar la diferencia entre meses", () => {
    const c = columnasDeCosto([p("2026-08-29", "2026-09-27", 100, { personas: 23 })], null);
    expect(c[0]).toMatchObject({ fechaIni: "2026-08-29", fechaFin: "2026-09-27", personas: 23, etiqueta: "27 sep" });
    expect(columnasDeCosto([p("2026-08-29", "2026-09-28", 100)], null)[0].personas).toBeNull();
  });
});

describe("resumenCosto — la cifra grande es siempre un periodo pagado", () => {
  const p = (ini: string, fin: string, costo: number) => ({ periodo_id: ini, fecha_ini: ini, fecha_fin: fin, costo, version: 1, reconstruida: false });
  it("el último pagado frente al anterior, en soles y en %", () => {
    const c = columnasDeCosto([p("2026-08-29", "2026-09-27", 33405), p("2026-09-28", "2026-10-28", 40131)], { fecha_ini: "2026-10-29", fecha_fin: "2026-11-28" });
    const r = resumenCosto(c);
    expect(r.ultima?.etiqueta).toBe("28 oct"); // el en curso NO encabeza: no tiene monto
    expect(r).toMatchObject({ diferencia: 6726, variacionPct: 20 });
  });
  it("con un solo periodo pagado no inventa una comparación", () => {
    const r = resumenCosto(columnasDeCosto([p("2026-09-28", "2026-10-28", 40131)], null));
    expect(r).toMatchObject({ diferencia: null, variacionPct: null, anterior: null });
    expect(r.ultima?.costo).toBe(40131);
  });
  it("sin periodos pagados no hay cifra", () => {
    expect(resumenCosto(columnasDeCosto([], { fecha_ini: "2026-10-29", fecha_fin: "2026-11-28" })).ultima).toBeNull();
  });
});

const fila = (sede: string, semana: string, dia: number, trab: number, faltas: number, offsets: number[]): FilaAsistencia =>
  ({ sede_codigo: sede, semana, dia_semana: dia, dias_trabajados: trab, faltas, offsets });

describe("asistenciaSemanal", () => {
  it("trabajados ÷ (trabajados + faltas), con un decimal", () => {
    const r = asistenciaSemanal([fila("TRU", "2026-10-05", 1, 9, 1, []), fila("TRU", "2026-10-05", 2, 8, 2, [])], "2026-12-01", null);
    expect(r).toEqual([{ semana: "2026-10-05", trabajados: 17, faltas: 3, pct: 85, parcial: false }]);
  });
  it("una semana sin días esperados no es 100 %: es «sin dato»", () => {
    expect(asistenciaSemanal([fila("TRU", "2026-10-05", 1, 0, 0, [])], "2026-12-01", null)[0].pct).toBeNull();
  });
  it("marca parcial la semana cuyo domingo aún no pasó, y filtra por sede", () => {
    const filas = [fila("TRU", "2026-10-12", 1, 4, 0, []), fila("LIM", "2026-10-12", 1, 9, 1, [])];
    const r = asistenciaSemanal(filas, "2026-10-14", "LIM");
    expect(r).toHaveLength(1);
    expect(r[0]).toMatchObject({ pct: 90, parcial: true });
  });
});

describe("resumenAsistencia — la cifra grande es la última semana completa", () => {
  const s = (semana: string, trabajados: number, faltas: number, parcial = false): PuntoSemana =>
    ({ semana, trabajados, faltas, pct: trabajados + faltas > 0 ? Math.round((trabajados / (trabajados + faltas)) * 1000) / 10 : null, parcial });
  it("la semana parcial no encabeza aunque sea la última", () => {
    const r = resumenAsistencia([s("2026-10-26", 99, 1), s("2026-11-02", 4, 1, true)]);
    expect(r.ultima?.semana).toBe("2026-10-26");
    expect(r.semanas).toBe(1);
  });
  it("el promedio pondera por días, no promedia porcentajes", () => {
    // 50 % de 4 días y 100 % de 96: el promedio de porcentajes diría 75 %; lo que pasó es 98 %.
    const r = resumenAsistencia([s("2026-10-19", 2, 2), s("2026-10-26", 96, 0)]);
    expect(r.promedio).toBe(98);
  });
  it("la más baja, y entre empatadas la más reciente; una semana sin dato no cuenta", () => {
    const r = resumenAsistencia([s("2026-10-05", 9, 1), s("2026-10-12", 0, 0), s("2026-10-19", 9, 1), s("2026-10-26", 10, 0)]);
    expect(r.minima?.semana).toBe("2026-10-19");
    expect(r.semanas).toBe(3);
  });
  it("sin semanas completas no hay cifra", () => {
    expect(resumenAsistencia([s("2026-11-02", 4, 1, true)])).toEqual({ ultima: null, promedio: null, minima: null, semanas: 0 });
  });
});

describe("llegadaPorSede y calorTardanza — nunca con pocos datos", () => {
  const muchos = (n: number, valor: number) => Array.from({ length: n }, () => valor);
  it("percentil interpola", () => expect(percentil([0, 10, 20, 30], 0.5)).toBe(15));
  it("con menos de 20 llegadas no hay mediana", () => {
    const r = llegadaPorSede([fila("TRU", "2026-10-05", 1, 10, 0, muchos(10, -3))]);
    expect(r[0]).toMatchObject({ sede: "TRU", n: 10, mediana: null });
  });
  it("con 20 o más, mediana y rango central", () => {
    const r = llegadaPorSede([fila("LIM", "2026-10-05", 1, 12, 0, muchos(12, -5)), fila("LIM", "2026-10-12", 1, 12, 0, muchos(12, -3))]);
    expect(r[0].mediana).toBe(-4);
    expect(r[0].p25).toBe(-5);
    expect(r[0].p75).toBe(-3);
  });
  it("el calor: pocas llegadas → sin pintar; sin trabajo ese día → «sin trabajo», no 0 %", () => {
    const filas = [
      fila("TRU", "2026-10-05", 1, 25, 0, [...muchos(20, 0), ...muchos(5, 10)]),
      fila("TRU", "2026-10-05", 2, 3, 0, muchos(3, 12)),
    ];
    const [tru] = calorTardanza(filas);
    const lunes = tru.celdas[0], martes = tru.celdas[1], domingo = tru.celdas[6];
    expect(lunes).toMatchObject({ dia: 1, pctTarde: 20, llegadas: 25 });
    expect(martes).toMatchObject({ pctTarde: null, llegadas: 3, sinTrabajo: false });
    expect(domingo).toMatchObject({ dia: 0, sinTrabajo: true, pctTarde: null });
  });
});
