// ============================================================================
// bandeja-seguros.test.ts — los seguros del equipo en la Bandeja (0528)
// ============================================================================
// Lo que se defiende acá:
//
// 1. QUIEN LLEVA PÓLIZA Y NO LA TIENE ES LO PRIMERO QUE SALE. Va a «Vencido» —el
//    riesgo ya corre— y, entre dos huecos, el más largo antes: quien nunca tuvo
//    póliza antes que quien la perdió ayer.
// 2. LA PRIMA ES LO ÚNICO CON PLAZO. Mora y suspensión de la cobertura (30 días)
//    pasan a «Vencido»; firma y factura no tienen fecha y quedan «Sin plazo».
// 3. UNA FILA POR HECHO, no varias: prima, firma y factura son un solo trámite
//    con el corredor, y «sin póliza de FOLA» y «dar de alta en FOLA» son la misma
//    tarea dicha dos veces.
// 4. UN CAMBIO DE SEGURO PIDE DOS COSAS Y CADA UNA SE CIERRA POR SU LADO: la baja
//    del anterior y el alta del nuevo.
// 5. EL SEGURO DE QUIEN NO LLEVA PÓLIZA (EsSalud) NO PIDE NADA: lo paga la planilla.
// 6. QUIEN NO DEBE VER SEGUROS NO LOS VE: el módulo es de DO, y no aparece para
//    una líder de equipo.
// 7. LAS TRES CONSULTAS NO SE PISAN: cargar una no borra lo que trajo otra, y
//    ninguna escribe sobre el objeto compartido de `FUENTES_VACIAS`.
// La regla de quién tiene hueco la dice la base y la lee `lib/admin/seguros.ts`
// (tests/seguros.test.ts); acá solo se comprueba lo que la Bandeja hace con ella.
// ============================================================================
import { describe, expect, it, vi } from "vitest";
import { armarPendientes, FUENTES_VACIAS, modulosDeLaBandeja, traerFuentesBandeja, type FuentesSeguros } from "../apps/web/lib/admin/bandeja-fuentes";
import {
  urgenciaSeguroCambio, urgenciaSeguroPapeleo, urgenciaSeguroPorVencer, urgenciaSeguroSinPoliza,
} from "../apps/web/lib/admin/bandeja-urgencia";
import type { CambioSeguro, FilaEquipoSeguro, Poliza } from "../apps/web/lib/admin/seguros";

const HOY = "2026-10-17";

function persona(o: Partial<FilaEquipoSeguro> = {}): FilaEquipoSeguro {
  return {
    persona_id: "p1", persona: "Ana Prueba", sede: "TRU", tipo_vinculo: "practicante", practicante_modalidad: "profesional",
    activa: true, tipo: "salud_practicantes", tipo_nombre: "FOLA", origen: "vinculo",
    asignacion_id: null, asignacion_desde: null, asignacion_motivo: null,
    tipo_automatico: "salud_practicantes", tipo_automatico_nombre: "FOLA",
    con_poliza: true, cubre_hoy: true, hueco: false, ...o,
  };
}
const sinCobertura = (o: Partial<FilaEquipoSeguro> = {}) => persona({ cubre_hoy: false, hueco: true, ...o });
const deLaPlanilla = (o: Partial<FilaEquipoSeguro> = {}) => persona({
  persona_id: "p2", persona: "Beto Planilla", tipo_vinculo: "planilla", practicante_modalidad: null,
  tipo: "essalud", tipo_nombre: "EsSalud", tipo_automatico: "essalud", tipo_automatico_nombre: "EsSalud",
  con_poliza: false, cubre_hoy: null, hueco: false, ...o,
});

/** Una póliza con todo el papeleo hecho, para que solo hable lo que cada prueba toca. */
function poliza(o: Partial<Poliza> = {}): Poliza {
  return {
    persona_id: "p1", persona: "Ana Prueba", sede: "TRU", persona_activa: true,
    producto: "salud_practicantes", producto_nombre: "FOLA", producto_principal: true,
    poliza_id: "z1", aseguradora: "Pacífico Seguros", numero_poliza: "24043267",
    vigente_desde: "2026-10-01", vigente_hasta: "2027-06-01", cubre_hoy: true, prima_total: 179.97,
    prima_vence_el: "2026-10-31", plan: null, beneficio_enfermedad: null, beneficio_accidente: null,
    renueva_sola: null, pagada_el: "2026-10-15", firmada_el: "2026-10-15", factura_recibida_el: "2026-10-16",
    nota: null, archivos: 0, creada_at: "2026-10-14T15:00:00Z", ...o,
  };
}
const sinPapeles = { pagada_el: null, firmada_el: null, factura_recibida_el: null };

function cambio(o: Partial<CambioSeguro> = {}): CambioSeguro {
  return {
    id: "c1", persona_id: "p1", persona: "Ana Prueba", sede: "TRU", persona_activa: true,
    de_tipo: "salud_practicantes", de_nombre: "FOLA", a_tipo: "essalud", a_nombre: "EsSalud",
    fecha: "2026-10-15", origen: "vinculo", vinculo_antes: "practicante", vinculo_despues: "planilla", detalle: null,
    baja_pendiente: true, baja_texto: "Pedirle a la aseguradora la baja de su póliza FOLA", baja_hecha_el: null, baja_nota: null,
    alta_pendiente: true, alta_texto: "Confirmar con el contador el alta en EsSalud", alta_hecha_el: null, alta_nota: null,
    creado_at: "2026-10-15T14:00:00Z", ...o,
  };
}

const armar = (s: Partial<FuentesSeguros>) =>
  armarPendientes({ ...FUENTES_VACIAS, seguros: { equipo: [], polizas: [], cambios: [], ...s } }, { hoy: HOY });

describe("quién entra a la Bandeja por sus seguros", () => {
  it("quien está al día y con todo el papeleo hecho no entra", () => {
    expect(armar({ equipo: [persona()], polizas: [poliza()] })).toEqual([]);
  });

  it("quien lleva póliza y no la tiene entra como «Vencido», con su botón y a su persona", () => {
    const [p] = armar({ equipo: [sinCobertura()] });
    expect(p).toMatchObject({
      tipo: "seguro_sin_poliza", clave: "seguro_sin_poliza:p1", modulo: "seguros", personaId: "p1",
      titulo: "Sin póliza de FOLA", resolucion: "afuera",
    });
    expect(p.urgencia.grupo).toBe("vencido");
    expect(p.ir).toEqual({ texto: "Registrar póliza", href: "/admin/seguros?persona=p1" });
  });

  it("una póliza que venció ayer también es un hueco, y dice hace cuánto", () => {
    const vencida = poliza({ vigente_hasta: "2026-10-16", cubre_hoy: false });
    const [p] = armar({ equipo: [sinCobertura()], polizas: [vencida] });
    expect(p.titulo).toBe("Su póliza de FOLA venció y no tiene seguro");
    expect(p.urgencia.plazo).toBe("Sin seguro hace 1 día");
  });

  it("cubierta pero por vencer entra con la fecha en que se queda sin seguro", () => {
    const [p] = armar({ equipo: [persona()], polizas: [poliza({ vigente_hasta: "2026-11-20" })] });
    expect(p).toMatchObject({ tipo: "seguro_por_vencer", titulo: "Su póliza de FOLA está por vencer" });
    expect(p.urgencia).toMatchObject({ grupo: "proximo", plazo: "Sin seguro en 34 días", nota: "el 20 de noviembre" });
    expect(p.ir?.texto).toBe("Registrar renovación");
  });

  it("con la renovación ya registrada, por vencer deja de entrar", () => {
    const renov = poliza({ poliza_id: "z2", vigente_desde: "2026-11-20", vigente_hasta: "2027-02-20", cubre_hoy: false });
    expect(armar({ equipo: [persona()], polizas: [poliza({ vigente_hasta: "2026-11-20" }), renov] })).toEqual([]);
  });

  it("el papeleo es UNA fila por póliza, con la prima como lo urgente", () => {
    const filas = armar({ equipo: [persona()], polizas: [poliza(sinPapeles)] });
    expect(filas).toHaveLength(1);
    expect(filas[0]).toMatchObject({ tipo: "seguro_papeleo", clave: "seguro_papeleo:z1", titulo: "Prima del seguro (FOLA) sin pagar" });
    expect(filas[0].detalle).toContain("Falta pagar la prima");
    expect(filas[0].detalle).toContain("Falta la factura");
  });

  it("el papeleo de un seguro complementario también entra, con su nombre", () => {
    const vida = poliza({ poliza_id: "zv", producto: "vida_ley", producto_nombre: "Vida Ley", producto_principal: false, firmada_el: null });
    const filas = armar({ equipo: [persona()], polizas: [poliza(), vida] });
    expect(filas.map((p) => p.titulo)).toEqual(["Póliza del seguro (Vida Ley) sin firmar"]);
  });

  it("quien dejó de estar activa y conserva su póliza pide la baja, sin plazo", () => {
    const [p] = armar({ equipo: [persona({ activa: false })], polizas: [poliza()] });
    expect(p).toMatchObject({ tipo: "seguro_baja", titulo: "Ya no está activa y su póliza de FOLA sigue vigente" });
    expect(p.urgencia.grupo).toBe("sin_plazo");
  });

  it("EsSalud no lleva póliza: quien está en planilla no entra, aunque no haya ninguna registrada", () => {
    expect(armar({ equipo: [deLaPlanilla()] })).toEqual([]);
  });

  it("dos personas con hueco no se pisan: cada una tiene su clave", () => {
    const filas = armar({ equipo: [sinCobertura({ persona_id: "a", persona: "Alba" }), sinCobertura({ persona_id: "b", persona: "Beto" })] });
    expect(new Set(filas.map((p) => p.clave)).size).toBe(2);
  });
});

describe("cuando alguien cambia de seguro", () => {
  // Ana volvió a planilla el 15 de octubre: su seguro pasó de FOLA a EsSalud y la póliza FOLA sigue vigente.
  const enPlanilla = () => deLaPlanilla({ persona_id: "p1", persona: "Ana Prueba" });

  it("la baja del seguro anterior entra con el texto del seguro, su botón y los días que lleva esperando", () => {
    const [p] = armar({ equipo: [enPlanilla()], polizas: [poliza()], cambios: [cambio({ alta_pendiente: false })] });
    expect(p).toMatchObject({
      tipo: "seguro_cambio_baja", clave: "seguro_cambio_baja:c1", itemId: "c1", modulo: "seguros", personaId: "p1",
      titulo: "Pedirle a la aseguradora la baja de su póliza FOLA", detalle: "Cambió el 15 de octubre: FOLA → EsSalud",
      resolucion: "afuera",
    });
    expect(p.urgencia).toMatchObject({ grupo: "sin_plazo", plazo: "Pedir la baja", nota: "cambió hace 2 días" });
    expect(p.ir).toEqual({ texto: "Marcar la baja", href: "/admin/seguros?persona=p1" });
  });

  it("el alta en un seguro sin póliza (EsSalud) es una fila propia, con su botón", () => {
    const [p] = armar({ equipo: [enPlanilla()], polizas: [poliza()], cambios: [cambio({ baja_pendiente: false })] });
    expect(p).toMatchObject({ tipo: "seguro_cambio_alta", titulo: "Confirmar con el contador el alta en EsSalud" });
    expect(p.urgencia.plazo).toBe("Dar de alta");
    expect(p.ir?.texto).toBe("Marcar el alta");
  });

  it("baja y alta son DOS filas, porque se cierran por separado", () => {
    const filas = armar({ equipo: [enPlanilla()], polizas: [poliza()], cambios: [cambio()] });
    expect(filas.map((p) => p.clave).sort()).toEqual(["seguro_cambio_alta:c1", "seguro_cambio_baja:c1"]);
  });

  it("el alta hacia un seguro CON póliza no se repite: ya es el hueco «sin póliza»", () => {
    // Pasó de EsSalud a FOLA y todavía no tiene póliza.
    const aFola = cambio({
      de_tipo: "essalud", de_nombre: "EsSalud", a_tipo: "salud_practicantes", a_nombre: "FOLA", vinculo_antes: "planilla", vinculo_despues: "practicante",
      baja_pendiente: false, alta_texto: "Registrar su póliza FOLA y avisarle al corredor",
    });
    const filas = armar({ equipo: [sinCobertura()], cambios: [aFola] });
    expect(filas.map((p) => p.tipo)).toEqual(["seguro_sin_poliza"]);
    expect(filas[0].detalle).toBe("Cambió el 15 de octubre: EsSalud → FOLA");
  });

  it("un cambio ya cerrado no entra", () => {
    const hecho = cambio({ baja_pendiente: false, alta_pendiente: false });
    expect(armar({ equipo: [enPlanilla()], polizas: [poliza()], cambios: [hecho] })).toEqual([]);
  });
});

describe("la urgencia de cada cosa", () => {
  it("ningún texto de plazo pasa de 24 letras: la columna es angosta y el texto se pisaba con el botón", () => {
    const textos = [
      urgenciaSeguroSinPoliza("nunca", null).plazo, urgenciaSeguroSinPoliza("vencida", 0).plazo,
      urgenciaSeguroSinPoliza("vencida", 100).plazo, urgenciaSeguroSinPoliza("aun_no_empieza", null).plazo,
      urgenciaSeguroSinPoliza("nunca", null).plazo, urgenciaSeguroSinPoliza(null, null).plazo,
      urgenciaSeguroPorVencer(45, "2026-12-01").plazo, urgenciaSeguroPorVencer(0, "2026-12-01").plazo,
      urgenciaSeguroPapeleo({ estado: "en_mora", dias: -29, venceEl: null }, ["pagada"]).plazo,
      urgenciaSeguroPapeleo({ estado: "suspendida", dias: -90, venceEl: null }, ["pagada"]).plazo,
      urgenciaSeguroPapeleo({ estado: "por_vencer", dias: 7, venceEl: null }, ["pagada"]).plazo,
      urgenciaSeguroPapeleo({ estado: "al_dia", dias: 20, venceEl: null }, ["pagada"]).plazo,
      urgenciaSeguroCambio("baja", 3).plazo, urgenciaSeguroCambio("alta", 3).plazo,
    ];
    for (const t of textos) expect(t.length, t).toBeLessThanOrEqual(24);
  });

  it("quien nunca tuvo póliza va antes que quien la perdió hace una semana, y esa antes que la de ayer", () => {
    const nunca = urgenciaSeguroSinPoliza("nunca", null);
    const semana = urgenciaSeguroSinPoliza("vencida", 7);
    const ayer = urgenciaSeguroSinPoliza("vencida", 1);
    expect([nunca, semana, ayer].every((u) => u.grupo === "vencido")).toBe(true);
    expect(nunca.orden).toBeLessThan(semana.orden);
    expect(semana.orden).toBeLessThan(ayer.orden);
  });

  it("si no se leyeron las pólizas, la fila lo dice en vez de afirmar que «nunca tuvo una registrada»", () => {
    expect(urgenciaSeguroSinPoliza(null, null)).toMatchObject({ grupo: "vencido", plazo: "Sin póliza vigente", nota: "no se leyeron sus pólizas" });
    expect(urgenciaSeguroSinPoliza("nunca", null)).toMatchObject({ plazo: "Sin póliza", nota: "nunca tuvo una registrada" });
  });

  it("la póliza que ya está registrada pero todavía no empieza sigue siendo «sin seguro hoy»", () => {
    expect(urgenciaSeguroSinPoliza("aun_no_empieza", null)).toMatchObject({ grupo: "vencido", plazo: "Sin seguro hoy" });
  });

  it("por vencer: mañana sigue siendo «próximo» (hoy ya sería un hueco)", () => {
    expect(urgenciaSeguroPorVencer(1, "2026-10-18")).toMatchObject({ grupo: "proximo", plazo: "Sin seguro mañana" });
  });

  it("la prima en mora y la suspendida son «Vencido»; la que vence esta semana, «Próximos»", () => {
    expect(urgenciaSeguroPapeleo({ estado: "en_mora", dias: -3, venceEl: "2026-10-14" }, ["pagada"])).toMatchObject({ grupo: "vencido", plazo: "En mora hace 3 días" });
    expect(urgenciaSeguroPapeleo({ estado: "suspendida", dias: -40, venceEl: "2026-09-07" }, ["pagada"])).toMatchObject({ grupo: "vencido", plazo: "Cobertura suspendida" });
    expect(urgenciaSeguroPapeleo({ estado: "por_vencer", dias: 4, venceEl: "2026-10-21" }, ["pagada"])).toMatchObject({ grupo: "proximo", plazo: "Prima vence en 4 días" });
    expect(urgenciaSeguroPapeleo({ estado: "por_vencer", dias: 0, venceEl: HOY }, ["pagada"])).toMatchObject({ grupo: "hoy", plazo: "Prima vence hoy" });
  });

  it("la mora pesa más cuanto más vieja: orden más bajo primero", () => {
    const tres = urgenciaSeguroPapeleo({ estado: "en_mora", dias: -3, venceEl: null }, ["pagada"]);
    const veinte = urgenciaSeguroPapeleo({ estado: "en_mora", dias: -20, venceEl: null }, ["pagada"]);
    expect(veinte.orden).toBeLessThan(tres.orden);
  });

  it("con la prima pagada, firma y factura no tienen plazo", () => {
    expect(urgenciaSeguroPapeleo({ estado: "pagada", dias: null, venceEl: null }, ["firmada", "factura"])).toMatchObject({ grupo: "sin_plazo", plazo: "Sin firmar" });
    expect(urgenciaSeguroPapeleo({ estado: "pagada", dias: null, venceEl: null }, ["factura"])).toMatchObject({ grupo: "sin_plazo", plazo: "Sin factura" });
  });

  it("una prima por pagar con tiempo de sobra no aprieta: «Sin plazo» con su fecha", () => {
    expect(urgenciaSeguroPapeleo({ estado: "al_dia", dias: 14, venceEl: "2026-10-31" }, ["pagada", "firmada"]))
      .toMatchObject({ grupo: "sin_plazo", plazo: "Prima por pagar", nota: "vence el 31 de octubre" });
  });

  it("un cambio de seguro no inventa un plazo: va a «Sin plazo» y sale primero el que lleva más esperando", () => {
    const hoy = urgenciaSeguroCambio("baja", 0);
    const semana = urgenciaSeguroCambio("baja", 7);
    expect(hoy).toMatchObject({ grupo: "sin_plazo", plazo: "Pedir la baja", nota: "cambió hoy" });
    expect(urgenciaSeguroCambio("alta", 1)).toMatchObject({ plazo: "Dar de alta", nota: "cambió ayer" });
    expect(semana.nota).toBe("cambió hace 7 días");
    expect(semana.orden).toBeLessThan(hoy.orden);
  });
});

describe("quién ve el módulo", () => {
  it("solo DO: la líder de equipo y la integrante no lo ven", () => {
    expect(modulosDeLaBandeja("admin")).toContain("seguros");
    expect(modulosDeLaBandeja("lider_do")).toContain("seguros");
    expect(modulosDeLaBandeja("supervisor_sede")).not.toContain("seguros");
    expect(modulosDeLaBandeja("integrante")).not.toContain("seguros");
  });
});

describe("de dónde se traen los seguros", () => {
  /** Un cliente de mentira: las consultas de seguros contestan lo que se le dé; todo lo demás, vacío. */
  function cliente(respuestas: Record<string, { data?: unknown; error?: unknown }> = {}) {
    const rpc = vi.fn((nombre: string) => Promise.resolve({ data: [], error: null, ...respuestas[nombre] }));
    const cadena = (): unknown => new Proxy(function () {}, {
      get: (_t, prop) => (prop === "then" ? (ok: (v: unknown) => unknown, ko: (e: unknown) => unknown) => Promise.resolve({ data: [], error: null }).then(ok, ko) : cadena()),
      apply: () => cadena(),
    });
    const supabase = { rpc, from: () => cadena(), auth: { getUser: () => Promise.resolve({ data: { user: null }, error: null }) } };
    return { supabase: supabase as never, rpc };
  }

  it("pide las tres consultas, y la de cambios solo con los pendientes", async () => {
    const { supabase, rpc } = cliente();
    await traerFuentesBandeja(supabase, "admin", () => {}, HOY);
    const llamadas = rpc.mock.calls.map(([nombre, args]) => [nombre, args]);
    expect(llamadas).toContainEqual(["fn_seguros_equipo", undefined]);
    expect(llamadas).toContainEqual(["fn_seguros_tablero", undefined]);
    expect(llamadas).toContainEqual(["fn_seguros_cambios", { p_solo_pendientes: true }]);
  });

  it("deja cada respuesta en su sitio, sin pisar las otras", async () => {
    const equipo = [persona()];
    const polizas = [poliza()];
    const cambios = [cambio()];
    const { supabase } = cliente({
      fn_seguros_equipo: { data: equipo }, fn_seguros_tablero: { data: polizas }, fn_seguros_cambios: { data: cambios },
    });
    const f = await traerFuentesBandeja(supabase, "admin", () => {}, HOY);
    expect(f.seguros).toEqual({ equipo, polizas, cambios });
    expect(f.fallidas).not.toContain("seguros");
  });

  it("no escribe sobre el objeto compartido de FUENTES_VACIAS: la siguiente persona que abre la Bandeja parte de cero", async () => {
    const { supabase } = cliente({ fn_seguros_equipo: { data: [persona()] } });
    await traerFuentesBandeja(supabase, "admin", () => {}, HOY);
    expect(FUENTES_VACIAS.seguros).toEqual({ equipo: [], polizas: [], cambios: [] });
  });

  it("si una consulta falla, el módulo queda marcado como fallido —nunca «Al día»— y las otras valen lo que trajeron", async () => {
    const equipo = [sinCobertura()];
    const { supabase } = cliente({
      fn_seguros_equipo: { data: equipo }, fn_seguros_tablero: { data: null, error: { message: "boom" } },
    });
    const avisos: string[] = [];
    const f = await traerFuentesBandeja(supabase, "admin", (que) => avisos.push(que), HOY);
    expect(f.fallidas).toContain("seguros");
    expect(avisos).toEqual(["las pólizas de seguro"]);
    expect(f.seguros.equipo).toEqual(equipo);
    expect(f.seguros.polizas).toEqual([]);
  });

  it("y el hueco real de quien no se pudo mirar la lista de pólizas sale SIN inventar la razón", async () => {
    const equipo = [sinCobertura()];
    const { supabase } = cliente({
      fn_seguros_equipo: { data: equipo }, fn_seguros_tablero: { data: null, error: { message: "boom" } },
    });
    const f = await traerFuentesBandeja(supabase, "admin", () => {}, HOY);
    const [p] = armarPendientes(f, { hoy: HOY });
    expect(p).toMatchObject({ tipo: "seguro_sin_poliza", titulo: "Sin póliza vigente de FOLA" });
    expect(p.urgencia).toMatchObject({ grupo: "vencido", plazo: "Sin póliza vigente" });
    expect(p.detalle).toContain("No se pudieron leer sus pólizas");
  });

  it("una consulta que falla nunca inventa un hueco: sin pólizas, quien está al día no se vuelve «sin póliza»", () => {
    // `hueco` lo dice `fn_seguros_equipo`; la lista de pólizas solo agrega detalle.
    expect(armar({ equipo: [persona()], polizas: [] })).toEqual([]);
  });

  it("la líder de equipo no pide los seguros: ni siquiera se consultan", async () => {
    const { supabase, rpc } = cliente();
    await traerFuentesBandeja(supabase, "supervisor_sede", () => {}, HOY);
    expect(rpc.mock.calls.map(([nombre]) => nombre).filter((n) => String(n).startsWith("fn_seguros"))).toEqual([]);
  });
});
