// ============================================================================
// vinculo.test.ts — que un dato ausente nunca convierta a nadie en locador
// ============================================================================
// El 2026-08-08 la boleta dejó de hablarle a todo el mundo en idioma de planilla:
// quien presta servicios por honorarios recibe otro documento, con otro
// encabezado, otro cierre y otro texto legal. Nueve pantallas van a hacer esa
// misma pregunta, así que la pregunta vive en un solo sitio.
//
// LAS DOS MITADES QUE ESTO DEFIENDE, y que se rompen por separado:
//
//   · EL DEFECTO SEGURO. Un `undefined` —el frontend desplegado contra una base
//     donde el campo todavía no viaja, que en este proyecto pasa de verdad porque
//     el SQL se pega a mano— tiene que dejar el documento como estaba. Si alguien
//     «simplifica» esto a `!enPlanilla`, treinta personas reciben de golpe un
//     papel que les niega gratificación, CTS y vacaciones. Es el fallo más caro
//     posible de este archivo y no avisa: el documento sale bonito y dice mentiras.
//
//   · QUE SÍ DISTINGA. Un `false` explícito tiene que cambiar el documento. Si
//     esto se rompe, CAYLA vuelve a emitirle a un locador un papel que lo llama
//     trabajador todos los meses — que pesa más en una inspección que el contrato.
// ============================================================================
import { describe, it, expect } from "vitest";
import { esPrestadorDeServicios, nombreDelDocumentoDePago } from "@cayla-dynamic/shared";

describe("esPrestadorDeServicios — solo un «no» explícito cuenta", () => {
  it("quien está en planilla NO es prestador de servicios", () => {
    expect(esPrestadorDeServicios(true)).toBe(false);
  });

  it("quien la base dice que NO está en planilla, sí lo es", () => {
    expect(esPrestadorDeServicios(false)).toBe(true);
  });

  // Las dos aserciones que sostienen el defecto seguro. Van separadas a
  // propósito: `undefined` es el campo que no viajó en el JSON y `null` es la
  // fila que no trajo el dato. Los dos significan «no sé», y no saber nunca
  // puede cambiarle el documento a nadie.
  it("un campo que no llegó (undefined) deja el documento como estaba", () => {
    expect(esPrestadorDeServicios(undefined)).toBe(false);
  });

  it("un dato nulo tampoco convierte a nadie", () => {
    expect(esPrestadorDeServicios(null)).toBe(false);
  });
});

describe("nombreDelDocumentoDePago — el título va pegado a la regla", () => {
  it("a quien está en planilla se le entrega una boleta interna", () => {
    expect(nombreDelDocumentoDePago(true)).toBe("Boleta interna de pago");
  });

  it("a quien presta servicios, un detalle de servicios prestados", () => {
    expect(nombreDelDocumentoDePago(false)).toBe("Detalle de servicios prestados");
  });

  it("y sin dato, la boleta de siempre — nunca el documento nuevo por descarte", () => {
    expect(nombreDelDocumentoDePago(undefined)).toBe("Boleta interna de pago");
    expect(nombreDelDocumentoDePago(null)).toBe("Boleta interna de pago");
  });
});
