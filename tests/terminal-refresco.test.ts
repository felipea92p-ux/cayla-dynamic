// ============================================================================
// terminal-refresco.test.ts — cuándo el terminal vuelve a preguntar
// ============================================================================
// La regla de `lib/terminal/refresco.ts`, nacida de medir producción el
// 2026-10-30 (la memoria de la base en «SEVERE»): las sugerencias se piden al
// arrancar, al cambiar de día y cada 15 min, no en cada refresco de la lista.
// La otra regla de ese día —la pestaña oculta no lee— vive desde el 2026-11-07 en
// `useAlDia` (lib/tiempo-real.ts) y se prueba en tests/tiempo-real.test.ts.
// Lo que más importa probar es lo que NO debe callarse: una carga vacía o un
// día nuevo siempre vuelven a pedir.
// ============================================================================
import { describe, it, expect } from "vitest";
import { VIGENCIA_SUGERENCIAS_MS, sugerenciasVencidas } from "@/lib/terminal/refresco";

const DIA = "2026-10-30";
const T0 = Date.parse("2026-10-30T14:00:00-05:00");

describe("sugerenciasVencidas", () => {
  it("sin carga previa (o la última vino vacía) siempre pide", () => {
    expect(sugerenciasVencidas(null, DIA, T0)).toBe(true);
  });

  it("dentro de la vigencia y el mismo día, no pide", () => {
    const ultima = { dia: DIA, ms: T0 };
    expect(sugerenciasVencidas(ultima, DIA, T0)).toBe(false);
    expect(sugerenciasVencidas(ultima, DIA, T0 + 60_000)).toBe(false);
    expect(sugerenciasVencidas(ultima, DIA, T0 + VIGENCIA_SUGERENCIAS_MS - 1)).toBe(false);
  });

  it("al cumplirse la vigencia, vuelve a pedir", () => {
    expect(sugerenciasVencidas({ dia: DIA, ms: T0 }, DIA, T0 + VIGENCIA_SUGERENCIAS_MS)).toBe(true);
  });

  it("al cambiar el día en Lima pide aunque haya pasado un minuto", () => {
    // 23:59 → 00:00: el horario esperado y los turnos son de otro día.
    expect(sugerenciasVencidas({ dia: "2026-10-29", ms: T0 - 60_000 }, DIA, T0)).toBe(true);
  });

  it("si el reloj de la Mac retrocedió, pide (mejor una consulta de más)", () => {
    expect(sugerenciasVencidas({ dia: DIA, ms: T0 }, DIA, T0 - 1)).toBe(true);
  });

  it("en un día abierto pide unas 4 veces por hora, no 60", () => {
    let ultima: { dia: string; ms: number } | null = null;
    let pedidas = 0;
    for (let minuto = 0; minuto < 60; minuto++) {
      const ahora = T0 + minuto * 60_000;
      if (sugerenciasVencidas(ultima, DIA, ahora)) {
        pedidas++;
        ultima = { dia: DIA, ms: ahora };
      }
    }
    expect(pedidas).toBe(4);
  });
});
