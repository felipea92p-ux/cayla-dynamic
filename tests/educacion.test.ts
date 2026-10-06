// Las reglas de la constancia de estudios que viven fuera de la base (0450):
// la fecha sugerida, qué archivo se puede enviar y el nombre que va a la ruta.
// Lo que decide el ESTADO de una constancia no está acá: lo prueba la 355.
import { describe, it, expect } from "vitest";
import {
  ESTADO_CONSTANCIA, MOTIVOS_RECHAZO, MOTIVO_RECHAZO_LABELS, TIPOS_CONSTANCIA, TIPO_CONSTANCIA_LABELS,
  VIGENCIA_CORTA_DIAS, constanciaPideAlgoALaIntegrante, diasDeVigencia, finDeCicloSugerido,
  nombreDeArchivoSeguro, problemaDeArchivo, sugerirProximaFecha,
} from "@cayla-dynamic/shared";

describe("finDeCicloSugerido", () => {
  it("de enero a julio: el 31 de julio del mismo año", () => {
    expect(finDeCicloSugerido("2026-01-02")).toBe("2026-07-31");
    expect(finDeCicloSugerido("2026-07-31")).toBe("2026-07-31");
  });
  it("de agosto a diciembre: el 31 de diciembre del mismo año", () => {
    expect(finDeCicloSugerido("2026-08-01")).toBe("2026-12-31");
    expect(finDeCicloSugerido("2026-10-06")).toBe("2026-12-31");
  });
  it("nunca el mismo día en que empieza, salvo que empiece justo al cierre", () => {
    expect(finDeCicloSugerido("2026-09-15")).not.toBe("2026-09-15");
  });
});

describe("diasDeVigencia", () => {
  it("cuenta el primer y el último día", () => {
    expect(diasDeVigencia("2026-09-15", "2026-09-26")).toBe(12);
    expect(diasDeVigencia("2026-10-06", "2026-10-06")).toBe(1);
  });
  it("cruza meses y años sin correrse por el huso", () => {
    expect(diasDeVigencia("2026-12-31", "2027-01-01")).toBe(2);
    expect(diasDeVigencia("2026-03-01", "2026-03-31")).toBe(31);
  });
  it("el caso que lo destapó pregunta; un mes completo no", () => {
    expect(diasDeVigencia("2026-09-15", "2026-09-26")).toBeLessThan(VIGENCIA_CORTA_DIAS);
    expect(diasDeVigencia("2026-10-01", "2026-10-31")).not.toBeLessThan(VIGENCIA_CORTA_DIAS);
  });
});

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
