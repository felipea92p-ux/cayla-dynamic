// ============================================================================
// seccion-en-la-direccion.test.ts — Enlace, «atrás» y recarga en «Lo mío»
// ============================================================================
// Las tres cosas que se pidieron el 2026-10-06 tiran en direcciones opuestas:
// un enlace abre su sección, «atrás» vuelve a la sección en la que estabas, y
// recargar abre Resumen. Cada caso de abajo es un camino real de una persona
// en su teléfono, y los dos de «trampa» son los que fallaban con una regla más
// simple.
// ============================================================================
import { describe, it, expect } from "vitest";
import {
  direccionDeSeccion,
  esRecargaDeEstaDireccion,
  seccionAlLlegar,
  seccionDeLaDireccion,
} from "@/lib/seccion-en-la-direccion";

const SECCIONES = ["resumen", "dias", "boletas", "reportes"] as const;
const BASE = "https://cayla-dynamic.vercel.app";

const llegar = (direccion: string, carga: { tipo: string; direccion: string } | null, primeraVez = true) =>
  seccionAlLlegar({ direccion: BASE + direccion, carga: carga && { ...carga, direccion: BASE + carga.direccion }, primeraVez },
    SECCIONES, "resumen");

describe("al llegar a «Lo mío»", () => {
  it("un enlace de la Bandeja abre su sección y deja la dirección como está", () => {
    expect(llegar("/mio?tab=boletas", { tipo: "navigate", direccion: "/mio?tab=boletas" }))
      .toEqual({ seccion: "boletas", reemplazarPor: null });
  });

  it("recargar en Reportes abre Resumen y limpia la dirección", () => {
    expect(llegar("/mio?tab=reportes", { tipo: "reload", direccion: "/mio?tab=reportes" }))
      .toEqual({ seccion: "resumen", reemplazarPor: `${BASE}/mio` });
  });

  it("recargar conserva los demás parámetros y el ancla", () => {
    expect(llegar("/mio?tab=reportes&x=1#arriba", { tipo: "reload", direccion: "/mio?tab=reportes&x=1" }))
      .toEqual({ seccion: "resumen", reemplazarPor: `${BASE}/mio?x=1#arriba` });
  });

  it("«atrás» desde un reporte vuelve a Reportes", () => {
    // Volver de /mio/reportes/<id> monta la pantalla otra vez, ya no por primera vez.
    expect(llegar("/mio?tab=reportes", { tipo: "navigate", direccion: "/mio" }, false))
      .toEqual({ seccion: "reportes", reemplazarPor: null });
  });

  it("«atrás» que obliga al navegador a cargar la página entera también vuelve a Reportes", () => {
    expect(llegar("/mio?tab=reportes", { tipo: "back_forward", direccion: "/mio?tab=reportes" }))
      .toEqual({ seccion: "reportes", reemplazarPor: null });
  });

  it("trampa 1: recargar la Bandeja y tocar un aviso abre la sección del aviso, no Resumen", () => {
    expect(llegar("/mio?tab=boletas", { tipo: "reload", direccion: "/mio/bandeja" }))
      .toEqual({ seccion: "boletas", reemplazarPor: null });
  });

  it("trampa 2: recargar, ir a Reportes, abrir uno y volver «atrás» vuelve a Reportes", () => {
    // La dirección coincide con la recargada, pero la pantalla ya había aparecido.
    expect(llegar("/mio?tab=reportes", { tipo: "reload", direccion: "/mio?tab=reportes" }, false))
      .toEqual({ seccion: "reportes", reemplazarPor: null });
  });

  it("un ?tab= mal escrito abre Resumen y se borra", () => {
    expect(llegar("/mio?tab=reporte", { tipo: "navigate", direccion: "/mio?tab=reporte" }))
      .toEqual({ seccion: "resumen", reemplazarPor: `${BASE}/mio` });
  });

  it("si el navegador no dice cómo se cargó, nunca se trata como recarga", () => {
    expect(llegar("/mio?tab=reportes", null)).toEqual({ seccion: "reportes", reemplazarPor: null });
  });
});

describe("la dirección de cada sección", () => {
  it("Resumen es la dirección limpia; las demás llevan ?tab=", () => {
    expect(direccionDeSeccion(`${BASE}/mio?tab=dias`, "resumen", "resumen")).toBe(`${BASE}/mio`);
    expect(direccionDeSeccion(`${BASE}/mio`, "reportes", "resumen")).toBe(`${BASE}/mio?tab=reportes`);
  });

  it("ida y vuelta: lo que se escribe es lo que se lee", () => {
    for (const s of SECCIONES) {
      expect(seccionDeLaDireccion(direccionDeSeccion(`${BASE}/mio`, s, "resumen"), SECCIONES, "resumen")).toBe(s);
    }
  });

  it("la recarga ignora el ancla al comparar direcciones", () => {
    expect(esRecargaDeEstaDireccion({
      direccion: `${BASE}/mio?tab=dias#detalle`,
      carga: { tipo: "reload", direccion: `${BASE}/mio?tab=dias` },
      primeraVez: true,
    })).toBe(true);
  });
});
