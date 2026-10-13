// ============================================================================
// marcaje-faltante.test.ts — con qué arranca «Agregar un marcaje faltante»
// ============================================================================
// Lo que hay que defender no es la comodidad, es el clic sin mirar: si alguien
// aprieta «Agregar» sin tocar nada, lo que quede registrado tiene que ser el
// error barato. Por eso la hora sale del horario (puntual, nunca tardía) y por
// eso no se propone una marca que todavía no puede haber pasado — una salida
// final propuesta a quien sigue en la tienda le cerraría el día en el terminal.
// ============================================================================
import { describe, expect, it } from "vitest";
import type { MarcajeDelDia } from "@cayla-dynamic/shared";
import type { Esperado } from "@/lib/admin/jornada-esperada";
import { horaDelHorario, tipoQueFalta, type Momento } from "@/lib/admin/marcaje-faltante";

// Un día de tienda AQP: 09:00 a 19:00.
const AQP: Esperado = { trabaja: true, entrada: "09:00", salida: "19:00", horas: 9, origen: "horario" };
// Personal de dirección: no lleva horario, a propósito.
const SIN_HORARIO: Esperado = { trabaja: false, entrada: null, salida: null, horas: 0, origen: "sin_horario" };
const DESCANSO: Esperado = { trabaja: false, entrada: null, salida: null, horas: 0, origen: "turno" };

const AYER: Momento = { fecha: "2026-10-12", hoy: "2026-10-13", ahora: "11:00" };
const hoyALas = (ahora: string): Momento => ({ fecha: "2026-10-13", hoy: "2026-10-13", ahora });
const MANANA: Momento = { fecha: "2026-10-14", hoy: "2026-10-13", ahora: "11:00" };

const marca = (tipo: MarcajeDelDia["tipo"], hhmm: string, fecha = "2026-10-12"): MarcajeDelDia =>
  ({ tipo, timestamp: `${fecha}T${hhmm}:00-05:00` });

describe("un día que ya pasó", () => {
  it("sin ninguna marca propone la entrada, a la hora de su horario", () => {
    const tipo = tipoQueFalta([], AQP, AYER);
    expect(tipo).toBe("entrada");
    expect(horaDelHorario(tipo!, AQP, AYER)).toBe("09:00");
  });

  it("con entrada y sin salida propone la salida final, a la hora de su horario", () => {
    const tipo = tipoQueFalta([marca("entrada", "09:02")], AQP, AYER);
    expect(tipo).toBe("salida_final");
    expect(horaDelHorario(tipo!, AQP, AYER)).toBe("19:00");
  });

  it("sin horario también propone la salida final, pero no inventa la hora", () => {
    const tipo = tipoQueFalta([marca("entrada", "08:00")], SIN_HORARIO, AYER);
    expect(tipo).toBe("salida_final");
    expect(horaDelHorario(tipo!, SIN_HORARIO, AYER)).toBeNull();
  });

  it("con un refrigerio sin volver propone su retorno, y el horario no fija esa hora", () => {
    const tipo = tipoQueFalta([marca("entrada", "09:00"), marca("salida_almuerzo", "13:00")], AQP, AYER);
    expect(tipo).toBe("retorno_almuerzo");
    expect(horaDelHorario(tipo!, AQP, AYER)).toBeNull();
  });

  it("un día cerrado no propone nada: no falta ninguna marca", () => {
    expect(tipoQueFalta([marca("entrada", "09:00"), marca("salida_final", "19:00")], AQP, AYER)).toBeNull();
  });

  it("un día de descanso no tiene hora que proponer", () => {
    expect(horaDelHorario("entrada", DESCANSO, AYER)).toBeNull();
    expect(horaDelHorario("salida_final", DESCANSO, AYER)).toBeNull();
  });
});

describe("hoy: nunca se propone lo que todavía no pudo pasar", () => {
  const entroHoy = [marca("entrada", "09:00", "2026-10-13")];

  it("a media mañana, quien entró sigue trabajando: no se le propone la salida final", () => {
    expect(tipoQueFalta(entroHoy, AQP, hoyALas("11:00"))).toBeNull();
    expect(horaDelHorario("salida_final", AQP, hoyALas("11:00"))).toBeNull();
  });

  it("pasada su hora de salida, sí", () => {
    const tipo = tipoQueFalta(entroHoy, AQP, hoyALas("19:30"));
    expect(tipo).toBe("salida_final");
    expect(horaDelHorario(tipo!, AQP, hoyALas("19:30"))).toBe("19:00");
  });

  it("justo a su hora de salida cuenta como pasada", () => {
    expect(tipoQueFalta(entroHoy, AQP, hoyALas("19:00"))).toBe("salida_final");
  });

  it("sin horario, hoy no se puede saber si olvidó marcar o sigue trabajando: no se propone", () => {
    expect(tipoQueFalta([marca("entrada", "08:00", "2026-10-13")], SIN_HORARIO, hoyALas("16:00"))).toBeNull();
  });

  it("antes de su hora de entrada se propone la entrada, pero sin esa hora futura", () => {
    expect(tipoQueFalta([], AQP, hoyALas("08:30"))).toBe("entrada");
    expect(horaDelHorario("entrada", AQP, hoyALas("08:30"))).toBeNull();
    expect(horaDelHorario("entrada", AQP, hoyALas("09:15"))).toBe("09:00");
  });
});

describe("un día que todavía no llega", () => {
  it("no tiene ni hora ni salida que proponer", () => {
    expect(horaDelHorario("entrada", AQP, MANANA)).toBeNull();
    expect(tipoQueFalta([marca("entrada", "09:00", "2026-10-14")], AQP, MANANA)).toBeNull();
  });
});
