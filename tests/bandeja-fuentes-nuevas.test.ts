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
  urgenciaCaso, urgenciaDiaPorRevisar, urgenciaFeriado,
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

  it("el trámite pendiente siempre mide el plazo de la copia — el MTPE ya no es trámite de nadie (0470)", () => {
    // mtpe_vence viaja en la fila (fn_contratos_tablero sigue devolviéndolo)
    // pero ya no decide nada: `tramite_pendiente` solo significa "falta la
    // copia", así que el plazo que se lee es siempre copia_vence.
    const tramite = { ...contratoBase, estado: "tramite_pendiente", copia_vence: "2026-09-17", mtpe_vence: "2026-09-10" };
    expect(urgenciaContrato(tramite, HOY)).toMatchObject({ grupo: "proximo", plazo: "Plazo vence en 2 días" });
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
    medio_entrega: null, entrega_testigo_nombre: null, enviado_a_info_at: null, enviado_a_info_por: null,
    observacion: null, ...x,
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

  it("la encargada ve sus seis módulos; DO ve los once", () => {
    // «casos» (Reportes, 0488) entra para las dos: la base decide qué casos ve cada una.
    expect(modulosDeLaBandeja("supervisor_sede")).toEqual(["correcciones", "disciplina", "ausencias", "horarios", "datos_personales", "casos"]);
    expect(modulosDeLaBandeja("admin")).toHaveLength(11);
    expect(modulosDeLaBandeja("integrante")).toEqual([]);
  });
});

// ── El bono que alguien pidió desde su Info (0478) ─────────────────────────
// Lo que se defiende: que firmar la constancia NO sea lo que apaga el aviso
// de DO. `documento_bono` se va al firmar (el tablero ya dice `ok`); este
// otro queda, se resuelve aquí mismo, y espera como cualquier pedido.
describe("bono de cumpleaños por transferir", () => {
  const pedido = {
    documento_id: "b1", persona_id: "m", persona: "Melany Prueba", sede: "TRU",
    anio: 2026, monto: 180, pedido_el: "2026-09-14", pedido_at: "2026-09-14T15:00:00Z",
  };

  it("un pedido es una fila de Documentación que se resuelve aquí, con monto y fecha", () => {
    const filas = armarPendientes({ ...FUENTES_VACIAS, bonosPorTransferir: [pedido] }, { hoy: HOY });
    expect(filas).toHaveLength(1);
    expect(filas[0]).toMatchObject({
      tipo: "bono_por_transferir", itemId: "b1", personaId: "m", modulo: "documentacion",
      titulo: "Pidió su bono de cumpleaños", resolucion: "aqui", ir: null,
    });
    expect(filas[0].detalle).toContain("por transferir · lo pidió el 14 de setiembre");
    expect(filas[0].urgencia.grupo).toBe("sin_plazo");
  });

  it("a la semana sin transferir pasa a vencido", () => {
    const filas = armarPendientes(
      { ...FUENTES_VACIAS, bonosPorTransferir: [{ ...pedido, pedido_el: "2026-09-05", pedido_at: "2026-09-05T15:00:00Z" }] },
      { hoy: HOY });
    expect(filas[0].urgencia.grupo).toBe("vencido");
  });

  it("convive con el aviso de otra persona que todavía no lo pide", () => {
    const filas = armarPendientes({
      ...FUENTES_VACIAS,
      bonosPorTransferir: [pedido],
      documentos: [{ persona_id: "o", persona: "Olga", sede: "TRU", estado: "ok", ruta_desfasada: false, bono_estado: "este_mes" }],
    }, { hoy: HOY });
    expect(filas.map((p) => p.tipo).sort()).toEqual(["bono_por_transferir", "documento_bono"]);
  });
});

// ── Casos de Reportes (0488) ───────────────────────────────────────────────
// Lo que se defiende: que la fila de un caso no diga nunca quién reportó ni a
// quién (la Bandeja es de un vistazo), y que un caso urgente suba a «Hoy».
describe("casos de Reportes", () => {
  const caso = {
    id: "k1", codigo: "R-2026-0007", tipo: "persona", via: "convivencia", estado: "recibido", urgente: false,
    sede_codigo: "TRU", proximo_plazo: "Resolución escrita", proximo_norma: "43-A.6",
    proximo_vence_at: "2026-09-18T04:59:59Z",
  };
  it("se nombra por su código y lleva a su ficha", () => {
    const [fila] = armarPendientes({ ...FUENTES_VACIAS, casos: [caso] }, { hoy: HOY });
    expect(fila.persona).toBe("Caso R-2026-0007");
    expect(fila.personaId).toBeNull();
    expect(fila.titulo).toBe("Convivencia · 43-A");
    expect(fila.ir?.href).toBe("/admin/casos/k1");
    expect(fila.urgencia.grupo).toBe("proximo");
  });
  it("un caso urgente va a «Hoy» aunque su plazo sea más adelante", () => {
    expect(urgenciaCaso({ ...caso, urgente: true }, HOY).grupo).toBe("hoy");
  });
  it("un plazo pasado es vencido, urgente o no", () => {
    expect(urgenciaCaso({ ...caso, proximo_vence_at: "2026-09-14T04:59:59Z" }, HOY).grupo).toBe("vencido");
  });
});

// ── Conducta: el aviso a DO y el aviso a la líder (0515) ────────────────────
describe("la Bandeja avisa de lo que registra una líder y de lo que DO hace con su caso", () => {
  const conducta = {
    id: "doc-1", persona_id: "p-1", persona: "Andrea Torres", sede: "TRU", nivel: "amonestacion",
    creado_at: "2026-09-14T15:00:00Z", creador: "Lucía Ramos", falta: "Trato descortés (53.2 h)",
  };
  const traspaso = {
    id: "tr-1", expediente_id: "doc-1", persona_id: "p-1", persona: "Andrea Torres", sede: "TRU",
    accion: "tomar" as const, motivo: "El hecho fue con la tienda cerrada; lo reviso con ella.", hecho_at: "2026-09-14T16:00:00Z",
  };

  it("DO ve quién registró qué, y la falta con su nombre y su cita", () => {
    const [fila] = armarPendientes({ ...FUENTES_VACIAS, conductaRegistrada: [conducta] }, { hoy: HOY });
    expect(fila.tipo).toBe("conducta_registrada");
    expect(fila.titulo).toBe("Lucía Ramos registró una amonestación escrita");
    expect(fila.detalle).toBe("Trato descortés (53.2 h)");
    expect(fila.persona).toBe("Andrea Torres");
  });
  it("lleva al caso abierto, no a la lista: DO «solo visualiza» y para tomarlo tiene que verlo", () => {
    const [fila] = armarPendientes({ ...FUENTES_VACIAS, conductaRegistrada: [conducta] }, { hoy: HOY });
    expect(fila.ir?.href).toBe("/admin/disciplina#doc-doc-1");
    expect(fila.modulo).toBe("disciplina");
    expect(fila.resolucion).toBe("afuera");
  });
  it("la líder lee que DO tomó su caso, con el motivo de DO", () => {
    const [fila] = armarPendientes({ ...FUENTES_VACIAS, casosTraspasados: [traspaso] }, { hoy: HOY });
    expect(fila.tipo).toBe("caso_traspasado");
    expect(fila.titulo).toBe("Desarrollo Organizacional tomó tu caso");
    expect(fila.detalle).toBe("«El hecho fue con la tienda cerrada; lo reviso con ella.»");
  });
  it("y que se lo devolvió", () => {
    const [fila] = armarPendientes({ ...FUENTES_VACIAS, casosTraspasados: [{ ...traspaso, accion: "devolver" }] }, { hoy: HOY });
    expect(fila.titulo).toBe("Desarrollo Organizacional te devolvió el caso");
  });
  it("sin avisos, no hay filas: una Bandeja sin conducta no inventa ninguna", () => {
    expect(armarPendientes(FUENTES_VACIAS, { hoy: HOY })).toEqual([]);
  });
  it("cada aviso tiene su propia clave: el mismo caso puede avisarle a DO y a la líder a la vez", () => {
    const filas = armarPendientes({ ...FUENTES_VACIAS, conductaRegistrada: [conducta], casosTraspasados: [traspaso] }, { hoy: HOY });
    expect(new Set(filas.map((f) => f.clave)).size).toBe(2);
  });
});

// ── Lo entregado en papel que nadie confirmó haber leído (0516) ─────────────
describe("la Bandeja de DO avisa de lo entregado en papel que nadie leyó", () => {
  const pendiente = {
    id: "doc-7", persona_id: "p-7", persona: "Andrea Torres", sede: "TRU", nivel: "amonestacion",
    entregado_at: "2026-09-05T15:00:00Z", dias: 10, abierto: false,
  };

  it("dice cuántos días lleva y que todavía no lo abrió", () => {
    const [fila] = armarPendientes({ ...FUENTES_VACIAS, lecturasPendientes: [pendiente] }, { hoy: HOY });
    expect(fila.tipo).toBe("lectura_pendiente");
    expect(fila.titulo).toBe("No dejó constancia de haber leído su amonestación escrita");
    expect(fila.detalle).toBe("Todavía no lo abrió. Se lo entregaron hace 10 días.");
    expect(fila.persona).toBe("Andrea Torres");
  });
  it("distingue al que lo abrió y no confirmó de al que ni lo abrió: DO no le dice lo mismo", () => {
    const [fila] = armarPendientes({ ...FUENTES_VACIAS, lecturasPendientes: [{ ...pendiente, abierto: true }] }, { hoy: HOY });
    expect(fila.detalle).toBe("Lo abrió, pero no confirmó que lo leyó. Se lo entregaron hace 10 días.");
  });
  it("lleva al caso abierto, que es donde DO ve la constancia", () => {
    const [fila] = armarPendientes({ ...FUENTES_VACIAS, lecturasPendientes: [pendiente] }, { hoy: HOY });
    expect(fila.ir?.href).toBe("/admin/disciplina#doc-doc-7");
    expect(fila.modulo).toBe("disciplina");
    expect(fila.resolucion).toBe("afuera");
  });
  it("lo resuelve la persona al leer, no DO al mirarlo: no hay marca de «nuevo»", () => {
    const [fila] = armarPendientes({ ...FUENTES_VACIAS, lecturasPendientes: [pendiente] }, { hoy: HOY });
    expect(fila.nuevo).toBe(false);
  });
  it("no se repite con la fila de «una líder registró»: cada una tiene su clave", () => {
    const filas = armarPendientes({
      ...FUENTES_VACIAS, lecturasPendientes: [pendiente],
      conductaRegistrada: [{ id: "doc-7", persona_id: "p-7", persona: "Andrea Torres", sede: "TRU", nivel: "amonestacion",
        creado_at: "2026-09-04T15:00:00Z", creador: "Lucía Ramos", falta: "Trato descortés (53.2 h)" }],
    }, { hoy: HOY });
    expect(new Set(filas.map((f) => f.clave)).size).toBe(2);
  });
});
