// ============================================================================
// importar-polizas.test.ts — de lo que dice el papel a pólizas listas para registrar (0528)
// ============================================================================
// Lo que se cuida:
//   · que NADA nazca seleccionado sin que el papel traiga número, vigencia y prima, sin una persona
//     clara, con un solo aviso del lector pendiente, o con un documento que no es el de la ficha de esa
//     persona: lo leído es una propuesta, no un registro;
//   · que el nombre PROPONGA y el documento COMPRUEBE: otro documento bloquea la tarjeta, y la falta de
//     documento (en el papel, en la ficha o porque no se pudo consultar) la deja sin marcar pero no la bloquea;
//   · que un campo de fecha nunca nazca en blanco (CLAUDE.md, regla del 2026-08-26), aunque el papel
//     no la traiga;
//   · que los rechazos de la base se vean en la tarjeta ANTES de registrar: la persona no está en ese
//     seguro, la póliza se cruza con otra, o con otra del mismo lote;
//   · que volver a leer un PDF que ya se registró no lo duplique.
// ============================================================================
import { describe, it, expect } from "vitest";
import type { PolizaLeida } from "@/lib/admin/leer-poliza";
import {
  cotejarDocumento, cotejoDeTarjeta, erroresDeTarjeta, productoSugerido, tarjetaDeLectura, yaRegistrada,
  type ContextoDeTarjeta, type FichaDeDocumento, type PersonaParaEmparejar,
} from "@/lib/admin/importar-polizas";

const HOY = "2026-10-17";

const ana: PersonaParaEmparejar = { id: "a", nombre: "Ana María Pérez Gómez", tipoPrincipal: "salud_practicantes" };
const beto: PersonaParaEmparejar = { id: "b", nombre: "Beto Luis Ramos Díaz", tipoPrincipal: "salud_practicantes" };
const carla: PersonaParaEmparejar = { id: "c", nombre: "Carla Soto Ruiz", tipoPrincipal: "essalud" };
const PERSONAS = [ana, beto, carla];

const TIPOS = [
  { clave: "salud_practicantes", nombre: "FOLA", principal: true, con_poliza: true, activo: true },
  { clave: "essalud", nombre: "EsSalud", principal: true, con_poliza: false, activo: true },
  { clave: "vida_ley", nombre: "Vida Ley", principal: false, con_poliza: true, activo: true },
];

/** Lo que `leerPolizas` entendió de una póliza completa. */
function leida(o: Partial<PolizaLeida> = {}): PolizaLeida {
  return {
    numero: "99000001", desde: "2026-11-01", hasta: "2027-02-01", prima: 179.97, primaVenceEl: "2026-11-30",
    aseguradora: "Pacífico Seguros", producto: "Seguro de salud practicantes",
    asegurado: { nombre: "PEREZ GOMEZ ANA MARIA", documento: "900000001" }, emitidaEl: "2026-10-14", avisos: [],
    ...o,
  };
}

/** El documento que cada ficha tiene: el de Ana es el que trae `leida()`. */
const FICHAS = new Map<string, FichaDeDocumento>([
  ["a", { documento: "900000001" }], ["b", { documento: "900000002" }], ["c", { documento: "900000003" }],
]);

/** Lo que el papel diría de Carla, con SU documento: para probar una regla a la vez sin que el cotejo se cuele. */
const papelDeCarla = () => leida({ asegurado: { nombre: "SOTO RUIZ CARLA", documento: "900000003" } });

const archivo = { name: "Cayla, Ana, FOLA 99000001.pdf" };
const tarjeta = (l: PolizaLeida = leida(), personas = PERSONAS, fichas: ReadonlyMap<string, FichaDeDocumento> | null = FICHAS) =>
  tarjetaDeLectura(archivo, 0, 0, 1, l, personas, HOY, fichas);

function ctx(o: Partial<ContextoDeTarjeta> = {}): ContextoDeTarjeta {
  return { hoy: HOY, producto: "salud_practicantes", tipos: TIPOS, personas: PERSONAS, fichas: FICHAS, polizas: [], lote: [], ...o };
}

describe("armar una tarjeta con lo que leyó el lector", () => {
  it("una póliza completa y con la persona clara nace seleccionada, con todo lo leído", () => {
    const t = tarjeta();
    expect(t).toMatchObject({
      incluir: true, personaId: "a", numero: "99000001", desde: "2026-11-01", hasta: "2027-02-01",
      prima: "179.97", primaVence: "2026-11-30", aseguradora: "Pacífico Seguros", nota: "Emitida el 14/10/2026",
      estado: { tipo: "pendiente" },
    });
  });

  it("sin una persona clara, nace SIN seleccionar y sin persona: no se le registra a quien no es", () => {
    expect(tarjeta(leida({ asegurado: { nombre: "ROJAS QUISPE ELENA", documento: "900000009" } })).incluir).toBe(false);
    expect(tarjeta(leida({ asegurado: { nombre: "ROJAS QUISPE ELENA", documento: "900000009" } })).personaId).toBe("");
    expect(tarjeta(leida({ asegurado: null })).incluir).toBe(false);
  });

  it("sin prima, o sin vigencia, nace sin seleccionar", () => {
    expect(tarjeta(leida({ prima: null })).incluir).toBe(false);
    expect(tarjeta(leida({ prima: null })).prima).toBe("");
    expect(tarjeta(leida({ desde: null })).incluir).toBe(false);
    expect(tarjeta(leida({ hasta: null })).incluir).toBe(false);
  });

  it("una fecha que el papel no trae NO nace en blanco: hoy, y tres meses después", () => {
    const t = tarjeta(leida({ desde: null, hasta: null }));
    expect(t.desde).toBe(HOY);
    expect(t.hasta).toBe("2027-01-17");
    // Y si solo falta el final, sigue al inicio que sí se leyó.
    expect(tarjeta(leida({ hasta: null })).hasta).toBe("2027-02-01");
  });

  it("lo que no se leyó queda vacío, no inventado", () => {
    const t = tarjeta(leida({ primaVenceEl: null, aseguradora: null, emitidaEl: null }));
    expect(t.primaVence).toBe("");
    expect(t.aseguradora).toBe("");
    expect(t.nota).toBe("");
  });

  it("dos pólizas del mismo archivo tienen claves distintas", () => {
    const a = tarjetaDeLectura(archivo, 0, 0, 2, leida(), PERSONAS, HOY, FICHAS);
    const b = tarjetaDeLectura(archivo, 0, 1, 2, leida(), PERSONAS, HOY, FICHAS);
    const c = tarjetaDeLectura(archivo, 1, 0, 1, leida(), PERSONAS, HOY, FICHAS);
    expect(new Set([a.clave, b.clave, c.clave]).size).toBe(3);
  });

  it("un solo aviso del lector la deja sin seleccionar aunque todo lo demás cuadre; no pierde lo leído", () => {
    const t = tarjeta(leida({ avisos: ["Las fechas salen de la portada y no de las condiciones: compáralas con el papel."] }));
    expect(t.incluir).toBe(false);
    expect(t).toMatchObject({ personaId: "a", numero: "99000001", prima: "179.97", desde: "2026-11-01" });
  });

  it("cuántas pólizas trajo el archivo queda en la tarjeta: de eso depende si su PDF se guarda", () => {
    expect(tarjeta().polizasDelArchivo).toBe(1);
    expect(tarjetaDeLectura(archivo, 0, 2, 4, leida(), PERSONAS, HOY, FICHAS).polizasDelArchivo).toBe(4);
  });

  it("solo nace seleccionada si el documento del papel es el de la ficha de la persona propuesta", () => {
    expect(tarjeta(leida(), PERSONAS, FICHAS).incluir).toBe(true);
    // Otro documento: el nombre se parece, la persona es otra (o hay un error en alguno de los dos lados).
    const otro = new Map<string, FichaDeDocumento>([["a", { documento: "900000777" }]]);
    expect(tarjeta(leida(), PERSONAS, otro).incluir).toBe(false);
    // Sin con qué comprobar —ficha sin documento, ficha ausente, o las fichas no se pudieron consultar—: tampoco.
    expect(tarjeta(leida(), PERSONAS, new Map([["a", { documento: null }]])).incluir).toBe(false);
    expect(tarjeta(leida(), PERSONAS, new Map()).incluir).toBe(false);
    expect(tarjeta(leida(), PERSONAS, null).incluir).toBe(false);
    // En todos esos casos la persona sigue propuesta: es la mejor pista, y quien la mira decide.
    expect(tarjeta(leida(), PERSONAS, otro).personaId).toBe("a");
    expect(tarjeta(leida(), PERSONAS, null).personaId).toBe("a");
  });
});

describe("el documento del papel contra el de la ficha", () => {
  it("el mismo documento coincide aunque cambie cómo se escribe: guiones, mayúsculas, espacios, ceros de adelante", () => {
    expect(cotejarDocumento("900000001", "900000001")).toBe("coincide");
    expect(cotejarDocumento("08817189", "8817189")).toBe("coincide");
    expect(cotejarDocumento("ce-001234567", "CE001234567")).toBe("coincide");
    expect(cotejarDocumento(" 900000001 ", "900000001")).toBe("coincide");
  });

  it("otro documento es otro, también si solo falta un dígito en medio", () => {
    expect(cotejarDocumento("900000001", "900000002")).toBe("distinto");
    expect(cotejarDocumento("90000001", "900000001")).toBe("distinto");
  });

  it("si falta un lado no hay con qué comprobar, y se dice cuál", () => {
    expect(cotejarDocumento(null, "900000001")).toBe("sin_documento_en_papel");
    expect(cotejarDocumento("  ", "900000001")).toBe("sin_documento_en_papel");
    expect(cotejarDocumento("900000001", null)).toBe("sin_documento_en_ficha");
    expect(cotejarDocumento("900000001", "  ")).toBe("sin_documento_en_ficha");
  });

  it("si no se pudieron consultar las fichas, no se afirma nada", () => {
    expect(cotejarDocumento("900000001", "900000001", false)).toBe("no_comprobado");
    expect(cotejarDocumento(null, null, false)).toBe("no_comprobado");
  });

  it("el cotejo de una tarjeta mira a la persona ELEGIDA, no a la propuesta", () => {
    const t = tarjeta();
    expect(cotejoDeTarjeta(t, FICHAS)).toBe("coincide");
    expect(cotejoDeTarjeta({ ...t, personaId: "b" }, FICHAS)).toBe("distinto");
    expect(cotejoDeTarjeta({ ...t, personaId: "" }, FICHAS)).toBeNull();
    expect(cotejoDeTarjeta(t, null)).toBe("no_comprobado");
    expect(cotejoDeTarjeta({ ...t, leida: leida({ asegurado: null }) }, FICHAS)).toBe("sin_documento_en_papel");
  });
});

describe("qué seguro proponer", () => {
  it("el seguro principal que comparten las personas propuestas, si lleva póliza", () => {
    expect(productoSugerido([{ personaId: "a" }, { personaId: "b" }], PERSONAS, TIPOS)).toBe("salud_practicantes");
  });

  it("si no se ponen de acuerdo, no se adivina", () => {
    expect(productoSugerido([{ personaId: "a" }, { personaId: "c" }], PERSONAS, TIPOS)).toBe("");
  });

  it("si es un seguro que no lleva póliza (EsSalud), no se propone: no hay nada que registrar", () => {
    expect(productoSugerido([{ personaId: "c" }], PERSONAS, TIPOS)).toBe("");
  });

  it("sin personas propuestas, no hay seguro que proponer", () => {
    expect(productoSugerido([{ personaId: "" }], PERSONAS, TIPOS)).toBe("");
    expect(productoSugerido([], PERSONAS, TIPOS)).toBe("");
  });

  it("un seguro archivado no se propone", () => {
    expect(productoSugerido([{ personaId: "a" }], PERSONAS, [{ clave: "salud_practicantes", activo: false, con_poliza: true }])).toBe("");
  });
});

describe("volver a leer un PDF que ya se registró", () => {
  const existente = { persona_id: "a", producto: "salud_practicantes", numero_poliza: "99000001", vigente_desde: "2026-11-01" };

  it("misma persona, seguro, número y día de inicio: ya está registrada", () => {
    expect(yaRegistrada(tarjeta(), "salud_practicantes", [existente])).toBe(true);
    expect(yaRegistrada({ ...tarjeta(), numero: " 99000001 " }, "salud_practicantes", [existente])).toBe(true);
  });

  it("otra persona, otro seguro, otro número u otro inicio: es otra póliza", () => {
    expect(yaRegistrada({ ...tarjeta(), personaId: "b" }, "salud_practicantes", [existente])).toBe(false);
    expect(yaRegistrada(tarjeta(), "vida_ley", [existente])).toBe(false);
    expect(yaRegistrada({ ...tarjeta(), numero: "99000002" }, "salud_practicantes", [existente])).toBe(false);
    expect(yaRegistrada({ ...tarjeta(), desde: "2027-02-01" }, "salud_practicantes", [existente])).toBe(false);
  });

  it("sin persona o sin seguro elegido no hay con qué comparar", () => {
    expect(yaRegistrada({ ...tarjeta(), personaId: "" }, "salud_practicantes", [existente])).toBe(false);
    expect(yaRegistrada(tarjeta(), "", [existente])).toBe(false);
  });
});

describe("qué impide registrar una tarjeta", () => {
  it("una tarjeta completa y sin choques no tiene errores", () => {
    expect(erroresDeTarjeta(tarjeta(), ctx())).toEqual([]);
  });

  it("sin persona, sin número, sin prima o sin aseguradora, lo dice", () => {
    const t = { ...tarjeta(), personaId: "", numero: "9", prima: "", aseguradora: "" };
    expect(erroresDeTarjeta(t, ctx())).toEqual([
      "Elige a quién asegura.",
      "Escribe el número de la póliza.",
      "Escribe la prima total (con IGV).",
      "Escribe la aseguradora.",
    ]);
  });

  it("una prima que no es un monto, o negativa, no pasa; con coma decimal sí", () => {
    expect(erroresDeTarjeta({ ...tarjeta(), prima: "abc" }, ctx())).toEqual(["La prima tiene que ser un monto, 0 o más."]);
    expect(erroresDeTarjeta({ ...tarjeta(), prima: "-5" }, ctx())).toEqual(["La prima tiene que ser un monto, 0 o más."]);
    expect(erroresDeTarjeta({ ...tarjeta(), prima: "179,97" }, ctx())).toEqual([]);
    expect(erroresDeTarjeta({ ...tarjeta(), prima: "0" }, ctx())).toEqual([]);
  });

  it("una vigencia que termina antes de empezar, o sin fechas", () => {
    expect(erroresDeTarjeta({ ...tarjeta(), hasta: "2026-11-01" }, ctx())).toEqual(["La vigencia tiene que terminar después de empezar."]);
    expect(erroresDeTarjeta({ ...tarjeta(), desde: "" }, ctx())).toEqual(["Faltan las fechas de la vigencia."]);
  });

  it("a alguien cuyo seguro principal es otro no se le registra FOLA: la base lo rechazaría", () => {
    const e = erroresDeTarjeta(tarjeta(papelDeCarla()), ctx());
    expect(e).toEqual(["Su seguro hoy es otro: no se le registra una póliza de FOLA. Si debe cambiar, cámbiale el seguro primero."]);
  });

  it("si el documento del papel no es el de la ficha de la persona, no se puede registrar, y dice cuál es cuál", () => {
    const e = erroresDeTarjeta({ ...tarjeta(), personaId: "b" }, ctx());
    expect(e).toHaveLength(1);
    expect(e[0]).toContain("900000001");
    expect(e[0]).toContain("900000002");
    expect(e[0]).toMatch(/revisa que sea la persona correcta/);
  });

  it("sin documento que cotejar —en la ficha, en el papel, o sin poder consultar— no se bloquea: se avisa en la tarjeta y DO decide", () => {
    expect(erroresDeTarjeta(tarjeta(), ctx({ fichas: new Map([["a", { documento: null }]]) }))).toEqual([]);
    expect(erroresDeTarjeta(tarjeta(), ctx({ fichas: null }))).toEqual([]);
    expect(erroresDeTarjeta({ ...tarjeta(), leida: leida({ asegurado: null }) }, ctx())).toEqual([]);
  });

  it("con un seguro que va además del principal, cualquiera sirve", () => {
    expect(erroresDeTarjeta(tarjeta(papelDeCarla()), ctx({ producto: "vida_ley" }))).toEqual([]);
  });

  it("una póliza que se cruza con otra de la misma persona dice cuál", () => {
    const polizas = [{ persona_id: "a", producto: "salud_practicantes", vigente_desde: "2026-10-01", vigente_hasta: "2026-12-01" }];
    expect(erroresDeTarjeta(tarjeta(), ctx({ polizas }))).toEqual(["Ya tiene una póliza de este seguro del 01/10/2026 al 01/12/2026 que se cruza con esas fechas."]);
  });

  it("la renovación que empieza el día en que termina la anterior NO se cruza", () => {
    const polizas = [{ persona_id: "a", producto: "salud_practicantes", vigente_desde: "2026-08-01", vigente_hasta: "2026-11-01" }];
    expect(erroresDeTarjeta(tarjeta(), ctx({ polizas }))).toEqual([]);
  });

  it("dos tarjetas del lote de la misma persona que se cruzan se avisan entre sí; las de otra persona, no", () => {
    const t = tarjeta();
    const hermana = { clave: "0:1", incluir: true, personaId: "a", desde: "2026-12-01", hasta: "2027-03-01", estado: { tipo: "pendiente" } as const };
    expect(erroresDeTarjeta(t, ctx({ lote: [t, hermana] }))).toEqual(["Otra póliza de esta lista es de la misma persona y se cruza con ésta: deja una."]);
    expect(erroresDeTarjeta(t, ctx({ lote: [t, { ...hermana, personaId: "b" }] }))).toEqual([]);
    // Una que no se va a registrar (sin seleccionar) o que ya se registró no frena a nadie.
    expect(erroresDeTarjeta(t, ctx({ lote: [t, { ...hermana, incluir: false }] }))).toEqual([]);
    expect(erroresDeTarjeta(t, ctx({ lote: [t, { ...hermana, estado: { tipo: "registrada", pdf: "guardado" } }] }))).toEqual([]);
  });

  it("un año mal tecleado no es una póliza: la tarjeta lo dice antes de que la base lo rechace", () => {
    expect(erroresDeTarjeta({ ...tarjeta(), hasta: "20277-01-10" }, ctx())).toEqual(["La vigencia no puede pasar de 10 años: revisa el año."]);
    // Diez años justos todavía es una vigencia; un día más ya no.
    expect(erroresDeTarjeta({ ...tarjeta(), desde: HOY, hasta: "2036-10-24" }, ctx())).toEqual([]);
    expect(erroresDeTarjeta({ ...tarjeta(), desde: HOY, hasta: "2036-10-25" }, ctx())).toEqual(["La vigencia no puede pasar de 10 años: revisa el año."]);
  });

  it("el vencimiento de la prima a años de la vigencia también es un tecleo", () => {
    expect(erroresDeTarjeta({ ...tarjeta(), primaVence: "20266-10-31" }, ctx())).toEqual(["El día en que vence la prima no cuadra con la vigencia: revisa el año."]);
    expect(erroresDeTarjeta({ ...tarjeta(), primaVence: "2028-06-01" }, ctx())).toEqual(["El día en que vence la prima no cuadra con la vigencia: revisa el año."]);
    // El del convenio real (dentro de la vigencia) y uno un poco antes o después, sí.
    expect(erroresDeTarjeta({ ...tarjeta(), primaVence: "2026-11-30" }, ctx())).toEqual([]);
    expect(erroresDeTarjeta({ ...tarjeta(), primaVence: "2026-05-01" }, ctx())).toEqual([]);
  });

  it("sin seguro elegido todavía no se comprueba nada que dependa de él", () => {
    const polizas = [{ persona_id: "a", producto: "salud_practicantes", vigente_desde: "2026-10-01", vigente_hasta: "2026-12-01" }];
    expect(erroresDeTarjeta(tarjeta(), ctx({ producto: "", polizas }))).toEqual([]);
  });
});
