import { describe, it, expect } from "vitest";
import type { ClienteCayla } from "@cayla-dynamic/database";
import { contarBandejaEquipoPendiente, cuentaBandejaEquipo, resumenNormasPendientes, traerFuentesYNormas } from "@/lib/admin/bandeja-equipo";
import { tituloDelContadorBandeja } from "@/lib/admin/bandeja-sistema";
import { FUENTES_VACIAS, MODULOS_BANDEJA } from "@/lib/admin/bandeja-fuentes";
import { RUTA_MODULO, resumenDeLaBandeja, resumirPendientes } from "@/lib/admin/pendientes-resumen";

const p = (modulo: (typeof MODULOS_BANDEJA)[number]["clave"], veces = 1) => Array.from({ length: veces }, () => ({ modulo }));

describe("resumirPendientes", () => {
  it("sin pendientes: total 0 y ningún módulo", () => {
    expect(resumirPendientes([], 0)).toEqual({ total: 0, porModulo: [], otros: 0 });
  });

  it("agrupa por módulo, de mayor a menor, con su etiqueta y su ruta", () => {
    const r = resumirPendientes([...p("ausencias", 5), ...p("documentacion", 9), ...p("correcciones", 2)], 16);
    expect(r.porModulo.map((m) => [m.clave, m.n])).toEqual([["documentacion", 9], ["ausencias", 5], ["correcciones", 2]]);
    expect(r.porModulo[0]).toMatchObject({ etiqueta: "Documentación", ruta: "/admin/documentacion" });
    expect(r.otros).toBe(0);
  });

  it("muestra solo los 3 primeros y suma el resto en «otros»", () => {
    const r = resumirPendientes([...p("ausencias", 4), ...p("documentacion", 3), ...p("correcciones", 2), ...p("horarios", 1)], 10);
    expect(r.porModulo).toHaveLength(3);
    expect(r.otros).toBe(1);
  });

  it("el total oficial manda: los avisos por correo, que no tienen módulo, quedan en «otros»", () => {
    const r = resumirPendientes(p("ausencias", 2), 5);
    expect(r.total).toBe(5);
    expect(r.otros).toBe(3);
  });

  it("si dos módulos empatan, gana el que la Bandeja pinta primero", () => {
    const r = resumirPendientes([...p("liquidaciones", 2), ...p("contratos", 2)], 4);
    expect(r.porModulo.map((m) => m.clave)).toEqual(["contratos", "liquidaciones"]);
  });

  it("nunca devuelve «otros» negativo aunque el total sea menor que la suma", () => {
    expect(resumirPendientes(p("ausencias", 3), 1).otros).toBe(0);
  });

  it("todo módulo de la Bandeja tiene una ruta de admin", () => {
    for (const m of MODULOS_BANDEJA) expect(RUTA_MODULO[m.clave]).toMatch(/^\/admin\//);
  });
});

// ── El menú y el Dashboard dan el MISMO número ─────────────────────────────
// Medido el 2026-10-25: el menú decía 96 y el indicador del Dashboard habría
// dicho 92 (sumaba los 61 correos pero no las 4 de Normas) — tres cuentas para
// una misma pregunta. Acá los dos caminos se corren contra el mismo cliente
// falso: uno es `contarBandejaEquipoPendiente` (lo que pinta nav.tsx) y el
// otro, lo que hace el hook del Dashboard (`traerFuentesYNormas` +
// `resumenDeLaBandeja`).

/** Un cliente que contesta cada RPC con lo que se le dé y todo lo demás con tablas vacías. */
function clienteFalso(rpcs: Record<string, unknown>): ClienteCayla {
  const cadena = (): unknown => new Proxy(() => {}, {
    get: (_t, k) => {
      if (k === "then") return (ok: (v: unknown) => unknown) => Promise.resolve({ data: [], error: null }).then(ok);
      if (k === "maybeSingle" || k === "single") return () => Promise.resolve({ data: null, error: null });
      return cadena;
    },
    apply: () => cadena(),
  });
  return {
    rpc: (nombre: string) => Promise.resolve({ data: rpcs[nombre] ?? [], error: null }),
    from: () => cadena(),
    auth: { getUser: () => Promise.resolve({ data: { user: null } }) },
  } as unknown as ClienteCayla;
}

const revision = (i: number) => ({
  id: `r${i}`, persona_id: "11111111-1111-1111-1111-111111111111", nombre: "Ana Prueba", sede: "TRU",
  fecha: "2026-09-03", comentario: "No tomó mi salida", pedida_at: "2026-09-06T15:00:00Z",
});
const CORREOS_CAIDOS = { despachables: 0, atascadas: 0, fallidas_definitivas: 61, caducadas: 0, ultimo_envio_at: null, motivos_definitivos: [] };
const NORMAS = [{ requiere_acuse: true, poblacion: 10, total_acuses: 6 }]; // 4 constancias por recoger

describe("el menú y el Dashboard dan el mismo número", () => {
  const rpcs = {
    fn_revisiones_pedidas: Array.from({ length: 31 }, (_, i) => revision(i)),
    fn_alertas_despacho_resumen: CORREOS_CAIDOS,
    fn_documentos_vigentes: NORMAS,
  };

  it("DO: 31 filas + 61 correos fallidos + 4 constancias = 33, en el menú y en el Dashboard", async () => {
    const cliente = clienteFalso(rpcs);
    const menu = await contarBandejaEquipoPendiente(cliente, "lider_do");
    const { fuentes, constanciasNormas } = await traerFuentesYNormas(cliente, "lider_do");
    const dashboard = resumenDeLaBandeja(fuentes, constanciasNormas);
    expect(fuentes.revisiones).toHaveLength(31); // el cliente falso sí llegó a la lista
    expect(menu).toBe(33);
    expect(dashboard.total).toBe(menu);
    // Lo que no es fila (correo + Normas) cae en «otros»: nada se pierde ni se cuenta dos veces.
    expect(dashboard.porModulo.reduce((s, m) => s + m.n, 0) + dashboard.otros).toBe(33);
  });

  it("la cuenta completa explica el número: el título del menú suma lo mismo que el bolito", async () => {
    const cuenta = await cuentaBandejaEquipo(clienteFalso(rpcs), "lider_do");
    expect(cuenta).toEqual({ tareas: 31, sistema: 1, normas: 1, total: 33 });
    expect(tituloDelContadorBandeja(cuenta)).toContain("33 en la Bandeja del equipo: 31 filas de la lista + 1 por los correos");
  });

  it("la franja de Normas habla de constancias, no de personas: son pares persona-documento", async () => {
    // 1 documento, 10 personas, 6 acuses = 4 constancias; podrían ser 4 personas distintas o una con cuatro documentos.
    const r = await resumenNormasPendientes(clienteFalso(rpcs), "lider_do");
    expect(r?.texto).toBe("Normas: 4 constancias pendientes");
    const una = await resumenNormasPendientes(clienteFalso({ ...rpcs, fn_documentos_vigentes: [{ requiere_acuse: true, poblacion: 10, total_acuses: 9 }] }), "lider_do");
    expect(una?.texto).toBe("Normas: 1 constancia pendiente");
    expect(await resumenNormasPendientes(clienteFalso({ ...rpcs, fn_documentos_vigentes: [] }), "lider_do")).toBeNull();
  });

  it("quien no es DO no ve Normas, y lo dicen igual los dos", async () => {
    const cliente = clienteFalso(rpcs);
    const menu = await contarBandejaEquipoPendiente(cliente, "supervisor_sede");
    const { fuentes, constanciasNormas } = await traerFuentesYNormas(cliente, "supervisor_sede");
    expect(constanciasNormas).toBe(0);
    expect(resumenDeLaBandeja(fuentes, constanciasNormas).total).toBe(menu);
  });

  it("sin correos con problema ni Normas, solo las filas", async () => {
    const cliente = clienteFalso({ ...rpcs, fn_alertas_despacho_resumen: { ...CORREOS_CAIDOS, fallidas_definitivas: 0 }, fn_documentos_vigentes: [] });
    expect(await contarBandejaEquipoPendiente(cliente, "lider_do")).toBe(31);
  });
});

describe("resumenDeLaBandeja", () => {
  it("el total es el de la cuenta, no la suma de lo agrupado: correo y Normas van a «otros»", () => {
    const f = { ...FUENTES_VACIAS, resumenAlertas: CORREOS_CAIDOS };
    const r = resumenDeLaBandeja(f, 4);
    expect(r).toEqual({ total: 2, porModulo: [], otros: 2 });
  });
});
