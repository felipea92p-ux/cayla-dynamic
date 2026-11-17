import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { nombreDelPdfDeContrato } from "../apps/web/lib/admin/contrato-nombre-pdf";

// El nombre del PDF de un contrato. El defecto que esto cierra (2026-11-17): con Carla elegida en el
// generador, bajar el contrato de Pepe desde el archivo lo guardaba como «Carla … — Contrato de trabajo».

describe("nombreDelPdfDeContrato", () => {
  it("lleva el nombre de la persona del contrato, el tipo y desde cuándo rige", () => {
    expect(nombreDelPdfDeContrato({ persona: "Pepe Pérez Rojas", tipo: "nuevo", fechaInicio: "2026-09-01" })).toBe(
      "Pepe Pérez Rojas — Contrato de trabajo — 01 de setiembre de 2026",
    );
  });

  it("dos contratos de personas distintas nunca se llaman igual", () => {
    const pepe = nombreDelPdfDeContrato({ persona: "Pepe Pérez", tipo: "renovacion", fechaInicio: "2026-10-01" });
    const luis = nombreDelPdfDeContrato({ persona: "Luis Gómez", tipo: "renovacion", fechaInicio: "2026-10-01" });
    expect(pepe).not.toBe(luis);
    expect(pepe).toContain("Pepe Pérez");
    expect(luis).toContain("Luis Gómez");
  });

  it("dos documentos de la misma persona se distinguen por la fecha: la renovación no pisa al ingreso", () => {
    const ingreso = nombreDelPdfDeContrato({ persona: "Pepe Pérez", tipo: "nuevo", fechaInicio: "2026-03-01" });
    const renovacion = nombreDelPdfDeContrato({ persona: "Pepe Pérez", tipo: "renovacion", fechaInicio: "2026-09-01" });
    const otraRenovacion = nombreDelPdfDeContrato({ persona: "Pepe Pérez", tipo: "renovacion", fechaInicio: "2027-03-01" });
    expect(new Set([ingreso, renovacion, otraRenovacion]).size).toBe(3);
  });

  it("un convenio de prácticas y un adendum no se llaman «Contrato de trabajo»", () => {
    expect(nombreDelPdfDeContrato({ persona: "Ana Ríos", tipo: "convenio_practicas", fechaInicio: "2026-08-04" })).toBe(
      "Ana Ríos — Convenio de prácticas — 04 de agosto de 2026",
    );
    expect(nombreDelPdfDeContrato({ persona: "Ana Ríos", tipo: "adendum", fechaInicio: "2026-08-04" })).toContain(
      "Adendum al contrato",
    );
    expect(nombreDelPdfDeContrato({ persona: "Ana Ríos", tipo: "indefinido", fechaInicio: "2026-08-04" })).toContain(
      "Contrato de trabajo indefinido",
    );
  });

  it("la fecha no se corre un día: el 1 de enero sigue siendo el 1 de enero en Lima", () => {
    expect(nombreDelPdfDeContrato({ persona: "Pepe Pérez", tipo: "nuevo", fechaInicio: "2027-01-01" })).toContain(
      "01 de enero de 2027",
    );
  });

  it("un tipo que todavía no conoce cae en «Contrato de trabajo», como antes", () => {
    expect(nombreDelPdfDeContrato({ persona: "Pepe Pérez", tipo: "otro_que_vendra", fechaInicio: "2026-09-01" })).toBe(
      "Pepe Pérez — Contrato de trabajo — 01 de setiembre de 2026",
    );
  });

  it("sin fecha válida, el nombre y el tipo bastan", () => {
    expect(nombreDelPdfDeContrato({ persona: "Pepe Pérez", tipo: "nuevo", fechaInicio: null })).toBe(
      "Pepe Pérez — Contrato de trabajo",
    );
    expect(nombreDelPdfDeContrato({ persona: "Pepe Pérez", tipo: "nuevo", fechaInicio: "01/09/2026" })).toBe(
      "Pepe Pérez — Contrato de trabajo",
    );
  });

  it("sin nombre no inventa uno: devuelve null y el PDF queda con el título del sitio", () => {
    expect(nombreDelPdfDeContrato({ persona: "", tipo: "nuevo", fechaInicio: "2026-09-01" })).toBeNull();
    expect(nombreDelPdfDeContrato({ persona: "   ", tipo: "nuevo", fechaInicio: "2026-09-01" })).toBeNull();
    expect(nombreDelPdfDeContrato({ persona: null, tipo: "nuevo", fechaInicio: "2026-09-01" })).toBeNull();
  });
});

// La otra mitad del defecto no vive en la función sino en DE DÓNDE la pantalla saca el título.
// Una prueba de unidad no la ve, así que se lee el código: el título tiene que salir del documento
// abierto en el visor, y nunca volver a calcularse con la persona elegida en el generador.
describe("Contratos: el título del PDF sale del documento abierto", () => {
  const pantalla = readFileSync(join(__dirname, "../apps/web/app/(admin)/admin/contratos/page.tsx"), "utf8");
  const llamadas = [...pantalla.matchAll(/useTituloDocumento\(([^;]*)\);/g)].map((m) => m[1].trim());

  it("hay una sola llamada y lee el título del visor", () => {
    expect(llamadas).toEqual(["documentoAbierto?.titulo ?? null"]);
  });

  it("abrir un contrato del archivo nombra el PDF con los datos de esa fila", () => {
    expect(pantalla).toMatch(
      /nombreDelPdfDeContrato\(\{ persona: c\.persona, tipo: c\.tipo, fechaInicio: c\.fecha_inicio \}\)/,
    );
  });
});
