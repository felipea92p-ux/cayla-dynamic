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
import { marcasDeLaJornadaEnCurso } from "@/lib/terminal/jornada-en-curso";
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
