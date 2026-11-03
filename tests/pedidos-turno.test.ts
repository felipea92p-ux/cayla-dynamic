import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import {
  DIAS_ADELANTE, HORAS_PARA_DO, MOTIVOS, PROPUESTAS, horasParaDo, pasoADo, respuestaValida,
  resumenPedido, sePuedePedir, tituloRespuesta,
} from "@/lib/pedidos-turno";

const MIGRACIONES = join(__dirname, "..", "supabase", "migrations");
const sql = readFileSync(join(MIGRACIONES, readdirSync(MIGRACIONES).find((f) => f.startsWith("0587_"))!), "utf8");

describe("lo mismo que dice la base (0587)", () => {
  it("las 48 horas y los 21 días", () => {
    expect(sql).toContain(`interval '${HORAS_PARA_DO} hours'`);
    expect(sql).toContain(`p_fecha > fn_hoy_lima() + ${DIAS_ADELANTE}`);
  });
  it("los motivos y las propuestas son los del CHECK", () => {
    expect(sql).toContain(`motivo in (${MOTIVOS.map((m) => `'${m.valor}'`).join(", ")})`);
    expect(sql).toContain(`propuesta in (${PROPUESTAS.map((p) => `'${p.valor}'`).join(", ")})`);
  });
});

describe("cuándo pasa a DO", () => {
  const creado = "2026-11-03T10:00:00Z";
  const t = (h: number) => Date.parse(creado) + h * 3600_000;
  it("a las 47 h sigue con su líder; a las 48 h es de DO", () => {
    expect(pasoADo({ estado: "abierto", creado_at: creado }, t(47.9))).toBe(false);
    expect(pasoADo({ estado: "abierto", creado_at: creado }, t(48))).toBe(true);
    expect(horasParaDo({ creado_at: creado }, t(10))).toBe(38);
    expect(horasParaDo({ creado_at: creado }, t(50))).toBe(0);
  });
  it("lo resuelto o retirado no pasa a nadie", () => {
    expect(pasoADo({ estado: "resuelto", creado_at: creado }, t(100))).toBe(false);
    expect(pasoADo({ estado: "retirado", creado_at: creado }, t(100))).toBe(false);
  });
});

describe("qué días se pueden pedir", () => {
  it("de hoy a 21 días, ni antes ni después", () => {
    expect(sePuedePedir("2026-11-03", "2026-11-03")).toBe(true);
    expect(sePuedePedir("2026-11-02", "2026-11-03")).toBe(false);
    expect(sePuedePedir("2026-11-24", "2026-11-03")).toBe(true);
    expect(sePuedePedir("2026-11-25", "2026-11-03")).toBe(false);
  });
});

describe("las palabras", () => {
  it("a ella le habla de tú; a su líder, de ella", () => {
    const p = { fecha: "2026-11-12", motivo: "estudios" as const, propuesta: "tarde" as const };
    expect(resumenPedido(p)).toBe("El 12 nov: puedo en la tarde · estudios");
    expect(resumenPedido(p, "ella")).toBe("El 12 nov: puede en la tarde · estudios");
  });
  it("la respuesta dice qué pasó con su día", () => {
    expect(tituloRespuesta({ fecha: "2026-11-12", resolucion: "se_mantiene" })).toBe("Tu pedido del 12 nov: el turno se mantiene");
    expect(tituloRespuesta({ fecha: "2026-11-12", resolucion: "acepta" })).toBe("Tu pedido del 12 nov: te lo cambian");
  });
  it("«se mantiene» explica por qué; «le calza» no hace falta", () => {
    expect(respuestaValida("acepta", "")).toBe(true);
    expect(respuestaValida("se_mantiene", "no")).toBe(false);
    expect(respuestaValida("se_mantiene", "Hay inventario ese día")).toBe(true);
  });
});
