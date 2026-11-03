import { describe, it, expect } from "vitest";
// React vive en el paquete de la web, no en la raíz: se importa desde ahí, como
// ya hace `alertas-encargadas-ruta.test.ts` con Sentry.
import { createElement } from "../apps/web/node_modules/react";
import { renderToStaticMarkup } from "../apps/web/node_modules/react-dom/server.node.js";
import { ComunicacionCargos, escalonDeSuspension, type CargosDetalle } from "@/components/disciplina/comunicacion-cargos";
import { MemoDocumento, type DocMemo } from "@/components/disciplina/memo-documento";
import { AREAS_FALLBACK } from "@/lib/areas";

// Lo que pasó el 2026-11-02: con el plazo de descargo corriendo, a una
// colaboradora se le entregó el BORRADOR del memo —«se le impone AMONESTACIÓN
// ESCRITA», con su «Recibí conforme»— para que lo firmara, porque Dynamic no
// le mostraba los cargos. Desde la 0581 los cargos le llegan a su Info.
//
// Estas pruebas fijan, sobre el HTML que ella ve:
//   1. la comunicación de cargos dice lo que el 55.2 y el 19.3 exigen, nunca
//      impone nada, y no trae líneas de firma (la constancia es su clic);
//   2. lo que corrigió la revisión del 2026-11-03: el escalón de la suspensión
//      sin días fijados, el corte del 56.6, «la autoría o la hora» del 19.5, y
//      minutos que no contradicen en silencio a la hora;
//   3. el borrador del memo no recoge la firma de la persona.

const persona = { nombres: "Ana", apellidos: "Prueba", documento: "00000000", funcion: "calidad_servicio", sede_codigo: "TRU" };

const base: CargosDetalle = {
  id: "abcdef12-0000-0000-0000-000000000000",
  tipo_causal: "conducta",
  nivel: "amonestacion",
  estado: "borrador",
  periodo_desde: "2026-09-13",
  periodo_hasta: "2026-09-13",
  hechos: [{ fecha: "2026-09-13", relato: "Relato de prueba." }],
  suspension_dias: null,
  cargos_comunicados_at: null,
  descargo_vence_at: null,
  plazo_vigente: false,
  conocido_el: "2026-09-13",
  falta: { numeral: "53.2", literal: "e", texto: "Incumplir una instrucción.", gravedad: "significativa" },
  persona,
  previas: [],
  corte: null,
  medicion: [],
  recepcion: null,
  descargos: [],
  recomunicado: null,
};

function carta(doc: Partial<CargosDetalle> = {}) {
  return renderToStaticMarkup(createElement(ComunicacionCargos, { doc: { ...base, ...doc }, areas: AREAS_FALLBACK }));
}

const suspension = { correlativo: "SU-1", nivel: "suspension", firmado_at: null, entregado_at: "2026-05-01T15:00:00Z" };
const amonestacion = { correlativo: "AM-1", nivel: "amonestacion", firmado_at: null, entregado_at: "2026-04-01T15:00:00Z" };

describe("la comunicación de cargos", () => {
  it("no impone ninguna sanción: dice que no lo es y que se decide después del descargo", () => {
    const html = carta();
    expect(html).not.toMatch(/se le impone/i);
    expect(html).toContain("no es una sanción");
    expect(html).toContain("antes de adoptar decisión alguna");
    expect(html).toContain("Lo que se decida dependerá de la evaluación de su descargo");
  });

  it("se ve en pantalla: no trae líneas de firma ni acta de negativa", () => {
    const html = carta();
    expect(html).not.toContain("Recibí");
    expect(html).not.toContain("Testigo");
  });

  it("con cargos comunicados, dice hasta qué día y hora puede responder (hora de Lima)", () => {
    // 04-nov 23:59 en Lima = 05-nov 04:59 UTC: el caso real, y el que se corre
    // un día si alguien formatea en UTC.
    const html = carta({ cargos_comunicados_at: "2026-11-02T23:14:00Z", descargo_vence_at: "2026-11-05T04:59:59Z" });
    expect(html).toContain("hasta el 04 de noviembre de 2026, a las 23:59 h");
    expect(html).toContain("dos (2) días hábiles</strong> siguientes a esta comunicación");
  });

  it("en una conducta cita el literal del catálogo y el relato", () => {
    const html = carta();
    expect(html).toContain("literal e) del numeral 53.2");
    expect(html).toContain("Relato de prueba.");
  });

  it("en tardanzas entrega la hora programada y la registrada, y avisa si los minutos de hoy difieren (19.3)", () => {
    const html = carta({
      tipo_causal: "tardanza", falta: null, hechos: [{ fecha: "2026-10-03", minutos: 12 }],
      medicion: [{ fecha: "2026-10-03", entrada_ts: "2026-10-03T14:03:00Z", minutos_tarde: 3, entrada_programada: "09:00:00", es_descanso: false }],
    });
    expect(html).toContain("09:00");
    expect(html).toContain("09:03");
    expect(html).toContain("12′ (hoy 3′)");
    expect(html).toContain("literal b) del numeral 53.2");
  });

  it("en tardanzas le dice que puede cuestionar la autoría O LA HORA (19.5)", () => {
    expect(carta({ tipo_causal: "tardanza", falta: null, hechos: [{ fecha: "2026-10-03", minutos: 12 }] }))
      .toContain("la autoría o la hora");
  });

  it("en una inasistencia no promete una hora que ese día no existe", () => {
    const html = carta({ tipo_causal: "falta", falta: null, hechos: [{ fecha: "2026-10-03" }] });
    expect(html).not.toContain("Hora programada");
    expect(html).toContain("descanso semanal");
  });

  it("dice el corte del cómputo (56.6), haya o no un documento anterior", () => {
    expect(carta({ corte: "2026-08-31" })).toContain("No se computa ningún hecho anterior al 31 de agosto de 2026");
    expect(carta()).toContain("No hay un documento entregado anterior por la misma causa");
  });

  it("la suspensión dice su escalón y su rango, no los días ya decididos", () => {
    const html = carta({ tipo_causal: "tardanza", nivel: "suspension", falta: null, suspension_dias: 2,
      hechos: [{ fecha: "2026-10-03", minutos: 12 }], previas: [amonestacion] });
    expect(html).toContain("literal c) del numeral 19.2");
    expect(html).toContain("de uno (1) a dos (2) días");
    expect(html).not.toContain("de 2 días");
  });
});

describe("el escalón de una suspensión", () => {
  it("con una suspensión previa es la segunda, de mayor duración", () => {
    expect(escalonDeSuspension("tardanza", [suspension])).toContain("literal d) del numeral 19.2");
    expect(escalonDeSuspension("falta", [suspension])).toContain("literal c) del numeral 21.2");
  });
  it("sin ella es la primera, de uno a dos días", () => {
    expect(escalonDeSuspension("tardanza", [amonestacion])).toContain("literal c) del numeral 19.2");
    expect(escalonDeSuspension("falta", [])).toContain("literal b) del numeral 21.2");
  });
});

describe("el borrador del memo", () => {
  const memo = (estado: string, nivel = "amonestacion") => {
    const doc: DocMemo = {
      correlativo: estado === "borrador" ? null : "AM-2026-001", tipo_causal: "conducta", nivel, estado,
      periodo_desde: "2026-09-13", hechos: [{ fecha: "2026-09-13", relato: "Relato." }],
      suspension_dias: null, suspension_desde: null, suspension_hasta: null, suspension_fechas: null,
      firmado_at: estado === "borrador" ? null : "2026-11-05T15:00:00Z", creado_at: "2026-11-02T23:00:00Z",
      falta: base.falta, conocido_el: "2026-09-13",
    };
    return renderToStaticMarkup(createElement(MemoDocumento, {
      doc, persona, sede: "TRU", areas: AREAS_FALLBACK, firmante: null, cargoFirmante: null, firmaUrl: null, previas: [],
    }));
  };

  it("no trae línea de firma para la colaboradora ni manda a firmarlo", () => {
    const html = memo("borrador");
    expect(html).not.toContain("Recibí conforme");
    expect(html).not.toContain("Fírmalo");
    expect(html).toContain("la colaboradora no lo firma");
    expect(html).toContain("se le comunican los cargos en su Info");
  });

  it("firmado, vuelve a traer su «Recibí conforme» como siempre", () => {
    expect(memo("firmado")).toContain("Recibí conforme");
  });
});

// ── Lo que corrigió la revisión del PR 644 (2026-11-03) ──────────────────────
describe("el memo dice lo que el 55.3 y el 55.5 exigen", () => {
  const firmado = (extra: Partial<DocMemo> = {}, descargos: { texto: string; presentado_at: string }[] = [], previas: { correlativo: string | null; nivel: string; firmado_at: string | null; entregado_at: string | null }[] = []) => {
    const doc: DocMemo = {
      correlativo: "AM-2026-001", tipo_causal: "conducta", nivel: "amonestacion", estado: "firmado",
      periodo_desde: "2026-09-13", periodo_hasta: "2026-09-13", hechos: [{ fecha: "2026-09-13", relato: "Relato." }],
      suspension_dias: null, suspension_desde: null, suspension_hasta: null, suspension_fechas: null,
      firmado_at: "2026-11-05T15:00:00Z", creado_at: "2026-11-02T23:00:00Z",
      falta: base.falta, conocido_el: "2026-09-13", cargos_comunicados_at: "2026-11-03T00:58:00Z",
      ...extra,
    };
    return renderToStaticMarkup(createElement(MemoDocumento, {
      doc, persona, sede: "TRU", areas: AREAS_FALLBACK, firmante: "Quien firma", cargoFirmante: null, firmaUrl: null, previas, descargos,
    }));
  };

  it("trae la valoración del descargo que ella escribió en su Info", () => {
    const html = firmado({ descargo_acogido: "no", descargo_valoracion: "Su líder confirma que no avisó." },
      [{ texto: "Avisé.", presentado_at: "2026-11-03T14:00:00Z" }]);
    expect(html).toContain("Descargo y su valoración");
    expect(html).toContain("presentó su descargo por escrito en su Info");
    expect(html).toContain("No se acoge, por las siguientes razones: Su líder confirma que no avisó.");
  });

  it("sin descargo, lo dice sin tomarlo como aceptación", () => {
    expect(firmado({ descargo_acogido: "sin_descargo" })).toContain("no se recibió descargo. Este hecho no se interpreta como aceptación");
  });

  it("dice el corte del cómputo y cómo pedir la reconsideración (56.6, 55.5)", () => {
    const html = firmado({ descargo_acogido: "sin_descargo" });
    expect(html).toContain("solo considerará hechos posteriores al 13 de setiembre de 2026");
    expect(html).toContain("Reconsideración.");
    expect(html).toContain("cinco (5) días hábiles");
  });

  it("la amonestación por inasistencia ya no afirma un descuento del descanso semanal (20.5)", () => {
    const html = firmado({ tipo_causal: "falta", falta: null, hechos: [{ fecha: "2026-10-03" }] });
    expect(html).not.toContain("parte proporcional del descanso semanal");
    expect(html).toContain("sin descuento adicional alguno");
  });

  it("la suspensión cita su escalón: primera o segunda, y por conducta el 54.8", () => {
    const susp = { nivel: "suspension", tipo_causal: "tardanza", falta: null, suspension_dias: 2, hechos: [{ fecha: "2026-10-03", minutos: 12 }] };
    const primera = firmado(susp, [], [amonestacion]);
    expect(primera).toContain("literal c) del numeral 19.2");
    // «despido» sí aparece, en la reconsideración («sanción distinta al despido»);
    // lo que no puede aparecer es la amenaza de despido tras la primera.
    expect(primera).not.toContain("procedimiento de despido");
    expect(primera).toContain("segunda suspensión sin goce de haber");
    expect(firmado(susp, [], [amonestacion, suspension])).toContain("literal d) del numeral 19.2");
    const conducta = firmado({ nivel: "suspension", suspension_dias: 1 }, [], [amonestacion]);
    expect(conducta).toContain("numeral 54.8");
    expect(conducta).not.toContain("numeral 21.2");
  });
});

describe("la comunicación de una inasistencia y el artículo 22", () => {
  it("manda el caso del artículo 22 a DO, no al descargo que lee su líder", () => {
    const html = carta({ tipo_causal: "falta", falta: null, hechos: [{ fecha: "2026-10-03" }] });
    expect(html).toContain("comuníquelo directamente a Desarrollo Organizacional");
    expect(html).toContain("numeral 20.4");
  });
});
