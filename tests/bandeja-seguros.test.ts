// ============================================================================
// bandeja-seguros.test.ts — los seguros de los practicantes en la Bandeja (0528)
// ============================================================================
// Lo que se defiende acá:
//
// 1. UN PRACTICANTE SIN PÓLIZA ES LO PRIMERO QUE SALE. Va a «Vencido» —el riesgo
//    ya corre— y, entre dos huecos, el más largo antes: quien nunca tuvo póliza
//    antes que quien la perdió ayer.
// 2. LA PRIMA ES LO ÚNICO CON PLAZO. Mora y suspensión de la cobertura (30 días)
//    pasan a «Vencido»; firma y factura no tienen fecha y quedan «Sin plazo».
// 3. UNA FILA POR PÓLIZA, no tres: prima, firma y factura son un solo trámite con
//    el corredor.
// 4. QUIEN NO DEBE VER SEGUROS NO LOS VE: el módulo es de DO, y no aparece para
//    una líder de equipo.
// La regla de quién tiene hueco la dice la base y la lee `lib/admin/seguros.ts`
// (tests/seguros.test.ts); acá solo se comprueba lo que la Bandeja hace con ella.
// ============================================================================
import { describe, expect, it } from "vitest";
import { armarPendientes, FUENTES_VACIAS, modulosDeLaBandeja } from "../apps/web/lib/admin/bandeja-fuentes";
import { urgenciaSeguroPapeleo, urgenciaSeguroPorVencer, urgenciaSeguroSinPoliza } from "../apps/web/lib/admin/bandeja-urgencia";
import type { FilaSeguro } from "../apps/web/lib/admin/seguros";

const HOY = "2026-10-17";

function fila(o: Partial<FilaSeguro> = {}): FilaSeguro {
  return {
    persona_id: "p1", persona: "Ana Prueba", sede: "TRU", practicante_modalidad: "profesional",
    es_practicante_activo: true, poliza_id: "z1", aseguradora: "Pacífico Seguros", numero_poliza: "24043267",
    vigente_desde: "2026-10-01", vigente_hasta: "2027-06-01", cubre_hoy: true, prima_total: 179.97,
    prima_vence_el: "2026-10-31", plan: null, beneficio_enfermedad: null, beneficio_accidente: null,
    renueva_sola: null, pagada_el: "2026-10-15", firmada_el: "2026-10-15", factura_recibida_el: "2026-10-16",
    nota: null, archivos: 0, creada_at: "2026-10-14T15:00:00Z", ...o,
  };
}
const hueco = (o: Partial<FilaSeguro> = {}): FilaSeguro => fila({
  poliza_id: null, aseguradora: null, numero_poliza: null, vigente_desde: null, vigente_hasta: null,
  cubre_hoy: false, prima_total: null, prima_vence_el: null, pagada_el: null, firmada_el: null,
  factura_recibida_el: null, creada_at: null, ...o,
});

const armar = (seguros: FilaSeguro[]) => armarPendientes({ ...FUENTES_VACIAS, seguros }, { hoy: HOY });

describe("quién entra a la Bandeja por sus seguros", () => {
  it("quien está al día y con todo el papeleo hecho no entra", () => {
    expect(armar([fila()])).toEqual([]);
  });

  it("un practicante sin póliza entra como «Vencido», con su botón y a su persona", () => {
    const [p] = armar([hueco()]);
    expect(p).toMatchObject({
      tipo: "seguro_sin_poliza", clave: "seguro_sin_poliza:p1", modulo: "seguros", personaId: "p1",
      titulo: "Practicante sin póliza de seguro", resolucion: "afuera",
    });
    expect(p.urgencia.grupo).toBe("vencido");
    expect(p.ir).toEqual({ texto: "Registrar póliza", href: "/admin/seguros?persona=p1" });
  });

  it("una póliza que venció ayer también es un hueco, y dice hace cuánto", () => {
    const vencida = fila({ vigente_hasta: "2026-10-16", cubre_hoy: false });
    const [p] = armar([hueco(), vencida]);
    expect(p.titulo).toBe("Su póliza venció y no tiene seguro");
    expect(p.urgencia.plazo).toBe("Dejó de cubrir hace 1 día");
  });

  it("cubierta pero por vencer entra con la fecha en que se queda sin seguro", () => {
    const [p] = armar([fila({ vigente_hasta: "2026-11-20" })]);
    expect(p).toMatchObject({ tipo: "seguro_por_vencer", titulo: "Se queda sin seguro pronto" });
    expect(p.urgencia).toMatchObject({ grupo: "proximo", plazo: "Se queda sin seguro en 34 días", nota: "el 20 de noviembre" });
    expect(p.ir?.texto).toBe("Registrar renovación");
  });

  it("con la renovación ya registrada, por vencer deja de entrar", () => {
    const renov = fila({ poliza_id: "z2", vigente_desde: "2026-11-20", vigente_hasta: "2027-02-20", cubre_hoy: false });
    expect(armar([fila({ vigente_hasta: "2026-11-20" }), renov])).toEqual([]);
  });

  it("el papeleo es UNA fila por póliza, con la prima como lo urgente", () => {
    const filas = armar([fila({ pagada_el: null, firmada_el: null, factura_recibida_el: null })]);
    expect(filas).toHaveLength(1);
    expect(filas[0]).toMatchObject({ tipo: "seguro_papeleo", clave: "seguro_papeleo:z1", titulo: "Prima del seguro sin pagar" });
    expect(filas[0].detalle).toContain("Falta pagar la prima");
    expect(filas[0].detalle).toContain("Falta la factura");
  });

  it("quien dejó de ser practicante y conserva su póliza pide la baja, sin plazo", () => {
    const [p] = armar([fila({ es_practicante_activo: false })]);
    expect(p).toMatchObject({ tipo: "seguro_baja", titulo: "Ya no es practicante y su póliza sigue vigente" });
    expect(p.urgencia.grupo).toBe("sin_plazo");
  });

  it("dos personas con hueco no se pisan: cada una tiene su clave", () => {
    const filas = armar([hueco({ persona_id: "a", persona: "Alba" }), hueco({ persona_id: "b", persona: "Beto" })]);
    expect(new Set(filas.map((p) => p.clave)).size).toBe(2);
  });
});

describe("la urgencia de cada cosa", () => {
  it("quien nunca tuvo póliza va antes que quien la perdió hace una semana, y esa antes que la de ayer", () => {
    const nunca = urgenciaSeguroSinPoliza("nunca", null);
    const semana = urgenciaSeguroSinPoliza("vencida", 7);
    const ayer = urgenciaSeguroSinPoliza("vencida", 1);
    expect([nunca, semana, ayer].every((u) => u.grupo === "vencido")).toBe(true);
    expect(nunca.orden).toBeLessThan(semana.orden);
    expect(semana.orden).toBeLessThan(ayer.orden);
  });

  it("la póliza que ya está registrada pero todavía no empieza sigue siendo «sin seguro hoy»", () => {
    expect(urgenciaSeguroSinPoliza("aun_no_empieza", null)).toMatchObject({ grupo: "vencido", plazo: "Sin seguro hoy" });
  });

  it("por vencer: mañana sigue siendo «próximo» (hoy ya sería un hueco)", () => {
    expect(urgenciaSeguroPorVencer(1, "2026-10-18")).toMatchObject({ grupo: "proximo", plazo: "Se queda sin seguro mañana" });
  });

  it("la prima en mora y la suspendida son «Vencido»; la que vence esta semana, «Próximos»", () => {
    expect(urgenciaSeguroPapeleo({ estado: "en_mora", dias: -3, venceEl: "2026-10-14" }, ["pagada"])).toMatchObject({ grupo: "vencido", plazo: "La prima venció hace 3 días" });
    expect(urgenciaSeguroPapeleo({ estado: "suspendida", dias: -40, venceEl: "2026-09-07" }, ["pagada"])).toMatchObject({ grupo: "vencido", plazo: "Cobertura suspendida" });
    expect(urgenciaSeguroPapeleo({ estado: "por_vencer", dias: 4, venceEl: "2026-10-21" }, ["pagada"])).toMatchObject({ grupo: "proximo", plazo: "La prima vence en 4 días" });
    expect(urgenciaSeguroPapeleo({ estado: "por_vencer", dias: 0, venceEl: HOY }, ["pagada"])).toMatchObject({ grupo: "hoy", plazo: "La prima vence hoy" });
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
});

describe("quién ve el módulo", () => {
  it("solo DO: la líder de equipo y la integrante no lo ven", () => {
    expect(modulosDeLaBandeja("admin")).toContain("seguros");
    expect(modulosDeLaBandeja("lider_do")).toContain("seguros");
    expect(modulosDeLaBandeja("supervisor_sede")).not.toContain("seguros");
    expect(modulosDeLaBandeja("integrante")).not.toContain("seguros");
  });
});
