import { describe, expect, it } from "vitest";
import type { MiBono } from "../apps/web/lib/mi-bono";
import { SALUDOS_CUMPLEANOS, esMesDeCumpleanos, saludoInicial } from "../apps/web/lib/saludos-cumpleanos";

const bono = (estado: MiBono["estado"], mes: number | null): MiBono => ({
  estado, mes_cumpleanos: mes, anio: 2026, monto: null, documento_id: null, pedido_el: null, entregado_el: null,
});

describe("saludo de cumpleaños", () => {
  it("son exactamente 16 mensajes, sin repetirse", () => {
    expect(SALUDOS_CUMPLEANOS).toHaveLength(16);
    expect(new Set(SALUDOS_CUMPLEANOS).size).toBe(16);
  });

  it("ninguno promete plata ni nombra el bono: le sale también a quien no lo tiene", () => {
    for (const m of SALUDOS_CUMPLEANOS) {
      expect(m).not.toMatch(/S\/|soles|bono|pago|plata|dinero|\d/i);
      expect(m).not.toMatch(/emplead|jefe|sucursal|RRHH/i);
    }
  });

  it("aparece desde el día 1 hasta el último día del mes, en cualquier estado del bono", () => {
    for (const estado of ["no_aplica", "este_mes", "pedido", "en_boleta", "entregado"] as const) {
      expect(esMesDeCumpleanos(bono(estado, 10), "2026-10-01")).toBe(true);
      expect(esMesDeCumpleanos(bono(estado, 10), "2026-10-31")).toBe(true);
    }
  });

  it("no aparece fuera de su mes, ni sin fecha de nacimiento", () => {
    expect(esMesDeCumpleanos(bono("proximo", 10), "2026-09-30")).toBe(false);
    expect(esMesDeCumpleanos(bono("vencido", 10), "2026-11-01")).toBe(false);
    expect(esMesDeCumpleanos(bono("sin_fecha", null), "2026-10-13")).toBe(false);
    expect(esMesDeCumpleanos(null, "2026-10-13")).toBe(false);
  });

  it("el mensaje inicial cae siempre dentro de la lista, el 31 incluido", () => {
    for (let d = 1; d <= 31; d++) {
      const i = saludoInicial(`2026-10-${String(d).padStart(2, "0")}`);
      expect(i).toBeGreaterThanOrEqual(0);
      expect(i).toBeLessThan(16);
    }
  });
});
