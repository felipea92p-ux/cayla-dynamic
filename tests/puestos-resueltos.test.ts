// puestos-resueltos.test.ts — la lectura única del plan de piso/almacén (0588)
import { describe, expect, it } from "vitest";
import { baseEsAlmacen, baseVigenteDesde, leerPuestosResueltos } from "../apps/web/lib/puestos-resueltos";

/** Un cliente de mentira: la RPC responde lo que se le diga, y la tabla también. */
function cliente(rpc: { data?: unknown; error?: { code?: string; message?: string } | null }, tabla: unknown[] = []) {
  const llamadas: string[] = [];
  const consulta = (res: { data: unknown; error: unknown }) => {
    const q = {
      abortSignal: () => q, eq: (k: string, v: string) => { llamadas.push(`eq ${k}=${v}`); return q; },
      gte: () => q, lte: () => q,
      then: (ok: (r: unknown) => unknown) => Promise.resolve(res).then(ok),
    };
    return q;
  };
  return {
    llamadas,
    rpc: (fn: string) => { llamadas.push(`rpc ${fn}`); return consulta({ data: rpc.data ?? null, error: rpc.error ?? null }); },
    from: (t: string) => ({ select: () => { llamadas.push(`tabla ${t}`); return consulta({ data: tabla, error: null }); } }),
  };
}

describe("leerPuestosResueltos", () => {
  it("lee la regla de la base y trae el origen", async () => {
    const c = cliente({ data: [
      { persona_id: "A", fecha: "2026-11-10", desde: null, hasta: null, origen: "base" },
      { persona_id: "B", fecha: "2026-11-10", desde: "10:00:00", hasta: "12:00:00", origen: "dia" },
    ] });
    const r = await leerPuestosResueltos(c, "2026-11-09", "2026-11-15");
    expect(r.error).toBeNull();
    expect(r.data?.map((f) => `${f.persona_id}:${f.origen}`)).toEqual(["A:base", "B:dia"]);
    expect(c.llamadas).toEqual(["rpc fn_puestos_resueltos"]);
  });

  it("con personaId, solo las suyas", async () => {
    const c = cliente({ data: [
      { persona_id: "A", fecha: "2026-11-10", desde: null, hasta: null, origen: "base" },
      { persona_id: "B", fecha: "2026-11-10", desde: null, hasta: null, origen: "dia" },
    ] });
    const r = await leerPuestosResueltos(c, "2026-11-09", "2026-11-15", { personaId: "B" });
    expect(r.data?.map((f) => f.persona_id)).toEqual(["B"]);
  });

  it("si la 0588 no está pegada, lee la tabla del día como antes", async () => {
    const c = cliente({ error: { code: "PGRST202", message: "no existe" } },
      [{ persona_id: "A", fecha: "2026-11-10", desde: null, hasta: null }]);
    const r = await leerPuestosResueltos(c, "2026-11-09", "2026-11-15", { personaId: "A" });
    expect(r.error).toBeNull();
    expect(r.data).toEqual([{ persona_id: "A", fecha: "2026-11-10", desde: null, hasta: null, origen: "dia" }]);
    expect(c.llamadas).toEqual(["rpc fn_puestos_resueltos", "tabla puestos_planificados", "eq persona_id=A"]);
  });

  it("otro error no se disfraza de «sin plan»: vuelve como error", async () => {
    const c = cliente({ error: { code: "42501", message: "permiso" } });
    const r = await leerPuestosResueltos(c, "2026-11-09", "2026-11-15");
    expect(r.data).toBeNull();
    expect(r.error?.code).toBe("42501");
    expect(c.llamadas).toEqual(["rpc fn_puestos_resueltos"]);
  });
});

describe("baseEsAlmacen — la misma pregunta que fn_puesto_base_es_almacen", () => {
  const periodos = [{ vigente_desde: "2026-11-10", vigente_hasta: "2026-11-19" }, { vigente_desde: "2026-12-01", vigente_hasta: null }];
  it("dentro, fuera y abierto", () => {
    expect(baseEsAlmacen(periodos, "2026-11-09")).toBe(false);
    expect(baseEsAlmacen(periodos, "2026-11-10")).toBe(true);
    expect(baseEsAlmacen(periodos, "2026-11-19")).toBe(true);
    expect(baseEsAlmacen(periodos, "2026-11-20")).toBe(false);
    expect(baseEsAlmacen(periodos, "2027-03-01")).toBe(true);
  });
  it("desde cuándo rige", () => {
    expect(baseVigenteDesde(periodos, "2026-11-15")).toBe("2026-11-10");
    expect(baseVigenteDesde(periodos, "2026-11-25")).toBeNull();
  });
});
