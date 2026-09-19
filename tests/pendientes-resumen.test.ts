import { describe, it, expect } from "vitest";
import { MODULOS_BANDEJA } from "@/lib/admin/bandeja-fuentes";
import { RUTA_MODULO, resumirPendientes } from "@/lib/admin/pendientes-resumen";

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
