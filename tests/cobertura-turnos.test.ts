// ============================================================================
// cobertura-turnos.test.ts — lo que Turnos le dice a quien arma la semana
// ============================================================================
// El caso que las originó (2026-09-18): Oficina TRU, cinco personas con turno,
// todas en áreas que no son operativas. La pantalla decía «sin turnos» y pintaba
// la cobertura como un bloque sólido. Aquí se fija que «no hay nadie DEL GRUPO
// MEDIDO» nunca se diga como «no hay turnos».
//
// El otro lado (2026-09-20): cuando de verdad NADIE de la sede tiene turno y las
// tres metas del día son 0 —el domingo de Central—, sí se dice «Sin turnos», una
// vez, en gris. Con cualquier meta puesta se queda la alerta roja de siempre.
// ============================================================================
import { describe, expect, it } from "vitest";
import { colorCobertura, etiquetaCobertura, etiquetaSedeSinTurnos } from "@/lib/admin/cobertura-turnos";
import { SEDE_SIN_TURNOS, diaDeLaSedeDe, type HorarioTramo, type TurnoDia } from "@/lib/admin/jornada-esperada";

const base = { quien: "operativas" as const, hayGente: true, sinMeta: false, hayMeta: true, pct: 75 };

describe("etiquetaCobertura — operativas", () => {
  it("con gente y con meta: el porcentaje cubierto", () => {
    expect(etiquetaCobertura(base)).toEqual({ texto: "cubierto 75%", tono: "porcentaje" });
  });

  it("con meta puesta y ninguna operativa programada: alerta roja", () => {
    // Alguien olvidó armar los turnos de ese día: se avisa, no se calla en gris.
    const r = etiquetaCobertura({ ...base, hayGente: false });
    expect(r).toEqual({ texto: "¡ninguna operativa programada!", tono: "alerta" });
  });

  it("sin meta y ninguna operativa (Oficina TRU): un dato neutro que NO dice «sin turnos»", () => {
    const r = etiquetaCobertura({ ...base, hayGente: false, hayMeta: false });
    expect(r).toEqual({ texto: "sin operativas programadas", tono: "neutro" });
    expect(r.texto).not.toMatch(/sin turnos/i);
  });

  it("con gente pero sin meta: «sin meta»", () => {
    expect(etiquetaCobertura({ ...base, sinMeta: true, hayMeta: false })).toEqual({ texto: "sin meta", tono: "neutro" });
  });

  it("la alerta manda sobre «sin meta»: meta puesta y nadie es lo más urgente", () => {
    // Con meta y sin gente, `sinMeta` no aplica (no hubo contra qué comparar la
    // gente que no existe), y aun así la alerta tiene que ganar.
    const r = etiquetaCobertura({ ...base, hayGente: false, sinMeta: false, hayMeta: true });
    expect(r.tono).toBe("alerta");
  });
});

describe("etiquetaCobertura — líderes de equipo", () => {
  const enc = { ...base, quien: "lideres" as const };

  it("las mismas cuatro respuestas, en su propio idioma", () => {
    expect(etiquetaCobertura(enc)).toEqual({ texto: "cubierto 75%", tono: "porcentaje" });
    expect(etiquetaCobertura({ ...enc, hayGente: false })).toEqual({ texto: "¡ningún líder programado!", tono: "alerta" });
    expect(etiquetaCobertura({ ...enc, hayGente: false, hayMeta: false })).toEqual({ texto: "sin líderes programados", tono: "neutro" });
    expect(etiquetaCobertura({ ...enc, sinMeta: true, hayMeta: false })).toEqual({ texto: "sin meta", tono: "neutro" });
  });

  it("tampoco dice «sin turnos»", () => {
    for (const hayMeta of [true, false]) {
      expect(etiquetaCobertura({ ...enc, hayGente: false, hayMeta }).texto).not.toMatch(/sin turnos/i);
    }
  });
});

describe("colorCobertura — de qué color se pinta una hora", () => {
  it("sin meta y sin nadie: arena tenue, no un bloque sólido que parezca «todo cubierto»", () => {
    const c = colorCobertura(0, 0);
    expect(c).toContain("--color-sand");
    expect(c).not.toBe("var(--color-taupe)");
  });

  it("sin meta pero con gente: taupe neutro (hay gente, no hay contra qué medirla)", () => {
    expect(colorCobertura(3, 0)).toBe("var(--color-taupe)");
  });

  it("con meta y nadie: el rojo entero", () => {
    expect(colorCobertura(0, 2)).toContain("--color-verde) 0%");
  });

  it("con la meta cubierta o pasada: el verde entero, sin pasarse", () => {
    expect(colorCobertura(2, 2)).toContain("--color-verde) 100%");
    expect(colorCobertura(9, 2)).toContain("--color-verde) 100%");
  });

  it("a medias: la proporción exacta", () => {
    expect(colorCobertura(1, 2)).toContain("--color-verde) 50%");
  });
});

// ----------------------------------------------------------------------------
// Un día en que la sede no se labora. Se arma con las personas y sus horarios de
// verdad (diaDeLaSedeDe, la pregunta de jornada-esperada.ts) en vez de escribir la
// respuesta a mano: lo que se prueba es la cadena completa que recorre la página.
// ----------------------------------------------------------------------------
describe("etiquetaSedeSinTurnos — el domingo de Central", () => {
  const DOMINGO = "2026-09-20"; // dowDe = 0
  const META_0 = { manana: 0, tarde: 0, lideres: 0 };

  // Un tramo de horario base que trabaja los días dados, de 08:00 a 17:00.
  const tramo = (persona_id: string, dias: number[]): HorarioTramo => ({
    persona_id, vigente_desde: "2026-01-01", vigente_hasta: null,
    hora_entrada: null, hora_salida: null, dias_laborables: null,
    horario_por_dia: Object.fromEntries(dias.map((d) => [String(d), { e: "08:00", s: "17:00" }])),
    almuerzo_min_minutos: null,
  });
  const LUN_A_SAB = [1, 2, 3, 4, 5, 6];
  const descanso: TurnoDia = { es_descanso: true, hora_entrada: null, hora_salida: null };
  const turno: TurnoDia = { es_descanso: false, hora_entrada: "09:00", hora_salida: "13:00" };

  // La pregunta de la página: ¿a alguien de esta sede le toca ese día?
  const diaDe = (ids: string[], turnos: Record<string, TurnoDia> = {}, tramos: Record<string, HorarioTramo[]> = {}) =>
    diaDeLaSedeDe(ids, DOMINGO, (id) => turnos[id] ?? null, (id) => tramos[id] ?? []);

  it("nadie tiene turno el domingo y las tres metas son 0: una sola palabra gris, la de SEDE_SIN_TURNOS", () => {
    const dia = diaDe(["a", "b"], {}, { a: [tramo("a", LUN_A_SAB)], b: [tramo("b", LUN_A_SAB)] });
    expect(dia).toBe("no_trabaja");
    const et = etiquetaSedeSinTurnos(dia, META_0);
    expect(et).toEqual({ texto: SEDE_SIN_TURNOS, tono: "neutro" });
    expect(et?.texto).toBe("Sin turnos"); // la misma palabra del Dashboard, Incidencias y la Hoja de sede
  });

  it("un turno de descanso puesto a mano para ese domingo también cuenta como «no se labora»", () => {
    const dia = diaDe(["a", "b"], { a: descanso, b: descanso });
    expect(etiquetaSedeSinTurnos(dia, META_0)?.texto).toBe(SEDE_SIN_TURNOS);
  });

  it("la misma situación con CUALQUIERA de las tres metas > 0: no se calla, sigue la alerta roja", () => {
    // Alguien olvidó armar los turnos (o la meta debería ser 0): en Turnos, donde se
    // arma la semana, eso es rojo. La etiqueta del día no la toca etiquetaSedeSinTurnos.
    const dia = diaDe(["a", "b"], {}, { a: [tramo("a", LUN_A_SAB)], b: [tramo("b", LUN_A_SAB)] });
    for (const campo of ["manana", "tarde", "lideres"] as const) {
      expect(etiquetaSedeSinTurnos(dia, { ...META_0, [campo]: 1 })).toBeNull();
    }
    // …y lo que se muestra entonces es lo de siempre, sin cambiarle una palabra.
    const alerta = { hayGente: false, sinMeta: false, hayMeta: true, pct: 0 };
    expect(etiquetaCobertura({ ...alerta, quien: "operativas" })).toEqual({ texto: "¡ninguna operativa programada!", tono: "alerta" });
    expect(etiquetaCobertura({ ...alerta, quien: "lideres" })).toEqual({ texto: "¡ningún líder programado!", tono: "alerta" });
  });

  it("un día con turnos de personas de otra área (oficina): el día SÍ tiene turnos, todo sigue igual", () => {
    // Oficina TRU (2026-09-18): cinco personas con turno y ninguna operativa. Con las
    // metas en 0 no se dice «Sin turnos» —sería falso— y sigue el dato de siempre.
    const dia = diaDe(["oficina", "b"], { oficina: turno }, { b: [tramo("b", LUN_A_SAB)] });
    expect(dia).toBe("trabaja");
    expect(etiquetaSedeSinTurnos(dia, META_0)).toBeNull();
    const sinGrupo = { hayGente: false, sinMeta: false, hayMeta: false, pct: 0 };
    expect(etiquetaCobertura({ ...sinGrupo, quien: "operativas" })).toEqual({ texto: "sin operativas programadas", tono: "neutro" });
    expect(etiquetaCobertura({ ...sinGrupo, quien: "lideres" })).toEqual({ texto: "sin líderes programados", tono: "neutro" });
  });

  it("TODOS sin horario cargado y las tres metas en 0: no hay nada que alarmar, y «Sin turnos» es cierto", () => {
    const dia = diaDe(["a", "b"]); // sin turno y sin tramo vigente: no se sabe
    expect(dia).toBe("sin_horario");
    expect(etiquetaSedeSinTurnos(dia, META_0)).toEqual({ texto: SEDE_SIN_TURNOS, tono: "neutro" });
  });

  it("TODOS sin horario cargado pero con meta puesta: «no se sabe» no autoriza a callar, sigue en rojo", () => {
    const dia = diaDe(["a", "b"]);
    expect(etiquetaSedeSinTurnos(dia, { manana: 2, tarde: 2, lideres: 0 })).toBeNull();
    expect(etiquetaSedeSinTurnos(dia, { ...META_0, lideres: 1 })).toBeNull();
  });

  it("una sede sin nadie en la grilla, con las metas en 0: la palabra gris; con meta, la alerta", () => {
    const dia = diaDe([]);
    expect(etiquetaSedeSinTurnos(dia, META_0)?.texto).toBe(SEDE_SIN_TURNOS);
    expect(etiquetaSedeSinTurnos(dia, { ...META_0, manana: 1 })).toBeNull();
  });

  it("una respuesta real de descanso y otra sin horario, con las metas en 0: no se labora", () => {
    const dia = diaDe(["a", "b"], {}, { a: [tramo("a", LUN_A_SAB)] });
    expect(dia).toBe("no_trabaja");
    expect(etiquetaSedeSinTurnos(dia, META_0)?.texto).toBe(SEDE_SIN_TURNOS);
  });

  it("basta una persona con turno para que ya no sea «Sin turnos», aunque las metas estén en 0", () => {
    const dia = diaDe(["a", "b"], { b: turno }, { a: [tramo("a", LUN_A_SAB)] });
    expect(etiquetaSedeSinTurnos(dia, META_0)).toBeNull();
  });
});
