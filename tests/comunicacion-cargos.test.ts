import { describe, it, expect } from "vitest";
// React vive en el paquete de la web, no en la raíz: se importa desde ahí, como
// ya hace `alertas-encargadas-ruta.test.ts` con Sentry.
import { createElement } from "../apps/web/node_modules/react";
import { renderToStaticMarkup } from "../apps/web/node_modules/react-dom/server.node.js";
import { ComunicacionCargos, type DocCargos } from "@/components/disciplina/comunicacion-cargos";
import { MemoDocumento, type DocMemo } from "@/components/disciplina/memo-documento";
import { AREAS_FALLBACK } from "@/lib/areas";

// Lo que pasó el 2026-11-02: con el plazo de descargo corriendo, a una
// colaboradora se le entregó el BORRADOR del memo —«se le impone AMONESTACIÓN
// ESCRITA», con su «Recibí conforme»— para que lo firmara, porque era el único
// papel que Dynamic imprimía. El 55.2 del RIT manda comunicar los hechos ANTES de
// imponer nada, y un papel que ya impone es la prueba de que se decidió sin
// escucharla.
//
// Estas pruebas fijan las dos mitades del arreglo, sobre el HTML que se imprime:
//   1. la comunicación de cargos dice lo que el 55.2 exige y nunca impone nada;
//   2. el borrador del memo no recoge la firma de la persona.

const persona = { nombres: "Ana", apellidos: "Prueba", documento: "00000000", funcion: "calidad_servicio" };

const base: DocCargos = {
  id: "abcdef12-0000-0000-0000-000000000000",
  tipo_causal: "conducta",
  nivel: "amonestacion",
  periodo_desde: "2026-09-13",
  hechos: [{ fecha: "2026-09-13", relato: "Relato de prueba." }],
  suspension_dias: null,
  cargos_comunicados_at: null,
  descargo_vence_at: null,
  falta: { numeral: "53.2", literal: "e", texto: "Incumplir una instrucción.", gravedad: "significativa" },
  conocido_el: "2026-09-13",
};

function carta(doc: Partial<DocCargos> = {}, medicion: { fecha: string; esperada: string; marco: string; minutos: number | null }[] = []) {
  return renderToStaticMarkup(createElement(ComunicacionCargos, {
    doc: { ...base, ...doc }, persona, sede: "TRU", areas: AREAS_FALLBACK, previas: [], medicion,
  }));
}

describe("la comunicación de cargos", () => {
  it("no impone ninguna sanción: dice que no lo es y que se decide después del descargo", () => {
    const html = carta();
    expect(html).not.toMatch(/se le impone/i);
    expect(html).toContain("no es una sanción");
    expect(html).toContain("antes de adoptar decisión alguna");
    expect(html).toContain("Lo que se decida dependerá de la evaluación de su descargo");
  });

  it("sin cargos comunicados en Dynamic, el plazo se cuenta desde la recepción del papel", () => {
    expect(carta()).toContain("dos (2) días hábiles</strong> siguientes a la recepción");
  });

  it("con cargos comunicados, trae el día y la hora exactos en que vence el plazo (hora de Lima)", () => {
    // 04-nov 23:59 en Lima = 05-nov 04:59 UTC: el caso real, y el que se corre
    // un día si alguien formatea en UTC.
    const html = carta({ cargos_comunicados_at: "2026-11-02T23:14:00Z", descargo_vence_at: "2026-11-05T04:59:59Z" });
    expect(html).toContain("04 de noviembre de 2026, a las 23:59 h");
    expect(html).not.toContain("siguientes a la recepción");
  });

  it("en una conducta cita el literal del catálogo y el relato", () => {
    const html = carta();
    expect(html).toContain("literal e) del numeral 53.2");
    expect(html).toContain("Relato de prueba.");
  });

  it("en tardanzas entrega la hora programada y la registrada de cada día (19.3)", () => {
    const html = carta(
      { tipo_causal: "tardanza", falta: null, hechos: [{ fecha: "2026-10-03", minutos: 12 }] },
      [{ fecha: "2026-10-03", esperada: "09:00", marco: "09:12", minutos: 12 }],
    );
    expect(html).toContain("09:00");
    expect(html).toContain("09:12");
    expect(html).toContain("literal b) del numeral 53.2");
  });

  it("la persona firma que la RECIBIÓ, no que está conforme", () => {
    const html = carta();
    expect(html).toContain("Recibí esta comunicación");
    expect(html).not.toContain("Recibí conforme");
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
    expect(html).toContain("comunicación de cargos");
  });

  it("firmado, vuelve a traer su «Recibí conforme» como siempre", () => {
    expect(memo("firmado")).toContain("Recibí conforme");
  });
});
