// ============================================================================
// roster-prueba.test.ts — el kiosco y los días de prueba (0539)
// ============================================================================
// Lo que se defiende acá, en orden de importancia:
//   1. EL TERMINAL SIGUE MARCANDO. El frontend se publica solo al fusionar y el SQL
//      lo pega Felipe a mano: puede haber una ventana en que la pantalla nueva corre
//      contra una base sin la 0539. Pedir columnas que no existen haría fallar la
//      consulta entera, y un terminal recién instalado no tiene copia guardada. Solo
//      ante ESE error se pide otra vez sin las columnas nuevas.
//   2. Los días de prueba viajan en la misma fila y se guardan con el roster, para
//      que la etiqueta salga igual sin red.
//   3. Cualquier OTRO error sigue yendo a la copia guardada, sin reintentar.
// ============================================================================
import { beforeEach, describe, expect, it, vi } from "vitest";

const consultas: string[] = [];
let respuestas: { data: unknown[] | null; error: { code?: string; message: string } | null }[] = [];
const guardados: unknown[][] = [];
let copia: unknown[] = [];

vi.mock("@cayla-dynamic/database", () => ({
  createTerminalSupabaseClient: () => ({
    from: () => ({
      select: (columnas: string) => {
        consultas.push(columnas);
        const respuesta = respuestas.shift() ?? { data: null, error: { message: "sin respuesta preparada" } };
        const b: Record<string, unknown> = {};
        b.abortSignal = () => b;
        b.order = () => Promise.resolve(respuesta);
        return b;
      },
    }),
  }),
}));
vi.mock("@/lib/terminal/offline-db", () => ({
  guardarRoster: async (e: unknown[]) => { guardados.push(e); },
  obtenerRoster: async () => copia,
}));

import { cargarRoster } from "@/lib/terminal/roster";

const fila = (o: Record<string, unknown> = {}) => ({
  id: "p1", nombres: "Mariel", apellidos: "Sarmiento", sede_codigo: "TRU", sede_nombre: "Trujillo", foto_url: null, ...o,
});

beforeEach(() => {
  consultas.length = 0;
  respuestas = [];
  guardados.length = 0;
  copia = [];
  Object.defineProperty(globalThis, "navigator", { value: { onLine: true }, configurable: true });
});

describe("los días de prueba en el roster", () => {
  it("quien está de prueba trae sus días y el plazo; quien no, null — y se guardan juntos", async () => {
    respuestas = [{ data: [fila({ prueba_dias: 2, prueba_plazo: 3 }), fila({ id: "p2", nombres: "Ana", prueba_dias: null, prueba_plazo: null })], error: null }];
    const r = await cargarRoster();
    expect(r.fuente).toBe("servidor");
    expect(r.entradas[0]).toMatchObject({ id: "p1", pruebaDias: 2, pruebaPlazo: 3 });
    expect(r.entradas[1]).toMatchObject({ id: "p2", pruebaDias: null, pruebaPlazo: null });
    expect(guardados).toHaveLength(1);
    expect(consultas[0]).toContain("prueba_dias");
  });

  it("una base sin esas columnas (aún sin la 0539) no deja al terminal sin lista: se pide otra vez sin ellas", async () => {
    respuestas = [
      { data: null, error: { code: "42703", message: "column terminal_roster.prueba_dias does not exist" } },
      { data: [fila()], error: null },
    ];
    const r = await cargarRoster();
    expect(consultas).toHaveLength(2);
    expect(consultas[1]).not.toContain("prueba_");
    expect(r.fuente).toBe("servidor");
    expect(r.entradas).toHaveLength(1);
    expect(r.entradas[0]).toMatchObject({ pruebaDias: null, pruebaPlazo: null });
  });

  it("también se reconoce por el mensaje, aunque el código no venga", async () => {
    respuestas = [
      { data: null, error: { message: "Could not find the 'prueba_plazo' column of 'terminal_roster' in the schema cache" } },
      { data: [fila()], error: null },
    ];
    expect((await cargarRoster()).entradas).toHaveLength(1);
    expect(consultas).toHaveLength(2);
  });

  it("cualquier OTRO error NO reintenta: va a la copia guardada, como siempre", async () => {
    copia = [{ id: "viejo", nombres: "Copia", apellidos: "Guardada", sedeCodigo: "TRU", sedeNombre: "Trujillo" }];
    respuestas = [{ data: null, error: { code: "57014", message: "canceling statement due to statement timeout" } }];
    const r = await cargarRoster();
    expect(consultas).toHaveLength(1);
    expect(r.fuente).toBe("cache");
    expect(r.entradas[0]).toMatchObject({ id: "viejo" });
  });

  it("si el reintento sin las columnas también falla, queda la copia guardada", async () => {
    copia = [{ id: "viejo", nombres: "Copia", apellidos: "Guardada", sedeCodigo: "TRU", sedeNombre: "Trujillo" }];
    respuestas = [
      { data: null, error: { code: "42703", message: "column terminal_roster.prueba_dias does not exist" } },
      { data: null, error: { message: "network error" } },
    ];
    const r = await cargarRoster();
    expect(r.fuente).toBe("cache");
  });

  it("un valor que no es número nunca se cuela como días de prueba", async () => {
    respuestas = [{ data: [fila({ prueba_dias: "2", prueba_plazo: undefined })], error: null }];
    expect((await cargarRoster()).entradas[0]).toMatchObject({ pruebaDias: null, pruebaPlazo: null });
  });
});
