// semana-persona.test.ts — la frase de cada día en la semana compacta de Correcciones
import { describe, expect, it } from "vitest";
import { resumenDiaSemana } from "../apps/web/lib/admin/semana-persona";

const HOY = "2026-10-21";
const j = (o: Partial<{ estado: string; horas_trabajadas: number | null; minutos_tarde: number | null }> = {}) => ({
  fecha: "2026-10-19", estado: "cerrada", horas_trabajadas: 8.05, minutos_tarde: 0, ...o,
});

describe("resumenDiaSemana", () => {
  it("un día pasado sin jornada dice «Sin jornada», sin acusar nada", () => {
    expect(resumenDiaSemana({ fecha: "2026-10-20", hoy: HOY, jornada: null, levantada: false }))
      .toEqual({ texto: "Sin jornada", tono: "neutro", tachado: false });
  });

  it("un día futuro dice «—»: no hay nada que decir de lo que aún no pasó", () => {
    expect(resumenDiaSemana({ fecha: "2026-10-23", hoy: HOY, jornada: null, levantada: false }).texto).toBe("—");
  });

  it("puntual con horas: muestra las horas trabajadas", () => {
    const r = resumenDiaSemana({ fecha: "2026-10-19", hoy: HOY, jornada: j(), levantada: false });
    expect(r.tono).toBe("ok");
    expect(r.texto).toMatch(/8/);
  });

  it("tardanza sin levantar: lo dice y va en tono de tardanza", () => {
    const r = resumenDiaSemana({ fecha: "2026-10-19", hoy: HOY, jornada: j({ minutos_tarde: 25 }), levantada: false });
    expect(r).toMatchObject({ tono: "tarde", tachado: false });
    expect(r.texto).toMatch(/25.*tarde/);
  });

  it("tardanza LEVANTADA: se tacha y deja de ser tono de tardanza (igual que en Horas y en el Dashboard)", () => {
    const r = resumenDiaSemana({ fecha: "2026-10-19", hoy: HOY, jornada: j({ minutos_tarde: 25 }), levantada: true });
    expect(r).toMatchObject({ tachado: true, tono: "neutro", nota: "levantada" });
  });

  it("más de 3 h de tardanza no se llama tardanza: pide revisar el horario", () => {
    const r = resumenDiaSemana({ fecha: "2026-10-19", hoy: HOY, jornada: j({ minutos_tarde: 400 }), levantada: false });
    expect(r).toMatchObject({ texto: "Revisar horario", tono: "aviso" });
  });

  it("sin horas ni tardanza (día abierto): dice el estado de la jornada", () => {
    const r = resumenDiaSemana({ fecha: "2026-10-21", hoy: HOY, jornada: j({ estado: "abierta", horas_trabajadas: null }), levantada: false });
    expect(r.tachado).toBe(false);
    expect(r.texto.length).toBeGreaterThan(0);
  });
});
