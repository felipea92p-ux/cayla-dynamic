import { describe, expect, it } from "vitest";
import {
  FILTRO_PERSONAS_INICIAL,
  hayFiltro,
  personasVisibles,
  type FiltroPersonas,
} from "@/lib/admin/costos-por-persona";

// Datos inventados: nombres y montos que no son de nadie.
const FILAS = [
  { nombre: "Ana Torres Ruiz", sede: "TRU", periodos: 4, horas: 700, costo: 4800 },
  { nombre: "María de los Ángeles Concepción Villanueva y Zegarra", sede: "TRU", periodos: 1, horas: 120, costo: 900 },
  { nombre: "Pedro Campos Salas", sede: "LIM", periodos: 4, horas: 760, costo: 5000 },
  { nombre: "Carmen Vega Núñez", sede: "AQP", periodos: 2, horas: 380, costo: 4800 },
  { nombre: "Luz Quispe Rojas", sede: "TRU", periodos: 2, horas: 380, costo: 2600 },
];

const con = (cambio: Partial<FiltroPersonas>): FiltroPersonas => ({ ...FILTRO_PERSONAS_INICIAL, ...cambio });
const nombres = (f: FiltroPersonas) => personasVisibles(FILAS, f).map((p) => p.nombre.split(" ")[0]);

describe("personasVisibles", () => {
  it("de entrada, quien más cuesta arriba; un empate de costo se desempata por nombre", () => {
    expect(nombres(FILTRO_PERSONAS_INICIAL)).toEqual(["Pedro", "Ana", "Carmen", "Luz", "María"]);
  });

  it("busca palabra por palabra, sin tildes ni mayúsculas", () => {
    expect(nombres(con({ texto: "maria zegarra" }))).toEqual(["María"]);
    expect(nombres(con({ texto: "  NUÑEZ " }))).toEqual(["Carmen"]);
    expect(nombres(con({ texto: "nadie" }))).toEqual([]);
  });

  it("filtra por sede, y se suma a lo buscado", () => {
    expect(nombres(con({ sede: "TRU" }))).toEqual(["Ana", "Luz", "María"]);
    expect(nombres(con({ sede: "TRU", texto: "luz" }))).toEqual(["Luz"]);
  });

  it("ordena por horas y por periodos, para los dos lados", () => {
    expect(nombres(con({ orden: "horas_desc" }))).toEqual(["Pedro", "Ana", "Carmen", "Luz", "María"]);
    expect(nombres(con({ orden: "horas_asc" }))).toEqual(["María", "Carmen", "Luz", "Ana", "Pedro"]);
    expect(nombres(con({ orden: "periodos_desc" }))).toEqual(["Pedro", "Ana", "Carmen", "Luz", "María"]);
    expect(nombres(con({ orden: "periodos_asc" }))).toEqual(["María", "Carmen", "Luz", "Pedro", "Ana"]);
    expect(nombres(con({ orden: "costo_asc" }))).toEqual(["María", "Luz", "Ana", "Carmen", "Pedro"]);
  });

  it("el orden no depende de cómo llegaron las filas", () => {
    const alReves = personasVisibles([...FILAS].reverse(), con({ orden: "horas_asc" })).map((p) => p.nombre);
    expect(alReves).toEqual(personasVisibles(FILAS, con({ orden: "horas_asc" })).map((p) => p.nombre));
  });

  it("no toca la lista que recibe", () => {
    const copia = FILAS.map((p) => p.nombre);
    personasVisibles(FILAS, con({ orden: "horas_asc" }));
    expect(FILAS.map((p) => p.nombre)).toEqual(copia);
  });
});

describe("hayFiltro", () => {
  it("solo cuando algo es distinto de lo de siempre", () => {
    expect(hayFiltro(FILTRO_PERSONAS_INICIAL)).toBe(false);
    expect(hayFiltro(con({ texto: "   " }))).toBe(false);
    expect(hayFiltro(con({ texto: "ana" }))).toBe(true);
    expect(hayFiltro(con({ sede: "LIM" }))).toBe(true);
    expect(hayFiltro(con({ orden: "horas_asc" }))).toBe(true);
  });
});
