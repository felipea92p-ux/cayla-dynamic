import { describe, it, expect } from "vitest";
import { formularioDeCalendario, haceCuanto, mesesQueCuenta, resumenDelPanel, ultimaAprobada } from "@/lib/admin/educacion-panel";
import type { CoberturaMes } from "@/lib/admin/educacion-meses";
import type { Entrega, Situacion } from "@/lib/admin/educacion-tipos";

const HOY = "2026-10-17";

function sit(over: Partial<Situacion> = {}): Situacion {
  return {
    familia_id: "f1", asignacion_id: "a1", persona_id: "p1", persona: "Diego Narro", sede: "OTRU", rango: "colibri",
    institucion: "Tecsup", beneficiario: "trabajador", beneficiario_nombre: null, monto: 90,
    vigente_desde: "2024-06-03", vigente_hasta: "2027-10-30", vigencia: "vigente", paga: true,
    frecuencia_pago: null, proxima_fecha_pago: null, dias_para_pago: null, pago_proximo: false,
    estado_constancia: "sin_calendario", fecha_pago_constancia: null, plazo: null, dias_para_plazo: null,
    entrega_id: null, entrega_estado: null, entrega_enviada_at: null, entrega_archivos: null,
    aprobadas: 1, aviso_fin_id: null, aviso_fin_motivo: null,
    ...over,
  };
}

function ent(over: Partial<Entrega> = {}): Entrega {
  return {
    id: "e1", asignacion_id: "a1", fecha_pago: "2024-06-01", tipo: "otro",
    proxima_fecha_pago: null, nota: null, estado: "aprobada", origen: "do",
    enviada_at: "2026-10-17T15:05:00Z", enviada_por: "Felipe", revisada_at: null, revisada_por: null,
    retirada_at: null, motivo_categoria: null, motivo_comentario: null, reemplaza_a: null, archivos: [],
    aprobada_at: null, aprobada_por: null, revertida_at: null, revertida_por: null,
    ...over,
  };
}

const cobertura = (entrega_id: string, mes: string): CoberturaMes => ({
  entrega_id, familia_id: "f1", mes, monto: 100, origen: "calculado", motivo: null,
});

describe("ultimaAprobada", () => {
  it("toma la de fecha de pago más reciente y deja pasar las que no están aprobadas", () => {
    const e = [
      ent({ id: "vieja", fecha_pago: "2026-07-30" }),
      ent({ id: "nueva", fecha_pago: "2026-09-30" }),
      ent({ id: "pendiente", fecha_pago: "2026-10-15", estado: "pendiente" }),
      ent({ id: "rechazada", fecha_pago: "2026-10-16", estado: "rechazada" }),
      ent({ id: "retirada", fecha_pago: "2026-10-17", estado: "retirada" }),
    ];
    expect(ultimaAprobada(e)?.id).toBe("nueva");
  });

  it("con el mismo día de pago gana el último envío, y al final el id: no depende del orden de la lista", () => {
    const a = ent({ id: "a", enviada_at: "2026-10-01T10:00:00Z" });
    const b = ent({ id: "b", enviada_at: "2026-10-02T10:00:00Z" });
    expect(ultimaAprobada([a, b])?.id).toBe("b");
    expect(ultimaAprobada([b, a])?.id).toBe("b");
    const c = ent({ id: "c" }), d = ent({ id: "d" });
    expect(ultimaAprobada([c, d])?.id).toBe(ultimaAprobada([d, c])?.id);
  });

  it("sin ninguna aprobada, null", () => {
    expect(ultimaAprobada([])).toBeNull();
    expect(ultimaAprobada([ent({ estado: "pendiente" })])).toBeNull();
  });
});

describe("mesesQueCuenta", () => {
  it("un pago normal cuenta para el mes de su fecha de pago", () => {
    expect(mesesQueCuenta(ent({ fecha_pago: "2024-06-01" }))).toBe("jun 2024");
  });

  it("un pago adelantado dice sus meses, con el año una sola vez si es el mismo", () => {
    const e = ent({ id: "adel", fecha_pago: "2026-07-28" });
    const filas = ["2026-08-01", "2026-09-01", "2026-10-01", "2026-11-01", "2026-12-01"].map((m) => cobertura("adel", m));
    expect(mesesQueCuenta(e, new Map([["adel", filas]]))).toBe("ago – dic 2026");
  });

  it("un pago adelantado que cruza de año dice los dos años", () => {
    const e = ent({ id: "adel", fecha_pago: "2026-11-28" });
    const filas = ["2026-12-01", "2027-01-01", "2027-02-01"].map((m) => cobertura("adel", m));
    expect(mesesQueCuenta(e, new Map([["adel", filas]]))).toBe("dic 2026 – feb 2027");
  });

  it("no depende del orden en que llegaron las filas de cobertura", () => {
    const e = ent({ id: "adel", fecha_pago: "2026-07-28" });
    const filas = ["2026-10-01", "2026-08-01", "2026-09-01"].map((m) => cobertura("adel", m));
    expect(mesesQueCuenta(e, new Map([["adel", filas]]))).toBe("ago – oct 2026");
  });
});

describe("haceCuanto", () => {
  it("dice el mes en palabras", () => {
    expect(haceCuanto("2026-10", HOY)).toBe("este mes");
    expect(haceCuanto("2026-09", HOY)).toBe("el mes pasado");
    expect(haceCuanto("2024-06", HOY)).toBe("hace 28 meses");
    expect(haceCuanto("2026-12", HOY)).toBe("de un mes que todavía no llega");
  });
});

describe("resumenDelPanel", () => {
  it("el caso que lo originó: constancia aprobada de junio de 2024, sin calendario, hoy octubre de 2026", () => {
    const r = resumenDelPanel(sit(), [ent()], HOY);
    expect(r.frase).toContain("No se sabe cuándo toca su próximo pago");
    expect(r.frase).toContain("cierra la asignación");
    expect(r.ultima).toBe("Última constancia aprobada: pago del 01/06/2024, cuenta para jun 2024 (hace 28 meses).");
    expect(r.ojo).toContain("jun 2024");
    expect(r.ojo).toContain("«Aprobadas del ciclo»");
  });

  it("pago ÚNICO sustentado (lo que contesta la 0549): no hay más pagos que sustentar", () => {
    const r = resumenDelPanel(sit({ frecuencia_pago: "unico", estado_constancia: "al_dia", proxima_fecha_pago: null,
      fecha_pago_constancia: null, aprobadas: 1 }), [ent({ fecha_pago: "2026-10-01" })], HOY);
    expect(r.frase).toBe("Pago único registrado: no hay más pagos que sustentar. Si el estudio ya terminó, puedes cerrar la asignación.");
  });

  it("pago único sustentado aunque la base conserve una fecha guardada: sigue siendo uno solo", () => {
    const r = resumenDelPanel(sit({ frecuencia_pago: "unico", estado_constancia: "al_dia", proxima_fecha_pago: "2026-10-25",
      fecha_pago_constancia: null }), null, HOY);
    expect(r.frase).toContain("Pago único registrado");
    expect(r.frase).not.toContain("próximo pago");
  });

  it("pago único SIN fecha: pide la «Fecha del pago», no un calendario", () => {
    const r = resumenDelPanel(sit({ frecuencia_pago: "unico", estado_constancia: "sin_calendario", aprobadas: 0 }), [], HOY);
    expect(r.frase).toContain("Falta la fecha del pago");
    expect(r.frase).toContain("«Fecha del pago»");
    expect(r.frase).not.toContain("calendario");
  });

  it("pago único con su fecha por venir y sin constancia: «su pago único es el…», no «su próximo pago»", () => {
    const r = resumenDelPanel(sit({ frecuencia_pago: "unico", estado_constancia: "al_dia", proxima_fecha_pago: "2026-11-14",
      fecha_pago_constancia: "2026-11-14", aprobadas: 0 }), [], HOY);
    expect(r.frase).toBe("Está al día. Su pago único es el 14/11/2026.");
  });

  it("MENSUAL, ciclo, otra y sin decir NO cambian: su «sin calendario» sigue ambiguo (decisión abierta)", () => {
    for (const frecuencia_pago of ["mensual", "ciclo", "otra", null] as const) {
      const r = resumenDelPanel(sit({ frecuencia_pago, estado_constancia: "sin_calendario" }), null, HOY);
      expect(r.frase).toContain("No se sabe cuándo toca su próximo pago");
    }
  });

  // La frase de siempre, palabra por palabra: lo que NO se tocó no puede moverse sin que esta prueba lo diga.
  const FRASE_DE_SIEMPRE =
    "No se sabe cuándo toca su próximo pago a la institución, así que el sistema todavía no le pide constancia ni cuenta plazos. "
    + "Elige «Paga a su institución» y el «Próximo pago» y guarda el calendario. Si ya no va a pagar más, cierra la asignación.";

  it("mensual, ciclo y otra: IDÉNTICO a hoy, tengan o no constancias aprobadas", () => {
    for (const frecuencia_pago of ["mensual", "ciclo", "otra"] as const) {
      for (const aprobadas of [0, 1, 4]) {
        expect(resumenDelPanel(sit({ frecuencia_pago, estado_constancia: "sin_calendario", aprobadas }), null, HOY).frase)
          .toBe(FRASE_DE_SIEMPRE);
      }
    }
  });

  it("frecuencia en blanco y SIN aprobadas: idéntico a hoy (no hay de qué sospechar un pago único)", () => {
    expect(resumenDelPanel(sit({ frecuencia_pago: null, estado_constancia: "sin_calendario", aprobadas: 0 }), null, HOY).frase)
      .toBe(FRASE_DE_SIEMPRE);
  });

  // La pregunta de Felipe: «si es pago único, ¿para qué me pide calendario?». Puede que nadie haya marcado «Pago único».
  it("frecuencia en blanco CON una constancia aprobada: le dice a DO que si fue un pago único la fecha es opcional", () => {
    const r = resumenDelPanel(sit({ frecuencia_pago: null, estado_constancia: "sin_calendario", aprobadas: 1 }), null, HOY);
    expect(r.frase).toBe(FRASE_DE_SIEMPRE
      + " Ya tiene una constancia aprobada. Si fue un pago único, elige «Pago único» y guarda: la fecha es opcional.");
  });

  // Base de ANTES de la 0549 (main se publica sola; la migración se pega a mano): un pago único con constancia
  // aprobada sigue llegando «sin calendario». Aconsejar «escribe la fecha» lo EMPEORARÍA: pasa a «falta enviar».
  it("pago único «sin calendario» CON constancia aprobada: dice lo cierto y NO aconseja poner una fecha", () => {
    const r = resumenDelPanel(sit({ frecuencia_pago: "unico", estado_constancia: "sin_calendario", aprobadas: 1 }), null, HOY);
    expect(r.frase).toBe("Este pago único ya tiene su constancia aprobada. No hace falta una fecha; si el estudio ya terminó, puedes cerrar la asignación.");
    expect(r.frase).not.toContain("Escribe");
    expect(r.frase).not.toContain("guárdala");
  });

  it("una constancia reciente no levanta el «ojo»", () => {
    const r = resumenDelPanel(sit({ estado_constancia: "al_dia", frecuencia_pago: "mensual", proxima_fecha_pago: "2026-10-30" }),
      [ent({ fecha_pago: "2026-09-30" })], HOY);
    expect(r.frase).toBe("Está al día. Su próximo pago es el 30/10/2026.");
    expect(r.ultima).toContain("el mes pasado");
    expect(r.ojo).toBeNull();
  });

  it("un pago adelantado se mide por su ÚLTIMO mes cubierto, no por el día en que se pagó", () => {
    const e = ent({ id: "adel", fecha_pago: "2026-03-28" });
    const filas = ["2026-04-01", "2026-05-01", "2026-06-01", "2026-07-01", "2026-08-01", "2026-09-01", "2026-10-01"].map((m) => cobertura("adel", m));
    const r = resumenDelPanel(sit({ estado_constancia: "al_dia" }), [e], HOY, new Map([["adel", filas]]));
    expect(r.ultima).toContain("abr – oct 2026");
    expect(r.ultima).toContain("este mes");
    expect(r.ojo).toBeNull();
  });

  it("si el estudio ya terminó no se señala nada: no hay cuadrícula de ahora que mirar", () => {
    const r = resumenDelPanel(sit({ vigencia: "terminada" }), [ent()], HOY);
    expect(r.ojo).toBeNull();
  });

  it("mientras llegan las constancias, solo la frase del estado", () => {
    const r = resumenDelPanel(sit(), null, HOY);
    expect(r.frase).toContain("No se sabe cuándo");
    expect(r.ultima).toBeNull();
    expect(r.ojo).toBeNull();
  });

  it("sin ninguna aprobada lo dice", () => {
    const r = resumenDelPanel(sit({ aprobadas: 0 }), [ent({ estado: "pendiente" })], HOY);
    expect(r.ultima).toBe("Todavía no tiene ninguna constancia aprobada.");
    expect(r.ojo).toBeNull();
  });

  it("los estados que piden algo repiten lo que dijo la base: de qué pago y hasta cuándo", () => {
    for (const estado of ["por_vencer", "vencida", "falta_enviar"] as const) {
      const r = resumenDelPanel(sit({ estado_constancia: estado, fecha_pago_constancia: "2026-10-30", plazo: "2026-11-05" }), [], HOY);
      expect(r.frase).toBe("Falta la constancia del pago del 30/10/2026, plazo 05/11/2026.");
    }
  });

  it("pendiente y rechazada mandan a la revisión y a esperar, sin inventar plazos", () => {
    expect(resumenDelPanel(sit({ estado_constancia: "pendiente_revision" }), [], HOY).frase).toContain("más abajo puedes aprobarla o rechazarla");
    expect(resumenDelPanel(sit({ estado_constancia: "rechazada" }), [], HOY).frase).toContain("se espera que la integrante envíe la corregida");
  });
});

describe("formularioDeCalendario — el bloque «Paga a su institución» del cajón", () => {
  const guardado = (over: Partial<Situacion> = {}) =>
    sit({ frecuencia_pago: "mensual", proxima_fecha_pago: "2026-10-30", estado_constancia: "al_dia", ...over });
  const sustentadoUnico = () =>
    sit({ frecuencia_pago: "unico", proxima_fecha_pago: null, estado_constancia: "al_dia", fecha_pago_constancia: null, aprobadas: 1 });

  it("mensual sin tocar: «Guardar calendario», deshabilitado y con el campo a la vista", () => {
    const f = formularioDeCalendario(guardado(), "mensual", "2026-10-30");
    expect(f).toMatchObject({ esUnico: false, ocultaFecha: false, nota: null, rotuloBoton: "Guardar calendario", sinCambios: true });
  });

  it("elegir «Pago único» sin escribir fecha: el botón dice «Guardar», no «Guardar fecha del pago»", () => {
    // Antes quedaba habilitado diciendo «Guardar fecha del pago» con la fecha vacía solo porque cambió el select.
    const f = formularioDeCalendario(guardado({ estado_constancia: "sin_calendario", proxima_fecha_pago: null }), "unico", "");
    expect(f.rotuloBoton).toBe("Guardar");
    expect(f.sinCambios).toBe(false);
    expect(f.ocultaFecha).toBe(false);
  });

  it("elegir «Pago único» y escribir la fecha: «Guardar fecha del pago»", () => {
    const f = formularioDeCalendario(guardado({ proxima_fecha_pago: null }), "unico", "2026-11-14");
    expect(f.rotuloBoton).toBe("Guardar fecha del pago");
  });

  it("un pago único ya guardado al que solo se le cambia la fecha: «Guardar fecha del pago»", () => {
    const f = formularioDeCalendario(sit({ frecuencia_pago: "unico", proxima_fecha_pago: "2026-11-14" }), "unico", "2026-11-20");
    expect(f.rotuloBoton).toBe("Guardar fecha del pago");
  });

  it("pago único ya sustentado: se esconde el campo y queda solo la frase, sin prometer lo que haga el SQL", () => {
    const f = formularioDeCalendario(sustentadoUnico(), "unico", "");
    expect(f.ocultaFecha).toBe(true);
    expect(f.sinCambios).toBe(true);
    expect(f.nota).toBe("Pago único registrado: no hace falta una fecha. Si hubo un segundo pago, cambia la frecuencia a «Otra» o «Mensual».");
    expect(f.nota).not.toContain("no vuelve a pedir");
  });

  it("si DO cambia la frecuencia de un pago único sustentado a «Otra» o «Mensual», el campo vuelve (hubo un segundo pago)", () => {
    for (const frecuencia of ["otra", "mensual"]) {
      const f = formularioDeCalendario(sustentadoUnico(), frecuencia, "");
      expect(f.ocultaFecha).toBe(false);
      expect(f.nota).toBeNull();
      expect(f.sinCambios).toBe(false);
    }
  });

  it("con la base de antes de la 0549 (pago único con aprobada, aún «sin calendario») el campo NO se esconde", () => {
    const f = formularioDeCalendario(
      sit({ frecuencia_pago: "unico", estado_constancia: "sin_calendario", proxima_fecha_pago: null, aprobadas: 1 }), "unico", "");
    expect(f.ocultaFecha).toBe(false);
    expect(f.nota).toBeNull();
  });
});
