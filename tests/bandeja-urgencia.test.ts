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

describe("urgenciaEducacion", () => {
  const base = { semaforo: "vigente", meses_sin_papel: 0, vigente_hasta: "2026-09-15" };

  it("0 días es Hoy, no Vencido", () => {
    const u = urgenciaEducacion({ ...base, semaforo: "por_vencer", dias_para_vencer: 0 });
    expect(u.grupo).toBe("hoy");
    expect(u.plazo).toBe("Vence hoy");
  });

  it("una vencida dice hace cuánto", () => {
    const u = urgenciaEducacion({ ...base, semaforo: "vencida", meses_sin_papel: 2, dias_para_vencer: -6, vigente_hasta: "2026-09-09" });
    expect(u.grupo).toBe("vencido");
    expect(u.plazo).toBe("Venció hace 6 días");
  });

  it("dentro de 30 días es Próximo; más lejos, con papel faltante, es Sin plazo", () => {
    expect(urgenciaEducacion({ ...base, semaforo: "por_vencer", dias_para_vencer: 30 }).grupo).toBe("proximo");
    const lejos = urgenciaEducacion({ ...base, meses_sin_papel: 1, dias_para_vencer: 64 });
    expect(lejos.grupo).toBe("sin_plazo");
    expect(lejos.plazo).toBe("Documento pendiente");
  });
});

describe("documentoEducacion", () => {
  const base = { dias_para_vencer: 10, vigente_hasta: "2026-09-25" };
  it("separa el papel faltante del plazo", () => {
    expect(documentoEducacion({ ...base, semaforo: "sin_comprobante", meses_sin_papel: 0 }))
      .toEqual({ detalle: "Sin comprobante: no se paga hasta subirlo", faltaPapel: true });
    expect(documentoEducacion({ ...base, semaforo: "vencida", meses_sin_papel: 2 }).detalle)
      .toBe("Falta el papel de 2 meses ya pagados");
    expect(documentoEducacion({ ...base, semaforo: "por_vencer", meses_sin_papel: 0 }).faltaPapel).toBe(false);
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
