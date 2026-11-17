// ============================================================================
// bandeja-compartida.test.ts — De quién es la lectura que se comparte
// ============================================================================
// El lector de la Bandeja vive en la memoria de la pestaña. Lo que se defiende:
//
// 1. MISMA PERSONA Y ROL, MISMO LECTOR: el menú, la pantalla, el Dashboard y
//    Equipo reciben el mismo objeto, que es lo que hace que compartan lectura.
// 2. OTRA PERSONA, OTRO LECTOR, aunque tenga el mismo rol. Dos líderes de equipo
//    ven sedes distintas: si la llave fuera solo el rol, quien entra después en
//    la misma pestaña vería la Bandeja de quien salió.
// 3. SIN SABER QUIÉN ES, NO HAY LECTOR.
// 4. AL CERRAR SESIÓN SE OLVIDA.
// ============================================================================
import { describe, expect, it } from "vitest";
import { lectorDeLaBandeja, olvidarLaBandeja } from "../apps/web/lib/admin/bandeja-compartida";

const ANA = "11111111-1111-1111-1111-111111111111";
const LUZ = "22222222-2222-2222-2222-222222222222";

describe("lectorDeLaBandeja", () => {
  it("la misma persona con el mismo rol recibe siempre el mismo lector", () => {
    olvidarLaBandeja();
    const a = lectorDeLaBandeja(ANA, "supervisor_sede");
    expect(a).not.toBeNull();
    expect(lectorDeLaBandeja(ANA, "supervisor_sede")).toBe(a);
  });

  it("otra persona con el mismo rol NO recibe el lector de la anterior", () => {
    olvidarLaBandeja();
    const deAna = lectorDeLaBandeja(ANA, "supervisor_sede");
    const deLuz = lectorDeLaBandeja(LUZ, "supervisor_sede");
    expect(deLuz).not.toBe(deAna);
    expect(deLuz?.ultima()).toBeNull();
  });

  it("la misma persona con otro rol tampoco comparte: cada rol ve otras secciones", () => {
    olvidarLaBandeja();
    expect(lectorDeLaBandeja(ANA, "lider_do")).not.toBe(lectorDeLaBandeja(ANA, "supervisor_sede"));
  });

  it("sin persona o sin rol no hay lector", () => {
    expect(lectorDeLaBandeja(null, "lider_do")).toBeNull();
    expect(lectorDeLaBandeja(ANA, null)).toBeNull();
    expect(lectorDeLaBandeja(undefined, undefined)).toBeNull();
  });

  it("al cerrar sesión se olvida: quien vuelve a entrar parte de un lector nuevo", () => {
    olvidarLaBandeja();
    const antes = lectorDeLaBandeja(ANA, "lider_do");
    olvidarLaBandeja();
    expect(lectorDeLaBandeja(ANA, "lider_do")).not.toBe(antes);
  });
});
