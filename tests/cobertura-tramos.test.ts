// cobertura-tramos.test.ts — «Mañana 2 de 3», «Tarde completo»
import { describe, expect, it } from "vitest";
import { CORTE_TRAMO, horasEnTramo, personasDelTramo, resumenDeLideres, resumenDelTramo, type TurnoDecimal } from "../apps/web/lib/admin/cobertura-tramos";

const t = (id: string, entrada: number, salida: number): TurnoDecimal => ({ id, entrada, salida });
const DIA = { inicioDia: 7, finDia: 21 };

describe("personasDelTramo", () => {
  it("cuenta a quien trabaja ≥ 3 h dentro del tramo", () => {
    const gaby = t("gaby", 8.75, 18);        // mañana 5.5 h, tarde 3.75 h → en las dos
    const carla = t("carla", 8, 14.25);      // solo mañana
    const bruno = t("bruno", 14.25, 21);     // solo tarde
    const turnos = [gaby, carla, bruno];
    expect(personasDelTramo(turnos, "manana", DIA.inicioDia, DIA.finDia).map((x) => x.id)).toEqual(["gaby", "carla"]);
    expect(personasDelTramo(turnos, "tarde", DIA.inicioDia, DIA.finDia).map((x) => x.id)).toEqual(["gaby", "bruno"]);
  });

  it("quien solo pasa un rato por el tramo no lo cubre", () => {
    expect(personasDelTramo([t("x", 12.5, 15.5)], "manana", 7, 21)).toHaveLength(0); // 1.75 h de mañana
    expect(horasEnTramo(t("x", 12.5, 15.5), 7, CORTE_TRAMO)).toBeCloseTo(1.75);
  });
});

describe("resumenDelTramo", () => {
  const dos = [t("a", 8, 14.25), t("b", 8.75, 14.25)];

  it("sin meta: nunca falta ni sobra, dice «sin_meta»", () => {
    expect(resumenDelTramo({ turnos: dos, tramo: "manana", meta: 0, ...DIA }).estado).toBe("sin_meta");
  });

  it("2 de 3: falta 1", () => {
    expect(resumenDelTramo({ turnos: dos, tramo: "manana", meta: 3, ...DIA })).toMatchObject({ n: 2, meta: 3, estado: "falta", faltan: 1 });
  });

  it("2 de 2: completo", () => {
    expect(resumenDelTramo({ turnos: dos, tramo: "manana", meta: 2, ...DIA }).estado).toBe("completo");
  });

  it("entradas escalonadas (una persona llega 45 min antes) no son hueco", () => {
    expect(resumenDelTramo({ turnos: [t("a", 8, 14.25), t("b", 8.75, 14.25)], tramo: "manana", meta: 2, ...DIA }).estado).toBe("completo");
  });

  it("3 de 2: sobra 1", () => {
    const tres = [...dos, t("c", 8, 14.25)];
    expect(resumenDelTramo({ turnos: tres, tramo: "manana", meta: 2, ...DIA })).toMatchObject({ estado: "sobra", sobran: 1 });
  });

  it("el número da, pero una persona sale en medio y queda 1 donde la meta pide 2: «con_huecos», no «completo»", () => {
    // b (8–11) cuenta como del tramo (3 h), pero de 11 a 14:15 solo queda a.
    const r = resumenDelTramo({ turnos: [t("a", 8, 14.25), t("b", 8, 11)], tramo: "manana", meta: 2, ...DIA });
    expect(r).toMatchObject({ n: 2, estado: "con_huecos" });
  });

  it("dos personas que nunca coinciden tampoco «completan» un tramo de meta 2", () => {
    const r = resumenDelTramo({ turnos: [t("a", 7.5, 10.5), t("b", 11.25, 14.25)], tramo: "manana", meta: 2, ...DIA });
    expect(r.estado).toBe("con_huecos");
  });
});

describe("resumenDeLideres", () => {
  it("sin meta: no se mide", () => expect(resumenDeLideres(1, 0).estado).toBe("sin_meta"));
  it("ningún líder con meta 1: falta 1", () => expect(resumenDeLideres(0, 1)).toMatchObject({ estado: "falta", faltan: 1 }));
  it("1 de 1: completo", () => expect(resumenDeLideres(1, 1).estado).toBe("completo"));
  it("2 de 1: sobra 1", () => expect(resumenDeLideres(2, 1)).toMatchObject({ estado: "sobra", sobran: 1 }));
});
