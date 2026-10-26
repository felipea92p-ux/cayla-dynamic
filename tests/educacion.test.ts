// Las reglas de la constancia de estudios que viven fuera de la base (0450):
// la fecha sugerida, qué archivo se puede enviar y el nombre que va a la ruta.
// Lo que decide el ESTADO de una constancia no está acá: lo prueba la 355.
import { describe, it, expect } from "vitest";
import {
  ESTADO_CONSTANCIA, MOTIVOS_RECHAZO, MOTIVO_RECHAZO_LABELS, TIPOS_CONSTANCIA, TIPO_CONSTANCIA_LABELS,
  VIGENCIA_CORTA_DIAS, constanciaPideAlgoALaIntegrante, diasDeVigencia, finDeCicloSugerido,
  esPagoUnicoAprobadoSinFecha, esPagoUnicoSustentado, insigniaDeEstadoConstancia,
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

// ── Un pago único tiene una fecha, no un calendario (0549) ──────────────────
describe("esPagoUnicoSustentado — lee lo que la base contestó, no recalcula", () => {
  const base = { frecuencia_pago: "unico", estado_constancia: "al_dia", fecha_pago_constancia: null };

  it("pago único + al día + sin fecha de constancia: lo que la 0549 le contesta a uno ya sustentado", () => {
    expect(esPagoUnicoSustentado(base)).toBe(true);
  });

  it("con la 0549 SIN pegar nunca da true: un «al día» de antes siempre traía su fecha", () => {
    expect(esPagoUnicoSustentado({ ...base, fecha_pago_constancia: "2026-11-14" })).toBe(false);
  });

  it("otra frecuencia, o ninguna, nunca es «pago único sustentado»", () => {
    for (const frecuencia_pago of ["mensual", "ciclo", "otra", null, undefined]) {
      expect(esPagoUnicoSustentado({ ...base, frecuencia_pago })).toBe(false);
    }
  });

  it("solo «al día»: lo que pide algo o espera revisión no se da por sustentado", () => {
    for (const estado_constancia of ["sin_calendario", "vencida", "falta_enviar", "rechazada", "pendiente_revision"]) {
      expect(esPagoUnicoSustentado({ ...base, estado_constancia })).toBe(false);
    }
  });
});

describe("insigniaDeEstadoConstancia — solo cambia la palabra", () => {
  it("un pago único «sin calendario» dice «Sin fecha de pago», con el mismo tono", () => {
    expect(insigniaDeEstadoConstancia("sin_calendario", "unico"))
      .toEqual({ etiqueta: "Sin fecha de pago", tono: ESTADO_CONSTANCIA.sin_calendario.tono });
  });

  it("mensual, ciclo, otra y sin decir siguen diciendo «Sin calendario de pagos» (su NULL sigue ambiguo)", () => {
    for (const f of ["mensual", "ciclo", "otra", null, undefined]) {
      expect(insigniaDeEstadoConstancia("sin_calendario", f)).toEqual(ESTADO_CONSTANCIA.sin_calendario);
    }
  });

  it("los demás estados no cambian con la frecuencia", () => {
    expect(insigniaDeEstadoConstancia("al_dia", "unico")).toEqual(ESTADO_CONSTANCIA.al_dia);
    expect(insigniaDeEstadoConstancia("vencida", "unico")).toEqual(ESTADO_CONSTANCIA.vencida);
  });
});

// ── La ventana entre publicar las pantallas y pegar la 0549 ─────────────────
// Main se publica sola y la migración la pega Felipe a mano: durante un rato las
// pantallas nuevas leen una base vieja, donde un pago único con constancia
// aprobada sigue llegando como «sin calendario». Ahí «escribe la fecha» EMPEORA.
describe("esPagoUnicoAprobadoSinFecha — solo existe con la base de antes de la 0549", () => {
  it("pago único + sin calendario + alguna aprobada", () => {
    expect(esPagoUnicoAprobadoSinFecha("sin_calendario", "unico", 1)).toBe(true);
    expect(esPagoUnicoAprobadoSinFecha("sin_calendario", "unico", 3)).toBe(true);
  });

  it("sin aprobadas, o sin saber cuántas, falta la fecha de verdad", () => {
    expect(esPagoUnicoAprobadoSinFecha("sin_calendario", "unico", 0)).toBe(false);
    expect(esPagoUnicoAprobadoSinFecha("sin_calendario", "unico", null)).toBe(false);
    expect(esPagoUnicoAprobadoSinFecha("sin_calendario", "unico", undefined)).toBe(false);
  });

  it("otra frecuencia, u otro estado, no", () => {
    for (const f of ["mensual", "ciclo", "otra", null, undefined]) {
      expect(esPagoUnicoAprobadoSinFecha("sin_calendario", f, 2)).toBe(false);
    }
    for (const e of ["al_dia", "vencida", "falta_enviar", "rechazada", "pendiente_revision", "por_vencer"]) {
      expect(esPagoUnicoAprobadoSinFecha(e, "unico", 2)).toBe(false);
    }
  });

  it("nunca coincide con el pago único sustentado de la 0549: son dos épocas distintas de la base", () => {
    expect(esPagoUnicoSustentado({ frecuencia_pago: "unico", estado_constancia: "sin_calendario", fecha_pago_constancia: null })).toBe(false);
  });
});

describe("insigniaDeEstadoConstancia con las constancias aprobadas", () => {
  it("pago único «sin calendario» con una aprobada: no dice que falte una fecha", () => {
    expect(insigniaDeEstadoConstancia("sin_calendario", "unico", 1))
      .toEqual({ etiqueta: "Pago único con constancia", tono: ESTADO_CONSTANCIA.sin_calendario.tono });
  });

  it("sin aprobadas (o sin dato) sigue diciendo «Sin fecha de pago»", () => {
    for (const a of [0, null, undefined]) {
      expect(insigniaDeEstadoConstancia("sin_calendario", "unico", a).etiqueta).toBe("Sin fecha de pago");
    }
  });

  it("mensual, ciclo, otra y sin decir NO cambian por tener aprobadas", () => {
    for (const f of ["mensual", "ciclo", "otra", null, undefined]) {
      expect(insigniaDeEstadoConstancia("sin_calendario", f, 5)).toEqual(ESTADO_CONSTANCIA.sin_calendario);
    }
  });
});
