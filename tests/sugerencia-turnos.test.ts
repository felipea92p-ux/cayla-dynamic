// sugerencia-turnos.test.ts — la propuesta de turnos de una semana
import { describe, expect, it } from "vitest";
import { semillaDe, sugerirSemana, type DiaSugerencia, type PersonaSugerencia, type Turno } from "../apps/web/lib/admin/sugerencia-turnos";

const h = (x: number) => Math.round(x * 60);
const FECHAS = ["2026-11-09", "2026-11-10", "2026-11-11", "2026-11-12", "2026-11-13", "2026-11-14", "2026-11-15"];

/** Una tienda de 09:00 a 21:00 que pide `pedia(min)` personas. */
const dia = (fecha: string, pedia: (m: number) => number = () => 2, metaLideres = 0): DiaSugerencia => ({
  fecha, abre: h(9), cierra: h(21), pedia, compras: () => 2, metaLideres,
});

const turnoBase: Turno = { entrada: h(9), salida: h(17) };
const persona = (id: string, over: Partial<PersonaSugerencia> = {}): PersonaSugerencia => ({
  id, nombre: id, cuenta: true, lider: false,
  objetivoHoras: 35, diasTrabajo: 5, refrigerioMin: 60,
  actual: Object.fromEntries(FECHAS.map((f, i) => [f, i < 5 ? turnoBase : null])),
  fijos: new Set(), bloques: {}, ...over,
});

const cruza = (t: Turno, desde: number, hasta: number) => t.entrada < hasta && desde < t.salida;

describe("sugerirSemana", () => {
  const dias = FECHAS.map((f) => dia(f));
  const personas = ["Ana", "Bea", "Ceci", "Dani"].map((n) => persona(n));
  const p = sugerirSemana({ dias, personas, semilla: semillaDe("ZZ|2026-11-09"), iteraciones: 20000 });

  it("cada persona conserva sus días de trabajo y las horas de su jornada", () => {
    for (const n of ["Ana", "Bea", "Ceci", "Dani"]) {
      expect(p.resumen[n].dias).toBe(5);
      expect(p.resumen[n].horas).toBe(35);
    }
  });

  it("cada día es un solo turno corrido, dentro de la ventana, y nadie pasa de 48 h", () => {
    for (const n of Object.keys(p.turnos)) {
      let total = 0;
      for (const f of FECHAS) {
        const t = p.turnos[n][f];
        if (!t) continue;
        expect(t.entrada).toBeGreaterThanOrEqual(h(9));
        expect(t.salida).toBeLessThanOrEqual(h(21));
        total += t.salida - t.entrada - 60;
      }
      expect(total).toBeLessThanOrEqual(48 * 60);
    }
  });

  it("la misma entrada da siempre la misma propuesta", () => {
    const otra = sugerirSemana({ dias, personas, semilla: semillaDe("ZZ|2026-11-09"), iteraciones: 20000 });
    expect(otra.turnos).toEqual(p.turnos);
  });

  it("un «no puedo» nunca se pisa", () => {
    const conBloque = personas.map((x) => x.id === "Ana"
      ? { ...x, bloques: { [FECHAS[0]]: [{ desde: h(12), hasta: h(21), estado: "no_puede" as const }], [FECHAS[2]]: [{ desde: 0, hasta: h(24), estado: "no_puede" as const }] } }
      : x);
    const r = sugerirSemana({ dias, personas: conBloque, semilla: 7, iteraciones: 20000 });
    const lunes = r.turnos.Ana[FECHAS[0]];
    if (lunes) expect(cruza(lunes, h(12), h(21))).toBe(false);
    expect(r.turnos.Ana[FECHAS[2]]).toBeNull();
  });

  it("un «horario fijo» deja ese día como estaba", () => {
    const fija = personas.map((x) => x.id === "Bea" ? { ...x, fijos: new Set([FECHAS[1], FECHAS[6]]) } : x);
    const r = sugerirSemana({ dias, personas: fija, semilla: 7, iteraciones: 20000 });
    expect(r.turnos.Bea[FECHAS[1]]).toEqual(turnoBase);
    expect(r.turnos.Bea[FECHAS[6]]).toBeNull();
  });

  it("«prefiero no» se respeta cuando alcanza la gente", () => {
    const pref = personas.map((x) => x.id === "Ceci"
      ? { ...x, bloques: { [FECHAS[3]]: [{ desde: 0, hasta: h(24), estado: "prefiere_no" as const }] } }
      : x);
    const r = sugerirSemana({ dias, personas: pref, semilla: 11, iteraciones: 30000 });
    expect(r.turnos.Ceci[FECHAS[3]]).toBeNull();
    expect(r.avisos.some((a) => a.startsWith("Ceci trabaja"))).toBe(false);
  });

  it("pone más gente donde la venta pide más", () => {
    const pico = FECHAS.map((f) => dia(f, (m) => (m >= h(17) && m < h(20) ? 3 : 1)));
    const r = sugerirSemana({ dias: pico, personas, semilla: 3, iteraciones: 30000 });
    const cob = r.cobertura[FECHAS[0]];
    const tarde = cob.filter((c) => c.hora >= 17 && c.hora < 20).map((c) => c.enPiso);
    const manana = cob.filter((c) => c.hora >= 9 && c.hora < 12).map((c) => c.enPiso);
    expect(Math.min(...tarde)).toBeGreaterThanOrEqual(Math.max(...manana));
  });

  it("si la sede pide líder, la pone en piso", () => {
    const conLider = [...personas.slice(0, 3), persona("Lia", { lider: true, cuenta: false, objetivoHoras: 48, diasTrabajo: 6, actual: Object.fromEntries(FECHAS.map((f, i) => [f, i < 6 ? { entrada: h(12), salida: h(21) } : null])) })];
    const diasL = FECHAS.map((f) => dia(f, () => 1, 1));
    const r = sugerirSemana({ dias: diasL, personas: conLider, semilla: 5, iteraciones: 30000 });
    const conElla = FECHAS.filter((f) => r.turnos.Lia[f]).length;
    expect(conElla).toBe(6);
  });

  it("avisa con palabras las horas que quedan cortas", () => {
    const mucha = FECHAS.map((f) => dia(f, () => 6));
    const r = sugerirSemana({ dias: mucha, personas, semilla: 3, iteraciones: 5000 });
    expect(r.avisos.some((a) => /faltan? \d+ personas? en piso/.test(a))).toBe(true);
  });
});
