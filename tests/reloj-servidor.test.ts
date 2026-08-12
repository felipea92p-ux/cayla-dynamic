import { describe, expect, it } from "vitest";
import { DESFASE_AVISO_SEG, DESFASE_GRAVE_SEG, textoDesfase } from "../apps/web/lib/terminal/reloj-servidor";

/**
 * El reloj de la Mac mini contra el del servidor.
 *
 * `marcajes.timestamp_marca` lo pone el navegador del terminal con el reloj de
 * esa Mac, y hasta el 2026-08-12 nadie lo verificaba. Una Mac adelantada media
 * hora convierte una entrada puntual en una tardanza de treinta minutos, y no
 * deja rastro: el número entra perfecto, solo que es de otro momento.
 *
 * Lo que estas pruebas fijan es el TEXTO y los DOS UMBRALES, que es lo único
 * que se puede medir sin red. La estimación del desfase en sí —descontar la ida
 * y vuelta— vive en `medirDesfase`, que necesita un servidor y se comprueba en
 * la pgTAP 172 por el otro lado.
 */

describe("los dos umbrales", () => {
  it("avisa a los dos minutos, porque una tardanza se mide por minuto", () => {
    // No es un número redondo elegido a ojo: `fn_recalcular_jornada` cuenta la
    // tardanza por minuto y sin tolerancia. Con dos minutos de desfase el
    // sistema puede inventar o borrar una tardanza del mismo tamaño que las que
    // registra de verdad — la de Keyla del 3 de agosto fue de dos minutos.
    expect(DESFASE_AVISO_SEG).toBe(120);
  });

  it("el aviso grave llega a la hora, cuando lo que puede moverse es el DÍA", () => {
    // Por debajo de eso el daño es a las horas y a las tardanzas del mismo día.
    // Pasadas varias, un marcaje nocturno cruza la medianoche de Lima y se paga
    // en otra jornada, que es un error de otra naturaleza.
    expect(DESFASE_GRAVE_SEG).toBe(3600);
    expect(DESFASE_GRAVE_SEG).toBeGreaterThan(DESFASE_AVISO_SEG);
  });
});

describe("cómo se dice en la pantalla de una sede", () => {
  it("distingue adelantado de atrasado, que es lo que decide qué se corrige", () => {
    expect(textoDesfase(300)).toContain("ADELANTADO");
    expect(textoDesfase(-300)).toContain("ATRASADO");
  });

  it("usa la unidad que se entiende de un vistazo, no siempre segundos", () => {
    // «7200 segundos» no se lee; «2 h» sí. Quien mira esto está en una tienda,
    // de pie, entre dos clientas.
    expect(textoDesfase(7200)).toContain("2 h");
    expect(textoDesfase(300)).toContain("5 min");
    expect(textoDesfase(45)).toContain("45 s");
  });

  it("redondea el signo correctamente en el límite del aviso", () => {
    // Justo en el umbral tiene que hablar de minutos, no de segundos: es el
    // primer mensaje que alguien va a leer de esta función.
    expect(textoDesfase(DESFASE_AVISO_SEG)).toContain("2 min");
  });

  it("nunca dice un desfase negativo en el texto: el signo va en la palabra", () => {
    // «va -5 min ATRASADO» se lee como un error del sistema, no del reloj.
    expect(textoDesfase(-300)).not.toContain("-");
  });
});
