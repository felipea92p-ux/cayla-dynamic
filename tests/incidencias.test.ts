import { describe, it, expect } from "vitest";
import {
  detectarIncidencias, ventanasDeConsulta, lunesDeLaSemana, addDias, estadoDe, compararIncidencias,
  coberturaDeCarga, enFrase, CARGA_COMPLETA,
  type DatosDeteccion,
} from "@/lib/admin/incidencias";
import { crearCargaVigente } from "@/lib/admin/carga-vigente";

// Martes 15 de setiembre de 2026, el día en que se escribió esto.
const HOY = "2026-09-15";

const persona = (nombres: string, sede = "AQP", extra: Record<string, unknown> = {}) => ({
  nombres, apellidos: "Prueba", en_planilla: true, estado: "activo", sedes: { codigo: sede }, ...extra,
});

function datos(parcial: Partial<DatosDeteccion>): DatosDeteccion {
  return {
    hoy: HOY,
    jornadasRango: [], salidaTemprana: [], tardanzas: [], tardanzasLevantadas: [],
    horasVentana: [], diasRacha: [], aceptadas: [], sedes: [], encargadas: [], equipo: [], metas: [],
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

  it("quien ya cesó no genera avisos de marcación: la detección corre en vivo y nadie va a dar por revisado el día de alguien que ya se fue", () => {
    const r = detectarIncidencias(datos({
      jornadasRango: [{
        persona_id: "p1", fecha: "2026-09-10", estado: "auto_cerrada_pendiente",
        entrada_ts: "2026-09-10T14:00:00Z", salida_final_ts: "2026-09-10T23:00:00Z",
        tiene_salida_no_retornada: true, personas: persona("Sasha", "AQP", { estado: "inactivo" }),
      }],
      salidaTemprana: [{ persona_id: "p1", fecha: "2026-09-10", minutos_salida_temprana: 142 }],
    }));
    expect(r).toEqual([]);
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

  it("a quien ya cesó no se le genera el aviso, aunque haya llegado tarde 4 veces en sus últimos días trabajados", () => {
    const cesada = { estado: "inactivo" };
    const r = detectarIncidencias(datos({
      tardanzas: [tardanza("2026-09-09", cesada), tardanza("2026-09-01", cesada), tardanza("2026-08-20", cesada)],
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

  it("a quien ya cesó no se le genera el aviso de racha", () => {
    const cesado = dias("2026-09-14", 7).map((j) => ({ ...j, personas: persona("Andrés", "LIM", { estado: "inactivo" }) }));
    expect(detectarIncidencias(datos({ diasRacha: cesado }))).toEqual([]);
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

  it("a quien ya cesó no se le genera el aviso de exceso de jornada", () => {
    const filas = Array.from({ length: 7 }, (_, i) => ({
      persona_id: "p1", fecha: addDias("2026-09-14", -i), horas_trabajadas: 7.5, estado: "cerrada",
      personas: persona("Carmen", "TRU", { estado: "inactivo" }),
    }));
    expect(detectarIncidencias(datos({ horasVentana: filas }))).toEqual([]);
  });

  it("una practicante preprofesional se mide contra su propio tope, no contra 48", () => {
    const filas = Array.from({ length: 5 }, (_, i) => ({
      persona_id: "p9", fecha: addDias("2026-09-14", -i), horas_trabajadas: 7, estado: "cerrada",
      personas: persona("Paola", "TRU", { tipo_vinculo: "practicante", practicante_modalidad: "preprofesional" }),
    }));
    const [r] = detectarIncidencias(datos({ horasVentana: filas }));
    expect(r?.detalle).toContain("máx. 30");
  });

  it("al personal de dirección no se le avisa el exceso: la ley lo excluye de la jornada máxima", () => {
    // Las mismas 52.5 h que dan un aviso «vivo» arriba; con la marca de dirección, ninguno.
    const filas = horas("2026-09-14", 7, 7.5).map((f) => ({ ...f, personas: persona("Carmen", "CCO", { personal_direccion: true }) }));
    expect(detectarIncidencias(datos({ horasVentana: filas }))).toEqual([]);
    // Y con la marca en falso, sigue siendo un exceso.
    const sinMarca = horas("2026-09-14", 7, 7.5).map((f) => ({ ...f, personas: persona("Carmen", "TRU", { personal_direccion: false }) }));
    expect(detectarIncidencias(datos({ horasVentana: sinMarca }))[0]?.tipo).toBe("jornada_excedida_viva");
  });

  it("la racha sin descanso SÍ se le avisa al personal de dirección: el descanso semanal es otra norma", () => {
    const filas = Array.from({ length: 8 }, (_, i) => ({
      persona_id: "p1", fecha: addDias("2026-09-14", -i), personas: persona("Carmen", "CCO", { personal_direccion: true }),
    }));
    expect(detectarIncidencias(datos({ diasRacha: filas }))[0]?.tipo).toBe("racha_sin_descanso");
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

  // Quién cuenta como líder es UNA definición (cobertura-equipo.ts), la misma del
  // Dashboard, Turnos y Reporte de sede. Esta detección tenía la suya
  // (`rol = supervisor_sede`) y por eso Central, que la lleva un administrador,
  // salía «0 de 1» TODOS los días: 12 de los 34 «por revisar» en producción.
  const todosLosDias = [0, 1, 2, 3, 4, 5, 6];
  const horario = (persona_id: string) => ({
    persona_id, vigente_desde: "2026-01-01", vigente_hasta: null, hora_entrada: "08:00", hora_salida: "17:00",
    dias_laborables: todosLosDias, horario_por_dia: null, almuerzo_min_minutos: 0,
  });
  const metaTodos = todosLosDias.map((dia_semana) => ({ sede_id: "s1", dia_semana, meta_encargadas: 1 }));
  const admin = { id: "a1", sede_base_id: "s1", rol: "admin", tipo_vinculo: "planilla", es_encargada_piso: false };

  it("en una sede central, un administrador que trabaja ese día cubre la meta", () => {
    const r = detectarIncidencias(datos({
      sedes: [{ id: "s1", codigo: "CCO", tipo: "central" }],
      metas: metaTodos, encargadas: [admin], horarios: [horario("a1")],
    }));
    expect(r).toEqual([]);
  });

  it("en una tienda, un administrador NO cuenta como líder: declararía cubierta una tienda sin encargada", () => {
    const r = detectarIncidencias(datos({
      sedes: [{ id: "s1", codigo: "AQP", tipo: "tienda" }],
      metas: metaTodos, encargadas: [admin], horarios: [horario("a1")],
    }));
    expect(r).toHaveLength(14);
  });

  it("en una tienda, la marca es_encargada_piso sí cuenta, y la líder de equipo también", () => {
    const sedes = [{ id: "s1", codigo: "AQP", tipo: "tienda" }];
    const conMarca = { ...admin, es_encargada_piso: true };
    const lider = { id: "l1", sede_base_id: "s1", rol: "supervisor_sede", tipo_vinculo: "planilla", es_encargada_piso: false };
    expect(detectarIncidencias(datos({ sedes, metas: metaTodos, encargadas: [conMarca], horarios: [horario("a1")] }))).toEqual([]);
    expect(detectarIncidencias(datos({ sedes, metas: metaTodos, encargadas: [lider], horarios: [horario("l1")] }))).toEqual([]);
  });

  it("una sede de tipo desconocido se trata como tienda: nunca cuenta de más", () => {
    const r = detectarIncidencias(datos({
      sedes: [{ id: "s1", codigo: "XX" }],
      metas: metaTodos, encargadas: [admin], horarios: [horario("a1")],
    }));
    expect(r).toHaveLength(14);
  });

  // ── Un día en que a nadie de la sede le toca trabajar (2026-09-20) ────────
  // Central trabaja de lunes a sábado; el domingo es opcional y nadie tiene turno.
  // Con meta de 1 líder los siete días, la bandeja abría «Déficit de líderes (0/1)»
  // cada domingo —dos por visita, este y el próximo— por una falta que ninguna
  // asistencia podía arreglar. HOY = martes 15: los domingos son el 20 y el 27.
  describe("un día en que a nadie de la sede le toca trabajar", () => {
    const DOMINGO = "2026-09-20";
    const DOMINGO_SIGUIENTE = "2026-09-27";
    const lunesASabado = [1, 2, 3, 4, 5, 6];
    const horarioDias = (persona_id: string, dias: number[]) => ({ ...horario(persona_id), dias_laborables: dias });
    const turnoTrabaja = (persona_id: string, fecha: string) =>
      ({ persona_id, fecha, hora_entrada: "09:00", hora_salida: "18:00", es_descanso: false });
    const turnoDescanso = (persona_id: string, fecha: string) =>
      ({ persona_id, fecha, hora_entrada: null, hora_salida: null, es_descanso: true });
    const central = { id: "s1", codigo: "CCO", tipo: "central" };
    const tienda = { id: "s2", codigo: "TRU", tipo: "tienda" };
    const enS1 = (id: string) => ({ id, sede_base_id: "s1" });
    const enS2 = (id: string) => ({ id, sede_base_id: "s2" });

    it("Central el domingo, sin turnos: no avisa; los días que el administrador trabaja no cambian", () => {
      const r = detectarIncidencias(datos({
        sedes: [central], metas: metaTodos,
        encargadas: [admin], equipo: [enS1("a1")], horarios: [horarioDias("a1", lunesASabado)],
      }));
      expect(r).toEqual([]);
    });

    it("el mismo domingo, con el administrador sin horario cargado, SÍ avisa: no se sabe si le tocaba", () => {
      // «Nadie tiene turno» solo calla con una respuesta real de descanso. Sin ningún
      // horario es «no se sabe» —un tramo venció, la sede es nueva—, y ahí el aviso
      // sigue como estaba: callar por una consulta vacía escondería un hueco real.
      const r = detectarIncidencias(datos({
        sedes: [central], metas: metaTodos,
        encargadas: [admin], equipo: [enS1("a1")], horarios: [],
      }));
      expect(r).toHaveLength(14);
    });

    it("sin equipo cargado (o si la consulta del equipo falló) el aviso sale como siempre", () => {
      const r = detectarIncidencias(datos({
        sedes: [central], metas: metaTodos,
        encargadas: [admin], equipo: [], horarios: [horarioDias("a1", lunesASabado)],
      }));
      expect(r.map((i) => i.fecha)).toEqual([DOMINGO, DOMINGO_SIGUIENTE]);
    });

    it("un tramo de horario vencido no es una respuesta de descanso", () => {
      const vencido = { ...horarioDias("a1", lunesASabado), vigente_hasta: "2026-08-31" };
      const r = detectarIncidencias(datos({
        sedes: [central], metas: metaTodos,
        encargadas: [admin], equipo: [enS1("a1")], horarios: [vencido],
      }));
      expect(r).toHaveLength(14);
    });

    it("una tienda con operativas que trabajan y sin líder SÍ tiene déficit; el domingo que nadie abre, no", () => {
      // Las dos operativas trabajan lunes a sábado: seis déficits por semana. Que un
      // administrador de la tienda también trabaje esos días no cuenta como líder.
      const r = detectarIncidencias(datos({
        sedes: [tienda], metas: metaTodos.map((m) => ({ ...m, sede_id: "s2" })),
        encargadas: [{ ...admin, sede_base_id: "s2" }],
        equipo: [enS2("o1"), enS2("o2"), enS2("a1")],
        horarios: [horarioDias("o1", lunesASabado), horarioDias("o2", lunesASabado), horarioDias("a1", lunesASabado)],
      }));
      expect(r).toHaveLength(12);
      expect(r.map((i) => i.fecha)).not.toContain(DOMINGO);
      expect(r.map((i) => i.fecha)).not.toContain(DOMINGO_SIGUIENTE);
      expect(r.every((i) => i.sede === "TRU")).toBe(true);
    });

    it("una tienda con operativas que trabajan TODOS los días, domingo incluido, avisa los catorce", () => {
      const r = detectarIncidencias(datos({
        sedes: [tienda], metas: metaTodos.map((m) => ({ ...m, sede_id: "s2" })),
        encargadas: [], equipo: [enS2("o1")], horarios: [horario("o1")],
      }));
      expect(r).toHaveLength(14);
    });

    it("la semana siguiente funciona igual: un turno puntual ese domingo lo vuelve un déficit de verdad", () => {
      // Central descansa el domingo 20 (calla) pero una colaboradora —que no cuenta
      // como líder— tiene turno el 27: a alguien le toca y no hay líder que lo cubra.
      const r = detectarIncidencias(datos({
        sedes: [central], metas: metaTodos,
        encargadas: [admin], equipo: [enS1("a1"), enS1("c1")],
        horarios: [horarioDias("a1", lunesASabado), horarioDias("c1", lunesASabado)],
        turnos: [turnoTrabaja("c1", DOMINGO_SIGUIENTE)],
      }));
      expect(r.map((i) => [i.fecha, i.detalle])).toEqual([[DOMINGO_SIGUIENTE, "0 de 1 · próxima semana"]]);
    });

    it("un turno de descanso es una respuesta real, aunque no haya horario base", () => {
      // El domingo 20 alguien marcó «descansa» a mano: a nadie le toca. El 27 nadie
      // dijo nada y no hay horario: no se sabe, y avisa.
      const r = detectarIncidencias(datos({
        sedes: [central], metas: [{ sede_id: "s1", dia_semana: 0, meta_encargadas: 1 }],
        encargadas: [admin], equipo: [enS1("a1")], horarios: [],
        turnos: [turnoDescanso("a1", DOMINGO)],
      }));
      expect(r.map((i) => i.fecha)).toEqual([DOMINGO_SIGUIENTE]);
    });

    it("un turno puntual en el domingo le gana a un horario que decía descanso", () => {
      // Su horario base descansa los domingos, pero este domingo tiene turno: a
      // alguien le toca, y sin líder que lo cubra es un déficit de verdad.
      const r = detectarIncidencias(datos({
        sedes: [central], metas: [{ sede_id: "s1", dia_semana: 0, meta_encargadas: 1 }],
        encargadas: [], equipo: [enS1("c1")], horarios: [horarioDias("c1", lunesASabado)],
        turnos: [turnoTrabaja("c1", DOMINGO)],
      }));
      expect(r.map((i) => i.fecha)).toEqual([DOMINGO]);
    });

    it("un líder que trabaja ese día prueba que la sede abre, aunque no figure en el equipo", () => {
      // Meta de 2 líderes el domingo. Un administrador con sueldo fijo (no marca, así que
      // no está en `equipo`) trabaja ese domingo: cubre 1 de 2. El equipo que sí marca
      // descansa —«nadie trabaja»—, pero decirlo callaría el segundo líder que falta.
      const sueldoFijo = { ...admin, id: "f1" };
      const r = detectarIncidencias(datos({
        sedes: [central], metas: [{ sede_id: "s1", dia_semana: 0, meta_encargadas: 2 }],
        encargadas: [sueldoFijo], equipo: [enS1("c1")],
        horarios: [horarioDias("c1", lunesASabado), horario("f1")],
      }));
      expect(r.map((i) => [i.fecha, i.detalle])).toEqual([
        [DOMINGO, "1 de 2"], [DOMINGO_SIGUIENTE, "1 de 2 · próxima semana"],
      ]);
    });

    it("cada sede se responde con SU equipo: que una abra no desapaga a la otra", () => {
      // Domingo: Central descansa entera (calla); la tienda TRU tiene una operativa
      // con turno y ninguna líder (avisa). El equipo de una no entra en la cuenta de la otra.
      const r = detectarIncidencias(datos({
        sedes: [central, tienda],
        metas: [{ sede_id: "s1", dia_semana: 0, meta_encargadas: 1 }, { sede_id: "s2", dia_semana: 0, meta_encargadas: 1 }],
        encargadas: [admin], equipo: [enS1("a1"), enS2("o1")],
        horarios: [horarioDias("a1", lunesASabado), horarioDias("o1", lunesASabado)],
        turnos: [turnoTrabaja("o1", DOMINGO)],
      }));
      expect(r.map((i) => [i.sede, i.fecha])).toEqual([["TRU", DOMINGO]]);
    });
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

describe("lo que no se pudo comprobar", () => {
  it("con todo contestado no hay faltantes ni categorías sin comprobar", () => {
    const c = coberturaDeCarga({ faltas: null, salidas: undefined, excesos: null });
    expect(c).toBe(CARGA_COMPLETA);
    expect(c.duras).toEqual([]);
  });

  it("si falla fn_faltas, «sin faltas» no se puede afirmar: la caja de faltas queda sin comprobar", () => {
    const c = coberturaDeCarga({ faltas: { message: "timeout" } });
    expect(c.duras).toEqual(["las faltas"]);
    expect([...c.categoriasSinComprobar]).toEqual(["faltas"]);
  });

  it("cada fuente dura apaga SU caja del resumen y ninguna otra", () => {
    expect([...coberturaDeCarga({ salidas: 1 }).categoriasSinComprobar]).toEqual(["marcaciones"]);
    expect([...coberturaDeCarga({ excesos: 1 }).categoriasSinComprobar]).toEqual(["patrones"]);
    expect([...coberturaDeCarga({ rachas: 1 }).categoriasSinComprobar]).toEqual(["patrones"]);
  });

  it("una fuente suave se avisa pero NO impide decir «todo revisado» ni apaga ninguna caja", () => {
    const c = coberturaDeCarga({ convenios: { message: "x" }, nombres: { message: "y" } });
    expect(c.faltantes).toHaveLength(2);
    expect(c.duras).toEqual([]);
    expect(c.categoriasSinComprobar.size).toBe(0);
  });

  it("si el equipo no llega, se avisa pero es suave: el déficit avisa de MÁS, nunca de menos", () => {
    // Sin el equipo, el déficit de líderes vuelve a salir también los días en que la
    // sede no trabaja. Son avisos de sobra, no avisos que falten: «todo revisado»
    // sigue siendo cierto, y ninguna caja del resumen queda sin comprobar.
    const c = coberturaDeCarga({ equipo: { message: "timeout" } });
    expect(c.faltantes).toHaveLength(1);
    expect(c.faltantes[0]).toContain("déficit de líderes");
    expect(c.duras).toEqual([]);
    expect(c.categoriasSinComprobar.size).toBe(0);
  });

  it("nombra lo que falta, no la consulta, y respeta el orden declarado", () => {
    const c = coberturaDeCarga({ rachas: 1, faltas: 1, revisiones: 1 });
    expect(c.faltantes).toEqual([
      "las faltas", "los días seguidos sin descanso", "los días que tu equipo pidió revisar",
    ]);
    expect(c.duras).toEqual(["las faltas", "los días seguidos sin descanso"]);
  });

  it("enFrase arma la lista en español", () => {
    expect(enFrase([])).toBe("");
    expect(enFrase(["a"])).toBe("a");
    expect(enFrase(["a", "b"])).toBe("a y b");
    expect(enFrase(["a", "b", "c"])).toBe("a, b y c");
  });
});

describe("carga vigente", () => {
  it("una carga lenta que termina DESPUÉS de una más nueva ya no vale", () => {
    const c = crearCargaVigente();
    const treintaDias = c.empezar();
    const estaSemana = c.empezar();
    // Termina primero la nueva, y luego la vieja llega tarde.
    expect(c.vigente(estaSemana)).toBe(true);
    expect(c.vigente(treintaDias)).toBe(false);
  });

  it("con una sola carga, vale", () => {
    const c = crearCargaVigente();
    expect(c.vigente(c.empezar())).toBe(true);
  });
});
