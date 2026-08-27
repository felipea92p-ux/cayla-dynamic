// ============================================================================
// jornada-en-curso.test.ts — La noche que cruza la medianoche
// ============================================================================
// El terminal decidía qué ofrecer mirando solo las marcas de HOY. A las 00:30
// «hoy» está vacío, así que a quien acababa de cerrar tienda le ofrecía
// «Entrada» — y con eso abría un día fantasma que el auto-cierre remataba en 22
// horas. Su salida real nunca llegaba a existir (C4, migración 0240).
//
// Lo que se prueba aquí es la regla del TURNO, no la del calendario. Y sobre
// todo la trampa: pasarle el día de ayer completo rompería el caso normal,
// porque `determinarSiguienteAccion` responde «cerrado» en cuanto ve un
// salida_final.
// ============================================================================
import { describe, expect, it } from "vitest";
import { jornadaEnCursoPorPersona, marcasDeLaJornadaEnCurso } from "@/lib/terminal/jornada-en-curso";
import { determinarSiguienteAccion, type MarcajeDelDia } from "@cayla-dynamic/shared";

const entrada = (t: string): MarcajeDelDia => ({ tipo: "entrada", timestamp: t });
const salidaFinal = (t: string): MarcajeDelDia => ({ tipo: "salida_final", timestamp: t });
const salidaAlmuerzo = (t: string): MarcajeDelDia => ({ tipo: "salida_almuerzo", timestamp: t });

describe("marcasDeLaJornadaEnCurso", () => {
  it("a las 00:30, con la jornada de ayer sin cerrar, sigue siendo la de ayer", () => {
    const ayer = [entrada("2026-08-04T20:00:00Z")];
    expect(marcasDeLaJornadaEnCurso(ayer, [])).toEqual(ayer);
  });

  it("y entonces el terminal le ofrece SALIR, no entrar — que es todo el arreglo", () => {
    const ayer = [entrada("2026-08-04T20:00:00Z")];
    const accion = determinarSiguienteAccion(marcasDeLaJornadaEnCurso(ayer, []));
    expect(accion.modo).not.toBe("cerrado");
    // Con una entrada sin salida, lo siguiente es alguna forma de salida.
    expect(JSON.stringify(accion)).toContain("salida");
  });

  it("si ayer cerró normal, hoy empieza de cero — la trampa que rompe el caso común", () => {
    // Pasarle el día de ayer entero haría que determinarSiguienteAccion dijera
    // «ya registraste tu salida final de hoy» a alguien que llega por la mañana.
    const ayer = [entrada("2026-08-04T14:00:00Z"), salidaFinal("2026-08-04T23:00:00Z")];
    expect(marcasDeLaJornadaEnCurso(ayer, [])).toEqual([]);
    expect(determinarSiguienteAccion(marcasDeLaJornadaEnCurso(ayer, []))).toEqual({
      modo: "unico", tipo: "entrada",
    });
  });

  it("en cuanto marca algo hoy, la noche terminó y manda lo de hoy", () => {
    const ayer = [entrada("2026-08-04T20:00:00Z")];           // quedó abierta
    const hoy = [entrada("2026-08-05T14:00:00Z")];
    expect(marcasDeLaJornadaEnCurso(ayer, hoy)).toEqual(hoy);
  });

  it("una pausa de ayer sin retorno también sigue en curso", () => {
    // No solo la entrada: si salió a refrigerio y no volvió antes de medianoche,
    // esa jornada sigue siendo la suya.
    const ayer = [entrada("2026-08-04T20:00:00Z"), salidaAlmuerzo("2026-08-05T02:00:00Z")];
    expect(marcasDeLaJornadaEnCurso(ayer, [])).toEqual(ayer);
  });

  it("sin nada ayer ni hoy, no hay jornada en curso", () => {
    expect(marcasDeLaJornadaEnCurso([], [])).toEqual([]);
  });
});

// ============================================================================
// Y LA MITAD QUE FALTABA: A QUÉ JORNADA PERTENECE CADA MARCA
// ============================================================================
// `marcasDeLaJornadaEnCurso` ya estaba probada, y decide bien. Lo que nadie
// probaba es lo que le llega: el reparto entre «ayer» y «hoy». Vivía dentro de
// `cargarMarcajesHoyPorPersona`, que hace red, y repartía por la fecha de
// CALENDARIO del `timestamp_marca`.
//
// Ahí estaba el defecto. Quien cierra tienda a las 00:30 tiene su salida
// guardada con `fecha_jornada` del día anterior —eso lo hace bien la 0240— pero
// por calendario esa salida cae en el cubo de HOY. Al marcar su entrada de la
// mañana, la máquina de estados veía un `salida_final` y respondía «cerrado»:
// el terminal le decía «Ya cerraste tu día. ¿Volviste a entrar?» a alguien que
// acababa de llegar, y el único botón hacia adelante ANULABA la salida real de
// anoche.
//
// Medido contra el Postgres local: 9,50 h y S/109,62 perdidos, y el día anterior
// reabierto sin entrada. La otra mitad del arreglo vive en la migración 0317.
// ============================================================================
const dia = (ts: string) => ts.slice(0, 10); // el «calendario» para estas pruebas

describe("jornadaEnCursoPorPersona", () => {
  const ANA = "ana";

  it("la salida de las 00:30 pertenece a AYER, aunque el calendario diga hoy", () => {
    // Entra el 25 a las 15:00 y cierra tienda a las 00:30 del 26. La salida
    // lleva fecha_jornada del 25 — que es lo que la 0240 guarda.
    const filas = [
      { persona_id: ANA, tipo: "entrada" as const, timestamp_marca: "2026-08-25T20:00:00Z", fecha_jornada: null },
      { persona_id: ANA, tipo: "salida_final" as const, timestamp_marca: "2026-08-26T05:30:00Z", fecha_jornada: "2026-08-25" },
    ];
    // Todavía no ha marcado nada del 26: no hay jornada en curso, y por eso el
    // terminal le va a ofrecer ENTRADA.
    const mapa = jornadaEnCursoPorPersona(filas, "2026-08-26", dia);
    expect(mapa.get(ANA) ?? []).toEqual([]);
    expect(determinarSiguienteAccion(mapa.get(ANA) ?? [])).toEqual({ modo: "unico", tipo: "entrada" });
  });

  it("y tras marcar su entrada de la mañana, el terminal NO dice «ya cerraste»", () => {
    // Éste es el caso que costaba S/109,62: con el reparto por calendario, la
    // salida de las 00:30 entraba aquí y la respuesta era «cerrado».
    const filas = [
      { persona_id: ANA, tipo: "entrada" as const, timestamp_marca: "2026-08-25T20:00:00Z", fecha_jornada: null },
      { persona_id: ANA, tipo: "salida_final" as const, timestamp_marca: "2026-08-26T05:30:00Z", fecha_jornada: "2026-08-25" },
      { persona_id: ANA, tipo: "entrada" as const, timestamp_marca: "2026-08-26T13:00:00Z", fecha_jornada: null },
    ];
    const enCurso = jornadaEnCursoPorPersona(filas, "2026-08-26", dia).get(ANA) ?? [];
    expect(enCurso).toHaveLength(1);
    expect(enCurso[0].tipo).toBe("entrada");
    expect(determinarSiguienteAccion(enCurso).modo).not.toBe("cerrado");
  });

  it("sin fecha_jornada manda el calendario: el caso NORMAL, no el defensivo", () => {
    // Las entradas no llevan `fecha_jornada`. Si el `??` se leyera como un
    // adorno defensivo y alguien lo quitara, dejaría de funcionar lo corriente.
    const filas = [
      { persona_id: ANA, tipo: "entrada" as const, timestamp_marca: "2026-08-26T14:00:00Z", fecha_jornada: null },
    ];
    const enCurso = jornadaEnCursoPorPersona(filas, "2026-08-26", dia).get(ANA) ?? [];
    expect(enCurso).toHaveLength(1);
  });

  it("no se rompe el caso que arregló la 0240: a las 00:30 sin cerrar, sigue la de ayer", () => {
    // La trampa al revés. Si esto se rompiera, a quien cierra tienda a la
    // medianoche se le ofrecería ENTRADA y volvería el día fantasma.
    const filas = [
      { persona_id: ANA, tipo: "entrada" as const, timestamp_marca: "2026-08-25T20:00:00Z", fecha_jornada: null },
    ];
    const enCurso = jornadaEnCursoPorPersona(filas, "2026-08-26", dia).get(ANA) ?? [];
    expect(enCurso).toHaveLength(1);
    expect(JSON.stringify(determinarSiguienteAccion(enCurso))).toContain("salida");
  });

  it("cada persona por su cuenta: la noche de una no mueve la de la otra", () => {
    const filas = [
      { persona_id: "ana", tipo: "salida_final" as const, timestamp_marca: "2026-08-26T05:30:00Z", fecha_jornada: "2026-08-25" },
      { persona_id: "bea", tipo: "entrada" as const, timestamp_marca: "2026-08-26T14:00:00Z", fecha_jornada: null },
    ];
    const mapa = jornadaEnCursoPorPersona(filas, "2026-08-26", dia);
    expect(mapa.get("ana") ?? []).toEqual([]);
    expect(mapa.get("bea") ?? []).toHaveLength(1);
  });
});
