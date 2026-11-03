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
