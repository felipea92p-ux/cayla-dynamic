import { describe, expect, it } from "vitest";
import {
  bandaLocacion,
  cuantasParaAtender,
  ESTADO_PERSONA,
  fechasSugeridas,
  textoPlazo,
  type FilaTableroLocacion,
} from "../apps/web/lib/admin/locaciones";

// La pestaña «Recibo por honorarios» (0610). El estado lo decide la base; aquí
// solo se prueba cómo se agrupa y cómo se dice.

const fila = (estado: FilaTableroLocacion["estado"], dias: number | null): FilaTableroLocacion => ({
  persona_id: estado, persona: "Prueba", sede: "TRU", contrato_id: null, servicio: null,
  fecha_inicio: null, cubierto_hasta: null, dias_restantes: dias, n_contratos: 0, estado,
});

describe("bandas de la pestaña", () => {
  it("vencido y sin contrato van juntos: los dos trabajan sin contrato vigente", () => {
    expect(bandaLocacion("vencido")).toBe("sin_cubrir");
    expect(bandaLocacion("sin_contrato")).toBe("sin_cubrir");
  });
  it("vence pronto es su propia banda; por empezar y vigente están al día", () => {
    expect(bandaLocacion("por_vencer")).toBe("pronto");
    expect(bandaLocacion("por_empezar")).toBe("al_dia");
    expect(bandaLocacion("vigente")).toBe("al_dia");
  });
  it("el número rojo de la pestaña cuenta solo lo que pide algo", () => {
    const filas = [fila("vencido", -3), fila("sin_contrato", null), fila("por_vencer", 10), fila("vigente", 200), fila("por_empezar", 300)];
    expect(cuantasParaAtender(filas)).toBe(3);
  });
});

describe("cómo se dice el plazo", () => {
  it("cuenta hacia adelante y hacia atrás, en singular cuando toca", () => {
    expect(textoPlazo(fila("vencido", -1))).toBe("Venció ayer");
    expect(textoPlazo(fila("vencido", -12))).toBe("Venció hace 12 días");
    expect(textoPlazo(fila("por_vencer", 0))).toBe("Vence hoy");
    expect(textoPlazo(fila("por_vencer", 1))).toBe("Vence mañana");
    expect(textoPlazo(fila("por_vencer", 40))).toBe("Vence en 40 días");
  });
  it("sin contrato no hay plazo que decir", () => {
    expect(textoPlazo(fila("sin_contrato", null))).toBeNull();
  });
  it("ningún estado va en rojo: en Contratos el rojo es solo del art. 77", () => {
    for (const e of Object.values(ESTADO_PERSONA)) expect(e.variante).not.toBe("alerta");
  });
});

describe("las fechas con que nace el formulario de registrar", () => {
  it("sin contrato, o con uno ya vencido: empieza hoy, dura seis meses y se firma hoy", () => {
    expect(fechasSugeridas({ cubierto_hasta: null }, "2026-11-09")).toEqual({ inicio: "2026-11-09", fin: "2027-05-08", firma: "2026-11-09" });
    expect(fechasSugeridas({ cubierto_hasta: "2026-10-28" }, "2026-11-09").inicio).toBe("2026-11-09");
  });
  it("cubierta hasta una fecha futura: lo probable es la renovación, que empieza al día siguiente", () => {
    expect(fechasSugeridas({ cubierto_hasta: "2026-12-04" }, "2026-11-09")).toEqual({ inicio: "2026-12-05", fin: "2027-06-04", firma: "2026-11-09" });
  });
  it("si vence hoy, la siguiente empieza mañana", () => {
    expect(fechasSugeridas({ cubierto_hasta: "2026-11-09" }, "2026-11-09").inicio).toBe("2026-11-10");
  });
  it("el fin de mes no se desborda: del 31 de agosto, seis meses llegan al 28 de febrero", () => {
    expect(fechasSugeridas({ cubierto_hasta: null }, "2026-08-31").fin).toBe("2027-02-27");
  });
});
