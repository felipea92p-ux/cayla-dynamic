import { describe, it, expect } from "vitest";
import { extensionDeArchivo, nombreEnZip, nombreLegible, sinRepetidos } from "@/lib/admin/zip-constancias";

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

describe("extensionDeArchivo — sale del tipo verificado, no del nombre que puso quien subió el archivo", () => {
  it("por el tipo que guardó el almacén", () => {
    expect(extensionDeArchivo({ tipo_mime: "image/jpeg", ruta: "educacion/p/entregas/e/1-foto.jpg" })).toBe("jpg");
    expect(extensionDeArchivo({ tipo_mime: "application/pdf", ruta: "x/1-boleta.pdf" })).toBe("pdf");
    expect(extensionDeArchivo({ tipo_mime: "image/png", ruta: "x/2.png" })).toBe("png");
  });

  it("una HEIC que el sistema recomprimió a JPG viaja como .jpg, no como .heic", () => {
    expect(extensionDeArchivo({ tipo_mime: "image/jpeg", ruta: "x/1-IMG-0001.jpg" })).toBe("jpg");
  });

  it("sin tipo (filas migradas) usa la ruta, pero solo si es una extensión conocida", () => {
    expect(extensionDeArchivo({ tipo_mime: null, ruta: "x/1-recibo.PDF" })).toBe("pdf");
    expect(extensionDeArchivo({ tipo_mime: null, ruta: "x/1-virus.exe" })).toBe("bin");
    expect(extensionDeArchivo({ tipo_mime: null, ruta: "x/1-sin-extension" })).toBe("bin");
  });

  it("un tipo raro no deja pasar la extensión de la ruta si esta no es conocida", () => {
    expect(extensionDeArchivo({ tipo_mime: "text/html", ruta: "x/1-pagina.html" })).toBe("bin");
  });
});

describe("nombreEnZip — se recorta la cabeza, nunca la cola", () => {
  it("un nombre corto queda completo", () => {
    expect(nombreEnZip("Sandra Ramírez", "Duolingo", "2026-09-30", 1, "jpg")).toBe("Sandra Ramírez - Duolingo - 2026-09-30 - 1.jpg");
  });

  it("con persona e institución larguísimas, la fecha, el número y la extensión sobreviven", () => {
    const largo = nombreEnZip(
      "María del Carmen Fernández de la Cruz",
      "Universidad Peruana de Ciencias Aplicadas - Facultad de Ciencias Económicas y Empresariales",
      "2026-09-30", 2, "pdf",
    );
    expect(largo.endsWith(" - 2026-09-30 - 2.pdf")).toBe(true);
    expect(largo.length).toBeLessThanOrEqual(120 - 6 + 0);
  });

  it("tres constancias de fechas distintas NUNCA dan el mismo nombre, por largo que sea el resto", () => {
    const nombres = ["2026-07-30", "2026-08-30", "2026-09-30"].map((f) =>
      nombreEnZip("María del Carmen Fernández de la Cruz", "Universidad Peruana de Ciencias Aplicadas - Facultad de Ciencias Económicas", f, 1, "jpg"));
    expect(new Set(nombres).size).toBe(3);
  });

  it("no deja caracteres que un sistema de archivos rechace", () => {
    expect(nombreEnZip('Ana "la" Torres', "Colegio / Lima: A?", "2026-09-30", 1, "jpg")).not.toMatch(/[\\/:*?"<>|]/);
  });
});
