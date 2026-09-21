// ============================================================================
// cobertura-hoja-sede.test.ts — cuándo la Hoja de sede NO mide la cobertura de hoy
// ============================================================================
// El caso que la originó (2026-09-20): Central tiene meta de 1 líder el domingo y
// el domingo nadie de Central tiene turno, así que la hoja IMPRESA decía
// «Líderes en piso 0 / meta 1 · faltan 1» en rojo. Una falta que ninguna
// asistencia podía arreglar, escrita en un papel que se firma.
//
// Lo que se defiende acá es lo contrario de lo que parece: no que la hoja calle,
// sino que solo calle con una respuesta REAL de que hoy nadie trabaja. Si todos
// están «sin horario», si alguien ya marcó o si el rango no llega a hoy, la línea
// queda como estaba — un «no sé» no autoriza a apagar una alarma.
// ============================================================================
import { describe, expect, it } from "vitest";
import {
  diaDeLaSedeDe,
  type DiaDeLaSede,
  type HorarioTramo,
  type TurnoDia,
} from "@/lib/admin/jornada-esperada";
import { coberturaDeHoyApagada, hojaIncluyeHoy, textoCoberturaApagada, textoMetaDeHoy } from "@/lib/admin/cobertura-hoja-sede";

const SIN_MARCAR = "sin_marcar";
const apagada = (dia: DiaDeLaSede | null, estadosHoy: string[], rangoIncluyeHoy = true) =>
  coberturaDeHoyApagada({ dia, estadosHoy, rangoIncluyeHoy });

describe("coberturaDeHoyApagada — solo con una respuesta real y sin nadie marcado", () => {
  it("no_trabaja y nadie marcó → apagada (Central un domingo)", () => {
    expect(apagada("no_trabaja", [SIN_MARCAR, SIN_MARCAR, SIN_MARCAR])).toBe(true);
  });

  it("no_trabaja pero alguien ya marcó → NO: quien viene en su día libre hizo abrir la sede", () => {
    // La meta vuelve a medirse: con una meta de 2 y una sola persona, «faltan» sí es cierto.
    expect(apagada("no_trabaja", [SIN_MARCAR, "abierta"])).toBe(false);
    expect(apagada("no_trabaja", [SIN_MARCAR, "en_pausa"])).toBe(false);
    expect(apagada("no_trabaja", ["cerrada", SIN_MARCAR])).toBe(false);
  });

  it("cualquier estado con jornada iniciada cuenta como «alguien marcó»", () => {
    for (const estado of ["abierta", "en_pausa", "cerrada", "auto_cerrada_pendiente", "revisada"]) {
      expect(apagada("no_trabaja", [SIN_MARCAR, estado]), estado).toBe(false);
    }
  });

  it("trabaja → NO se apaga nunca, marque o no marque alguien", () => {
    expect(apagada("trabaja", [SIN_MARCAR, SIN_MARCAR])).toBe(false);
    expect(apagada("trabaja", ["abierta", SIN_MARCAR])).toBe(false);
  });

  it("sin_horario → NO: «nadie tiene horario» no es «hoy no abre», es «no se sabe»", () => {
    // Un tramo venció sin sucesor, una sede nueva. La alarma sigue como estaba.
    expect(apagada("sin_horario", [SIN_MARCAR, SIN_MARCAR])).toBe(false);
  });

  it("no se pudo preguntar (null: falló la consulta de turnos u horarios) → NO", () => {
    expect(apagada(null, [SIN_MARCAR, SIN_MARCAR])).toBe(false);
  });

  it("un equipo vacío nunca la apaga: «nadie marcó» dicho de nadie no afirma nada", () => {
    expect(apagada("no_trabaja", [])).toBe(false);
  });

  it("si el rango de la hoja no llega a hoy NO se apaga: las jornadas de hoy nunca se trajeron", () => {
    // Una hoja de un periodo cerrado llega con todos «sin_marcar» aunque hoy haya
    // trabajado alguien: ese cero no es un dato, es una consulta que no incluía hoy.
    expect(apagada("no_trabaja", [SIN_MARCAR, SIN_MARCAR], false)).toBe(false);
  });
});

describe("hojaIncluyeHoy — el rango elegido llega a hoy", () => {
  it("el rango por defecto (del primero del mes a hoy) sí", () => {
    expect(hojaIncluyeHoy("2026-09-01", "2026-09-20", "2026-09-20")).toBe(true);
  });

  it("un solo día, hoy, sí", () => {
    expect(hojaIncluyeHoy("2026-09-20", "2026-09-20", "2026-09-20")).toBe(true);
  });

  it("un periodo cerrado, no", () => {
    expect(hojaIncluyeHoy("2026-08-29", "2026-09-28", "2026-10-02")).toBe(false);
  });

  it("un rango que empieza mañana, no", () => {
    expect(hojaIncluyeHoy("2026-09-21", "2026-09-25", "2026-09-20")).toBe(false);
  });
});

describe("de punta a punta — Central, con sus turnos y horarios de verdad", () => {
  // Central trabaja de lunes a sábado; el domingo es opcional y nadie tiene turno.
  const centralLunAsab: HorarioTramo = {
    persona_id: "x", vigente_desde: "2026-01-01", vigente_hasta: null,
    hora_entrada: "09:00", hora_salida: "18:00", dias_laborables: [1, 2, 3, 4, 5, 6],
    horario_por_dia: Object.fromEntries([1, 2, 3, 4, 5, 6].map((d) => [String(d), { e: "09:00", s: "18:00", r: 60 }])),
    almuerzo_min_minutos: 60,
  };
  const equipo = ["a", "b", "c"];
  const tramosDe = (id: string) => [{ ...centralLunAsab, persona_id: id }];
  const sinTurno = () => null;
  const nadieMarco = equipo.map(() => SIN_MARCAR);

  it("el domingo 2026-09-20, sin turnos, nadie marcado → «Sin turnos», no «faltan 1»", () => {
    const dia = diaDeLaSedeDe(equipo, "2026-09-20", sinTurno, tramosDe);
    expect(dia).toBe("no_trabaja");
    expect(apagada(dia, nadieMarco)).toBe(true);
  });

  it("el sábado 2026-09-19 la sede trabaja: la línea se pinta como siempre", () => {
    const dia = diaDeLaSedeDe(equipo, "2026-09-19", sinTurno, tramosDe);
    expect(dia).toBe("trabaja");
    expect(apagada(dia, nadieMarco)).toBe(false);
  });

  it("un domingo con un turno puntual armado: la sede trabaja y la meta se mide", () => {
    const turno = (id: string): TurnoDia | null => (id === "a" ? { hora_entrada: "10:00", hora_salida: "14:00", es_descanso: false } : null);
    const dia = diaDeLaSedeDe(equipo, "2026-09-20", turno, tramosDe);
    expect(dia).toBe("trabaja");
    expect(apagada(dia, nadieMarco)).toBe(false);
  });

  it("un domingo con turnos de DESCANSO explícitos: también es una respuesta real", () => {
    const descanso = (): TurnoDia => ({ hora_entrada: null, hora_salida: null, es_descanso: true });
    const dia = diaDeLaSedeDe(equipo, "2026-09-20", descanso, () => []);
    expect(dia).toBe("no_trabaja");
    expect(apagada(dia, nadieMarco)).toBe(true);
  });

  it("el domingo con TODO el equipo sin horario vigente: no se apaga, no se sabe", () => {
    const dia = diaDeLaSedeDe(equipo, "2026-09-20", sinTurno, () => []);
    expect(dia).toBe("sin_horario");
    expect(apagada(dia, nadieMarco)).toBe(false);
  });

  it("el domingo con UNA persona con horario que descansa y las demás sin horario: sí es una respuesta real", () => {
    // Basta una respuesta real de descanso; las demás no la contradicen.
    const dia = diaDeLaSedeDe(equipo, "2026-09-20", sinTurno, (id) => (id === "a" ? [{ ...centralLunAsab, persona_id: id }] : []));
    expect(dia).toBe("no_trabaja");
    expect(apagada(dia, nadieMarco)).toBe(true);
  });
});

describe("textoMetaDeHoy — la meta que acompaña al «Sin turnos»", () => {
  it("Central: meta de 1 líder → «Meta de hoy: 1 líder.»", () => {
    expect(textoMetaDeHoy(0, 0, 1)).toBe("Meta de hoy: 1 líder.");
  });

  it("concuerda en singular y plural, y junta operativas con líderes", () => {
    expect(textoMetaDeHoy(1, 1, 0)).toBe("Meta de hoy: 1 operativa.");
    expect(textoMetaDeHoy(4, 4, 2)).toBe("Meta de hoy: 4 operativas y 2 líderes.");
  });

  it("de operativas toma la más alta de mañana y tarde: la de una sede que solo abre por la tarde no se pierde", () => {
    expect(textoMetaDeHoy(0, 3, 0)).toBe("Meta de hoy: 3 operativas.");
    expect(textoMetaDeHoy(2, 3, 0)).toBe("Meta de hoy: 3 operativas.");
  });

  it("sin meta hoy → null: no hay nada que nombrar", () => {
    expect(textoMetaDeHoy(0, 0, 0)).toBeNull();
  });

  it("usa el vocabulario de la casa: líder, nunca encargada ni jefe", () => {
    const t = textoMetaDeHoy(2, 2, 1) ?? "";
    expect(t).not.toMatch(/encargad|jefe|supervisor/i);
  });
});

// ----------------------------------------------------------------------------
// FERIADOS (2026-09-20). La hoja se IMPRIME y se firma: un feriado sin turnos y sin
// nadie marcado no puede quedar escrito como «faltan 1» en rojo, cuando no se sabe si
// la sede abre. Pero tampoco puede decir «a nadie le tocaba»: por su horario les
// tocaría, y esa es una afirmación falsa en un papel.
// ----------------------------------------------------------------------------
describe("coberturaDeHoyApagada — un feriado sin turnos", () => {
  it("feriado_sin_confirmar y nadie marcó → apagada", () => {
    expect(apagada("feriado_sin_confirmar", [SIN_MARCAR, SIN_MARCAR])).toBe(true);
  });

  it("apenas alguien marca la sede abrió: la meta vuelve a medirse, igual que con «no_trabaja»", () => {
    expect(apagada("feriado_sin_confirmar", [SIN_MARCAR, "abierta"])).toBe(false);
    expect(apagada("feriado_sin_confirmar", ["cerrada", SIN_MARCAR])).toBe(false);
  });

  it("si el rango no llega a hoy, «nadie marcó» sería un cero inventado: no se apaga", () => {
    expect(apagada("feriado_sin_confirmar", [SIN_MARCAR], false)).toBe(false);
  });

  it("un equipo vacío no la apaga", () => {
    expect(apagada("feriado_sin_confirmar", [])).toBe(false);
  });

  it("«trabaja» y «sin_horario» siguen sin apagarla: un feriado no relaja lo que ya estaba cerrado a propósito", () => {
    expect(apagada("trabaja", [SIN_MARCAR])).toBe(false);
    expect(apagada("sin_horario", [SIN_MARCAR])).toBe(false);
    expect(apagada(null, [SIN_MARCAR])).toBe(false);
  });
});

describe("textoCoberturaApagada — lo que queda escrito en el papel", () => {
  it("un día en que a nadie le tocaba trabajar dice lo de siempre", () => {
    expect(textoCoberturaApagada("no_trabaja")).toEqual({
      titulo: "Sin turnos",
      detalle: "Hoy a nadie del equipo le tocaba trabajar.",
    });
  });

  it("un feriado sin turnos NO afirma que a nadie le tocaba: dice lo que no se sabe", () => {
    const t = textoCoberturaApagada("feriado_sin_confirmar");
    expect(t.titulo).toBe("Feriado");
    expect(t.detalle).toContain("no se sabe si la sede abre");
    expect(t.detalle).not.toMatch(/a nadie/i);
  });
});

describe("Hoja de sede — de punta a punta, con el martes de Fiestas Patrias", () => {
  const lunAsab: HorarioTramo = {
    persona_id: "x", vigente_desde: "2026-01-01", vigente_hasta: null,
    hora_entrada: "09:00", hora_salida: "18:00", dias_laborables: [1, 2, 3, 4, 5, 6],
    horario_por_dia: Object.fromEntries([1, 2, 3, 4, 5, 6].map((d) => [String(d), { e: "09:00", s: "18:00", r: 60 }])),
    almuerzo_min_minutos: 60,
  };
  const tramosDe = (id: string) => [{ ...lunAsab, persona_id: id }];
  const sinTurno = () => null;

  it("feriado, sin turnos, nadie marcó: la línea se apaga con la palabra «Feriado»", () => {
    const dia = diaDeLaSedeDe(["a", "b"], "2026-07-28", sinTurno, tramosDe, true);
    expect(apagada(dia, [SIN_MARCAR, SIN_MARCAR])).toBe(true);
    expect(textoCoberturaApagada(dia).titulo).toBe("Feriado");
  });

  it("el mismo día sin saber que es feriado (falló la consulta): la línea se imprime como antes", () => {
    const dia = diaDeLaSedeDe(["a", "b"], "2026-07-28", sinTurno, tramosDe);
    expect(apagada(dia, [SIN_MARCAR, SIN_MARCAR])).toBe(false);
  });

  it("feriado con turnos armados: la línea se imprime, con su «faltan» si toca", () => {
    const turno = (id: string): TurnoDia | null => (id === "a" ? { hora_entrada: "10:00", hora_salida: "14:00", es_descanso: false } : null);
    const dia = diaDeLaSedeDe(["a", "b"], "2026-07-28", turno, tramosDe, true);
    expect(apagada(dia, [SIN_MARCAR, SIN_MARCAR])).toBe(false);
  });
});
