import { describe, it, expect } from "vitest";
import {
  estadoParaMostrar, grupoDeEstudio, personasSinSolicitar, nivelesDeApoyo, type PersonaActiva,
} from "@/lib/admin/educacion-grupos";

describe("grupoDeEstudio", () => {
  it("al día solo si ya hay una constancia aprobada", () => {
    expect(grupoDeEstudio({ estado_constancia: "al_dia", aprobadas: 2 })).toBe("al_dia");
  });

  it("al_dia SIN ninguna aprobada no es «al día»: no hay respaldo todavía", () => {
    expect(grupoDeEstudio({ estado_constancia: "al_dia", aprobadas: 0 })).toBe("por_completar");
  });

  it("cada estado cae en su grupo", () => {
    const g = (e: string) => grupoDeEstudio({ estado_constancia: e, aprobadas: 1 });
    expect(g("pendiente_revision")).toBe("por_revisar");
    expect(g("vencida")).toBe("en_falta");
    expect(g("rechazada")).toBe("en_falta");
    expect(g("por_vencer")).toBe("por_completar");
    expect(g("falta_enviar")).toBe("por_completar");
    expect(g("sin_calendario")).toBe("por_completar");
  });

  it("un estado desconocido nunca se presenta como al día", () => {
    expect(grupoDeEstudio({ estado_constancia: "algo_nuevo", aprobadas: 5 })).toBe("por_completar");
  });
});

describe("estadoParaMostrar", () => {
  it("al_dia sin constancias aprobadas no se pinta «Al día»", () => {
    expect(estadoParaMostrar({ estado_constancia: "al_dia", aprobadas: 0 }).etiqueta).toBe("Sin constancias aún");
  });
  it("al_dia con una aprobada sí, y el resto conserva su etiqueta", () => {
    expect(estadoParaMostrar({ estado_constancia: "al_dia", aprobadas: 1 }).etiqueta).toBe("Al día");
    expect(estadoParaMostrar({ estado_constancia: "vencida", aprobadas: 0 }).etiqueta).toBe("Vencida");
  });
  it("un pago único «sin calendario» dice «Sin fecha de pago»; los demás siguen con «Sin calendario de pagos» (0549)", () => {
    expect(estadoParaMostrar({ estado_constancia: "sin_calendario", aprobadas: 0, frecuencia_pago: "unico" }).etiqueta)
      .toBe("Sin fecha de pago");
    for (const f of ["mensual", "ciclo", "otra", null, undefined]) {
      expect(estadoParaMostrar({ estado_constancia: "sin_calendario", aprobadas: 0, frecuencia_pago: f }).etiqueta)
        .toBe("Sin calendario de pagos");
    }
  });
  it("un pago único «sin calendario» CON constancia aprobada (base de antes de la 0549) no dice que falte una fecha", () => {
    expect(estadoParaMostrar({ estado_constancia: "sin_calendario", aprobadas: 1, frecuencia_pago: "unico" }).etiqueta)
      .toBe("Pago único con constancia");
    // Mensual con constancia aprobada sigue como siempre.
    expect(estadoParaMostrar({ estado_constancia: "sin_calendario", aprobadas: 1, frecuencia_pago: "mensual" }).etiqueta)
      .toBe("Sin calendario de pagos");
  });
  it("en una fila con varios tramos manda la constancia del tramo que habla, no la suma de los demás", () => {
    // La fila suma 1 aprobada (de OTRO tramo en curso), pero el tramo que habla —pago único sin calendario— tiene 0.
    expect(estadoParaMostrar({ estado_constancia: "sin_calendario", aprobadas: 1, aprobadas_del_tramo: 0, frecuencia_pago: "unico" }).etiqueta)
      .toBe("Sin fecha de pago");
  });
  it("un pago único sustentado (al día, con constancia aprobada) está en el grupo «al_dia» y se pinta «Al día»", () => {
    const s = { estado_constancia: "al_dia", aprobadas: 1, frecuencia_pago: "unico" };
    expect(grupoDeEstudio(s)).toBe("al_dia");
    expect(estadoParaMostrar(s).etiqueta).toBe("Al día");
  });
});

const persona = (id: string, rango = "cayla", tope: number | null = 180): PersonaActiva =>
  ({ persona_id: id, persona: `Persona ${id}`, sede: "LIM", rango, tope });

describe("personasSinSolicitar", () => {
  const activas = [persona("a"), persona("b"), persona("c"), persona("d")];

  it("deja fuera a quien tiene un estudio, aunque ya haya terminado", () => {
    const r = personasSinSolicitar(activas, [{ persona_id: "a" }], [], new Set(), false);
    expect(r.map((p) => p.persona_id)).toEqual(["b", "c", "d"]);
  });

  it("deja fuera a quien tiene una solicitud por revisar", () => {
    const r = personasSinSolicitar(activas, [], [{ persona_id: "b" }], new Set(), false);
    expect(r.map((p) => p.persona_id)).toEqual(["a", "c", "d"]);
  });

  it("oculta a las liquidadas, salvo que se pidan", () => {
    const liq = new Set(["c"]);
    expect(personasSinSolicitar(activas, [], [], liq, false).map((p) => p.persona_id)).toEqual(["a", "b", "d"]);
    expect(personasSinSolicitar(activas, [], [], liq, true).map((p) => p.persona_id)).toEqual(["a", "b", "c", "d"]);
  });
});

describe("nivelesDeApoyo", () => {
  it("agrupa por rango, cuenta personas y ordena por techo", () => {
    const n = nivelesDeApoyo([
      persona("1", "support", 270), persona("2", "colibri", 90), persona("3", "support", 270), persona("4", "cayla", 180),
    ]);
    expect(n).toEqual([
      { rango: "colibri", tope: 90, personas: 1 },
      { rango: "cayla", tope: 180, personas: 1 },
      { rango: "support", tope: 270, personas: 2 },
    ]);
  });

  it("un rango sin techo cargado va al final y conserva el null", () => {
    const n = nivelesDeApoyo([persona("1", "raro", null), persona("2", "cayla", 180)]);
    expect(n.map((x) => x.rango)).toEqual(["cayla", "raro"]);
    expect(n[1].tope).toBeNull();
  });
});
