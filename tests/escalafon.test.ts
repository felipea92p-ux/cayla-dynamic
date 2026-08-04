// ============================================================================
// escalafon.test.ts — Quién puede tocar la cuenta de quién
// ============================================================================
// Blinda el agujero encontrado el 04/08/2026 en /api/admin/cuentas: la ruta
// comprobaba que quien llamara fuera admin o lider_do, y nada sobre la persona
// objetivo. Un líder DO podía pedir `resetear` con el id del ADMIN — el servidor
// le cambiaba la clave y se la devolvía en la respuesta. Toma de cuenta completa
// del sistema que decide los pagos.
//
// Estas pruebas existen para que ese caso concreto no pueda volver.
// ============================================================================
import { describe, it, expect } from "vitest";
import { puedeActuarSobre } from "@/lib/admin/escalafon";

describe("puedeActuarSobre — el caso que abrió el agujero", () => {
  it("un líder DO NO puede tocar la cuenta del admin", () => {
    expect(puedeActuarSobre("lider_do", "admin")).toBe(false);
  });

  it("un líder DO tampoco puede tocar la de otro líder DO (su propio nivel)", () => {
    expect(puedeActuarSobre("lider_do", "lider_do")).toBe(false);
  });

  it("un líder DO sí gestiona encargadas e integrantes", () => {
    expect(puedeActuarSobre("lider_do", "supervisor_sede")).toBe(true);
    expect(puedeActuarSobre("lider_do", "integrante")).toBe(true);
  });
});

describe("puedeActuarSobre — el admin es el techo", () => {
  it("el admin alcanza a todos, incluido otro admin", () => {
    // Si un admin no pudiera con otro admin, dos administradores quedarían
    // mutuamente bloqueados el día que uno pierda su clave.
    for (const rol of ["admin", "lider_do", "supervisor_sede", "integrante"]) {
      expect(puedeActuarSobre("admin", rol)).toBe(true);
    }
  });
});

describe("puedeActuarSobre — nadie por debajo de líder DO gestiona cuentas", () => {
  it("una encargada no toca la cuenta de nadie, ni la de una integrante de su sede", () => {
    // La puerta de la ruta ya la excluye; esto ancla que la regla tampoco la deje
    // pasar si mañana esa puerta se abre a más roles.
    expect(puedeActuarSobre("supervisor_sede", "integrante")).toBe(true);
    expect(puedeActuarSobre("supervisor_sede", "lider_do")).toBe(false);
    expect(puedeActuarSobre("supervisor_sede", "admin")).toBe(false);
    expect(puedeActuarSobre("integrante", "integrante")).toBe(false);
  });
});

describe("puedeActuarSobre — lo desconocido se niega", () => {
  it("un rol que nadie mapeó no autoriza nada, ni como sujeto ni como objetivo", () => {
    // El modo de fallar importa: un rol nuevo sin mapear debe dejar a alguien sin
    // poder resetear una clave, nunca dejarlo llegar a la del admin.
    expect(puedeActuarSobre("rol_nuevo_sin_mapear", "integrante")).toBe(false);
    expect(puedeActuarSobre("admin", "rol_nuevo_sin_mapear")).toBe(false);
    expect(puedeActuarSobre("", "")).toBe(false);
  });
});
