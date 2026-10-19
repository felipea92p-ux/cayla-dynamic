// ============================================================================
// mio-secciones.test.ts — El menú de «Lo mío», en grupos, y su buscador (⌘K)
// ============================================================================
// El 2026-10-06 las secciones pasaron de una sola lista a cuatro
// grupos que se pueden cerrar, con un buscador. Lo que se prueba acá es lo que
// un cambio en esa lista puede romper EN SILENCIO, sin error de tipos:
//
//   · una sección que se queda fuera de todos los grupos no aparece en el
//     menú, y nadie la vuelve a encontrar —salvo con un enlace guardado—;
//   · una sección repetida en dos grupos se dibuja dos veces;
//   · un alias que deja de llevar a su sección: quien escribe «sueldo» ya no
//     llega a sus boletas, y el buscador parece roto.
// ============================================================================
import { describe, it, expect } from "vitest";
import { GRUPOS_MIO, TABS, esTab, type Tab } from "@/lib/mio-secciones";
import { buscarSecciones, type GrupoDetalle } from "@/lib/secciones-de-menu";

const TODAS: Tab[] = [
  "resumen", "dias", "turnos", "dni", "seguro", "datos", "ausencias", "contrato", "boletas", "movilidad", "educacion",
  "firma", "objetivos", "reportes", "disciplina", "historial",
];

describe("cada sección vive en un grupo, y en uno solo", () => {
  it("están las dieciséis, ni una más ni una menos", () => {
    expect([...TABS].sort()).toEqual([...TODAS].sort());
  });

  it("ninguna se repite", () => {
    expect(new Set(TABS).size).toBe(TABS.length);
  });

  it("«Resumen» va primero, solo y sin título: es donde se aterriza", () => {
    const [primero] = GRUPOS_MIO;
    expect(primero.label).toBeUndefined();
    expect(primero.secciones.map((s) => s.valor)).toEqual(["resumen"]);
  });

  it("los demás grupos tienen título, y no hay dos con el mismo (es la llave de lo que se recuerda cerrado)", () => {
    const titulos = GRUPOS_MIO.slice(1).map((g) => g.label);
    expect(titulos.every((t) => typeof t === "string" && t.trim() !== "")).toBe(true);
    expect(new Set(titulos).size).toBe(titulos.length);
  });

  it("«Asistencia» y «Pago» se llaman igual que en el menú del panel", () => {
    const titulos = GRUPOS_MIO.map((g) => g.label);
    expect(titulos).toContain("Asistencia");
    expect(titulos).toContain("Pago");
  });

  it("«Historial» no va en Asistencia: son correcciones, no asistencia de todos los días", () => {
    const asistencia = GRUPOS_MIO.find((g) => g.label === "Asistencia");
    expect(asistencia?.secciones.map((s) => s.valor)).not.toContain("historial");
  });

  it("«Disciplina» va en Seguimiento, justo antes de «Historial»: ya no hay que buscar sus memos en la última sección", () => {
    const seguimiento = GRUPOS_MIO.find((g) => g.label === "Seguimiento")!.secciones.map((s) => s.valor);
    expect(seguimiento).toContain("disciplina");
    expect(seguimiento.indexOf("disciplina")).toBe(seguimiento.indexOf("historial") - 1);
  });

  it("quien escribe «memo» o «amonestación» llega a Disciplina, que es donde están ahora, y no a Historial", () => {
    for (const q of ["memo", "amonestacion", "llamada de atencion", "legajo"]) {
      expect(buscarSecciones(GRUPOS_MIO, q)[0]?.seccion.valor, q).toBe("disciplina");
    }
    expect(buscarSecciones(GRUPOS_MIO, "correcciones")[0]?.seccion.valor).toBe("historial");
  });

  it("«Mi seguro» va en Documentos, junto a Contrato, Firma y Mi DNI, con el ícono del escudo", () => {
    const documentos = GRUPOS_MIO.find((g) => g.label === "Documentos")!;
    const valores = documentos.secciones.map((s) => s.valor);
    expect(valores).toEqual(expect.arrayContaining(["contrato", "firma", "dni", "seguro"]));
    const seguro = documentos.secciones.find((s) => s.valor === "seguro")!;
    expect(seguro.label).toBe("Mi seguro");
    // lucide-react es dependencia de apps/web, no de la raíz: se lee el nombre del ícono, no el ícono.
    expect((seguro.Icon as { displayName?: string }).displayName).toBe("ShieldCheck");
  });

  it("el menú habla en primera persona: «Mis datos», ya no «Tus datos»", () => {
    const etiquetas = GRUPOS_MIO.flatMap((g) => g.secciones.map((s) => s.label));
    expect(etiquetas).toContain("Mis datos");
    expect(etiquetas.some((e) => /^(tu|tus)\b/i.test(e))).toBe(false);
  });
});

describe("un ?tab= que llega de un enlace", () => {
  it("se acepta si es una sección que existe", () => {
    expect(esTab("boletas")).toBe(true);
    expect(esTab("seguro")).toBe(true);
  });

  it("se rechaza si viene mal escrito, o con el nombre que se ve y no el valor", () => {
    expect(esTab("boleta")).toBe(false);
    expect(esTab("Boletas")).toBe(false);
    expect(esTab("")).toBe(false);
  });
});

describe("el buscador (⌘K) encuentra lo que alguien escribiría", () => {
  const primera = (q: string) => buscarSecciones(GRUPOS_MIO, q)[0]?.seccion.valor;

  it("sin nada escrito, las dieciséis y en el orden del menú: abrirlo sirve para hojear", () => {
    expect(buscarSecciones(GRUPOS_MIO, "").map((r) => r.seccion.valor)).toEqual([...TABS]);
    expect(buscarSecciones(GRUPOS_MIO, "   ")).toHaveLength(TABS.length);
  });

  // Lo que la gente escribe cuando no sabe cómo se llama la sección.
  const CASOS: Array<[string, Tab]> = [
    ["sueldo", "boletas"],
    // Hasta el 2026-10-06 «memo» llevaba a Historial; sus memos viven ahora en Disciplina.
    ["memo", "disciplina"],
    ["vacaciones", "ausencias"],
    ["descanso medico", "ausencias"],
    ["horario", "turnos"],
    ["tardanza", "dias"],
    ["ruta", "movilidad"],
    ["banco", "datos"],
    ["dni", "dni"],
    // «Mi seguro»: lo que alguien escribe sin saber cómo se llama la sección.
    ["poliza", "seguro"],
    ["fola", "seguro"],
    ["pacifico", "seguro"],
    ["clinica", "seguro"],
    ["salud", "seguro"],
    ["essalud", "seguro"],
  ];
  for (const [escrito, seccion] of CASOS) {
    it(`«${escrito}» lleva a ${seccion}`, () => {
      expect(primera(escrito)).toBe(seccion);
    });
  }

  it("no distingue tildes ni mayúsculas, en ninguna de las dos direcciones", () => {
    expect(primera("educacion")).toBe("educacion");
    expect(primera("EDUCACIÓN")).toBe("educacion");
    expect(primera("amonestacion")).toBe("disciplina");
    expect(primera("dirección")).toBe("datos");
  });

  it("dice por qué salió cuando no fue por su nombre, y lo calla cuando sí", () => {
    const [porSueldo] = buscarSecciones(GRUPOS_MIO, "sueldo");
    expect(porSueldo.porAlias).toBe("sueldo");
    const [porNombre] = buscarSecciones(GRUPOS_MIO, "bolet");
    expect(porNombre.seccion.valor).toBe("boletas");
    expect(porNombre.porAlias).toBeUndefined();
  });

  it("muestra el grupo de cada resultado, y nada para «Resumen», que no tiene", () => {
    expect(buscarSecciones(GRUPOS_MIO, "sueldo")[0].grupo).toBe("Pago");
    expect(buscarSecciones(GRUPOS_MIO, "resumen")[0].grupo).toBeUndefined();
  });

  it("«bono» trae los dos bonos, no uno al azar", () => {
    expect(buscarSecciones(GRUPOS_MIO, "bono").map((r) => r.seccion.valor)).toEqual(["movilidad", "educacion"]);
  });

  it("lo que no existe no trae nada, en vez de traer cualquier cosa", () => {
    expect(buscarSecciones(GRUPOS_MIO, "zzzz")).toEqual([]);
  });

  it("«Mi seguro» es de todo el equipo: no hay nada en el catálogo que la reserve a un vínculo", () => {
    // Nació acotada a los practicantes (FOLA) y se abrió cuando el módulo de Seguros pasó a ser
    // general: cada colaborador ve el suyo. Si alguien la vuelve a esconder para algunos, esta
    // sección dejaría de existir para ellos sin que ninguna prueba de menú lo note.
    const seccion = GRUPOS_MIO.flatMap((g) => g.secciones).find((s) => s.valor === "seguro")!;
    expect(Object.keys(seccion).sort()).toEqual(["Icon", "alias", "label", "valor"]);
    expect(buscarSecciones(GRUPOS_MIO, "essalud").map((r) => r.seccion.valor)).toContain("seguro");
    expect(buscarSecciones(GRUPOS_MIO, "fola").map((r) => r.seccion.valor)).toContain("seguro");
  });

  it("no inventa secciones: solo devuelve las que le pasan (una sección oculta no se busca)", () => {
    // «Mi DNI» se esconde mientras la base no tiene dónde guardarlo; si el
    // buscador la ofreciera igual, llevaría a una sección que no existe.
    const sinDni: GrupoDetalle<Tab>[] = GRUPOS_MIO.map((g) => ({
      ...g, secciones: g.secciones.filter((s) => s.valor !== "dni"),
    }));
    expect(buscarSecciones(sinDni, "dni").map((r) => r.seccion.valor)).not.toContain("dni");
  });
});
