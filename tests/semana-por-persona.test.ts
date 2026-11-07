// semana-por-persona.test.ts — la fila «En piso» de Semana: cómo le fue a cada día
import { describe, expect, it } from "vitest";
import { celdaConNombres, type TurnoConNombre } from "../apps/web/lib/admin/semana-con-nombres";
import { resumenSemanalDelDia, tonoDeHora } from "../apps/web/lib/admin/semana-por-persona";

const t = (nombre: string, entrada: number, salida: number, extra: Partial<TurnoConNombre> = {}): TurnoConNombre =>
  ({ id: nombre.toLowerCase(), nombre, entrada, salida, cuenta: true, lider: false, ...extra });

/** Las celdas de un día tal como las arma la Integrada: filas ancladas a :30, de 08:30 a 21:30. */
function celdas(turnos: TurnoConNombre[], metaEn: (h: number) => number, metaLideres = 0) {
  const horas = Array.from({ length: 13 }, (_, i) => 8.5 + i);
  return horas.map((hora) => celdaConNombres({ turnos, hora, metaEn, metaLideres }));
}

describe("resumenSemanalDelDia", () => {
  it("junta las horas seguidas con falta en un tramo y dice cuánto falta en el peor momento", () => {
    // Mañana: 3 contra meta 4 hasta que llegan dos más a las 13:00. Tarde: meta 2, cubierta.
    const turnos = [t("Ana", 8.5, 17), t("Bea", 8.5, 17), t("Cata", 8.5, 17), t("Dora", 13, 21.5), t("Eva", 13, 21.5)];
    const d = resumenSemanalDelDia(celdas(turnos, (h) => (h < 14.25 ? 4 : 2)), turnos);
    expect(d.estado).toEqual({ tipo: "falta", peor: { desde: 8.5, hasta: 13.5, faltan: 1 }, otrosTramos: 0 });
  });

  it("elige el tramo donde más falta, aunque sea más tarde", () => {
    // De 08:30 a 10:30 faltan 1; desde las 19:00 (fila de 18:30) faltan 2.
    const turnos = [t("Ana", 8.5, 21.5), t("Bea", 8.5, 19), t("Cata", 10.5, 19)];
    const d = resumenSemanalDelDia(celdas(turnos, () => 3), turnos);
    expect(d.estado).toEqual({ tipo: "falta", peor: { desde: 18.5, hasta: 21.5, faltan: 2 }, otrosTramos: 1 });
  });

  it("a igualdad de falta, el tramo más temprano: lo que se ve no cambia de una carga a otra", () => {
    // Falta 1 de 08:30 a 10:30 y falta 1 de 19:30 a 21:30.
    const turnos = [t("Ana", 8.5, 21.5), t("Bea", 10.5, 19.5)];
    const d = resumenSemanalDelDia(celdas(turnos, () => 2), turnos);
    expect(d.estado).toEqual({ tipo: "falta", peor: { desde: 8.5, hasta: 10.5, faltan: 1 }, otrosTramos: 1 });
  });

  it("recorta el tramo a la hora en que la tienda cierra, no al fin de la fila", () => {
    // El domingo de TRU cierra a las 18:15: el tramo con falta no puede decir 18:30.
    const turnos = [t("Ana", 8.5, 18.25), t("Bea", 9.75, 18.25)];
    const d = resumenSemanalDelDia(celdas(turnos, () => 3), turnos);
    expect(d.estado.tipo).toBe("falta");
    if (d.estado.tipo !== "falta") return;
    expect(d.estado.peor.hasta).toBe(18.25);
  });

  it("un día que alcanza en todas sus horas medidas dice «alcanza», aunque sobre gente", () => {
    const turnos = [t("Ana", 8.5, 21.5), t("Bea", 8.5, 21.5), t("Cata", 12, 16)];
    expect(resumenSemanalDelDia(celdas(turnos, () => 2), turnos).estado).toEqual({ tipo: "alcanza" });
  });

  it("sin meta no es «alcanza»: no hay contra qué medir", () => {
    const turnos = [t("Ana", 8.5, 17)];
    expect(resumenSemanalDelDia(celdas(turnos, () => 0), turnos).estado).toEqual({ tipo: "sin_meta" });
  });

  it("un día sin nadie con turno dice «sin gente», no «alcanza» ni «falta»", () => {
    expect(resumenSemanalDelDia(celdas([], () => 4), []).estado).toEqual({ tipo: "sin_gente" });
  });

  it("quien no suma (preselección) no tapa una falta", () => {
    const turnos = [t("Ana", 8.5, 17), t("Sofía", 8.5, 17, { cuenta: false, aparte: "preselección" })];
    const d = resumenSemanalDelDia(celdas(turnos, () => 2), turnos);
    expect(d.estado.tipo).toBe("falta");
  });

  it("junta los tramos sin líder, con la misma regla de la Integrada", () => {
    // La líder entra a las 13:00: de 08:30 a 13:00 hay gente en piso y ninguna líder.
    const turnos = [t("Ana", 8.5, 17), t("Bea", 8.5, 17), t("Lucía", 13, 21.5, { lider: true })];
    const d = resumenSemanalDelDia(celdas(turnos, () => 1, 1), turnos);
    expect(d.sinLider).toEqual([{ desde: 8.5, hasta: 13.5 }]);
  });

  it("el número de cada hora es el de celdaConNombres: Semana no cuenta por su cuenta", () => {
    const turnos = [t("Ana", 8.5, 17), t("Bea", 9.75, 15.25), t("Cata", 13, 21.5, { almacen: [{ desde: 15, hasta: 17 }] })];
    const cs = celdas(turnos, (h) => (h < 14.25 ? 3 : 2));
    const d = resumenSemanalDelDia(cs, turnos);
    // El peor «faltan» es exactamente el máximo de meta − en piso de las celdas medidas.
    const maxFalta = Math.max(...cs.filter((c) => !c.fuera && c.meta > 0).map((c) => c.meta - c.enPiso));
    expect(d.estado.tipo).toBe("falta");
    if (d.estado.tipo === "falta") expect(d.estado.peor.faltan).toBe(maxFalta);
    expect(d.tonos).toEqual(cs.map(tonoDeHora));
  });
});
