// ============================================================================
// bandeja-urgencia.test.ts — En qué grupo cae cada pendiente de la Bandeja
// ============================================================================
// Lo que se defiende acá no se ve mirando la pantalla con los datos de hoy:
//
// 1. «VENCE EN 0 DÍAS» ES HOY, NO VENCIDO. `dias_para_vencer = 0` es el último
//    día de vigencia y la asignación todavía paga.
// 2. EL PLAZO Y EL PAPEL SON DOS COSAS. Una asignación lejos de vencer con un
//    mes sin papel es «Documento pendiente», no un vencimiento.
// 3. UNA SOLICITUD DE VACACIONES SE MIDE POR SU INICIO, no por su espera.
// 4. EL DÍA DE LIMA. Un pedido de las 22:00 en Lima ya es otro día en UTC.
// 5. EL ORDEN ES ESTABLE aunque dos pendientes empaten en todo menos la clave.
// ============================================================================
import { describe, expect, it } from "vitest";
import {
  compararPendientes, conCese, documentoEducacion, enDias, urgenciaEducacion, urgenciaEspera,
  urgenciaInicio, urgenciaRecordVacaciones, urgenciaSinHorario,
} from "../apps/web/lib/admin/bandeja-urgencia";

const VENCE = { futuro: "Vence", pasado: "Venció" };

describe("enDias", () => {
  it("habla como persona, no como sistema", () => {
    expect(enDias(0, VENCE)).toBe("Vence hoy");
    expect(enDias(1, VENCE)).toBe("Vence mañana");
    expect(enDias(12, VENCE)).toBe("Vence en 12 días");
    expect(enDias(-1, VENCE)).toBe("Venció hace 1 día");
    expect(enDias(-3, VENCE)).toBe("Venció hace 3 días");
  });
});

// ⇩ CAMBIO 0450 ⇩ Educación se mide contra su CONSTANCIA, no contra el fin de la
// asignación: «vence en 0 días» era casi siempre una renovación normal.
describe("urgenciaEducacion", () => {
  const hoy = "2026-09-15";
  const base = {
    estado_constancia: "al_dia", vigencia: "vigente", plazo: null, fecha_pago_constancia: null,
    pago_proximo: false, dias_para_pago: null, proxima_fecha_pago: null,
  };

  it("una constancia vencida es Vencido, y dice hace cuánto venció su plazo", () => {
    const u = urgenciaEducacion({ ...base, estado_constancia: "vencida", plazo: "2026-09-09", fecha_pago_constancia: "2026-09-05" }, hoy);
    expect(u.grupo).toBe("vencido");
    expect(u.plazo).toBe("Venció hace 6 días");
    expect(u.nota).toBe("pago del 5 de setiembre");
  });

  it("un pago a la institución que es hoy es Hoy; más adelante, Próximos", () => {
    expect(urgenciaEducacion({ ...base, pago_proximo: true, dias_para_pago: 0, proxima_fecha_pago: hoy }, hoy))
      .toMatchObject({ grupo: "hoy", plazo: "Paga hoy" });
    expect(urgenciaEducacion({ ...base, pago_proximo: true, dias_para_pago: 5, proxima_fecha_pago: "2026-09-20" }, hoy))
      .toMatchObject({ grupo: "proximo", plazo: "Paga en 5 días" });
  });

  it("un estudio sin calendario no tiene contra qué medirse: Sin plazo", () => {
    expect(urgenciaEducacion({ ...base, estado_constancia: "sin_calendario" }, hoy).grupo).toBe("sin_plazo");
  });

  it("vencida manda sobre un pago cercano: lo que falta pesa más que lo que viene", () => {
    const u = urgenciaEducacion({ ...base, estado_constancia: "vencida", plazo: "2026-09-10", pago_proximo: true, dias_para_pago: 2 }, hoy);
    expect(u.grupo).toBe("vencido");
  });
});

describe("documentoEducacion", () => {
  const base = {
    estado_constancia: "al_dia", vigencia: "vigente", plazo: null, fecha_pago_constancia: null,
    pago_proximo: false, dias_para_pago: null, proxima_fecha_pago: null,
  };
  it("dice qué falta y a qué lleva el botón", () => {
    expect(documentoEducacion({ ...base, estado_constancia: "vencida" }))
      .toEqual({ titulo: "Constancia de estudios vencida", accion: "Pedir constancia" });
    expect(documentoEducacion({ ...base, pago_proximo: true }).accion).toBe("Ver estudio");
    expect(documentoEducacion({ ...base, estado_constancia: "sin_calendario" }).accion).toBe("Fijar calendario");
  });
});

describe("urgenciaInicio — solicitudes de vacaciones", () => {
  const hoy = "2026-09-15";
  it("por su fecha de inicio", () => {
    expect(urgenciaInicio("2026-09-15", hoy)).toMatchObject({ grupo: "hoy", plazo: "Empiezan hoy" });
    expect(urgenciaInicio("2026-09-13", hoy)).toMatchObject({ grupo: "vencido", plazo: "Empezaron hace 2 días" });
    expect(urgenciaInicio("2026-09-28", hoy)).toMatchObject({ grupo: "proximo", plazo: "Empiezan en 13 días" });
  });
});

describe("urgenciaEspera", () => {
  const hoy = "2026-09-15";
  it("pasa a Vencido desde el día 8", () => {
    expect(urgenciaEspera("2026-09-08T15:00:00Z", hoy)).toMatchObject({ grupo: "sin_plazo", plazo: "Esperando 7 días" });
    expect(urgenciaEspera("2026-09-07T15:00:00Z", hoy)).toMatchObject({ grupo: "vencido", plazo: "Esperando 8 días" });
  });

  it("cuenta en días de Lima: las 22:00 del 14 en Lima son las 03:00 del 15 en UTC", () => {
    expect(urgenciaEspera("2026-09-15T03:00:00Z", hoy).plazo).toBe("Esperando 1 día");
    expect(urgenciaEspera("2026-09-15T14:00:00Z", hoy).plazo).toBe("Pedido hoy");
  });
});

describe("récord de vacaciones y sin horario", () => {
  it("un récord ya vencido es Vencido aunque la fecha diga otra cosa", () => {
    expect(urgenciaRecordVacaciones({ records_vencidos: 1, dias_para_vencer: 200, vence_el: "2027-04-03" }).grupo).toBe("vencido");
    expect(urgenciaRecordVacaciones({ records_vencidos: 0, dias_para_vencer: 5, vence_el: "2026-09-20" }))
      .toMatchObject({ grupo: "proximo", plazo: "Vence en 5 días" });
  });

  it("sin horario es riesgo ya corriendo", () => {
    expect(urgenciaSinHorario({ dias: 3, primer_dia: "2026-09-08", nunca_tuvo_horario: false }).grupo).toBe("vencido");
  });
});

describe("conCese y el orden", () => {
  it("quien cesó baja a Sin plazo y conserva su texto", () => {
    const u = conCese(urgenciaSinHorario({ dias: 3, primer_dia: "2026-09-08", nunca_tuvo_horario: true }));
    expect(u).toMatchObject({ grupo: "sin_plazo", plazo: "Riesgo en curso" });
  });

  it("grupo, luego lo más vencido, luego persona, luego clave", () => {
    const hoy = "2026-09-15";
    const filas = [
      { clave: "b", persona: "Zoe", urgencia: urgenciaEspera("2026-09-14T15:00:00Z", hoy) },
      { clave: "a", persona: "Ana", urgencia: urgenciaInicio("2026-09-15", hoy) },
      { clave: "d", persona: "Luz", urgencia: urgenciaEspera("2026-09-01T15:00:00Z", hoy) },
      { clave: "c", persona: "Luz", urgencia: urgenciaEspera("2026-09-05T15:00:00Z", hoy) },
      { clave: "f", persona: "Eva", urgencia: urgenciaEspera("2026-09-14T15:00:00Z", hoy) },
      { clave: "e", persona: "Eva", urgencia: urgenciaEspera("2026-09-14T15:00:00Z", hoy) },
    ];
    expect([...filas].sort(compararPendientes).map((f) => f.clave)).toEqual(["d", "c", "a", "e", "f", "b"]);
  });
});
