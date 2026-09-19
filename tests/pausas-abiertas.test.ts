// ============================================================================
// pausas-abiertas.test.ts — de dónde sale «desde cuándo» está en pausa
// ============================================================================
// El cargador lee marcajes de la base; acá se prueba con un cliente de mentira
// que solo anota cómo lo llamaron. Lo que importa comprobar:
//   · que pide justo lo que hace correcto el resultado (no anuladas, solo hoy,
//     solo esas personas),
//   · que arma bien la pausa de cada una, y
//   · que cuando la consulta FALLA lo diga, en vez de devolver «nadie tiene
//     pausa» — que sería mentir con la misma cara que la verdad.
// ============================================================================
import { describe, expect, it } from "vitest";
import type { ClienteCayla } from "@cayla-dynamic/database";
import { traerPausasAbiertas } from "@/lib/admin/pausas-abiertas";

interface Llamada { metodo: string; args: unknown[] }

/** Un cliente que contesta lo que se le diga y anota cada llamada de la cadena. */
function clienteFalso(respuesta: { data: unknown; error: unknown }) {
  const llamadas: Llamada[] = [];
  const consulta: Record<string, unknown> = {};
  for (const metodo of ["select", "in", "is", "gte"]) {
    consulta[metodo] = (...args: unknown[]) => {
      llamadas.push({ metodo, args });
      return consulta;
    };
  }
  consulta.order = (...args: unknown[]) => {
    llamadas.push({ metodo: "order", args });
    return Promise.resolve(respuesta);
  };
  const cliente = {
    from: (tabla: string) => {
      llamadas.push({ metodo: "from", args: [tabla] });
      return consulta;
    },
  } as unknown as ClienteCayla;
  return { cliente, llamadas };
}

const HOY = "2026-09-18";
const fila = (persona_id: string, tipo: string, timestamp_marca: string) => ({ persona_id, tipo, timestamp_marca });

describe("traerPausasAbiertas", () => {
  it("sin nadie en pausa no consulta la base", async () => {
    const cliente = { from: () => { throw new Error("no debía consultar nada"); } } as unknown as ClienteCayla;
    expect(await traerPausasAbiertas(cliente, [], HOY)).toEqual({ porPersona: new Map(), fallo: false });
  });

  it("pide solo marcajes no anuladas, de hoy en Lima y de esas personas", async () => {
    const { cliente, llamadas } = clienteFalso({ data: [], error: null });
    await traerPausasAbiertas(cliente, ["a", "b"], HOY);
    const de = (metodo: string) => llamadas.find((l) => l.metodo === metodo)?.args;
    expect(de("from")).toEqual(["marcajes"]);
    expect(de("in")).toEqual(["persona_id", ["a", "b"]]);
    expect(de("is")).toEqual(["anulada_at", null]); // una marca anulada no existió
    expect(de("gte")).toEqual(["timestamp_marca", "2026-09-18T00:00:00-05:00"]); // las 00:00 de Lima
  });

  it("arma la pausa de cada una: quien no regresó aparece, quien ya regresó no", async () => {
    const { cliente } = clienteFalso({
      error: null,
      data: [
        fila("a", "entrada", "2026-09-18T12:00:00Z"),
        fila("a", "salida_almuerzo", "2026-09-18T18:05:00Z"),
        fila("b", "entrada", "2026-09-18T12:00:00Z"),
        fila("b", "salida_almuerzo", "2026-09-18T18:00:00Z"),
        fila("b", "retorno_almuerzo", "2026-09-18T19:00:00Z"),
      ],
    });
    const { porPersona, fallo } = await traerPausasAbiertas(cliente, ["a", "b", "c"], HOY);
    expect(fallo).toBe(false);
    expect([...porPersona.keys()]).toEqual(["a"]); // b ya regresó; c no tiene marcas
    expect(porPersona.get("a")).toEqual({ tipo: "salida_almuerzo", desde: "2026-09-18T18:05:00Z" });
  });

  it("si la consulta FALLA lo dice: no devuelve «nadie tiene pausa»", async () => {
    const { cliente } = clienteFalso({ data: null, error: { message: "sin conexión" } });
    const r = await traerPausasAbiertas(cliente, ["a"], HOY);
    expect(r.fallo).toBe(true);
    expect(r.porPersona.size).toBe(0);
  });

  it("si la base contesta sin datos, no se cae", async () => {
    const { cliente } = clienteFalso({ data: null, error: null });
    expect(await traerPausasAbiertas(cliente, ["a"], HOY)).toEqual({ porPersona: new Map(), fallo: false });
  });
});
