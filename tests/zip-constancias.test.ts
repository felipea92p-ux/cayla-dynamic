import { describe, it, expect } from "vitest";
import { nombreLegible, sinRepetidos } from "@/lib/admin/zip-constancias";

describe("nombreLegible — un nombre que se entiende y que ningún sistema de archivos rechaza", () => {
  it("conserva acentos, eñes y espacios", () => {
    expect(nombreLegible("Sandra Ramírez - Duolingo - 2026-09-30 - 1.jpg")).toBe("Sandra Ramírez - Duolingo - 2026-09-30 - 1.jpg");
  });

  it("quita lo que Windows y macOS no dejan en un nombre", () => {
    expect(nombreLegible('Colegio "Santa Rosa" / Lima: pago?.pdf')).toBe("Colegio Santa Rosa Lima pago.pdf");
  });

  it("junta espacios repetidos y recorta los de los extremos", () => {
    expect(nombreLegible("  Ana   Torres  ")).toBe("Ana Torres");
  });

  it("nunca devuelve un nombre vacío", () => {
    expect(nombreLegible("///")).toBe("archivo");
  });

  it("recorta los nombres larguísimos", () => {
    expect(nombreLegible("a".repeat(400)).length).toBe(120);
  });
});

describe("sinRepetidos — dos constancias del mismo día no se pisan dentro del ZIP", () => {
  it("el primero se queda igual y el segundo lleva (2)", () => {
    expect(sinRepetidos(["a.jpg", "a.jpg", "a.jpg"])).toEqual(["a.jpg", "a (2).jpg", "a (3).jpg"]);
  });

  it("no distingue mayúsculas: macOS y Windows tampoco", () => {
    expect(sinRepetidos(["A.jpg", "a.JPG"])).toEqual(["A.jpg", "a (2).JPG"]);
  });

  it("los que no se repiten no se tocan, y el orden se conserva", () => {
    expect(sinRepetidos(["x.pdf", "y.pdf", "x.pdf"])).toEqual(["x.pdf", "y.pdf", "x (2).pdf"]);
  });

  it("sin extensión también", () => {
    expect(sinRepetidos(["recibo", "recibo"])).toEqual(["recibo", "recibo (2)"]);
  });
});
