import { describe, it, expect } from "vitest";
import { cuentaEnCobertura, esRolAdministrativo } from "@cayla-dynamic/shared";

// Los casos son los de producción del 2026-09-19: CCO (cinco administradores en
// áreas de oficina) y OTRU (cuatro practicantes en «Crecimiento y expansión» y
// Daniel Ruiz, supervisor_sede).
const persona = (o: Partial<Parameters<typeof cuentaEnCobertura>[0]> = {}) => ({
  rol: "integrante", tipoVinculo: "planilla", esEncargadaPiso: false, areaOperativa: false, ...o,
});

describe("cuentaEnCobertura — operativa", () => {
  it("un practicante en un área de oficina cuenta como operativo (OTRU)", () => {
    expect(cuentaEnCobertura(persona({ tipoVinculo: "practicante" }), "central").operativa).toBe(true);
  });

  it("el practicante cuenta en cualquier tipo de sede, no solo en una central", () => {
    for (const tipo of ["tienda", "taller", "central"]) {
      expect(cuentaEnCobertura(persona({ tipoVinculo: "practicante" }), tipo).operativa).toBe(true);
    }
  });

  it("quien está de prueba en un área de oficina cuenta como operativo (Robert Cabrera en OTRU, 2026-10-19)", () => {
    for (const tipo of ["tienda", "taller", "central"]) {
      expect(cuentaEnCobertura(persona({ tipoVinculo: "prueba" }), tipo).operativa).toBe(true);
    }
  });

  it("RxH, no trabajador o vínculo vacío en un área de oficina NO cuentan como operativos", () => {
    for (const tipoVinculo of ["rxh", "no_trabajador", null, undefined, ""]) {
      expect(cuentaEnCobertura(persona({ tipoVinculo }), "central").operativa).toBe(false);
    }
  });

  it("estar de prueba no hace líder a nadie", () => {
    expect(cuentaEnCobertura(persona({ tipoVinculo: "prueba" }), "central").lider).toBe(false);
  });

  it("quien no es practicante sigue contando solo si su área es operativa", () => {
    expect(cuentaEnCobertura(persona({ areaOperativa: true }), "tienda").operativa).toBe(true);
    expect(cuentaEnCobertura(persona({ areaOperativa: false }), "tienda").operativa).toBe(false);
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
