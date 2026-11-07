import { describe, expect, it } from "vitest";
import { conservaMarca, cualesPoner, cuantasRetirar, decidirAlVolver } from "../apps/web/lib/hojas-atras";

const arriba = { id: "b", pagina: "/admin/equipo" };

describe("qué hacer con un «atrás»", () => {
  it("con una hoja abierta en la misma pantalla, la cierra", () => {
    expect(decidirAlVolver({ marca: "a", pagina: "/admin/equipo", paginaAntes: "/admin/equipo", arriba, abiertas: ["a", "b"] })).toBe("cerrar");
    expect(decidirAlVolver({ marca: null, pagina: "/admin/equipo", paginaAntes: "/admin/equipo", arriba, abiertas: ["b"] })).toBe("cerrar");
  });
  it("si se llegó a la entrada de la propia hoja, no hay nada que cerrar", () => {
    expect(decidirAlVolver({ marca: "b", pagina: "/admin/equipo", paginaAntes: "/admin/planilla", arriba, abiertas: ["b"] })).toBe("nada");
  });
  it("si se fue a otra pantalla, no es un «atrás» sobre la hoja", () => {
    expect(decidirAlVolver({ marca: null, pagina: "/admin/planilla", paginaAntes: "/admin/equipo", arriba, abiertas: ["b"] })).toBe("nada");
  });
  it("sin hojas y sin marca, el router sigue como siempre", () => {
    expect(decidirAlVolver({ marca: null, pagina: "/mio", paginaAntes: "/admin", arriba: null, abiertas: [] })).toBe("nada");
  });
  it("una entrada huérfana a la que se vuelve desde otra pantalla se salta", () => {
    expect(decidirAlVolver({ marca: "vieja", pagina: "/admin/equipo", paginaAntes: "/admin/planilla", arriba: null, abiertas: [] })).toBe("saltar");
  });
  it("una huérfana en la misma pantalla se deja: no se sabe hacia dónde saltar", () => {
    expect(decidirAlVolver({ marca: "vieja", pagina: "/mio", paginaAntes: "/mio", arriba: null, abiertas: [] })).toBe("nada");
  });
  it("salvo si la enterró una sección de Lo mío: ahí sería un «atrás» que no hace nada", () => {
    expect(decidirAlVolver({ marca: "vieja", pagina: "/mio", paginaAntes: "/mio", arriba: null, abiertas: [], enterrada: true })).toBe("saltar");
  });
});

describe("las entradas", () => {
  it("se retiran las de las hojas que cerraron, hasta la primera que sigue abierta", () => {
    expect(cuantasRetirar(["a", "b", "c"], ["a"])).toBe(2);
    expect(cuantasRetirar(["a", "b"], ["a", "b"])).toBe(0);
    expect(cuantasRetirar(["a", "b"], ["b"])).toBe(0);
    expect(cuantasRetirar([], [])).toBe(0);
  });
  it("una hoja abierta sin entrada la recibe, solo en la página donde se abrió", () => {
    const pila = [{ id: "a", pagina: "/x" }, { id: "b", pagina: "/x" }, { id: "c", pagina: "/y" }];
    expect(cualesPoner(pila, ["a"], "/x").map((h) => h.id)).toEqual(["b"]);
  });
  it("Next no le borra la marca a una entrada de la misma página, y sí a la que ya es de otra pantalla", () => {
    expect(conservaMarca("/x", "/x")).toBe(true);
    expect(conservaMarca("/x", "/y")).toBe(false);
  });
});
