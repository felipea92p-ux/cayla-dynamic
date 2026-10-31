// ============================================================================
// revision-turnos.test.ts — lo que se ve antes de volver un día pasado al horario base
// ============================================================================
// El caso que lo originó (2026-09-26): Diana, viernes 11 de septiembre, turno
// 13:45–19:45 y horario base 07:45–19:45. «Usar el horario base» quitaba el
// turno sin preguntar y su jornada pasaba a medirse contra las 07:45.
// ============================================================================
import { describe, expect, it } from "vitest";
import { consecuenciaDeUsarBase, type DiaParaRevisar } from "@/lib/admin/revision-turnos";

const diana: DiaParaRevisar = {
  etiqueta: "vie 11 sep", turnoTxt: "13:45–19:45", baseTxt: "07:45–19:45",
  turnoEntrada: "13:45", baseEntrada: "07:45", marco: "13:47",
};

describe("consecuenciaDeUsarBase", () => {
  it("Diana: marcó a la hora de su turno y el horario base la esperaba seis horas antes", () => {
    const t = consecuenciaDeUsarBase(diana);
    expect(t).toContain("Marcó a las 13:47");
    expect(t).toContain("6 h 2 min después de la entrada del horario base (07:45)");
    expect(t).toContain("puede quedar como tardanza");
  });

  it("un espejo viejo que la hacía llegar tarde: vuelve a la base y marcó antes", () => {
    const t = consecuenciaDeUsarBase({ ...diana, turnoEntrada: "07:45", turnoTxt: "07:45–19:45", baseEntrada: "13:45", baseTxt: "13:45–19:45", marco: "07:47" });
    expect(t).toContain("5 h 58 min antes de la entrada del horario base (13:45)");
    expect(t).not.toContain("tardanza");
  });

  it("minutos sueltos, sin horas", () => {
    expect(consecuenciaDeUsarBase({ ...diana, marco: "07:52" })).toContain("7 min después");
  });

  it("el turno era descanso y no marcó: con el horario base el día vuelve a ser laborable", () => {
    const t = consecuenciaDeUsarBase({ ...diana, turnoEntrada: null, turnoTxt: "descanso", marco: null });
    expect(t).toContain("le tocaba trabajar (07:45–19:45)");
    expect(t).toContain("puede quedar como falta");
  });

  it("el horario base ese día es descanso: lo dice, sin inventar tardanza", () => {
    const t = consecuenciaDeUsarBase({ ...diana, baseEntrada: null, baseTxt: "descanso" });
    expect(t).toContain("era descanso");
    expect(t).not.toContain("tardanza");
  });

  it("nunca afirma la sanción: tolerancias y excepciones las decide fn_recalcular_jornada", () => {
    for (const d of [diana, { ...diana, turnoEntrada: null, marco: null }]) {
      expect(consecuenciaDeUsarBase(d)).not.toMatch(/quedará como|es una (falta|tardanza)/);
    }
  });
});
