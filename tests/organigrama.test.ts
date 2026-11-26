// ============================================================================
// organigrama.test.ts — La forma del dibujo del organigrama (0623)
// ============================================================================
import { describe, it, expect } from "vitest";
import {
  filasDelOrganigrama, leerOrganigrama, trazarLinea, type Bloque, type Nodo,
} from "@/lib/organigrama";

const bloque = (clave: string, fila: number, orden: number, columnas: number | null = null): Bloque =>
  ({ clave, nombre: clave, fila, orden, ancho: 1, columnas, discreto: false, orden_movil: orden });
const nodo = (id: string, b: string, nivel: number, columna: number | null = null, orden = 1): Nodo =>
  ({ persona_id: id, nombres: id, apellidos: "Prueba", foto_url: null, bloque: b, nivel, columna, orden,
    funcion: "x", etiqueta: null, color: null, discreto: false });

describe("las filas y los renglones", () => {
  const bloques = [bloque("direccion", 1, 2, 2), bloque("sistemas", 1, 1), bloque("tienda", 2, 1), bloque("vacio", 2, 2)];

  it("ordena los equipos por fila y posición, y no dibuja los vacíos", () => {
    const filas = filasDelOrganigrama(bloques, [nodo("a", "sistemas", 1), nodo("b", "direccion", 2, 1), nodo("c", "tienda", 1)]);
    expect(filas.map((f) => f.equipos.map((e) => e.bloque.clave))).toEqual([["sistemas", "direccion"], ["tienda"]]);
  });

  it("comparte renglones solo cuando algún equipo de la fila empieza más abajo", () => {
    const filas = filasDelOrganigrama(bloques, [
      nodo("a", "sistemas", 1), nodo("a2", "sistemas", 3), nodo("b", "direccion", 2, 1), nodo("c", "tienda", 1),
    ]);
    expect(filas[0]).toMatchObject({ comparteNiveles: true, ultimoNivel: 3 });
    expect(filas[1]).toMatchObject({ comparteNiveles: false, ultimoNivel: 1 });
  });

  it("sin columnas, el renglón se reparte entre quienes están, por orden", () => {
    const [fila] = filasDelOrganigrama([bloque("tienda", 1, 1)],
      [nodo("z", "tienda", 1, null, 2), nodo("a", "tienda", 1, null, 3), nodo("m", "tienda", 1, null, 1)]);
    const [nivel] = fila.equipos[0].niveles;
    expect(nivel.columnas).toBe(3);
    expect(nivel.celdas.map((c) => [c.nodo.persona_id, c.columna])).toEqual([["m", 1], ["z", 2], ["a", 3]]);
  });

  it("con columnas, cada quien cae en la suya y quien no la dice ocupa todo el renglón", () => {
    const [fila] = filasDelOrganigrama([bloque("tienda", 1, 1, 2)],
      [nodo("lado", "tienda", 1, 2), nodo("lider", "tienda", 1, 1), nodo("abajo", "tienda", 2)]);
    const [arriba, abajo] = fila.equipos[0].niveles;
    expect(arriba.celdas.map((c) => [c.nodo.persona_id, c.columna, c.ocupa])).toEqual([["lider", 1, 1], ["lado", 2, 1]]);
    expect(abajo.celdas[0]).toMatchObject({ columna: 1, ocupa: 2 });
  });
});

describe("las líneas", () => {
  const caja = (izq: number, arr: number, ancho = 100, alto = 50) => ({ izq, arr, der: izq + ancho, aba: arr + alto });

  it("a la misma altura, recta de borde a borde, en los dos sentidos", () => {
    expect(trazarLinea(caja(0, 0), caja(130, 0))).toBe("M100 25H130");
    expect(trazarLinea(caja(130, 0), caja(0, 0))).toBe("M130 25H100");
  });

  it("una encima de otra, recta vertical, en los dos sentidos", () => {
    expect(trazarLinea(caja(0, 0), caja(0, 80))).toBe("M50 50V80");
    expect(trazarLinea(caja(0, 80), caja(0, 0))).toBe("M50 50V80");
  });

  it("en diagonal dobla justo antes de quien recibe, así comparten el tronco", () => {
    const jefa = caja(150, 100);
    expect(trazarLinea(caja(0, 0), jefa)).toBe("M100 25H136V125H150");
    expect(trazarLinea(caja(0, 200), jefa)).toBe("M100 225H136V125H150");
  });
});

describe("leer la respuesta de la base", () => {
  it("lo que no viene se toma como vacío y sin permiso", () => {
    expect(leerOrganigrama(null)).toEqual({ publicado: false, puede_editar: false, bloques: [], personas: [], lineas: [], sin_ubicar: [] });
    expect(leerOrganigrama({ publicado: "si", personas: {} })).toMatchObject({ publicado: false, personas: [] });
  });
});
