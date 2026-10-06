// ============================================================================
// volver-atras.test.ts — Cuándo «← Volver» puede ser un «atrás»
// ============================================================================
// Un «Cancelar» que saca a alguien de la app es peor que el que abría una
// página nueva: por eso la regla es «solo si la página anterior ES el destino»,
// y cada caso de abajo es un camino real de una persona en su teléfono.
// ============================================================================
import { beforeEach, describe, expect, it } from "vitest";
import {
  alCambiarLaDireccion,
  elDestinoEsLaPaginaAnterior,
  olvidarLaRuta,
} from "@/lib/volver-atras";

beforeEach(olvidarLaRuta);

describe("cuando se vuelve con «atrás»", () => {
  it("Reportes → Nuevo reporte → «Cancelar» vuelve a Reportes", () => {
    alCambiarLaDireccion("/mio?tab=reportes");
    alCambiarLaDireccion("/mio/reportes/nuevo");
    expect(elDestinoEsLaPaginaAnterior("/mio?tab=reportes")).toBe(true);
  });

  it("«← Volver a Info» vuelve a la sección desde la que se abrió el memo", () => {
    alCambiarLaDireccion("/mio?tab=historial");
    alCambiarLaDireccion("/mio/memo/abc");
    expect(elDestinoEsLaPaginaAnterior("/mio")).toBe(true);
  });

  it("también cuando se venía del Resumen, que es la dirección limpia", () => {
    alCambiarLaDireccion("/mio");
    alCambiarLaDireccion("/mio/boleta");
    expect(elDestinoEsLaPaginaAnterior("/mio")).toBe(true);
  });

  it("ignora el ancla de la dirección", () => {
    alCambiarLaDireccion("/mio?tab=reportes#abajo");
    alCambiarLaDireccion("/mio/reportes/nuevo");
    expect(elDestinoEsLaPaginaAnterior("/mio?tab=reportes")).toBe(true);
  });
});

describe("cuando NO se puede volver con «atrás» y el enlace navega", () => {
  it("al abrir la página directamente no hay nada anterior en la app", () => {
    alCambiarLaDireccion("/mio/reportes/nuevo");
    expect(elDestinoEsLaPaginaAnterior("/mio?tab=reportes")).toBe(false);
  });

  it("el destino pide Reportes y se venía del Resumen", () => {
    alCambiarLaDireccion("/mio");
    alCambiarLaDireccion("/mio/reportes/nuevo");
    expect(elDestinoEsLaPaginaAnterior("/mio?tab=reportes")).toBe(false);
  });

  it("se venía de otra pantalla, no de la que dice el enlace", () => {
    alCambiarLaDireccion("/mio/bandeja");
    alCambiarLaDireccion("/mio/reportes/nuevo");
    expect(elDestinoEsLaPaginaAnterior("/mio")).toBe(false);
  });

  it("trampa: tras un «atrás» ya no se sabe qué hay detrás", () => {
    // /mio → /mio/boleta → /mio/memo/abc, y «atrás» a /mio/boleta: la página
    // «anterior» que se había anotado (/mio/boleta → memo) ya no es la del historial.
    alCambiarLaDireccion("/mio");
    alCambiarLaDireccion("/mio/boleta");
    alCambiarLaDireccion("/mio/memo/abc");
    alCambiarLaDireccion("/mio/boleta", true);
    expect(elDestinoEsLaPaginaAnterior("/mio")).toBe(false);
    expect(elDestinoEsLaPaginaAnterior("/mio/memo/abc")).toBe(false);
  });

  it("trampa: si el efecto anota la dirección ANTES de que llegue el aviso del retroceso, también se olvida", () => {
    // Medido en el navegador: al retroceder, Next pinta primero (el efecto anota
    // «/mio» como una navegación más) y `popstate` llega 27 ms después.
    alCambiarLaDireccion("/mio");
    alCambiarLaDireccion("/mio/boleta");
    alCambiarLaDireccion("/mio");          // el efecto, primero
    alCambiarLaDireccion("/mio", true);    // el aviso del retroceso, después
    expect(elDestinoEsLaPaginaAnterior("/mio/boleta")).toBe(false);
  });

  it("un destino que no se puede leer no rompe nada", () => {
    alCambiarLaDireccion("/mio");
    alCambiarLaDireccion("/mio/boleta");
    expect(elDestinoEsLaPaginaAnterior("http://[")).toBe(false);
  });
});

describe("al anotar las direcciones", () => {
  it("repetir la misma dirección no borra la anterior", () => {
    alCambiarLaDireccion("/mio?tab=reportes");
    alCambiarLaDireccion("/mio/reportes/nuevo");
    alCambiarLaDireccion("/mio/reportes/nuevo");
    expect(elDestinoEsLaPaginaAnterior("/mio?tab=reportes")).toBe(true);
  });

  it("cada cambio de dirección anota la anterior, también dentro de «Lo mío»", () => {
    alCambiarLaDireccion("/mio");
    alCambiarLaDireccion("/mio?tab=dias");
    expect(elDestinoEsLaPaginaAnterior("/mio")).toBe(true);
    expect(elDestinoEsLaPaginaAnterior("/mio?tab=reportes")).toBe(false);
  });
});
