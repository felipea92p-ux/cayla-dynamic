// ============================================================================
// parametro-vigente.test.ts — qué fila de parametros_laborales rige un día
// ============================================================================
// La RMV se versiona cerrando la fila vieja y abriendo otra. Contratos la leía
// como «la fila abierta» (`vigente_hasta IS NULL`) y, entre cerrar la vieja y que
// llegue la fecha de la nueva, no había ninguna: el convenio de jornada reducida
// salía con «[FALTA PUBLICAR LA RMV VIGENTE EN EL SISTEMA]» y el piso de la
// subvención de prácticas (Ley 28518, art. 45) no bloqueaba nada.
// Estas pruebas fijan la regla de la planilla —la misma de fn_planilla_calcular—.
// ============================================================================
import { describe, it, expect } from "vitest";
import { estaVigente, vigentesAl, type FilaParametro } from "@/lib/admin/parametro-vigente";

type Fila = FilaParametro & { valor: number };

const fila = (
  clave: string, valor: number, desde: string, hasta: string | null = null, sede: string | null = null,
): Fila => ({ clave, valor, sede_codigo: sede, vigente_desde: desde, vigente_hasta: hasta });

// Como queda la RMV el día de la migración 0501: la vieja cerrada, la nueva abierta.
const RMV_VERSIONADA: Fila[] = [
  fila("rmv", 1130, "2025-01-01", "2026-09-30"),
  fila("rmv", 1230, "2026-10-01"),
];

const rmvDe = (filas: Fila[], dia: string) => vigentesAl(filas, dia).find((f) => f.clave === "rmv")?.valor;

describe("la RMV el día del cambio: nunca una ventana sin RMV", () => {
  it("el 30 de septiembre sigue rigiendo la vieja, aunque ya esté cerrada", () => {
    // Con `vigente_hasta IS NULL` esta consulta devolvía NADA: la vieja está
    // cerrada y la nueva todavía no empieza.
    expect(rmvDe(RMV_VERSIONADA, "2026-09-30")).toBe(1130);
  });

  it("el 1 de octubre rige la nueva, y solo la nueva", () => {
    expect(rmvDe(RMV_VERSIONADA, "2026-10-01")).toBe(1230);
    expect(vigentesAl(RMV_VERSIONADA, "2026-10-01")).toHaveLength(1);
  });

  it("la fecha de cierre cuenta: `vigente_hasta` es inclusivo", () => {
    expect(estaVigente(RMV_VERSIONADA[0], "2026-09-30")).toBe(true);
    expect(estaVigente(RMV_VERSIONADA[0], "2026-10-01")).toBe(false);
  });

  it("antes de que empiece la primera fila no hay RMV, y no se inventa una", () => {
    expect(rmvDe(RMV_VERSIONADA, "2024-12-31")).toBeUndefined();
    expect(vigentesAl(RMV_VERSIONADA, "2024-12-31")).toEqual([]);
  });

  it("el día siguiente a que una fila cierre sin reemplazo, tampoco hay RMV", () => {
    const sinReemplazo = [fila("rmv", 1130, "2025-01-01", "2026-09-30")];
    expect(rmvDe(sinReemplazo, "2026-10-01")).toBeUndefined();
  });
});

describe("si las dos filas conviven, manda la más reciente", () => {
  // Pasa si la vieja todavía no se cerró: la migración abre primero y cierra
  // después a propósito, para que nunca falte una.
  const ambasAbiertas = [fila("rmv", 1130, "2025-01-01"), fila("rmv", 1230, "2026-10-01")];

  it("con las dos abiertas, el 15 de octubre lee la nueva, no la primera que llegue", () => {
    expect(rmvDe(ambasAbiertas, "2026-10-15")).toBe(1230);
    expect(rmvDe([...ambasAbiertas].reverse(), "2026-10-15")).toBe(1230);
  });

  it("y antes de la fecha de la nueva sigue leyendo la vieja", () => {
    expect(rmvDe(ambasAbiertas, "2026-09-30")).toBe(1130);
  });
});

describe("una fila por (clave, sede): la movilidad y el bono no se pisan con la RMV", () => {
  const todo: Fila[] = [
    ...RMV_VERSIONADA,
    fila("movilidad_diaria", 10, "2026-01-01", null, "TRU"),
    fila("movilidad_diaria", 12, "2026-01-01", null, "LIM"),
    fila("movilidad_diaria", 11, "2025-01-01", "2025-12-31", "LIM"), // ya cerrada
    fila("bono_onomastico", 50, "2026-01-01"),
  ];

  it("cada sede conserva su tarifa vigente y la cerrada no aparece", () => {
    const tarifas = vigentesAl(todo, "2026-10-15").filter((f) => f.clave === "movilidad_diaria");
    expect(tarifas.map((t) => `${t.sede_codigo}:${t.valor}`).sort()).toEqual(["LIM:12", "TRU:10"]);
  });

  it("la RMV y el bono salen cada uno una sola vez", () => {
    const v = vigentesAl(todo, "2026-10-15");
    expect(v.filter((f) => f.clave === "rmv").map((f) => f.valor)).toEqual([1230]);
    expect(v.filter((f) => f.clave === "bono_onomastico").map((f) => f.valor)).toEqual([50]);
  });

  it("en dos sedes distintas la misma clave no se confunde", () => {
    const conDosSedes = [fila("movilidad_diaria", 10, "2026-01-01", null, "TRU"), fila("movilidad_diaria", 12, "2026-06-01", null, "LIM")];
    expect(vigentesAl(conDosSedes, "2026-10-15")).toHaveLength(2);
  });
});

describe("no toca lo que recibe", () => {
  it("devuelve una lista nueva y deja la original como estaba", () => {
    const original = [...RMV_VERSIONADA];
    const salida = vigentesAl(original, "2026-10-15");
    expect(original).toEqual(RMV_VERSIONADA);
    expect(salida).not.toBe(original);
  });
});
