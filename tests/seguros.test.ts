// ============================================================================
// seguros.test.ts — lo que la pantalla de Seguros decide (0528)
// ============================================================================
// Cuida lo que, si falla, deja a una persona SIN seguro sin que nadie lo vea:
// que quien tiene un seguro con póliza y no la tiene hoy sea un hueco, que una
// renovación que empalma no se lea como hueco ni como «por vencer», que el último
// día de una póliza (EXCLUSIVO) no cuente como cubierto, que EsSalud —que no lleva
// póliza— nunca sea un hueco, que un seguro complementario no tape el hueco del
// principal, que la prima en mora se distinga de la suspendida, que el cambio de
// seguro de una persona quede pendiente hasta que alguien lo cierre, y que la
// Bandeja reciba UNA fila por hecho y no varias.
// La regla de quién debe tener póliza y de si cubre hoy la dice la base; acá se
// comprueba que la pantalla la lea sin reinterpretarla.
// ============================================================================
import { describe, it, expect } from "vitest";
import {
  coincideSeguro, contarPorTipo, cubiertoHasta, estadoPrima, etiquetaTipoArchivo, etiquetaVinculo,
  fechaDelPaso, fechasSospechosas, hermanasDe, numeroDeTexto, origenDelCambio, pasosDelCambio, pasosPendientes, pendientesDeSeguros, personasParaPoliza, polizaQueSeCruza,
  resumenDelCambio, resumenDeSeguros, seguroPorPersona, sumarMeses,
  DIAS_AVISO_PRIMA, DIAS_AVISO_RENOVACION, DIAS_DE_GRACIA_PRIMA,
  type CambioSeguro, type FilaEquipoSeguro, type Poliza,
} from "@/lib/admin/seguros";

const HOY = "2026-10-17";

/** Una persona tal como la devuelve `fn_seguros_equipo`: por defecto, una practicante en FOLA que hoy cubre. */
function persona(o: Partial<FilaEquipoSeguro> = {}): FilaEquipoSeguro {
  return {
    persona_id: "p1", persona: "Ana Prueba", sede: "TRU", tipo_vinculo: "practicante", practicante_modalidad: "profesional", en_planilla: false,
    activa: true, tipo: "salud_practicantes", tipo_nombre: "FOLA", origen: "vinculo",
    asignacion_id: null, asignacion_desde: null, asignacion_motivo: null,
    tipo_automatico: "salud_practicantes", tipo_automatico_nombre: "FOLA",
    con_poliza: true, cubre_hoy: true, hueco: false, ...o,
  };
}

/** A quien no le toca ningún seguro de la empresa (honorarios): ni principal, ni automático. */
const SIN_SEGURO = {
  tipo: null, tipo_nombre: null, origen: null, tipo_automatico: null, tipo_automatico_nombre: null,
  con_poliza: false, cubre_hoy: null, hueco: false,
} as const;

/** Quien lleva póliza y hoy no tiene ninguna que cubra. */
const sinCobertura = (o: Partial<FilaEquipoSeguro> = {}) => persona({ cubre_hoy: false, hueco: true, ...o });

/** Una integrante de planilla: su seguro es EsSalud, que se paga con la planilla y no lleva póliza. */
const deLaPlanilla = (o: Partial<FilaEquipoSeguro> = {}) => persona({
  persona_id: "p2", persona: "Beto Planilla", tipo_vinculo: "planilla", practicante_modalidad: null, en_planilla: true,
  tipo: "essalud", tipo_nombre: "EsSalud", tipo_automatico: "essalud", tipo_automatico_nombre: "EsSalud",
  con_poliza: false, cubre_hoy: null, hueco: false, ...o,
});

/** Una póliza tal como la devuelve `fn_seguros_tablero`: por defecto la de hoy, con los tres pasos pendientes. */
function poliza(o: Partial<Poliza> = {}): Poliza {
  return {
    persona_id: "p1", persona: "Ana Prueba", sede: "TRU", persona_activa: true,
    producto: "salud_practicantes", producto_nombre: "FOLA", producto_principal: true,
    poliza_id: "z1", aseguradora: "Pacífico Seguros", numero_poliza: "24043267",
    vigente_desde: "2026-10-01", vigente_hasta: "2027-01-01", cubre_hoy: true, prima_total: 179.97,
    prima_vence_el: "2026-10-31", plan: null, beneficio_enfermedad: null, beneficio_accidente: null,
    renueva_sola: null, pagada_el: null, firmada_el: null, factura_recibida_el: null, nota: null,
    archivos: 0, creada_at: "2026-10-14T15:00:00Z", ...o,
  };
}

/** Los tres pasos hechos: la póliza ya no pide nada. */
const completa = { pagada_el: "2026-10-15", firmada_el: "2026-10-15", factura_recibida_el: "2026-10-16" };

/** Un cambio tal como lo devuelve `fn_seguros_cambios`: por defecto de EsSalud a FOLA por cambio de vínculo, con baja y alta pendientes. */
function cambio(o: Partial<CambioSeguro> = {}): CambioSeguro {
  return {
    id: "c1", persona_id: "p1", persona: "Ana Prueba", sede: "TRU", persona_activa: true,
    de_tipo: "essalud", de_nombre: "EsSalud", a_tipo: "salud_practicantes", a_nombre: "FOLA",
    fecha: "2026-10-15", origen: "vinculo", vinculo_antes: "planilla", vinculo_despues: "practicante", detalle: null,
    baja_pendiente: true, baja_texto: "Confirmar con el contador la baja en EsSalud", baja_hecha_el: null, baja_nota: null,
    alta_pendiente: true, alta_texto: "Registrar su póliza FOLA y avisarle al corredor", alta_hecha_el: null, alta_nota: null,
    creado_at: "2026-10-15T14:00:00Z", ...o,
  };
}

const una = (filas: FilaEquipoSeguro[], polizas: Poliza[] = [], cambios: CambioSeguro[] = [], hoy = HOY) =>
  seguroPorPersona(filas, polizas, cambios, hoy);

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
    expect(pasosPendientes(poliza())).toEqual(["pagada", "firmada", "factura"]);
  });
  it("cada paso hecho sale de la lista, sin mover los demás", () => {
    expect(pasosPendientes(poliza({ pagada_el: "2026-10-15" }))).toEqual(["firmada", "factura"]);
    expect(pasosPendientes(poliza({ firmada_el: "2026-10-16" }))).toEqual(["pagada", "factura"]);
    expect(pasosPendientes(poliza(completa))).toEqual([]);
  });
  it("la fecha de cada paso es la suya, no la de otro", () => {
    const z = poliza(completa);
    expect(fechaDelPaso(z, "pagada")).toBe("2026-10-15");
    expect(fechaDelPaso(z, "factura")).toBe("2026-10-16");
    expect(fechaDelPaso(poliza(), "firmada")).toBeNull();
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

describe("en qué seguro está cada colaborador, y a quién le falta póliza", () => {
  it("quien lleva póliza y no tiene ninguna es un hueco, y dice que nunca tuvo", () => {
    const [p] = una([sinCobertura()]);
    expect(p.situacion).toBe("hueco");
    expect(p.motivoHueco).toBe("nunca");
    expect(p.actual).toBeNull();
    expect(p.tipo).toEqual({ clave: "salud_practicantes", nombre: "FOLA" });
  });

  it("con una póliza que cubre hoy y margen de sobra, está al día", () => {
    const [p] = una([persona()], [poliza({ vigente_hasta: "2027-06-01" })]);
    expect(p.situacion).toBe("al_dia");
    expect(p.diasParaQuedarSinSeguro).toBeGreaterThan(DIAS_AVISO_RENOVACION);
  });

  it("la póliza de hoy (vence el 01/01/2027) cae «por vencer» recién dentro de la ventana de aviso", () => {
    // Faltan 76 días hoy: todavía al día. A 45 días ya avisa.
    expect(una([persona()], [poliza()])[0].situacion).toBe("al_dia");
    const [p] = una([persona()], [poliza()], [], "2026-11-17");
    expect(p.situacion).toBe("por_vencer");
    expect(p.diasParaQuedarSinSeguro).toBe(DIAS_AVISO_RENOVACION);
    expect(p.cubiertoHasta).toBe("2027-01-01");
  });

  it("con la renovación ya registrada y empalmando, deja de estar por vencer", () => {
    // Con la prima pagada: lo que se prueba es la renovación, no la mora (a esa fecha, sin pagar, la cobertura estaría suspendida).
    const renov = poliza({ poliza_id: "z2", vigente_desde: "2027-01-01", vigente_hasta: "2027-04-02", cubre_hoy: false });
    const [p] = una([persona()], [poliza(completa), renov], [], "2026-12-20");
    expect(p.situacion).toBe("al_dia");
    expect(p.cubiertoHasta).toBe("2027-04-02");
  });

  it("el último día de la póliza ya NO cubre (la base lo manda con cubre_hoy = false) y es un hueco vencido", () => {
    const vencida = poliza({ vigente_hasta: "2027-01-01", cubre_hoy: false });
    const [p] = una([sinCobertura()], [vencida], [], "2027-01-01");
    expect(p.situacion).toBe("hueco");
    expect(p.motivoHueco).toBe("vencida");
    expect(p.diasDesdeQueVencio).toBe(0);
  });

  it("un hueco con una póliza que todavía no empieza lo dice y da la fecha", () => {
    const futura = poliza({ vigente_desde: "2026-11-01", vigente_hasta: "2027-02-01", cubre_hoy: false });
    const [p] = una([sinCobertura()], [futura]);
    expect(p.situacion).toBe("hueco");
    expect(p.motivoHueco).toBe("aun_no_empieza");
    expect(p.empiezaEl).toBe("2026-11-01");
  });

  it("la póliza que habla por la persona es la que cubre hoy, aunque haya otras más recientes o más viejas", () => {
    const vieja = poliza({ poliza_id: "z0", vigente_desde: "2026-04-01", vigente_hasta: "2026-07-01", cubre_hoy: false });
    const futura = poliza({ poliza_id: "z2", vigente_desde: "2027-01-01", vigente_hasta: "2027-04-01", cubre_hoy: false });
    const [p] = una([persona()], [vieja, poliza(), futura], [], "2026-12-20");
    expect(p.actual?.poliza_id).toBe("z1");
    expect(p.polizasPrincipales.map((z) => z.poliza_id)).toEqual(["z2", "z1", "z0"]);
  });

  it("EsSalud no lleva póliza: queda «por planilla» y NUNCA es un hueco, aunque no haya ninguna", () => {
    const [p] = una([deLaPlanilla()]);
    expect(p.situacion).toBe("por_planilla");
    expect(p.conPoliza).toBe(false);
    expect(p.motivoHueco).toBeNull();
    expect(p.diasParaQuedarSinSeguro).toBeNull();
  });

  it("quien no tiene un seguro que le toque (honorarios, sin vínculo laboral) queda «sin seguro»", () => {
    const [p] = una([persona({
      persona_id: "p3", tipo_vinculo: "rxh", practicante_modalidad: null, en_planilla: false, ...SIN_SEGURO,
    })]);
    expect(p.situacion).toBe("sin_seguro");
    expect(p.tipo).toBeNull();
  });

  it("un seguro complementario NO tapa el hueco del principal: va aparte, en «otras»", () => {
    const vida = poliza({ poliza_id: "zv", producto: "vida_ley", producto_nombre: "Vida Ley", producto_principal: false });
    const [p] = una([sinCobertura()], [vida]);
    expect(p.situacion).toBe("hueco");
    expect(p.polizasPrincipales).toEqual([]);
    expect(p.otras.map((z) => z.poliza_id)).toEqual(["zv"]);
    expect(p.actual).toBeNull();
  });

  it("la póliza del seguro anterior queda en «otras» cuando la persona ya cambió de seguro", () => {
    // Pasó de FOLA a EsSalud: la póliza FOLA sigue vigente hasta que la aseguradora dé la baja.
    const [p] = una([deLaPlanilla({ persona_id: "p1", persona: "Ana Prueba" })], [poliza()]);
    expect(p.situacion).toBe("por_planilla");
    expect(p.polizasPrincipales).toEqual([]);
    expect(p.otras.map((z) => z.poliza_id)).toEqual(["z1"]);
  });

  it("quien ya no está activa y conserva una póliza vigente pide la baja", () => {
    const [p] = una([persona({ activa: false })], [poliza(completa)]);
    expect(p.situacion).toBe("baja_pendiente");
  });

  it("quien ya se fue y solo conserva pólizas que terminaron es historia: no sale, aunque la base la traiga", () => {
    // `equipo` y `polizas` son dos consultas: a medianoche una póliza puede vencer entre la una y la otra.
    const vencida = poliza({ cubre_hoy: false, vigente_hasta: "2026-10-10" });
    expect(una([persona({ activa: false })], [vencida])).toEqual([]);
    expect(una([persona({ activa: false })], [])).toEqual([]);
  });

  it("el último día de una póliza (EXCLUSIVO) ya no la mantiene viva: quien se fue deja de pedir la baja", () => {
    const termina = poliza({ cubre_hoy: false, vigente_hasta: HOY });
    expect(una([persona({ activa: false })], [termina])).toEqual([]);
  });

  it("el papeleo de quien está activa cuenta aunque la póliza ya haya vencido: la factura se sigue debiendo", () => {
    const vencida = poliza({ cubre_hoy: false, vigente_hasta: "2026-10-10" });
    expect(una([sinCobertura()], [vencida])[0].conPapeleo.map((z) => z.poliza_id)).toEqual(["z1"]);
  });

  it("junta los cambios de seguro de la persona, el más reciente primero, y separa los que piden algo", () => {
    const viejo = cambio({ id: "c0", fecha: "2026-06-01", baja_pendiente: false, alta_pendiente: false, creado_at: "2026-06-01T10:00:00Z" });
    const nuevo = cambio({ id: "c1" });
    const [p] = una([persona()], [poliza(completa)], [viejo, nuevo]);
    expect(p.cambios.map((c) => c.id)).toEqual(["c1", "c0"]);
    expect(p.cambiosPendientes.map((c) => c.id)).toEqual(["c1"]);
  });

  it("los cambios de una persona no se le pegan a otra", () => {
    const personas = una([persona(), deLaPlanilla()], [], [cambio({ persona_id: "p2" })]);
    expect(personas.find((p) => p.personaId === "p1")!.cambios).toEqual([]);
    expect(personas.find((p) => p.personaId === "p2")!.cambios).toHaveLength(1);
  });

  it("una asignación de DO se lee tal cual la manda la base", () => {
    const [p] = una([persona({
      origen: "asignacion", asignacion_id: "a1", asignacion_desde: "2026-10-10", asignacion_motivo: "Cotizó con otro corredor",
      tipo_automatico: "essalud", tipo_automatico_nombre: "EsSalud",
    })], [poliza(completa)]);
    expect(p.origen).toBe("asignacion");
    expect(p.asignacion).toEqual({ id: "a1", desde: "2026-10-10", motivo: "Cotizó con otro corredor" });
  });

  it("y dice también cuál le toca por su vínculo, que es adonde vuelve con «volver al automático»", () => {
    const [p] = una([persona({
      origen: "asignacion", asignacion_id: "a1", asignacion_desde: "2026-10-10", asignacion_motivo: "Cotizó con otro corredor",
      tipo_automatico: "essalud", tipo_automatico_nombre: "EsSalud",
    })], [poliza(completa)]);
    expect(p.tipo?.nombre).toBe("FOLA");
    expect(p.automatico).toEqual({ clave: "essalud", nombre: "EsSalud" });
    expect(una([persona()])[0].automatico).toEqual({ clave: "salud_practicantes", nombre: "FOLA" });
    expect(una([persona({ ...SIN_SEGURO })])[0].automatico).toBeNull();
  });

  describe("el orden de la lista", () => {
    const todas = () => una(
      [
        persona({ persona_id: "a", persona: "Alba" }),
        sinCobertura({ persona_id: "b", persona: "Beto" }),
        persona({ persona_id: "c", persona: "Carla" }),
        persona({ persona_id: "d", persona: "Dani", activa: false }),
        deLaPlanilla({ persona_id: "e", persona: "Eva" }),
        persona({ persona_id: "f", persona: "Fito", ...SIN_SEGURO }),
        persona({ persona_id: "g", persona: "Gina" }),
        persona({ persona_id: "h", persona: "Hugo" }),
      ],
      [
        poliza({ ...completa, persona_id: "a", poliza_id: "za", vigente_hasta: "2027-06-01" }),
        poliza({ ...completa, persona_id: "c", poliza_id: "zc", vigente_hasta: "2026-11-20" }),
        poliza({ ...completa, persona_id: "d", poliza_id: "zd", persona_activa: false }),
        poliza({ ...completa, persona_id: "g", poliza_id: "zg", vigente_hasta: "2027-06-01" }),
        poliza({ persona_id: "h", poliza_id: "zh", vigente_hasta: "2027-06-01" }),
      ],
      [cambio({ id: "cg", persona_id: "g" })],
    );

    it("primero lo que pide algo, lo más serio antes; después lo que está en orden", () => {
      expect(todas().map((p) => `${p.persona}:${p.situacion}`)).toEqual([
        "Beto:hueco", "Carla:por_vencer", "Gina:al_dia", "Dani:baja_pendiente", "Hugo:al_dia",
        "Alba:al_dia", "Eva:por_planilla", "Fito:sin_seguro",
      ]);
    });

    it("las tarjetas cuentan a cada persona UNA vez, y los cambios y el papeleo por separado", () => {
      expect(resumenDeSeguros(todas())).toEqual({
        hueco: 1, suspendida: 0, por_vencer: 1, baja_pendiente: 1, al_dia: 3, por_planilla: 1, sin_seguro: 1, cambios: 1, papeleo: 1,
      });
    });
  });

  describe("la cobertura suspendida por mora", () => {
    // Una póliza vigente por FECHAS cuya prima lleva más de 30 días sin pagarse ya no cubre: el
    // convenio de pago suspende la cobertura sola. La base no lo sabe (`cubre_hoy` es de fechas).
    const enMora = (venceEl: string, extra: Partial<Poliza> = {}) => poliza({ prima_vence_el: venceEl, vigente_hasta: "2027-06-01", ...extra });

    it("con la prima sin pagar y más de 30 días vencida, NO figura «al día»: queda suspendida", () => {
      const [p] = una([persona()], [enMora("2026-09-01")]);
      expect(p.situacion).toBe("suspendida");
      expect(p.motivoHueco).toBeNull();
    });
    it("con exactamente 30 días de mora todavía cubre (la suspensión empieza al día 31)", () => {
      expect(una([persona()], [enMora("2026-09-17")])[0].situacion).toBe("al_dia");
      expect(una([persona()], [enMora("2026-09-16")])[0].situacion).toBe("suspendida");
    });
    it("con la prima pagada nunca se suspende, por vieja que sea la fecha", () => {
      expect(una([persona()], [enMora("2026-01-01", { pagada_el: "2026-10-15" })])[0].situacion).toBe("al_dia");
    });
    it("va justo después de quien no tiene póliza y antes de lo que se vence pronto", () => {
      const filas = [
        persona({ persona_id: "a", persona: "Alba" }),
        persona({ persona_id: "b", persona: "Beto" }),
        sinCobertura({ persona_id: "c", persona: "Carla" }),
      ];
      const polizas = [
        enMora("2026-09-01", { persona_id: "a", poliza_id: "za", vigente_hasta: "2026-11-20" }),
        enMora("2026-09-01", { persona_id: "b", poliza_id: "zb" }),
        poliza({ ...completa, persona_id: "d", poliza_id: "zd" }),
      ];
      expect(una(filas, polizas).map((p) => `${p.persona}:${p.situacion}`)).toEqual(["Carla:hueco", "Alba:suspendida", "Beto:suspendida"]);
    });
    it("la tarjeta de arriba la cuenta aparte, y a la Bandeja le basta la fila del papeleo (la prima sin pagar)", () => {
      const personas = una([persona()], [enMora("2026-09-01")]);
      expect(resumenDeSeguros(personas)).toMatchObject({ suspendida: 1, al_dia: 0, hueco: 0 });
      const items = pendientesDeSeguros(personas, HOY);
      expect(items.map((i) => i.tipo)).toEqual(["papeleo"]);
      expect(items[0].prima?.estado).toBe("suspendida");
    });
  });

  describe("entre varios huecos, el más grave primero (el mismo orden de la Bandeja)", () => {
    it("quien nunca tuvo póliza, después quien lleva más días sin ella, y al final a quien ya le espera una", () => {
      const filas = [
        sinCobertura({ persona_id: "a", persona: "Alba" }),
        sinCobertura({ persona_id: "m", persona: "Mara" }),
        sinCobertura({ persona_id: "p", persona: "Pía" }),
        sinCobertura({ persona_id: "z", persona: "Zoe" }),
      ];
      const polizas = [
        poliza({ ...completa, persona_id: "a", poliza_id: "za", vigente_hasta: "2026-10-16", cubre_hoy: false }),
        poliza({ ...completa, persona_id: "m", poliza_id: "zm", vigente_hasta: "2026-10-07", cubre_hoy: false }),
        poliza({ ...completa, persona_id: "p", poliza_id: "zp", vigente_desde: "2026-11-01", vigente_hasta: "2027-02-01", cubre_hoy: false }),
      ];
      expect(una(filas, polizas).map((p) => p.persona)).toEqual(["Zoe", "Mara", "Alba", "Pía"]);
    });
  });

  it("una persona con varias pólizas o varios cambios pendientes cuenta UNA vez: el número del botón es el de filas que deja ver", () => {
    const dos = una(
      [persona()],
      [poliza({ poliza_id: "z1" }), poliza({ poliza_id: "z2", producto: "vida_ley", producto_nombre: "Vida Ley", producto_principal: false })],
      [cambio({ id: "c1" }), cambio({ id: "c2", fecha: "2026-10-16", creado_at: "2026-10-16T09:00:00Z" })],
    );
    expect(dos[0].conPapeleo).toHaveLength(2);
    expect(dos[0].cambiosPendientes).toHaveLength(2);
    expect(resumenDeSeguros(dos)).toMatchObject({ papeleo: 1, cambios: 1 });
  });
});

describe("cuánta gente hay en cada seguro", () => {
  const tipos = [
    { clave: "salud_practicantes", nombre: "FOLA", principal: true, activo: true },
    { clave: "essalud", nombre: "EsSalud", principal: true, activo: true },
    { clave: "vida_ley", nombre: "Vida Ley", principal: false, activo: true },
    { clave: "viejo", nombre: "Un seguro retirado", principal: true, activo: false },
  ];
  const gente = () => una([
    persona({ persona_id: "a" }),
    deLaPlanilla({ persona_id: "b", persona: "Beto" }),
    deLaPlanilla({ persona_id: "c", persona: "Cora" }),
    persona({ persona_id: "d", persona: "Dani", ...SIN_SEGURO }),
    persona({ persona_id: "e", persona: "Eva", activa: false }),
  ]);

  it("sigue el orden del catálogo, deja fuera lo que no es principal y lo archivado sin gente, y cierra con «sin seguro»", () => {
    expect(contarPorTipo(gente(), tipos)).toEqual([
      { clave: "salud_practicantes", nombre: "FOLA", n: 1 },
      { clave: "essalud", nombre: "EsSalud", n: 2 },
      { clave: null, nombre: "Sin seguro (no aplica)", n: 1 },
    ]);
  });

  it("cuenta TODAS las filas de la lista, también a quien ya no está activa pero conserva una póliza: el número y las filas coinciden", () => {
    // Eva ya no está activa y su póliza FOLA sigue vigente: sale en la lista (pide la baja) y en el filtro.
    const personas = una(
      [persona({ persona_id: "a" }), persona({ persona_id: "e", persona: "Eva", activa: false })],
      [poliza({ ...completa, persona_id: "e", poliza_id: "ze", persona_activa: false })],
    );
    expect(personas).toHaveLength(2);
    expect(contarPorTipo(personas, tipos).find((t) => t.clave === "salud_practicantes")!.n).toBe(2);
  });

  it("un tipo archivado que todavía tiene gente sigue saliendo: nadie queda sin filtro", () => {
    const personas = una([persona({ tipo: "viejo", tipo_nombre: "Un seguro retirado" })]);
    expect(contarPorTipo(personas, tipos).find((t) => t.clave === "viejo")).toEqual({ clave: "viejo", nombre: "Un seguro retirado", n: 1 });
  });

  it("un tipo que ya no está en el catálogo, pero tiene gente, sale con el nombre que trajo la persona", () => {
    const personas = una([persona({ tipo: "raro", tipo_nombre: "Seguro raro" })]);
    expect(contarPorTipo(personas, tipos).find((t) => t.clave === "raro")).toEqual({ clave: "raro", nombre: "Seguro raro", n: 1 });
  });
});

describe("los cambios de seguro", () => {
  it("se leen como «de dónde → a dónde», con «sin seguro» donde no había", () => {
    expect(resumenDelCambio(cambio())).toBe("EsSalud → FOLA");
    expect(resumenDelCambio(cambio({ de_nombre: null, de_tipo: null }))).toBe("sin seguro → FOLA");
    expect(resumenDelCambio(cambio({ a_nombre: null, a_tipo: null }))).toBe("EsSalud → sin seguro");
  });

  it("dicen por qué: el vínculo nuevo, o lo que escribió DO", () => {
    expect(origenDelCambio(cambio())).toBe("cambió de vínculo: Planilla → Practicantes");
    expect(origenDelCambio(cambio({ origen: "asignacion", detalle: "Lo pidió el corredor" }))).toBe("lo cambió DO: «Lo pidió el corredor»");
    expect(origenDelCambio(cambio({ origen: "asignacion", detalle: null }))).toBe("lo cambió DO");
  });

  it("piden dos pasos, la baja del anterior y el alta del nuevo, cada uno con su texto", () => {
    expect(pasosDelCambio(cambio())).toEqual([
      { paso: "baja", texto: "Confirmar con el contador la baja en EsSalud" },
      { paso: "alta", texto: "Registrar su póliza FOLA y avisarle al corredor" },
    ]);
  });

  it("solo piden lo que falta: con la baja hecha queda el alta", () => {
    expect(pasosDelCambio(cambio({ baja_pendiente: false, baja_hecha_el: "2026-10-16" })).map((x) => x.paso)).toEqual(["alta"]);
    expect(pasosDelCambio(cambio({ baja_pendiente: false, alta_pendiente: false }))).toEqual([]);
  });

  it("el nombre del vínculo es el del resto del sistema, y uno que no conoce se muestra tal cual", () => {
    expect(etiquetaVinculo("practicante")).toBe("Practicantes");
    expect(etiquetaVinculo("planilla")).toBe("Planilla");
    expect(etiquetaVinculo("vinculo_nuevo")).toBe("vinculo_nuevo");
    expect(etiquetaVinculo(null)).toBe("—");
  });
});

describe("lo que entra a la Bandeja", () => {
  const pendientes = (filas: FilaEquipoSeguro[], polizas: Poliza[] = [], cambios: CambioSeguro[] = [], hoy = HOY) =>
    pendientesDeSeguros(seguroPorPersona(filas, polizas, cambios, hoy), hoy);

  it("un hueco entra con su motivo y los días desde que venció", () => {
    const vencida = poliza({ ...completa, vigente_hasta: "2026-10-10", cubre_hoy: false });
    const items = pendientes([sinCobertura()], [vencida]);
    expect(items).toHaveLength(1);
    expect(items[0]).toMatchObject({
      tipo: "sin_poliza", clave: "sin_poliza:p1", motivoHueco: "vencida", dias: 7,
      titulo: "Su póliza de FOLA venció y no tiene seguro",
    });
  });

  it("el título dice de qué seguro se trata", () => {
    expect(pendientes([sinCobertura()])[0].titulo).toBe("Sin póliza de FOLA");
  });

  it("quien está al día y sin papeleo pendiente no entra", () => {
    expect(pendientes([persona()], [poliza({ ...completa, vigente_hasta: "2027-06-01" })])).toEqual([]);
  });

  it("EsSalud y quien no tiene seguro no piden nada: no hay póliza que registrar", () => {
    expect(pendientes([deLaPlanilla(), persona({ persona_id: "p3", ...SIN_SEGURO })])).toEqual([]);
  });

  it("el papeleo es UNA fila por póliza con lo que falta junto, no tres", () => {
    const items = pendientes([persona()], [poliza({ vigente_hasta: "2027-06-01" })]);
    expect(items).toHaveLength(1);
    expect(items[0]).toMatchObject({
      tipo: "papeleo", clave: "papeleo:z1", polizaId: "z1", titulo: "Prima del seguro (FOLA) sin pagar",
      pasos: ["pagada", "firmada", "factura"],
    });
    expect(items[0].detalle).toBe("Falta pagar la prima · Falta firmar y devolver la póliza y el convenio de pago · Falta la factura");
    expect(items[0].prima).toEqual({ estado: "al_dia", dias: 14, venceEl: "2026-10-31" });
  });

  it("con la prima pagada, el título pasa a lo que sigue", () => {
    const [i] = pendientes([persona()], [poliza({ vigente_hasta: "2027-06-01", pagada_el: "2026-10-15" })]);
    expect(i.titulo).toBe("Póliza del seguro (FOLA) sin firmar");
    const [j] = pendientes([persona()], [poliza({ vigente_hasta: "2027-06-01", pagada_el: "2026-10-15", firmada_el: "2026-10-15" })]);
    expect(j.titulo).toBe("Falta la factura del seguro (FOLA)");
  });

  it("el papeleo de un seguro complementario también entra, con el nombre del seguro", () => {
    const vida = poliza({ ...completa, poliza_id: "zv", producto: "vida_ley", producto_nombre: "Vida Ley", producto_principal: false, firmada_el: null, vigente_hasta: "2027-06-01" });
    const items = pendientes([persona()], [poliza({ ...completa, vigente_hasta: "2027-06-01" }), vida]);
    expect(items.map((i) => `${i.tipo}:${i.titulo}`)).toEqual(["papeleo:Póliza del seguro (Vida Ley) sin firmar"]);
  });

  it("por vencer entra con los días y con la fecha en que se queda sin seguro", () => {
    const items = pendientes([persona()], [poliza(completa)], [], "2026-12-01");
    expect(items).toHaveLength(1);
    expect(items[0]).toMatchObject({
      tipo: "por_vencer", dias: 31, hasta: "2027-01-01", titulo: "Su póliza de FOLA está por vencer",
      detalle: "Falta registrar la renovación",
    });
  });

  it("si la póliza dice que renueva sola, el aviso pide confirmarlo en vez de pedir registrar", () => {
    const [i] = pendientes([persona()], [poliza({ ...completa, renueva_sola: true })], [], "2026-12-01");
    expect(i.detalle).toBe("La póliza dice que renueva sola: confirmar con el corredor");
  });

  it("quien dejó de estar activa y conserva una póliza vigente pide la baja", () => {
    const items = pendientes([persona({ activa: false })], [poliza(completa)]);
    expect(items).toHaveLength(1);
    expect(items[0]).toMatchObject({ tipo: "baja", clave: "baja:p1", polizaId: "z1", titulo: "Ya no está activa y su póliza de FOLA sigue vigente" });
    // La fila se va cuando la póliza termina o cuando DO corrige su fecha de fin: el aviso lo dice.
    expect(items[0].detalle).toContain("corregir la fecha en que termina la póliza");
  });

  it("si las pólizas no se pudieron leer, el hueco sigue pero NO inventa que «nunca tuvo una»", () => {
    const vencida = poliza({ ...completa, vigente_hasta: "2026-10-10", cubre_hoy: false });
    const conLista = pendientesDeSeguros(seguroPorPersona([sinCobertura()], [vencida], [], HOY), HOY)[0];
    expect(conLista).toMatchObject({ titulo: "Su póliza de FOLA venció y no tiene seguro", motivoHueco: "vencida", dias: 7 });
    const sinLista = pendientesDeSeguros(seguroPorPersona([sinCobertura()], [], [], HOY), HOY, { sinDetalleDePolizas: true })[0];
    expect(sinLista).toMatchObject({
      tipo: "sin_poliza", clave: "sin_poliza:p1", titulo: "Sin póliza vigente de FOLA", motivoHueco: null, dias: null,
      detalle: "No se pudieron leer sus pólizas: míralas en Seguros",
    });
  });

  it("si la póliza de quien se fue todavía no empieza, también hay que darla de baja, y el aviso lo dice", () => {
    const futura = poliza({ ...completa, cubre_hoy: false, vigente_desde: "2026-11-01", vigente_hasta: "2027-02-01" });
    const [i] = pendientes([persona({ activa: false })], [futura]);
    expect(i).toMatchObject({ tipo: "baja", polizaId: "z1", titulo: "Ya no está activa y tiene una póliza de FOLA por empezar" });
  });

  it("el papeleo de una póliza vencida de quien ya se fue no vuelve a la Bandeja", () => {
    const vencida = poliza({ cubre_hoy: false, vigente_hasta: "2026-10-10" });
    expect(pendientes([persona({ activa: false })], [vencida])).toEqual([]);
  });

  describe("cuando alguien cambió de seguro", () => {
    // Ana pasó de FOLA a EsSalud (volvió a planilla) el 15 de octubre; su póliza FOLA sigue vigente.
    const aEsSalud = (o: Partial<CambioSeguro> = {}) => cambio({
      de_tipo: "salud_practicantes", de_nombre: "FOLA", a_tipo: "essalud", a_nombre: "EsSalud",
      vinculo_antes: "practicante", vinculo_despues: "planilla",
      baja_texto: "Pedirle a la aseguradora la baja de su póliza FOLA", alta_texto: "Confirmar con el contador el alta en EsSalud", ...o,
    });

    it("la baja del seguro anterior queda pendiente, con el texto del seguro y los días que lleva", () => {
      const items = pendientes([deLaPlanilla({ persona_id: "p1", persona: "Ana Prueba" })], [poliza(completa)], [aEsSalud({ alta_pendiente: false })]);
      expect(items).toHaveLength(1);
      expect(items[0]).toMatchObject({
        tipo: "cambio_baja", clave: "cambio_baja:c1", cambioId: "c1", personaId: "p1", dias: 2, hasta: "2026-10-15",
        titulo: "Pedirle a la aseguradora la baja de su póliza FOLA", detalle: "Cambió el 15 de octubre: FOLA → EsSalud",
      });
    });

    it("el alta en un seguro SIN póliza (EsSalud) es una tarea propia: no hay hueco que la cubra", () => {
      const items = pendientes([deLaPlanilla({ persona_id: "p1", persona: "Ana Prueba" })], [poliza(completa)], [aEsSalud({ baja_pendiente: false })]);
      expect(items.map((i) => i.tipo)).toEqual(["cambio_alta"]);
      expect(items[0].titulo).toBe("Confirmar con el contador el alta en EsSalud");
    });

    it("baja y alta son DOS pendientes, porque se cierran por separado", () => {
      const items = pendientes([deLaPlanilla({ persona_id: "p1", persona: "Ana Prueba" })], [poliza(completa)], [aEsSalud()]);
      expect(items.map((i) => i.clave)).toEqual(["cambio_baja:c1", "cambio_alta:c1"]);
    });

    it("el alta hacia un seguro CON póliza no se repite: ya es el hueco «sin póliza», y ese cuenta de dónde viene", () => {
      // Pasó de EsSalud a FOLA y todavía no se le registró la póliza: «Sin póliza de FOLA» y
      // «Dar de alta en FOLA» serían la misma tarea dicha dos veces.
      const items = pendientes([sinCobertura()], [], [cambio()]);
      expect(items.map((i) => i.tipo)).toEqual(["sin_poliza", "cambio_baja"]);
      expect(items[0].detalle).toBe("Cambió el 15 de octubre: EsSalud → FOLA");
    });

    it("si cambió dos veces hacia el mismo seguro sin registrar nada, tampoco se repite", () => {
      const otro = cambio({ id: "c2", fecha: "2026-10-16", creado_at: "2026-10-16T09:00:00Z", baja_pendiente: false });
      const items = pendientes([sinCobertura()], [], [cambio({ baja_pendiente: false }), otro]);
      expect(items.map((i) => i.tipo)).toEqual(["sin_poliza"]);
    });

    it("un cambio de hoy lleva cero días, no uno negativo", () => {
      const items = pendientes([deLaPlanilla({ persona_id: "p1", persona: "Ana Prueba" })], [poliza(completa)], [aEsSalud({ fecha: HOY, alta_pendiente: false })]);
      expect(items[0].dias).toBe(0);
    });

    it("sin pasos pendientes no entra nada", () => {
      const hecho = aEsSalud({ baja_pendiente: false, alta_pendiente: false });
      expect(pendientes([deLaPlanilla({ persona_id: "p1", persona: "Ana Prueba" })], [], [hecho])).toEqual([]);
    });
  });

  it("las claves no se repiten entre dos personas", () => {
    const items = pendientes([
      sinCobertura({ persona_id: "a", persona: "Alba" }), sinCobertura({ persona_id: "b", persona: "Beto" }),
    ]);
    expect(new Set(items.map((i) => i.clave)).size).toBe(2);
  });
});

describe("el buscador no esconde a nadie por una tilde", () => {
  const [p] = una([persona({ persona: "María Prueba" })], [poliza({ plan: "Plan 1" })]);
  it("encuentra por nombre sin tilde ni mayúsculas", () => { expect(coincideSeguro(p, "maria")).toBe(true); });
  it("por número de póliza", () => { expect(coincideSeguro(p, "24043267")).toBe(true); });
  it("por plan y por sede", () => { expect(coincideSeguro(p, "plan 1")).toBe(true); expect(coincideSeguro(p, "tru")).toBe(true); });
  it("por el seguro en que está y por su vínculo", () => {
    expect(coincideSeguro(p, "fola")).toBe(true);
    expect(coincideSeguro(p, "practicantes")).toBe(true);
  });
  it("por la aseguradora", () => { expect(coincideSeguro(p, "pacifico")).toBe(true); });
  it("sin texto, deja pasar a todos", () => { expect(coincideSeguro(p, "  ")).toBe(true); });
  it("y no inventa coincidencias", () => { expect(coincideSeguro(p, "lima")).toBe(false); });
});

describe("los papeles de una póliza", () => {
  it("cada tipo de archivo tiene su nombre en pantalla", () => {
    expect(etiquetaTipoArchivo("poliza")).toBe("Póliza");
    expect(etiquetaTipoArchivo("convenio_pago")).toBe("Convenio de pago");
    expect(etiquetaTipoArchivo("factura")).toBe("Factura");
    expect(etiquetaTipoArchivo("otro")).toBe("Otro papel");
    expect(etiquetaTipoArchivo("raro")).toBe("raro");
  });
});

describe("registrar la misma póliza a varias personas: a quién la base le va a rechazar", () => {
  const viva = poliza({ persona_id: "p1", producto: "vida_ley", vigente_desde: "2026-10-01", vigente_hasta: "2027-10-01" });

  it("una póliza del mismo seguro que se cruza con las fechas es un cruce", () => {
    expect(polizaQueSeCruza([viva], "p1", "vida_ley", "2026-12-01", "2027-12-01")).toBe(viva);
    expect(polizaQueSeCruza([viva], "p1", "vida_ley", "2026-01-01", "2026-10-02")).toBe(viva);
    expect(polizaQueSeCruza([viva], "p1", "vida_ley", "2026-11-01", "2026-12-01")).toBe(viva);
  });

  it("el último día es EXCLUSIVO: la que empieza el día en que otra termina no se cruza (así se renueva)", () => {
    expect(polizaQueSeCruza([viva], "p1", "vida_ley", "2027-10-01", "2028-10-01")).toBeNull();
    expect(polizaQueSeCruza([viva], "p1", "vida_ley", "2025-10-01", "2026-10-01")).toBeNull();
    // Un día de más a cualquiera de los dos lados sí se cruza.
    expect(polizaQueSeCruza([viva], "p1", "vida_ley", "2027-09-30", "2028-10-01")).toBe(viva);
    expect(polizaQueSeCruza([viva], "p1", "vida_ley", "2025-10-01", "2026-10-02")).toBe(viva);
  });

  it("solo cuenta la misma persona y el mismo seguro", () => {
    expect(polizaQueSeCruza([viva], "p2", "vida_ley", "2026-12-01", "2027-12-01")).toBeNull();
    expect(polizaQueSeCruza([viva], "p1", "eps", "2026-12-01", "2027-12-01")).toBeNull();
  });

  it("fechas incompletas o al revés no cruzan con nada: de eso se queja el formulario", () => {
    expect(polizaQueSeCruza([viva], "p1", "vida_ley", "", "2027-12-01")).toBeNull();
    expect(polizaQueSeCruza([viva], "p1", "vida_ley", "2026-12-01", "")).toBeNull();
    expect(polizaQueSeCruza([viva], "p1", "vida_ley", "2027-12-01", "2026-12-01")).toBeNull();
    expect(polizaQueSeCruza([viva], "p1", "vida_ley", "2026-12-01", "2026-12-01")).toBeNull();
  });
});

describe("quién está en planilla lo dice la base, no el navegador", () => {
  it("la persona lleva `en_planilla` tal como llegó, sin deducirlo de su vínculo", () => {
    const [practicante] = seguroPorPersona([persona()], [poliza()], [], HOY);
    const [planilla] = seguroPorPersona([deLaPlanilla()], [], [], HOY);
    expect(practicante.enPlanilla).toBe(false);
    expect(planilla.enPlanilla).toBe(true);
    // Si la base dijera otra cosa de un vínculo, manda la base.
    const [raro] = seguroPorPersona([persona({ tipo_vinculo: "planilla", en_planilla: false })], [poliza()], [], HOY);
    expect(raro.enPlanilla).toBe(false);
  });
});

describe("las otras pólizas de la misma póliza colectiva", () => {
  const colectiva = (persona_id: string, o: Partial<Poliza> = {}) => poliza({
    persona_id, persona: `Persona ${persona_id}`, poliza_id: `z-${persona_id}`,
    producto: "vida_ley", producto_nombre: "Vida Ley", aseguradora: "La Positiva", numero_poliza: "VL-001",
    vigente_desde: "2026-10-01", vigente_hasta: "2027-10-01", ...o,
  });
  const ana = colectiva("a");

  it("son las de otras personas con el mismo seguro, aseguradora, número y vigencia", () => {
    const todas = [ana, colectiva("b"), colectiva("c")];
    expect(hermanasDe(ana, todas).map((z) => z.persona_id)).toEqual(["b", "c"]);
  });

  it("no incluye a la propia póliza ni otra de la misma persona", () => {
    const otraDeAna = colectiva("a", { poliza_id: "z-a2", vigente_desde: "2027-10-01", vigente_hasta: "2028-10-01" });
    expect(hermanasDe(ana, [ana, otraDeAna])).toEqual([]);
    // Ni siquiera con idénticos datos: una persona no se hermana consigo misma.
    expect(hermanasDe(ana, [ana, colectiva("a", { poliza_id: "z-a3" })])).toEqual([]);
  });

  it("una fila corregida —otra fecha, otro número— deja de ser la misma póliza", () => {
    expect(hermanasDe(ana, [ana, colectiva("b", { vigente_hasta: "2027-09-30" })])).toEqual([]);
    expect(hermanasDe(ana, [ana, colectiva("b", { vigente_desde: "2026-10-02" })])).toEqual([]);
    expect(hermanasDe(ana, [ana, colectiva("b", { numero_poliza: "VL-002" })])).toEqual([]);
    expect(hermanasDe(ana, [ana, colectiva("b", { aseguradora: "Rímac Seguros" })])).toEqual([]);
  });

  it("otro seguro con el mismo número no se mezcla", () => {
    expect(hermanasDe(ana, [ana, colectiva("b", { producto: "eps", producto_nombre: "EPS" })])).toEqual([]);
  });

  it("un espacio de más o una mayúscula en el número no las separa", () => {
    expect(hermanasDe(ana, [ana, colectiva("b", { numero_poliza: " vl-001 ", aseguradora: "la positiva" })]).map((z) => z.persona_id)).toEqual(["b"]);
  });

  it("una póliza sola no tiene hermanas", () => {
    expect(hermanasDe(ana, [ana])).toEqual([]);
  });
});

describe("a quién se le ofrece una póliza de un seguro", () => {
  const personas = [
    { id: "a", tipoPrincipal: "salud_practicantes" },
    { id: "b", tipoPrincipal: "essalud" },
    { id: "c", tipoPrincipal: null },
  ];
  const tipos = [
    { clave: "salud_practicantes", principal: true },
    { clave: "essalud", principal: true },
    { clave: "vida_ley", principal: false },
  ];

  it("si es el seguro PRINCIPAL, solo a quien lo tiene hoy: a alguien de planilla no se le registra FOLA", () => {
    expect(personasParaPoliza("salud_practicantes", tipos, personas).map((p) => p.id)).toEqual(["a"]);
  });

  it("si va además del principal, a cualquiera, también a quien no tiene seguro principal (honorarios)", () => {
    expect(personasParaPoliza("vida_ley", tipos, personas).map((p) => p.id)).toEqual(["a", "b", "c"]);
  });

  it("sin seguro elegido, o uno que ya no está en el catálogo, no se filtra nada: la base decide", () => {
    expect(personasParaPoliza("", tipos, personas)).toHaveLength(3);
    expect(personasParaPoliza("otro", tipos, personas)).toHaveLength(3);
  });

  it("no devuelve la misma lista: quien la modifique no toca la de la pantalla", () => {
    expect(personasParaPoliza("vida_ley", tipos, personas)).not.toBe(personas);
  });
});

describe("el número que alguien escribió en un campo", () => {
  it("«179,97» y «179.97» son lo mismo; vacío o texto, nada", () => {
    expect(numeroDeTexto("179,97")).toBe(179.97);
    expect(numeroDeTexto(" 179.97 ")).toBe(179.97);
    expect(numeroDeTexto("0")).toBe(0);
    expect(numeroDeTexto("")).toBeNull();
    expect(numeroDeTexto("   ")).toBeNull();
    expect(numeroDeTexto("abc")).toBeNull();
  });
});

describe("las fechas que son un año mal tecleado y no una póliza", () => {
  // La base rechaza lo mismo (`fn_seguro_datos_validos`): diez años de vigencia, diez años desde hoy y un
  // año de la prima a cada lado de la vigencia. Aquí solo se dice antes y junto al campo.
  it("una vigencia normal, de tres meses o de un año, no es sospechosa", () => {
    expect(fechasSospechosas({ desde: "2026-10-17", hasta: "2027-01-17" }, HOY)).toEqual({});
    expect(fechasSospechosas({ desde: "2026-10-17", hasta: "2027-10-17" }, HOY)).toEqual({});
  });

  it("escribir 20277 por 2027 sí lo es", () => {
    expect(fechasSospechosas({ desde: "2026-10-17", hasta: "20277-01-10" }, HOY).vigencia).toBe("La vigencia no puede pasar de 10 años: revisa el año.");
  });

  it("diez años justos (3660 días) todavía pasa; un día más, no", () => {
    expect(fechasSospechosas({ desde: HOY, hasta: "2036-10-24" }, HOY)).toEqual({});
    expect(fechasSospechosas({ desde: HOY, hasta: "2036-10-25" }, HOY).vigencia).toBeDefined();
  });

  it("una póliza que EMPIEZA en un futuro lejano también: el final se compara con hoy, no solo con el inicio", () => {
    expect(fechasSospechosas({ desde: "2045-01-01", hasta: "2045-04-01" }, HOY).vigencia).toBeDefined();
  });

  it("una que empezó hace mucho no se avisa aquí: no deja a nadie cubierto, y no es de este tecleo", () => {
    expect(fechasSospechosas({ desde: "2015-01-01", hasta: "2015-04-01" }, HOY)).toEqual({});
  });

  it("fechas incompletas o al revés no son de aquí: de eso se queja el formulario", () => {
    expect(fechasSospechosas({ desde: "", hasta: "20277-01-10" }, HOY)).toEqual({});
    expect(fechasSospechosas({ desde: "2026-10-17", hasta: "" }, HOY)).toEqual({});
    expect(fechasSospechosas({ desde: "2027-10-17", hasta: "2026-10-17" }, HOY)).toEqual({});
  });

  it("el vencimiento de la prima: dentro de un año de la vigencia, no; más lejos, sí", () => {
    const base = { desde: "2026-10-01", hasta: "2027-01-01" };
    expect(fechasSospechosas({ ...base, primaVence: "2026-10-31" }, HOY)).toEqual({});
    expect(fechasSospechosas({ ...base, primaVence: "2025-10-01" }, HOY)).toEqual({});
    expect(fechasSospechosas({ ...base, primaVence: "2028-01-01" }, HOY)).toEqual({});
    expect(fechasSospechosas({ ...base, primaVence: "2025-09-30" }, HOY).primaVence).toBeDefined();
    expect(fechasSospechosas({ ...base, primaVence: "2028-01-02" }, HOY).primaVence).toBeDefined();
    expect(fechasSospechosas({ ...base, primaVence: "20266-10-31" }, HOY).primaVence).toBeDefined();
    expect(fechasSospechosas({ ...base, primaVence: "" }, HOY)).toEqual({});
  });

  it("si la vigencia ya es el problema, no se agrega un segundo aviso sobre la prima", () => {
    const r = fechasSospechosas({ desde: "2026-10-01", hasta: "20277-01-01", primaVence: "2026-10-31" }, HOY);
    expect(r.vigencia).toBeDefined();
    expect(r.primaVence).toBeUndefined();
  });
});

