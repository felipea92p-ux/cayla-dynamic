// semana-con-nombres.test.ts — la semana de Turnos hora por hora, con nombres
import { describe, expect, it } from "vitest";
import { celdaConNombres, horasDeLaSemana, resumenDelDia, ventanaDeTurnos, type TurnoConNombre } from "../apps/web/lib/admin/semana-con-nombres";

const t = (nombre: string, entrada: number, salida: number, extra: Partial<TurnoConNombre> = {}): TurnoConNombre =>
  ({ id: nombre.toLowerCase(), nombre, entrada, salida, cuenta: true, lider: false, ...extra });
const META_PLANA = () => 3;

describe("celdaConNombres", () => {
  it("lista a todas las que pasan por la hora, con la hora exacta de quien entra o sale dentro", () => {
    const c = celdaConNombres({
      turnos: [t("Diana", 8.5, 20.25), t("Melany", 10.75, 18), t("Janis", 8.5, 13.25)],
      hora: 13, metaEn: META_PLANA, metaLideres: 0,
    });
    expect(c.gente.map((g) => g.nombre)).toEqual(["Diana", "Janis", "Melany"]);
    expect(c.gente.find((g) => g.nombre === "Janis")!.sale).toBe(13.25);
    expect(c.gente.find((g) => g.nombre === "Diana")!.sale).toBeNull();
    const entraTarde = celdaConNombres({ turnos: [t("Melany", 10.75, 18), t("Diana", 8.5, 20)], hora: 10, metaEn: META_PLANA, metaLideres: 0 });
    expect(entraTarde.gente.find((g) => g.nombre === "Melany")!.entra).toBe(10.75);
  });

  it("cuenta el peor momento de la hora, no a cualquiera que la toque", () => {
    // Janis se va a las 13:15: de 13:15 a 14:00 solo queda Diana. La Integrada diría 2.
    const c = celdaConNombres({ turnos: [t("Diana", 8.5, 20.25), t("Janis", 8.5, 13.25)], hora: 13, metaEn: META_PLANA, metaLideres: 0 });
    expect(c.gente).toHaveLength(2);
    expect(c.enPiso).toBe(1);
  });

  it("quien no cuenta sale en la lista pero no suma, y conserva su motivo", () => {
    const c = celdaConNombres({
      turnos: [t("Diana", 8, 20), t("Lesly", 8, 13, { cuenta: false, aparte: "preselección" })],
      hora: 9, metaEn: META_PLANA, metaLideres: 0,
    });
    expect(c.enPiso).toBe(1);
    expect(c.gente.find((g) => g.nombre === "Lesly")).toMatchObject({ cuenta: false, aparte: "preselección" });
  });

  it("las líderes van primero y se cuentan aparte", () => {
    const c = celdaConNombres({
      turnos: [t("Ana", 8, 20), t("Janis", 8, 20, { lider: true }), t("Berta", 8, 20)],
      hora: 10, metaEn: META_PLANA, metaLideres: 1,
    });
    expect(c.gente[0].nombre).toBe("Janis");
    expect(c.lideres).toBe(1);
    expect(c.sinLider).toBe(false);
  });

  it("avisa sin líder solo si hay gente, hay meta de líderes y en algún momento no queda ninguna", () => {
    const turnos = [t("Ana", 8, 20), t("Janis", 8, 12.5, { lider: true })];
    expect(celdaConNombres({ turnos, hora: 12, metaEn: META_PLANA, metaLideres: 1 }).sinLider).toBe(true);
    expect(celdaConNombres({ turnos, hora: 12, metaEn: META_PLANA, metaLideres: 0 }).sinLider).toBe(false);
    expect(celdaConNombres({ turnos, hora: 10, metaEn: META_PLANA, metaLideres: 1 }).sinLider).toBe(false);
  });

  it("una hora que cruza el corte mañana/tarde toma la meta más alta", () => {
    const metaEn = (h: number) => (h >= 14.25 ? 5 : 3);
    expect(celdaConNombres({ turnos: [t("Ana", 8, 20)], hora: 14, metaEn, metaLideres: 0 }).meta).toBe(5);
    expect(celdaConNombres({ turnos: [t("Ana", 8, 20)], hora: 13, metaEn, metaLideres: 0 }).meta).toBe(3);
  });

  it("lo que queda fuera de la primera entrada y la última salida del día no se mide", () => {
    // El domingo de TRU cierra a las 18:15: de 19:00 a 20:00 no es una falta.
    const domingo = [t("Ana", 8.5, 18.25), t("Berta", 10, 18.25)];
    const c = celdaConNombres({ turnos: domingo, hora: 19, metaEn: META_PLANA, metaLideres: 1 });
    expect(c).toMatchObject({ fuera: true, enPiso: 0, meta: 0, sinLider: false });
    expect(c.gente).toHaveLength(0);
    // La hora del cierre sí se mide, en los cuartos que siguen abiertos.
    expect(celdaConNombres({ turnos: domingo, hora: 18, metaEn: META_PLANA, metaLideres: 0 })).toMatchObject({ fuera: false, enPiso: 2 });
  });

  it("un día sin nadie que cuente ni lidere queda fuera entero", () => {
    const c = celdaConNombres({ turnos: [t("Lesly", 8, 13, { cuenta: false })], hora: 9, metaEn: META_PLANA, metaLideres: 1 });
    expect(c.fuera).toBe(true);
    expect(c.gente).toHaveLength(1); // se nombra igual: está en la tienda
  });

  it("un borde exacto no cuenta doble: quien sale a las 14:00 no está en la hora de las 14", () => {
    const c = celdaConNombres({ turnos: [t("Ana", 8, 14), t("Berta", 14, 20)], hora: 14, metaEn: META_PLANA, metaLideres: 0 });
    expect(c.gente.map((g) => g.nombre)).toEqual(["Berta"]);
    expect(c.enPiso).toBe(1);
  });
});

describe("horasDeLaSemana y ventanaDeTurnos", () => {
  it("dibuja de la primera entrada a la última salida de cualquier día, en horas en punto", () => {
    expect(horasDeLaSemana([[t("A", 8.5, 14.5)], [t("B", 13.25, 20.25)]])).toEqual([8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]);
    expect(horasDeLaSemana([[], []])).toEqual([]);
  });
  it("la ventana del día ignora a quien no cuenta ni lidera", () => {
    expect(ventanaDeTurnos([t("A", 9, 18), t("X", 7, 21, { cuenta: false })])).toEqual({ desde: 9, hasta: 18 });
    expect(ventanaDeTurnos([])).toBeNull();
  });
});

describe("resumenDelDia", () => {
  it("suma las horas en tienda con el refrigerio adentro, y promedia el peor momento de las horas medidas", () => {
    const turnos = [t("Ana", 8, 14), t("Berta", 10, 16)];
    const celdas = [8, 9, 10, 11, 12, 13, 14, 15, 16, 17].map((hora) => celdaConNombres({ turnos, hora, metaEn: () => 2, metaLideres: 0 }));
    const r = resumenDelDia(celdas, turnos);
    expect(r.horasEnTienda).toBe(12);
    expect(r.personas).toBe(2);
    // medidas: de 8 a 16 → 8 horas; en piso 1,1,2,2,2,2,1,1
    expect(r.promedioEnPiso).toBe(1.5);
    expect(r.horasConFalta).toBe(4);
  });
  it("un día sin nadie no inventa un promedio", () => {
    expect(resumenDelDia([celdaConNombres({ turnos: [], hora: 9, metaEn: () => 3, metaLideres: 0 })], [])).toEqual({ horasEnTienda: 0, personas: 0, promedioEnPiso: null, horasConFalta: 0 });
  });
});
