import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";
import { colorDelDia, colorTardanza, MUESTRA, TARDANZA_GRAVE_MIN, TARDANZA_SERIA_MIN } from "@/lib/admin/color-del-dia";
import type { EstadoDia } from "@/lib/admin/jornada-esperada";

// Una sola escala de color del día para Horas y Lo mío (lib/admin/color-del-dia.ts). Hasta el 2026-11-09 eran dos copias, y la de Lo mío se
// había quedado con la tardanza grave pintada con un filtro que en oscuro se lee al revés.

const WEB = path.resolve(import.meta.dirname, "../apps/web");
const leer = (f: string) => readFileSync(path.join(WEB, f), "utf8");
const ESTADOS: EstadoDia[] = ["falta", "revisar", "tarde", "justificada", "ok", "extra", "sin_marca", "descanso", "sin_horario", "futuro"];
const PANTALLAS = ["app/(admin)/admin/horas/page.tsx", "app/(mio)/mio/page.tsx"];

describe("el color del día", () => {
  it("cada estado tiene su color", () => {
    for (const e of ESTADOS) expect(colorDelDia(e, 0), e).toMatch(/\S/);
  });

  it("la intensidad nunca es un filtro ni un token más oscuro: en oscuro eso se lee al revés", () => {
    const todas = [...ESTADOS.map((e) => colorDelDia(e, TARDANZA_GRAVE_MIN)), ...MUESTRA.tardanza].join(" ");
    expect(todas).not.toMatch(/\b(brightness|contrast|saturate|invert|grayscale)-/);
  });

  it("la tardanza tiene tres intensidades distintas, y la grave se distingue con un anillo", () => {
    const [leve, seria, grave] = [colorTardanza(1), colorTardanza(TARDANZA_SERIA_MIN), colorTardanza(TARDANZA_GRAVE_MIN)];
    expect(new Set([leve, seria, grave]).size).toBe(3);
    expect(grave).toMatch(/\bring-2\b/);
    expect(MUESTRA.tardanza).toEqual([colorTardanza(0), seria, grave]);
  });

  it("las dos pantallas usan esta escala y no una copia propia", () => {
    for (const p of PANTALLAS) {
      const fuente = leer(p);
      expect(fuente, p).toContain('from "@/lib/admin/color-del-dia"');
      expect(fuente, p).not.toMatch(/function colorTardanza|bg-ambar brightness|case "justificada": return "bg-/);
    }
  });
});
