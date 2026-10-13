// ============================================================================
// planilla-revision.test.ts — Lo que se revisa antes de pagar un periodo
// ============================================================================
// Lo que se defiende acá, cada punto con su accidente o su hallazgo:
//
// 1. EL TOTAL DE UN GRUPO NO DEPENDE DEL FILTRO. Hasta el 2026-09-15 la
//    pantalla sumaba y habilitaba el pago sobre lo filtrado, mientras la base
//    congelaba al grupo entero (auditoría, hallazgo C2).
// 2. LOS DOS FRENOS SON LOS DE LA BASE, CON SU CONDICIÓN. La liquidación está
//    resuelta cuando los descuentos cubren lo que pagó de este mes (0244), no
//    cuando la fila quedó en cero (0243).
// 3. EL DESGLOSE SUMA EL TOTAL, y si no, se dice.
// 4. «CESÓ» SE LEE CONTRA EL PERIODO, no contra hoy.
// 5. A MITAD DE PERIODO NO SE COMPARA COMO SI HUBIERA TERMINADO.
// 6. UN PERIODO ANTERIOR ABIERTO SE VE aunque la pregunta se haga meses después.
// ============================================================================
import { describe, expect, it } from "vitest";
import {
  agruparPorGrupo, agruparHallazgos, avanceDelPeriodo, ceseRespectoDelPeriodo, claveFila, desgloseDe, grupoDe,
  hallazgosDePersona, lecturaDelEstado, liquidacionResuelta, periodoInicialSugerido,
  periodosAnterioresSinPagar, periodosVencidosSinPagar, sumarFilas,
} from "../apps/web/lib/admin/planilla/revision";
import type { Fila, GrupoPago, PeriodoInfo } from "../apps/web/lib/admin/planilla/tipos";
import { COLUMNAS_QUE_RESTAN, COLUMNAS_QUE_SUMAN, filasCsvPlanilla } from "../apps/web/lib/admin/planilla/csv-planilla";

function fila(p: Partial<Fila> = {}): Fila {
  return {
    persona_id: "p1", nombre: "Ana", sede: "LIM", estado: "activo", rango: "r1", salario_ref: 1500,
    en_planilla: true, tipo_vinculo: "planilla", horas_mes: 100, dias_trabajados: 15, dias_pendientes: 0,
    horas_sin_salario: 0, dias_vacaciones: 0, dias_laborables: 22, pago_base: 800,
    basica_legal_prop: null, complemento_variable: null, sueldo_base_legal: null, rendimiento_pct: null,
    rendimiento_por_defecto: null, complemento_etiqueta: null, fecha_ingreso: "2025-01-01",
    feriados_detalle: [], monto_feriados: 0, feriados_no_corresponde: 0, objetivos_cumplidos: null,
    objetivos_total: null, monto_plus: 0, bajo_desempeno: false, feriados_sin_salario: 0, con_hijos: false,
    asignacion_familiar: 0, bonos: 0, descuentos: 0, movimientos: [], provision_gratificacion: 0,
    provision_cts: 0, provision_vacaciones: 0, provision_total: 0, total: 800,
    ...p,
  };
}

const periodo = (id: string, ini: string, fin: string, estado: "abierto" | "pagado" = "abierto"): PeriodoInfo => ({
  id, fecha_ini: ini, fecha_fin: fin, estado, pagado_at: null,
  anio_etiqueta: Number(fin.slice(0, 4)), mes_etiqueta: Number(fin.slice(5, 7)),
});

describe("grupos y totales", () => {
  it("un vínculo desconocido cae en planilla, como en la base", () => {
    expect(grupoDe({ tipo_vinculo: null })).toBe("planilla");
    expect(grupoDe({ tipo_vinculo: "rarisimo" })).toBe("planilla");
    expect(grupoDe({ tipo_vinculo: "practicante" })).toBe("practicante");
  });

  it("agrupa siempre las cinco claves y el total del grupo incluye a quien un filtro escondería", () => {
    const filas = [
      fila({ persona_id: "a", sede: "TRU", total: 500 }),
      fila({ persona_id: "b", sede: "LIM", estado: "inactivo", total: 234.39 }),
      fila({ persona_id: "c", tipo_vinculo: "practicante", total: 300 }),
    ];
    const g = agruparPorGrupo(filas);
    expect([...g.keys()].sort()).toEqual(["no_trabajador", "planilla", "practicante", "prueba", "rxh"]);
    expect(sumarFilas(g.get("planilla")!).total).toBeCloseTo(734.39, 2);
    expect(sumarFilas(g.get("planilla")!).personas).toBe(2);
  });

  it("lo que sale del banco suma pensión, EsSalud y 4ta, y tolera claves ausentes", () => {
    const t = sumarFilas([
      fila({ total: 1000, descuento_afp: 130, aporte_essalud: 102.5 }),
      fila({ total: 920, retencion_4ta: 80 }),
    ]);
    expect(t.sale_del_banco).toBeCloseTo(1000 + 920 + 130 + 102.5 + 80, 2);
  });

  it("suma la movilidad y la educación de cada fila, y una base sin esas claves no da NaN", () => {
    // La tabla de Planilla las muestra en su propia columna (la practicante las
    // cobra desde la 0397): el pie tiene que sumar lo mismo que las filas.
    const t = sumarFilas([
      fila({ tipo_vinculo: "practicante", en_planilla: false, monto_movilidad: 60.5, monto_educacion: 80 }),
      fila({ monto_movilidad: 39.5 }),
      fila({}), // base sin la 0110 / la 0120 pegadas: no manda ninguna de las dos
    ]);
    expect(t.movilidad).toBeCloseTo(100, 2);
    expect(t.educacion).toBeCloseTo(80, 2);
    expect(sumarFilas([fila({})]).movilidad).toBe(0);
    expect(sumarFilas([fila({})]).educacion).toBe(0);
  });

  it("las columnas de la tabla cuadran con las líneas del desglose de la persona", () => {
    // Una sola verdad: lo que la tabla suma por columna es lo que el desglose
    // de cada persona dice en «Movilidad» y «Educación».
    const filas = [
      fila({ monto_movilidad: 60, monto_educacion: 90, total: 950 }),
      fila({ persona_id: "p2", monto_movilidad: 45.25, total: 845.25 }),
    ];
    const t = sumarFilas(filas);
    const deLineas = (clave: string) =>
      filas.reduce((a, f) => a + (desgloseDe(f).lineas.find((l) => l.clave === clave)?.monto ?? 0), 0);
    expect(t.movilidad).toBeCloseTo(deLineas("movilidad"), 2);
    expect(t.educacion).toBeCloseTo(deLineas("educacion"), 2);
  });
});

describe("desglose", () => {
  it("las partidas suman el total con la aritmética del núcleo", () => {
    const f = fila({
      pago_base: 1200, monto_feriados: 50, asignacion_familiar: 113, monto_movilidad: 90, monto_educacion: 100,
      bonos: 40, monto_sobretiempo: 12.5, monto_descanso_semanal: 30,
      descuento_afp: 156, descuentos: 20, retencion_4ta: 0,
      total: 1200 + 50 + 113 + 90 + 100 + 40 + 12.5 + 30 - 156 - 20,
    });
    const d = desgloseDe(f);
    expect(d.cuadra).toBe(true);
    expect(d.lineas.map((l) => l.clave)).not.toContain("retencion_4ta");
    expect(d.lineas[0].clave).toBe("pago_base");
  });

  it("si una partida nueva no está en la lista, lo dice en vez de callar", () => {
    const f = fila({ pago_base: 800, total: 850 });
    const d = desgloseDe(f);
    expect(d.cuadra).toBe(false);
    expect(d.diferencia).toBe(50);
    expect(hallazgosDePersona(f, {}).map((h) => h.codigo)).toContain("desglose_no_cuadra");
  });
});

describe("frenos y avisos", () => {
  const liq = { cobro_del_periodo: 400, total_liquidacion: 2000, pagada_el: "2026-09-07", fecha_cese: "2026-09-05" };

  it("la liquidación se da por resuelta con la condición de la 0244", () => {
    expect(liquidacionResuelta(fila({ total: 600, descuentos: 0 }), liq)).toBe(false);
    // Le queda saldo propio, pero el descuento ya cubre lo que pagó la liquidación.
    expect(liquidacionResuelta(fila({ total: 150, descuentos: 400 }), liq)).toBe(true);
    expect(liquidacionResuelta(fila({ total: 0, descuentos: 0 }), liq)).toBe(true);
  });

  it("solo bloquean los dos frenos de la base", () => {
    const f = fila({ dias_pendientes: 2, horas_sin_salario: 8, total: 600 });
    const h = hallazgosDePersona(f, { liquidada: liq });
    expect(h.filter((x) => x.severidad === "bloquea").map((x) => x.codigo).sort())
      .toEqual(["dias_sin_confirmar", "liquidacion_sin_descuento"]);
    expect(h.find((x) => x.codigo === "sin_salario")?.severidad).toBe("revisar");
  });

  it("de vacaciones en cero no es un hallazgo; sin horario y sin marcar sí", () => {
    const base = { total: 0, horas_mes: 0, pago_base: 0 };
    expect(hallazgosDePersona(fila({ ...base, dias_vacaciones: 30 }), {})).toEqual([]);
    expect(hallazgosDePersona(fila({ ...base, dias_laborables: 0 }), {})[0].codigo).toBe("sin_horario");
    expect(hallazgosDePersona(fila({ ...base, dias_laborables: 20 }), {})[0].codigo).toBe("no_marco");
  });

  it("no pide régimen de pensión a practicantes ni a locadores", () => {
    const sin = { tasa_es_del_regimen: false };
    expect(hallazgosDePersona(fila(sin), {}).map((h) => h.codigo)).toContain("sin_regimen_pension");
    expect(hallazgosDePersona(fila({ ...sin, tipo_vinculo: "practicante", en_planilla: false }), {})).toEqual([]);
    expect(hallazgosDePersona(fila({ ...sin, tipo_vinculo: "rxh", en_planilla: false }), {})).toEqual([]);
  });

  it("agrupa por hallazgo con los bloqueos primero", () => {
    const a = fila({ persona_id: "a", nombre: "Ana", horas_sin_salario: 4 });
    const b = fila({ persona_id: "b", nombre: "Bea", dias_pendientes: 1 });
    const g = agruparHallazgos([
      { fila: a, hallazgos: hallazgosDePersona(a, {}) },
      { fila: b, hallazgos: hallazgosDePersona(b, {}) },
    ]);
    expect(g[0].codigo).toBe("dias_sin_confirmar");
    expect(g[0].personas[0].nombre).toBe("Bea");
  });

  // Caso Ruben Dulce (jul-2026): cesó de RxH a mitad de julio, y el periodo lo
  // cuenta con DOS filas — misma persona_id, tipo_vinculo distinto ("planilla"
  // y "rxh"), cada una con su propio total/descuentos. Un mapa indexado solo
  // por persona_id no puede guardar las dos: la segunda que se procese pisa a
  // la primera, y da igual desde cuál fila se pregunte, siempre se recibe la
  // que quedó guardada al final. Así fue como un "Ya le pagué aparte" puesto
  // correctamente en la fila de RxH no destrababa su pago — el diálogo de
  // cierre seguía leyendo el hallazgo de su fila de Planilla, nunca tocada.
  it("dos filas de la MISMA persona (cambió de grupo a mitad de periodo) no se pisan", () => {
    const planilla = fila({ persona_id: "ruben", nombre: "Ruben Dulce", tipo_vinculo: "planilla", total: 218.99, descuentos: 0 });
    const rxh = fila({ persona_id: "ruben", nombre: "Ruben Dulce", tipo_vinculo: "rxh", total: -112.10, descuentos: 315.92 });
    expect(claveFila(planilla)).not.toBe(claveFila(rxh));

    const liq = { cobro_del_periodo: 315.92, total_liquidacion: 315.92, pagada_el: "2026-08-06", fecha_cese: "2026-07-17" };
    // Un mapa por claveFila SÍ guarda las dos: la de Planilla sigue bloqueada
    // (nunca se le puso el descuento), la de RxH ya quedó resuelta.
    const m = new Map<string, ReturnType<typeof hallazgosDePersona>>();
    for (const f of [planilla, rxh]) m.set(claveFila(f), hallazgosDePersona(f, { liquidada: liq }));
    expect(m.get(claveFila(planilla))!.some((h) => h.codigo === "liquidacion_sin_descuento")).toBe(true);
    expect(m.get(claveFila(rxh))!.some((h) => h.codigo === "liquidacion_sin_descuento")).toBe(false);

    // agruparHallazgos ya traía una entrada por fila (no colapsaba); lo que
    // faltaba es que cada una supiera de qué grupo es, sin volver a adivinarlo
    // con un mapa aparte indexado por persona_id (el mismo problema, dos veces).
    const g = agruparHallazgos([
      { fila: planilla, hallazgos: m.get(claveFila(planilla))! },
      { fila: rxh, hallazgos: m.get(claveFila(rxh))! },
    ]);
    const bloqueo = g.find((x) => x.codigo === "liquidacion_sin_descuento")!;
    expect(bloqueo.personas).toHaveLength(1);
    expect(bloqueo.personas[0]).toMatchObject({ persona_id: "ruben", grupo: "planilla" });
  });
});

describe("cese respecto del periodo", () => {
  const ini = "2026-07-29", fin = "2026-08-28";
  it("cesó dentro, antes o después", () => {
    expect(ceseRespectoDelPeriodo("inactivo", "2026-08-10", ini, fin)).toEqual({ tipo: "durante", fecha: "2026-08-10" });
    expect(ceseRespectoDelPeriodo("inactivo", "2026-07-01", ini, fin)?.tipo).toBe("antes");
    // En agosto trabajó entero: que hoy ya no esté no es un hallazgo de agosto.
    expect(ceseRespectoDelPeriodo("inactivo", "2026-09-10", ini, fin)?.tipo).toBe("despues");
    expect(hallazgosDePersona(fila(), { cese: { tipo: "despues", fecha: "2026-09-10" } })).toEqual([]);
  });
  it("activa sin cese no dice nada; inactiva sin fecha lo dice", () => {
    expect(ceseRespectoDelPeriodo("activo", null, ini, fin)).toBeNull();
    expect(ceseRespectoDelPeriodo("inactivo", null, ini, fin)).toEqual({ tipo: "sin_fecha" });
  });
});

describe("periodos", () => {
  const jul = periodo("jul", "2026-06-29", "2026-07-28");
  const ago = periodo("ago", "2026-07-29", "2026-08-28");
  const sep = periodo("sep", "2026-08-29", "2026-09-27");
  const lista = [sep, ago, jul];

  it("al pagar septiembre se ven julio y agosto abiertos, del más antiguo al más nuevo", () => {
    expect(periodosAnterioresSinPagar(lista, sep).map((p) => p.id)).toEqual(["jul", "ago"]);
    expect(periodosAnterioresSinPagar([sep, { ...ago, estado: "pagado" }, jul], sep).map((p) => p.id)).toEqual(["jul"]);
  });

  it("vencidos: todos, no solo el más antiguo", () => {
    expect(periodosVencidosSinPagar(lista, "2026-09-15").map((p) => p.id)).toEqual(["jul", "ago"]);
  });

  it("abre el que contiene a hoy; si no hay, el más antiguo sin pagar", () => {
    expect(periodoInicialSugerido(lista, "2026-09-15")?.id).toBe("sep");
    expect(periodoInicialSugerido([ago, jul], "2026-09-15")?.id).toBe("jul");
  });

  it("a mitad de periodo está en curso, con los días contados de los dos lados", () => {
    expect(avanceDelPeriodo(sep.fecha_ini, sep.fecha_fin, "2026-09-15")).toEqual({ estado: "en_curso", transcurridos: 18, dias: 30 });
    expect(avanceDelPeriodo(sep.fecha_ini, sep.fecha_fin, "2026-09-27").estado).toBe("en_curso");
    expect(avanceDelPeriodo(sep.fecha_ini, sep.fecha_fin, "2026-09-28").estado).toBe("terminado");
  });

  it("pagado en parte es una lectura de los grupos, no un estado nuevo", () => {
    const grupos: GrupoPago[] = [
      { grupo: "planilla", estado: "pagado", pagado_at: "2026-08-29T12:00:00Z", pagado_por_nombre: "F", personas: 20 },
      { grupo: "practicante", estado: "abierto", pagado_at: null, pagado_por_nombre: null, personas: 3 },
      { grupo: "rxh", estado: "abierto", pagado_at: null, pagado_por_nombre: null, personas: 0 },
    ];
    expect(lecturaDelEstado(ago, grupos, "2026-09-15")).toBe("pagado_en_parte");
    expect(lecturaDelEstado(ago, grupos.map((g) => ({ ...g, estado: "abierto" as const })), "2026-09-15")).toBe("vencido");
    expect(lecturaDelEstado(sep, null, "2026-09-15")).toBe("abierto");
  });
});

describe("CSV para el contador", () => {
  const filas = [
    fila({ persona_id: "p", nombre: "Pia", tipo_vinculo: "practicante", en_planilla: false, pago_base: 500, monto_movilidad: 60, total: 560 }),
    fila({
      persona_id: "a", nombre: "Ana", pago_base: 1200, monto_feriados: 40, asignacion_familiar: 113, monto_educacion: 100,
      bonos: 50, monto_sobretiempo: 12.5, monto_descanso_semanal: 30, descuento_afp: 156, descuentos: 20,
      total: 1200 + 40 + 113 + 100 + 50 + 12.5 + 30 - 156 - 20,
    }),
    fila({ persona_id: "c", nombre: "Cesia", estado: "inactivo", pago_base: 234.39, total: 234.39 }),
  ];
  const csv = filasCsvPlanilla(filas, (id) => (id === "c" ? { tipo: "durante", fecha: "2026-09-10" } : null));

  it("la columna total se reconstruye con sus propias columnas, fila por fila", () => {
    for (const r of csv) {
      const suma = COLUMNAS_QUE_SUMAN.reduce((a, k) => a + Number(r[k]), 0)
        - COLUMNAS_QUE_RESTAN.reduce((a, k) => a + Number(r[k]), 0);
      expect(suma).toBeCloseTo(r.total, 2);
    }
  });

  it("sale completo, con grupo y con quien cesó, ordenado por grupo", () => {
    expect(csv.map((r) => r.nombre)).toEqual(["Ana", "Cesia", "Pia"]);
    expect(csv.map((r) => r.grupo)).toEqual(["Planilla", "Planilla", "Practicantes"]);
    expect(csv[1].situacion_en_periodo).toBe("Cesó el 10 sep");
  });
});
