import { describe, it, expect } from "vitest";
import { cuentaEnCobertura, esRolAdministrativo, estaDePrueba } from "@cayla-dynamic/shared";

// Los casos son los de producción del 2026-09-19: CCO (cinco administradores en
// áreas de oficina) y OTRU (cuatro practicantes en «Crecimiento y expansión» y
// Daniel Ruiz, supervisor_sede).
const persona = (o: Partial<Parameters<typeof cuentaEnCobertura>[0]> = {}) => ({
  rol: "integrante", tipoVinculo: "planilla", esEncargadaPiso: false, areaOperativa: false, ...o,
});

describe("cuentaEnCobertura — operativa (el área manda; la prueba no suma, 2026-10-20)", () => {
  it("quien está en un área operativa cuenta, sea cual sea su vínculo", () => {
    for (const tipoVinculo of ["planilla", "practicante", "rxh", "no_trabajador"]) {
      expect(cuentaEnCobertura(persona({ tipoVinculo, areaOperativa: true }), "tienda").operativa).toBe(true);
    }
  });

  it("un practicante en un área de oficina YA NO cuenta: el área manda (revierte lo del 2026-09-19)", () => {
    for (const tipo of ["tienda", "taller", "central"]) {
      expect(cuentaEnCobertura(persona({ tipoVinculo: "practicante", areaOperativa: false }), tipo).operativa).toBe(false);
    }
  });

  it("quien está de prueba NO cuenta, aunque su área sea operativa (revierte lo del 2026-10-19)", () => {
    for (const tipo of ["tienda", "taller", "central"]) {
      expect(cuentaEnCobertura(persona({ tipoVinculo: "prueba", areaOperativa: true }), tipo).operativa).toBe(false);
      expect(cuentaEnCobertura(persona({ tipoVinculo: "prueba", areaOperativa: false }), tipo).operativa).toBe(false);
    }
  });

  it("cuando deja de estar de prueba, suma: cambia el vínculo y la regla lo toma sola", () => {
    expect(cuentaEnCobertura(persona({ tipoVinculo: "prueba", areaOperativa: true }), "tienda").operativa).toBe(false);
    expect(cuentaEnCobertura(persona({ tipoVinculo: "planilla", areaOperativa: true }), "tienda").operativa).toBe(true);
  });

  it("estaDePrueba solo es cierto para el vínculo «prueba»", () => {
    expect(estaDePrueba("prueba")).toBe(true);
    for (const v of ["planilla", "practicante", "rxh", null, undefined, ""]) expect(estaDePrueba(v)).toBe(false);
  });

  it("estar de prueba no hace líder a nadie", () => {
    expect(cuentaEnCobertura(persona({ tipoVinculo: "prueba" }), "central").lider).toBe(false);
  });

  it("un integrante en planilla de un área de oficina NO cuenta como operativo", () => {
    expect(cuentaEnCobertura(persona({ tipoVinculo: "planilla" }), "central").operativa).toBe(false);
  });
});

describe("cuentaEnCobertura — líder", () => {
  it("un administrador cuenta como líder en una sede central (CCO)", () => {
    expect(cuentaEnCobertura(persona({ rol: "admin" }), "central").lider).toBe(true);
    expect(cuentaEnCobertura(persona({ rol: "lider_do" }), "central").lider).toBe(true);
  });

  it("un administrador NO cuenta como líder en una tienda ni en un taller", () => {
    expect(cuentaEnCobertura(persona({ rol: "admin" }), "tienda").lider).toBe(false);
    expect(cuentaEnCobertura(persona({ rol: "admin" }), "taller").lider).toBe(false);
  });

  it("un tipo desconocido o vacío se trata como tienda: nunca cuenta de más", () => {
    expect(cuentaEnCobertura(persona({ rol: "admin" }), null).lider).toBe(false);
    expect(cuentaEnCobertura(persona({ rol: "admin" }), "almacen").lider).toBe(false);
  });

  it("la encargada cuenta como líder en cualquier sede (Daniel Ruiz en OTRU)", () => {
    for (const tipo of ["tienda", "taller", "central"]) {
      expect(cuentaEnCobertura(persona({ rol: "supervisor_sede" }), tipo).lider).toBe(true);
    }
  });

  it("la marca es_encargada_piso cuenta en cualquier sede: el admin que sí está en piso (0040)", () => {
    expect(cuentaEnCobertura(persona({ rol: "admin", esEncargadaPiso: true }), "tienda").lider).toBe(true);
  });

  it("un integrante no es líder por estar en una central", () => {
    expect(cuentaEnCobertura(persona({ rol: "integrante" }), "central").lider).toBe(false);
  });
});

describe("esRolAdministrativo", () => {
  it("admin y líder DO sí; encargada, integrante y vacío no", () => {
    expect(esRolAdministrativo("admin")).toBe(true);
    expect(esRolAdministrativo("lider_do")).toBe(true);
    expect(esRolAdministrativo("supervisor_sede")).toBe(false);
    expect(esRolAdministrativo("integrante")).toBe(false);
    expect(esRolAdministrativo(null)).toBe(false);
  });
});
