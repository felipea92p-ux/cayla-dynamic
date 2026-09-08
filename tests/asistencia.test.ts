// ============================================================================
// asistencia.test.ts — Blindaje de la máquina de estados de asistencia
// ============================================================================
// Esta es la lógica que decide QUÉ marca le toca a una persona cuando toca la
// terminal (entrada / salida / retorno). Un error aquí no cuesta plata: registra
// mal la asistencia de alguien, y de ahí sale su sueldo y su legajo.
//
// Importante: el propio código advierte que esta lógica está DUPLICADA con
// fn_registrar_marcaje en Postgres. Estas pruebas anclan el lado del navegador,
// para que si alguien cambia una sin la otra, se note.
// ============================================================================
import { describe, it, expect } from "vitest";
import {
  calcularHoraMediaRefrigerio,
  determinarSiguienteAccion,
  sugerirSalidaPrincipal,
  type EstadisticasSugerencia,
  type MarcajeDelDia,
} from "@cayla-dynamic/shared";

// Ayudita para escribir marcajes legibles: hora de Lima → instante real (Lima = UTC-5).
const enLima = (fecha: string, hora: string) => `${fecha}T${hora}:00-05:00`;

// ESPEJO: supabase/tests/90_espejo_de_la_maquina_de_estados.test.sql tiene estos
// mismos casos, con los mismos nombres, contra fn_siguiente_tipo_esperado.
//
// "Qué marca toca ahora" se decide en dos sitios: aquí (dibuja los botones del
// terminal) y en la base (acepta o rechaza la marca al llegar). Si divergen, el
// terminal ofrece un botón que el servidor va a rechazar y la persona se queda
// sin poder marcar. Pasó el 26-07-2026 con las marcas anuladas: se arregló la
// versión SQL y esta se quedó atrás.
//
// Si tocas un caso aquí, tócalo allí.
describe("determinarSiguienteAccion — qué marca toca ahora", () => {
  it("sin ningún marcaje, lo único posible es ENTRAR", () => {
    expect(determinarSiguienteAccion([])).toEqual({ modo: "unico", tipo: "entrada" });
  });

  it("con la entrada marcada y nada más, toca ELEGIR cómo sale", () => {
    const marcajes: MarcajeDelDia[] = [{ tipo: "entrada", timestamp: enLima("2026-07-23", "09:00") }];
    const accion = determinarSiguienteAccion(marcajes);
    expect(accion.modo).toBe("elegir_salida");
  });

  it("si salió a almorzar, lo ÚNICO posible es su retorno (sin ambigüedad)", () => {
    const marcajes: MarcajeDelDia[] = [
      { tipo: "entrada", timestamp: enLima("2026-07-23", "09:00") },
      { tipo: "salida_almuerzo", timestamp: enLima("2026-07-23", "13:00") },
    ];
    expect(determinarSiguienteAccion(marcajes)).toEqual({
      modo: "unico",
      tipo: "retorno_almuerzo",
      motivoRequerido: false,
    });
  });

  it("cada tipo de salida exige SU retorno correspondiente (médico → retorno médico)", () => {
    const marcajes: MarcajeDelDia[] = [
      { tipo: "entrada", timestamp: enLima("2026-07-23", "09:00") },
      { tipo: "salida_medico", timestamp: enLima("2026-07-23", "11:00") },
    ];
    const accion = determinarSiguienteAccion(marcajes);
    expect(accion).toMatchObject({ modo: "unico", tipo: "retorno_medico" });
  });

  it("tras volver del almuerzo, vuelve a poder elegir cómo sale", () => {
    const marcajes: MarcajeDelDia[] = [
      { tipo: "entrada", timestamp: enLima("2026-07-23", "09:00") },
      { tipo: "salida_almuerzo", timestamp: enLima("2026-07-23", "13:00") },
      { tipo: "retorno_almuerzo", timestamp: enLima("2026-07-23", "14:00") },
    ];
    expect(determinarSiguienteAccion(marcajes).modo).toBe("elegir_salida");
  });

  it("con la salida final marcada, el día queda CERRADO", () => {
    const marcajes: MarcajeDelDia[] = [
      { tipo: "entrada", timestamp: enLima("2026-07-23", "09:00") },
      { tipo: "salida_final", timestamp: enLima("2026-07-23", "18:00") },
    ];
    const accion = determinarSiguienteAccion(marcajes);
    expect(accion.modo).toBe("cerrado");
  });

  it("no se confunde si los marcajes llegan DESORDENADOS (los ordena por hora)", () => {
    // La cola offline puede devolverlos en cualquier orden: el resultado debe ser el mismo.
    const desordenados: MarcajeDelDia[] = [
      { tipo: "salida_almuerzo", timestamp: enLima("2026-07-23", "13:00") },
      { tipo: "entrada", timestamp: enLima("2026-07-23", "09:00") },
    ];
    expect(determinarSiguienteAccion(desordenados)).toMatchObject({
      modo: "unico",
      tipo: "retorno_almuerzo",
    });
  });

  it("la salida final manda aunque haya una salida temporal previa", () => {
    const marcajes: MarcajeDelDia[] = [
      { tipo: "entrada", timestamp: enLima("2026-07-23", "09:00") },
      { tipo: "salida_almuerzo", timestamp: enLima("2026-07-23", "13:00") },
      { tipo: "retorno_almuerzo", timestamp: enLima("2026-07-23", "14:00") },
      { tipo: "salida_final", timestamp: enLima("2026-07-23", "18:00") },
    ];
    expect(determinarSiguienteAccion(marcajes).modo).toBe("cerrado");
  });
});

describe("sugerirSalidaPrincipal — qué salida destacar en la terminal", () => {
  const entrada9am: MarcajeDelDia[] = [
    { tipo: "entrada", timestamp: enLima("2026-07-23", "09:00") },
  ];

  it("a mediodía y con 2+ horas adentro, sugiere REFRIGERIO", () => {
    const mediodiaLima = new Date(enLima("2026-07-23", "12:00"));
    expect(sugerirSalidaPrincipal(entrada9am, mediodiaLima)).toBe("salida_almuerzo");
  });

  it("si YA almorzó hoy, sugiere salida final (no lo manda a almorzar dos veces)", () => {
    const yaAlmorzo: MarcajeDelDia[] = [
      ...entrada9am,
      { tipo: "salida_almuerzo", timestamp: enLima("2026-07-23", "13:00") },
      { tipo: "retorno_almuerzo", timestamp: enLima("2026-07-23", "14:00") },
    ];
    const tarde = new Date(enLima("2026-07-23", "15:00"));
    expect(sugerirSalidaPrincipal(yaAlmorzo, tarde)).toBe("salida_final");
  });

  it("temprano en la mañana sugiere salida final, no refrigerio", () => {
    const temprano: MarcajeDelDia[] = [
      { tipo: "entrada", timestamp: enLima("2026-07-23", "07:00") },
    ];
    const nueveYMedia = new Date(enLima("2026-07-23", "09:30"));
    expect(sugerirSalidaPrincipal(temprano, nueveYMedia)).toBe("salida_final");
  });

  it("a mediodía pero recién llegado (menos de 2h), NO sugiere refrigerio", () => {
    const recienLlegado: MarcajeDelDia[] = [
      { tipo: "entrada", timestamp: enLima("2026-07-23", "11:30") },
    ];
    const doceYMedia = new Date(enLima("2026-07-23", "12:30"));
    expect(sugerirSalidaPrincipal(recienLlegado, doceYMedia)).toBe("salida_final");
  });

  // Con `estadisticas`: el patrón personal manda por completo dentro de su
  // ventana, y el horario asignado decide salida final vs. "neutra" cuando
  // el patrón no aplica. Sin pasar el tercer argumento (los 4 tests de
  // arriba), el comportamiento tiene que seguir siendo EXACTAMENTE el mismo
  // — por eso esos tests no cambiaron una línea.
  describe("con estadísticas personalizadas", () => {
    const conPatron = (horaMediaRefrigerio: number | null, horaSalidaEsperada: number | null = null): EstadisticasSugerencia => ({
      horaMediaRefrigerio,
      horaSalidaEsperada,
    });

    it("dentro de la ventana de su media histórica (±30min), sugiere refrigerio aunque sea temprano", () => {
      const entrada7am: MarcajeDelDia[] = [{ tipo: "entrada", timestamp: enLima("2026-07-23", "07:00") }];
      const nueveYCuarto = new Date(enLima("2026-07-23", "09:15"));
      // Media histórica: 9:00. Regla fija diría "salida_final" (antes de 11h) —
      // el patrón personal la reemplaza por completo.
      expect(sugerirSalidaPrincipal(entrada7am, nueveYCuarto, conPatron(9.0))).toBe("salida_almuerzo");
    });

    it("fuera de la ventana de su media histórica, NO sugiere refrigerio aunque la regla fija sí lo haría", () => {
      const entrada9am: MarcajeDelDia[] = [{ tipo: "entrada", timestamp: enLima("2026-07-23", "09:00") }];
      const mediodia = new Date(enLima("2026-07-23", "12:00"));
      // Media histórica: 14:00 — 12:00 cae fuera de [13:30, 14:30]. Sin horario
      // asignado en las estadísticas, cae al respaldo de siempre: salida final.
      expect(sugerirSalidaPrincipal(entrada9am, mediodia, conPatron(14.0))).toBe("salida_final");
    });

    it("con horario asignado, cerca de la hora de salida esperada sugiere salida final", () => {
      const entrada8am: MarcajeDelDia[] = [{ tipo: "entrada", timestamp: enLima("2026-07-23", "08:00") }];
      const cincoYDiez = new Date(enLima("2026-07-23", "17:10"));
      // Hora de salida esperada: 17:00 — 17:10 cae dentro de [16:30, ∞).
      expect(sugerirSalidaPrincipal(entrada8am, cincoYDiez, conPatron(null, 17.0))).toBe("salida_final");
    });

    it('ni refrigerio ni salida final aplican → zona "neutra" (el caso de las 9am recién entrando)', () => {
      const entrada8am: MarcajeDelDia[] = [{ tipo: "entrada", timestamp: enLima("2026-07-23", "08:00") }];
      const nueveYVeintiseis = new Date(enLima("2026-07-23", "09:26"));
      // Media de refrigerio 13:00, sale a las 17:00: 9:26 no cae en ninguna.
      expect(sugerirSalidaPrincipal(entrada8am, nueveYVeintiseis, conPatron(13.0, 17.0))).toBe("neutra");
    });

    it("ya almorzó hoy: el patrón de refrigerio no vuelve a aplicar aunque la hora coincida", () => {
      const yaAlmorzo: MarcajeDelDia[] = [
        { tipo: "entrada", timestamp: enLima("2026-07-23", "08:00") },
        { tipo: "salida_almuerzo", timestamp: enLima("2026-07-23", "13:00") },
        { tipo: "retorno_almuerzo", timestamp: enLima("2026-07-23", "14:00") },
      ];
      const unaYCinco = new Date(enLima("2026-07-23", "13:05"));
      expect(sugerirSalidaPrincipal(yaAlmorzo, unaYCinco, conPatron(13.0, 17.0))).not.toBe("salida_almuerzo");
    });

    it("sin horario asignado (RxH, o sin dato), respalda en salida final como siempre — nunca neutra", () => {
      const entrada8am: MarcajeDelDia[] = [{ tipo: "entrada", timestamp: enLima("2026-07-23", "08:00") }];
      const nueveYVeintiseis = new Date(enLima("2026-07-23", "09:26"));
      expect(sugerirSalidaPrincipal(entrada8am, nueveYVeintiseis, conPatron(13.0, null))).toBe("salida_final");
    });
  });
});

describe("calcularHoraMediaRefrigerio — el patrón personal de cada persona", () => {
  it("con menos de 3 muestras, no hay patrón confiable", () => {
    expect(calcularHoraMediaRefrigerio([enLima("2026-07-20", "13:00"), enLima("2026-07-21", "13:00")])).toBeNull();
  });

  it("con 3 o más muestras, calcula la media en hora decimal Lima", () => {
    const resultado = calcularHoraMediaRefrigerio([
      enLima("2026-07-20", "13:00"),
      enLima("2026-07-21", "13:00"),
      enLima("2026-07-22", "13:30"),
    ]);
    expect(resultado?.muestras).toBe(3);
    expect(resultado?.media).toBeCloseTo(13.1667, 3);
  });
});
