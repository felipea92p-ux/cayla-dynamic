// metas-cobertura.test.ts — la meta de cobertura por rangos (0590)
import { describe, expect, it } from "vitest";
import {
  compararHoraPorHora, lideresDelDia, mananaTarde, metasPorFecha, personalEn, pideEn, problemaDeRangos,
  rangosDesdeSugerido, rangosParaGuardar, type RangoMeta,
} from "../apps/web/lib/admin/metas-cobertura";

const lunes: RangoMeta[] = [
  { desde: 9, hasta: 12, personal: 3, lideres: 1 },
  { desde: 12, hasta: 21, personal: 5, lideres: 1 },
];

describe("metasPorFecha — las filas de la base, por fecha", () => {
  it("agrupa, ordena y guarda de qué meta sale", () => {
    const m = metasPorFecha([
      { fecha: "2026-11-09", desde_min: 720, hasta_min: 1260, personal: 5, lideres: 1, periodo_id: "p", periodo_nombre: "Predeterminada", es_predeterminada: true },
      { fecha: "2026-11-09", desde_min: 540, hasta_min: 720, personal: 3, lideres: 1, periodo_id: "p", periodo_nombre: "Predeterminada", es_predeterminada: true },
      { fecha: "2026-11-14", desde_min: 540, hasta_min: 1260, personal: 9, lideres: null, periodo_id: "c", periodo_nombre: "Campaña", es_predeterminada: false },
    ]);
    expect(m.get("2026-11-09")?.rangos).toEqual(lunes);
    expect(m.get("2026-11-14")?.origen).toEqual({ id: "c", nombre: "Campaña", predeterminada: false });
    expect(m.get("2026-11-10")).toBeUndefined();
  });
});

describe("qué pide la meta a una hora", () => {
  it("el rango que la contiene; el borde de fin no cuenta", () => {
    expect(personalEn(lunes, 9)).toBe(3);
    expect(personalEn(lunes, 11.75)).toBe(3);
    expect(personalEn(lunes, 12)).toBe(5);
    expect(personalEn(lunes, 21)).toBeNull();
    expect(personalEn(lunes, 8)).toBeNull();
  });
  it("manda la meta, aunque sea 0; sin meta manda la venta", () => {
    const conCero: RangoMeta[] = [{ desde: 9, hasta: 12, personal: 0, lideres: null }, { desde: 12, hasta: 18, personal: null, lideres: 1 }];
    expect(pideEn(conCero, 10, 4)).toEqual({ n: 0, de: "meta" });
    expect(pideEn(conCero, 13, 4)).toEqual({ n: 4, de: "venta" });
    expect(pideEn(conCero, 20, null)).toEqual({ n: null, de: null });
  });
});

describe("mananaTarde — lo de la 0039, para las pantallas que cuentan así", () => {
  it("la siembra de la 0039 vuelve a dar lo mismo", () => {
    const sembrada: RangoMeta[] = [{ desde: 0, hasta: 14.25, personal: 6, lideres: 2 }, { desde: 14.25, hasta: 24, personal: 7, lideres: 2 }];
    expect(mananaTarde(sembrada)).toEqual({ manana: 6, tarde: 7, lideres: 2 });
  });
  it("con rangos libres, el mayor de cada lado; sin meta es 0", () => {
    expect(mananaTarde(lunes)).toEqual({ manana: 5, tarde: 5, lideres: 1 });
    expect(mananaTarde([])).toEqual({ manana: 0, tarde: 0, lideres: 0 });
    expect(lideresDelDia([{ desde: 9, hasta: 12, personal: 3, lideres: null }])).toBe(0);
  });
});

describe("comparar con lo que pide la venta", () => {
  const venta: Record<number, number> = { 9: 3, 10: 3, 11: 4, 12: 4, 13: 3 };
  const sugerido = (h: number) => venta[h] ?? null;
  it("hora por hora, con la diferencia", () => {
    const c = compararHoraPorHora(lunes, sugerido, 9, 14);
    expect(c.map((x) => [x.hora, x.meta, x.sugerido, x.diferencia])).toEqual([
      [9, 3, 3, 0], [10, 3, 3, 0], [11, 3, 4, -1], [12, 5, 4, 1], [13, 5, 3, 2],
    ]);
  });
  it("«usar el sugerido» junta las horas que piden lo mismo", () => {
    expect(rangosDesdeSugerido(sugerido, 9, 14)).toEqual([
      { desde: 9, hasta: 11, personal: 3, lideres: null },
      { desde: 11, hasta: 13, personal: 4, lideres: null },
      { desde: 13, hasta: 14, personal: 3, lideres: null },
    ]);
  });
  it("y conserva los líderes que ya pedía la meta", () => {
    const r = rangosDesdeSugerido(sugerido, 9, 13, (h) => (h < 12 ? 1 : 2));
    expect(r.map((x) => `${x.desde}-${x.hasta} ${x.personal}/${x.lideres}`)).toEqual(["9-11 3/1", "11-12 4/1", "12-13 4/2"]);
  });
});

describe("antes de guardar", () => {
  it("dice con palabras lo que la base rechazaría", () => {
    expect(problemaDeRangos(lunes)).toBeNull();
    expect(problemaDeRangos([{ desde: 9, hasta: 13, personal: 3, lideres: 1 }, { desde: 12, hasta: 15, personal: 3, lideres: 1 }]))
      .toBe("Dos rangos se cruzan a las 12:00.");
    expect(problemaDeRangos([{ desde: 13, hasta: 12, personal: 3, lideres: 1 }])).toBe("Un rango termina antes de empezar.");
  });
  it("y lo manda en minutos, por día", () => {
    expect(rangosParaGuardar(new Map([[1, lunes]]))).toEqual([
      { dia: 1, desde_min: 540, hasta_min: 720, personal: 3, lideres: 1 },
      { dia: 1, desde_min: 720, hasta_min: 1260, personal: 5, lideres: 1 },
    ]);
  });
});
