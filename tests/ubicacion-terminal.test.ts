// ============================================================================
// ubicacion-terminal.test.ts — ¿está en tienda o en almacén? (terminal)
// ============================================================================
// La regla tiene que ser la misma de `fn_ubicaciones_del_dia` (0580), que leen
// Turnos y los reportes: si el terminal dijera «En almacén» y la Integrada «en
// piso», la líder de equipo no sabría a cuál creerle. La prueba pgTAP 469 cubre
// los mismos casos del lado de la base.
// ============================================================================
import { describe, it, expect } from "vitest";
import type { MarcajeDelDia } from "@cayla-dynamic/shared";
import {
  DURACIONES_ALMACEN,
  cambiosDelPlan,
  textoPlanDeHoy,
  tramosDelDia,
  tramosPlanificados,
  detalleCasillaAlmacen,
  textoEstadoAlmacen,
  ubicacionActual,
  vueltaPrevista,
  type CambioUbicacion,
} from "@/lib/terminal/ubicacion";

const lima = (hora: string) => `2026-10-15T${hora}:00-05:00`;
const a = (hora: string) => new Date(lima(hora));
const alm = (hora: string, vuelve: string | null = null): CambioUbicacion => ({
  ubicacion: "almacen", timestamp: lima(hora), vuelvePrevisto: vuelve ? lima(vuelve) : null,
});
const tienda = (hora: string): CambioUbicacion => ({ ubicacion: "tienda", timestamp: lima(hora), vuelvePrevisto: null });
const salida = (hora: string): MarcajeDelDia => ({ tipo: "salida_final", timestamp: lima(hora) });

describe("ubicacionActual", () => {
  it("sin cambios está en tienda", () => {
    expect(ubicacionActual([], [], a("12:00")).enAlmacen).toBe(false);
  });

  it("se fue por una hora y todavía no vence: en almacén, con su vuelta", () => {
    const e = ubicacionActual([alm("12:32", "13:32")], [], a("13:00"));
    expect(e).toEqual({ enAlmacen: true, desde: lima("12:32"), vuelve: lima("13:32") });
  });

  it("venció su vuelta y no marcó: se la da de vuelta en tienda", () => {
    expect(ubicacionActual([alm("12:32", "13:32")], [], a("13:33")).enAlmacen).toBe(false);
  });

  it("«hasta que vuelva» sigue en almacén hasta que marque", () => {
    expect(ubicacionActual([alm("10:00")], [], a("18:00")).enAlmacen).toBe(true);
    expect(ubicacionActual([alm("10:00"), tienda("11:00")], [], a("18:00")).enAlmacen).toBe(false);
  });

  it("la salida final cierra el almacén; una salida de antes, no", () => {
    expect(ubicacionActual([alm("14:00")], [salida("15:00")], a("16:00")).enAlmacen).toBe(false);
    expect(ubicacionActual([alm("14:00")], [salida("13:00")], a("16:00")).enAlmacen).toBe(true);
  });

  it("un doble toque es un solo tramo: el desde es el primero y manda la última vuelta", () => {
    const e = ubicacionActual([alm("09:05"), alm("09:00", "09:30")], [], a("09:40"));
    expect(e).toEqual({ enAlmacen: true, desde: lima("09:00"), vuelve: null });
  });

  it("si la primera ida ya venció, la segunda empieza un tramo nuevo", () => {
    const e = ubicacionActual([alm("16:00", "16:30"), alm("17:00", "17:30")], [], a("17:10"));
    expect(e.desde).toBe(lima("17:00"));
  });
});

describe("textos", () => {
  it("dice desde cuándo y hasta cuándo, en la hora de Lima", () => {
    const e = ubicacionActual([alm("12:32", "13:32")], [], a("13:00"));
    expect(textoEstadoAlmacen(e)).toBe("En almacén desde 12:32 · vuelves 13:32");
    expect(detalleCasillaAlmacen(e)).toBe("En almacén · vuelve 13:32");
  });

  it("sin vuelta prevista no inventa una hora", () => {
    const e = ubicacionActual([alm("10:00")], [], a("11:00"));
    expect(textoEstadoAlmacen(e)).toBe("En almacén desde 10:00");
    expect(detalleCasillaAlmacen(e)).toBe("En almacén desde 10:00");
  });

  it("en tienda no hay nada que decir", () => {
    expect(textoEstadoAlmacen({ enAlmacen: false })).toBeNull();
    expect(detalleCasillaAlmacen({ enAlmacen: false })).toBeNull();
  });
});

describe("¿Por cuánto tiempo?", () => {
  it("son las cuatro respuestas decididas, en ese orden", () => {
    expect(DURACIONES_ALMACEN.map((d) => d.etiqueta)).toEqual(["30 min", "1 hora", "2 horas", "Hasta que vuelva"]);
  });

  it("la vuelta se calcula desde ahora; «hasta que vuelva» no lleva hora", () => {
    expect(vueltaPrevista(a("12:32"), 60)).toBe(new Date(lima("13:32")).toISOString());
    expect(vueltaPrevista(a("12:32"), null)).toBeNull();
  });
});

describe("lo planificado (0579)", () => {
  const medianoche = "2026-10-15T00:00:00-05:00";
  const turno = { desde: 9, hasta: 18 };

  it("dice dónde le toca hoy; si es piso, no dice nada", () => {
    expect(textoPlanDeHoy({ todoElTurno: false, tramos: [{ desde: 10.5, hasta: 12.5 }] })).toBe("Hoy te toca almacén de 10:30 a 12:30");
    expect(textoPlanDeHoy({ todoElTurno: true, tramos: [] })).toBe("Hoy te toca almacén todo el turno");
    expect(textoPlanDeHoy({ todoElTurno: false, tramos: [] })).toBeNull();
    expect(
      textoPlanDeHoy({ todoElTurno: false, tramos: [{ desde: 10, hasta: 11 }, { desde: 15, hasta: 16 }] }),
    ).toBe("Hoy te toca almacén de 10:00 a 11:00 y de 15:00 a 16:00");
  });

  it("se recorta a su turno: lo que cae fuera no se anuncia", () => {
    expect(tramosPlanificados({ todoElTurno: false, tramos: [{ desde: 8, hasta: 10 }, { desde: 19, hasta: 20 }] }, turno))
      .toEqual({ todoElTurno: false, tramos: [{ desde: 9, hasta: 10 }] });
    expect(tramosPlanificados({ todoElTurno: true, tramos: [] }, turno)).toEqual({ todoElTurno: true, tramos: [turno] });
  });

  it("dentro del tramo planificado está en almacén sin marcar nada", () => {
    const plan = cambiosDelPlan({ todoElTurno: false, tramos: [{ desde: 10.5, hasta: 12.5 }] }, medianoche);
    const e = ubicacionActual(plan, [], a("11:00"));
    expect(e.enAlmacen).toBe(true);
    expect(new Date(e.desde!).getTime()).toBe(a("10:30").getTime());
    expect(new Date(e.vuelve!).getTime()).toBe(a("12:30").getTime());
    expect(ubicacionActual(plan, [], a("12:31")).enAlmacen).toBe(false);
    expect(ubicacionActual(plan, [], a("10:00")).enAlmacen).toBe(false);
  });

  it("si marca «Vuelvo a tienda» durante lo planificado, manda lo real", () => {
    const plan = cambiosDelPlan({ todoElTurno: false, tramos: [{ desde: 10.5, hasta: 12.5 }] }, medianoche);
    expect(ubicacionActual([...plan, tienda("11:00")], [], a("11:30")).enAlmacen).toBe(false);
  });

  it("todo el turno sin horario conocido: hasta que vuelva o hasta su salida final", () => {
    const plan = cambiosDelPlan(tramosPlanificados({ todoElTurno: true, tramos: [] }, null), medianoche);
    expect(ubicacionActual(plan, [], a("15:00")).enAlmacen).toBe(true);
    expect(ubicacionActual(plan, [salida("17:00")], a("17:30")).enAlmacen).toBe(false);
  });
});

describe("tramosDelDia: la regla única, en tramos (la usa Turnos)", () => {
  const h = (iso: string | null) => (iso ? new Date(iso).toISOString() : null);
  const tramos = (cs: CambioUbicacion[], ms: MarcajeDelDia[], ahora: string) =>
    tramosDelDia(cs, ms, a(ahora)).map((t) => [h(t.desde), h(t.hasta)]);

  it("los mismos casos que la prueba 469 de la base", () => {
    expect(tramos([alm("10:00"), tienda("11:00")], [], "20:00")).toEqual([[h(lima("10:00")), h(lima("11:00"))]]);
    expect(tramos([alm("12:00", "12:30")], [], "20:00")).toEqual([[h(lima("12:00")), h(lima("12:30"))]]);
    expect(tramos([alm("14:00")], [salida("15:00")], "20:00")).toEqual([[h(lima("14:00")), h(lima("15:00"))]]);
    expect(tramos([alm("09:00", "09:30"), alm("09:05"), tienda("10:00")], [], "20:00")).toEqual([[h(lima("09:00")), h(lima("10:00"))]]);
    expect(tramos([alm("16:00", "16:30"), alm("17:00", "17:30")], [], "20:00")).toEqual([
      [h(lima("16:00")), h(lima("16:30"))],
      [h(lima("17:00")), h(lima("17:30"))],
    ]);
  });

  it("el tramo de ahora queda abierto (hasta = null)", () => {
    expect(tramos([alm("10:00", "11:00")], [], "10:30")).toEqual([[h(lima("10:00")), null]]);
  });
});
