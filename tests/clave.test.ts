// ============================================================================
// clave.test.ts — El único candado de las cuentas que ven todos los sueldos
// ============================================================================
// Hasta la auditoría, el panel pedía seis caracteres y nada más: «111111»
// entraba, y con eso se veía la planilla entera, los sueldos por persona y el
// padrón con documentos. No hay segundo factor detrás.
//
// La primera prueba de este archivo es la que DEBE bloquear. Un freno que solo
// se prueba con casos que pasan es un freno que no se ha probado — lección que
// esta casa ya pagó con el linter, escrito cuatro veces dando el push por bueno.
// ============================================================================
import { describe, expect, it } from "vitest";
import { LARGO_MINIMO_CLAVE, claveSirve, problemasDeClave } from "@cayla-dynamic/shared";

describe("lo que la auditoría encontró", () => {
  it("«111111» ya no entra", () => {
    expect(claveSirve("111111")).toBe(false);
  });

  it("y estirarlo a doce tampoco: sigue siendo un número repetido", () => {
    expect(claveSirve("111111111111")).toBe(false);
  });

  it("ni disfrazado de las tres familias", () => {
    // Cumple largo, minúscula, mayúscula y dígito — y sigue siendo «1» diez veces.
    expect(claveSirve("Aa1111111111")).toBe(false);
  });

  it("ni una seguidilla", () => {
    expect(claveSirve("Abcdefgh1234")).toBe(false);
  });
});

describe("problemasDeClave", () => {
  it("una clave razonable pasa", () => {
    expect(problemasDeClave("Nieve7Taller2Q")).toEqual([]);
  });

  it("dice TODO lo que falta de una vez, no de a uno por intento", () => {
    // Corta, sin mayúscula y sin número: tres cosas, tres avisos.
    expect(problemasDeClave("abcdf")).toHaveLength(3);
  });

  it("cuenta bien el largo que falta", () => {
    const p = problemasDeClave("Ab3");
    expect(p[0]).toContain(String(LARGO_MINIMO_CLAVE));
    expect(p[0]).toContain("3 caracteres");
  });

  it("no acepta el nombre de la empresa dentro", () => {
    expect(claveSirve("CaylaTaller29")).toBe(false);
  });

  it("no acepta tu propio correo dentro", () => {
    expect(claveSirve("Felipe29Taller", "felipe@cayla.pe")).toBe(false);
    // Y sin correo declarado, la misma clave no tiene por qué molestar.
    expect(claveSirve("Felipe29Taller")).toBe(true);
  });

  it("un correo cortísimo no descalifica media clave", () => {
    // El usuario «ana» tiene 3 letras: buscarlo dentro dejaría fuera cualquier
    // clave que lleve esas tres seguidas por casualidad («Ventana7Roja»).
    expect(claveSirve("Ventana7Roja", "ana@cayla.pe")).toBe(true);
  });

  it("no exige símbolos — se prefiere largo a `Cayla2026!`", () => {
    expect(claveSirve("mangoAzul2026")).toBe(true);
  });

  it("una seguidilla corta no descalifica: «2345» aparece por azar", () => {
    expect(claveSirve("Nqrt2345vwxy")).toBe(true);
  });
});
