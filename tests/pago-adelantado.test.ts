import { describe, expect, it, vi } from "vitest";
import { hoyLima } from "@cayla-dynamic/shared";
import {
  PALABRA_PAGO_ADELANTADO, confirmaPagoAdelantado, diasQueFaltanParaTerminar, textoDiasQueFaltan,
} from "@/lib/admin/planilla/pago-adelantado";

// El caso real del 2026-10-21: periodo 28-sep → 28-oct, pagado el grupo planilla a las 15:27.
describe("diasQueFaltanParaTerminar", () => {
  it("el incidente: el 21 de octubre le faltaban 7 días a un periodo que cierra el 28", () => {
    expect(diasQueFaltanParaTerminar("2026-10-28", "2026-10-21")).toBe(7);
  });

  it("la víspera del cierre falta 1 día", () => {
    expect(diasQueFaltanParaTerminar("2026-10-28", "2026-10-27")).toBe(1);
  });

  it("el día del cierre ya no avisa (la regla es «fecha_fin posterior a hoy»)", () => {
    expect(diasQueFaltanParaTerminar("2026-10-28", "2026-10-28")).toBe(0);
  });

  it("un periodo que ya cerró nunca avisa, sea cuando sea", () => {
    expect(diasQueFaltanParaTerminar("2026-10-28", "2026-10-29")).toBe(0);
    expect(diasQueFaltanParaTerminar("2026-10-28", "2027-03-01")).toBe(0);
  });

  it("cuenta bien al cruzar mes y año, y en febrero bisiesto", () => {
    expect(diasQueFaltanParaTerminar("2027-01-05", "2026-12-30")).toBe(6);
    expect(diasQueFaltanParaTerminar("2028-03-01", "2028-02-27")).toBe(3);
  });

  it("solo importa cuándo cierra: un periodo que ni empezó también avisa", () => {
    expect(diasQueFaltanParaTerminar("2026-11-28", "2026-10-21")).toBe(38);
  });

  it("con hoyLima(): a las 9 pm de Lima ya es el día siguiente en UTC, y aun así falta 1 día", () => {
    vi.useFakeTimers();
    try {
      // 2026-10-28T02:00Z = 27 de octubre, 21:00 en Lima.
      vi.setSystemTime(new Date("2026-10-28T02:00:00Z"));
      expect(hoyLima()).toBe("2026-10-27");
      expect(diasQueFaltanParaTerminar("2026-10-28", hoyLima())).toBe(1);
    } finally {
      vi.useRealTimers();
    }
  });
});

describe("textoDiasQueFaltan", () => {
  it("singular y plural", () => {
    expect(textoDiasQueFaltan(1)).toBe("Falta 1 día");
    expect(textoDiasQueFaltan(7)).toBe("Faltan 7 días");
  });
});

describe("confirmaPagoAdelantado", () => {
  it("acepta la palabra sin importar mayúsculas ni espacios de los lados", () => {
    expect(confirmaPagoAdelantado(PALABRA_PAGO_ADELANTADO)).toBe(true);
    expect(confirmaPagoAdelantado("  Adelantar ")).toBe(true);
    expect(confirmaPagoAdelantado("ADELANTAR")).toBe(true);
  });

  it("no acepta vacío, una palabra parecida ni una parte", () => {
    expect(confirmaPagoAdelantado("")).toBe(false);
    expect(confirmaPagoAdelantado("   ")).toBe(false);
    expect(confirmaPagoAdelantado("adelantado")).toBe(false);
    expect(confirmaPagoAdelantado("adelant")).toBe(false);
    expect(confirmaPagoAdelantado("octubre")).toBe(false);
  });

  it("no es el mes: esa es la palabra de «Eliminar periodo»", () => {
    for (const mes of ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"]) {
      expect(confirmaPagoAdelantado(mes)).toBe(false);
    }
  });
});
