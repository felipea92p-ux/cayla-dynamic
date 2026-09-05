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
  tieneTopePropio,
  topeSemanalDe,
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
// El tope semanal de una practicante — art. 44 de la Ley 28518
// ============================================================================
// Las 30 h de una preprofesional no son «una jornada más corta»: son la
// condición que sostiene que el convenio sea FORMATIVO. Pasarse de ellas es uno
// de los indicios con los que se desnaturaliza en contrato de trabajo, y esas
// horas quedan escritas en `marcajes`, que es append-only — la evidencia se
// acumula sola y no se puede corregir hacia atrás.
//
// `maximoSemanalPracticante` existía desde la 0324 y decidía el texto de un
// convenio SIN UNA SOLA PRUEBA. Estas son las suyas y las de `topeSemanalDe`,
// que es la que resuelve el `null` en un solo sitio.
describe("maximoSemanalPracticante — el tope de la modalidad, o null si no aplica", () => {
  it("preprofesional: 30 h mientras estudia", () => {
    expect(maximoSemanalPracticante("practicante", "preprofesional")).toBe(30);
  });

  it("profesional: 48 h, ya egresó", () => {
    expect(maximoSemanalPracticante("practicante", "profesional")).toBe(48);
  });

  it("quien no es practicante no tiene tope de modalidad", () => {
    expect(maximoSemanalPracticante("planilla", "preprofesional")).toBeNull();
    expect(maximoSemanalPracticante("rxh", null)).toBeNull();
    expect(maximoSemanalPracticante(null, null)).toBeNull();
  });

  // El null que NO significa «sin límite», sino «falta un dato».
  it("practicante sin modalidad: null, nunca un número inventado", () => {
    expect(maximoSemanalPracticante("practicante", null)).toBeNull();
    expect(maximoSemanalPracticante("practicante", undefined)).toBeNull();
    expect(maximoSemanalPracticante("practicante", "")).toBeNull();
  });
});

describe("topeSemanalDe — contra cuántas horas se mide ESTA persona", () => {
  it("una preprofesional se mide contra 30, no contra las 48 de todos", () => {
    expect(topeSemanalDe("practicante", "preprofesional")).toBe(30);
  });

  it("todo el resto del equipo, contra el tope constitucional", () => {
    expect(topeSemanalDe("planilla", null)).toBe(MAXIMO_LEGAL_SEMANAL);
    expect(topeSemanalDe("prueba", null)).toBe(MAXIMO_LEGAL_SEMANAL);
    expect(topeSemanalDe("rxh", null)).toBe(MAXIMO_LEGAL_SEMANAL);
    expect(topeSemanalDe("practicante", "profesional")).toBe(MAXIMO_LEGAL_SEMANAL);
  });

  // LA DECISIÓN QUE ESTA PRUEBA FIJA, y la que se rompe sola si alguien
  // «simplifica» la función: sin modalidad se cae HACIA ARRIBA.
  //
  // Inventarle 30 a quien quizá sea profesional acusaría de más, y en esta casa
  // el falso positivo es el peor error. Lo que falta ahí es el DATO, y ese hueco
  // se cierra en la ficha de la persona, no en quien la mide.
  it("practicante SIN modalidad se mide contra 48, no contra 30", () => {
    expect(topeSemanalDe("practicante", null)).toBe(MAXIMO_LEGAL_SEMANAL);
    expect(topeSemanalDe("practicante", undefined)).toBe(MAXIMO_LEGAL_SEMANAL);
  });

  it("un dato ausente nunca deja a alguien sin tope", () => {
    expect(topeSemanalDe(null, null)).toBe(MAXIMO_LEGAL_SEMANAL);
    expect(topeSemanalDe(undefined, undefined)).toBe(MAXIMO_LEGAL_SEMANAL);
  });
});

describe("tieneTopePropio — para poder decir de dónde sale el número", () => {
  it("solo la preprofesional, que es la única con un tope más bajo", () => {
    expect(tieneTopePropio("practicante", "preprofesional")).toBe(true);
  });

  it("una practicante profesional NO: su tope es el de todos", () => {
    expect(tieneTopePropio("practicante", "profesional")).toBe(false);
  });

  it("ni el resto del equipo, ni un dato ausente", () => {
    expect(tieneTopePropio("planilla", null)).toBe(false);
    expect(tieneTopePropio("practicante", null)).toBe(false);
    expect(tieneTopePropio(null, null)).toBe(false);
  });
});
