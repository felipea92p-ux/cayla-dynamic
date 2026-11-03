// repeticion.test.ts — la repetición de un día cerrado (Turnos · Día, 0584)
import { describe, expect, it } from "vitest";
import {
  columnasEnElMomento, diaCompletoReal, enPisoEnLaHora, estadoEnElMomento, horasDeLaRepeticion, resumenReal, ventaPedia,
  type PersonaRepeticion,
} from "../apps/web/lib/admin/repeticion";

const medianocheIso = "2026-11-02T00:00:00-05:00";
const iso = (hhmm: string) => new Date(`2026-11-02T${hhmm}:00-05:00`).toISOString();

const persona = (over: Partial<PersonaRepeticion> & { id: string }): PersonaRepeticion => ({
  nombre: over.id, cuenta: true, lider: false, marcajes: [], almacen: [], plan: { desde: 8.5, hasta: 17 }, ...over,
});

const ana = persona({
  id: "Ana",
  marcajes: [
    { tipo: "entrada", timestamp: iso("08:34") },
    { tipo: "salida_almuerzo", timestamp: iso("13:00") },
    { tipo: "retorno_almuerzo", timestamp: iso("13:45") },
    { tipo: "salida_final", timestamp: iso("17:02") },
  ],
});

describe("estadoEnElMomento — la misma máquina del terminal, cortada en la hora", () => {
  it("por llegar, en piso, en refrigerio, de vuelta y ya salió", () => {
    expect(estadoEnElMomento(ana, 8, medianocheIso)).toBe("por_llegar");
    expect(estadoEnElMomento(ana, 9, medianocheIso)).toBe("piso");
    expect(estadoEnElMomento(ana, 13.25, medianocheIso)).toBe("refrigerio");
    expect(estadoEnElMomento(ana, 14, medianocheIso)).toBe("piso");
    expect(estadoEnElMomento(ana, 17.5, medianocheIso)).toBe("salio");
  });
  it("en un tramo de almacén está en almacén, no en piso", () => {
    const conAlmacen = { ...ana, almacen: [{ desde: 10.5, hasta: 12 }] };
    expect(estadoEnElMomento(conAlmacen, 11, medianocheIso)).toBe("almacen");
    expect(estadoEnElMomento(conAlmacen, 12, medianocheIso)).toBe("piso");
  });
  it("una salida por trámite es pausa", () => {
    const p = persona({ id: "Bea", marcajes: [{ tipo: "entrada", timestamp: iso("09:00") }, { tipo: "salida_tramite", timestamp: iso("11:00") }] });
    expect(estadoEnElMomento(p, 11.5, medianocheIso)).toBe("pausa");
  });
});

describe("ventaPedia — compras ÷ ritmo, hacia arriba, nunca menos que el mínimo", () => {
  const p = { ritmo: 1.5, minimo: 3 };
  it("con poca venta manda el mínimo", () => {
    expect(ventaPedia(0, p)).toBe(3);
    expect(ventaPedia(4, p)).toBe(3);
  });
  it("con mucha venta, la cuenta: 6 compras a 1,5 son 4 personas; 7 son 5", () => {
    expect(ventaPedia(6, p)).toBe(4);
    expect(ventaPedia(7, p)).toBe(5);
  });
  it("sin saber la venta no dice nada", () => {
    expect(ventaPedia(null, p)).toBeNull();
  });
});

describe("enPisoEnLaHora — el peor cuarto de la hora, solo quien cuenta", () => {
  it("quien sale a refrigerio a media hora resta en esa hora", () => {
    const bea = persona({ id: "Bea", marcajes: [{ tipo: "entrada", timestamp: iso("08:30") }] });
    const otraArea = persona({ id: "Ceci", cuenta: false, marcajes: [{ tipo: "entrada", timestamp: iso("08:30") }] });
    expect(enPisoEnLaHora([ana, bea, otraArea], 12, medianocheIso)).toBe(2);
    expect(enPisoEnLaHora([ana, bea, otraArea], 13, medianocheIso)).toBe(1);
  });
});

describe("columnasEnElMomento — qué se dice de cada una", () => {
  it("dice la hora real, y el plan al lado solo si difiere más de 5 minutos", () => {
    const tarde = persona({ id: "Dani", marcajes: [{ tipo: "entrada", timestamp: iso("08:50") }] });
    const col = columnasEnElMomento([ana, tarde], 10, medianocheIso, true);
    expect(col.piso.map((f) => f.detalle)).toEqual(["llegó 08:34", "llegó 08:50 · plan 08:30"]);
  });
  it("en un día cerrado, quien nunca marcó dice «sin marca de entrada», sin acusar", () => {
    const nunca = persona({ id: "Eli" });
    const col = columnasEnElMomento([nunca], 12, medianocheIso, true);
    expect(col.por_llegar[0].detalle).toBe("sin marca de entrada · plan 08:30");
  });
  it("quien ya salió lleva su hora, y el plan si se fue antes", () => {
    const temprano = persona({ id: "Fio", marcajes: [{ tipo: "entrada", timestamp: iso("08:30") }, { tipo: "salida_final", timestamp: iso("15:00") }] });
    const col = columnasEnElMomento([ana, temprano], 18, medianocheIso, true);
    expect(col.salio.map((f) => f.detalle)).toEqual(["salió 17:02", "salió 15:00 · plan 17:00"]);
  });
  it("las líderes van primero", () => {
    const lider = persona({ id: "Zoe", lider: true, marcajes: [{ tipo: "entrada", timestamp: iso("08:30") }] });
    expect(columnasEnElMomento([ana, lider], 10, medianocheIso, true).piso.map((f) => f.persona.id)).toEqual(["Zoe", "Ana"]);
  });
});

describe("el día completo y su resumen", () => {
  const bea = persona({ id: "Bea", marcajes: [{ tipo: "entrada", timestamp: iso("08:30") }, { tipo: "salida_final", timestamp: iso("17:00") }] });
  const compras: Record<number, number> = { 9: 1, 11: 6, 13: 3 };
  const horas = diaCompletoReal({
    personas: [ana, bea], medianocheIso, comprasDe: (h) => compras[h] ?? 0, parametros: { ritmo: 1.5, minimo: 2 },
  });
  it("las horas van de la primera marca o plan a la última", () => {
    expect(horasDeLaRepeticion([ana, bea], medianocheIso)).toEqual([8, 9, 10, 11, 12, 13, 14, 15, 16, 17]);
    expect(horas[0].hora).toBe(8);
  });
  it("a las 11 la venta pedía 4 y había 2: es una hora con falta", () => {
    const once = horas.find((h) => h.hora === 11)!;
    expect(once).toEqual({ hora: 11, enPiso: 2, compras: 6, pedia: 4 });
    const r = resumenReal(horas);
    expect(r.totalCompras).toBe(10);
    expect(r.masCargada).toEqual({ hora: 11, comprasPorPersona: 3 });
    expect(r.horasConFalta).toBeGreaterThanOrEqual(1);
  });
  it("sin la venta no hay total ni falta que contar", () => {
    const sin = diaCompletoReal({ personas: [ana], medianocheIso, comprasDe: null, parametros: { ritmo: 1.5, minimo: 2 } });
    expect(sin.every((h) => h.compras === null && h.pedia === null)).toBe(true);
    expect(resumenReal(sin)).toEqual({ totalCompras: null, horasConFalta: 0, masCargada: null });
  });
});
