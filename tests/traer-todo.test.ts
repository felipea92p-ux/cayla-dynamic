// ============================================================================
// traer-todo.test.ts — que ningún reporte se entregue cortado en silencio
// ============================================================================
// PostgREST corta toda respuesta en 1000 filas y devuelve 200 OK: `error` viene
// en null y supabase-js no dice nada. El CSV de asistencia que va al contador se
// descargaba entero, abría bien en Excel y simplemente terminaba antes.
//
// Lo que estas pruebas anclan es la regla, no la implementación: o llegan TODAS
// las filas, o llega un error. Nunca un subconjunto que parezca completo.
// ============================================================================
import { describe, it, expect } from "vitest";
import { traerTodo, TAMANO_LOTE } from "@/lib/admin/traer-todo";

/** Simula PostgREST: nunca devuelve más de TAMANO_LOTE filas por llamada. */
function fuenteCon(totalFilas: number) {
  const todas = Array.from({ length: totalFilas }, (_, i) => ({ n: i }));
  const rangosPedidos: Array<[number, number]> = [];

  const hacerLote = async (desde: number, hasta: number) => {
    rangosPedidos.push([desde, hasta]);
    return { data: todas.slice(desde, hasta + 1), error: null };
  };

  return { hacerLote, rangosPedidos };
}

describe("traerTodo — o completo, o error", () => {
  it("un resultado que cabe en un lote se devuelve en una sola llamada", async () => {
    const { hacerLote, rangosPedidos } = fuenteCon(42);
    const { data, error } = await traerTodo(hacerLote);

    expect(error).toBeNull();
    expect(data).toHaveLength(42);
    expect(rangosPedidos).toHaveLength(1);
  });

  it("2500 filas llegan completas — antes se perdían 1500 sin avisar", async () => {
    const { hacerLote, rangosPedidos } = fuenteCon(2500);
    const { data, error } = await traerTodo<{ n: number }>(hacerLote);

    expect(error).toBeNull();
    expect(data).toHaveLength(2500);
    // Sin huecos ni repetidos: el orden de la fuente se conserva entero.
    expect(data!.map((f) => f.n)).toEqual(Array.from({ length: 2500 }, (_, i) => i));
    expect(rangosPedidos).toHaveLength(3);
  });

  it("un total múltiplo exacto del lote pide una vez más para confirmar el final", async () => {
    // El caso borde clásico: con 2000 filas el segundo lote viene lleno, así que
    // no se puede asumir que ahí terminó. Si esta prueba falla, el reporte se
    // corta justo en los múltiplos de 1000 — el escenario más fácil de no notar.
    const { hacerLote, rangosPedidos } = fuenteCon(TAMANO_LOTE * 2);
    const { data, error } = await traerTodo(hacerLote);

    expect(error).toBeNull();
    expect(data).toHaveLength(TAMANO_LOTE * 2);
    expect(rangosPedidos).toHaveLength(3);
  });

  it("un rango vacío devuelve lista vacía, no error", async () => {
    const { hacerLote } = fuenteCon(0);
    const { data, error } = await traerTodo(hacerLote);

    expect(error).toBeNull();
    expect(data).toEqual([]);
  });

  it("si un lote falla, no se entrega lo que ya se había traído", async () => {
    // Devolver las primeras 1000 filas con error null sería exactamente el bug
    // que esto viene a cerrar, pero por otro camino.
    let llamadas = 0;
    const hacerLote = async (desde: number, hasta: number) => {
      llamadas++;
      if (llamadas === 2) return { data: null, error: { message: "se cayó la red" } };
      return { data: Array.from({ length: TAMANO_LOTE }, (_, i) => ({ n: desde + i })), error: null };
    };

    const { data, error } = await traerTodo(hacerLote);

    expect(data).toBeNull();
    expect(error?.message).toBe("se cayó la red");
  });

  it("una consulta desbocada corta con error explícito en vez de colgar el navegador", async () => {
    // Fuente infinita: siempre devuelve lotes llenos.
    const hacerLote = async (desde: number) =>
      ({ data: Array.from({ length: TAMANO_LOTE }, (_, i) => ({ n: desde + i })), error: null });

    const { data, error } = await traerTodo(hacerLote);

    expect(data).toBeNull();
    expect(error?.message).toContain("acota el rango de fechas");
  });
});
