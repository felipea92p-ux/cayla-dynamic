import { describe, expect, it } from "vitest";
import { debeTenerSalario, finDeContratoProximo } from "../apps/web/lib/admin/equipo-situacion";

describe("debeTenerSalario — quién cuenta en «sin salario asignado»", () => {
  it("planilla, prueba y practicante deben tener tramo", () => {
    for (const t of ["planilla", "prueba", "practicante"]) {
      expect(debeTenerSalario({ tipo_vinculo: t, personal_direccion: false })).toBe(true);
    }
  });
  it("honorarios (rxh) y sin vínculo laboral no", () => {
    expect(debeTenerSalario({ tipo_vinculo: "rxh", personal_direccion: false })).toBe(false);
    expect(debeTenerSalario({ tipo_vinculo: "no_trabajador", personal_direccion: false })).toBe(false);
  });
  it("el personal de dirección no, sea cual sea su vínculo", () => {
    expect(debeTenerSalario({ tipo_vinculo: "planilla", personal_direccion: true })).toBe(false);
  });
});

describe("finDeContratoProximo — la ventana de 60 días", () => {
  const hoy = "2026-10-19";
  it("dentro de la ventana cuenta", () => expect(finDeContratoProximo("2026-12-18", hoy)).toBe(true));
  it("justo en el borde (60 días) cuenta, uno más no", () => {
    expect(finDeContratoProximo("2026-12-18", hoy)).toBe(true);
    expect(finDeContratoProximo("2026-12-19", hoy)).toBe(false);
  });
  it("un contrato a 14 meses ya no es una alerta", () => expect(finDeContratoProximo("2027-12-31", hoy)).toBe(false));
  it("uno que YA terminó y sigue activo cuenta: es lo más urgente", () => expect(finDeContratoProximo("2026-10-10", hoy)).toBe(true));
  it("sin fecha anotada no hay nada que avisar", () => expect(finDeContratoProximo(undefined, hoy)).toBe(false));
});
