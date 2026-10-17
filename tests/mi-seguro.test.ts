// ============================================================================
// mi-seguro.test.ts — lo que «Mi seguro» (Lo mío) decide para dibujar (0530)
// ============================================================================
// Cuida lo que, si falla, le miente a alguien sobre su propio seguro:
//   · que «cubierta hasta» cuente las renovaciones que empalman —y las que dejan un hueco,
//     no—, y que el último día de una póliza (EXCLUSIVO) no cuente,
//   · que un seguro SIN póliza (EsSalud) no se lea como «te falta la póliza», ni quien no
//     tiene seguro principal como «te falta algo»,
//   · que la cuenta dé lo MISMO que la del tablero de DO para las mismas pólizas (son dos
//     respuestas a «¿esta persona tiene seguro hoy?» y no pueden diferir),
//   · que un dato sin confirmar (plan, beneficio máximo) NO se pinte,
//   · que el archivo no se rotule ni se nombre con nada que escribió otra persona, y
//   · que el texto fijo no prometa cifras, que solo aparezca para el seguro de quien es y
//     mientras la póliza cubre, y que el enlace de llamar marque el número que dice.
// Quién ve qué lo decide la base (pgTAP, prueba 423); aquí se comprueba que la pantalla lea
// eso sin reinterpretarlo.
// ============================================================================
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { describe, it, expect } from "vitest";
import type { ClienteCayla } from "@cayla-dynamic/database";
import {
  loVeLaPersona, seguroPorPersona, TIPOS_ARCHIVO_SEGURO, TIPOS_DE_ARCHIVO_QUE_VE_LA_PERSONA,
  type FilaEquipoSeguro, type Poliza as PolizaDeDO,
} from "@/lib/admin/seguros";
import {
  GUIAS_DE_USO, archivosDe, datosConfirmados, enlaceTelefono, guiasQueAplican, leerPolizasMias, nombreDeDescarga,
  resolverMiSeguro, rotuloDeArchivo, traerMiSeguro,
  type ArchivoMio, type PolizaMia, type SeguroPrincipal,
} from "@/lib/mi-seguro";

const HOY = "2026-10-17";

const FOLA: SeguroPrincipal = { tipo: "salud_practicantes", tipo_nombre: "FOLA", con_poliza: true, cubre_hoy: true };
const FOLA_SIN_COBERTURA: SeguroPrincipal = { ...FOLA, cubre_hoy: false };
const ESSALUD: SeguroPrincipal = { tipo: "essalud", tipo_nombre: "EsSalud", con_poliza: false, cubre_hoy: null };
const NINGUNO: SeguroPrincipal = { tipo: null, tipo_nombre: null, con_poliza: false, cubre_hoy: null };

/** Una póliza FOLA de 92 días que empieza el 1 de octubre, como la de hoy. `cubre_hoy` sale de las fechas, como en la base. */
function poliza(o: Partial<PolizaMia> = {}, hoy = HOY): PolizaMia {
  const desde = o.vigente_desde ?? "2026-10-01";
  const hasta = o.vigente_hasta ?? "2027-01-01";
  return {
    poliza_id: "z1", producto: "salud_practicantes", producto_nombre: "FOLA", aseguradora: "Pacífico Seguros",
    numero_poliza: "24043267", vigente_desde: desde, vigente_hasta: hasta,
    cubre_hoy: hoy >= desde && hoy < hasta,
    plan: null, beneficio_enfermedad: null, beneficio_accidente: null, archivos: [], ...o,
  };
}

function archivo(o: Partial<ArchivoMio> = {}): ArchivoMio {
  return { id: "a1", tipo: "poliza", storage_path: "5b000000-0000-0000-0000-0000000000a1.pdf", mime: "application/pdf", bytes: 1779531, ...o };
}

describe("leer los archivos que manda la base", () => {
  it("lee los dos tipos que la persona ve, en el orden en que llegan", () => {
    const r = archivosDe([
      { id: "a1", tipo: "poliza", storage_path: "x.pdf", mime: "application/pdf", bytes: 10 },
      { id: "a2", tipo: "convenio_pago", storage_path: "y.pdf", mime: "application/pdf", bytes: 20 },
    ]);
    expect(r.map((a) => a.tipo)).toEqual(["poliza", "convenio_pago"]);
    expect(r[1]).toEqual({ id: "a2", tipo: "convenio_pago", storage_path: "y.pdf", mime: "application/pdf", bytes: 20 });
  });

  it("descarta lo que no tiene la forma esperada en vez de reventar", () => {
    const r = archivosDe([
      null, "texto", 7, [],
      { id: "a1", tipo: "factura", storage_path: "x.pdf" },        // un tipo que no es suyo
      { id: "a2", tipo: "poliza" },                                 // sin ruta
      { tipo: "poliza", storage_path: "z.pdf" },                    // sin id
      { id: "a3", tipo: "poliza", storage_path: "ok.pdf" },         // este sí
    ]);
    expect(r.map((a) => a.id)).toEqual(["a3"]);
  });

  it("completa lo que falta con valores seguros, y todo lo que no sea un arreglo es vacío", () => {
    expect(archivosDe([{ id: "a3", tipo: "poliza", storage_path: "ok.pdf" }])[0]).toMatchObject({ mime: "application/pdf", bytes: 0 });
    expect(archivosDe(null)).toEqual([]);
    expect(archivosDe({ id: "a1" })).toEqual([]);
    expect(archivosDe(undefined)).toEqual([]);
  });

  it("una fila de la base se convierte en una póliza con sus archivos tipados", () => {
    const [p] = leerPolizasMias([{ ...poliza(), archivos: [{ id: "a1", tipo: "poliza", storage_path: "x.pdf", mime: "application/pdf", bytes: 5 }] }]);
    expect(p.archivos).toHaveLength(1);
    expect(p.numero_poliza).toBe("24043267");
  });
});

describe("pedir fn_mi_seguro y fn_mis_polizas", () => {
  type Respuesta = { data: unknown; error: unknown };
  const cliente = (porFuncion: Record<string, Respuesta>) =>
    ({ rpc: async (nombre: string) => porFuncion[nombre] ?? { data: null, error: { message: `no hay ${nombre}` } } }) as unknown as ClienteCayla;

  it("devuelve su seguro principal y sus pólizas leídas", async () => {
    const r = await traerMiSeguro(cliente({
      fn_mi_seguro: { data: [FOLA], error: null },
      fn_mis_polizas: { data: [{ ...poliza(), archivos: [] }], error: null },
    }));
    expect(r.error).toBeNull();
    expect(r.principal).toEqual(FOLA);
    expect(r.polizas.map((p) => p.numero_poliza)).toEqual(["24043267"]);
  });

  it("sin filas, vacío y sin error: no tener nada que ver no es una falla", async () => {
    const r = await traerMiSeguro(cliente({ fn_mi_seguro: { data: [], error: null }, fn_mis_polizas: { data: null, error: null } }));
    expect(r).toEqual({ principal: null, polizas: [], error: null });
  });

  it("si CUALQUIERA de las dos falla, un texto para leerse y nada inventado: ni «sin seguro» ni lanzar", async () => {
    const malo = { message: "boom", code: "42883" };
    for (const respuestas of [
      { fn_mi_seguro: { data: null, error: malo }, fn_mis_polizas: { data: [], error: null } },
      { fn_mi_seguro: { data: [FOLA], error: null }, fn_mis_polizas: { data: null, error: malo } },
    ]) {
      const r = await traerMiSeguro(cliente(respuestas));
      expect(r.principal).toBeNull();
      expect(r.polizas).toEqual([]);
      expect(r.error).toMatch(/No pudimos leer tu seguro/);
      expect(r.error).not.toMatch(/boom|42883/);
    }
  });
});

describe("cómo está su seguro hoy", () => {
  it("una póliza FOLA a 76 días de vencer: al día, con hasta cuándo", () => {
    const r = resolverMiSeguro(FOLA, [poliza()], HOY);
    expect(r.situacion).toBe("al_dia");
    expect(r.tipo).toEqual({ clave: "salud_practicantes", nombre: "FOLA" });
    expect(r.conPoliza).toBe(true);
    expect(r.cubiertoHasta).toBe("2027-01-01");
    expect(r.diasParaQuedarSinSeguro).toBe(76);
    expect(r.actual?.poliza_id).toBe("z1");
    expect(r.resto).toEqual([]);
  });

  it("EsSalud no lleva póliza: va por planilla, y nunca se lee como «te falta la póliza»", () => {
    const r = resolverMiSeguro(ESSALUD, [], HOY);
    expect(r.situacion).toBe("por_planilla");
    expect(r.tipo).toEqual({ clave: "essalud", nombre: "EsSalud" });
    expect(r.conPoliza).toBe(false);
    expect(r.actual).toBeNull();
    expect(r.motivoHueco).toBeNull();
    expect(r.cubiertoHasta).toBeNull();
  });

  it("quien no tiene seguro principal (honorarios, sin vínculo laboral) no tiene un hueco: no le toca uno", () => {
    for (const sinSeguro of [NINGUNO, null]) {
      const r = resolverMiSeguro(sinSeguro, [], HOY);
      expect(r.situacion).toBe("sin_seguro");
      expect(r.tipo).toBeNull();
      expect(r.motivoHueco).toBeNull();
    }
  });

  it("un seguro que lleva póliza y no tiene ninguna registrada es un hueco «nunca»", () => {
    const r = resolverMiSeguro(FOLA_SIN_COBERTURA, [], HOY);
    expect(r.situacion).toBe("hueco");
    expect(r.motivoHueco).toBe("nunca");
    expect(r.actual).toBeNull();
    expect(r.empiezaEl).toBeNull();
  });

  it("se avisa a los 45 días y no a los 46", () => {
    // hasta = HOY + 45 → por vencer; HOY + 46 → al día.
    expect(resolverMiSeguro(FOLA, [poliza({ vigente_hasta: "2026-12-01" })], HOY).situacion).toBe("por_vencer");   // 45 días
    expect(resolverMiSeguro(FOLA, [poliza({ vigente_hasta: "2026-12-02" })], HOY).situacion).toBe("al_dia");        // 46 días
    expect(resolverMiSeguro(FOLA, [poliza({ vigente_hasta: "2026-12-01" })], HOY).diasParaQuedarSinSeguro).toBe(45);
  });

  it("una renovación que empalma no la deja «por vencer» ni sin seguro: cuenta hasta donde llega la cadena", () => {
    const vieja = poliza({ poliza_id: "z1", vigente_desde: "2026-10-01", vigente_hasta: "2026-11-01" });
    const nueva = poliza({ poliza_id: "z2", numero_poliza: "24043277", vigente_desde: "2026-11-01", vigente_hasta: "2027-02-01" });
    const r = resolverMiSeguro(FOLA, [vieja, nueva], HOY);
    expect(r.situacion).toBe("al_dia");
    expect(r.cubiertoHasta).toBe("2027-02-01");
    expect(r.diasParaQuedarSinSeguro).toBe(107);
    expect(r.actual?.poliza_id).toBe("z1");                       // la que cubre hoy
    expect(r.resto.map((p) => p.poliza_id)).toEqual(["z2"]);
  });

  it("una renovación que empieza DESPUÉS de un hueco no empalma: se queda «por vencer»", () => {
    const vieja = poliza({ poliza_id: "z1", vigente_desde: "2026-10-01", vigente_hasta: "2026-11-01" });
    const nueva = poliza({ poliza_id: "z2", vigente_desde: "2026-11-05", vigente_hasta: "2027-02-05" });
    const r = resolverMiSeguro(FOLA, [vieja, nueva], HOY);
    expect(r.situacion).toBe("por_vencer");
    expect(r.cubiertoHasta).toBe("2026-11-01");
  });

  it("el día en que termina la póliza ya NO cubre (vence a las 12 M), y la renovación de ese mismo día sí", () => {
    const hoy = "2027-01-01";
    const vieja = poliza({ poliza_id: "z1", vigente_desde: "2026-10-01", vigente_hasta: "2027-01-01" }, hoy);
    // Sola, ese día no tiene póliza que la cubra: terminó hoy, hace 0 días.
    const sola = resolverMiSeguro(FOLA_SIN_COBERTURA, [vieja], hoy);
    expect(sola.situacion).toBe("hueco");
    expect(sola.motivoHueco).toBe("vencida");
    expect(sola.diasDesdeQueVencio).toBe(0);
    expect(sola.vencioEl).toBe("2027-01-01");
    // Con la renovación que empieza hoy, está cubierta.
    const nueva = poliza({ poliza_id: "z2", vigente_desde: "2027-01-01", vigente_hasta: "2027-04-01" }, hoy);
    const con = resolverMiSeguro(FOLA, [vieja, nueva], hoy);
    expect(con.situacion).toBe("al_dia");
    expect(con.actual?.poliza_id).toBe("z2");
    expect(con.cubiertoHasta).toBe("2027-04-01");
  });

  it("vencida: dice cuándo terminó y hace cuántos días, y que no hay otra que empiece", () => {
    const r = resolverMiSeguro(FOLA_SIN_COBERTURA, [poliza({ vigente_hasta: "2026-10-08", vigente_desde: "2026-07-08" })], HOY);
    expect(r.situacion).toBe("hueco");
    expect(r.motivoHueco).toBe("vencida");
    expect(r.diasDesdeQueVencio).toBe(9);
    expect(r.vencioEl).toBe("2026-10-08");
    expect(r.empiezaEl).toBeNull();
    expect(r.cubiertoHasta).toBeNull();
    expect(r.actual?.poliza_id).toBe("z1");
  });

  it("vencida, y con otra ya registrada que empieza pronto: lo dice con las dos fechas", () => {
    const vieja = poliza({ poliza_id: "z1", vigente_desde: "2026-06-01", vigente_hasta: "2026-10-10" });
    const proxima = poliza({ poliza_id: "z2", vigente_desde: "2026-10-24", vigente_hasta: "2027-01-24" });
    const r = resolverMiSeguro(FOLA_SIN_COBERTURA, [vieja, proxima], HOY);
    expect(r.motivoHueco).toBe("vencida");
    expect(r.vencioEl).toBe("2026-10-10");
    expect(r.empiezaEl).toBe("2026-10-24");
    expect(r.actual?.poliza_id).toBe("z2");                      // la que viene habla por su seguro
  });

  it("aún no empieza: lo dice con la fecha en que empieza, y esa es la que habla por ella", () => {
    const r = resolverMiSeguro(FOLA_SIN_COBERTURA, [poliza({ vigente_desde: "2026-10-20", vigente_hasta: "2027-01-20" })], HOY);
    expect(r.situacion).toBe("hueco");
    expect(r.motivoHueco).toBe("aun_no_empieza");
    expect(r.empiezaEl).toBe("2026-10-20");
    expect(r.vencioEl).toBeNull();
    expect(r.actual?.vigente_desde).toBe("2026-10-20");
  });

  it("LA PUERTA ES «ES MI PÓLIZA»: quien ya está en EsSalud conserva su póliza FOLA, como otra", () => {
    const r = resolverMiSeguro(ESSALUD, [poliza()], HOY);
    expect(r.situacion).toBe("por_planilla");
    expect(r.actual).toBeNull();
    expect(r.principales).toEqual([]);
    expect(r.otras.map((p) => p.numero_poliza)).toEqual(["24043267"]);
    expect(r.resto.map((p) => p.numero_poliza)).toEqual(["24043267"]);
  });

  it("la póliza de OTRO seguro no cubre el principal: la base lo dice, y esa va como «otra»", () => {
    const vida = poliza({ poliza_id: "v1", producto: "vida_ley", producto_nombre: "Vida Ley", numero_poliza: "VL-0002" });
    const r = resolverMiSeguro(FOLA_SIN_COBERTURA, [vida], HOY);
    expect(r.situacion).toBe("hueco");
    expect(r.motivoHueco).toBe("nunca");
    expect(r.principales).toEqual([]);
    expect(r.otras.map((p) => p.numero_poliza)).toEqual(["VL-0002"]);
    expect(r.resto.map((p) => p.numero_poliza)).toEqual(["VL-0002"]);
  });

  it("el orden de las filas no cambia la respuesta", () => {
    const a = poliza({ poliza_id: "z1", vigente_desde: "2026-07-01", vigente_hasta: "2026-10-01" });
    const b = poliza({ poliza_id: "z2", vigente_desde: "2026-10-01", vigente_hasta: "2027-01-01" });
    const c = poliza({ poliza_id: "z3", vigente_desde: "2027-01-01", vigente_hasta: "2027-04-01" });
    const uno = resolverMiSeguro(FOLA, [a, b, c], HOY);
    const otro = resolverMiSeguro(FOLA, [c, a, b], HOY);
    expect(otro).toEqual(uno);
    expect(uno.resto.map((p) => p.poliza_id)).toEqual(["z3", "z1"]);    // la más reciente primero, sin la actual
  });
});

// ── Las dos cuentas tienen que dar lo mismo ─────────────────────────────────
// `seguroPorPersona` es la del tablero de DO; `resolverMiSeguro` es la de la persona. Para las
// mismas pólizas y el mismo seguro, dicen lo mismo de la cobertura. Si alguien toca una y no la
// otra, la persona y DO leerían respuestas distintas.
describe("la cuenta de la persona coincide con la del tablero de DO", () => {
  function comoEquipoDeDO(principal: SeguroPrincipal | null, polizas: readonly PolizaMia[]): FilaEquipoSeguro {
    const tipo = principal?.tipo ?? null;
    const cubre = tipo && principal?.con_poliza ? polizas.some((z) => z.producto === tipo && z.cubre_hoy) : null;
    return {
      persona_id: "p1", persona: "Ana Prueba", sede: "TRU", tipo_vinculo: "practicante", practicante_modalidad: null, activa: true,
      tipo, tipo_nombre: principal?.tipo_nombre ?? null, origen: tipo ? "vinculo" : null,
      asignacion_id: null, asignacion_desde: null, asignacion_motivo: null, tipo_automatico: tipo, tipo_automatico_nombre: principal?.tipo_nombre ?? null,
      con_poliza: principal?.con_poliza ?? false, cubre_hoy: cubre,
      // La regla de quién tiene un hueco, tal como la escribe `fn_seguros_equipo` (0528).
      hueco: Boolean(tipo && principal?.con_poliza && !cubre),
    };
  }
  const comoPolizaDeDO = (z: PolizaMia): PolizaDeDO => ({
    persona_id: "p1", persona: "Ana Prueba", sede: "TRU", persona_activa: true,
    producto: z.producto, producto_nombre: z.producto_nombre, producto_principal: z.producto !== "vida_ley",
    poliza_id: z.poliza_id, aseguradora: z.aseguradora, numero_poliza: z.numero_poliza,
    vigente_desde: z.vigente_desde, vigente_hasta: z.vigente_hasta, cubre_hoy: z.cubre_hoy,
    prima_total: 179.97, prima_vence_el: null, plan: z.plan, beneficio_enfermedad: z.beneficio_enfermedad,
    beneficio_accidente: z.beneficio_accidente, renueva_sola: null, pagada_el: null, firmada_el: null,
    factura_recibida_el: null, nota: null, archivos: 0, creada_at: "2026-10-14T15:00:00Z",
  });

  /** El principal tal como lo diría la base: si lleva póliza, `cubre_hoy` sale de las pólizas de ese tipo. */
  const principalCon = (base: SeguroPrincipal, polizas: readonly PolizaMia[]): SeguroPrincipal =>
    base.con_poliza ? { ...base, cubre_hoy: polizas.some((z) => z.producto === base.tipo && z.cubre_hoy) } : base;

  const ESCENARIOS: Array<[string, string, SeguroPrincipal, Array<Partial<PolizaMia>>]> = [
    ["una póliza lejos de vencer", "2026-10-17", FOLA, [{ poliza_id: "z1", vigente_desde: "2026-10-01", vigente_hasta: "2027-01-01" }]],
    ["a 45 días de vencer", "2026-10-17", FOLA, [{ poliza_id: "z1", vigente_desde: "2026-08-01", vigente_hasta: "2026-12-01" }]],
    ["a 46 días de vencer", "2026-10-17", FOLA, [{ poliza_id: "z1", vigente_desde: "2026-08-01", vigente_hasta: "2026-12-02" }]],
    ["vence mañana", "2026-10-17", FOLA, [{ poliza_id: "z1", vigente_desde: "2026-07-18", vigente_hasta: "2026-10-18" }]],
    ["terminó hoy", "2026-10-17", FOLA, [{ poliza_id: "z1", vigente_desde: "2026-07-17", vigente_hasta: "2026-10-17" }]],
    ["terminó hace 9 días", "2026-10-17", FOLA, [{ poliza_id: "z1", vigente_desde: "2026-07-08", vigente_hasta: "2026-10-08" }]],
    ["empieza en 3 días", "2026-10-17", FOLA, [{ poliza_id: "z1", vigente_desde: "2026-10-20", vigente_hasta: "2027-01-20" }]],
    ["nunca tuvo póliza", "2026-10-17", FOLA, []],
    ["renovación que empalma", "2026-10-17", FOLA, [
      { poliza_id: "z1", vigente_desde: "2026-07-01", vigente_hasta: "2026-11-01" },
      { poliza_id: "z2", vigente_desde: "2026-11-01", vigente_hasta: "2027-02-01" }]],
    ["renovación con un hueco de 4 días", "2026-10-17", FOLA, [
      { poliza_id: "z1", vigente_desde: "2026-07-01", vigente_hasta: "2026-11-01" },
      { poliza_id: "z2", vigente_desde: "2026-11-05", vigente_hasta: "2027-02-05" }]],
    ["la vencida y la que empieza en una semana", "2026-10-17", FOLA, [
      { poliza_id: "z1", vigente_desde: "2026-06-01", vigente_hasta: "2026-10-10" },
      { poliza_id: "z2", vigente_desde: "2026-10-24", vigente_hasta: "2027-01-24" }]],
    ["la renovación empieza hoy", "2027-01-01", FOLA, [
      { poliza_id: "z1", vigente_desde: "2026-10-01", vigente_hasta: "2027-01-01" },
      { poliza_id: "z2", vigente_desde: "2027-01-01", vigente_hasta: "2027-04-01" }]],
    ["tres pólizas encadenadas", "2026-12-20", FOLA, [
      { poliza_id: "z1", vigente_desde: "2026-10-01", vigente_hasta: "2027-01-01" },
      { poliza_id: "z2", vigente_desde: "2027-01-01", vigente_hasta: "2027-04-01" },
      { poliza_id: "z3", vigente_desde: "2027-04-01", vigente_hasta: "2027-07-01" }]],
    ["EsSalud, que no lleva póliza", "2026-10-17", ESSALUD, []],
    ["en EsSalud y con una póliza FOLA que le quedó", "2026-10-17", ESSALUD, [{ poliza_id: "z1", vigente_desde: "2026-10-01", vigente_hasta: "2027-01-01" }]],
    ["sin seguro principal", "2026-10-17", NINGUNO, []],
    ["FOLA sin póliza FOLA pero con una de otro seguro que cubre", "2026-10-17", FOLA, [
      { poliza_id: "v1", producto: "vida_ley", producto_nombre: "Vida Ley", vigente_desde: "2026-09-01", vigente_hasta: "2027-03-01" }]],
  ];

  for (const [nombre, hoy, base, partes] of ESCENARIOS) {
    it(nombre, () => {
      const polizas = partes.map((o) => poliza({ ...o, cubre_hoy: hoy >= (o.vigente_desde ?? "") && hoy < (o.vigente_hasta ?? "") }, hoy));
      const principal = principalCon(base, polizas);
      const mia = resolverMiSeguro(principal, polizas, hoy);
      const [deDo] = seguroPorPersona([comoEquipoDeDO(principal, polizas)], polizas.map(comoPolizaDeDO), [], hoy);

      expect(deDo, "el tablero tiene que devolver a la persona").toBeDefined();
      expect(mia.situacion).toBe(deDo.situacion);
      expect(mia.cubiertoHasta).toBe(deDo.cubiertoHasta);
      expect(mia.diasParaQuedarSinSeguro).toBe(deDo.diasParaQuedarSinSeguro);
      expect(mia.diasDesdeQueVencio).toBe(deDo.diasDesdeQueVencio);
      expect(mia.empiezaEl).toBe(deDo.empiezaEl);
      expect(mia.motivoHueco).toBe(deDo.motivoHueco);
      expect(mia.actual?.poliza_id).toBe(deDo.actual?.poliza_id);
      expect(mia.principales.map((z) => z.poliza_id)).toEqual(deDo.polizasPrincipales.map((z) => z.poliza_id));
      expect(mia.otras.map((z) => z.poliza_id)).toEqual(deDo.otras.map((z) => z.poliza_id));
    });
  }
});

describe("lo que ya está confirmado, y solo eso", () => {
  const soles = (n: number) => `S/ ${n}`;

  it("mientras el corredor no confirme nada, no sale ni una línea (ni un «pendiente»)", () => {
    expect(datosConfirmados({ plan: null, beneficio_enfermedad: null, beneficio_accidente: null }, soles)).toEqual([]);
  });

  it("un plan en blanco cuenta como sin confirmar", () => {
    expect(datosConfirmados({ plan: "   ", beneficio_enfermedad: null, beneficio_accidente: null }, soles)).toEqual([]);
    expect(datosConfirmados({ plan: "", beneficio_enfermedad: null, beneficio_accidente: null }, soles)).toEqual([]);
  });

  it("sale cada dato confirmado, con su etiqueta, y solo ese", () => {
    expect(datosConfirmados({ plan: " Plan 1 ", beneficio_enfermedad: null, beneficio_accidente: 36000 }, soles)).toEqual([
      { etiqueta: "Plan", valor: "Plan 1" },
      { etiqueta: "Máximo anual por accidente", valor: "S/ 36000" },
    ]);
    expect(datosConfirmados({ plan: "Plan 1", beneficio_enfermedad: 16800, beneficio_accidente: 36000 }, soles).map((d) => d.etiqueta))
      .toEqual(["Plan", "Máximo anual por enfermedad", "Máximo anual por accidente"]);
  });

  it("un beneficio de 0 se muestra: es un dato confirmado, no «sin confirmar» (la base no admite 0, pero la pantalla no lo adivina)", () => {
    expect(datosConfirmados({ plan: null, beneficio_enfermedad: 0, beneficio_accidente: null }, soles)).toHaveLength(1);
  });
});

describe("cómo se rotula y se nombra un archivo", () => {
  const fola = { numero_poliza: "24043267", producto_nombre: "FOLA" };

  it("por su tipo, nunca por el nombre que le puso DO", () => {
    expect(rotuloDeArchivo(archivo({ tipo: "poliza" }), [archivo()])).toBe("Tu póliza");
    expect(rotuloDeArchivo(archivo({ id: "a2", tipo: "convenio_pago" }), [archivo(), archivo({ id: "a2", tipo: "convenio_pago" })]))
      .toBe("Convenio de pago");
  });

  it("si hay dos del mismo tipo se numeran, en el orden en que llegan", () => {
    const dos = [archivo({ id: "a1" }), archivo({ id: "a2" })];
    expect(rotuloDeArchivo(dos[0], dos)).toBe("Tu póliza (1)");
    expect(rotuloDeArchivo(dos[1], dos)).toBe("Tu póliza (2)");
  });

  it("el archivo que se baja se llama por su seguro y su póliza, con la extensión de lo que es", () => {
    expect(nombreDeDescarga(archivo(), fola)).toBe("Poliza-FOLA-24043267.pdf");
    expect(nombreDeDescarga(archivo({ tipo: "convenio_pago" }), fola)).toBe("Convenio-de-pago-FOLA-24043267.pdf");
    expect(nombreDeDescarga(archivo({ mime: "image/jpeg", storage_path: "x.jpg" }), fola)).toBe("Poliza-FOLA-24043267.jpg");
    expect(nombreDeDescarga(archivo({ mime: "image/heic" }), fola)).toBe("Poliza-FOLA-24043267.heic");
  });

  it("el nombre del seguro entra limpio, sin tildes ni espacios, y no se llama «FOLA» si no lo es", () => {
    expect(nombreDeDescarga(archivo(), { numero_poliza: "VL-0001", producto_nombre: "Vida Ley" })).toBe("Poliza-Vida-Ley-VL-0001.pdf");
    expect(nombreDeDescarga(archivo(), { numero_poliza: "123", producto_nombre: "Póliza Médica ñandú" })).toBe("Poliza-Poliza-Medica-nandu-123.pdf");
    expect(nombreDeDescarga(archivo(), { numero_poliza: "123", producto_nombre: "???" })).toBe("Poliza-Seguro-123.pdf");
  });

  it("un mime raro cae a la extensión de la ruta, y el número tecleado a mano se limpia", () => {
    expect(nombreDeDescarga(archivo({ mime: "application/x-raro", storage_path: "abc.pdf" }), fola)).toBe("Poliza-FOLA-24043267.pdf");
    expect(nombreDeDescarga(archivo(), { ...fola, numero_poliza: " 24/043 267 " })).toBe("Poliza-FOLA-24-043-267.pdf");
    expect(nombreDeDescarga(archivo(), { ...fola, numero_poliza: "///" })).toBe("Poliza-FOLA-sin-numero.pdf");
  });

  it("nada en el nombre se parece a una persona: solo el seguro y el número de póliza", () => {
    const n = nombreDeDescarga(archivo({ storage_path: "5b000000-0000-0000-0000-0000000000a1.pdf" }), fola);
    expect(n).toMatch(/^[A-Za-z0-9-]+\.[a-z0-9]+$/);
  });
});

describe("el texto fijo de «cómo usar»", () => {
  const guia = GUIAS_DE_USO.salud_practicantes;
  const todoElTexto = [...guia.pasos.flatMap((p) => [p.titulo, p.texto]), ...guia.noCubre].join(" ");

  it("hay guía para FOLA, que es lo único de lo que se tiene el resumen a mano", () => {
    expect(Object.keys(GUIAS_DE_USO)).toEqual(["salud_practicantes"]);
    expect(guia.aseguradora).toBe("Pacífico");
  });

  it("lleva lo que el resumen de la póliza dice, y lo dice con las cifras del resumen", () => {
    expect(todoElTexto).toMatch(/DNI/);
    expect(todoElTexto).toMatch(/carta de garantía/i);
    expect(todoElTexto).toMatch(/3 días útiles/);
    expect(todoElTexto).toMatch(/Pacífico Asiste/);
    expect(todoElTexto).toMatch(/90 días/);
    expect(todoElTexto).toMatch(/originales/);
    expect(guia.telefonos).toEqual(["(01) 415-1515", "(01) 513-5000"]);
  });

  it("dice lo que NO cubre: gestación, odontología salvo accidente, salud mental y preexistencias", () => {
    const x = guia.noCubre.join(" | ");
    expect(x).toMatch(/Gestación/);
    expect(x).toMatch(/Odontología, salvo por accidente/);
    expect(x).toMatch(/Salud mental/);
    expect(x).toMatch(/Preexistencias/);
    expect(guia.noCubre).toHaveLength(4);
  });

  it("no promete cifras: ni soles, ni «subvenciones», ni más números que los dos plazos del resumen", () => {
    expect(todoElTexto).not.toMatch(/S\/|soles|subvenci/i);
    const numeros = (todoElTexto.match(/\d+/g) ?? []).sort();
    expect(numeros).toEqual(["3", "90"]);
  });

  it("habla como el resto del sistema: nada de «empleado», «sucursal», «RRHH» ni «cliente»", () => {
    expect(todoElTexto).not.toMatch(/empleado|sucursal|rrhh|\bjefe\b|supervisor|cliente/i);
  });

  it("cada paso tiene su clave, su título y su texto, y las claves no se repiten", () => {
    expect(new Set(guia.pasos.map((p) => p.clave)).size).toBe(guia.pasos.length);
    for (const p of guia.pasos) {
      expect(p.titulo.trim()).not.toBe("");
      expect(p.texto.trim()).not.toBe("");
    }
  });

  describe("a quién le sirve", () => {
    const vida = poliza({ poliza_id: "v1", producto: "vida_ley", producto_nombre: "Vida Ley", numero_poliza: "VL-0001" });

    it("a quien tiene una póliza FOLA que cubre hoy", () => {
      expect(guiasQueAplican([poliza()]).map((g) => g.clave)).toEqual(["salud_practicantes"]);
      expect(guiasQueAplican([poliza()])[0].nombre).toBe("FOLA");
    });

    it("no si la póliza ya venció o todavía no empieza: no se explica cómo usar lo que no cubre", () => {
      expect(guiasQueAplican([poliza({ vigente_desde: "2026-07-08", vigente_hasta: "2026-10-08" })])).toEqual([]);
      expect(guiasQueAplican([poliza({ vigente_desde: "2026-10-20", vigente_hasta: "2027-01-20" })])).toEqual([]);
    });

    it("tampoco a quien está en EsSalud y no tiene ninguna póliza: no hay nada que explicar, y no se inventa", () => {
      expect(guiasQueAplican([])).toEqual([]);
    });

    it("ni por un seguro del que no hay guía (Vida Ley, o uno que DO agregue)", () => {
      expect(guiasQueAplican([vida])).toEqual([]);
    });

    it("sí a quien ya está en EsSalud pero su póliza FOLA sigue cubriendo: todavía puede necesitarla", () => {
      expect(guiasQueAplican([poliza(), vida]).map((g) => g.clave)).toEqual(["salud_practicantes"]);
    });

    it("una sola guía por seguro, aunque tenga dos pólizas que cubren", () => {
      const dos = [poliza({ poliza_id: "z1" }), poliza({ poliza_id: "z2", numero_poliza: "24043277" })];
      expect(guiasQueAplican(dos)).toHaveLength(1);
    });
  });
});

describe("qué archivos de una póliza ve también la persona", () => {
  it("de los cuatro tipos, la póliza y el convenio de pago sí; la factura y «otro», no", () => {
    expect(TIPOS_ARCHIVO_SEGURO.map((t) => `${t.valor}:${loVeLaPersona(t.valor)}`)).toEqual([
      "poliza:true", "convenio_pago:true", "factura:false", "otro:false",
    ]);
    expect(loVeLaPersona("algo-nuevo")).toBe(false);
  });

  const carpeta = path.resolve(import.meta.dirname, "../supabase/migrations");
  const archivo0530 = () => readdirSync(carpeta).find((f) => f.startsWith("0530_"));
  const sqlSinComentarios = () =>
    readFileSync(path.join(carpeta, archivo0530()!), "utf8").split("\n").filter((l) => !l.trimStart().startsWith("--")).join("\n");

  // La lista vive en TRES sitios que no se pueden comparar en el compilador: las dos funciones de
  // la 0530 (SQL) y esta pantalla de DO (TypeScript). Si una cambia sola, DO leería «la persona lo
  // ve» sobre un archivo que la base no le da, o al revés.
  it("la lista de TypeScript es la misma que la 0530 escribe en sus dos funciones", () => {
    expect(archivo0530(), "la 0530 tiene que existir").toBeDefined();
    const sql = readFileSync(path.join(carpeta, archivo0530()!), "utf8");
    const listas = [...sql.matchAll(/a\.tipo in \(([^)]*)\)/g)].map((m) =>
      m[1].split(",").map((x) => x.trim().replace(/'/g, "")).sort());
    // Una en `fn_seguro_archivo_es_mio` (la política de Storage) y otra en `fn_mis_polizas`.
    expect(listas).toHaveLength(2);
    for (const l of listas) expect(l).toEqual([...TIPOS_DE_ARCHIVO_QUE_VE_LA_PERSONA].sort());
  });

  // La regla central de esta etapa, escrita como prueba: la puerta es «es MI póliza». Si alguien
  // vuelve a pedir un vínculo (practicante, planilla…), quien cambie de seguro pierde su póliza.
  it("la 0530 no mira el vínculo de nadie: la puerta es «es mi póliza»", () => {
    expect(sqlSinComentarios()).not.toMatch(/tipo_vinculo/);
    expect(sqlSinComentarios()).not.toMatch(/practicante/i);
  });

  it("la 0530 no devuelve nada interno: ni descripción del seguro, ni prima, ni notas, ni historial", () => {
    const sql = sqlSinComentarios();
    for (const interno of ["descripcion", "prima_total", "prima_vence_el", "pagada_el", "firmada_el", "factura_recibida_el",
      "nota", "creada_por", "renueva_sola", "nombre_archivo", "polizas_seguro_eventos", "seguros_asignaciones", "seguros_cambios"]) {
      expect(sql, interno).not.toMatch(new RegExp(`\\b${interno}\\b`));
    }
  });
});

describe("el enlace para llamar", () => {
  it("marca el número que dice: Lima es +51 1", () => {
    expect(enlaceTelefono("(01) 415-1515")).toBe("tel:+5114151515");
    expect(enlaceTelefono("(01) 513-5000")).toBe("tel:+5115135000");
  });

  it("los dos teléfonos del texto producen un enlace de 7 cifras después del código de Lima", () => {
    for (const t of GUIAS_DE_USO.salud_practicantes.telefonos) expect(enlaceTelefono(t)).toMatch(/^tel:\+511\d{7}$/);
  });
});
