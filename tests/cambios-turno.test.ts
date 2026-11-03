import { describe, it, expect } from "vitest";
import { estadoParaElla, estaVivo, resumenCambio, tituloResultado } from "@/lib/cambios-turno";
import { armarBandeja } from "@/lib/bandeja-mia";

const base = {
  id: "c1", fecha: "2026-09-12", soy: "solicitante" as const, otra_nombre: "Ana Lab",
  mi_entrada: "08:30:00", mi_salida: "14:30:00", otra_entrada: "14:00:00", otra_salida: "20:00:00",
  estado: "propuesto" as const, comentario: null, respuesta_companera: null, respuesta: null,
  lo_propuso_su_lider: false, creado_at: "2026-09-06T15:00:00Z", contestado_at: null, resuelto_at: null,
};
const VACIO = {
  perfil: [], vacaciones: [], revisiones: [], contrato: null, memos: [], acuses: [], marcajes: [], periodo: null,
  movilidad: null, revisionesMovilidad: [], turnos: [], vistos: new Set<string>(),
};
const HOY = "2026-09-08";

describe("las palabras de un cambio", () => {
  it("dice qué turno por cuál y con quién", () => {
    expect(resumenCambio(base)).toBe("12 set: tu 08:30–14:30 por el 14:00–20:00 de Ana Lab");
  });
  it("en qué está, según quién pregunta", () => {
    expect(estadoParaElla(base)).toBe("Esperando a tu compañera");
    expect(estadoParaElla({ ...base, soy: "companera" })).toBe("Te lo piden: ¿aceptas?");
    expect(tituloResultado({ fecha: base.fecha, estado: "aprobado" })).toBe("Cambio de turno del 12 set: aprobado");
    expect(estaVivo("aceptado")).toBe(true);
    expect(estaVivo("aprobado")).toBe(false);
  });
});

describe("la Bandeja (0592)", () => {
  it("a la compañera le toca contestar, y no caduca", () => {
    const b = armarBandeja({ ...VACIO, cambiosTurno: [{ ...base, soy: "companera" }] }, HOY);
    expect(b.pendientes).toHaveLength(1);
    expect(b.pendientes[0].estado).toBe("por_contestar");
    expect(b.pendientes[0].titulo).toBe("Ana Lab te pide cambiar el turno del 12 de setiembre");
  });
  it("a quien lo pidió le queda esperando mientras está vivo", () => {
    const b = armarBandeja({ ...VACIO, cambiosTurno: [{ ...base, estado: "aceptado" }] }, HOY);
    expect(b.esperando).toHaveLength(1);
    expect(b.pendientes).toHaveLength(0);
  });
  it("aprobado: les llega a las dos como respuesta", () => {
    const fin = { ...base, estado: "aprobado" as const, resuelto_at: "2026-09-07T15:00:00Z" };
    for (const soy of ["solicitante", "companera"] as const) {
      const b = armarBandeja({ ...VACIO, cambiosTurno: [{ ...fin, soy }] }, HOY);
      expect(b.respuestas[0].estado).toBe("aprobado");
    }
  });
  it("un día que ya pasó no le pide nada a la compañera", () => {
    const b = armarBandeja({ ...VACIO, cambiosTurno: [{ ...base, soy: "companera", fecha: "2026-09-01" }] }, HOY);
    expect(b.pendientes).toHaveLength(0);
  });
});
