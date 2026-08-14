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
import { esPrestadorDeServicios, leCorrespondeCuspp, nombreDelDocumentoDePago } from "@cayla-dynamic/shared";

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

// ============================================================================
// leCorrespondeCuspp — a quién se le pide el código de su cuenta en la AFP
// ============================================================================
// El 2026-08-13 la pantalla de fichas le mostraba «falta CUSPP» a dos locadoras.
// Nadie podía completarlo nunca: el CUSPP identifica a un TRABAJADOR en el
// T-Registro, y una locadora no está en el T-Registro. Un aviso permanente e
// imposible es lo que enseña a ignorar los avisos que sí importan.
//
// Las dos mitades, otra vez, y se rompen por separado:
//
//   · QUE NO PIDA lo que no corresponde — locadora, ONP, jubilada, sin régimen.
//   · QUE SIGA PIDIENDO a quien sí. Y sobre todo: que un campo AUSENTE no exima
//     a nadie. Si `en_planilla` no viaja en el JSON, el defecto tiene que ser
//     seguir pidiendo el CUSPP a las veinte que lo necesitan — no dejar de
//     pedírselo en silencio, que es la falla que nadie ve hasta la PLAME.
describe("leCorrespondeCuspp — tres descartes por tres razones distintas", () => {
  it("a quien está en planilla y en una AFP, sí se le pide", () => {
    expect(leCorrespondeCuspp(true, "integra")).toBe(true);
    expect(leCorrespondeCuspp(true, "profuturo")).toBe(true);
    expect(leCorrespondeCuspp(true, "prima")).toBe(true);
    expect(leCorrespondeCuspp(true, "habitat")).toBe(true);
  });

  it("a una locadora NO, aunque tenga una AFP cargada", () => {
    // El caso real de Catherine y Claudia: régimen puesto y vínculo por
    // honorarios. Que tengan AFP no la convierte en asunto de CAYLA.
    expect(leCorrespondeCuspp(false, "integra")).toBe(false);
    expect(leCorrespondeCuspp(false, "profuturo")).toBe(false);
  });

  it("en ONP no, porque no hay cuenta individual que identificar", () => {
    expect(leCorrespondeCuspp(true, "onp")).toBe(false);
  });

  it("jubilada no, porque ya no aporta", () => {
    expect(leCorrespondeCuspp(true, "jubilada")).toBe(false);
  });

  it("sin régimen cargado no se pide todavía: primero hay que saber cuál es", () => {
    expect(leCorrespondeCuspp(true, null)).toBe(false);
    expect(leCorrespondeCuspp(true, undefined)).toBe(false);
    expect(leCorrespondeCuspp(true, "")).toBe(false);
    expect(leCorrespondeCuspp(true, "   ")).toBe(false);
  });

  // La aserción que sostiene el defecto seguro, y la razón de que esto use
  // `esPrestadorDeServicios` en vez de un `!enPlanilla`.
  it("un `en_planilla` que no llegó NO exime a nadie: se sigue pidiendo", () => {
    expect(leCorrespondeCuspp(undefined, "integra")).toBe(true);
    expect(leCorrespondeCuspp(null, "integra")).toBe(true);
  });
});
