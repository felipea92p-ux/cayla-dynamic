// ============================================================================
// seguros.test.ts — lo que la pantalla de Seguros decide (0528)
// ============================================================================
// Cuida lo que, si falla, deja a una persona SIN seguro sin que nadie lo vea:
// que un practicante sin cobertura hoy sea un hueco, que una renovación que
// empalma no se lea como hueco ni como «por vencer», que el último día de una
// póliza (EXCLUSIVO) no cuente como cubierto, que la prima en mora se distinga de
// la suspendida, y que la Bandeja reciba UNA fila de papeleo por póliza y no tres.
// La regla de quién debe tener póliza y de si cubre hoy la dice la base; acá se
// comprueba que la pantalla la lea sin reinterpretarla.
// ============================================================================
import { describe, it, expect } from "vitest";
import {
  coincideSeguro, cubiertoHasta, estadoPrima, pasosPendientes, pendientesDeSeguros,
  polizasConPapeleoPendiente, resumenDeSeguros, seguroPorPersona, sumarMeses,
  DIAS_AVISO_PRIMA, DIAS_AVISO_RENOVACION, DIAS_DE_GRACIA_PRIMA,
  type FilaSeguro,
} from "@/lib/admin/seguros";

const HOY = "2026-10-17";

function fila(o: Partial<FilaSeguro> = {}): FilaSeguro {
  return {
    persona_id: "p1", persona: "Ana Prueba", sede: "TRU", practicante_modalidad: "profesional",
    es_practicante_activo: true, poliza_id: "z1", aseguradora: "Pacífico Seguros", numero_poliza: "24043267",
    vigente_desde: "2026-10-01", vigente_hasta: "2027-01-01", cubre_hoy: true, prima_total: 179.97,
    prima_vence_el: "2026-10-31", plan: null, beneficio_enfermedad: null, beneficio_accidente: null,
    renueva_sola: null, pagada_el: null, firmada_el: null, factura_recibida_el: null, nota: null,
    archivos: 0, creada_at: "2026-10-14T15:00:00Z", ...o,
  };
}

/** La fila que la base devuelve para un practicante sin póliza que cubra hoy. */
function hueco(o: Partial<FilaSeguro> = {}): FilaSeguro {
  return fila({
    poliza_id: null, aseguradora: null, numero_poliza: null, vigente_desde: null, vigente_hasta: null,
    cubre_hoy: false, prima_total: null, prima_vence_el: null, archivos: 0, creada_at: null, ...o,
  });
}

describe("sumar meses: la vigencia por defecto de una póliza nueva", () => {
  it("tres meses desde el 1 de octubre llegan al 1 de enero: los 92 días de la póliza de hoy", () => {
    expect(sumarMeses("2026-10-01", 3)).toBe("2027-01-01");
  });
  it("un año entero", () => { expect(sumarMeses("2027-01-01", 12)).toBe("2028-01-01"); });
  it("el día se recorta al último del mes de llegada, no salta al siguiente", () => {
    expect(sumarMeses("2026-01-31", 1)).toBe("2026-02-28");
    expect(sumarMeses("2028-01-31", 1)).toBe("2028-02-29");
  });
  it("cruza el año", () => { expect(sumarMeses("2026-11-15", 3)).toBe("2027-02-15"); });
});

describe("la prima: vence el día indicado, y el día siguiente ya es mora", () => {
  it("pagada es pagada, aunque la fecha de vencimiento ya pasó", () => {
    expect(estadoPrima({ pagada_el: "2026-10-15", prima_vence_el: "2026-10-01" }, HOY).estado).toBe("pagada");
  });
  it("sin fecha de vencimiento no se puede medir", () => {
    expect(estadoPrima({ pagada_el: null, prima_vence_el: null }, HOY).estado).toBe("sin_fecha");
  });
  it("faltando más de una semana está al día; en la última semana, por vencer", () => {
    expect(estadoPrima({ pagada_el: null, prima_vence_el: "2026-10-31" }, HOY).estado).toBe("al_dia");
    expect(estadoPrima({ pagada_el: null, prima_vence_el: "2026-10-24" }, HOY)).toEqual({ estado: "por_vencer", dias: DIAS_AVISO_PRIMA });
  });
  it("el último día todavía vale: vence hoy es por vencer, no mora", () => {
    expect(estadoPrima({ pagada_el: null, prima_vence_el: HOY }, HOY)).toEqual({ estado: "por_vencer", dias: 0 });
  });
  it("el día siguiente ya es mora, y los días salen negativos como en el resto de la Bandeja", () => {
    expect(estadoPrima({ pagada_el: null, prima_vence_el: "2026-10-16" }, HOY)).toEqual({ estado: "en_mora", dias: -1 });
  });
  it("con 30 días de mora todavía es mora; con 31, la cobertura se suspendió sola", () => {
    expect(estadoPrima({ pagada_el: null, prima_vence_el: "2026-09-17" }, HOY).estado).toBe("en_mora");
    expect(-estadoPrima({ pagada_el: null, prima_vence_el: "2026-09-17" }, HOY).dias!).toBe(DIAS_DE_GRACIA_PRIMA);
    expect(estadoPrima({ pagada_el: null, prima_vence_el: "2026-09-16" }, HOY).estado).toBe("suspendida");
  });
});

describe("el papeleo: qué falta de una póliza, en el orden en que se hace", () => {
  it("una póliza recién emitida las tiene pendientes las tres", () => {
    expect(pasosPendientes(fila())).toEqual(["pagada", "firmada", "factura"]);
  });
  it("cada paso hecho sale de la lista, sin mover los demás", () => {
    expect(pasosPendientes(fila({ pagada_el: "2026-10-15" }))).toEqual(["firmada", "factura"]);
    expect(pasosPendientes(fila({ firmada_el: "2026-10-16" }))).toEqual(["pagada", "factura"]);
    expect(pasosPendientes(fila({ pagada_el: "2026-10-15", firmada_el: "2026-10-16", factura_recibida_el: "2026-10-17" }))).toEqual([]);
  });
});

describe("la cobertura encadena las renovaciones que empalman", () => {
  const primera = { vigente_desde: "2026-10-01", vigente_hasta: "2027-01-01" };
  it("sin otra póliza, llega hasta donde termina la suya", () => {
    expect(cubiertoHasta(primera, [primera])).toBe("2027-01-01");
  });
  it("una renovación que empieza el día en que termina la anterior alarga la cobertura", () => {
    const renov = { vigente_desde: "2027-01-01", vigente_hasta: "2027-04-02" };
    expect(cubiertoHasta(primera, [primera, renov])).toBe("2027-04-02");
  });
  it("encadena varias seguidas", () => {
    const r1 = { vigente_desde: "2027-01-01", vigente_hasta: "2027-04-02" };
    const r2 = { vigente_desde: "2027-04-02", vigente_hasta: "2027-07-02" };
    expect(cubiertoHasta(primera, [r2, primera, r1])).toBe("2027-07-02");
  });
  it("una renovación con un día de hueco NO empalma: ese día no hay seguro", () => {
    const tarde = { vigente_desde: "2027-01-02", vigente_hasta: "2027-04-02" };
    expect(cubiertoHasta(primera, [primera, tarde])).toBe("2027-01-01");
  });
});

describe("quién tiene un hueco, quién está por vencer, quién está al día", () => {
  it("un practicante sin ninguna póliza es un hueco, y dice que nunca tuvo", () => {
    const [p] = seguroPorPersona([hueco()], HOY);
    expect(p.situacion).toBe("hueco");
    expect(p.motivoHueco).toBe("nunca");
    expect(p.actual).toBeNull();
  });

  it("con una póliza que cubre hoy y margen de sobra, está al día", () => {
    const [p] = seguroPorPersona([fila({ vigente_hasta: "2027-06-01" })], HOY);
    expect(p.situacion).toBe("al_dia");
    expect(p.diasParaQuedarSinSeguro).toBeGreaterThan(DIAS_AVISO_RENOVACION);
  });

  it("la póliza de hoy (vence el 01/01/2027) cae «por vencer» recién dentro de la ventana de aviso", () => {
    // Faltan 76 días hoy: todavía al día. A 45 días ya avisa.
    expect(seguroPorPersona([fila()], HOY)[0].situacion).toBe("al_dia");
    const [p] = seguroPorPersona([fila()], "2026-11-17");
    expect(p.situacion).toBe("por_vencer");
    expect(p.diasParaQuedarSinSeguro).toBe(DIAS_AVISO_RENOVACION);
    expect(p.cubiertoHasta).toBe("2027-01-01");
  });

  it("con la renovación ya registrada y empalmando, deja de estar por vencer", () => {
    const renov = fila({ poliza_id: "z2", numero_poliza: "24043267", vigente_desde: "2027-01-01", vigente_hasta: "2027-04-02", cubre_hoy: false });
    const [p] = seguroPorPersona([fila(), renov], "2026-12-20");
    expect(p.situacion).toBe("al_dia");
    expect(p.cubiertoHasta).toBe("2027-04-02");
  });

  it("el último día de la póliza ya NO cubre (la base lo manda con cubre_hoy = false) y es un hueco vencido", () => {
    const vencida = fila({ vigente_hasta: "2027-01-01", cubre_hoy: false });
    const [p] = seguroPorPersona([hueco(), vencida], "2027-01-01");
    expect(p.situacion).toBe("hueco");
    expect(p.motivoHueco).toBe("vencida");
    expect(p.diasDesdeQueVencio).toBe(0);
  });

  it("un hueco con una póliza que todavía no empieza lo dice y da la fecha", () => {
    const futura = fila({ vigente_desde: "2026-11-01", vigente_hasta: "2027-02-01", cubre_hoy: false });
    const [p] = seguroPorPersona([hueco(), futura], HOY);
    expect(p.situacion).toBe("hueco");
    expect(p.motivoHueco).toBe("aun_no_empieza");
    expect(p.empiezaEl).toBe("2026-11-01");
  });

  it("la póliza que habla por la persona es la que cubre hoy, aunque haya otras más recientes o más viejas", () => {
    const vieja = fila({ poliza_id: "z0", vigente_desde: "2026-04-01", vigente_hasta: "2026-07-01", cubre_hoy: false });
    const futura = fila({ poliza_id: "z2", vigente_desde: "2027-01-01", vigente_hasta: "2027-04-01", cubre_hoy: false });
    const [p] = seguroPorPersona([vieja, fila(), futura], "2026-12-20");
    expect(p.actual?.poliza_id).toBe("z1");
    expect(p.polizas.map((z) => z.poliza_id)).toEqual(["z2", "z1", "z0"]);
  });

  it("quien ya no es practicante y conserva una póliza vigente pide la baja", () => {
    const [p] = seguroPorPersona([fila({ es_practicante_activo: false })], HOY);
    expect(p.situacion).toBe("baja_pendiente");
  });

  it("quien ya no es practicante y cuya póliza venció es historia: no sale", () => {
    expect(seguroPorPersona([fila({ es_practicante_activo: false, cubre_hoy: false, vigente_hasta: "2026-10-10" })], HOY)).toEqual([]);
  });

  it("ordena lo más serio primero: hueco, por vencer, baja, al día; dentro, por días y por nombre", () => {
    const filas = [
      fila({ persona_id: "a", persona: "Alba", vigente_hasta: "2027-06-01" }),
      hueco({ persona_id: "b", persona: "Beto" }),
      fila({ persona_id: "c", persona: "Carla", poliza_id: "zc", vigente_hasta: "2026-11-20" }),
      fila({ persona_id: "d", persona: "Dani", poliza_id: "zd", es_practicante_activo: false }),
    ];
    expect(seguroPorPersona(filas, HOY).map((p) => `${p.persona}:${p.situacion}`))
      .toEqual(["Beto:hueco", "Carla:por_vencer", "Dani:baja_pendiente", "Alba:al_dia"]);
  });

  it("las tarjetas cuentan a cada persona UNA vez", () => {
    const personas = seguroPorPersona([
      hueco({ persona_id: "b", persona: "Beto" }),
      fila({ persona_id: "a", persona: "Alba", vigente_hasta: "2027-06-01" }),
    ], HOY);
    expect(resumenDeSeguros(personas)).toEqual({ hueco: 1, por_vencer: 0, al_dia: 1, baja_pendiente: 0 });
  });

  it("el papeleo se cuenta por póliza, no por persona", () => {
    const personas = seguroPorPersona([
      fila({ persona_id: "a", persona: "Alba", vigente_hasta: "2027-06-01", pagada_el: "2026-10-15", firmada_el: "2026-10-15", factura_recibida_el: "2026-10-16" }),
      fila({ persona_id: "b", persona: "Beto", poliza_id: "zb" }),
    ], HOY);
    expect(polizasConPapeleoPendiente(personas)).toBe(1);
  });
});

describe("lo que entra a la Bandeja", () => {
  it("un hueco entra con su motivo y los días desde que venció", () => {
    const vencida = fila({ vigente_hasta: "2026-10-10", cubre_hoy: false, pagada_el: "2026-10-01", firmada_el: "2026-10-01", factura_recibida_el: "2026-10-01" });
    const items = pendientesDeSeguros(seguroPorPersona([hueco(), vencida], HOY), HOY);
    expect(items).toHaveLength(1);
    expect(items[0]).toMatchObject({ tipo: "sin_poliza", clave: "sin_poliza:p1", motivoHueco: "vencida", dias: 7 });
  });

  it("quien está al día y sin papeleo pendiente no entra", () => {
    const todo = { pagada_el: "2026-10-15", firmada_el: "2026-10-15", factura_recibida_el: "2026-10-16", vigente_hasta: "2027-06-01" };
    expect(pendientesDeSeguros(seguroPorPersona([fila(todo)], HOY), HOY)).toEqual([]);
  });

  it("el papeleo es UNA fila por póliza con lo que falta junto, no tres", () => {
    const items = pendientesDeSeguros(seguroPorPersona([fila({ vigente_hasta: "2027-06-01" })], HOY), HOY);
    expect(items).toHaveLength(1);
    expect(items[0]).toMatchObject({ tipo: "papeleo", clave: "papeleo:z1", titulo: "Prima del seguro sin pagar", pasos: ["pagada", "firmada", "factura"] });
    expect(items[0].detalle).toBe("Falta pagar la prima · Falta firmar y devolver la póliza y el convenio de pago · Falta la factura");
    expect(items[0].prima).toEqual({ estado: "al_dia", dias: 14, venceEl: "2026-10-31" });
  });

  it("con la prima pagada, el título pasa a lo que sigue", () => {
    const [i] = pendientesDeSeguros(seguroPorPersona([fila({ vigente_hasta: "2027-06-01", pagada_el: "2026-10-15" })], HOY), HOY);
    expect(i.titulo).toBe("Póliza del seguro sin firmar");
    const [j] = pendientesDeSeguros(seguroPorPersona([fila({ vigente_hasta: "2027-06-01", pagada_el: "2026-10-15", firmada_el: "2026-10-15" })], HOY), HOY);
    expect(j.titulo).toBe("Falta la factura del seguro");
  });

  it("por vencer entra con los días y con la fecha en que se queda sin seguro", () => {
    const todo = { pagada_el: "2026-10-15", firmada_el: "2026-10-15", factura_recibida_el: "2026-10-16" };
    const items = pendientesDeSeguros(seguroPorPersona([fila(todo)], "2026-12-01"), "2026-12-01");
    expect(items).toHaveLength(1);
    expect(items[0]).toMatchObject({ tipo: "por_vencer", dias: 31, hasta: "2027-01-01", detalle: "Falta registrar la renovación" });
  });

  it("si la póliza dice que renueva sola, el aviso pide confirmarlo en vez de pedir registrar", () => {
    const todo = { pagada_el: "2026-10-15", firmada_el: "2026-10-15", factura_recibida_el: "2026-10-16", renueva_sola: true };
    const [i] = pendientesDeSeguros(seguroPorPersona([fila(todo)], "2026-12-01"), "2026-12-01");
    expect(i.detalle).toBe("La póliza dice que renueva sola: confirmar con el corredor");
  });

  it("quien dejó de ser practicante y conserva póliza pide la baja", () => {
    const todo = { pagada_el: "2026-10-15", firmada_el: "2026-10-15", factura_recibida_el: "2026-10-16" };
    const items = pendientesDeSeguros(seguroPorPersona([fila({ ...todo, es_practicante_activo: false })], HOY), HOY);
    expect(items.map((i) => i.tipo)).toEqual(["baja"]);
  });

  it("el papeleo de una póliza vencida de quien ya se fue no vuelve a la Bandeja", () => {
    // Si no sale la persona, no sale su papeleo: es la regla de `seguroPorPersona`.
    const vencida = fila({ es_practicante_activo: false, cubre_hoy: false, vigente_hasta: "2026-10-10" });
    expect(pendientesDeSeguros(seguroPorPersona([vencida], HOY), HOY)).toEqual([]);
  });

  it("las claves no se repiten entre dos personas", () => {
    const items = pendientesDeSeguros(seguroPorPersona([
      hueco({ persona_id: "a", persona: "Alba" }), hueco({ persona_id: "b", persona: "Beto" }),
    ], HOY), HOY);
    expect(new Set(items.map((i) => i.clave)).size).toBe(2);
  });
});

describe("el buscador no esconde a nadie por una tilde", () => {
  const [p] = seguroPorPersona([fila({ persona: "María Prueba", plan: "Plan 1" })], HOY);
  it("encuentra por nombre sin tilde ni mayúsculas", () => { expect(coincideSeguro(p, "maria")).toBe(true); });
  it("por número de póliza", () => { expect(coincideSeguro(p, "24043267")).toBe(true); });
  it("por plan y por sede", () => { expect(coincideSeguro(p, "plan 1")).toBe(true); expect(coincideSeguro(p, "tru")).toBe(true); });
  it("sin texto, deja pasar a todos", () => { expect(coincideSeguro(p, "  ")).toBe(true); });
  it("y no inventa coincidencias", () => { expect(coincideSeguro(p, "lima")).toBe(false); });
});
