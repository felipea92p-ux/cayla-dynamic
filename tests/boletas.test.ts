// ============================================================================
// boletas.test.ts — las reglas de la boleta oficial que dibujan las pantallas
// ============================================================================
// Lo que decide la pantalla (¿avisa esta edición?, ¿pasa el tope?, ¿qué estado
// muestra?) lo vuelve a decidir la base (migración 0482, prueba 380) y la base
// gana. Estas pruebas cuidan que la pantalla no MIENTA: que no ofrezca «no
// avisar» donde la base lo va a ignorar, ni pinte «confirmada» sobre una boleta
// que no lo está.
// ============================================================================
import { describe, it, expect } from "vitest";
import {
  cambiosEntreVersiones, contarTablero, editaAvisa, esBoletaNueva, estadoVisible, etiquetaDeHojas,
  extensionPorMime, problemaConLasHojas, puedeElegirNoAvisar, rutaDeHoja,
  TOPE_ARCHIVO_BYTES, TOPE_BOLETA_BYTES,
} from "@/lib/boletas";

const PERIODO = "00000000-0000-0000-0000-0000000ef001";
const PERSONA = "00000000-0000-0000-0000-0000000ea002";
const MB = 1024 * 1024;

describe("estadoVisible", () => {
  it("distingue sin fila de boleta según el grupo esté pagado o no", () => {
    expect(estadoVisible({ estado: "falta", grupo_pagado: true })).toBe("falta");
    expect(estadoVisible({ estado: "falta", grupo_pagado: false })).toBe("sin_pago");
    expect(estadoVisible({ estado: null, grupo_pagado: true })).toBe("falta");
  });

  it("una publicada pasa de «sin abrir» a «vista» a «confirmada» según las dos fechas", () => {
    expect(estadoVisible({ estado: "publicada" })).toBe("publicada");
    expect(estadoVisible({ estado: "publicada", vista_at: "2026-09-01T10:00:00Z" })).toBe("vista");
    expect(estadoVisible({ estado: "publicada", vista_at: "2026-09-01T10:00:00Z", recibida_at: "2026-09-02T10:00:00Z" })).toBe("confirmada");
  });

  it("una fecha de acuse NO le cambia el estado a lo que no está publicado", () => {
    // Un borrador o una anulada nunca deben pintarse «confirmada», aunque una
    // versión vieja tuviera acuse: la persona no la ve.
    expect(estadoVisible({ estado: "borrador", vista_at: "x", recibida_at: "y" })).toBe("borrador");
    expect(estadoVisible({ estado: "anulada", vista_at: "x", recibida_at: "y" })).toBe("anulada");
    expect(estadoVisible({ estado: "papel" })).toBe("papel");
  });
});

describe("cambiosEntreVersiones", () => {
  it("las mismas hojas en el mismo orden no cambian nada", () => {
    expect(cambiosEntreVersiones(["a", "b"], ["a", "b"])).toEqual({ contenido: false, orden: false, igual: true });
  });

  it("las mismas hojas en otro orden es solo un cambio de orden", () => {
    expect(cambiosEntreVersiones(["a", "b"], ["b", "a"])).toEqual({ contenido: false, orden: true, igual: false });
  });

  it("agregar o quitar una hoja cambia el contenido", () => {
    expect(cambiosEntreVersiones(["a"], ["a", "b"]).contenido).toBe(true);
    expect(cambiosEntreVersiones(["a", "b"], ["b"]).contenido).toBe(true);
  });

  it("cambiar una hoja por otra (mismo número de hojas) también es contenido nuevo", () => {
    expect(cambiosEntreVersiones(["a", "b"], ["a", "c"]).contenido).toBe(true);
  });

  it("no altera los arreglos que recibe", () => {
    const v = ["b", "a"];
    cambiosEntreVersiones(v, ["a", "b"]);
    expect(v).toEqual(["b", "a"]);
  });
});

describe("editaAvisa — espeja fn_boleta_guardar_version (0482)", () => {
  const solo_orden = cambiosEntreVersiones(["a", "b"], ["b", "a"]);
  const contenido = cambiosEntreVersiones(["a"], ["a", "b"]);

  it("un borrador no avisa a nadie, pase lo que pase", () => {
    expect(editaAvisa({ publicada: false, cambios: contenido, quiereAvisar: true })).toBe(false);
  });

  it("si cambió el contenido de una publicada, SIEMPRE avisa, aunque DO diga que no", () => {
    expect(editaAvisa({ publicada: true, cambios: contenido, quiereAvisar: false })).toBe(true);
  });

  it("si solo se reordenó, avisa lo que diga DO", () => {
    expect(editaAvisa({ publicada: true, cambios: solo_orden, quiereAvisar: false })).toBe(false);
    expect(editaAvisa({ publicada: true, cambios: solo_orden, quiereAvisar: true })).toBe(true);
  });

  it("«no avisar» solo se ofrece cuando de verdad se puede", () => {
    expect(puedeElegirNoAvisar({ publicada: true, cambios: solo_orden })).toBe(true);
    expect(puedeElegirNoAvisar({ publicada: true, cambios: contenido })).toBe(false);
    expect(puedeElegirNoAvisar({ publicada: false, cambios: solo_orden })).toBe(false);
  });
});

describe("problemaConLasHojas", () => {
  const foto = (bytes = 500 * 1024) => ({ bytes, mime: "image/jpeg" });
  const pdf = (bytes = 200 * 1024) => ({ bytes, mime: "application/pdf" });

  it("sin hojas no hay boleta, y el mensaje habla del tipo elegido", () => {
    expect(problemaConLasHojas("imagen", [])).toBe("Agrega al menos una foto.");
    expect(problemaConLasHojas("pdf", [])).toBe("Agrega al menos un PDF.");
  });

  it("fotos con fotos y PDF con PDF; no se mezclan", () => {
    expect(problemaConLasHojas("imagen", [foto(), foto()])).toBeNull();
    expect(problemaConLasHojas("pdf", [pdf(), pdf()])).toBeNull();
    expect(problemaConLasHojas("imagen", [foto(), pdf()])).toMatch(/mismo tipo/);
    expect(problemaConLasHojas("pdf", [pdf(), foto()])).toMatch(/mismo tipo/);
  });

  it("50 MB por archivo pasa; 50 MB + 1 no", () => {
    expect(problemaConLasHojas("pdf", [pdf(TOPE_ARCHIVO_BYTES)])).toBeNull();
    expect(problemaConLasHojas("pdf", [pdf(TOPE_ARCHIVO_BYTES + 1)])).toMatch(/50 MB/);
  });

  it("500 MB por boleta pasa; 500 MB + 1 no", () => {
    // Diez PDF de 50 MB = 500 MB justos.
    expect(problemaConLasHojas("pdf", Array.from({ length: 10 }, () => pdf(50 * MB)))).toBeNull();
    expect(problemaConLasHojas("pdf", [...Array.from({ length: 10 }, () => pdf(50 * MB)), pdf(1)])).toMatch(/500 MB/);
    expect(TOPE_BOLETA_BYTES).toBe(500 * MB);
  });

  it("no hay tope por cantidad de hojas: cien fotos livianas entran", () => {
    expect(problemaConLasHojas("imagen", Array.from({ length: 100 }, () => foto()))).toBeNull();
  });
});

describe("etiquetaDeHojas", () => {
  it("singular y plural, por tipo", () => {
    expect(etiquetaDeHojas("imagen", 1)).toBe("1 foto");
    expect(etiquetaDeHojas("imagen", 3)).toBe("3 fotos");
    expect(etiquetaDeHojas("pdf", 1)).toBe("1 PDF");
    expect(etiquetaDeHojas("pdf", 2)).toBe("2 PDF");
  });
});

describe("rutaDeHoja — la forma que exige la 0482", () => {
  // La misma expresión que el `check` de `boletas_partes.storage_path`.
  const FORMA_BD = /^[0-9a-f-]{36}\/[0-9a-f-]{36}\/[0-9a-f-]{36}\.[a-z0-9]{2,5}$/;

  it("arma <periodo>/<persona>/<uuid>.<ext> y cumple el check de la base", () => {
    const r = rutaDeHoja(PERIODO, PERSONA, "jpg");
    expect(r).toMatch(FORMA_BD);
    expect(r.startsWith(`${PERIODO}/${PERSONA}/`)).toBe(true);
  });

  it("cada hoja lleva un uuid nuevo: un archivo ya usado nunca se pisa", () => {
    expect(rutaDeHoja(PERIODO, PERSONA, "jpg")).not.toBe(rutaDeHoja(PERIODO, PERSONA, "jpg"));
  });

  it("normaliza la extensión", () => {
    expect(rutaDeHoja(PERIODO, PERSONA, ".JPG", "f0000000-0000-0000-0000-000000000001"))
      .toBe(`${PERIODO}/${PERSONA}/f0000000-0000-0000-0000-000000000001.jpg`);
  });

  it("solo ids: un nombre o un DNI en la ruta se rechaza", () => {
    expect(() => rutaDeHoja("agosto-2026", PERSONA, "jpg")).toThrow();
    expect(() => rutaDeHoja(PERIODO, "45012345", "jpg")).toThrow();
  });
});

describe("extensionPorMime", () => {
  it("conoce lo que admite el bucket y nada más", () => {
    expect(extensionPorMime("image/jpeg")).toBe("jpg");
    expect(extensionPorMime("image/png")).toBe("png");
    expect(extensionPorMime("image/webp")).toBe("webp");
    expect(extensionPorMime("image/heic")).toBe("heic");
    expect(extensionPorMime("application/pdf")).toBe("pdf");
    expect(extensionPorMime("application/zip")).toBeNull();
    expect(extensionPorMime("")).toBeNull();
  });
});

describe("contarTablero", () => {
  it("cuenta a cada quien una sola vez y separa lo que falta de lo que no toca", () => {
    const c = contarTablero([
      { estado: "publicada" },                                                 // con boleta
      { estado: "publicada", vista_at: "x" },                                  // con boleta
      { estado: "publicada", vista_at: "x", recibida_at: "y" },                // con boleta, confirmada
      { estado: "papel" },                                                     // con boleta
      { estado: "borrador" },                                                  // sin publicar
      { estado: "falta", grupo_pagado: true },                                 // falta
      { estado: "anulada" },                                                   // falta
      { estado: "falta", grupo_pagado: false },                                // su grupo no está pagado: no «falta»
    ]);
    expect(c).toEqual({ total: 8, conBoleta: 4, sinPublicar: 1, faltan: 2, confirmadas: 1 });
  });
});

describe("esBoletaNueva", () => {
  it("nueva = publicada y todavía sin abrir", () => {
    expect(esBoletaNueva({ estado: "publicada", vista_at: null })).toBe(true);
    expect(esBoletaNueva({ estado: "publicada", vista_at: "x" })).toBe(false);
    expect(esBoletaNueva({ estado: "papel", vista_at: null })).toBe(false);
    expect(esBoletaNueva({ estado: null, vista_at: null })).toBe(false);
  });
});
