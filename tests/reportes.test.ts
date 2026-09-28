// ============================================================================
// reportes.test.ts — Lo que la pantalla de Reportes decide antes de preguntar
// ============================================================================
// La base (0483, 0488) es la que manda: quién lee, qué plazos corren, si se
// puede enviar. Esto prueba lo único que la pantalla decide sola, y que puede
// romperse sin que nadie lo note: qué vía corresponde a lo que se marcó (si se
// equivoca, un acoso viaja como reclamo y su plazo es otro), qué se reclama
// en cada paso, y cómo se dice una fecha de vencimiento en Lima.
// ============================================================================
import { describe, expect, it } from "vitest";
import {
  contarSinLeer, faltaEnReporte, fechaEnPalabras, rutaDeAdjunto, tituloDeReporte, viaDeReporte,
  type BorradorReporte, type FilaMiReporte,
} from "@/lib/reportes";

const base: BorradorReporte = {
  tituloX: false, tipo: "persona", maltrato: false, relato: "Pasó algo.",
  fechaHecho: "2026-09-22", sedeId: "sede", involucradas: ["bea"], testigos: [],
};

describe("viaDeReporte", () => {
  it("el Título X gana siempre, aunque también se marque maltrato", () => {
    expect(viaDeReporte({ tituloX: true, tipo: "persona", maltrato: true })).toBe("titulo_x");
    expect(viaDeReporte({ tituloX: true, tipo: "clienta", maltrato: false })).toBe("titulo_x");
  });
  it("el maltrato entre personas es convivencia (43-A)", () => {
    expect(viaDeReporte({ tituloX: false, tipo: "persona", maltrato: true })).toBe("convivencia");
  });
  it("todo lo demás es reclamo, consulta o sugerencia (43-B)", () => {
    expect(viaDeReporte({ tituloX: false, tipo: "persona", maltrato: false })).toBe("reclamo");
    expect(viaDeReporte({ tituloX: false, tipo: "consulta", maltrato: false })).toBe("reclamo");
    // «Maltrato» solo existe para personas: marcarlo sobre la empresa no cambia la vía.
    expect(viaDeReporte({ tituloX: false, tipo: "empresa", maltrato: true })).toBe("reclamo");
  });
});

describe("faltaEnReporte", () => {
  const hoy = "2026-09-26";
  it("un borrador completo se puede enviar", () => {
    expect(faltaEnReporte(base, hoy)).toBeNull();
  });
  it("sin tipo no se avanza", () => {
    expect(faltaEnReporte({ ...base, tipo: null }, hoy, 1)).toMatch(/sobre qué/);
  });
  it("el Título X es sobre una persona o una clienta", () => {
    expect(faltaEnReporte({ ...base, tituloX: true, tipo: "idea" }, hoy, 1)).toMatch(/persona o una clienta/);
    expect(faltaEnReporte({ ...base, tituloX: true, tipo: "clienta", involucradas: [] }, hoy)).toBeNull();
  });
  it("en el Título X no hace falta nombrar a nadie (48.8: solo el relato es obligatorio)", () => {
    expect(faltaEnReporte({ ...base, tituloX: true, involucradas: [] }, hoy)).toBeNull();
  });
  it("no reclama en el paso 1 lo que se pide en el 3", () => {
    expect(faltaEnReporte({ ...base, relato: "", involucradas: [] }, hoy, 1)).toBeNull();
    expect(faltaEnReporte({ ...base, relato: "  " }, hoy, 2)).toMatch(/qué pasó/);
  });
  it("sobre una persona, hay que elegirla", () => {
    expect(faltaEnReporte({ ...base, involucradas: [] }, hoy)).toMatch(/Elige a la persona/);
  });
  it("la fecha del hecho no puede ser futura ni faltar", () => {
    expect(faltaEnReporte({ ...base, fechaHecho: "2026-09-27" }, hoy)).toMatch(/futura/);
    expect(faltaEnReporte({ ...base, fechaHecho: "" }, hoy)).toMatch(/fecha/);
  });
  it("nadie es involucrada y testigo a la vez", () => {
    expect(faltaEnReporte({ ...base, testigos: ["bea"] }, hoy)).toMatch(/involucrada y testigo/);
  });
});

describe("fechaEnPalabras", () => {
  it("dice el día de LIMA, no el del servidor", () => {
    // 23:59:59 de Lima del lunes 12 de octubre = 04:59:59 UTC del martes 13.
    expect(fechaEnPalabras("2026-10-13T04:59:59Z")).toBe("lunes 12 de octubre");
  });
});

describe("tituloDeReporte", () => {
  it("una queja del Título X se nombra por su camino, aunque empezó como otro tipo", () => {
    expect(tituloDeReporte("persona", "titulo_x")).toBe("Queja de hostigamiento sexual");
    expect(tituloDeReporte("consulta", "reclamo")).toBe("Consulta a mi líder");
  });
});

describe("contarSinLeer", () => {
  it("cuenta reportes con algo sin leer, no mensajes", () => {
    const f = (sin_leer: number) => ({ sin_leer }) as FilaMiReporte;
    expect(contarSinLeer([f(0), f(3), f(1)])).toBe(2);
  });
});

describe("rutaDeAdjunto", () => {
  it("arma la única forma de ruta que acepta el bucket", () => {
    expect(rutaDeAdjunto("r1", "image/heic", "u1")).toBe("r1/u1.heic");
    expect(rutaDeAdjunto("r1", "application/pdf", "u1")).toBe("r1/u1.pdf");
  });
  it("un formato que el bucket no acepta no se intenta subir", () => {
    expect(rutaDeAdjunto("r1", "video/mp4", "u1")).toBeNull();
  });
});
