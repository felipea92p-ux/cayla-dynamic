import { describe, it, expect } from "vitest";
import {
  detectarIncidencias, ventanasDeConsulta, lunesDeLaSemana, addDias, estadoDe, compararIncidencias,
  type DatosDeteccion,
} from "@/lib/admin/incidencias";

// Martes 15 de setiembre de 2026, el día en que se escribió esto.
const HOY = "2026-09-15";

const persona = (nombres: string, sede = "AQP", extra: Record<string, unknown> = {}) => ({
  nombres, apellidos: "Prueba", en_planilla: true, sedes: { codigo: sede }, ...extra,
});

function datos(parcial: Partial<DatosDeteccion>): DatosDeteccion {
  return {
    hoy: HOY,
    jornadasRango: [], salidaTemprana: [], tardanzas: [], tardanzasLevantadas: [],
    horasVentana: [], diasRacha: [], aceptadas: [], sedes: [], encargadas: [], metas: [],
    horarios: [], turnos: [], faltas: [],
    etiquetaMotivo: (m) => m ?? "",
    ...parcial,
  };
}

describe("ventanasDeConsulta", () => {
  it("las aceptaciones se piden desde lo más atrás entre el filtro y las ventanas fijas", () => {
    // Filtro estrecho (esta semana): sin el mínimo, un exceso de hace 25 días ya
    // revisado volvería a aparecer solo por haber movido la fecha.
    const v = ventanasDeConsulta(HOY, "2026-09-14", HOY);
    expect(v.desdeAceptadas).toBe("2026-08-16");
    expect(v.desdePatron).toBe("2026-08-17");
    expect(v.desdeHoras).toBe("2026-08-11");
  });
  it("la semana va de lunes a domingo, también si hoy es domingo", () => {
    expect(lunesDeLaSemana("2026-09-15")).toBe("2026-09-14");
    expect(lunesDeLaSemana("2026-09-20")).toBe("2026-09-14");
    expect(addDias("2026-09-14", 13)).toBe("2026-09-27");
  });
});

describe("cierres del día", () => {
  it("un mismo día puede traer varias incidencias a la vez", () => {
    const r = detectarIncidencias(datos({
      jornadasRango: [{
        persona_id: "p1", fecha: "2026-09-10", estado: "auto_cerrada_pendiente",
        entrada_ts: "2026-09-10T14:00:00Z", salida_final_ts: "2026-09-10T23:00:00Z",
        tiene_salida_no_retornada: true, personas: persona("Rosa"),
      }],
      salidaTemprana: [{ persona_id: "p1", fecha: "2026-09-10", minutos_salida_temprana: 142 }],
    }));
    expect(r.map((i) => i.tipo)).toEqual(["auto_cierre", "sin_retorno_almuerzo", "salida_anticipada"]);
    const salida = r[2];
    expect(salida.texto).toBe("Salida anticipada (142 min)");
    expect(salida.valor).toBe(142);
    expect(salida.categoria).toBe("marcaciones");
  });

  it("un día de hoy todavía abierto no es «sin salida»: la persona sigue trabajando", () => {
    const r = detectarIncidencias(datos({
      jornadasRango: [{
        persona_id: "p1", fecha: HOY, estado: "abierta", entrada_ts: "x", salida_final_ts: null,
        tiene_salida_no_retornada: false, personas: persona("Rosa"),
      }],
    }));
    expect(r).toEqual([]);
  });

  it("una aceptación se adjunta a su incidencia; no la hace desaparecer de la detección", () => {
    const r = detectarIncidencias(datos({
      jornadasRango: [{
        persona_id: "p1", fecha: "2026-09-10", estado: "cerrada", entrada_ts: "x", salida_final_ts: "y",
        tiene_salida_no_retornada: false, personas: persona("Rosa"),
      }],
      salidaTemprana: [{ persona_id: "p1", fecha: "2026-09-10", minutos_salida_temprana: 20 }],
      aceptadas: [{ persona_id: "p1", fecha: "2026-09-10", tipo: "salida_anticipada", nota: "cita médica", aceptado_por: "felipe", aceptado_at: "t" }],
    }));
    expect(r).toHaveLength(1);
    expect(r[0].aceptacion?.nota).toBe("cita médica");
  });

  // 0451: el caso que abrió la auditoría. Se aceptaron 20 minutos; una
  // corrección los llevó a 142. Nadie vio esos 142, así que el aviso vuelve.
  const salida142 = {
    jornadasRango: [{
      persona_id: "p1", fecha: "2026-09-04", estado: "cerrada", entrada_ts: "x", salida_final_ts: "y",
      tiene_salida_no_retornada: false, personas: persona("Diego"),
    }],
    salidaTemprana: [{ persona_id: "p1", fecha: "2026-09-04", minutos_salida_temprana: 142 }],
  };

  it("un visto bueno sobre OTRO número caduca: el aviso vuelve y dice qué se había aceptado", () => {
    const [r] = detectarIncidencias(datos({
      ...salida142,
      aceptadas: [{ persona_id: "p1", fecha: "2026-09-04", tipo: "salida_anticipada", nota: null, aceptado_por: "f", aceptado_at: "t", valor: "20" }],
    }));
    expect(r.aceptacion).toBeUndefined();
    expect(r.aceptacionCaducada?.valor).toBe(20);
  });

  it("un visto bueno anterior a la 0451 (sin número) sigue valiendo", () => {
    const [r] = detectarIncidencias(datos({
      ...salida142,
      aceptadas: [{ persona_id: "p1", fecha: "2026-09-04", tipo: "salida_anticipada", nota: null, aceptado_por: "f", aceptado_at: "t", valor: null }],
    }));
    expect(r.aceptacion).toBeDefined();
    expect(r.aceptacionCaducada).toBeUndefined();
  });
});

describe("patrón de tardanzas", () => {
  const tardanza = (fecha: string, extra: Record<string, unknown> = {}) =>
    ({ persona_id: "p1", fecha, entrada_ts: `${fecha}T14:20:00Z`, personas: persona("Lucía", "CCO", extra) });

  it("avisa desde 3 en la ventana y ancla la fila a la más reciente", () => {
    const r = detectarIncidencias(datos({ tardanzas: [tardanza("2026-09-09"), tardanza("2026-09-01"), tardanza("2026-08-20")] }));
    expect(r).toHaveLength(1);
    expect(r[0].fecha).toBe("2026-09-09");
    expect(r[0].detalle).toBe("3 en 30 días corridos");
  });

  it("una tardanza levantada no cuenta", () => {
    const r = detectarIncidencias(datos({
      tardanzas: [tardanza("2026-09-09"), tardanza("2026-09-01"), tardanza("2026-08-20")],
      tardanzasLevantadas: [{ persona_id: "p1", fecha: "2026-09-01" }],
    }));
    expect(r).toEqual([]);
  });

  it("si no se pudo comprobar qué tardanzas se levantaron, no acusa a nadie", () => {
    const r = detectarIncidencias(datos({
      tardanzas: [tardanza("2026-09-09"), tardanza("2026-09-01"), tardanza("2026-08-20")],
      tardanzasLevantadas: null,
    }));
    expect(r).toEqual([]);
  });

  it("a quien no está en planilla (practicante) no se le genera el aviso (0413)", () => {
    const fuera = { en_planilla: false };
    const r = detectarIncidencias(datos({
      tardanzas: [tardanza("2026-09-09", fuera), tardanza("2026-09-01", fuera), tardanza("2026-08-20", fuera)],
    }));
    expect(r).toEqual([]);
  });
});

describe("descanso semanal", () => {
  const dias = (hasta: string, n: number) =>
    Array.from({ length: n }, (_, i) => ({ persona_id: "p1", fecha: addDias(hasta, -i), personas: persona("Andrés", "LIM") }));

  it("7 seguidos es infracción consumada: alta y se saca con visto bueno", () => {
    const [r] = detectarIncidencias(datos({ diasRacha: dias("2026-09-14", 7) }));
    expect(r.tipo).toBe("racha_sin_descanso");
    expect(r.aceptable).toBe("racha_sin_descanso");
    expect(r.severidad).toBe("alta");
  });

  it("6 seguidos hasta ayer es preventivo: baja y sin visto bueno", () => {
    const [r] = detectarIncidencias(datos({ diasRacha: dias("2026-09-14", 6) }));
    expect(r.tipo).toBe("racha_preventiva");
    expect(r.aceptable).toBeUndefined();
    expect(r.severidad).toBe("baja");
  });
});

describe("exceso de jornada", () => {
  const horas = (hasta: string, n: number, h: number) =>
    Array.from({ length: n }, (_, i) => ({
      persona_id: "p1", fecha: addDias(hasta, -i), horas_trabajadas: h, estado: "cerrada", personas: persona("Carmen", "TRU"),
    }));

  it("una ventana de esta semana sobre 48 h es viva: alta, sin visto bueno", () => {
    const [r] = detectarIncidencias(datos({ horasVentana: horas("2026-09-14", 7, 7.5) }));
    expect(r.tipo).toBe("jornada_excedida_viva");
    expect(r.aceptable).toBeUndefined();
    expect(r.valor).toBe(52.5);
  });

  it("una que ya terminó hace más de una semana «ya ocurrió» y se marca revisada", () => {
    const [r] = detectarIncidencias(datos({ horasVentana: horas("2026-09-01", 7, 7.5) }));
    expect(r.tipo).toBe("jornada_excedida");
    expect(r.aceptable).toBe("jornada_excedida");
  });

  it("una practicante preprofesional se mide contra su propio tope, no contra 48", () => {
    const filas = Array.from({ length: 5 }, (_, i) => ({
      persona_id: "p9", fecha: addDias("2026-09-14", -i), horas_trabajadas: 7, estado: "cerrada",
      personas: persona("Paola", "TRU", { tipo_vinculo: "practicante", practicante_modalidad: "preprofesional" }),
    }));
    const [r] = detectarIncidencias(datos({ horasVentana: filas }));
    expect(r?.detalle).toContain("máx. 30");
  });
});

describe("faltas", () => {
  it("la justificada es baja y lleva su motivo legible; la injustificada es alta", () => {
    const r = detectarIncidencias(datos({
      faltas: [
        { persona_id: "p1", nombre: "Rosa Q", sede: "AQP", fecha: "2026-09-11", justificada: false, motivo: null },
        { persona_id: "p1", nombre: "Rosa Q", sede: "AQP", fecha: "2026-08-26", justificada: true, motivo: "estudios" },
      ],
      etiquetaMotivo: (m) => (m === "estudios" ? "Estudios" : m ?? ""),
    }));
    expect(r.map((i) => [i.tipo, i.severidad, i.detalle])).toEqual([
      ["falta_injustificada", "alta", null],
      ["falta_justificada", "baja", "Estudios"],
    ]);
  });
});

describe("déficit de encargadas", () => {
  it("avisa la semana siguiente también, y lo dice", () => {
    // Una sede con meta de 1 encargada los lunes y ninguna encargada: faltan los dos lunes.
    const r = detectarIncidencias(datos({
      sedes: [{ id: "s1", codigo: "LIM" }],
      metas: [{ sede_id: "s1", dia_semana: 1, meta_encargadas: 1 }],
    }));
    expect(r.map((i) => [i.fecha, i.detalle])).toEqual([
      ["2026-09-14", "0 de 1"],
      ["2026-09-21", "0 de 1 · próxima semana"],
    ]);
    expect(r[0].personaId).toBeNull();
    expect(r[0].clave).not.toBe(r[1].clave);
  });
});

describe("estado y orden de la bandeja", () => {
  const casos = detectarIncidencias(datos({
    jornadasRango: [{
      persona_id: "p1", fecha: "2026-09-12", estado: "cerrada", entrada_ts: "x", salida_final_ts: "y",
      tiene_salida_no_retornada: false, personas: persona("Diego"),
    }],
    salidaTemprana: [{ persona_id: "p1", fecha: "2026-09-12", minutos_salida_temprana: 40 }],
    diasRacha: Array.from({ length: 6 }, (_, i) => ({ persona_id: "p2", fecha: addDias("2026-09-14", -i), personas: persona("Paola", "TRU") })),
    faltas: [
      { persona_id: "p3", nombre: "Rosa Q", sede: "AQP", fecha: "2026-09-02", justificada: false, motivo: null },
      { persona_id: "p3", nombre: "Rosa Q", sede: "AQP", fecha: "2026-09-10", justificada: false, motivo: null },
      { persona_id: "p3", nombre: "Rosa Q", sede: "AQP", fecha: "2026-08-26", justificada: true, motivo: "estudios" },
    ],
  }));

  it("una falta justificada está resuelta; 6 días seguidos es preventivo; lo demás, pendiente", () => {
    const por = Object.fromEntries(casos.map((c) => [`${c.tipo}|${c.fecha}`, estadoDe(c)]));
    expect(por["falta_justificada|2026-08-26"]).toBe("resuelta");
    expect(por["racha_preventiva|2026-09-14"]).toBe("preventivo");
    expect(por["falta_injustificada|2026-09-02"]).toBe("pendiente");
    expect(por["salida_anticipada|2026-09-12"]).toBe("pendiente");
  });

  it("ordena por severidad y, dentro de cada una, lo más reciente primero", () => {
    const orden = [...casos].sort(compararIncidencias).map((c) => `${c.severidad} ${c.fecha}`);
    expect(orden).toEqual([
      "alta 2026-09-10", "alta 2026-09-02",
      "media 2026-09-12",
      "baja 2026-09-14", "baja 2026-08-26",
    ]);
  });
});
