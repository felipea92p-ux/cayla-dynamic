// ============================================================================
// mi-seguro.test.ts — lo que «Mi seguro» (Lo mío) decide para dibujar (0530)
// ============================================================================
// Cuida lo que, si falla, le miente a una practicante sobre su propio seguro:
//   · que «cubierta hasta» cuente las renovaciones que empalman —y las que dejan
//     un hueco, no—, y que el último día de una póliza (EXCLUSIVO) no cuente,
//   · que la cuenta dé lo MISMO que la del tablero de DO para las mismas pólizas
//     (son dos respuestas a «¿esta persona tiene seguro hoy?» y no pueden diferir),
//   · que un dato sin confirmar (plan, beneficio máximo) NO se pinte,
//   · que el archivo no se rotule ni se nombre con nada que escribió otra persona
//     ni con datos de la practicante, y
//   · que el texto fijo no prometa cifras y que el enlace de llamar marque el
//     número que dice.
// Quién ve la sección y qué trae cada fila lo decide la base (pgTAP, prueba 423);
// aquí se comprueba que la pantalla lea eso sin reinterpretarlo.
// ============================================================================
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { describe, it, expect } from "vitest";
import type { ClienteCayla } from "@cayla-dynamic/database";
import {
  loVeLaPracticante, seguroPorPersona, TIPOS_ARCHIVO_SEGURO, TIPOS_QUE_VE_LA_PRACTICANTE, type FilaSeguro,
} from "@/lib/admin/seguros";
import {
  COMO_USARLO, NO_CUBRE, TELEFONOS_PACIFICO, archivosDe, datosConfirmados, enlaceTelefono, leerPolizasMias,
  nombreDeDescarga, resolverMiSeguro, rotuloDeArchivo, traerMiSeguro,
  type ArchivoMio, type PolizaMia,
} from "@/lib/mi-seguro";

const HOY = "2026-10-17";

function poliza(o: Partial<PolizaMia> = {}): PolizaMia {
  const desde = o.vigente_desde ?? "2026-10-01";
  const hasta = o.vigente_hasta ?? "2027-01-01";
  return {
    poliza_id: "z1", aseguradora: "Pacífico Seguros", numero_poliza: "24043267",
    vigente_desde: desde, vigente_hasta: hasta,
    // Lo mismo que calcula la base: el día final NO cubre.
    cubre_hoy: HOY >= desde && HOY < hasta,
    plan: null, beneficio_enfermedad: null, beneficio_accidente: null, archivos: [], ...o,
  };
}

function archivo(o: Partial<ArchivoMio> = {}): ArchivoMio {
  return { id: "a1", tipo: "poliza", storage_path: "5b000000-0000-0000-0000-0000000000a1.pdf", mime: "application/pdf", bytes: 1779531, ...o };
}

describe("leer los archivos que manda la base", () => {
  it("lee los dos tipos que la practicante ve, en el orden en que llegan", () => {
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

describe("pedir fn_mi_seguro", () => {
  const clienteQueDevuelve = (resultado: { data: unknown; error: unknown }) =>
    ({ rpc: async (nombre: string) => { expect(nombre).toBe("fn_mi_seguro"); return resultado; } }) as unknown as ClienteCayla;

  it("devuelve las pólizas leídas", async () => {
    const r = await traerMiSeguro(clienteQueDevuelve({ data: [{ ...poliza(), archivos: [] }], error: null }));
    expect(r.error).toBeNull();
    expect(r.polizas.map((p) => p.numero_poliza)).toEqual(["24043267"]);
  });

  it("sin filas, vacío y sin error: no tener póliza no es una falla", async () => {
    const r = await traerMiSeguro(clienteQueDevuelve({ data: [], error: null }));
    expect(r).toEqual({ polizas: [], error: null });
    expect((await traerMiSeguro(clienteQueDevuelve({ data: null, error: null }))).polizas).toEqual([]);
  });

  it("si la base falla, un texto para leerse y nada inventado: ni «sin póliza» ni lanzar", async () => {
    const r = await traerMiSeguro(clienteQueDevuelve({ data: null, error: { message: "boom", code: "42883" } }));
    expect(r.polizas).toEqual([]);
    expect(r.error).toMatch(/No pudimos leer tu seguro/);
    expect(r.error).not.toMatch(/boom|42883/);
  });
});

describe("cómo está su cobertura hoy", () => {
  it("sin ninguna póliza registrada", () => {
    expect(resolverMiSeguro([], HOY)).toEqual({
      situacion: "sin_poliza", actual: null, otras: [], cubiertoHasta: null,
      diasParaQuedarSinSeguro: null, empiezaEl: null, diasDesdeQueVencio: null,
    });
  });

  it("la póliza de hoy, a 76 días de vencer, está al día", () => {
    const r = resolverMiSeguro([poliza()], HOY);
    expect(r.situacion).toBe("al_dia");
    expect(r.cubiertoHasta).toBe("2027-01-01");
    expect(r.diasParaQuedarSinSeguro).toBe(76);
    expect(r.actual?.poliza_id).toBe("z1");
    expect(r.otras).toEqual([]);
  });

  it("se avisa a los 45 días y no a los 46", () => {
    // hasta = HOY + 45 → por vencer; HOY + 46 → al día.
    expect(resolverMiSeguro([poliza({ vigente_hasta: "2026-12-01" })], HOY).situacion).toBe("por_vencer");   // 45 días
    expect(resolverMiSeguro([poliza({ vigente_hasta: "2026-12-02" })], HOY).situacion).toBe("al_dia");        // 46 días
    expect(resolverMiSeguro([poliza({ vigente_hasta: "2026-12-01" })], HOY).diasParaQuedarSinSeguro).toBe(45);
  });

  it("una renovación que empalma no la deja «por vencer» ni sin seguro: cuenta hasta donde llega la cadena", () => {
    const vieja = poliza({ poliza_id: "z1", vigente_desde: "2026-10-01", vigente_hasta: "2026-11-01" });
    const nueva = poliza({ poliza_id: "z2", numero_poliza: "24043277", vigente_desde: "2026-11-01", vigente_hasta: "2027-02-01" });
    const r = resolverMiSeguro([vieja, nueva], HOY);
    expect(r.situacion).toBe("al_dia");
    expect(r.cubiertoHasta).toBe("2027-02-01");
    expect(r.diasParaQuedarSinSeguro).toBe(107);
    expect(r.actual?.poliza_id).toBe("z1");                       // la que cubre hoy
    expect(r.otras.map((p) => p.poliza_id)).toEqual(["z2"]);
  });

  it("una renovación que empieza DESPUÉS de un hueco no empalma: se queda «por vencer»", () => {
    const vieja = poliza({ poliza_id: "z1", vigente_desde: "2026-10-01", vigente_hasta: "2026-11-01" });
    const nueva = poliza({ poliza_id: "z2", vigente_desde: "2026-11-05", vigente_hasta: "2027-02-05" });
    const r = resolverMiSeguro([vieja, nueva], HOY);
    expect(r.situacion).toBe("por_vencer");
    expect(r.cubiertoHasta).toBe("2026-11-01");
  });

  it("el día en que termina la póliza ya NO cubre (vence a las 12 M), y la renovación de ese mismo día sí", () => {
    const hoy = "2027-01-01";
    const vieja = poliza({ poliza_id: "z1", vigente_desde: "2026-10-01", vigente_hasta: "2027-01-01", cubre_hoy: false });
    // Sola, ese día no tiene seguro: terminó hoy, hace 0 días.
    const sola = resolverMiSeguro([vieja], hoy);
    expect(sola.situacion).toBe("sin_cobertura");
    expect(sola.diasDesdeQueVencio).toBe(0);
    // Con la renovación que empieza hoy, está cubierta.
    const nueva = poliza({ poliza_id: "z2", vigente_desde: "2027-01-01", vigente_hasta: "2027-04-01", cubre_hoy: true });
    const con = resolverMiSeguro([vieja, nueva], hoy);
    expect(con.situacion).toBe("al_dia");
    expect(con.actual?.poliza_id).toBe("z2");
    expect(con.cubiertoHasta).toBe("2027-04-01");
  });

  it("vencida: dice hace cuántos días terminó, y que no hay otra que empiece", () => {
    const r = resolverMiSeguro([poliza({ vigente_hasta: "2026-10-08", vigente_desde: "2026-07-08" })], HOY);
    expect(r.situacion).toBe("sin_cobertura");
    expect(r.diasDesdeQueVencio).toBe(9);
    expect(r.empiezaEl).toBeNull();
    expect(r.cubiertoHasta).toBeNull();
    expect(r.actual?.poliza_id).toBe("z1");
  });

  it("aún no empieza: lo dice con la fecha en que empieza, y esa es la que habla por ella", () => {
    const r = resolverMiSeguro([poliza({ vigente_desde: "2026-10-20", vigente_hasta: "2027-01-20" })], HOY);
    expect(r.situacion).toBe("sin_cobertura");
    expect(r.empiezaEl).toBe("2026-10-20");
    expect(r.actual?.vigente_desde).toBe("2026-10-20");
  });

  it("el orden de las filas no cambia la respuesta", () => {
    const a = poliza({ poliza_id: "z1", vigente_desde: "2026-07-01", vigente_hasta: "2026-10-01", cubre_hoy: false });
    const b = poliza({ poliza_id: "z2", vigente_desde: "2026-10-01", vigente_hasta: "2027-01-01" });
    const c = poliza({ poliza_id: "z3", vigente_desde: "2027-01-01", vigente_hasta: "2027-04-01", cubre_hoy: false });
    const uno = resolverMiSeguro([a, b, c], HOY);
    const otro = resolverMiSeguro([c, a, b], HOY);
    expect(otro).toEqual(uno);
    expect(uno.otras.map((p) => p.poliza_id)).toEqual(["z3", "z1"]);    // la más reciente primero, sin la actual
  });
});

// ── Las dos cuentas tienen que dar lo mismo ─────────────────────────────────
// `seguroPorPersona` es la del tablero de DO; `resolverMiSeguro` es la de la
// practicante. Para las mismas pólizas, dicen lo mismo de la cobertura. Si alguien
// toca una y no la otra, la practicante y DO leerían respuestas distintas.
describe("la cuenta de la practicante coincide con la del tablero de DO", () => {
  function comoTablero(polizas: readonly PolizaMia[], hoy: string): FilaSeguro[] {
    const base = {
      persona_id: "p1", persona: "Ana Prueba", sede: "TRU", practicante_modalidad: "profesional", es_practicante_activo: true,
      prima_total: 179.97, prima_vence_el: null, plan: null, beneficio_enfermedad: null, beneficio_accidente: null,
      renueva_sola: null, pagada_el: null, firmada_el: null, factura_recibida_el: null, nota: null, archivos: 0, creada_at: null,
    };
    const filas: FilaSeguro[] = polizas.map((p) => ({
      ...base, poliza_id: p.poliza_id, aseguradora: p.aseguradora, numero_poliza: p.numero_poliza,
      vigente_desde: p.vigente_desde, vigente_hasta: p.vigente_hasta, cubre_hoy: hoy >= p.vigente_desde && hoy < p.vigente_hasta,
    }));
    // La fila sin póliza que la base agrega cuando nada cubre hoy.
    if (!filas.some((f) => f.cubre_hoy)) {
      filas.push({ ...base, poliza_id: null, aseguradora: null, numero_poliza: null, vigente_desde: null, vigente_hasta: null, cubre_hoy: false, prima_total: null });
    }
    return filas;
  }

  const ESCENARIOS: Array<[string, string, Array<Partial<PolizaMia>>]> = [
    ["una póliza lejos de vencer", "2026-10-17", [{ poliza_id: "z1", vigente_desde: "2026-10-01", vigente_hasta: "2027-01-01" }]],
    ["a 45 días de vencer", "2026-10-17", [{ poliza_id: "z1", vigente_desde: "2026-08-01", vigente_hasta: "2026-12-01" }]],
    ["a 46 días de vencer", "2026-10-17", [{ poliza_id: "z1", vigente_desde: "2026-08-01", vigente_hasta: "2026-12-02" }]],
    ["vence mañana", "2026-10-17", [{ poliza_id: "z1", vigente_desde: "2026-07-18", vigente_hasta: "2026-10-18" }]],
    ["terminó hoy", "2026-10-17", [{ poliza_id: "z1", vigente_desde: "2026-07-17", vigente_hasta: "2026-10-17" }]],
    ["terminó hace 9 días", "2026-10-17", [{ poliza_id: "z1", vigente_desde: "2026-07-08", vigente_hasta: "2026-10-08" }]],
    ["empieza en 3 días", "2026-10-17", [{ poliza_id: "z1", vigente_desde: "2026-10-20", vigente_hasta: "2027-01-20" }]],
    ["renovación que empalma", "2026-10-17", [
      { poliza_id: "z1", vigente_desde: "2026-07-01", vigente_hasta: "2026-11-01" },
      { poliza_id: "z2", vigente_desde: "2026-11-01", vigente_hasta: "2027-02-01" }]],
    ["renovación con un hueco de 4 días", "2026-10-17", [
      { poliza_id: "z1", vigente_desde: "2026-07-01", vigente_hasta: "2026-11-01" },
      { poliza_id: "z2", vigente_desde: "2026-11-05", vigente_hasta: "2027-02-05" }]],
    ["la vencida y la que empieza en una semana", "2026-10-17", [
      { poliza_id: "z1", vigente_desde: "2026-06-01", vigente_hasta: "2026-10-10" },
      { poliza_id: "z2", vigente_desde: "2026-10-24", vigente_hasta: "2027-01-24" }]],
    ["la renovación empieza hoy", "2027-01-01", [
      { poliza_id: "z1", vigente_desde: "2026-10-01", vigente_hasta: "2027-01-01" },
      { poliza_id: "z2", vigente_desde: "2027-01-01", vigente_hasta: "2027-04-01" }]],
    ["tres pólizas encadenadas", "2026-12-20", [
      { poliza_id: "z1", vigente_desde: "2026-10-01", vigente_hasta: "2027-01-01" },
      { poliza_id: "z2", vigente_desde: "2027-01-01", vigente_hasta: "2027-04-01" },
      { poliza_id: "z3", vigente_desde: "2027-04-01", vigente_hasta: "2027-07-01" }]],
  ];

  for (const [nombre, hoy, partes] of ESCENARIOS) {
    it(nombre, () => {
      const polizas = partes.map((o) => poliza({ ...o, cubre_hoy: hoy >= o.vigente_desde! && hoy < o.vigente_hasta! }));
      const mia = resolverMiSeguro(polizas, hoy);
      const [deDo] = seguroPorPersona(comoTablero(polizas, hoy), hoy);

      expect(deDo, "el tablero tiene que devolver a la persona").toBeDefined();
      // Los nombres de la situación cambian (`hueco` se llama aquí `sin_cobertura`); el significado, no.
      const equivalente = { al_dia: "al_dia", por_vencer: "por_vencer", hueco: "sin_cobertura" } as const;
      expect(mia.situacion).toBe(equivalente[deDo.situacion as "al_dia" | "por_vencer" | "hueco"]);
      expect(mia.cubiertoHasta).toBe(deDo.cubiertoHasta);
      expect(mia.diasParaQuedarSinSeguro).toBe(deDo.diasParaQuedarSinSeguro);
      expect(mia.diasDesdeQueVencio).toBe(deDo.diasDesdeQueVencio);
      expect(mia.empiezaEl).toBe(deDo.empiezaEl);
      expect(mia.actual?.poliza_id).toBe(deDo.actual?.poliza_id);
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

  it("el archivo que se baja se llama por su póliza, con la extensión de lo que es", () => {
    expect(nombreDeDescarga(archivo(), "24043267")).toBe("Poliza-FOLA-24043267.pdf");
    expect(nombreDeDescarga(archivo({ tipo: "convenio_pago" }), "24043267")).toBe("Convenio-de-pago-FOLA-24043267.pdf");
    expect(nombreDeDescarga(archivo({ mime: "image/jpeg", storage_path: "x.jpg" }), "24043267")).toBe("Poliza-FOLA-24043267.jpg");
    expect(nombreDeDescarga(archivo({ mime: "image/heic" }), "24043267")).toBe("Poliza-FOLA-24043267.heic");
  });

  it("un mime raro cae a la extensión de la ruta, y el número tecleado a mano se limpia", () => {
    expect(nombreDeDescarga(archivo({ mime: "application/x-raro", storage_path: "abc.pdf" }), "24043267")).toBe("Poliza-FOLA-24043267.pdf");
    expect(nombreDeDescarga(archivo(), " 24/043 267 ")).toBe("Poliza-FOLA-24-043-267.pdf");
    expect(nombreDeDescarga(archivo(), "///")).toBe("Poliza-FOLA-sin-numero.pdf");
  });

  it("nada en el nombre se parece a una persona: solo FOLA y el número de póliza", () => {
    const n = nombreDeDescarga(archivo({ storage_path: "5b000000-0000-0000-0000-0000000000a1.pdf" }), "24043267");
    expect(n).toMatch(/^[A-Za-z0-9-]+\.[a-z0-9]+$/);
  });
});

describe("el texto fijo de «cómo usarlo»", () => {
  const todoElTexto = [...COMO_USARLO.flatMap((p) => [p.titulo, p.texto]), ...NO_CUBRE].join(" ");

  it("lleva lo que el resumen de la póliza dice, y lo dice con las cifras del resumen", () => {
    expect(todoElTexto).toMatch(/DNI/);
    expect(todoElTexto).toMatch(/carta de garantía/i);
    expect(todoElTexto).toMatch(/3 días útiles/);
    expect(todoElTexto).toMatch(/Pacífico Asiste/);
    expect(todoElTexto).toMatch(/90 días/);
    expect(todoElTexto).toMatch(/originales/);
    expect(TELEFONOS_PACIFICO).toEqual(["(01) 415-1515", "(01) 513-5000"]);
  });

  it("dice lo que NO cubre: gestación, odontología salvo accidente, salud mental y preexistencias", () => {
    const x = NO_CUBRE.join(" | ");
    expect(x).toMatch(/Gestación/);
    expect(x).toMatch(/Odontología, salvo por accidente/);
    expect(x).toMatch(/Salud mental/);
    expect(x).toMatch(/Preexistencias/);
    expect(NO_CUBRE).toHaveLength(4);
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
    expect(new Set(COMO_USARLO.map((p) => p.clave)).size).toBe(COMO_USARLO.length);
    for (const p of COMO_USARLO) {
      expect(p.titulo.trim()).not.toBe("");
      expect(p.texto.trim()).not.toBe("");
    }
  });
});

describe("qué archivos de una póliza ve también la practicante", () => {
  it("de los cuatro tipos, la póliza y el convenio de pago sí; la factura y «otro», no", () => {
    expect(TIPOS_ARCHIVO_SEGURO.map((t) => `${t.valor}:${loVeLaPracticante(t.valor)}`)).toEqual([
      "poliza:true", "convenio_pago:true", "factura:false", "otro:false",
    ]);
    expect(loVeLaPracticante("algo-nuevo")).toBe(false);
  });

  // La lista vive en TRES sitios que no se pueden comparar en el compilador: las dos
  // funciones de la 0530 (SQL) y esta pantalla de DO (TypeScript). Si una cambia sola,
  // DO leería «la practicante lo ve» sobre un archivo que la base no le da, o al revés.
  it("la lista de TypeScript es la misma que la 0530 escribe en sus dos funciones", () => {
    const carpeta = path.resolve(import.meta.dirname, "../supabase/migrations");
    const archivo = readdirSync(carpeta).find((f) => f.startsWith("0530_"));
    expect(archivo, "la 0530 tiene que existir").toBeDefined();
    const sql = readFileSync(path.join(carpeta, archivo!), "utf8");
    const listas = [...sql.matchAll(/a\.tipo in \(([^)]*)\)/g)].map((m) =>
      m[1].split(",").map((x) => x.trim().replace(/'/g, "")).sort());
    // Una en `fn_seguro_archivo_es_mio` (la política de Storage) y otra en `fn_mi_seguro`.
    expect(listas).toHaveLength(2);
    for (const l of listas) expect(l).toEqual([...TIPOS_QUE_VE_LA_PRACTICANTE].sort());
  });
});

describe("el enlace para llamar", () => {
  it("marca el número que dice: Lima es +51 1", () => {
    expect(enlaceTelefono("(01) 415-1515")).toBe("tel:+5114151515");
    expect(enlaceTelefono("(01) 513-5000")).toBe("tel:+5115135000");
  });

  it("los dos teléfonos del texto producen un enlace de 7 cifras después del código de Lima", () => {
    for (const t of TELEFONOS_PACIFICO) expect(enlaceTelefono(t)).toMatch(/^tel:\+511\d{7}$/);
  });
});
