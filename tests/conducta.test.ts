// Faltas de conducta: lo que la pantalla decide antes de llamar a la base.
// Lo que importa acá: que la pantalla no ofrezca a nadie lo que la base (0510)
// va a rechazar, y que diga qué falta para guardar en el orden del formulario.

import { describe, it, expect } from "vitest";
import { puedeTramitarDisciplina } from "@cayla-dynamic/shared";
import {
  accionDeTraspaso, casoBloqueadoParaMi, citaDeFalta, faltasElegibles, puedeRegistrarleConducta, queFaltaParaRegistrar,
  traspasosDe,
  type BorradorConducta, type Candidata, type FaltaCatalogo, type QuienRegistra, type Traspaso,
} from "@/lib/admin/conducta";

const falta = (numeral: string, literal: string, extra: Partial<FaltaCatalogo> = {}): FaltaCatalogo => ({
  rit_version: 4, numeral, literal, gravedad: numeral === "53.1" ? "leve" : "significativa",
  texto: `texto ${numeral} ${literal}`, se_registra_a_mano: true, rotulo: null, ...extra,
});

describe("puedeTramitarDisciplina", () => {
  it("DO tramita aunque no esté en planilla: tramitar no es imponer", () => {
    expect(puedeTramitarDisciplina("lider_do", false)).toBe(true);
    expect(puedeTramitarDisciplina("admin", false)).toBe(true);
  });
  it("la líder solo con contrato de trabajo (RIT 2.9)", () => {
    expect(puedeTramitarDisciplina("supervisor_sede", true)).toBe(true);
    expect(puedeTramitarDisciplina("supervisor_sede", false)).toBe(false);
  });
  it("sin dato del vínculo, no: un null no pasa por autorizado", () => {
    expect(puedeTramitarDisciplina("supervisor_sede", null)).toBe(false);
    expect(puedeTramitarDisciplina("supervisor_sede", undefined)).toBe(false);
  });
  it("una integrante nunca", () => {
    expect(puedeTramitarDisciplina("integrante", true)).toBe(false);
    expect(puedeTramitarDisciplina(null, true)).toBe(false);
  });
});

describe("puedeRegistrarleConducta", () => {
  const lider: QuienRegistra = { id: "L", rol: "supervisor_sede", sedeBaseId: "TRU", enPlanilla: true };
  const integrante: Candidata = { id: "I", rol: "integrante", sede_base_id: "TRU", estado: "activo", en_planilla: true };

  it("la líder registra a una integrante de su sede", () => {
    expect(puedeRegistrarleConducta(lider, integrante)).toBe(true);
  });
  it("no a otra líder: a una líder la amonesta DO", () => {
    expect(puedeRegistrarleConducta(lider, { ...integrante, rol: "supervisor_sede" })).toBe(false);
  });
  it("no a sí misma", () => {
    expect(puedeRegistrarleConducta(lider, { ...integrante, id: "L" })).toBe(false);
  });
  it("no a alguien de otra sede", () => {
    expect(puedeRegistrarleConducta(lider, { ...integrante, sede_base_id: "AQP" })).toBe(false);
  });
  it("no a quien el régimen disciplinario no alcanza: practicante o por honorarios (RIT 2.5, 2.6), ni a quien ya no está", () => {
    expect(puedeRegistrarleConducta(lider, { ...integrante, en_planilla: false })).toBe(false);
    expect(puedeRegistrarleConducta(lider, { ...integrante, estado: "inactivo" })).toBe(false);
  });
  it("una líder por honorarios no registra a nadie", () => {
    expect(puedeRegistrarleConducta({ ...lider, enPlanilla: false }, integrante)).toBe(false);
  });
  it("DO registra a cualquiera con contrato, también a una líder, de cualquier sede", () => {
    const dop: QuienRegistra = { id: "D", rol: "lider_do", sedeBaseId: "CCO", enPlanilla: false };
    expect(puedeRegistrarleConducta(dop, { ...integrante, rol: "supervisor_sede", sede_base_id: "AQP" })).toBe(true);
    expect(puedeRegistrarleConducta(dop, { ...integrante, id: "D" })).toBe(false);
  });
});

describe("faltasElegibles", () => {
  it("solo la versión vigente del RIT, y solo lo que se registra a mano", () => {
    const { leves, significativas } = faltasElegibles([
      falta("53.1", "d"),
      falta("53.1", "a", { rit_version: 3.2 }),               // versión vieja: fuera
      falta("53.2", "b", { se_registra_a_mano: false }),     // la mide el motor: fuera
      falta("53.2", "h"),
      falta("53.2", "g"),
    ]);
    expect(leves.map((f) => f.literal)).toEqual(["d"]);
    expect(significativas.map((f) => f.literal)).toEqual(["g", "h"]);
  });
  it("la versión vigente es la MAYOR como número: 10.0 va después de 4.0", () => {
    const { leves } = faltasElegibles([falta("53.1", "d", { rit_version: 4 }), falta("53.1", "c", { rit_version: 10 })]);
    expect(leves.map((f) => f.literal)).toEqual(["c"]);
  });
});

describe("citaDeFalta", () => {
  it("cita numeral y literal, como pide el RIT 55.3", () => {
    expect(citaDeFalta({ numeral: "53.2", literal: "h" })).toBe("literal h) del numeral 53.2");
  });
});

describe("queFaltaParaRegistrar", () => {
  const hoy = "2026-10-06";
  const completo: BorradorConducta = {
    personaId: "I", falta: { numeral: "53.2", literal: "h" }, fechaHecho: "2026-10-02", conocidoEl: "2026-10-03",
    relato: "Le respondió de mala manera a una clienta delante de otras dos.", nivel: "amonestacion",
  };

  it("completo, se puede guardar", () => {
    expect(queFaltaParaRegistrar(completo, hoy)).toBeNull();
  });
  it("dice el SIGUIENTE paso, en el orden del formulario", () => {
    expect(queFaltaParaRegistrar({ ...completo, personaId: null, falta: null }, hoy)).toBe("Elige a quién.");
    expect(queFaltaParaRegistrar({ ...completo, falta: null, nivel: null }, hoy)).toBe("Elige qué falta fue.");
  });
  it("las mismas fechas que rechaza la base", () => {
    expect(queFaltaParaRegistrar({ ...completo, fechaHecho: "2026-10-07" }, hoy)).toMatch(/futura/);
    expect(queFaltaParaRegistrar({ ...completo, conocidoEl: "2026-10-07" }, hoy)).toMatch(/futura/);
    expect(queFaltaParaRegistrar({ ...completo, conocidoEl: "2026-10-01" }, hoy)).toMatch(/antes de que pasara/);
    expect(queFaltaParaRegistrar({ ...completo, conocidoEl: completo.fechaHecho }, hoy)).toBeNull();
  });
  it("un relato de una palabra no es un hecho; los espacios no cuentan", () => {
    expect(queFaltaParaRegistrar({ ...completo, relato: "Teléfono." }, hoy)).toMatch(/Cuenta qué pasó/);
    expect(queFaltaParaRegistrar({ ...completo, relato: "   corto                      " }, hoy)).toMatch(/Cuenta qué pasó/);
  });
  it("sin nivel elegido, no se guarda", () => {
    expect(queFaltaParaRegistrar({ ...completo, nivel: null }, hoy)).toBe("Elige qué vas a hacer.");
  });
});

describe("accionDeTraspaso", () => {
  const libre = { estado: "borrador", tomado_por: null };
  it("DO toma un caso que inició una líder y nadie tiene", () => {
    expect(accionDeTraspaso(libre, "supervisor_sede", true)).toBe("tomar");
  });
  it("y lo devuelve cuando ya lo tiene", () => {
    expect(accionDeTraspaso({ ...libre, tomado_por: "D" }, "supervisor_sede", true)).toBe("devolver");
  });
  it("lo que inició DO ya está con DO: no hay nada que tomar", () => {
    expect(accionDeTraspaso(libre, "lider_do", true)).toBeNull();
    expect(accionDeTraspaso(libre, "admin", true)).toBeNull();
  });
  it("lo anulado no se toma, ni se devuelve", () => {
    expect(accionDeTraspaso({ estado: "anulado", tomado_por: null }, "supervisor_sede", true)).toBeNull();
    expect(accionDeTraspaso({ estado: "anulado", tomado_por: "D" }, "supervisor_sede", true)).toBeNull();
  });
  it("la líder no toma ni devuelve: sin permiso, ningún botón", () => {
    expect(accionDeTraspaso(libre, "supervisor_sede", false)).toBeNull();
    expect(accionDeTraspaso({ ...libre, tomado_por: "D" }, "supervisor_sede", false)).toBeNull();
  });
  it("sin saber quién lo inició, no se ofrece tomar", () => {
    expect(accionDeTraspaso(libre, null, true)).toBeNull();
    expect(accionDeTraspaso(libre, undefined, true)).toBeNull();
  });
});

describe("casoBloqueadoParaMi", () => {
  const tomado = { tomado_por: "D", persona_id: "I" };
  it("la líder ve bloqueado el caso que tomó DO", () => {
    expect(casoBloqueadoParaMi(tomado, { id: "L", rol: "supervisor_sede" })).toBe(true);
  });
  it("si nadie lo tomó, no hay bloqueo", () => {
    expect(casoBloqueadoParaMi({ ...tomado, tomado_por: null }, { id: "L", rol: "supervisor_sede" })).toBe(false);
  });
  it("DO no se bloquea a sí misma", () => {
    expect(casoBloqueadoParaMi(tomado, { id: "D", rol: "lider_do" })).toBe(false);
  });
  it("la persona del documento no queda atrapada, aunque sea líder: sigue pudiendo responder a su memo", () => {
    expect(casoBloqueadoParaMi(tomado, { id: "I", rol: "supervisor_sede" })).toBe(false);
  });
  it("sin sesión cargada, no se bloquea nada que no se sepa", () => {
    expect(casoBloqueadoParaMi(tomado, null)).toBe(false);
  });
});

describe("traspasosDe", () => {
  const t = (id: string, exp: string, hecho_at: string): Traspaso =>
    ({ id, expediente_id: exp, accion: "tomar", por: "D", motivo: "m", hecho_at });
  it("solo los de ese caso, del más nuevo al más viejo", () => {
    const lista = [t("1", "A", "2026-10-01T10:00:00Z"), t("2", "B", "2026-10-02T10:00:00Z"), t("3", "A", "2026-10-03T10:00:00Z")];
    expect(traspasosDe(lista, "A").map((x) => x.id)).toEqual(["3", "1"]);
    expect(traspasosDe(lista, "Z")).toEqual([]);
  });
});
