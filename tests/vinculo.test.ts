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
import {
  MAXIMO_LEGAL_SEMANAL,
  esPrestadorDeServicios,
  leCorrespondeCuspp,
  maximoSemanalPracticante,
  nombreDelDocumentoDePago,
} from "@cayla-dynamic/shared";

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

  // CAMBIO 0328 · los cuatro códigos de comisión mixta son la MISMA AFP con otro
  // esquema de cobro, no otro sistema previsional: la cuenta individual existe
  // igual y el CUSPP la identifica igual. Se comprueba porque la función mira el
  // código como texto, así que un sufijo nuevo es justo la forma en que podría
  // dejar de reconocerlos — y dejar de pedir el CUSPP no falla en ninguna
  // pantalla, falla en la PLAME.
  it("y a quien está en la misma AFP con comisión mixta, también", () => {
    expect(leCorrespondeCuspp(true, "integra_mixta")).toBe(true);
    expect(leCorrespondeCuspp(true, "profuturo_mixta")).toBe(true);
    expect(leCorrespondeCuspp(true, "prima_mixta")).toBe(true);
    expect(leCorrespondeCuspp(true, "habitat_mixta")).toBe(true);
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

// ============================================================================
// maximoSemanalPracticante — el tope que sostiene que el convenio sea formativo
// ============================================================================
// Existía desde la 0324 SIN UNA SOLA PRUEBA, y desde entonces decide dos cosas
// que cuestan caro por separado:
//
//   · el texto del convenio — «seis (6) horas diarias ni treinta (30) semanales»
//     contra «ocho (8) y cuarenta y ocho (48)», art. 44 de la Ley 28518;
//   · y, desde el arreglo del hallazgo 12, contra qué número Incidencias mide el
//     exceso de jornada de una practicante.
//
// Las 30 h de una preprofesional no son «una jornada más corta»: son la
// condición que sostiene que la relación sea FORMATIVA. Pasarse es un indicio
// de desnaturalización, y esas horas quedan en `marcajes`, que es append-only.
//
// LAS DOS MITADES QUE ESTO DEFIENDE, y que se rompen por separado:
//
//   · QUE DISTINGA. Si las dos modalidades devolvieran lo mismo, un convenio
//     preprofesional saldría prometiendo 48 h y el aviso de Incidencias se
//     callaría hasta las 48 — justo con quien menos margen tiene.
//
//   · QUE EL `null` SIGA SIENDO `null`. Es lo que le dice a quien arma el
//     horario que FALTA UN DATO, no que no hay límite. El día que alguien lo
//     «simplifique» devolviendo 30 por defecto, se le estaría acusando de
//     exceso a una profesional que trabaja 40 h con todo derecho; y si lo
//     simplifica a 48, se deja de avisar a la preprofesional. Los dos errores
//     son silenciosos y ninguno falla al desplegar.
describe("maximoSemanalPracticante — 30 h o 48 h, según la modalidad", () => {
  it("preprofesional: 30 h mientras estudia", () => {
    expect(maximoSemanalPracticante("practicante", "preprofesional")).toBe(30);
  });

  it("profesional: 48 h, ya egresó", () => {
    expect(maximoSemanalPracticante("practicante", "profesional")).toBe(48);
  });

  it("distingue de verdad entre las dos modalidades", () => {
    expect(maximoSemanalPracticante("practicante", "preprofesional"))
      .not.toBe(maximoSemanalPracticante("practicante", "profesional"));
  });

  it("quien no es practicante no tiene tope de modalidad", () => {
    expect(maximoSemanalPracticante("planilla", "preprofesional")).toBeNull();
    expect(maximoSemanalPracticante("prueba", null)).toBeNull();
    expect(maximoSemanalPracticante("rxh", null)).toBeNull();
    expect(maximoSemanalPracticante("no_trabajador", null)).toBeNull();
    expect(maximoSemanalPracticante(null, null)).toBeNull();
    expect(maximoSemanalPracticante(undefined, undefined)).toBeNull();
  });

  // EL null QUE NO SIGNIFICA «SIN LÍMITE», SINO «FALTA UN DATO».
  it("practicante sin modalidad: null, nunca un número inventado", () => {
    expect(maximoSemanalPracticante("practicante", null)).toBeNull();
    expect(maximoSemanalPracticante("practicante", undefined)).toBeNull();
    expect(maximoSemanalPracticante("practicante", "")).toBeNull();
    expect(maximoSemanalPracticante("practicante", "cualquier_cosa")).toBeNull();
  });

  // La decisión que toman sus dos consumidores con ese null, escrita acá para
  // que se lea junta: caen al tope general. Inventarle 30 a quien quizá sea
  // profesional sería acusar de más, y acá el falso positivo es el peor error.
  it("el tope efectivo de quien no tiene modalidad es el general, no el más estricto", () => {
    const efectivo = maximoSemanalPracticante("practicante", null) ?? MAXIMO_LEGAL_SEMANAL;
    expect(efectivo).toBe(MAXIMO_LEGAL_SEMANAL);
    expect(efectivo).not.toBe(30);
  });
});
