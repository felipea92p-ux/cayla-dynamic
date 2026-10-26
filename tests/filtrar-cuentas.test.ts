// ============================================================================
// filtrar-cuentas.test.ts — el buscador y el filtro por sede de /admin/cuentas
// ============================================================================
// Lo que se cuida: que quien busca con prisa encuentre a la persona (sin tildes, en
// cualquier orden, por nombre o por correo) y que el filtro por sede salga de los datos.
// Los nombres y correos son inventados.

import { describe, expect, it } from "vitest";
import { filtrarCuentas, sedesDe } from "@/lib/admin/filtrar-cuentas";

const cuentas = [
  { id: "1", nombre: "Ana Quispe", sede: "TRU", email: "ana.q@ejemplo.test" },
  { id: "2", nombre: "Beatriz Núñez", sede: "CCO", email: "bea@ejemplo.test" },
  { id: "3", nombre: "Carla Gutiérrez", sede: "TRU", email: null },
  { id: "4", nombre: "Diana Flores", sede: "LIM", email: "diana@otro.test" },
];

const ids = (xs: { id: string }[]) => xs.map((x) => x.id);

describe("filtrarCuentas", () => {
  it("sin filtro devuelve todas, en el mismo orden", () => {
    expect(ids(filtrarCuentas(cuentas, { busca: "", sede: null }))).toEqual(["1", "2", "3", "4"]);
  });

  it("un texto de solo espacios no filtra", () => {
    expect(ids(filtrarCuentas(cuentas, { busca: "   ", sede: null }))).toEqual(["1", "2", "3", "4"]);
  });

  it("por sede deja solo esa sede", () => {
    expect(ids(filtrarCuentas(cuentas, { busca: "", sede: "TRU" }))).toEqual(["1", "3"]);
  });

  it("por sede sin nadie devuelve vacío, no todas", () => {
    expect(filtrarCuentas(cuentas, { busca: "", sede: "AQP" })).toEqual([]);
  });

  it("busca sin tildes ni mayúsculas, en los dos sentidos", () => {
    expect(ids(filtrarCuentas(cuentas, { busca: "nunez", sede: null }))).toEqual(["2"]);
    expect(ids(filtrarCuentas(cuentas, { busca: "GUTIERREZ", sede: null }))).toEqual(["3"]);
    // y escribiendo la tilde contra un dato sin ella
    expect(ids(filtrarCuentas(cuentas, { busca: "Quíspe", sede: null }))).toEqual(["1"]);
  });

  it("las palabras pueden ir en cualquier orden, y todas tienen que estar", () => {
    expect(ids(filtrarCuentas(cuentas, { busca: "flores diana", sede: null }))).toEqual(["4"]);
    expect(filtrarCuentas(cuentas, { busca: "diana quispe", sede: null })).toEqual([]);
  });

  it("también encuentra por correo", () => {
    expect(ids(filtrarCuentas(cuentas, { busca: "otro.test", sede: null }))).toEqual(["4"]);
    expect(ids(filtrarCuentas(cuentas, { busca: "bea@", sede: null }))).toEqual(["2"]);
  });

  it("una cuenta sin correo no rompe la búsqueda ni coincide con «null»", () => {
    expect(ids(filtrarCuentas(cuentas, { busca: "carla", sede: null }))).toEqual(["3"]);
    expect(filtrarCuentas(cuentas, { busca: "null", sede: null })).toEqual([]);
  });

  it("sede y texto se combinan", () => {
    expect(ids(filtrarCuentas(cuentas, { busca: "a", sede: "TRU" }))).toEqual(["1", "3"]);
    expect(filtrarCuentas(cuentas, { busca: "diana", sede: "TRU" })).toEqual([]);
  });

  it("no modifica la lista que recibe", () => {
    const copia = structuredClone(cuentas);
    filtrarCuentas(cuentas, { busca: "ana", sede: "TRU" });
    expect(cuentas).toEqual(copia);
  });
});

describe("sedesDe", () => {
  it("sale de los datos: sin repetir y ordenadas", () => {
    expect(sedesDe(cuentas)).toEqual(["CCO", "LIM", "TRU"]);
  });

  it("sin cuentas no hay sedes", () => {
    expect(sedesDe([])).toEqual([]);
  });
});
