// ============================================================================
// bandeja-fuentes-nuevas.test.ts — Contratos, Correcciones, Documentación,
// Feriados y Disciplina en la Bandeja (2026-09-15)
// ============================================================================
// Lo que se defiende acá:
//
// 1. CADA FUENTE USA EL CRITERIO DE SU PANTALLA, y donde esa pantalla traería
//    casos que no piden nada, no entran: un contrato `sin_vencimiento` (la
//    pantalla de Contratos lo cuenta como pendiente y como vigente a la vez) y
//    un feriado trabajado sin descanso registrado (por ley se paga la sobretasa).
// 2. CADA PLAZO ES EL REAL: el cierre del periodo para un día por revisar, el
//    trámite que falta para un contrato, los 30 días del descanso sustitutorio.
// 3. DISCIPLINA NO INVENTA ETAPAS: usa etapaDelBorrador y pendientesDeEntregado.
// 4. UNA FUENTE QUE FALLA NO SE PINTA «AL DÍA»: lo cubre `fallidas`.
// ============================================================================
import { describe, expect, it } from "vitest";
import {
  armarPendientes, FUENTES_VACIAS, modulosDeLaBandeja, pasoDisciplina, pendientesDeDocumento,
  type FuentesBandeja,
} from "../apps/web/lib/admin/bandeja-fuentes";
import {
  ESTADOS_CONTRATO_PENDIENTE, esFeriadoParaBandeja, sumarDias, urgenciaBono, urgenciaContrato,
  urgenciaDiaPorRevisar, urgenciaFeriado,
} from "../apps/web/lib/admin/bandeja-urgencia";
import type { DocDisciplina } from "../apps/web/lib/admin/disciplina";

const HOY = "2026-09-15";
const PERIODO = { fecha_ini: "2026-08-29", fecha_fin: "2026-09-28" };
const contratoBase = {
  estado: "ok", dias_restantes: null, fecha_fin_contrato: null, copia_entregada_at: null,
  comunicado_mtpe_at: null, copia_vence: null, mtpe_vence: null, dias_marcados_despues: 0,
};

describe("contratos", () => {
  it("sin_vencimiento y ok no entran; los seis que piden algo sí", () => {
    expect(ESTADOS_CONTRATO_PENDIENTE.has("sin_vencimiento")).toBe(false);
    expect(ESTADOS_CONTRATO_PENDIENTE.has("ok")).toBe(false);
    expect([...ESTADOS_CONTRATO_PENDIENTE].sort()).toEqual(
      ["desnaturalizado", "por_vencer", "sin_contrato", "sin_firmar", "tramite_pendiente", "vencido"]);
  });

  it("vencido y por vencer se miden contra su fin", () => {
    expect(urgenciaContrato({ ...contratoBase, estado: "vencido", dias_restantes: -4, fecha_fin_contrato: "2026-09-11" }, HOY))
      .toMatchObject({ grupo: "vencido", plazo: "Venció hace 4 días" });
    expect(urgenciaContrato({ ...contratoBase, estado: "por_vencer", dias_restantes: 10, fecha_fin_contrato: "2026-09-25" }, HOY))
      .toMatchObject({ grupo: "proximo", plazo: "Vence en 10 días" });
  });

  it("el trámite que falta decide el plazo: primero la copia, después el MTPE", () => {
    const tramite = { ...contratoBase, estado: "tramite_pendiente", copia_vence: "2026-09-17", mtpe_vence: "2026-09-10" };
    expect(urgenciaContrato(tramite, HOY)).toMatchObject({ grupo: "proximo", plazo: "Plazo vence en 2 días" });
    expect(urgenciaContrato({ ...tramite, copia_entregada_at: "2026-09-12" }, HOY))
      .toMatchObject({ grupo: "vencido", plazo: "Plazo venció hace 5 días" });
  });

  it("el riesgo art. 77 va primero de todo el grupo vencido", () => {
    const art77 = urgenciaContrato({ ...contratoBase, estado: "desnaturalizado", dias_marcados_despues: 2 }, HOY);
    const vencido = urgenciaContrato({ ...contratoBase, estado: "vencido", dias_restantes: -400 }, HOY);
    expect(art77.grupo).toBe("vencido");
    expect(art77.orden).toBeLessThan(vencido.orden);
  });
});

describe("correcciones: el plazo es el cierre del periodo que lo paga", () => {
  it("dentro del periodo abierto", () => {
    expect(urgenciaDiaPorRevisar("2026-09-12", false, PERIODO, HOY)).toMatchObject({ grupo: "proximo", plazo: "Periodo cierra en 13 días" });
    expect(urgenciaDiaPorRevisar("2026-09-12", false, PERIODO, "2026-09-28")).toMatchObject({ grupo: "hoy", plazo: "Periodo cierra hoy" });
  });

  it("antes del periodo abierto, o en uno ya pagado, es vencido", () => {
    expect(urgenciaDiaPorRevisar("2026-08-20", false, PERIODO, HOY)).toMatchObject({ grupo: "vencido", plazo: "Su periodo ya cerró" });
    expect(urgenciaDiaPorRevisar("2026-08-20", true, PERIODO, HOY)).toMatchObject({ grupo: "vencido", plazo: "Periodo ya pagado" });
  });

  it("sin periodo leído no se inventa un plazo", () => {
    expect(urgenciaDiaPorRevisar("2026-09-12", false, null, HOY).grupo).toBe("sin_plazo");
  });
});

describe("documentación", () => {
  const base = { persona_id: "p", persona: "P", sede: "TRU", estado: "ok", ruta_desfasada: false, bono_estado: "ok" };
  it("ruta sin firmar o desfasada; se_nego ya está resuelta", () => {
    expect(pendientesDeDocumento({ ...base, estado: "sin_ruta" }).ruta).toBe("sin_ruta");
    expect(pendientesDeDocumento({ ...base, ruta_desfasada: true }).ruta).toBe("desfasada");
    expect(pendientesDeDocumento({ ...base, estado: "se_nego" }).ruta).toBeNull();
  });

  it("bono: este mes o vencido; sin_fecha no (la pantalla lo deja en «nada que hacer»)", () => {
    expect(pendientesDeDocumento({ ...base, bono_estado: "este_mes" }).bono).toBe(true);
    expect(pendientesDeDocumento({ ...base, bono_estado: "vencido" }).bono).toBe(true);
    expect(pendientesDeDocumento({ ...base, bono_estado: "sin_fecha" }).bono).toBe(false);
    expect(urgenciaBono("este_mes", HOY)).toMatchObject({ grupo: "proximo", nota: "cargo antes del 30 de setiembre" });
    expect(urgenciaBono("este_mes", "2026-09-30").grupo).toBe("hoy");
  });
});

describe("feriados", () => {
  it("un feriado trabajado sin descanso registrado NO es un pendiente", () => {
    expect(esFeriadoParaBandeja({ fecha_feriado: "2026-08-30", estado: null, no_compensa_porque: null })).toBe(false);
    expect(esFeriadoParaBandeja({ fecha_feriado: "2026-08-30", estado: "OTORGADO", no_compensa_porque: null })).toBe(false);
    expect(esFeriadoParaBandeja({ fecha_feriado: "2026-08-30", estado: "PENDIENTE", no_compensa_porque: null })).toBe(true);
    expect(esFeriadoParaBandeja({ fecha_feriado: "2026-08-30", estado: null, no_compensa_porque: "cae en descanso" })).toBe(true);
  });

  it("el plazo son 30 días desde el feriado", () => {
    expect(sumarDias("2026-08-30", 30)).toBe("2026-09-29");
    expect(urgenciaFeriado({ fecha_feriado: "2026-08-30", estado: "PENDIENTE", no_compensa_porque: null }, HOY))
      .toMatchObject({ grupo: "proximo", plazo: "Plazo vence en 14 días" });
    expect(urgenciaFeriado({ fecha_feriado: "2026-07-29", estado: "PENDIENTE", no_compensa_porque: null }, HOY).grupo).toBe("vencido");
  });
});

describe("disciplina usa las etapas de su pantalla", () => {
  const doc = (x: Partial<DocDisciplina>): DocDisciplina => ({
    id: "d", persona_id: "p", tipo_causal: "tardanza", nivel: "amonestacion", estado: "borrador",
    periodo_desde: null, periodo_hasta: null, hechos: [], suspension_dias: null, suspension_desde: null,
    suspension_hasta: null, suspension_fechas: null, fecha_cese: null, resuelto_at: null, resuelto_resultado: null,
    resuelto_motivo: null, resuelto_por: null, cargos_comunicados_at: null, descargo_vence_at: null,
    descargo_acogido: null, descargo_valoracion: null, correlativo: null, creado_at: "2026-09-01T15:00:00Z",
    creado_por: null, firmante_id: null, firmado_at: null, entregado_at: null, entregado_por: null,
    medio_entrega: null, entrega_testigo_nombre: null, observacion: null, ...x,
  });
  const ahora = new Date("2026-09-15T15:00:00Z");

  it("borrador según su etapa; firmado es entregar; entregado sin cargo pide el cargo", () => {
    expect(pasoDisciplina(doc({}), [], true, ahora)).toBe("comunicar");
    expect(pasoDisciplina(doc({ cargos_comunicados_at: "2026-09-10T15:00:00Z", descargo_vence_at: "2026-09-20T15:00:00Z" }), [], true, ahora)).toBe("esperando");
    expect(pasoDisciplina(doc({}), [], false, ahora)).toBe("firmar");
    expect(pasoDisciplina(doc({ estado: "firmado" }), [], true, ahora)).toBe("entregar");
    expect(pasoDisciplina(doc({ estado: "entregado" }), [], true, ahora)).toBe("cargo");
    expect(pasoDisciplina(doc({ estado: "entregado" }), [{ id: "a", documento_id: "d", storage_path: "x", tipo: "cargo_firmado", nota: null, subido_at: "" }], true, ahora)).toBeNull();
    expect(pasoDisciplina(doc({ estado: "entregado", nivel: "imputacion" }), [], true, ahora)).toBe("cargo_y_resolver");
    expect(pasoDisciplina(doc({ estado: "anulado" }), [], true, ahora)).toBeNull();
  });
});

describe("la lista y las categorías", () => {
  it("cada fuente nueva cae en su módulo", () => {
    const f: FuentesBandeja = {
      ...FUENTES_VACIAS,
      periodo: PERIODO,
      contratos: [{ ...contratoBase, persona_id: "c", persona: "Carla", sede: "CCO", tipo: "plazo_fijo", estado: "vencido", dias_restantes: -2 }],
      diasPorRevisar: [{ persona_id: "d", nombre: "Dora", sede: "LIM", fecha: "2026-09-12", marcas: 3, periodo_pagado: false, motivo: "auto_cierre_sin_confirmar" }],
      documentos: [{ persona_id: "o", persona: "Olga", sede: "TRU", estado: "sin_ruta", ruta_desfasada: false, bono_estado: "este_mes" }],
      feriados: [{ persona_id: "e", nombre: "Eva", sede: "AQP", fecha_feriado: "2026-08-30", estado: "PENDIENTE", no_compensa_porque: null, feriado_nombre: "Santa Rosa", fecha_descanso: null }],
      disciplina: [{ id: "x", persona_id: "k", persona: "Karla", sede: "LIM", nivel: "amonestacion", creado_at: "2026-09-01T15:00:00Z", firmado_at: "2026-09-10T15:00:00Z", entregado_at: null, descargo_vence_at: null, paso: "entregar" }],
    };
    const filas = armarPendientes(f, { hoy: HOY });
    expect(filas.map((p) => p.modulo).sort()).toEqual(["contratos", "correcciones", "disciplina", "documentacion", "documentacion", "feriados"]);
    expect(filas.find((p) => p.tipo === "dia_por_revisar")?.titulo).toBe("Cierre automático sin confirmar: 12 de setiembre");
    expect(filas.find((p) => p.tipo === "disciplina")?.titulo).toBe("Amonestación escrita firmada, sin entregar");
    expect(filas.find((p) => p.tipo === "contrato")?.ir?.href).toBe("/admin/contratos?persona=c");
  });

  it("la encargada ve sus cinco módulos; DO ve los diez", () => {
    expect(modulosDeLaBandeja("supervisor_sede")).toEqual(["correcciones", "disciplina", "ausencias", "horarios", "datos_personales"]);
    expect(modulosDeLaBandeja("admin")).toHaveLength(10);
    expect(modulosDeLaBandeja("integrante")).toEqual([]);
  });
});
