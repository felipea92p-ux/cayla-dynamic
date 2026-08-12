import { describe, it, expect } from "vitest";
import { readFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import { bloquesDe, marcasDe, type Bloque, type Marca } from "@/lib/admin/markdown-documento";

// El visor del Reglamento en /admin/normas.
//
// POR QUÉ ESTE ARCHIVO. El 2026-08-11 se publicó el Reglamento y se vio en
// pantalla con los asteriscos del markdown a la vista: «**TÍTULO I —
// DISPOSICIONES GENERALES**». En el Reglamento CADA numeral empieza en negrita,
// así que eran más de mil líneas con `**` delante, en el texto que veintiuna
// personas tienen que leer para dejar su constancia. Un documento que se lee mal
// se lee menos, y este obliga.
//
// Lo que se prueba acá es el ANÁLISIS, que es lo que se puede equivocar: dónde
// empieza una tabla, cuándo deja de serlo una lista, qué es un separador y qué
// es contenido. El dibujo es JSX y no se prueba — si el análisis está bien, el
// dibujo es una correspondencia de uno a uno.

const RAIZ = join(import.meta.dirname, "..");
const doc = (n: string) => join(RAIZ, "docs", `${n}.md`);

/** Todo el texto de un bloque, sin las marcas. */
function textoDe(b: Bloque): string {
  const junta = (ms: Marca[]) => ms.map((m) => m.texto).join("");
  switch (b.tipo) {
    case "encabezado": case "cita": case "parrafo": return junta(b.marcas);
    case "lista": return b.items.map(junta).join(" ");
    case "tabla": return [...(b.cabecera ?? []), ...b.filas.flat()].map(junta).join(" ");
    default: return "";
  }
}

describe("marcas de línea", () => {
  it("saca la negrita y deja el resto en su sitio", () => {
    expect(marcasDe("**60.1. Versión.** Este documento es el RIT.")).toEqual([
      { estilo: "negrita", texto: "60.1. Versión." },
      { estilo: "plano", texto: " Este documento es el RIT." },
    ]);
  });

  it("distingue la cursiva de la negrita, que empiezan igual", () => {
    expect(marcasDe("**fuerte** y *suave*")).toEqual([
      { estilo: "negrita", texto: "fuerte" },
      { estilo: "plano", texto: " y " },
      { estilo: "cursiva", texto: "suave" },
    ]);
  });

  it("un asterisco suelto no es una marca y se queda como está", () => {
    expect(marcasDe("3 * 4 = 12")).toEqual([{ estilo: "plano", texto: "3 * 4 = 12" }]);
  });

  it("lo que va dentro de `código` no se vuelve a interpretar", () => {
    // Es el caso que obligó a hacer UN solo recorrido: en tres pasadas, los
    // asteriscos de dentro del código se habrían convertido en negrita.
    expect(marcasDe("usa `a ** b` con cuidado")).toEqual([
      { estilo: "plano", texto: "usa " },
      { estilo: "codigo", texto: "a ** b" },
      { estilo: "plano", texto: " con cuidado" },
    ]);
  });

  it("una negrita sin cerrar se muestra tal cual, no se traga el resto", () => {
    expect(marcasDe("**sin cerrar")).toEqual([{ estilo: "plano", texto: "**sin cerrar" }]);
  });

  it("dos negritas en la misma línea son dos marcas", () => {
    const m = marcasDe("**a** entre **b**");
    expect(m.filter((x) => x.estilo === "negrita").map((x) => x.texto)).toEqual(["a", "b"]);
  });
});

describe("bloques", () => {
  it("una tabla con cabecera separa la primera fila del cuerpo", () => {
    const b = bloquesDe("| Nombre | Firma |\n|---|---|\n| Ana | |") as Bloque[];
    const t = b.find((x) => x.tipo === "tabla");
    expect(t).toBeDefined();
    if (t?.tipo !== "tabla") throw new Error("no es tabla");
    expect(t.cabecera?.map((c) => c.map((m) => m.texto).join(""))).toEqual(["Nombre", "Firma"]);
    expect(t.filas).toHaveLength(1);
    expect(t.filas[0][0][0].texto).toBe("Ana");
  });

  it("una tabla de una sola fila SIN separador no pierde esa fila", () => {
    // El cargo de recepción tiene casillas que son solo cabecera. Tragarse la
    // única fila dejaría el papel sin el hueco donde se escribe el nombre.
    const b = bloquesDe("| Nombre y apellidos | |");
    const t = b.find((x) => x.tipo === "tabla");
    if (t?.tipo !== "tabla") throw new Error("no es tabla");
    expect(t.cabecera).toBeNull();
    expect(t.filas).toHaveLength(1);
  });

  it("«---» es una regla horizontal, nunca una viñeta", () => {
    const b = bloquesDe("uno\n\n---\n\ndos");
    expect(b.some((x) => x.tipo === "regla")).toBe(true);
    expect(b.some((x) => x.tipo === "lista")).toBe(false);
  });

  it("una lista con viñetas y otra numerada no se funden", () => {
    const b = bloquesDe("- uno\n- dos\n1. tres\n2. cuatro");
    const listas = b.filter((x) => x.tipo === "lista");
    expect(listas).toHaveLength(2);
    if (listas[0].tipo !== "lista" || listas[1].tipo !== "lista") throw new Error("no son listas");
    expect(listas[0].ordenada).toBe(false);
    expect(listas[0].items).toHaveLength(2);
    expect(listas[1].ordenada).toBe(true);
    expect(listas[1].items).toHaveLength(2);
  });

  it("los encabezados llegan con su nivel y con sus marcas", () => {
    const b = bloquesDe("## TÍTULO I\n#### **19.2.** Gradación");
    const encs = b.filter((x) => x.tipo === "encabezado");
    if (encs[0].tipo !== "encabezado" || encs[1].tipo !== "encabezado") throw new Error("no");
    expect(encs[0].nivel).toBe(2);
    expect(encs[1].nivel).toBe(4);
    expect(encs[1].marcas[0]).toEqual({ estilo: "negrita", texto: "19.2." });
  });

  it("una tabla DENTRO de una cita sigue siendo una tabla", () => {
    // Los once modelos de carta del Manual van citados enteros y llevan tablas
    // dentro. Antes salían como cita con las barras a la vista, justo en la
    // casilla donde hay que escribir las tardanzas.
    const b = bloquesDe("> **1. Hechos.**\n>\n> | Fecha | Minutos |\n> |---|---|\n> | [ ] | [ ] |");
    const t = b.find((x) => x.tipo === "tabla");
    if (t?.tipo !== "tabla") throw new Error("la tabla citada no se reconoció");
    expect(t.enCita).toBe(true);
    expect(t.cabecera?.map((c) => c.map((m) => m.texto).join(""))).toEqual(["Fecha", "Minutos"]);
    expect(t.filas).toHaveLength(1);
    expect(b.some((x) => x.tipo === "cita" && textoDe(x).includes("|"))).toBe(false);
  });

  it("una lista citada se marca como citada y no se funde con la de fuera", () => {
    const b = bloquesDe("- fuera\n> - dentro");
    const listas = b.filter((x) => x.tipo === "lista");
    expect(listas).toHaveLength(2);
    if (listas[0].tipo !== "lista" || listas[1].tipo !== "lista") throw new Error("no");
    expect(listas[0].enCita).toBe(false);
    expect(listas[1].enCita).toBe(true);
  });

  it("una tabla cortada por un párrafo se cierra y no se come lo que sigue", () => {
    const b = bloquesDe("| a | b |\ntexto suelto\n| c | d |");
    expect(b.filter((x) => x.tipo === "tabla")).toHaveLength(2);
    expect(b.filter((x) => x.tipo === "parrafo")).toHaveLength(1);
  });
});

// ── Contra los documentos de verdad ─────────────────────────────────────────
//
// Los casos de arriba son de laboratorio. Estos son los seis documentos que se
// publican, con sus 45.000 palabras: es donde aparece lo que no se me ocurrió.
const SEIS = [
  "reglamento-interno-de-trabajo",
  "manual-procedimiento-disciplinario",
  "politica-prevencion-hostigamiento-sexual",
  "resolucion-designacion-hostigamiento",
  "formato-queja-hostigamiento-sexual",
  "cargo-recepcion-reglamento",
];

describe("los seis documentos que se publican", () => {
  for (const nombre of SEIS) {
    const ruta = doc(nombre);
    // Si algún día un documento se renombra, la prueba lo dice en vez de pasar
    // en verde sobre un archivo que no existe.
    it(`${nombre} existe`, () => expect(existsSync(ruta)).toBe(true));

    it(`${nombre} no deja marcas de markdown a la vista`, () => {
      const bloques = bloquesDe(readFileSync(ruta, "utf8"));
      const sucios = bloques
        .map(textoDe)
        .filter((t) => t.includes("**") || /^\s*\|/.test(t));
      expect(sucios.slice(0, 3)).toEqual([]);
    });

    it(`${nombre} no pierde ninguna línea con contenido`, () => {
      // La red de seguridad de verdad: cada línea no vacía del archivo tiene que
      // seguir estando en algún bloque. Es lo que habría cazado que el conversor
      // se comiera la primera sección de los cinco satélites.
      const crudo = readFileSync(ruta, "utf8");
      const bloques = bloquesDe(crudo);
      const todo = bloques.map(textoDe).join("\n");
      const perdidas = crudo.split("\n")
        // El «>» se quita PRIMERO, igual que hace el analizador: si no, las
        // tablas de los modelos de carta —que van citadas— se cuelan en la
        // comparación con sus barras y esta prueba culpa al analizador de un
        // defecto suyo.
        .map((l) => l.trim().replace(/^>\s?/, "").trim())
        .filter((l) => l && l !== "---" && !l.startsWith("|"))
        .map((l) => l.replace(/^#{1,4}\s+/, "")
                     .replace(/^[-*+]\s+/, "").replace(/^\d+[.)]\s+/, ""))
        .filter((l) => l && !todo.includes(l.replace(/[*`]/g, "")));
      expect(perdidas.slice(0, 3)).toEqual([]);
    });
  }
});
