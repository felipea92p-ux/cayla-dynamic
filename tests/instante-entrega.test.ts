// ============================================================================
// instante-entrega.test.ts — La hora de una entrega que decide plazos legales
// ============================================================================
// Cuando se archiva el cargo firmado de un memo disciplinario, la pantalla pide
// un DÍA y la base guarda un INSTANTE. Esa traducción de día a instante no es
// libre: `fn_expediente_adjuntar` (mig. 0074) rechaza el guardado si el instante
// es futuro o si es anterior a la firma del documento.
//
// POR QUÉ ESTE ARCHIVO. Hasta agosto de 2026 la traducción era "las 12:00 de
// ese día", fija. Eso rompía el camino más transitado del módulo: se firma un
// memo por la tarde y se entrega el mismo día. Mediodía queda ANTES de la
// firma, la base respondía «la entrega no puede ser anterior a la firma» y la
// persona no tenía forma de salir del error — la fecha que había puesto era la
// correcta. Ninguna combinación del formulario la habría desbloqueado.
//
// De esta fecha cuelgan los plazos de descargo (6 días hábiles en una
// imputación de cargos, art. 31 del D.S. 003-97-TR). Adelantar o atrasar el
// sello un día cambia cuándo vence el derecho de defensa de una persona.
//
// El reloj se inyecta como tercer parámetro para que las pruebas no dependan de
// a qué hora se corran.

import { describe, it, expect } from "vitest";
import { instanteEntrega } from "@/lib/admin/instante-entrega";
import { hoyLima } from "@cayla-dynamic/shared";

const HOY = hoyLima();
// Un "ahora" fijo: 05 de agosto de 2026, 16:30 en Lima (21:30 UTC).
const AHORA = new Date("2026-08-05T21:30:00Z");

describe("instanteEntrega", () => {
  it("entregado hoy: usa el instante real, no el mediodía", () => {
    // El caso que estaba roto. Si devolviera las 12:00 y el memo se firmó a las
    // 15:00, la base rechazaría el archivado.
    const r = instanteEntrega(HOY, "2026-08-05T20:00:00Z", AHORA);
    expect(r).toBe(AHORA.toISOString());
  });

  it("entregado hoy, memo firmado hace un minuto: queda después de la firma", () => {
    const firma = new Date(AHORA.getTime() - 60_000).toISOString();
    const r = instanteEntrega(HOY, firma, AHORA);
    expect(new Date(r).getTime()).toBeGreaterThan(new Date(firma).getTime());
  });

  it("entregado un día anterior: mediodía de Lima de ESE día", () => {
    // 12:00 en Lima (UTC-5) son las 17:00 UTC del mismo día. Si esto se corriera
    // un día, la entrega quedaría fechada el 30 o el 1 y los plazos con ella.
    const r = instanteEntrega("2026-07-31", null, AHORA);
    expect(r).toBe("2026-07-31T17:00:00.000Z");
  });

  it("entregado un día anterior pero firmado esa tarde: se sube a la hora de la firma", () => {
    // Se firma el 31 a las 15:00 de Lima (20:00 UTC) y se entrega ese mismo día
    // al cierre; el cargo se escanea al día siguiente. El mediodía sería
    // anterior a la firma y la base lo rechazaría.
    const firma = "2026-07-31T20:00:00Z";
    const r = instanteEntrega("2026-07-31", firma, AHORA);
    expect(new Date(r).getTime()).toBe(new Date(firma).getTime());
  });

  it("nunca devuelve un instante futuro", () => {
    // Aunque la firma tuviera un sello posterior a "ahora" por un desfase de
    // relojes: la base rechaza cualquier entrega futura.
    const r = instanteEntrega(HOY, "2099-01-01T00:00:00Z", AHORA);
    expect(new Date(r).getTime()).toBeLessThanOrEqual(AHORA.getTime());
  });

  it("sin fecha de firma: se queda en el mediodía del día elegido", () => {
    expect(instanteEntrega("2026-07-31", null, AHORA)).toBe("2026-07-31T17:00:00.000Z");
  });

  it("una fecha de firma ilegible no rompe el cálculo", () => {
    // Preferimos un sello razonable a una pantalla caída: si el dato viene mal,
    // la base sigue siendo la que valida el borde.
    expect(instanteEntrega("2026-07-31", "no es una fecha", AHORA))
      .toBe("2026-07-31T17:00:00.000Z");
  });
});
