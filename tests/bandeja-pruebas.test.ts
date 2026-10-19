// ============================================================================
// bandeja-pruebas.test.ts — la prueba de tres días en la Bandeja (0536–0538)
// ============================================================================
// Lo que se defiende acá:
//
// 1. UNA PRUEBA ABIERTA ES UN PENDIENTE que se resuelve aquí mismo, con la urgencia
//    que le toca por sus DÍAS: vencida es «Vencido», cumplida es «Hoy», en curso
//    es «Próximos».
// 2. NO SE DICE DOS VECES. Quien está de prueba no «le falta un contrato» —la
//    prueba existe para no hacérselo todavía—, así que el «sin contrato» de
//    Contratos se calla para ella. Pero solo ese estado: un borrador sin firmar
//    o un contrato vencido sí son pendientes de verdad.
// 3. LOS CIERRES RECIENTES SON PARA ENTERARSE: DO ve lo que una líder decidió sola.
// 4. QUIÉN VE EL MÓDULO: la líder de equipo y DO.
// ============================================================================
import { describe, expect, it } from "vitest";
import { armarPendientes, FUENTES_VACIAS, modulosDeLaBandeja, type FuentesBandeja } from "../apps/web/lib/admin/bandeja-fuentes";
import { urgenciaCierrePrueba, urgenciaPrueba } from "../apps/web/lib/admin/bandeja-urgencia";
import type { CierrePrueba, FilaPrueba } from "../apps/web/lib/admin/pruebas";

const HOY = "2026-10-19";

function prueba(o: Partial<FilaPrueba> = {}): FilaPrueba {
  return {
    prueba_id: "p1", persona_id: "x1", nombres: "Mariel", apellidos: "Sarmiento", sede_id: "s", sede_codigo: "TRU",
    inicio: "2026-10-16", dias_trabajados: 1, dias_plazo: 3, situacion: "en_curso", ultima_jornada: "2026-10-16",
    registrada: true, horas_marcadas: 5.35, dni_cargado: true, ...o,
  };
}
function cierre(o: Partial<CierrePrueba> = {}): CierrePrueba {
  return {
    prueba_id: "c1", persona_id: "y1", nombres: "Deyvid", apellidos: "Gamboa", sede_codigo: "OTRU", resultado: "retirado",
    motivo: "Dijo que no volvía", decidida_por: "Ana Supervisora", cerrada_at: "2026-10-17T15:00:00Z",
    cerrada_fecha: "2026-10-16", dias_trabajados: 1, horas_marcadas: 3.79, ...o,
  };
}
const contratoBase = {
  estado: "sin_contrato", dias_restantes: null, fecha_fin_contrato: null, copia_entregada_at: null,
  comunicado_mtpe_at: null, copia_vence: null, mtpe_vence: null, dias_marcados_despues: 0,
  persona_id: "x1", persona: "Mariel Sarmiento", sede: "TRU", tipo: null,
};

describe("urgencia de una prueba abierta", () => {
  it("vencida es «Vencido» y cuenta cuánto se pasó; la que más se pasó va primero", () => {
    const a = urgenciaPrueba(prueba({ situacion: "vencida", dias_trabajados: 4 }));
    const b = urgenciaPrueba(prueba({ situacion: "vencida", dias_trabajados: 9 }));
    expect(a).toMatchObject({ grupo: "vencido", plazo: "Pasó el plazo", nota: "4 días trabajados" });
    expect(b.orden).toBeLessThan(a.orden);
  });

  it("cumplida es «Hoy»: completó el plazo y toca decidir", () => {
    expect(urgenciaPrueba(prueba({ situacion: "cumplida", dias_trabajados: 3 })))
      .toMatchObject({ grupo: "hoy", plazo: "Toca decidir" });
  });

  it("en curso es «Próximos» y dice cuántos días faltan, en singular y plural", () => {
    expect(urgenciaPrueba(prueba({ dias_trabajados: 1 }))).toMatchObject({ grupo: "proximo", plazo: "Faltan 2 días", nota: "lleva 1 de 3" });
    expect(urgenciaPrueba(prueba({ dias_trabajados: 2 }))).toMatchObject({ plazo: "Falta 1 día" });
  });
});

describe("el cierre reciente", () => {
  it("no tiene plazo: es para enterarse, y lo más reciente va primero", () => {
    const viejo = urgenciaCierrePrueba(cierre({ cerrada_at: "2026-10-17T15:00:00Z" }));
    const nuevo = urgenciaCierrePrueba(cierre({ cerrada_at: "2026-10-18T15:00:00Z" }));
    expect(viejo.grupo).toBe("sin_plazo");
    expect(nuevo.orden).toBeLessThan(viejo.orden);
    expect(viejo).toMatchObject({ plazo: "Se retiró", nota: "decidió Ana Supervisora" });
    expect(urgenciaCierrePrueba(cierre({ resultado: "no_apto", decidida_por: null })))
      .toMatchObject({ plazo: "No fue apto", nota: null });
  });
});

describe("armar los pendientes", () => {
  it("una prueba cae en el módulo «pruebas», se resuelve aquí y avisa si falta el DNI", () => {
    const f: FuentesBandeja = { ...FUENTES_VACIAS, pruebas: [prueba({ dni_cargado: false })] };
    const filas = armarPendientes(f, { hoy: HOY });
    expect(filas).toHaveLength(1);
    expect(filas[0]).toMatchObject({
      tipo: "prueba", modulo: "pruebas", resolucion: "aqui", personaId: "x1", persona: "Mariel Sarmiento", sede: "TRU",
    });
    expect(filas[0].detalle).toContain("falta el DNI");
  });

  it("con el DNI guardado no lo pide", () => {
    const filas = armarPendientes({ ...FUENTES_VACIAS, pruebas: [prueba({ dni_cargado: true })] }, { hoy: HOY });
    expect(filas[0].detalle).not.toContain("falta el DNI");
  });

  it("un cierre reciente es un pendiente de enterarse, con quién y cuántas horas quedaron", () => {
    const filas = armarPendientes({ ...FUENTES_VACIAS, cierresPruebas: [cierre()] }, { hoy: HOY });
    expect(filas[0]).toMatchObject({ tipo: "prueba_cierre", modulo: "pruebas", resolucion: "aqui", titulo: "Se retiró en su prueba" });
    expect(filas[0].detalle).toContain("decidió Ana Supervisora");
    expect(filas[0].detalle).toContain("sin pagar");
  });

  it("quien está de prueba NO aparece además como «sin contrato»", () => {
    const f: FuentesBandeja = { ...FUENTES_VACIAS, pruebas: [prueba()], contratos: [contratoBase] };
    const filas = armarPendientes(f, { hoy: HOY });
    expect(filas.map((p) => p.tipo)).toEqual(["prueba"]);
  });

  it("pero un borrador sin firmar o un contrato vencido de esa persona SÍ siguen siendo pendientes", () => {
    for (const estado of ["sin_firmar", "vencido", "desnaturalizado"]) {
      const f: FuentesBandeja = { ...FUENTES_VACIAS, pruebas: [prueba()], contratos: [{ ...contratoBase, estado, dias_restantes: -3 }] };
      expect(armarPendientes(f, { hoy: HOY }).map((p) => p.tipo).sort()).toEqual(["contrato", "prueba"]);
    }
  });

  it("y el «sin contrato» de alguien que NO está de prueba se queda como estaba", () => {
    const f: FuentesBandeja = { ...FUENTES_VACIAS, pruebas: [prueba({ persona_id: "otra" })], contratos: [contratoBase] };
    expect(armarPendientes(f, { hoy: HOY }).map((p) => p.tipo).sort()).toEqual(["contrato", "prueba"]);
  });
});

describe("quién ve el módulo", () => {
  it("DO y la líder de equipo; una integrante no", () => {
    expect(modulosDeLaBandeja("admin")).toContain("pruebas");
    expect(modulosDeLaBandeja("lider_do")).toContain("pruebas");
    expect(modulosDeLaBandeja("supervisor_sede")).toContain("pruebas");
    expect(modulosDeLaBandeja("integrante")).not.toContain("pruebas");
  });
});
