import { describe, it, expect } from "vitest";
import { cicloVigente, type DiaTrabajado } from "@/lib/admin/ciclo-sobretiempo";

// N días consecutivos de `h` horas, empezando en `desde` (ISO).
function racha(desde: string, n: number, h: number): DiaTrabajado[] {
  const [y, m, d] = desde.split("-").map(Number);
  return Array.from({ length: n }, (_, i) => {
    const dt = new Date(Date.UTC(y, m - 1, d + i));
    return { fecha: dt.toISOString().slice(0, 10), horas: h };
  });
}

describe("cicloVigente", () => {
  it("sin días trabajados, no hay ciclo", () => {
    expect(cicloVigente([], "2026-08-20")).toBeNull();
  });

  it("una racha corta de cinco días es un solo ciclo con esos cinco días", () => {
    const dias = racha("2026-08-10", 5, 9);
    const c = cicloVigente(dias, "2026-08-14");
    expect(c).toEqual({ horas: 45, dia: 5, desde: "2026-08-10", hasta: "2026-08-14" });
  });

  // EL CASO QUE ESTE MÓDULO EXISTE PARA NO ROMPER (comentario "CAMBIO 0185" de
  // la 0339): doce días seguidos de 8 h son DOS ciclos de 7, no uno de doce.
  // El día 12 cae en el segundo ciclo (días 8-12), con 40 h — no 96.
  it("doce días seguidos de 8h: el ciclo vigente es el segundo bloque (40h, no 96h)", () => {
    const dias = racha("2026-08-01", 12, 8);
    const c = cicloVigente(dias, "2026-08-12");
    expect(c).toEqual({ horas: 40, dia: 5, desde: "2026-08-08", hasta: "2026-08-12" });
  });

  it("exactamente siete días seguidos de 7h: un solo ciclo de 49h (ya en exceso)", () => {
    const dias = racha("2026-08-01", 7, 7);
    const c = cicloVigente(dias, "2026-08-07");
    expect(c).toEqual({ horas: 49, dia: 7, desde: "2026-08-01", hasta: "2026-08-07" });
  });

  it("el octavo día consecutivo abre un ciclo nuevo de un solo día", () => {
    const dias = racha("2026-08-01", 8, 8);
    const c = cicloVigente(dias, "2026-08-08");
    expect(c).toEqual({ horas: 8, dia: 1, desde: "2026-08-08", hasta: "2026-08-08" });
  });

  it("si el último día trabajado fue ayer, el ciclo sigue vigente hoy", () => {
    const dias = racha("2026-08-10", 3, 8); // hasta el 12
    const c = cicloVigente(dias, "2026-08-13"); // hoy 13, ayer 12 = último trabajado
    expect(c).not.toBeNull();
    expect(c!.hasta).toBe("2026-08-12");
  });

  it("si el último día trabajado fue hace dos días o más, la racha ya se cortó", () => {
    const dias = racha("2026-08-10", 3, 8); // hasta el 12
    expect(cicloVigente(dias, "2026-08-15")).toBeNull();
  });

  it("un hueco entre dos rachas separa las islas; solo importa la más reciente", () => {
    const vieja = racha("2026-07-01", 6, 9); // racha larga, pero ya vieja
    const nueva = racha("2026-08-10", 2, 8); // racha corta, la vigente
    const c = cicloVigente([...vieja, ...nueva], "2026-08-11");
    expect(c).toEqual({ horas: 16, dia: 2, desde: "2026-08-10", hasta: "2026-08-11" });
  });

  it("un día con 0 horas no cuenta como trabajado y corta la racha", () => {
    const dias: DiaTrabajado[] = [
      { fecha: "2026-08-10", horas: 8 },
      { fecha: "2026-08-11", horas: 0 },
      { fecha: "2026-08-12", horas: 8 },
    ];
    const c = cicloVigente(dias, "2026-08-12");
    expect(c).toEqual({ horas: 8, dia: 1, desde: "2026-08-12", hasta: "2026-08-12" });
  });

  it("el orden de entrada no importa: se ordena por fecha antes de armar las islas", () => {
    const enDesorden = [...racha("2026-08-10", 5, 9)].reverse();
    const c = cicloVigente(enDesorden, "2026-08-14");
    expect(c).toEqual({ horas: 45, dia: 5, desde: "2026-08-10", hasta: "2026-08-14" });
  });
});
