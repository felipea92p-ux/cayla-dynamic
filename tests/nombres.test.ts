// ============================================================================
// nombres.test.ts — Dos nombres, cada uno en su sitio
// ============================================================================
// Cada integrante tiene un nombre corto («Elida Salinas», el del terminal) y un
// nombre completo («Elida Lizeth Salinas Mamani», el del DNI). Los papeles que
// salen de la empresa llevan el segundo; el terminal, el primero.
//
// La segunda mitad de este archivo no prueba una función: prueba una promesa de
// diseño. Si alguien «mejora» el terminal para que muestre el nombre completo,
// la fila de 5 columnas se rompe y, peor, `datos_personales` empieza a leerse
// desde una pantalla que marca SIN PIN, a la vista de toda la sede. Un freno que
// solo se prueba con casos que pasan no se ha probado, así que el escáner se
// prueba primero contra un archivo que DEBE rechazar.
// ============================================================================
import { describe, expect, it } from "vitest";
import { readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { avisoDocumentoEnNombre, avisoNombresDelDni, nombreCorto, nombreOficial, usaNombreDelDni } from "@cayla-dynamic/shared";

describe("nombreCorto", () => {
  it("junta nombre y apellido sin dejar espacios sueltos", () => {
    expect(nombreCorto("Elida", "Salinas")).toBe("Elida Salinas");
    expect(nombreCorto("Elida", "")).toBe("Elida");
    expect(nombreCorto("", "Salinas")).toBe("Salinas");
  });
});

describe("nombreOficial — el que va en un papel", () => {
  const CORTO = "Elida Salinas";

  it("usa el nombre del DNI cuando la ficha lo tiene", () => {
    expect(nombreOficial("Elida Lizeth Salinas Mamani", CORTO)).toBe("Elida Lizeth Salinas Mamani");
  });

  it("lo entrega limpio: sin los espacios que deja un copiar y pegar", () => {
    expect(nombreOficial("  Elida Lizeth Salinas Mamani \n", CORTO)).toBe("Elida Lizeth Salinas Mamani");
  });

  it("cae al corto si la ficha no lo tiene cargado, en vez de imprimir un papel sin nombre", () => {
    expect(nombreOficial(null, CORTO)).toBe(CORTO);
    expect(nombreOficial(undefined, CORTO)).toBe(CORTO);
    expect(nombreOficial("", CORTO)).toBe(CORTO);
  });

  it("y también si se guardó solo con espacios — que es lo que la forma corta `||` deja pasar", () => {
    // `"   " || corto` da «   »: un certificado sin nombre. Este es el caso que
    // justifica tener la condición en un solo sitio.
    expect("   " || CORTO).toBe("   ");
    expect(nombreOficial("   ", CORTO)).toBe(CORTO);
    expect(nombreOficial("\t\n", CORTO)).toBe(CORTO);
  });
});

describe("usaNombreDelDni — para avisar antes de imprimir lo que no se puede corregir", () => {
  it("dice la verdad en los cinco casos", () => {
    expect(usaNombreDelDni("Elida Lizeth Salinas Mamani")).toBe(true);
    expect(usaNombreDelDni(null)).toBe(false);
    expect(usaNombreDelDni(undefined)).toBe(false);
    expect(usaNombreDelDni("")).toBe(false);
    expect(usaNombreDelDni("   ")).toBe(false);
  });
});

describe("avisoNombresDelDni — a cuántas les falta, en una hoja con muchas personas", () => {
  it("si a todas les consta, no avisa nada", () => {
    expect(avisoNombresDelDni(["Elida Lizeth Salinas Mamani", "Angie Aderlin Chávez Honorio"])).toBeNull();
    expect(avisoNombresDelDni([])).toBeNull();
  });

  it("cuenta como faltante la que no tiene dato, la vacía y la de puros espacios", () => {
    const aviso = avisoNombresDelDni(["Elida Lizeth Salinas Mamani", null, undefined, "", "   ", "Angie Aderlin Chávez Honorio"]);
    expect(aviso).toContain("4 de 6 integrantes no tienen");
  });

  it("habla en singular cuando falta una sola", () => {
    const aviso = avisoNombresDelDni(["Elida Lizeth Salinas Mamani", null]);
    expect(aviso).toContain("1 de 2 integrantes no tiene cargado");
    expect(aviso).toContain("sale solo con el nombre corto");
  });

  it("dice dónde se arregla, con el vocabulario de la casa", () => {
    const aviso = avisoNombresDelDni([null]) ?? "";
    expect(aviso).toContain("Datos personales");
    expect(aviso).not.toMatch(/\b(emplead[oa]s?|jef[ea]s?|sucursal(es)?|rrhh)\b/i);
  });
});

// ── El terminal ve el nombre corto, y solo el corto ─────────────────────────

const RAIZ = path.resolve(import.meta.dirname, "..");
const PROHIBIDO_EN_EL_TERMINAL = /nombre_dni|datos_personales|nombreOficial|usaNombreDelDni/;

/** Líneas que tocan el nombre del DNI, ignorando comentarios (que lo explican). */
function lineasQueTocanElNombreDelDni(texto: string): string[] {
  return texto
    .split("\n")
    .filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l))
    .filter((l) => PROHIBIDO_EN_EL_TERMINAL.test(l));
}

function archivosTs(dir: string): string[] {
  return readdirSync(dir).flatMap((nombre) => {
    const ruta = path.join(dir, nombre);
    if (statSync(ruta).isDirectory()) return archivosTs(ruta);
    return /\.(ts|tsx)$/.test(nombre) ? [ruta] : [];
  });
}

describe("el terminal nunca lee el nombre completo", () => {
  it("el escáner SÍ rechaza un terminal que lo pide (el caso que debe bloquear)", () => {
    const malo = [
      "const { data } = await supabase",
      '  .from("datos_personales").select("nombre_dni")',
    ].join("\n");
    expect(lineasQueTocanElNombreDelDni(malo).length).toBeGreaterThan(0);
  });

  it("y deja pasar un comentario que solo lo explica", () => {
    expect(lineasQueTocanElNombreDelDni("// el terminal no pide nombre_dni nunca")).toEqual([]);
  });

  it("ningún archivo del terminal lo toca", () => {
    const carpetas = [
      path.join(RAIZ, "apps/web/app/(terminal)"),
      path.join(RAIZ, "apps/web/lib/terminal"),
    ];
    const infractores = carpetas
      .flatMap(archivosTs)
      .filter((f) => lineasQueTocanElNombreDelDni(readFileSync(f, "utf8")).length > 0)
      .map((f) => path.relative(RAIZ, f));
    expect(infractores).toEqual([]);
  });
});

// La 0512 tiene la misma regla en la base (`personas_nombre_sin_documento`). Los
// casos son los mismos que la prueba pgTAP 406, para que las dos mitades no
// puedan separarse sin que una de las dos lo note.
describe("avisoDocumentoEnNombre — el DNI no va en el nombre", () => {
  it("frena un documento en el nombre o en el apellido", () => {
    expect(avisoDocumentoEnNombre("Prueba", "Cuatrocientos 12345678")).toMatch(/Datos personales/);
    expect(avisoDocumentoEnNombre("12345678 Prueba", "Cuatrocientos")).not.toBeNull();
    expect(avisoDocumentoEnNombre("Prueba", "Cuatrocientos 001234567")).not.toBeNull();
  });
  it("deja pasar nombres reales y estaciones con un número corto", () => {
    expect(avisoDocumentoEnNombre("Prueba", "Cuatrocientos-Ñúñez")).toBeNull();
    expect(avisoDocumentoEnNombre("ESTACIÓN — Caja 2", "(no es persona)")).toBeNull();
    expect(avisoDocumentoEnNombre("Prueba", "Cuatrocientos 12345")).toBeNull();
  });
});
