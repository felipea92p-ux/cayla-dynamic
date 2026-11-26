// ============================================================================
// organigrama.test.ts — La forma del dibujo del organigrama (0623)
// ============================================================================
import { describe, it, expect } from "vitest";
import {
  asignarCarriles, filasDelOrganigrama, leerOrganigrama, redondear, tramoEn, trazarEntreFilas, trazarLinea,
  type Bloque, type Nodo,
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

describe("las líneas que unen filas distintas", () => {
  const caja = (izq: number, arr: number, ancho = 100, alto = 50) => ({ izq, arr, der: izq + ancho, aba: arr + alto });
  const filas = [{ arriba: 100, pasillos: [150, 450] }, { arriba: 300, pasillos: [] }];
  const jefa = caja(500, 20);

  it("a la fila siguiente: baja al canal, avanza y entra por el centro de la tarjeta", () => {
    const abajo = caja(0, 130);
    expect(trazarEntreFilas(jefa, abajo, { filas: filas.slice(0, 1), obstaculos: [jefa, abajo], carril: 0 }))
      .toBe("M550 70V114H50V130");
  });

  it("si hay una tarjeta justo debajo, sale por el costado izquierdo", () => {
    const debajo = caja(500, 80, 100, 20);
    const lejos = caja(700, 130);
    expect(trazarEntreFilas(jefa, lejos, { filas: filas.slice(0, 1), obstaculos: [jefa, debajo], carril: 1 }))
      .toBe("M500 45H488V124H750V130");
  });

  it("a dos filas: atraviesa la del medio por el pasillo más cercano a quien sale", () => {
    const abajo = caja(0, 330);
    expect(trazarEntreFilas(jefa, abajo, { filas, obstaculos: [jefa, abajo], carril: 0 }))
      .toBe("M550 70V114H450V314H50V330");
  });

  it("si el pasillo ya cae sobre la tarjeta de llegada, entra derecho", () => {
    const ancha = caja(200, 330, 400);
    expect(trazarEntreFilas(jefa, ancha, { filas, obstaculos: [jefa, ancha], carril: 0 }))
      .toBe("M550 70V114H450V314H450V330");
  });

  it("dos personas comparten altura salvo que sus tramos se pisen", () => {
    const c = asignarCarriles([{ clave: "a", ini: 0, fin: 300 }, { clave: "b", ini: 400, fin: 600 }, { clave: "c", ini: 250, fin: 420 }]);
    expect([c.get("a"), c.get("b"), c.get("c")]).toEqual([0, 0, 1]);
    expect(tramoEn("M550 70V114H150V314H50V330", 114)).toEqual({ ini: 150, fin: 550 });
  });

  it("redondea las esquinas y deja las rectas como rectas", () => {
    expect(redondear("M0 0V100H100", 10)).toBe("M0 0L0 90Q0 100 10 100L100 100");
    expect(redondear("M0 0H50H100", 10)).toBe("M0 0L100 0");
  });
});

describe("leer la respuesta de la base", () => {
  it("lo que no viene se toma como vacío y sin permiso", () => {
    expect(leerOrganigrama(null)).toEqual({ publicado: false, puede_editar: false, bloques: [], personas: [], lineas: [], sin_ubicar: [] });
    expect(leerOrganigrama({ publicado: "si", personas: {} })).toMatchObject({ publicado: false, personas: [] });
  });
});
