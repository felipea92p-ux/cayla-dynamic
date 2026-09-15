// Las reglas de la constancia de estudios que viven fuera de la base (0450):
// la fecha sugerida, qué archivo se puede enviar y el nombre que va a la ruta.
// Lo que decide el ESTADO de una constancia no está acá: lo prueba la 355.
import { describe, it, expect } from "vitest";
import {
  ESTADO_CONSTANCIA, MOTIVOS_RECHAZO, MOTIVO_RECHAZO_LABELS, TIPOS_CONSTANCIA, TIPO_CONSTANCIA_LABELS,
  constanciaPideAlgoALaIntegrante, nombreDeArchivoSeguro, problemaDeArchivo, sugerirProximaFecha,
} from "@cayla-dynamic/shared";

describe("sugerirProximaFecha", () => {
  it("mensual: el mismo día del mes siguiente", () => {
    expect(sugerirProximaFecha("2026-09-05", "mensual")).toBe("2026-10-05");
  });
  it("mensual: el 31 de enero pasa al último de febrero, no a marzo", () => {
    expect(sugerirProximaFecha("2026-01-31", "mensual")).toBe("2026-02-28");
    expect(sugerirProximaFecha("2028-01-31", "mensual")).toBe("2028-02-29");
  });
  it("mensual: diciembre cruza de año", () => {
    expect(sugerirProximaFecha("2026-12-15", "mensual")).toBe("2027-01-15");
  });
  it("por ciclo, pago único u otra: no se adivina", () => {
    expect(sugerirProximaFecha("2026-09-05", "ciclo")).toBeNull();
    expect(sugerirProximaFecha("2026-09-05", "unico")).toBeNull();
    expect(sugerirProximaFecha("2026-09-05", null)).toBeNull();
  });
});

describe("problemaDeArchivo", () => {
  it("un PDF de hasta 10 MB pasa", () => {
    expect(problemaDeArchivo({ nombre: "c.pdf", tipo: "application/pdf", bytes: 10 * 1024 * 1024 })).toBeNull();
  });
  it("un PDF de más de 10 MB se frena antes de subir", () => {
    expect(problemaDeArchivo({ nombre: "c.pdf", tipo: "application/pdf", bytes: 10 * 1024 * 1024 + 1 })).toMatch(/10 MB/);
  });
  it("una foto pesada pasa: se comprime antes de subir", () => {
    expect(problemaDeArchivo({ nombre: "IMG.jpg", tipo: "image/jpeg", bytes: 30 * 1024 * 1024 })).toBeNull();
  });
  it("la HEIC que Chrome entrega sin tipo se reconoce por la extensión", () => {
    expect(problemaDeArchivo({ nombre: "IMG_0001.HEIC", tipo: "", bytes: 3_000_000 })).toBeNull();
  });
  it("un documento de Word no pasa", () => {
    expect(problemaDeArchivo({ nombre: "constancia.docx", tipo: "application/vnd.openxmlformats-officedocument.wordprocessingml.document", bytes: 1000 }))
      .toMatch(/PDF, JPG o PNG/);
  });
});

describe("nombreDeArchivoSeguro", () => {
  it("quita acentos, espacios y símbolos y conserva la extensión", () => {
    expect(nombreDeArchivoSeguro("Constancia de matrícula (sept).PDF")).toBe("Constancia-de-matricula-sept.pdf");
  });
  it("puede forzar la extensión de lo que se convirtió", () => {
    expect(nombreDeArchivoSeguro("IMG_0001.HEIC", "jpg")).toBe("IMG_0001.jpg");
  });
  it("un nombre vacío no deja una ruta vacía", () => {
    expect(nombreDeArchivoSeguro("???.png")).toBe("archivo.png");
  });
});

describe("catálogos", () => {
  it("cada tipo y cada motivo tiene su etiqueta", () => {
    for (const t of TIPOS_CONSTANCIA) expect(TIPO_CONSTANCIA_LABELS[t]).toBeTruthy();
    for (const m of MOTIVOS_RECHAZO) expect(MOTIVO_RECHAZO_LABELS[m]).toBeTruthy();
  });
  it("rojo solo para lo vencido y lo rechazado", () => {
    const rojos = Object.entries(ESTADO_CONSTANCIA).filter(([, v]) => v.tono === "alerta").map(([k]) => k).sort();
    expect(rojos).toEqual(["rechazada", "vencida"]);
  });
  it("pendiente de revisión y al día no le piden nada a la integrante", () => {
    expect(constanciaPideAlgoALaIntegrante("pendiente_revision")).toBe(false);
    expect(constanciaPideAlgoALaIntegrante("al_dia")).toBe(false);
    expect(constanciaPideAlgoALaIntegrante("por_vencer")).toBe(true);
  });
});
