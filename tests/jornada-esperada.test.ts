import { describe, it, expect } from "vitest";
import {
  dowDe, horarioVigente, esperadoDelDia, fechasDelRango, estadoDelDia,
  type HorarioTramo, type Esperado,
} from "@/lib/admin/jornada-esperada";

// Un horario de tienda AQP: cinco días de 09:00 a 19:00 con una hora de
// refrigerio = 9 h al día × 5 = 45 h/semana. Es el régimen real de LIM y AQP,
// y el que hacía falta para que la meta del gráfico dejara de ser 7.5 h fijas.
const AQP: HorarioTramo = {
  persona_id: "p1",
  vigente_desde: "2026-01-01",
  vigente_hasta: null,
  hora_entrada: "09:00",
  hora_salida: "19:00",
  dias_laborables: [1, 2, 3, 4, 5],
  horario_por_dia: {
    "1": { e: "09:00", s: "19:00", r: 60 },
    "2": { e: "09:00", s: "19:00", r: 60 },
    "3": { e: "09:00", s: "19:00", r: 60 },
    "4": { e: "09:00", s: "19:00", r: 60 },
    "5": { e: "09:00", s: "19:00", r: 60 },
  },
  almuerzo_min_minutos: 45,
};

// Trujillo: seis días, incluido el DOMINGO. Cualquier cálculo que asuma
// «lunes a sábado» da resultados falsos para esta sede.
const TRU: HorarioTramo = {
  persona_id: "p2",
  vigente_desde: "2026-01-01",
  vigente_hasta: null,
  hora_entrada: "10:00",
  hora_salida: "18:30",
  dias_laborables: [0, 1, 2, 3, 4, 5],
  horario_por_dia: {
    "0": { e: "10:00", s: "18:30", r: 60 },
    "1": { e: "10:00", s: "18:30", r: 60 },
    "2": { e: "10:00", s: "18:30", r: 60 },
    "3": { e: "10:00", s: "18:30", r: 60 },
    "4": { e: "10:00", s: "18:30", r: 60 },
    "5": { e: "10:00", s: "18:30", r: 60 },
  },
  almuerzo_min_minutos: 45,
};

describe("dowDe", () => {
  it("lee el día de la semana sin que el huso lo corra un día", () => {
    expect(dowDe("2026-08-09")).toBe(0); // domingo
    expect(dowDe("2026-08-10")).toBe(1); // lunes
    expect(dowDe("2026-08-15")).toBe(6); // sábado
  });
});

describe("esperadoDelDia — las 45 h se cumplen en regímenes distintos", () => {
  it("AQP hace 9 h en cinco días, no 7.5", () => {
    const lunes = esperadoDelDia("2026-08-10", null, AQP);
    expect(lunes.trabaja).toBe(true);
    expect(lunes.entrada).toBe("09:00");
    expect(lunes.horas).toBe(9); // 10 h de reloj − 1 h de refrigerio
    // Cinco días de 9 h = las 45 h de la semana.
    const semana = ["2026-08-10", "2026-08-11", "2026-08-12", "2026-08-13", "2026-08-14"]
      .reduce((s, f) => s + esperadoDelDia(f, null, AQP).horas, 0);
    expect(semana).toBe(45);
  });

  it("Trujillo trabaja el domingo, y también suma 45", () => {
    expect(esperadoDelDia("2026-08-09", null, TRU).trabaja).toBe(true); // domingo
    const semana = ["2026-08-09", "2026-08-10", "2026-08-11", "2026-08-12", "2026-08-13", "2026-08-14"]
      .reduce((s, f) => s + esperadoDelDia(f, null, TRU).horas, 0);
    expect(semana).toBe(45); // 6 × 7.5
  });

  it("un día ausente del horario por día es descanso, no un «no sé»", () => {
    const domingo = esperadoDelDia("2026-08-09", null, AQP);
    expect(domingo.trabaja).toBe(false);
    expect(domingo.horas).toBe(0);
    expect(domingo.origen).toBe("horario");
  });
});

describe("esperadoDelDia — la cascada", () => {
  it("el turno del día manda sobre el horario base", () => {
    const conTurno = esperadoDelDia("2026-08-10",
      { hora_entrada: "14:00", hora_salida: "21:00", es_descanso: false }, AQP);
    expect(conTurno.entrada).toBe("14:00");
    expect(conTurno.horas).toBe(6); // 7 h de reloj − 1 h de refrigerio del horario
    expect(conTurno.origen).toBe("turno");
  });

  it("un turno de descanso apaga el día aunque el horario base diga que trabaja", () => {
    const d = esperadoDelDia("2026-08-10", { hora_entrada: null, hora_salida: null, es_descanso: true }, AQP);
    expect(d.trabaja).toBe(false);
    expect(d.origen).toBe("turno");
  });

  it("sin horario_por_dia se cae al resumen legacy dias_laborables", () => {
    const legacy: HorarioTramo = { ...AQP, horario_por_dia: null };
    expect(esperadoDelDia("2026-08-10", null, legacy).origen).toBe("legacy");
    expect(esperadoDelDia("2026-08-10", null, legacy).horas).toBe(9.25); // 10 h − 45 min
    expect(esperadoDelDia("2026-08-09", null, legacy).trabaja).toBe(false); // domingo
  });

  it("sin turno ni horario no inventa una jornada", () => {
    const d = esperadoDelDia("2026-08-10", null, null);
    expect(d.trabaja).toBe(false);
    expect(d.horas).toBe(0);
    expect(d.origen).toBe("sin_horario");
  });

  it("un turno que cruza medianoche son las horas que son, no dieciséis", () => {
    const noche = esperadoDelDia("2026-08-10",
      { hora_entrada: "21:00", hora_salida: "05:00", es_descanso: false },
      { ...AQP, horario_por_dia: { "1": { e: "09:00", s: "19:00", r: 0 } } });
    expect(noche.horas).toBe(8);
  });
});

describe("horarioVigente", () => {
  const viejo: HorarioTramo = { ...AQP, vigente_desde: "2026-01-01", vigente_hasta: "2026-06-30" };
  const nuevo: HorarioTramo = { ...AQP, vigente_desde: "2026-07-01", vigente_hasta: null };

  it("elige el tramo que cubre la fecha, no el último a secas", () => {
    expect(horarioVigente([viejo, nuevo], "2026-03-15")).toBe(viejo);
    expect(horarioVigente([viejo, nuevo], "2026-08-14")).toBe(nuevo);
  });

  it("devuelve null antes de que exista cualquier tramo", () => {
    expect(horarioVigente([viejo, nuevo], "2025-12-31")).toBeNull();
  });
});

describe("fechasDelRango", () => {
  it("incluye los dos extremos", () => {
    expect(fechasDelRango("2026-08-12", "2026-08-15"))
      .toEqual(["2026-08-12", "2026-08-13", "2026-08-14", "2026-08-15"]);
  });

  it("cruza el fin de mes sin saltarse ni repetir un día", () => {
    const r = fechasDelRango("2026-07-29", "2026-08-02");
    expect(r).toEqual(["2026-07-29", "2026-07-30", "2026-07-31", "2026-08-01", "2026-08-02"]);
  });

  it("un solo día es un solo día", () => {
    expect(fechasDelRango("2026-08-14", "2026-08-14")).toEqual(["2026-08-14"]);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// En qué quedó un día. Esta es la regla que decide el color del cuadrito y lo
// que se cuenta: un fallo acá acusa de faltar a quien no faltó.
// ─────────────────────────────────────────────────────────────────────────────
const TOCABA: Esperado = { trabaja: true, entrada: "09:00", salida: "19:00", horas: 9, origen: "horario" };
const DESCANSO: Esperado = { trabaja: false, entrada: null, salida: null, horas: 0, origen: "horario" };
const SIN_HORARIO: Esperado = { trabaja: false, entrada: null, salida: null, horas: 0, origen: "sin_horario" };

function dia(over: Partial<Parameters<typeof estadoDelDia>[0]> = {}) {
  return estadoDelDia({
    fecha: "2026-08-10", hoy: "2026-08-14", esperado: TOCABA,
    jornada: null, falta: null, tardanzaJustificada: false, agregado: false,
    ...over,
  });
}

describe("estadoDelDia — lo normal", () => {
  it("trabajó su día sin novedad", () => {
    expect(dia({ jornada: { horas: 9, minutosTarde: 0, estado: "cerrada" } })).toBe("ok");
  });

  it("no le tocaba", () => {
    expect(dia({ esperado: DESCANSO })).toBe("descanso");
  });

  it("trabajó en su día de descanso, y eso se ve distinto a un día normal", () => {
    expect(dia({ esperado: DESCANSO, jornada: { horas: 6, minutosTarde: 0, estado: "cerrada" } })).toBe("extra");
  });

  it("sin horario cargado no se afirma que faltó: no hay contra qué medirlo", () => {
    expect(dia({ esperado: SIN_HORARIO })).toBe("sin_horario");
  });

  it("un día que todavía no llega no es una falta", () => {
    expect(dia({ fecha: "2026-08-20", hoy: "2026-08-14" })).toBe("futuro");
  });
});

describe("estadoDelDia — la prioridad, que es donde está la regla", () => {
  it("la falta manda sobre cualquier otra cosa", () => {
    expect(dia({
      falta: { justificada: false },
      jornada: { horas: null, minutosTarde: 30, estado: "auto_cerrada_pendiente" },
    })).toBe("falta");
  });

  it("un marcaje roto manda sobre la tardanza: hasta arreglarlo no se sabe el día", () => {
    expect(dia({ jornada: { horas: null, minutosTarde: 40, estado: "abierta" } })).toBe("revisar");
    expect(dia({ jornada: { horas: 8, minutosTarde: 40, estado: "auto_cerrada_pendiente" } })).toBe("revisar");
  });

  it("la tardanza solo pinta si nadie la justificó", () => {
    expect(dia({ jornada: { horas: 8, minutosTarde: 135, estado: "cerrada" } })).toBe("tarde");
    expect(dia({ jornada: { horas: 8, minutosTarde: 135, estado: "cerrada" }, tardanzaJustificada: true })).toBe("ok");
  });
});

describe("estadoDelDia — los falsos positivos, que son el peor error", () => {
  it("una falta con motivo registrado NO se pinta como falta", () => {
    expect(dia({ falta: { justificada: true } })).toBe("justificada");
  });

  it("le tocaba y no marcó, pero la base no lo llama falta: se dice, no se acusa", () => {
    // Es el caso del feriado: fn_faltas no devuelve fila y la jornada no existe.
    expect(dia({ jornada: null, falta: null })).toBe("sin_marca");
  });

  it("un agregado histórico de 2025 no es un día trabajado ni una falta", () => {
    expect(dia({ agregado: true, jornada: { horas: 180, minutosTarde: null, estado: "cerrada" } })).toBe("sin_marca");
  });

  it("marcó cero horas y no hay falta: queda sin marcar, no como jornada cumplida", () => {
    expect(dia({ jornada: { horas: 0, minutosTarde: 0, estado: "cerrada" } })).toBe("sin_marca");
  });
});
