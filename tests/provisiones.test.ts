import { describe, it, expect } from "vitest";
import {
  COLUMNAS_CSV,
  COLUMNAS_CSV_ANTERIORES,
  calendario,
  estadoVentana,
  estadosFila,
  fechaCorta,
  filasCsv,
  filtrar,
  FILTROS_VACIOS,
  gratiConBonificacion,
  montoProximo,
  pagosDe,
  proximoDesembolso,
  resumen,
  saldoDeFila,
  subvencionDe,
  totalProximo,
  totalesSubvenciones,
  ventanasDe,
  type DesembolsoLibro,
  type ProvData,
  type ProvPersona,
  type SubvData,
} from "@/lib/admin/provisiones";

// Personas de ejemplo con la forma del jsonb de fn_provisiones (0428). Los
// montos son inventados pero internamente coherentes: gran_total es la suma de
// las cuatro columnas ya redondeadas, como lo arma la base.
function persona(o: Partial<ProvPersona> & { persona_id: string; nombre: string }): ProvPersona {
  const base: ProvPersona = {
    persona_id: o.persona_id,
    nombre: o.nombre,
    sede: "TRU",
    fecha_ingreso: "2025-01-10",
    tipo_vinculo: "planilla",
    grati_s1: 0, grati_s2: 0, grati_total: 0,
    be_s1: 0, be_s2: 0, be_total: 0, tasa_be: 0.09,
    cts_may: 0, cts_nov: 0, cts_total: 0,
    vac: 0, vac_dias: 0, proximo_aniversario: "2027-01-10",
    gran_total: 0,
    sin_salario_vigente: false, dias_sin_salario: 0,
  };
  const p = { ...base, ...o };
  p.grati_total = Math.round((p.grati_s1 + p.grati_s2) * 100) / 100;
  p.be_total = Math.round(((p.be_s1 ?? 0) + (p.be_s2 ?? 0)) * 100) / 100;
  p.cts_total = Math.round((p.cts_may + p.cts_nov) * 100) / 100;
  p.gran_total = Math.round((p.grati_total + p.be_total + p.cts_total + p.vac) * 100) / 100;
  return p;
}

function datos(personas: ProvPersona[], asOf = "2026-09-15", proximo?: ProvData["proximo"]): ProvData {
  return {
    as_of: asOf,
    factores: { gratificacion: 0.08333, cts: 0.04167, vacaciones: 0.04167 },
    proximo: proximo ?? { fecha: "2026-11-15", tipo: "CTS", ref: "cts_nov" },
    grati_s1_pago: "2026-07-15", grati_s2_pago: "2026-12-15",
    cts_may_pago: "2026-05-15", cts_nov_pago: "2026-11-15",
    grati_s1_periodo: "ene-jun", grati_s2_periodo: "jul-dic",
    cts_may_periodo: "nov-abr", cts_nov_periodo: "may-oct",
    personas,
  };
}

const alDia = persona({
  persona_id: "a", nombre: "Andrea Ruiz", sede: "LIM",
  grati_s1: 0, grati_s1_pagada: true, grati_s1_monto_pagado: 563.99,
  be_s1: 0, grati_s2: 283.23, be_s2: 25.49,
  cts_may: 0, cts_may_pagada: true, cts_may_monto_pagado: 308.16, cts_nov: 276.7,
  vac: 423.66, vac_dias: 9,
});
const ctsVencida = persona({
  persona_id: "b", nombre: "Rosa Quispe",
  grati_s1: 0, grati_s1_monto_pagado: 332.44, grati_s2: 253.14, be_s2: 22.78,
  cts_may: 67.05, cts_nov: 250.18, vac: 292.82,
});
const parcial = persona({
  persona_id: "c", nombre: "Lucía Flores",
  cts_may: 256.4, cts_may_pagada: true, cts_may_monto_pagado: 141.25, cts_nov: 266.11,
});
const deMas = persona({
  persona_id: "d", nombre: "Marco Salas", sede: "CCO",
  grati_s1: 2.84, grati_s2: 242.51, be_s2: 21.83,
  cts_may: -409.06, cts_may_pagada: true, cts_may_monto_pagado: 409.06, cts_nov: 132.91,
  vac: 122.69,
});
const practicante = persona({ persona_id: "e", nombre: "Sofía Cueva", tipo_vinculo: "practicante" });
const sinTramo = persona({
  persona_id: "f", nombre: "Valeria Ríos", sede: "AQP",
  grati_s2: 120, cts_nov: 118, vac: 60, sin_salario_vigente: true, dias_sin_salario: 34,
});

const equipo = [alDia, ctsVencida, parcial, deMas, practicante, sinTramo];
const d = datos(equipo);
const v = (clave: string) => ventanasDe(d).find((x) => x.clave === clave)!;

describe("estadoVentana — lo que ya pasó y lo que viene no se ven igual", () => {
  it("CTS de mayo sin pago cuatro meses después del 15/05 está vencida", () => {
    expect(estadoVentana(ctsVencida, v("cts_may"), d.as_of)).toBe("vencido");
  });
  it("un depósito parcial deja la ventana vencida por lo que falta", () => {
    expect(estadoVentana(parcial, v("cts_may"), d.as_of)).toBe("pago_parcial");
  });
  it("depositado más que lo devengado se dice «pagado de más», no se esconde", () => {
    expect(estadoVentana(deMas, v("cts_may"), d.as_of)).toBe("pagado_de_mas");
  });
  it("una ventana pagada completa está pagada", () => {
    expect(estadoVentana(alDia, v("cts_may"), d.as_of)).toBe("pagado");
  });
  it("una ventana cuyo pago no llega todavía está acumulando", () => {
    expect(estadoVentana(ctsVencida, v("cts_nov"), d.as_of)).toBe("acumulando");
  });
  it("el mismo día del pago todavía no está vencida", () => {
    const hoyEsQuince = datos([ctsVencida], "2026-05-15");
    const cm = ventanasDe(hoyEsQuince).find((x) => x.clave === "cts_may")!;
    expect(estadoVentana(ctsVencida, cm, hoyEsQuince.as_of)).toBe("acumulando");
  });
  it("sin nada devengado ni pagado, una ventana pasada no se da por pagada", () => {
    expect(estadoVentana(sinTramo, v("grati_s1"), d.as_of)).toBe("sin_monto");
  });
  it("gratificación pagada con el 9 % pendiente no se da por pagada: queda parcial (el caso de la 0372)", () => {
    const sinNueve = persona({ persona_id: "g", nombre: "X", grati_s1: 0, grati_s1_monto_pagado: 500, be_s1: 45 });
    expect(estadoVentana(sinNueve, v("grati_s1"), d.as_of)).toBe("pago_parcial");
  });
  it("una practicante no tiene estado de ventana: no aplica", () => {
    expect(estadoVentana(practicante, v("cts_may"), d.as_of)).toBe("no_aplica");
  });
});

describe("estadosFila", () => {
  it("junta lo que requiere mirar, del más grave al menos", () => {
    expect(estadosFila(sinTramo, d)).toEqual(["sin_tramo"]);
    expect(estadosFila(ctsVencida, d)).toEqual(["vencido"]);
    expect(estadosFila(deMas, d)).toEqual(["vencido", "pagado_de_mas"]); // julio: S/2.84 sin pagar
    expect(estadosFila(alDia, d)).toEqual(["al_dia"]);
    expect(estadosFila(practicante, d)).toEqual(["no_aplica"]);
  });
  it("quien hoy tiene tramo pero tuvo días sin salario en el año no sale «Al día»", () => {
    const conHueco = persona({ persona_id: "j", nombre: "Z", grati_s2: 55.21, be_s2: 4.97, cts_nov: 27.61, vac: 27.61, dias_sin_salario: 240 });
    expect(estadosFila(conHueco, d)).toEqual(["sin_tramo"]);
  });
  it("vacaciones pagadas de más también marcan la fila", () => {
    const vac = persona({ persona_id: "h", nombre: "Diego Torres", vac: -396.24, vac_monto_pagado: 700 });
    expect(estadosFila(vac, d)).toContain("pagado_de_mas");
  });
});

describe("los totales se leen de la base, no se rehacen", () => {
  it("Gratificación (con su 9 %) + CTS + Vacaciones es exactamente gran_total", () => {
    for (const p of equipo) {
      const suma = Math.round((gratiConBonificacion(p) + p.cts_total + p.vac) * 100) / 100;
      expect(suma).toBe(p.gran_total);
    }
  });
  it("el resumen suma gran_total fila por fila y cuenta aparte los pagos de más", () => {
    const r = resumen(equipo);
    expect(r.total).toBe(Math.round(equipo.reduce((a, p) => a + p.gran_total, 0) * 100) / 100);
    expect(r.ajustes).toBe(-409.06);
  });
});

describe("próximo desembolso", () => {
  it("para CTS es lo acumulado a hoy de noviembre", () => {
    expect(montoProximo(ctsVencida, d)).toBe(250.18);
  });
  it("para gratificación incluye el 9 %, que sale el mismo día", () => {
    const dic = datos(equipo, "2026-11-30", { fecha: "2026-12-15", tipo: "Gratificacion", ref: "grati_s2" });
    expect(montoProximo(ctsVencida, dic)).toBe(275.92);
  });
  it("una practicante no tiene próximo pago", () => {
    expect(montoProximo(practicante, d)).toBeNull();
  });
  it("el total no descuenta a una persona el pago de más de otra", () => {
    const adelantada = persona({ persona_id: "i", nombre: "Y", cts_nov: -100, cts_nov_monto_pagado: 150 });
    const dd = datos([ctsVencida, adelantada]);
    expect(totalProximo(dd.personas, dd)).toBe(250.18);
  });
  it("del 16 al 31 de diciembre no inventa un monto: la base apunta al año siguiente", () => {
    const fin = datos(equipo, "2026-12-20", { fecha: "2027-05-15", tipo: "CTS", ref: "cts_may" });
    expect(proximoDesembolso(fin)).toMatchObject({ fecha: "2027-05-15", fiable: false, cierre: null });
    expect(montoProximo(ctsVencida, fin)).toBeNull();
    expect(totalProximo(fin.personas, fin)).toBeNull();
    const cal = calendario(fin, fin.personas);
    expect(cal.proximos).toHaveLength(1);
    expect(cal.proximos[0]).toMatchObject({ fecha: "2027-05-15", monto: null });
  });
  it("el cierre de la ventana es el del año de corte", () => {
    expect(proximoDesembolso(d)?.cierre).toBe("2026-10-31");
  });
});

describe("calendario", () => {
  const cal = calendario(d, equipo);
  it("lista lo vencido con quién lo debe, en orden", () => {
    expect(cal.vencidos.map((x) => x.fecha)).toEqual(["2026-05-15", "2026-07-15"]);
    const mayo = cal.vencidos[0]!;
    expect(mayo.personas.map((x) => x.nombre)).toEqual(["Rosa Quispe", "Lucía Flores"]);
    expect(mayo.monto).toBe(323.45);
  });
  it("lo que viene suma solo saldos positivos y deja fuera a practicantes", () => {
    expect(cal.proximos.map((x) => x.fecha)).toEqual(["2026-11-15", "2026-12-15"]);
    expect(cal.proximos[0]!.monto).toBe(Math.round((276.7 + 250.18 + 266.11 + 132.91 + 118) * 100) / 100);
  });
});

describe("filtros", () => {
  it("busca sin importar tildes ni mayúsculas", () => {
    expect(filtrar(equipo, d, { ...FILTROS_VACIOS, texto: "lucia" }).map((p) => p.nombre)).toEqual(["Lucía Flores"]);
  });
  it("filtra por sede y por estado", () => {
    expect(filtrar(equipo, d, { ...FILTROS_VACIOS, sede: "CCO" })).toEqual([deMas]);
    expect(filtrar(equipo, d, { ...FILTROS_VACIOS, estado: "pagado_de_mas" })).toEqual([deMas]);
  });
});

describe("pagos del libro", () => {
  const libro: DesembolsoLibro[] = [
    { persona_id: "c", ventana: "cts_may", anio: 2026, monto: 141.25, fecha_pago: "2026-05-15", origen: "plame", nota: null, created_at: "2026-05-16T10:00:00Z" },
    { persona_id: "c", ventana: "cts_may", anio: 2025, monto: 99, fecha_pago: "2025-05-15", origen: "plame", nota: null, created_at: "2025-05-16T10:00:00Z" },
  ];
  it("toma solo la ventana y el año de corte", () => {
    const p = pagosDe(parcial, "cts_may", 2026, libro);
    expect(p.filas).toHaveLength(1);
    expect(p.porPlanilla).toBe(0);
  });
  it("lo cobrado que el libro no explica viene de planilla", () => {
    expect(pagosDe(ctsVencida, "grati_s1", 2026, libro)).toMatchObject({ filas: [], porPlanilla: 332.44 });
  });
});

describe("CSV", () => {
  it("las 18 columnas anteriores van primero, en el mismo orden", () => {
    expect(COLUMNAS_CSV.slice(0, 18)).toEqual([...COLUMNAS_CSV_ANTERIORES]);
    expect(COLUMNAS_CSV_ANTERIORES).toHaveLength(18);
  });
  it("y conservan los valores de siempre (proximo_pago_monto sin el 9 %)", () => {
    const [f] = filasCsv(d, [ctsVencida], []);
    expect(f).toMatchObject({
      nombre: "Rosa Quispe", grati_julio_ene_jun: 0, grati_diciembre_jul_dic: 253.14,
      bonificacion_extraordinaria: 22.78, cts_mayo_nov_abr: 67.05, gran_total: ctsVencida.gran_total,
      proximo_pago_monto: 250.18, proximo_pago_fecha: "2026-11-15", sin_tramo_salario: "", dias_sin_salario: "",
    });
  });
  it("las nuevas dicen de dónde salió cada pago", () => {
    const libro: DesembolsoLibro[] = [
      { persona_id: "c", ventana: "cts_may", anio: 2026, monto: 141.25, fecha_pago: "2026-05-15", origen: "plame", nota: null, created_at: "" },
    ];
    const [f] = filasCsv(d, [parcial], libro);
    expect(f).toMatchObject({ fecha_corte: "2026-09-15", cts_mayo_pagado: 141.25, cts_mayo_fecha_pago: "2026-05-15", cts_mayo_via: "PLAME" });
  });
  it("si el libro no se pudo leer, dice «no disponible» en vez de dejar vacío", () => {
    const [f] = filasCsv(d, [parcial], null);
    expect(f).toMatchObject({ cts_mayo_fecha_pago: "no disponible", cts_mayo_via: "no disponible" });
  });
});

describe("subvenciones de modalidad formativa (0466)", () => {
  // Lo que devuelve fn_subvenciones_practicante para la practicante del equipo.
  const subv: SubvData = {
    as_of: "2026-09-15",
    factor_media_subvencion: 0.5,
    factor_descanso: 0.5,
    personas: [
      {
        persona_id: "e",
        nombre: "Sofía Cueva",
        sede: "TRU",
        fecha_ingreso: "2026-01-01",
        subvencion_mensual: 1130,
        sin_subvencion: false,
        semestres_cumplidos: 1,
        semestre_desde: "2026-07-01",
        semestre_hasta: "2027-01-01",
        proximo_hito: "2027-01-01",
        media_sub_devengado: 799.19,
        media_sub_pagado: null,
        media_sub_saldo: 799.19,
        descanso_cumple: "2027-01-01",
        descanso_ganado: false,
        descanso_devengado: 396.35,
        descanso_pagado: null,
        descanso_saldo: 396.35,
        total_saldo: 1195.54,
      },
    ],
  };

  it("encuentra la subvención de su persona y solo la suya", () => {
    expect(subvencionDe(subv, practicante)?.media_sub_saldo).toBe(799.19);
    expect(subvencionDe(subv, ctsVencida)).toBeNull();
  });

  it("mientras se lee, o si no se pudo leer, no inventa una fila", () => {
    expect(subvencionDe(undefined, practicante)).toBeNull();
    expect(subvencionDe(null, practicante)).toBeNull();
  });

  it("el saldo de una practicante sale de su función, no del gran_total de la base", () => {
    // La base manda gran_total 0 para ella, y ESO SIGUE SIENDO CORRECTO: no
    // devenga gratificación, CTS ni vacaciones (art. 47).
    expect(practicante.gran_total).toBe(0);
    expect(saldoDeFila(practicante, subv)).toBe(1195.54);
  });

  it("para el resto del equipo el saldo sigue siendo el de la base", () => {
    expect(saldoDeFila(ctsVencida, subv)).toBe(ctsVencida.gran_total);
  });

  it("los totales de practicantes se suman aparte y dicen a cuántas cubren", () => {
    expect(totalesSubvenciones(equipo, subv)).toEqual({
      media: 799.19,
      descanso: 396.35,
      total: 1195.54,
      personas: 1,
    });
  });

  it("sin practicantes visibles no hay fila de totales que pintar", () => {
    expect(totalesSubvenciones([ctsVencida, alDia], subv)).toBeNull();
  });
});

describe("fechaCorta", () => {
  it("formatea por texto", () => {
    expect(fechaCorta("2026-11-15")).toBe("15 nov 2026");
    expect(fechaCorta(null)).toBe("—");
  });
});
