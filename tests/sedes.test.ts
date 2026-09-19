import { describe, it, expect } from "vitest";
import { etiquetaDeSede, TIPOS_SEDE, TIPO_SEDE_LABELS } from "@cayla-dynamic/shared";

// El caso que motivó esto: el Taller de Lima y la Tienda de Lima comparten
// ciudad y en pantalla solo se veía un código. Los datos son los de la 0099,
// la 0216 y la 0279: LIM es el Taller y la Tienda de Lima nació con código 003.
const TALLER_LIMA = { codigo: "LIM", nombre: "Taller LIM", tipo: "taller", ciudad: "Lima" };
const TIENDA_LIMA = { codigo: "003", nombre: "Tienda LIM", tipo: "tienda", ciudad: "Lima" };

describe("etiquetaDeSede", () => {
  it("el Taller de Lima y la Tienda de Lima no se pueden confundir", () => {
    const taller = etiquetaDeSede(TALLER_LIMA);
    const tienda = etiquetaDeSede(TIENDA_LIMA);
    expect(taller.titulo).toBe("Taller · Lima");
    expect(tienda.titulo).toBe("Tienda · Lima");
    expect(taller.titulo).not.toBe(tienda.titulo);
  });

  it("el rótulo se deriva del tipo: una sede que nadie conocía se rotula sola", () => {
    const nueva = etiquetaDeSede({ codigo: "TRUAS", nombre: "lo que sea", tipo: "tienda", ciudad: "Trujillo" });
    expect(nueva.titulo).toBe("Tienda · Trujillo");
  });

  it("Central no lleva ciudad, ni siquiera si una fila vieja la trae (0282)", () => {
    const central = etiquetaDeSede({ codigo: "CCO", nombre: "Central", tipo: "central", ciudad: "Trujillo" });
    expect(central.titulo).toBe("Central");
  });

  it("sin ciudad no se inventa una: cae al nombre de la sede", () => {
    const sinCiudad = etiquetaDeSede({ codigo: "OTRU", nombre: "Otra sede", tipo: "tienda", ciudad: null });
    expect(sinCiudad.titulo).toBe("Otra sede");
  });

  it("una ciudad en blanco cuenta como ausente", () => {
    const enBlanco = etiquetaDeSede({ codigo: "OTRU", nombre: "Otra sede", tipo: "tienda", ciudad: "   " });
    expect(enBlanco.titulo).toBe("Otra sede");
  });

  it("sin ciudad ni nombre queda el código: el título nunca sale vacío", () => {
    expect(etiquetaDeSede({ codigo: "XY", nombre: "  ", tipo: "taller", ciudad: null }).titulo).toBe("XY");
  });

  it("es total: un tipo desconocido o nulo no lanza y no inventa un tipo", () => {
    expect(etiquetaDeSede({ codigo: "ZZ", nombre: "Zeta", tipo: null, ciudad: "Lima" }).titulo).toBe("Zeta");
    expect(etiquetaDeSede({ codigo: "ZZ", nombre: "Zeta", tipo: "almacen", ciudad: "Lima" }).titulo).toBe("Zeta");
  });

  it("dos tiendas de la misma ciudad comparten título pero el código las separa", () => {
    const sinchiRoca = etiquetaDeSede({ codigo: "TRU", nombre: "Tienda TRU", tipo: "tienda", ciudad: "Trujillo" });
    const avSur = etiquetaDeSede({ codigo: "TRUAS", nombre: "Tienda AS", tipo: "tienda", ciudad: "Trujillo" });
    expect(sinchiRoca.titulo).toBe(avSur.titulo);
    expect(sinchiRoca.texto).not.toBe(avSur.texto);
    expect(sinchiRoca.texto).toBe("Tienda · Trujillo (TRU)");
  });

  it("el código viaja tal cual, sin espacios sobrantes", () => {
    expect(etiquetaDeSede({ ...TALLER_LIMA, codigo: " LIM " }).codigo).toBe("LIM");
  });

  it("todo tipo de sede tiene su palabra en pantalla", () => {
    for (const t of TIPOS_SEDE) expect(TIPO_SEDE_LABELS[t]).toBeTruthy();
  });
});
