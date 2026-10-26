import { describe, it, expect } from "vitest";
import {
  dowDe, horarioVigente, esperadoDelDia, fechasDelRango, estadoDelDia, esTurnoEspejoViejo,
  esJornadaEnCurso, cuentaEnLoQueLeTocaba,
  diaDeLaSede, diaDeLaSedeDe, esFeriadoSinTurno, SEDE_SIN_TURNOS,
  type HorarioTramo, type Esperado, type TurnoDia,
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

// ─────────────────────────────────────────────────────────────────────────────
// El caso Diana (set-2026): un turno puntual viejo que quedó de un horario ya
// reemplazado sigue mandando sobre el horario base y genera una tardanza falsa.
// Dos tramos —el que Diana tenía hasta agosto y el que tiene desde setiembre—,
// y turnos puntuales fechados YA en setiembre (cuando el vigente es el nuevo).
// ─────────────────────────────────────────────────────────────────────────────
const DIANA_VIEJO: HorarioTramo = {
  persona_id: "diana",
  vigente_desde: "2026-01-01",
  vigente_hasta: "2026-08-31",
  hora_entrada: "07:45",
  hora_salida: "16:45",
  dias_laborables: [1, 2, 3, 4, 5],
  horario_por_dia: {
    "1": { e: "07:45", s: "16:45", r: 45 },
    "2": { e: "07:45", s: "16:45", r: 45 },
    "3": { e: "07:45", s: "16:45", r: 45 },
    "4": { e: "07:45", s: "16:45", r: 45 },
    "5": { e: "07:45", s: "16:45", r: 45 },
  },
  almuerzo_min_minutos: 45,
};

const DIANA_VIGENTE: HorarioTramo = {
  ...DIANA_VIEJO,
  vigente_desde: "2026-09-01",
  vigente_hasta: null,
  hora_entrada: "09:00",
  hora_salida: "18:00",
  horario_por_dia: {
    "1": { e: "09:00", s: "18:00", r: 60 },
    "2": { e: "09:00", s: "18:00", r: 60 },
    "3": { e: "09:00", s: "18:00", r: 60 },
    "4": { e: "09:00", s: "18:00", r: 60 },
    "5": { e: "09:00", s: "18:00", r: 60 },
  },
  almuerzo_min_minutos: 60,
};

const TRAMOS_DIANA = [DIANA_VIEJO, DIANA_VIGENTE];

describe("esTurnoEspejoViejo — el caso Diana", () => {
  it("coincide con el tramo YA SUPERADO → probable espejo viejo, avisar", () => {
    const turno: TurnoDia = { hora_entrada: "07:45", hora_salida: "16:45", es_descanso: false };
    // 2026-09-09 es miércoles: para esa fecha el vigente ya es DIANA_VIGENTE,
    // y el turno trae las horas del tramo que dejó de correr en agosto.
    expect(esTurnoEspejoViejo("2026-09-09", turno, TRAMOS_DIANA)).toBe(true);
  });

  it("coincide con el tramo VIGENTE → no hay discrepancia real, no avisar", () => {
    const turno: TurnoDia = { hora_entrada: "09:00", hora_salida: "18:00", es_descanso: false };
    expect(esTurnoEspejoViejo("2026-09-09", turno, TRAMOS_DIANA)).toBe(false);
  });

  it("no coincide con ningún tramo histórico → excepción a propósito, no ruido", () => {
    const turno: TurnoDia = { hora_entrada: "14:00", hora_salida: "21:00", es_descanso: false };
    expect(esTurnoEspejoViejo("2026-09-09", turno, TRAMOS_DIANA)).toBe(false);
  });

  it("un descanso que coincide con el descanso del tramo viejo ese día → avisar", () => {
    const turno: TurnoDia = { hora_entrada: null, hora_salida: null, es_descanso: true };
    // 2026-09-13 es domingo, día ausente de horario_por_dia en los dos tramos,
    // pero lo que importa es que el tramo viejo (no vigente) también descansaba.
    expect(esTurnoEspejoViejo("2026-09-13", turno, TRAMOS_DIANA)).toBe(true);
  });

  it("un descanso que ningún tramo histórico tuvo como descanso ese día → no avisar", () => {
    const turno: TurnoDia = { hora_entrada: null, hora_salida: null, es_descanso: true };
    // 2026-09-09 es miércoles, laborable en el tramo viejo: no hay espejo de descanso.
    expect(esTurnoEspejoViejo("2026-09-09", turno, TRAMOS_DIANA)).toBe(false);
  });
});

// El caso TRU (set-2026): los horarios base de la sede empiezan a regir el
// 2026-07-12, pero el periodo abierto arranca el 2026-06-28. Los turnos de esas
// dos semanas son la ÚNICA referencia de esos días, y el horario del 12 de julio
// se armó copiándolos — así que coinciden con él. Eso no los vuelve viejos: un
// horario que todavía no empezaba no puede haber quedado atrás.
describe("esTurnoEspejoViejo — un horario que aún no empezaba no es viejo", () => {
  const tramoDesdeJulio: HorarioTramo = { ...DIANA_VIEJO, vigente_desde: "2026-07-12", vigente_hasta: null };

  it("sin ningún horario vigente ese día, coincidir con uno POSTERIOR no es espejo", () => {
    const turno: TurnoDia = { hora_entrada: "07:45", hora_salida: "16:45", es_descanso: false };
    // 2026-07-01 es miércoles; el único tramo empieza once días después.
    expect(esTurnoEspejoViejo("2026-07-01", turno, [tramoDesdeJulio])).toBe(false);
  });

  it("con un horario vigente, coincidir con uno que empieza DESPUÉS tampoco es espejo", () => {
    const turno: TurnoDia = { hora_entrada: "09:00", hora_salida: "18:00", es_descanso: false };
    // El 2026-08-26 rige DIANA_VIEJO (07:45); el turno ya trae la hora de
    // DIANA_VIGENTE, que arranca el 1 de septiembre: se adelantó, no se quedó atrás.
    expect(esTurnoEspejoViejo("2026-08-26", turno, TRAMOS_DIANA)).toBe(false);
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

// ----------------------------------------------------------------------------
// HOY, mientras el día no termina. El 2026-09-26 a las 12:03 Desempeño decía
// «Por revisar 6 — marcajes sin cerrar»: eran las seis personas de TRU que
// estaban en su turno. Y a cada una le cargaba ya las horas de hoy en «lo que
// le tocaba» contra cero horas trabajadas. Dos falsos positivos del mismo día.
// ----------------------------------------------------------------------------
describe("esJornadaEnCurso — hoy abierta es trabajar, ayer abierta es un marcaje roto", () => {
  const HOY = "2026-09-26";

  it("hoy, abierta o en pausa: está trabajando", () => {
    expect(esJornadaEnCurso(HOY, HOY, "abierta")).toBe(true);
    expect(esJornadaEnCurso(HOY, HOY, "en_pausa")).toBe(true);
  });

  it("ayer abierta sigue siendo un marcaje sin cerrar: se fue sin marcar la salida", () => {
    expect(esJornadaEnCurso("2026-09-25", HOY, "abierta")).toBe(false);
  });

  it("hoy, pero ya cerrada o cerrada por el sistema: no está en curso", () => {
    expect(esJornadaEnCurso(HOY, HOY, "cerrada")).toBe(false);
    expect(esJornadaEnCurso(HOY, HOY, "auto_cerrada_pendiente")).toBe(false);
    expect(esJornadaEnCurso(HOY, HOY, null)).toBe(false);
  });

  it("estadoDelDia la sigue llamando «revisar»: la excepción la aplica quien pinta, con esta función", () => {
    const j = { horas: null, minutosTarde: 0, estado: "abierta" };
    expect(dia({ fecha: HOY, hoy: HOY, jornada: j })).toBe("revisar");
    expect(esJornadaEnCurso(HOY, HOY, j.estado)).toBe(true);
  });
});

describe("cuentaEnLoQueLeTocaba — hoy entra a la vez que sus horas, no antes", () => {
  const HOY = "2026-09-26";
  const abierta = { horas: null, minutosTarde: 0, estado: "abierta" };
  const cerrada = { horas: 7.5, minutosTarde: 0, estado: "cerrada" };

  it("un día pasado siempre cuenta, haya marcado o no", () => {
    expect(cuentaEnLoQueLeTocaba("2026-09-25", HOY, null)).toBe(true);
    expect(cuentaEnLoQueLeTocaba("2026-09-25", HOY, abierta)).toBe(true);
  });

  it("un día futuro nunca", () => {
    expect(cuentaEnLoQueLeTocaba("2026-09-27", HOY, null)).toBe(false);
  });

  it("hoy, todavía sin marcar o en su jornada: no — el caso de Pamela, «40.4 / 45.0» a mediodía", () => {
    expect(cuentaEnLoQueLeTocaba(HOY, HOY, null)).toBe(false);
    expect(cuentaEnLoQueLeTocaba(HOY, HOY, abierta)).toBe(false);
    expect(cuentaEnLoQueLeTocaba(HOY, HOY, { ...abierta, estado: "en_pausa" })).toBe(false);
  });

  it("hoy, ya cerrada con horas: sí, porque sus horas ya entraron abajo", () => {
    expect(cuentaEnLoQueLeTocaba(HOY, HOY, cerrada)).toBe(true);
  });
});

// ----------------------------------------------------------------------------
// «¿A alguien de esta sede le toca trabajar ese día?» — la misma pregunta que
// esperadoDelDia, un piso más arriba. Nació el 2026-09-20 porque Central tiene
// meta de 1 líder el domingo y el domingo nadie tiene turno, y tres pantallas
// (Dashboard, Incidencias, Hoja de sede) lo respondían cada una a su manera.
// ----------------------------------------------------------------------------
describe("diaDeLaSede — a nadie le toca no es lo mismo que no se sabe", () => {
  const trabaja = { trabaja: true, origen: "horario" } as const;
  const descansaPorHorario = { trabaja: false, origen: "horario" } as const;
  const descansaPorTurno = { trabaja: false, origen: "turno" } as const;
  const sinHorario = { trabaja: false, origen: "sin_horario" } as const;

  it("basta una persona a quien le toque", () => {
    expect(diaDeLaSede([descansaPorHorario, trabaja])).toBe("trabaja");
    expect(diaDeLaSede([sinHorario, trabaja])).toBe("trabaja");
  });

  it("a nadie le toca, con una respuesta real de descanso: «no_trabaja»", () => {
    expect(diaDeLaSede([descansaPorHorario, descansaPorHorario])).toBe("no_trabaja");
    expect(diaDeLaSede([descansaPorTurno])).toBe("no_trabaja");
  });

  it("una sola respuesta real alcanza, aunque otras personas no tengan horario", () => {
    expect(diaDeLaSede([sinHorario, descansaPorHorario])).toBe("no_trabaja");
  });

  it("TODOS sin horario es «sin_horario»: no se sabe, y eso NO autoriza a callar una alarma", () => {
    expect(diaDeLaSede([sinHorario, sinHorario])).toBe("sin_horario");
  });

  it("un equipo vacío no tiene a quién preguntarle: «sin_horario»", () => {
    expect(diaDeLaSede([])).toBe("sin_horario");
  });

  it("la palabra de pantalla es una sola", () => {
    expect(SEDE_SIN_TURNOS).toBe("Sin turnos");
  });
});

describe("diaDeLaSedeDe — desde las personas, sus turnos y sus horarios", () => {
  // Central: dos personas con horario de lunes a sábado. El domingo nadie trabaja.
  const centralLunAsab: HorarioTramo = {
    persona_id: "x", vigente_desde: "2026-01-01", vigente_hasta: null,
    hora_entrada: "09:00", hora_salida: "18:00", dias_laborables: [1, 2, 3, 4, 5, 6],
    horario_por_dia: Object.fromEntries([1, 2, 3, 4, 5, 6].map((d) => [String(d), { e: "09:00", s: "18:00", r: 60 }])),
    almuerzo_min_minutos: 60,
  };
  const tramosDe = (id: string) => (id === "sin" ? [] : [{ ...centralLunAsab, persona_id: id }]);
  const sinTurno = () => null;

  it("Central el domingo 2026-09-20: nadie trabaja, con respuesta real", () => {
    expect(diaDeLaSedeDe(["a", "b"], "2026-09-20", sinTurno, tramosDe)).toBe("no_trabaja");
  });

  it("Central el sábado 2026-09-19: trabaja", () => {
    expect(diaDeLaSedeDe(["a", "b"], "2026-09-19", sinTurno, tramosDe)).toBe("trabaja");
  });

  it("un turno puntual de un domingo por excepción le gana al horario: la sede trabaja", () => {
    const turno = (id: string): TurnoDia | null => (id === "a" ? { hora_entrada: "10:00", hora_salida: "14:00", es_descanso: false } : null);
    expect(diaDeLaSedeDe(["a", "b"], "2026-09-20", turno, tramosDe)).toBe("trabaja");
  });

  it("nadie con horario vigente: «sin_horario», no «no_trabaja»", () => {
    expect(diaDeLaSedeDe(["sin"], "2026-09-20", sinTurno, tramosDe)).toBe("sin_horario");
  });

  it("un horario vencido ayer cuenta como sin horario hoy", () => {
    const vencido = (id: string) => [{ ...centralLunAsab, persona_id: id, vigente_hasta: "2026-09-19" }];
    expect(diaDeLaSedeDe(["a"], "2026-09-21", sinTurno, vencido)).toBe("sin_horario");
  });
});

// ----------------------------------------------------------------------------
// FERIADOS (2026-09-20). `fn_faltas` no cuenta falta un feriado sin turno
// explícito (0051, 0070, 0414), pero la base SÍ mide tardanza y horas contra el
// horario base ese día (fn_recalcular_jornada, 0446; decisión de Felipe del
// 2026-08-18: 22 de 25 feriados trabajados no tenían ni un turno). Son dos
// preguntas: «¿qué le tocaba?» y «¿se le puede exigir?».
// ----------------------------------------------------------------------------
describe("esperadoDelDia NO sabe de feriados, a propósito", () => {
  // 2026-07-28 = martes y Fiestas Patrias (tabla `feriados`, migración 0024).
  // 2026-07-21 = martes normal.
  const FERIADO = "2026-07-28";
  const NORMAL = "2026-07-21";

  it("un feriado de horario base «trabaja» contesta EXACTAMENTE lo mismo que un martes normal", () => {
    // Si esto falla porque alguien enseñó feriados a la cascada, leer el encabezado de
    // jornada-esperada.ts antes de tocar la prueba: la base mide tardanza y horas contra
    // el horario base también en feriado, y la cascada tiene que decir lo mismo que ella.
    expect(esperadoDelDia(FERIADO, null, AQP)).toEqual(esperadoDelDia(NORMAL, null, AQP));
    expect(esperadoDelDia(FERIADO, null, AQP).trabaja).toBe(true);
  });

  it("quien SÍ vino un feriado sin turno es «ok», no «extra» — y lo sería si la cascada dijera «no trabaja»", () => {
    const vino = { horas: 9, minutosTarde: 0, estado: "cerrada" };
    const base = { fecha: FERIADO, hoy: "2026-07-29", jornada: vino, falta: null, tardanzaJustificada: false, agregado: false };
    expect(estadoDelDia({ ...base, esperado: esperadoDelDia(FERIADO, null, AQP) })).toBe("ok");
    // El estado que saldría en Horas y Mío si se hiciera el «arreglo» en la cascada:
    const siFueraDescanso: Esperado = { trabaja: false, entrada: null, salida: null, horas: 0, origen: "horario" };
    expect(estadoDelDia({ ...base, esperado: siFueraDescanso })).toBe("extra");
  });

  it("quien NO vino ya sale «sin_marca» y no «falta»: la falta viene de fn_faltas, que sí conoce el feriado", () => {
    const base = { fecha: FERIADO, hoy: "2026-07-29", jornada: null, falta: null, tardanzaJustificada: false, agregado: false };
    expect(estadoDelDia({ ...base, esperado: esperadoDelDia(FERIADO, null, AQP) })).toBe("sin_marca");
  });
});

describe("esFeriadoSinTurno — el gemelo de la cláusula de fn_faltas", () => {
  it("feriado y ningún turno puntual (manda el horario base): sí", () => {
    expect(esFeriadoSinTurno(true, { origen: "horario" })).toBe(true);
    expect(esFeriadoSinTurno(true, { origen: "legacy" })).toBe(true);
  });

  it("feriado con un turno puntual, de trabajo o de descanso: no — el turno explícito es lo que la base pide", () => {
    expect(esFeriadoSinTurno(true, { origen: "turno" })).toBe(false);
  });

  it("un día que no es feriado nunca lo es, tenga o no turno", () => {
    for (const origen of ["turno", "horario", "legacy", "sin_horario"] as const) {
      expect(esFeriadoSinTurno(false, { origen })).toBe(false);
    }
  });
});

describe("diaDeLaSede en feriado — «no se sabe si abre» es una respuesta, no un silencio ni una acusación", () => {
  const porHorarioEnFeriado = { trabaja: true, origen: "horario", feriadoSinTurno: true } as const;
  const conTurno = { trabaja: true, origen: "turno", feriadoSinTurno: false } as const;
  const descansa = { trabaja: false, origen: "horario", feriadoSinTurno: true } as const;
  const sinHorario = { trabaja: false, origen: "sin_horario", feriadoSinTurno: true } as const;

  it("a todos les tocaría solo por su horario base: «feriado_sin_confirmar»", () => {
    expect(diaDeLaSede([porHorarioEnFeriado, porHorarioEnFeriado])).toBe("feriado_sin_confirmar");
  });

  it("un turno explícito de UNA persona prueba que la sede abre: «trabaja», y el rojo de siempre", () => {
    expect(diaDeLaSede([porHorarioEnFeriado, conTurno])).toBe("trabaja");
    expect(diaDeLaSede([conTurno, porHorarioEnFeriado])).toBe("trabaja"); // el orden no importa
  });

  it("gana a «no_trabaja»: si alguien tiene horario ese día y otros descansan, no se afirma que la sede no abre", () => {
    expect(diaDeLaSede([descansa, porHorarioEnFeriado])).toBe("feriado_sin_confirmar");
  });

  it("si a NADIE le tocaría, el feriado no inventa una pregunta: sigue «no_trabaja» o «sin_horario»", () => {
    expect(diaDeLaSede([descansa, descansa])).toBe("no_trabaja");
    expect(diaDeLaSede([sinHorario, sinHorario])).toBe("sin_horario");
  });

  it("SIN la bandera la respuesta es la de siempre: quien no la pasa, o no pudo saber si es feriado, no cambia", () => {
    expect(diaDeLaSede([{ trabaja: true, origen: "horario" }])).toBe("trabaja");
    expect(diaDeLaSede([{ trabaja: true, origen: "horario", feriadoSinTurno: false }])).toBe("trabaja");
  });
});

describe("diaDeLaSedeDe con esFeriado — el martes de Fiestas Patrias en una sede de lunes a sábado", () => {
  const lunAsab: HorarioTramo = {
    persona_id: "x", vigente_desde: "2026-01-01", vigente_hasta: null,
    hora_entrada: "09:00", hora_salida: "18:00", dias_laborables: [1, 2, 3, 4, 5, 6],
    horario_por_dia: Object.fromEntries([1, 2, 3, 4, 5, 6].map((d) => [String(d), { e: "09:00", s: "18:00", r: 60 }])),
    almuerzo_min_minutos: 60,
  };
  const tramosDe = (id: string) => [{ ...lunAsab, persona_id: id }];
  const sinTurno = () => null;
  const FERIADO = "2026-07-28";

  it("feriado y nadie con turno: «feriado_sin_confirmar»", () => {
    expect(diaDeLaSedeDe(["a", "b"], FERIADO, sinTurno, tramosDe, true)).toBe("feriado_sin_confirmar");
  });

  it("el mismo día sin decir que es feriado (Turnos, o la consulta falló): «trabaja», como antes", () => {
    expect(diaDeLaSedeDe(["a", "b"], FERIADO, sinTurno, tramosDe)).toBe("trabaja");
    expect(diaDeLaSedeDe(["a", "b"], FERIADO, sinTurno, tramosDe, false)).toBe("trabaja");
  });

  it("feriado con el turno de UNA persona armado: «trabaja»", () => {
    const turno = (id: string): TurnoDia | null => (id === "a" ? { hora_entrada: "10:00", hora_salida: "14:00", es_descanso: false } : null);
    expect(diaDeLaSedeDe(["a", "b"], FERIADO, turno, tramosDe, true)).toBe("trabaja");
  });

  it("un turno de DESCANSO también es un turno explícito, pero no prueba que la sede abra: sigue la pregunta si otra persona tiene horario", () => {
    const descanso = (id: string): TurnoDia | null => (id === "a" ? { hora_entrada: null, hora_salida: null, es_descanso: true } : null);
    expect(diaDeLaSedeDe(["a", "b"], FERIADO, descanso, tramosDe, true)).toBe("feriado_sin_confirmar");
  });

  it("un feriado en domingo, en una sede que no abre domingos: nadie trabajaría por horario, así que no hay nada que preguntar", () => {
    expect(diaDeLaSedeDe(["a", "b"], "2026-11-01", sinTurno, tramosDe, true)).toBe("no_trabaja");
  });
});
