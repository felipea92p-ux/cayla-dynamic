// piso-venta.test.ts — la tendencia «Gente en piso frente a la venta» junta días; no decide quién estaba en piso
import { describe, expect, it } from "vitest";
import { esDelTipo, faltaSeguido, horaMasCorta, MINIMO_DIAS_HORA, pisoPorHora, type DiaDePiso } from "../apps/web/lib/admin/piso-venta";

const hora = (h: number, enPiso: number, compras: number | null, pedia: number | null) => ({ hora: h, enPiso, compras, pedia });
// 2026-11-02 es lunes; 2026-11-07 sábado; 2026-11-08 domingo.
const dia = (fecha: string, horas: ReturnType<typeof hora>[]): DiaDePiso => ({ fecha, horas });

describe("esDelTipo", () => {
  it("lunes a viernes contra sábado y domingo", () => {
    expect(esDelTipo("2026-11-02", "semana")).toBe(true);
    expect(esDelTipo("2026-11-07", "semana")).toBe(false);
    expect(esDelTipo("2026-11-08", "finde")).toBe(true);
    expect(esDelTipo("2026-11-08", "todos")).toBe(true);
  });
});

describe("pisoPorHora — promedia cada hora sobre los días en que la tienda estuvo abierta a esa hora", () => {
  const dias = [
    dia("2026-11-02", [hora(10, 2, 1, 3), hora(19, 3, 9, 6)]),
    dia("2026-11-03", [hora(10, 3, 2, 3), hora(19, 3, 3, 3)]),
    dia("2026-11-07", [hora(19, 2, 12, 8)]),
  ];
  it("promedios con un decimal y días con falta", () => {
    expect(pisoPorHora(dias, "todos")).toEqual([
      { hora: 10, dias: 2, compras: 1.5, enPiso: 2.5, pedia: 3, conFalta: 1 },
      { hora: 19, dias: 3, compras: 8, enPiso: 2.7, pedia: 5.7, conFalta: 2 },
    ]);
  });
  it("el filtro de días deja fuera los otros", () => {
    expect(pisoPorHora(dias, "finde")).toEqual([{ hora: 19, dias: 1, compras: 12, enPiso: 2, pedia: 8, conFalta: 1 }]);
  });
  it("sin compras leídas no hay promedio de venta ni de lo que pedía, y no se cuenta falta", () => {
    const r = pisoPorHora([dia("2026-11-02", [hora(10, 2, null, null)])], "todos");
    expect(r[0]).toMatchObject({ compras: null, pedia: null, conFalta: 0, enPiso: 2 });
  });
});

describe("horaMasCorta y faltaSeguido — una hora con pocos días no se juzga", () => {
  const h = (hr: number, dias: number, conFalta: number) => ({ hora: hr, dias, compras: 1, enPiso: 1, pedia: 1, conFalta });
  it("la de mayor proporción; entre empatadas, la de más días con falta", () => {
    expect(horaMasCorta([h(18, 10, 4), h(19, 20, 9), h(20, 8, 4)])?.hora).toBe(20);
    expect(horaMasCorta([h(18, 10, 5), h(19, 20, 10)])?.hora).toBe(19);
  });
  it(`con menos de ${MINIMO_DIAS_HORA} días, ni encabeza ni se marca`, () => {
    expect(horaMasCorta([h(21, 3, 3)])).toBeNull();
    expect(faltaSeguido(h(21, 3, 3))).toBe(false);
    expect(faltaSeguido(h(19, 8, 4))).toBe(true);
    expect(faltaSeguido(h(19, 8, 3))).toBe(false);
  });
  it("sin ninguna falta no hay hora que señalar", () => {
    expect(horaMasCorta([h(10, 20, 0)])).toBeNull();
  });
});
