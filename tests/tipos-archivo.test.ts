// ============================================================================
// tipos-archivo.test.ts — La foto del iPhone que el navegador no sabe nombrar
// ============================================================================
// Los tres buckets del almacén tienen lista CERRADA de formatos, y la función
// que guarda las actas de descanso también. Si el tipo que se declara no está
// en esa lista, el papel se rechaza:
//
//     415 · mime type application/octet-stream is not supported
//
// Y Chrome no reconoce el `.HEIC` —el formato en que un iPhone guarda sus
// fotos—, así que entrega el archivo SIN tipo. Desde la pantalla eso se veía
// como «no me deja subir el archivo», sin nada que la persona pudiera hacer:
// la foto era correcta y el permiso también.
//
// Medido el 2026-08-06 contra el almacén local, la MISMA foto:
//     declarada image/heic  → sube
//     sin tipo (Chrome)     → 415
//     declarada image/heif  → 415  (los buckets solo listan image/heic)
//
// POR QUÉ ESTE ARCHIVO. La corrección es una tabla de siete líneas, y ese es
// justo el tipo de código que alguien "limpia" sin saber qué sostenía. Si se
// cae esta prueba, lo que se rompió es que en las sedes no se pueden archivar
// los papeles firmados — y eso no se nota hasta que hace falta el papel.

import { describe, it, expect } from "vitest";
import { tipoDeArchivo, conTipoCorregido } from "@/lib/tipos-archivo";

describe("tipoDeArchivo", () => {
  it("Chrome no reconoce el .HEIC y no da tipo: se deduce de la extensión", () => {
    expect(tipoDeArchivo("IMG_7355.HEIC", "")).toBe("image/heic");
  });

  it("y tampoco cuando lo llama binario genérico", () => {
    expect(tipoDeArchivo("IMG_7355.HEIC", "application/octet-stream")).toBe("image/heic");
  });

  it("Safari sí lo reconoce: se respeta lo que dice el navegador", () => {
    expect(tipoDeArchivo("IMG_7355.HEIC", "image/heic")).toBe("image/heic");
  });

  it(".heif se declara como image/heic — los buckets no listan image/heif", () => {
    // Mismo contenedor, distinto nombre. Declararlo tal cual da 415.
    expect(tipoDeArchivo("foto.heif", "image/heif")).toBe("image/heic");
    expect(tipoDeArchivo("foto.HEIF", "")).toBe("image/heic");
  });

  it("la extensión se lee sin importar mayúsculas", () => {
    expect(tipoDeArchivo("ACTA.PDF", "")).toBe("application/pdf");
    expect(tipoDeArchivo("cargo.JPG", "")).toBe("image/jpeg");
  });

  it("un PDF o un JPEG normales pasan intactos", () => {
    expect(tipoDeArchivo("acta.pdf", "application/pdf")).toBe("application/pdf");
    expect(tipoDeArchivo("foto.jpg", "image/jpeg")).toBe("image/jpeg");
  });

  it("una extensión desconocida se deja como venga: decide el servidor", () => {
    // Preferimos el mensaje del almacén a inventar un tipo acá. Un .exe no debe
    // colarse como imagen por una traducción nuestra.
    expect(tipoDeArchivo("virus.exe", "application/octet-stream")).toBe("application/octet-stream");
    expect(tipoDeArchivo("sin-extension", "")).toBe("");
  });
});

describe("conTipoCorregido · el acta que va como texto a la base", () => {
  it("corrige la cabecera de un HEIC que llegó sin tipo", () => {
    expect(conTipoCorregido("data:application/octet-stream;base64,QUJD", "IMG_1.HEIC"))
      .toBe("data:image/heic;base64,QUJD");
  });

  it("no toca un data URL que ya venía bien", () => {
    const bueno = "data:application/pdf;base64,QUJD";
    expect(conTipoCorregido(bueno, "acta.pdf")).toBe(bueno);
  });

  it("deja intacto lo que no sabe traducir, para que la base dé su mensaje", () => {
    const raro = "data:application/octet-stream;base64,QUJD";
    expect(conTipoCorregido(raro, "cosa.xyz")).toBe(raro);
  });

  it("un texto que no es un data URL no rompe nada", () => {
    expect(conTipoCorregido("esto no es un data url", "x.heic")).toBe("esto no es un data url");
  });
});
