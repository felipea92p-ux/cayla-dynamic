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
  determinarSiguienteAccion,
  sugerirSalidaPrincipal,
  type MarcajeDelDia,
} from "@cayla-dynamic/shared";

// Ayudita para escribir marcajes legibles: hora de Lima → instante real (Lima = UTC-5).
const enLima = (fecha: string, hora: string) => `${fecha}T${hora}:00-05:00`;

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
});
