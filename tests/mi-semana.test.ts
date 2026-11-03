import { describe, it, expect } from "vitest";
import {
  armarSemana, cuadreDeSemana, hoyEnUnaLinea, inclinacionDeSemana, lunesDe,
  semanaDe, textoHoras, textoRotacion, totalDeSemana,
} from "@/lib/mi-semana";
import type { HorarioTramo, TurnoDia } from "@/lib/admin/jornada-esperada";
import { puestoDesdeFilas, textoPuesto } from "@/lib/admin/almacen";

// Una semana de TRU: lunes a sábado, descanso el domingo, refrigerio de 60 solo
// el sábado (turno largo). 6 h × 5 + 11.75 − 1 = 40.75 h.
const TRAMO: HorarioTramo = {
  persona_id: "p1",
  vigente_desde: "2026-10-01",
  vigente_hasta: null,
  hora_entrada: null,
  hora_salida: null,
  dias_laborables: [1, 2, 3, 4, 5, 6],
  horario_por_dia: {
    "1": { e: "08:30", s: "14:30" },
    "2": { e: "08:30", s: "14:30" },
    "3": { e: "14:15", s: "20:15" },
    "4": { e: "14:15", s: "20:15" },
    "5": { e: "14:15", s: "20:15" },
    "6": { e: "08:30", s: "20:15", r: 60 },
  },
  almuerzo_min_minutos: 0,
};

const LUNES = "2026-11-09";

function semana(turnos: Record<string, TurnoDia> = {}, puestos: Parameters<typeof armarSemana>[0]["puestos"] = null) {
  return armarSemana({
    lunes: LUNES, turnos: new Map(Object.entries(turnos)), tramos: [TRAMO],
    feriados: new Map(), puestos,
  });
}

describe("las fechas de la semana", () => {
  it("la semana va de lunes a domingo, también cuando hoy es domingo", () => {
    expect(lunesDe("2026-11-09")).toBe("2026-11-09");   // lunes
    expect(lunesDe("2026-11-12")).toBe("2026-11-09");   // jueves
    expect(lunesDe("2026-11-15")).toBe("2026-11-09");   // domingo: NO salta a la semana siguiente
    expect(semanaDe(LUNES)).toEqual([
      "2026-11-09", "2026-11-10", "2026-11-11", "2026-11-12", "2026-11-13", "2026-11-14", "2026-11-15",
    ]);
  });
  it("cruza el cambio de mes y de año", () => {
    expect(lunesDe("2027-01-02")).toBe("2026-12-28");
  });
});

describe("el total de la semana", () => {
  it("suma las horas ya sin refrigerio y lo compara con su horario", () => {
    const t = totalDeSemana(semana());
    expect(t.horas).toBeCloseTo(40.75);
    expect(t.referencia).toBeCloseTo(40.75);
    expect(t.diasDeTrabajo).toBe(6);
    expect(cuadreDeSemana(t)?.tono).toBe("positivo");
  });

  it("un turno puntual que acorta un día se dice con palabras, sin prometer que alguien lo revisa", () => {
    const t = totalDeSemana(semana({ "2026-11-10": { hora_entrada: "08:30", hora_salida: "12:30", es_descanso: false } }));
    expect(t.horas).toBeCloseTo(38.75);
    const c = cuadreDeSemana(t)!;
    expect(c.tono).toBe("advertencia");
    expect(c.texto).toContain("2 h menos que tu horario");
    expect(c.texto).toContain("pregúntale a tu líder de equipo");
    expect(c.texto).not.toMatch(/revisando/);
  });

  it("un descanso puesto por turno resta el día entero", () => {
    const t = totalDeSemana(semana({ "2026-11-14": { hora_entrada: null, hora_salida: null, es_descanso: true } }));
    expect(t.horas).toBeCloseTo(30);
    expect(t.diasDeTrabajo).toBe(5);
  });

  it("sin horario base no hay contra qué comparar, y no inventa un cuadre", () => {
    const dias = armarSemana({ lunes: LUNES, turnos: new Map(), tramos: [], feriados: new Map(), puestos: null });
    const t = totalDeSemana(dias);
    expect(t.referencia).toBeNull();
    expect(cuadreDeSemana(t)).toBeNull();
  });

  it("el refrigerio del día viaja con el día", () => {
    const dias = semana();
    expect(dias[5].esperado.refrigerioMin).toBe(60);   // sábado
    expect(dias[0].esperado.refrigerioMin).toBe(0);
  });
});

describe("las palabras", () => {
  it("horas legibles", () => {
    expect(textoHoras(45)).toBe("45 h");
    expect(textoHoras(7.25)).toBe("7 h 15 min");
    expect(textoHoras(0.5)).toBe("30 min");
  });
});

describe("la rotación", () => {
  it("cuenta mañanas y tardes por el punto medio del turno", () => {
    // Lun y Mar mañana; Mié–Vie tarde; Sáb 08:30–20:15 tiene el medio a las 14:22 → tarde.
    expect(inclinacionDeSemana(semana())).toBe("tardes");
  });
  it("solo habla de la próxima si la próxima dice otra cosa", () => {
    expect(textoRotacion("tardes", "mananas")).toBe("Esta semana haces más tardes; la próxima, más mañanas.");
    expect(textoRotacion("tardes", "tardes")).toBe("Esta semana haces más tardes.");
    expect(textoRotacion("tardes", null)).toBe("Esta semana haces más tardes.");
    expect(textoRotacion("pareja", "mananas")).toBeNull();
    expect(textoRotacion(null, "mananas")).toBeNull();
  });
});

describe("el puesto", () => {
  it("si la tabla no se pudo leer no se afirma ningún puesto", () => {
    expect(semana().every((d) => d.puesto === null)).toBe(true);
  });

  it("leída y sin filas es piso; con filas, almacén entero o por tramos", () => {
    const dias = semana({}, [
      { fecha: "2026-11-10", desde: "10:30:00", hasta: "12:30:00" },
      { fecha: "2026-11-12", desde: null, hasta: null },
      { fecha: "2026-11-15", desde: null, hasta: null },   // domingo: descansa, no se muestra
    ]);
    expect(textoPuesto(dias[0].puesto!)).toBe("Piso");
    expect(textoPuesto(dias[1].puesto!)).toBe("Almacén 10:30–12:30");
    expect(textoPuesto(dias[3].puesto!)).toBe("Almacén todo el turno");
    expect(dias[6].puesto).toBeNull();
  });

  it("varios tramos del mismo día salen en orden", () => {
    expect(textoPuesto(puestoDesdeFilas([
      { desde: "16:00", hasta: "17:00" },
      { desde: "10:30", hasta: "11:00" },
    ]))).toBe("Almacén 10:30–11:00, 16:00–17:00");
  });

  it("la línea de hoy del Resumen", () => {
    const dias = semana({}, [{ fecha: "2026-11-10", desde: "10:30", hasta: "12:30" }]);
    expect(hoyEnUnaLinea(dias[0])).toBe("08:30–14:30 en piso");
    expect(hoyEnUnaLinea(dias[1])).toBe("08:30–14:30 · almacén 10:30–12:30");
    expect(hoyEnUnaLinea(dias[6])).toBe("Descansas");
    expect(hoyEnUnaLinea(semana()[0])).toBe("08:30–14:30");   // sin saber el puesto, no lo inventa
  });
});
