import { describe, it, expect } from "vitest";
import {
  armarHistorial, desdeAuditoria, desdeDisponibilidad, diaDelMotivo,
  type FilaAuditoria, type FilaDisponibilidad,
} from "@/lib/historial-horario";

const ELLA = "p-ella";
const LIDER = "p-lider";
const DO = "p-do";

function aud(campo: string, antes: string | null, despues: string | null, motivo: string, cuando: string, id = campo): FilaAuditoria {
  return { id, persona_id: ELLA, campo_modificado: campo, valor_anterior: antes, valor_nuevo: despues,
    corregido_at: cuando, motivo, corregido_por: LIDER };
}

function disp(over: Partial<FilaDisponibilidad>): FilaDisponibilidad {
  return {
    id: "d1", persona_id: ELLA, tipo: "parcial", estado: "aprobada", vigente_desde: "2026-11-10", vigente_hasta: null,
    horario_fijo: false, registrada_por: ELLA, creada_at: "2026-11-03T10:00:00+00:00",
    resuelta_por: LIDER, resuelta_at: "2026-11-04T09:00:00+00:00", respuesta: null,
    disponibilidad_bloques: [{ dia_semana: 2, desde: "08:30:00", hasta: "14:00:00", estado: "no_puede" }],
    ...over,
  };
}

describe("el día que afecta sale del motivo que arma la función", () => {
  it("turno y puesto traen el día; si no, no se inventa", () => {
    expect(diaDelMotivo("Turno del 12/11/2026 cambiado desde la pantalla de Turnos.")).toBe("2026-11-12");
    expect(diaDelMotivo("Puesto del 05/12/2026 planificado desde la pantalla de Turnos.")).toBe("2026-12-05");
    expect(diaDelMotivo("Cambio de horario por estudios")).toBeNull();
    expect(diaDelMotivo(null)).toBeNull();
  });
});

describe("cada cambio de la auditoría", () => {
  it("un turno: qué cambió, de qué a qué, qué día y quién", () => {
    const e = desdeAuditoria(aud("turnos.horario", "08:30–14:30", "descanso",
      "Turno del 12/11/2026 cambiado desde la pantalla de Turnos.", "2026-11-03T15:00:00+00:00"))!;
    expect(e.tipo).toBe("turno");
    expect(e.accion).toBe("Turno cambiado");
    expect(e.detalle).toBe("08:30–14:30 → descanso");
    expect(e.dia).toBe("2026-11-12");
    expect(e.quien).toBe(LIDER);
    expect(e.motivo).toBeNull();   // la frase de la función no se repite como motivo
  });

  it("la jornada: en horas, con el motivo que escribió DO y sin la coletilla", () => {
    const e = desdeAuditoria(aud("personas.jornada_semanal_horas", null, "45",
      "Contrato a tiempo completo — No cambia su pago: es la referencia de su semana.", "2026-11-03T15:00:00+00:00"))!;
    expect(e.accion).toBe("Jornada cambiada");
    expect(e.detalle).toBe("Pasa de sin registrar a 45 h por semana");
    expect(e.motivo).toBe("Contrato a tiempo completo");
  });

  it("lo que no es de horario no entra", () => {
    expect(desdeAuditoria(aud("timestamp_marca", "a", "b", "x", "2026-11-03T15:00:00+00:00"))).toBeNull();
  });
});

describe("la disponibilidad", () => {
  it("enviada por ella y aprobada por su líder son dos momentos", () => {
    const es = desdeDisponibilidad(disp({}));
    expect(es.map((e) => e.accion)).toEqual(["Disponibilidad enviada", "Disponibilidad aprobada"]);
    expect(es[0].quien).toBeNull();
    expect(es[0].detalle).toBe("No puede: los martes de 08:30 a 14:00. Desde el 10 nov.");
    expect(es[1].quien).toBe(LIDER);
  });
  it("registrada por DO es un solo momento, y dice quién", () => {
    const es = desdeDisponibilidad(disp({ registrada_por: DO, resuelta_por: DO, horario_fijo: true }));
    expect(es).toHaveLength(1);
    expect(es[0].accion).toBe("Disponibilidad registrada por DO");
    expect(es[0].quien).toBe(DO);
  });
  it("conversada: muestra lo que le escribió su líder", () => {
    const es = desdeDisponibilidad(disp({ estado: "conversar", respuesta: "¿Lo vemos el jueves?" }));
    expect(es[1].accion).toBe("Disponibilidad: pidió conversarla");
    expect(es[1].detalle).toBe("«¿Lo vemos el jueves?»");
  });
  it("en «Lo mío» le habla a ella", () => {
    expect(desdeDisponibilidad(disp({}), "tu")[0].detalle).toContain("No puedes:");
  });
});

describe("todo junto", () => {
  it("de lo más reciente a lo más viejo, mezclando auditoría y disponibilidad", () => {
    const h = armarHistorial(
      [aud("turnos.horario", "a", "b", "Turno del 12/11/2026 x", "2026-11-05T10:00:00+00:00", "t1"),
       aud("horarios_asignados", null, null, "Cambio por estudios", "2026-11-01T10:00:00+00:00", "h1")],
      [disp({})],
    );
    expect(h.map((e) => e.clave)).toEqual(["a-t1", "d-d1-resuelta", "d-d1-envio", "a-h1"]);
  });
});
