// ============================================================================
// educacion-pago-unico-bandeja.test.ts — El pago único llega a la Bandeja con las
// palabras correctas, pasando por la fuente real (armarPendientes)
// ============================================================================
// bandeja-urgencia.test.ts prueba las funciones sueltas. Esto prueba el CAMINO:
// la fila de `fn_educacion_situacion` entra a `armarPendientes` y sale la tarjeta.
// Si alguien reescribe `FilaEducacionBandeja` y pierde `frecuencia_pago` o
// `aprobadas` (otro agente tocó ese archivo a la vez), el TypeScript de este
// archivo deja de compilar y el texto se vuelve a decir «Poner la fecha» a un
// estudio al que ponérsela lo empeora.
//
// El contexto: main se publica sola y la 0549 la pega Felipe a mano. En esa
// ventana, un pago único con constancia aprobada llega «sin calendario».
// ============================================================================
import { describe, expect, it } from "vitest";
import { armarPendientes, FUENTES_VACIAS, type FilaEducacionBandeja } from "../apps/web/lib/admin/bandeja-fuentes";

const HOY = "2026-10-25";

const fila = (over: Partial<FilaEducacionBandeja> = {}): FilaEducacionBandeja => ({
  familia_id: "f1", persona_id: "p1", persona: "Persona de Prueba", sede: "LIM", institucion: "Instituto de Prueba",
  vigencia: "vigente", estado_constancia: "sin_calendario", frecuencia_pago: "unico", aprobadas: 0,
  fecha_pago_constancia: null, plazo: null, pago_proximo: false, proxima_fecha_pago: null, dias_para_pago: null,
  ...over,
});

const tarjeta = (f: FilaEducacionBandeja) => {
  const filas = armarPendientes({ ...FUENTES_VACIAS, educacion: [f] }, { hoy: HOY });
  expect(filas).toHaveLength(1);
  return filas[0];
};

describe("el pago único en la Bandeja", () => {
  it("sin constancia aprobada: falta la fecha, y el botón la pide", () => {
    const t = tarjeta(fila());
    expect(t.titulo).toBe("Pago único sin fecha de pago");
    expect(t.ir.texto).toBe("Poner la fecha");
    expect(t.urgencia).toMatchObject({ plazo: "Sin fecha de pago", nota: "falta la fecha del pago" });
  });

  it("CON constancia aprobada (base de antes de la 0549): no se aconseja una fecha que lo empeoraría", () => {
    const t = tarjeta(fila({ aprobadas: 1 }));
    expect(t.titulo).toBe("Pago único con constancia aprobada");
    expect(t.ir.texto).toBe("Ver estudio");
    expect(t.ir.texto).not.toBe("Poner la fecha");
    expect(t.urgencia).toMatchObject({ plazo: "Sin plazo", nota: "no hace falta una fecha" });
  });

  it("mensual con constancias aprobadas: idéntico a hoy", () => {
    const t = tarjeta(fila({ frecuencia_pago: "mensual", aprobadas: 3 }));
    expect(t.titulo).toBe("Estudio sin calendario de pagos");
    expect(t.ir.texto).toBe("Fijar calendario");
    expect(t.urgencia).toMatchObject({ plazo: "Sin calendario", nota: "falta saber cuándo paga" });
  });
});
