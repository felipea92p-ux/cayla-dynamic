// ============================================================================
// disciplina.test.ts — Lo que la pantalla de Disciplina ordena y describe
// ============================================================================
// La regla disciplinaria vive en la base y la prueban las pgTAP. Esto prueba
// la otra mitad, la que decide qué ve quien tramita: en qué paso está un
// borrador, si un entregado ya se puede dar por cerrado, y qué dice hoy la
// asistencia de un día que un documento cita. Esa última es la que importa:
// es la única forma de ver que un borrador quedó desactualizado.
// ============================================================================
import { describe, it, expect } from "vitest";
import {
  etapaDelBorrador, pestanaDelDocumento, pendientesDeEntregado, situacionTardanza, situacionFalta,
  estadoHoyTardanza, estadoHoyFalta, antecedentesVigentes, eventosDeObservacion,
  admiteEntregaAnteriorAlCese, normalizarBusqueda, horaEsperada, SIN_FOTO_DEL_HORARIO, explicarPasoTardanza,
  estadoDeLectura, lecturaPendienteParaAviso, DIAS_SIN_LEER_PARA_AVISO, exigeNotificacionReforzada,
  type DocDisciplina, type Adjunto, type TardanzaRow, type FaltaRow, type DiaAsistencia,
} from "@/lib/admin/disciplina";

function doc(p: Partial<DocDisciplina> = {}): DocDisciplina {
  return {
    id: "d1", persona_id: "p1", tipo_causal: "tardanza", nivel: "amonestacion", estado: "borrador",
    periodo_desde: "2026-09-02", periodo_hasta: "2026-09-11", hechos: [],
    suspension_dias: null, suspension_desde: null, suspension_hasta: null, suspension_fechas: null,
    fecha_cese: null, resuelto_at: null, resuelto_resultado: null, resuelto_motivo: null, resuelto_por: null,
    cargos_comunicados_at: null, descargo_vence_at: null, descargo_acogido: null, descargo_valoracion: null,
    correlativo: null, creado_at: "2026-09-12T15:00:00Z", creado_por: null, firmante_id: null, firmado_at: null,
    entregado_at: null, entregado_por: null, medio_entrega: null, entrega_testigo_nombre: null,
    enviado_a_info_at: null, enviado_a_info_por: null, observacion: null,
    ...p,
  };
}
const adj = (tipo: Adjunto["tipo"]): Adjunto =>
  ({ id: "a", documento_id: "d1", storage_path: "d1/x.pdf", tipo, nota: null, subido_at: "2026-09-13T00:00:00Z" });
const tard = (p: Partial<TardanzaRow>): TardanzaRow =>
  ({ persona_id: "p1", nombre: "X", sede: "TRU", tardanzas_mes: 3, umbral: "amonestacion", sin_medir: 0, minimo: 3, nivel_siguiente: "amonestacion", ...p });
const dia = (p: Partial<DiaAsistencia>): DiaAsistencia =>
  ({ fecha: "2026-09-02", entrada_ts: "2026-09-02T15:14:00Z", minutos_tarde: 14, horario_aplicado: { entrada: "10:00:00", es_descanso: false }, ...p });

describe("un borrador de amonestación pasa por el descargo antes de poder firmarse (RIT 55.2)", () => {
  const ahora = new Date("2026-09-15T17:00:00Z");
  it("sin cargos comunicados, lo que toca es comunicarlos", () => {
    expect(etapaDelBorrador(doc(), true, ahora)).toBe("comunicar");
  });
  it("con el plazo corriendo, se espera — firmar antes invalidaría la sanción", () => {
    expect(etapaDelBorrador(doc({ cargos_comunicados_at: "2026-09-14T15:00:00Z", descargo_vence_at: "2026-09-16T23:00:00Z" }), true, ahora)).toBe("esperando");
  });
  it("vencido el plazo y sin valorar, se valora aunque no haya presentado nada (19.3)", () => {
    expect(etapaDelBorrador(doc({ cargos_comunicados_at: "2026-09-10T15:00:00Z", descargo_vence_at: "2026-09-12T23:00:00Z" }), true, ahora)).toBe("valorar");
  });
  it("valorado, ya se puede firmar", () => {
    expect(etapaDelBorrador(doc({ cargos_comunicados_at: "2026-09-10T15:00:00Z", descargo_vence_at: "2026-09-12T23:00:00Z", descargo_acogido: "sin_descargo" }), true, ahora)).toBe("firmar");
  });
  it("una imputación no pasa por esta cascada: sigue el art. 31 de la LPCL", () => {
    expect(etapaDelBorrador(doc({ nivel: "imputacion" }), true, ahora)).toBe("firmar");
  });
  it("si la empresa no exige el descargo previo (0268), se firma directo", () => {
    expect(etapaDelBorrador(doc(), false, ahora)).toBe("firmar");
  });
});

describe("entregado no es lo mismo que cerrado", () => {
  it("un entregado sin el cargo archivado sigue pendiente, no pasa al historial", () => {
    const d = doc({ estado: "entregado" });
    expect(pendientesDeEntregado(d, [])).toEqual(["cargo"]);
    expect(pestanaDelDocumento(d, [])).toBe("entregar");
  });
  it("el acta de negativa vale como papel de entrega (55.4)", () => {
    expect(pestanaDelDocumento(doc({ estado: "entregado" }), [adj("acta_negativa")])).toBe("historial");
  });
  it("un descargo archivado NO es el papel de la entrega", () => {
    expect(pestanaDelDocumento(doc({ estado: "entregado" }), [adj("descargo")])).toBe("entregar");
  });
  it("una imputación entregada con cargo pero sin resolver sigue pidiendo una decisión", () => {
    expect(pendientesDeEntregado(doc({ estado: "entregado", nivel: "imputacion" }), [adj("cargo_firmado")])).toEqual(["resolver"]);
  });
  // 0486. La entrega por Info se prueba con la confirmación de la persona, que
  // vive en la fila; no hay papel que archivar. Sin esta regla, cada memo
  // entregado por Info se quedaría para siempre en «Entregados que aún piden
  // algo», pidiéndole a quien emitió un cargo que no existe.
  it("un entregado por Info no pide cargo y pasa al historial", () => {
    const d = doc({ estado: "entregado", medio_entrega: "digital", enviado_a_info_at: "2026-09-12T15:00:00Z", enviado_a_info_por: "u1" });
    expect(pendientesDeEntregado(d, [])).toEqual([]);
    expect(pestanaDelDocumento(d, [])).toBe("historial");
  });
  it("y uno entregado en mano sin cargo lo sigue pidiendo: la excepción es solo del medio digital", () => {
    expect(pendientesDeEntregado(doc({ estado: "entregado", medio_entrega: "fisico" }), [])).toEqual(["cargo"]);
    expect(pendientesDeEntregado(doc({ estado: "entregado", medio_entrega: "correo" }), [])).toEqual(["cargo"]);
  });
  it("enviado a Info pero sin recibir sigue siendo un firmado: está por entregar", () => {
    expect(pestanaDelDocumento(doc({ estado: "firmado", enviado_a_info_at: "2026-09-12T15:00:00Z", enviado_a_info_por: "u1" }), [])).toBe("entregar");
  });
  it("anulados y cerrados sin entrega van al historial", () => {
    expect(pestanaDelDocumento(doc({ estado: "anulado" }), [])).toBe("historial");
    expect(pestanaDelDocumento(doc({ estado: "cerrado_sin_entrega" }), [])).toBe("historial");
  });
  it("un firmado siempre está por entregar", () => {
    expect(pestanaDelDocumento(doc({ estado: "firmado" }), [])).toBe("entregar");
  });
});

describe("el semáforo no ofrece un borrador que la base va a rechazar", () => {
  it("en «aviso» —le falta una— se sigue, pero no se genera", () => {
    const s = situacionTardanza(tard({ tardanzas_mes: 2, umbral: "aviso", minimo: 3 }), "setiembre", false);
    expect(s.grupo).toBe("seguimiento");
    expect(s.generable).toBe(false);
    expect(s.etiqueta).toBe("Le falta 1");
  });
  it("con una imputación vigente decide Gerencia, no el sistema", () => {
    expect(situacionTardanza(tard({ umbral: "bloqueado", minimo: null }), "setiembre", false).generable).toBe(false);
  });
  it("con solo días de más de tres horas no hay nada medible que imputar", () => {
    const s = situacionTardanza(tard({ tardanzas_mes: 0, sin_medir: 2, umbral: "aviso" }), "setiembre", false);
    expect(s.generable).toBe(false);
    expect(s.etiqueta).toBe("2 sin medir");
  });
  it("alcanzado el umbral requiere revisión y admite borrador", () => {
    const s = situacionTardanza(tard({}), "setiembre", false);
    expect(s).toMatchObject({ grupo: "alcanzo", generable: true });
  });
  it("si ya hay un borrador de esa causal, no se ofrece otro y deja de pedir revisión: ya se tramita", () => {
    expect(situacionTardanza(tard({}), "setiembre", true)).toMatchObject({ generable: false, grupo: "seguimiento" });
    const f: FaltaRow = { persona_id: "p1", nombre: "X", sede: "LIM", consecutivas: 1, en_30: 1, en_180: 1, nivel: "ambar" };
    expect(situacionFalta(f, true).generable).toBe(false);
    expect(situacionFalta(f, false).generable).toBe(true);
  });
});

describe("la evidencia dice qué es verdad HOY, no solo lo que se guardó al generar", () => {
  it("una tardanza levantada deja de sostener el documento", () => {
    expect(estadoHoyTardanza({ dia: dia({}), minutosCitados: 14, levantada: true, documentadaEn: null, ausencia: null }).cuenta).toBe(false);
  });
  it("una marca corregida a la hora ya no es tardanza — el caso del borrador desactualizado", () => {
    const e = estadoHoyTardanza({ dia: dia({ minutos_tarde: 0 }), minutosCitados: 14, levantada: false, documentadaEn: null, ausencia: null });
    expect(e).toEqual({ cuenta: false, etiqueta: "Hoy no figura tardanza" });
  });
  it("más de tres horas no suma (0189)", () => {
    expect(estadoHoyTardanza({ dia: dia({ minutos_tarde: 221 }), levantada: false, documentadaEn: null, ausencia: null }).cuenta).toBe(false);
  });
  it("lo ya documentado en otro documento no vuelve a contar (non bis in idem)", () => {
    expect(estadoHoyTardanza({ dia: dia({}), levantada: false, documentadaEn: "T-01/0004-2026", ausencia: null }).etiqueta)
      .toBe("Ya documentada en T-01/0004-2026");
  });
  it("si hoy los minutos son otros, se muestra el número de hoy", () => {
    expect(estadoHoyTardanza({ dia: dia({ minutos_tarde: 9 }), minutosCitados: 14, levantada: false, documentadaEn: null, ausencia: null }).etiqueta)
      .toBe("Cuenta · hoy 9′");
  });
  it("una ausencia ese día se avisa, pero no se descuenta: la base no la descuenta", () => {
    const e = estadoHoyTardanza({ dia: dia({}), levantada: false, documentadaEn: null, ausencia: "Vacaciones" });
    expect(e.cuenta).toBe(true);
  });
  it("una falta que después se cubrió con un descanso médico ya no cuenta", () => {
    expect(estadoHoyFalta({ dia: undefined, ausencia: "Descanso médico" })).toEqual({ cuenta: false, etiqueta: "Justificada · descanso médico" });
  });
  it("una falta con marca de entrada corregida ya no es falta", () => {
    expect(estadoHoyFalta({ dia: dia({}), ausencia: null }).cuenta).toBe(false);
  });
  it("sin jornada ni ausencia, la falta se sostiene", () => {
    expect(estadoHoyFalta({ dia: undefined, ausencia: null }).cuenta).toBe(true);
  });
  it("la hora esperada sale de la foto del horario (0446), recortada a HH:MM", () => {
    expect(horaEsperada(dia({}))).toBe("10:00");
    expect(horaEsperada(dia({ horario_aplicado: null, minutos_tarde: 0 }))).toBe("Sin dato del horario");
  });
  it("una tardanza medida sin foto del horario no se muestra como «—»: se midió contra algo (0445)", () => {
    expect(horaEsperada(dia({ horario_aplicado: null, minutos_tarde: 2 }))).toBe(SIN_FOTO_DEL_HORARIO);
    expect(horaEsperada(undefined)).toBe("—");
  });
  it("un día de descanso o sin hora de entrada lo dice", () => {
    expect(horaEsperada(dia({ horario_aplicado: { entrada: null, es_descanso: true } }))).toBe("Descanso");
    expect(horaEsperada(dia({ horario_aplicado: { entrada: null, es_descanso: false } }))).toBe("Sin horario");
  });
});

describe("antecedentes: solo lo entregado en los doce meses previos (56.1, 56.2)", () => {
  const ref = "2026-09-15T12:00:00Z";
  const docs = [
    doc({ id: "a", estado: "entregado", entregado_at: "2026-06-20T12:00:00Z" }),
    doc({ id: "b", estado: "firmado", firmado_at: "2026-08-01T12:00:00Z" }),
    doc({ id: "c", estado: "entregado", entregado_at: "2025-08-01T12:00:00Z" }),
    doc({ id: "d", estado: "entregado", entregado_at: "2026-07-01T12:00:00Z", tipo_causal: "falta" }),
  ];
  it("un firmado sin entregar no agrava; uno de hace más de un año tampoco; otra causal no cuenta", () => {
    expect(antecedentesVigentes(docs, "p1", "tardanza", ref).map((x) => x.id)).toEqual(["a"]);
  });
});

describe("el rastro que hoy vive como texto en observacion", () => {
  it("separa anulación, reapertura y cierre de las notas sueltas", () => {
    const ev = eventosDeObservacion(
      "Comunicación declarada por DO. [REABIERTO 2026-08-20: vuelto a borrador para cambiar el firmante (firmaba Ana)] [CERRADO SIN ENTREGA 2026-09-03: la persona cesó el 02/09/2026. no se ubicó]",
    );
    expect(ev.map((e) => e.tipo)).toEqual(["nota", "reabierto", "cerrado_sin_entrega"]);
    expect(ev[2]).toMatchObject({ fecha: "2026-09-03", texto: "la persona cesó el 02/09/2026. no se ubicó" });
  });
  it("sin observación no inventa eventos", () => {
    expect(eventosDeObservacion(null)).toEqual([]);
  });
});

describe("persona cesada: la entrega solo tiene sentido si pudo ocurrir antes del cese", () => {
  const firmado = doc({ estado: "firmado", firmado_at: "2026-08-26T19:36:00Z" });
  it("firmado antes del cese admite registrar una entrega anterior", () => {
    expect(admiteEntregaAnteriorAlCese(firmado, "2026-09-02")).toBe(true);
  });
  it("firmado después del cese ya no pudo entregarse", () => {
    expect(admiteEntregaAnteriorAlCese(firmado, "2026-08-20")).toBe(false);
  });
  it("sin fecha de cese no se ofrece", () => {
    expect(admiteEntregaAnteriorAlCese(firmado, null)).toBe(false);
  });
});

it("la búsqueda ignora tildes y mayúsculas", () => {
  expect(normalizarBusqueda("  Ramírez ")).toBe("ramirez");
});

describe("el paso de la escala se dice completo: los cuatro peldaños del numeral 19.2", () => {
  const paso = (minimo: number | null, nivel_siguiente: string) => explicarPasoTardanza({ minimo, nivel_siguiente });
  it("sin antecedente toca la amonestación, con 3", () => {
    expect(paso(3, "amonestacion")).toMatch(/amonestación escrita: 3 tardanzas/);
  });
  it("con una amonestación toca la primera suspensión, con 2", () => {
    expect(paso(2, "suspension")).toMatch(/primera suspensión: 2 tardanzas/);
  });
  it("con una suspensión toca la SEGUNDA, y lo dice — el mismo minimo=1 que la imputación", () => {
    expect(paso(1, "suspension")).toMatch(/segunda suspensión, de mayor duración/);
  });
  it("con dos suspensiones toca la imputación de cargos (19.2 e)", () => {
    expect(paso(1, "imputacion")).toMatch(/imputación de cargos/);
  });
  it("con una imputación vigente no propone nada: decide Gerencia", () => {
    expect(paso(null, "imputacion")).toMatch(/Gerencia/);
  });
});


describe("la constancia de lectura que ve DO (0516)", () => {
  const ahora = new Date("2026-10-16T15:00:00Z");
  const papel = (p: Partial<DocDisciplina> = {}) => doc({ estado: "entregado", medio_entrega: "fisico", entregado_at: "2026-10-04T15:00:00Z", ...p });

  it("lo recibido por Info no la pide: recibir ya es la constancia", () => {
    expect(estadoDeLectura(papel({ medio_entrega: "digital" }), undefined, ahora).tipo).toBe("no_aplica");
  });
  it("una imputación o un despido se entregan en físico o por notario: no aplica", () => {
    expect(estadoDeLectura(papel({ nivel: "imputacion" }), undefined, ahora).tipo).toBe("no_aplica");
  });
  it("lo que no se entregó no aplica", () => {
    expect(estadoDeLectura(papel({ estado: "firmado" }), undefined, ahora).tipo).toBe("no_aplica");
  });
  it("sin abrir: dice cuántos días lleva", () => {
    expect(estadoDeLectura(papel(), undefined, ahora)).toEqual({ tipo: "sin_abrir", dias: 12 });
  });
  it("abierto pero sin «Lo leí»", () => {
    const l = { expediente_id: "d1", abierto_at: "2026-10-05T10:00:00Z", leido_at: null };
    expect(estadoDeLectura(papel(), l, ahora)).toEqual({ tipo: "abierto", abierto_at: l.abierto_at });
  });
  it("leído, con las dos horas", () => {
    const l = { expediente_id: "d1", abierto_at: "2026-10-05T10:00:00Z", leido_at: "2026-10-05T10:02:00Z" };
    expect(estadoDeLectura(papel(), l, ahora)).toEqual({ tipo: "leido", abierto_at: l.abierto_at, leido_at: l.leido_at });
  });
  it("firmar su copia cuenta como haberlo leído: es un acto deliberado con su propia fecha", () => {
    expect(estadoDeLectura(papel({ firma_sancionado_confirmada_at: "2026-10-06T10:00:00Z" }), undefined, ahora).tipo).toBe("firmo");
  });
  it("el aviso a DO salta a los 7 días y no antes", () => {
    expect(DIAS_SIN_LEER_PARA_AVISO).toBe(7);
    expect(lecturaPendienteParaAviso(papel({ entregado_at: "2026-10-09T15:00:00Z" }), undefined, ahora)).toBe(true);
    expect(lecturaPendienteParaAviso(papel({ entregado_at: "2026-10-10T15:00:00Z" }), undefined, ahora)).toBe(false);
  });
  it("abierto y sin «Lo leí» también avisa: abrirlo no es dejar constancia", () => {
    const l = { expediente_id: "d1", abierto_at: "2026-10-05T10:00:00Z", leido_at: null };
    expect(lecturaPendienteParaAviso(papel(), l, ahora)).toBe(true);
  });
  it("no avisa de lo ya leído, de lo ya firmado ni de lo que no aplica", () => {
    const leido = { expediente_id: "d1", abierto_at: "2026-10-05T10:00:00Z", leido_at: "2026-10-05T10:02:00Z" };
    expect(lecturaPendienteParaAviso(papel(), leido, ahora)).toBe(false);
    expect(lecturaPendienteParaAviso(papel({ firma_sancionado_confirmada_at: "2026-10-06T10:00:00Z" }), undefined, ahora)).toBe(false);
    expect(lecturaPendienteParaAviso(papel({ medio_entrega: "digital" }), undefined, ahora)).toBe(false);
  });
});

describe("notificación reforzada del art. 57.8", () => {
  // La pantalla usa esto para no repetirle a quien entrega que el acta
  // «produce los mismos efectos que el cargo firmado»: en estos dos niveles no
  // los produce, y durante meses el formulario lo afirmó.
  it("alcanza a la carta de imputación y a la de despido", () => {
    expect(exigeNotificacionReforzada("imputacion")).toBe(true);
    expect(exigeNotificacionReforzada("despido")).toBe(true);
  });

  it("y no a las tres sanciones de la escala del art. 54.1", () => {
    // Acá sí vale el numeral 55.4: el acta equivale al cargo firmado. Un aviso
    // que también saliera en una amonestación sería falso, y los falsos
    // positivos son el peor error de este sistema.
    expect(exigeNotificacionReforzada("verbal")).toBe(false);
    expect(exigeNotificacionReforzada("amonestacion")).toBe(false);
    expect(exigeNotificacionReforzada("suspension")).toBe(false);
  });

  it("no se cae con un nivel que no conoce", () => {
    // La pantalla le pasa `doc?.nivel ?? ""` cuando todavía no cargó el
    // documento. Un `undefined` ahí no debe encender un aviso de despido.
    expect(exigeNotificacionReforzada("")).toBe(false);
    expect(exigeNotificacionReforzada("cualquier_cosa")).toBe(false);
  });
});
