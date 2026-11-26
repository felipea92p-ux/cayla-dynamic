// ============================================================================
// organigrama.test.ts — La forma del dibujo del organigrama (0623)
// ============================================================================
import { describe, it, expect } from "vitest";
import {
  agruparLineas, asignarCarriles, fichasPorRenglon, filasDelOrganigrama, formaDelEquipo, leerOrganigrama, redondear,
  tituloDeEquipo, tramoEn, trazarEntreFilas, trazarLinea, type Bloque, type Lugar, type Nodo,
} from "@/lib/organigrama";

const bloque = (clave: string, fila: number, orden: number, columnas: number | null = null): Bloque =>
  ({ clave, nombre: clave, fila, orden, ancho: 1, columnas, discreto: false, orden_movil: orden });
const nodo = (id: string, b: string, nivel: number, columna: number | null = null, orden = 1): Nodo =>
  ({ persona_id: id, nombres: id, apellidos: "Prueba", foto_url: null, bloque: b, nivel, columna, orden,
    funcion: "x", etiqueta: null, color: null, discreto: false });

describe("las filas y la forma de cada equipo", () => {
  const bloques = [bloque("direccion", 1, 1, 2), bloque("sistemas", 1, 2), bloque("tienda", 2, 1), bloque("vacio", 2, 2)];
  bloques[0].ancho = 2;

  it("ordena los equipos por fila y posición, y no dibuja los vacíos", () => {
    const filas = filasDelOrganigrama(bloques, [nodo("a", "sistemas", 1), nodo("b", "direccion", 2, 1), nodo("c", "tienda", 1)]);
    expect(filas.map((f) => f.equipos.map((e) => e.bloque.clave))).toEqual([["direccion", "sistemas"], ["tienda"]]);
  });

  it("comparte renglones solo cuando algún equipo de la fila empieza más abajo", () => {
    const filas = filasDelOrganigrama(bloques, [
      nodo("a", "sistemas", 1), nodo("a2", "sistemas", 3), nodo("b", "direccion", 2, 1), nodo("c", "tienda", 1),
    ]);
    expect(filas[0]).toMatchObject({ comparteNiveles: true, primerNivel: 1, ultimoNivel: 3 });
    expect(filas[1]).toMatchObject({ comparteNiveles: false });
  });

  it("junto a otros, un equipo angosto es una sola columna, en orden de nivel y columna", () => {
    const [fila] = filasDelOrganigrama([{ ...bloque("tienda", 1, 1, 2), ancho: 1.35 }, bloque("otro", 1, 2)],
      [nodo("lado", "tienda", 1, 2), nodo("abajo", "tienda", 2), nodo("lider", "tienda", 1, 1), nodo("x", "otro", 1)]);
    const forma = formaDelEquipo(fila.equipos[0], false);
    expect(forma.tipo).toBe("columnas");
    expect(forma.grupos.map((g) => g.map((n) => n.persona_id))).toEqual([["lider", "lado", "abajo"]]);
  });

  it("el de ancho 2 reparte en dos columnas; quien no dice columna va en la primera", () => {
    const [fila] = filasDelOrganigrama(bloques,
      [nodo("derecha", "direccion", 2, 2), nodo("izquierda", "direccion", 2, 1), nodo("debajo", "direccion", 3, 1), nodo("s", "sistemas", 1)]);
    expect(formaDelEquipo(fila.equipos[0], false).grupos.map((g) => g.map((n) => n.persona_id)))
      .toEqual([["izquierda", "debajo"], ["derecha"]]);
  });

  it("solo en su fila, cada nivel es un renglón; de más de cuatro se parte de tres en tres", () => {
    const [fila] = filasDelOrganigrama([bloque("tienda", 1, 1)], [nodo("b", "tienda", 2), nodo("a", "tienda", 1)]);
    const forma = formaDelEquipo(fila.equipos[0], true);
    expect(forma.tipo).toBe("renglones");
    expect(forma.grupos.map((g) => g.length)).toEqual([1, 1]);
    expect([2, 4, 6].map(fichasPorRenglon)).toEqual([2, 4, 3]);
  });

  it("el nombre del equipo se parte en título y bajada", () => {
    expect(tituloDeEquipo("Lima · taller y tienda")).toEqual({ titulo: "Lima", bajada: "taller y tienda" });
    expect(tituloDeEquipo("Sistemas")).toEqual({ titulo: "Sistemas", bajada: null });
  });
});

describe("las líneas que se dibujan", () => {
  const lugares = new Map<string, Lugar>([
    ["jefa", { fila: 0, equipo: "dir", columna: 0, puesto: 0 }],
    ["debajo", { fila: 0, equipo: "dir", columna: 0, puesto: 1 }],
    ["jefe", { fila: 0, equipo: "dir", columna: 1, puesto: 0 }],
    ["ing1", { fila: 0, equipo: "sis", columna: 0, puesto: 0 }],
    ["ing2", { fila: 0, equipo: "sis", columna: 0, puesto: 1 }],
    ["t1", { fila: 2, equipo: "tienda", columna: 0, puesto: 0 }],
    ["t2", { fila: 2, equipo: "tienda", columna: 1, puesto: 0 }],
  ]);
  const linea = (desde: string, hasta: string, tipo: "equipo" | "asesoria" = "equipo") => ({ desde, hasta, tipo });

  it("dos que llegan al mismo equipo se dibujan una sola vez, desde quien las reparte", () => {
    expect(agruparLineas([linea("jefa", "t1"), linea("t2", "jefa")], lugares))
      .toEqual([{ clase: "a-equipo", tipo: "equipo", desde: "jefa", equipo: "tienda" }]);
  });

  it("en la misma fila sale de quien tiene varias", () => {
    expect(agruparLineas([linea("ing1", "jefe"), linea("ing2", "jefe")], lugares))
      .toEqual([{ clase: "al-lado", tipo: "equipo", desde: "jefe", hasta: ["ing1", "ing2"] }]);
  });

  it("dentro de un equipo solo se traza la de dos vecinas en línea de equipo", () => {
    expect(agruparLineas([linea("jefa", "debajo")], lugares)).toHaveLength(1);
    expect(agruparLineas([linea("jefa", "debajo", "asesoria"), linea("jefa", "jefe")], lugares)).toEqual([]);
    expect(agruparLineas([linea("jefa", "nadie")], lugares)).toEqual([]);
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
      .toBe("M500 45H486V124H750V130");
  });

  it("a dos filas: atraviesa la del medio por el pasillo más cercano a quien sale", () => {
    const abajo = caja(0, 330);
    expect(trazarEntreFilas(jefa, abajo, { filas, obstaculos: [jefa, abajo], carril: 0 }))
      .toBe("M550 70V114H450V314H50V330");
  });

  it("dos personas comparten altura salvo que sus tramos se pisen", () => {
    const c = asignarCarriles([{ clave: "a", ini: 0, fin: 300 }, { clave: "b", ini: 400, fin: 600 }, { clave: "c", ini: 250, fin: 420 }]);
    expect([c.get("a"), c.get("b"), c.get("c")]).toEqual([0, 0, 1]);
    // Entre dos que se pisan, va arriba quien sale más a la derecha.
    const dos = asignarCarriles([{ clave: "izq", ini: 0, fin: 400 }, { clave: "der", ini: 300, fin: 600 }]);
    expect([dos.get("der"), dos.get("izq")]).toEqual([0, 1]);
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
