// ============================================================================
// presencia-casilla.test.ts — lo que dice la casilla de cada persona
// ============================================================================
// `presenciaDeLaCasilla` convierte el estado del día (derivado de las marcas) y
// el horario de hoy en la línea que se lee bajo el nombre. Se prueba con la hora
// fija: sin reloj real, un «hace 25 min» no podría comprobarse.
//
// Las dos reglas que más importan son de NO acusar:
//   · pasada la hora de entrada, la casilla no dice «debía entrar»;
//   · «Libre hoy» solo se dice cuando el horario o un turno lo AFIRMAN, nunca
//     porque falte un horario.
// ============================================================================
import { describe, it, expect } from "vitest";
import type { MarcajeDelDia, TipoMarca } from "@cayla-dynamic/shared";
import { ORDEN_PRESENCIA, contarPresencias, horaDecimalDeHHMM, presenciaDeLaCasilla } from "@/lib/terminal/presencia";

const lima = (hora: string) => `2026-10-05T${hora}:00-05:00`;
const m = (tipo: TipoMarca, hora: string): MarcajeDelDia => ({ tipo, timestamp: lima(hora) });
const a = (hora: string) => new Date(lima(hora));

describe("sin ninguna marca", () => {
  it("sin horario conocido: «aún sin entrada», sin inventar nada", () => {
    expect(presenciaDeLaCasilla([], undefined, a("10:00"))).toEqual({ clave: "sin_entrada", detalle: "aún sin entrada" });
  });

  it("si le toca entrar más tarde, lo dice: «entra 14:00»", () => {
    const r = presenciaDeLaCasilla([], { entradaEsperada: "14:00", libreHoy: false }, a("10:00"));
    expect(r).toEqual({ clave: "sin_entrada", detalle: "entra 14:00" });
  });

  it("quita los segundos de una hora que llega como «14:00:00»", () => {
    const r = presenciaDeLaCasilla([], { entradaEsperada: "14:00:00", libreHoy: false }, a("10:00"));
    expect(r.detalle).toBe("entra 14:00");
  });

  it("PASADA su hora de entrada NO dice «debía entrar»: se ve igual que antes de tener horario", () => {
    const r = presenciaDeLaCasilla([], { entradaEsperada: "08:00", libreHoy: false }, a("09:30"));
    expect(r).toEqual({ clave: "sin_entrada", detalle: "aún sin entrada" });
    expect(r.detalle).not.toMatch(/deb[íi]a|tarde|falt/i);
  });

  it("justo a su hora ya no es futuro: tampoco acusa", () => {
    const r = presenciaDeLaCasilla([], { entradaEsperada: "14:00", libreHoy: false }, a("14:00"));
    expect(r.detalle).toBe("aún sin entrada");
  });

  it("si su horario dice que hoy descansa: «libre hoy», con su propia clave", () => {
    const r = presenciaDeLaCasilla([], { entradaEsperada: null, libreHoy: true }, a("10:00"));
    expect(r).toEqual({ clave: "libre", detalle: "día de descanso" });
  });

  it("si NO hay horario, nunca se afirma que está de descanso", () => {
    const r = presenciaDeLaCasilla([], { entradaEsperada: null, libreHoy: false }, a("10:00"));
    expect(r.clave).toBe("sin_entrada");
  });

  it("si vino un día que no le tocaba, manda lo que marcó, no el horario", () => {
    const r = presenciaDeLaCasilla([m("entrada", "09:00")], { entradaEsperada: null, libreHoy: true }, a("10:00"));
    expect(r.clave).toBe("laborando");
  });
});

describe("con marcas", () => {
  it("laborando: la hora a la que entró, sin segunda línea", () => {
    expect(presenciaDeLaCasilla([m("entrada", "08:02")], undefined, a("10:00"))).toEqual({
      clave: "laborando",
      detalle: "entró 08:02",
    });
  });

  it("laborando tras un regreso: SIGUE diciendo la entrada de la mañana, y el regreso va aparte", () => {
    const marcas = [m("entrada", "08:00"), m("salida_almuerzo", "13:00"), m("retorno_almuerzo", "13:45")];
    const r = presenciaDeLaCasilla(marcas, undefined, a("15:00"));
    // La segunda línea dice de cuándo a cuándo estuvo fuera, no solo cuándo volvió.
    expect(r).toEqual({ clave: "laborando", detalle: "entró 08:00", detalle2: "salió 13:00 · volvió 13:45" });
  });

  it("con varias salidas, la segunda línea habla de la ÚLTIMA", () => {
    const marcas = [
      m("entrada", "08:00"),
      m("salida_almuerzo", "12:00"),
      m("retorno_almuerzo", "13:00"),
      m("salida_tramite", "15:30"),
      m("retorno_tramite", "16:10"),
    ];
    expect(presenciaDeLaCasilla(marcas, undefined, a("17:00")).detalle2).toBe("salió 15:30 · volvió 16:10");
  });

  it("si faltara la salida, dice solo el regreso en vez de inventarla", () => {
    const marcas = [m("entrada", "08:00"), m("retorno_almuerzo", "13:45")];
    expect(presenciaDeLaCasilla(marcas, undefined, a("15:00")).detalle2).toBe("volvió 13:45");
  });

  it("nunca dice «desde» con la hora del regreso: se leería como una llegada tardía", () => {
    const marcas = [m("entrada", "08:00"), m("salida_almuerzo", "13:00"), m("retorno_almuerzo", "13:45")];
    const r = presenciaDeLaCasilla(marcas, undefined, a("15:00"));
    expect(`${r.detalle} ${r.detalle2}`).not.toMatch(/desde/);
  });

  it("en refrigerio: cuánto lleva fuera", () => {
    const marcas = [m("entrada", "08:00"), m("salida_almuerzo", "13:00")];
    expect(presenciaDeLaCasilla(marcas, undefined, a("13:25"))).toEqual({
      clave: "refrigerio",
      detalle: "salió hace 25 min",
    });
  });

  it("en refrigerio, recién salida: «recién salió», no «hace 0 min»", () => {
    const marcas = [m("entrada", "08:00"), m("salida_almuerzo", "13:00")];
    expect(presenciaDeLaCasilla(marcas, undefined, a("13:00")).detalle).toBe("recién salió");
  });

  it("si el reloj de esta Mac va atrás de la marca, tampoco sale un número negativo", () => {
    const marcas = [m("entrada", "08:00"), m("salida_almuerzo", "13:00")];
    expect(presenciaDeLaCasilla(marcas, undefined, new Date(lima("12:59"))).detalle).toBe("recién salió");
  });

  it("más de una hora fuera se dice en horas: «1 h 15 min», «2 h»", () => {
    const marcas = [m("entrada", "08:00"), m("salida_almuerzo", "13:00")];
    expect(presenciaDeLaCasilla(marcas, undefined, a("14:15")).detalle).toBe("salió hace 1 h 15 min");
    expect(presenciaDeLaCasilla(marcas, undefined, a("15:00")).detalle).toBe("salió hace 2 h");
  });

  it("en pausa: el motivo y la hora", () => {
    const marcas = [m("entrada", "08:00"), m("salida_tramite", "14:08")];
    expect(presenciaDeLaCasilla(marcas, undefined, a("14:30"))).toEqual({
      clave: "pausa",
      detalle: "Trámite · 14:08",
    });
  });

  it.each([
    ["salida_personal", "Personal"],
    ["salida_medico", "Médico"],
    ["salida_otro", "Otro motivo"],
  ] as const)("en pausa por %s dice «%s»", (tipo, motivo) => {
    const r = presenciaDeLaCasilla([m("entrada", "08:00"), m(tipo, "11:00")], undefined, a("11:10"));
    expect(r.detalle).toBe(`${motivo} · 11:00`);
  });

  it("turno terminado: la hora de la salida", () => {
    const marcas = [m("entrada", "08:00"), m("salida_final", "14:33")];
    expect(presenciaDeLaCasilla(marcas, undefined, a("15:00"))).toEqual({
      clave: "termino",
      detalle: "salió a las 14:33",
    });
  });

  it("las horas son las de Lima aunque el instante venga en UTC", () => {
    const e: MarcajeDelDia = { tipo: "entrada", timestamp: "2026-10-05T13:02:00Z" }; // 08:02 en Lima
    expect(presenciaDeLaCasilla([e], undefined, new Date("2026-10-05T15:00:00Z")).detalle).toBe("entró 08:02");
  });
});

describe("horaDecimalDeHHMM", () => {
  it.each([
    ["14:00", 14],
    ["08:30", 8.5],
    ["14:15:00", 14.25],
  ])("%s → %s", (hhmm, esperado) => {
    expect(horaDecimalDeHHMM(hhmm)).toBeCloseTo(esperado);
  });
});

describe("contarPresencias y el orden de la píldora", () => {
  const hecha = (clave: "laborando" | "refrigerio" | "pausa" | "termino" | "sin_entrada" | "libre") => ({
    clave,
    detalle: "x",
  });

  it("cuenta a cada persona en su estado, y los que no tiene en cero", () => {
    const c = contarPresencias([hecha("laborando"), hecha("laborando"), hecha("refrigerio"), hecha("libre")]);
    expect(c).toEqual({ laborando: 2, refrigerio: 1, pausa: 0, termino: 0, sin_entrada: 0, libre: 1 });
  });

  it("sin gente, todo en cero", () => {
    expect(Object.values(contarPresencias([])).every((n) => n === 0)).toBe(true);
  });

  it("el orden incluye cada estado una sola vez, y «libre» es el último", () => {
    expect([...ORDEN_PRESENCIA].sort()).toEqual(["laborando", "libre", "pausa", "refrigerio", "sin_entrada", "termino"]);
    expect(ORDEN_PRESENCIA[ORDEN_PRESENCIA.length - 1]).toBe("libre");
  });

  it("lo que cuenta es lo que `presenciaDeLaCasilla` produce de verdad", () => {
    const ahora = a("15:00");
    const gente = [
      presenciaDeLaCasilla([m("entrada", "08:00")], undefined, ahora),
      presenciaDeLaCasilla([m("entrada", "08:00"), m("salida_almuerzo", "14:50")], undefined, ahora),
      presenciaDeLaCasilla([], { entradaEsperada: null, libreHoy: true }, ahora),
    ];
    expect(contarPresencias(gente)).toMatchObject({ laborando: 1, refrigerio: 1, libre: 1, sin_entrada: 0 });
  });
});
