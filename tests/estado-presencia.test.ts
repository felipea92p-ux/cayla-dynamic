// ============================================================================
// estado-presencia.test.ts — «en qué punto del día está cada integrante»
// ============================================================================
// El terminal pinta a cada persona como Laborando, En refrigerio, En pausa,
// Turno terminado o Sin entrada. Eso se DERIVA de los marcajes (`estadoPresencia`)
// y la decisión de qué marca le toca la sigue tomando `determinarSiguienteAccion`.
//
// Lo que más importa acá no es cada caso suelto sino que las dos funciones NO
// puedan contradecirse: si la pantalla dice «Laborando» y el terminal le ofrece
// «Volver», alguien marca lo que no es. Por eso la última prueba las cruza con
// todas las secuencias posibles de marcas de un día.
// ============================================================================
import { describe, it, expect } from "vitest";
import {
  ESTADO_PRESENCIA_LABELS,
  MOTIVO_PAUSA_LABELS,
  PARES_SALIDA_RETORNO,
  TIPOS_MARCA,
  determinarSiguienteAccion,
  estadoPresencia,
  type MarcajeDelDia,
  type TipoMarca,
} from "@cayla-dynamic/shared";

// Hora de Lima → instante real (Lima = UTC-5), con la fecha fija de las pruebas.
const m = (tipo: TipoMarca, hora: string): MarcajeDelDia => ({
  tipo,
  timestamp: `2026-10-05T${hora}:00-05:00`,
});

describe("estadoPresencia", () => {
  it("sin ninguna marca: sin entrada", () => {
    expect(estadoPresencia([])).toEqual({ estado: "sin_entrada" });
  });

  it("solo la entrada: laborando, con la hora de esa entrada", () => {
    const e = m("entrada", "08:02");
    expect(estadoPresencia([e])).toEqual({ estado: "laborando", entrada: e.timestamp });
  });

  it("salió a refrigerio y no volvió: en refrigerio", () => {
    const s = m("salida_almuerzo", "13:00");
    expect(estadoPresencia([m("entrada", "08:00"), s])).toEqual({ estado: "refrigerio", desde: s.timestamp });
  });

  it("volvió del refrigerio: sigue laborando Y NO SE PIERDE la entrada de la mañana", () => {
    // Si solo se guardara la hora del regreso, la casilla diría «desde 13:45» y
    // parecería que llegó a esa hora: tarde. La mañana trabajada desaparecería.
    const e = m("entrada", "08:00");
    const sa = m("salida_almuerzo", "13:00");
    const r = m("retorno_almuerzo", "13:45");
    expect(estadoPresencia([e, sa, r])).toEqual({
      estado: "laborando",
      entrada: e.timestamp,
      // Con la salida de la que volvió: «volvió 13:45» solo no dice de cuándo a cuándo.
      regreso: { volvio: r.timestamp, salio: sa.timestamp },
    });
  });

  it("con varias salidas y regresos: la entrada es la primera y el regreso se empareja con SU salida", () => {
    const e = m("entrada", "08:00");
    const s2 = m("salida_tramite", "15:30");
    const r2 = m("retorno_tramite", "16:10");
    const r = estadoPresencia([e, m("salida_almuerzo", "12:00"), m("retorno_almuerzo", "13:00"), s2, r2]);
    // El regreso es el del trámite y su salida la del trámite: NO la del refrigerio de la mañana.
    expect(r).toEqual({ estado: "laborando", entrada: e.timestamp, regreso: { volvio: r2.timestamp, salio: s2.timestamp } });
  });

  it("un regreso sin su salida (datos incompletos) no inventa una salida", () => {
    const e = m("entrada", "08:00");
    const r = m("retorno_almuerzo", "13:45");
    expect(estadoPresencia([e, r])).toEqual({ estado: "laborando", entrada: e.timestamp, regreso: { volvio: r.timestamp } });
  });

  it("si hay dos salidas del mismo tipo, el regreso se empareja con la más reciente", () => {
    const e = m("entrada", "08:00");
    const s2 = m("salida_tramite", "15:00");
    const r2 = m("retorno_tramite", "15:30");
    const r = estadoPresencia([e, m("salida_tramite", "10:00"), m("retorno_tramite", "10:20"), s2, r2]);
    expect(r).toMatchObject({ regreso: { salio: s2.timestamp, volvio: r2.timestamp } });
  });

  it.each(["salida_personal", "salida_tramite", "salida_medico", "salida_otro"] as const)(
    "salió por %s y no volvió: en pausa, con su motivo",
    (tipo) => {
      const s = m(tipo, "14:08");
      expect(estadoPresencia([m("entrada", "08:00"), s])).toEqual({ estado: "pausa", motivo: tipo, desde: s.timestamp });
    },
  );

  it("la salida final cierra el turno", () => {
    const f = m("salida_final", "18:02");
    expect(estadoPresencia([m("entrada", "08:00"), f])).toEqual({ estado: "termino", a: f.timestamp });
  });

  it("no depende del orden en que lleguen las marcas", () => {
    const marcas = [m("salida_almuerzo", "13:00"), m("entrada", "08:00")];
    expect(estadoPresencia(marcas).estado).toBe("refrigerio");
  });

  it("no modifica la lista que recibe", () => {
    const marcas = [m("salida_almuerzo", "13:00"), m("entrada", "08:00")];
    const antes = JSON.stringify(marcas);
    estadoPresencia(marcas);
    expect(JSON.stringify(marcas)).toBe(antes);
  });

  it("una marca suelta sin entrada (ej. un retorno huérfano) NO se pinta como laborando", () => {
    // Igual que la máquina: sin entrada, lo único que se ofrece es la entrada.
    expect(estadoPresencia([m("retorno_almuerzo", "13:45")]).estado).toBe("sin_entrada");
  });
});

describe("las etiquetas", () => {
  it("hay una por cada estado, y ninguna vacía", () => {
    expect(Object.keys(ESTADO_PRESENCIA_LABELS).sort()).toEqual(
      ["laborando", "pausa", "refrigerio", "sin_entrada", "termino"],
    );
    for (const etiqueta of Object.values(ESTADO_PRESENCIA_LABELS)) expect(etiqueta.length).toBeGreaterThan(0);
  });

  it("cada salida temporal que no es refrigerio tiene su motivo en corto", () => {
    const salidasDePausa = Object.keys(PARES_SALIDA_RETORNO).filter((t) => t !== "salida_almuerzo");
    for (const t of salidasDePausa) expect(MOTIVO_PAUSA_LABELS[t as TipoMarca], t).toBeTruthy();
  });
});

describe("estadoPresencia ↔ determinarSiguienteAccion: nunca se contradicen", () => {
  // Todas las secuencias de hasta 4 marcas sacadas de los 12 tipos, en orden de
  // hora creciente. Son 12^1 + … + 12^4 ≈ 22 000 casos; corre en milisegundos.
  function* secuencias(max: number): Generator<MarcajeDelDia[]> {
    yield [];
    let nivel: MarcajeDelDia[][] = [[]];
    for (let largo = 1; largo <= max; largo++) {
      const siguiente: MarcajeDelDia[][] = [];
      for (const base of nivel) {
        for (const tipo of TIPOS_MARCA) {
          const hora = String(7 + base.length * 2).padStart(2, "0");
          siguiente.push([...base, m(tipo, `${hora}:00`)]);
        }
      }
      for (const s of siguiente) yield s;
      nivel = siguiente;
    }
  }

  it("para toda secuencia, lo que se pinta corresponde a lo que se ofrece", () => {
    let revisadas = 0;
    for (const marcas of secuencias(4)) {
      const presencia = estadoPresencia(marcas);
      const accion = determinarSiguienteAccion(marcas);
      const detalle = `${marcas.map((x) => x.tipo).join(" → ") || "(sin marcas)"}`;

      switch (presencia.estado) {
        case "sin_entrada":
          expect(accion, detalle).toEqual({ modo: "unico", tipo: "entrada" });
          break;
        case "termino":
          expect(accion.modo, detalle).toBe("cerrado");
          break;
        case "laborando":
          expect(accion.modo, detalle).toBe("elegir_salida");
          break;
        case "refrigerio":
          expect(accion, detalle).toMatchObject({ modo: "unico", tipo: "retorno_almuerzo" });
          break;
        case "pausa":
          expect(accion, detalle).toMatchObject({ modo: "unico", tipo: PARES_SALIDA_RETORNO[presencia.motivo] });
          break;
      }
      revisadas++;
    }
    expect(revisadas).toBeGreaterThan(20_000);
  });
});
