// ============================================================================
// terminos-mios.test.ts — de «lo que se leyó» a «qué capa va ahora»
// ============================================================================
// Se prueba `estadoDeCapas` junto con `capaActiva` y `bloqueaElModulo`, que es
// como las usa la pantalla: la pregunta de negocio es «¿qué ve esta persona?»,
// no «¿qué devuelve esta función?». Los catálogos son inventados para poder
// aprobar textos sin aprobar ninguno de verdad.
// ============================================================================
import { describe, it, expect } from "vitest";
import {
  TERMINOS, bloqueaElModulo, capaActiva,
  type TerminosModulo,
} from "@cayla-dynamic/shared";
import {
  claveDeTerminos, estadoDeCapas, hayTerminosAprobados, llaveDeAviso,
  type EntradaEstado,
} from "@/lib/terminos-mios";

function t(modulo: string, peso: TerminosModulo["peso"], extra: Partial<TerminosModulo> = {}): TerminosModulo {
  return {
    modulo, titulo: modulo, peso, version: 1, estado: "aprobado",
    aprobado: { por: "DO", fecha: "2026-10-01" },
    puntos: ["uno de ejemplo", "dos de ejemplo"], texto: "texto de ejemplo",
    ...(peso === "constancia_propia" ? { apuntaA: "su constancia" } : {}),
    ...extra,
  };
}

const GENERAL = t("general", "aceptacion");
const BOLETAS = t("boletas", "aviso");
const FIRMA = t("firma", "aceptacion");
const DNI = t("dni", "constancia_propia");

function entrada(parcial: Partial<EntradaEstado> & Pick<EntradaEstado, "catalogo">): EntradaEstado {
  return {
    modulo: "resumen", tieneGuia: true,
    lecturaAceptaciones: "lista", aceptadas: new Set(), avisosLeidos: true, avisosVistos: new Set(),
    ...parcial,
  };
}

/** Lo que ve la persona: la capa y si el módulo está bloqueado. */
function ve(e: EntradaEstado) {
  const estado = estadoDeCapas(e);
  return { capa: capaActiva(estado), bloquea: bloqueaElModulo(estado) };
}

describe("hoy: con todo en borrador, esto no cambia nada de lo que ve una integrante", () => {
  it("el catálogo real no tiene ningún texto aprobado", () => {
    expect(hayTerminosAprobados()).toBe(false);
    expect(hayTerminosAprobados(TERMINOS)).toBe(false);
  });

  it("Resumen: no hay capa de términos y la guía sale como antes — y sin esperar ninguna lectura", () => {
    // Aun con «cargando»: sin textos aprobados no hay nada que leer, así que
    // no se espera. Es lo que mantiene la guía de Resumen arrancando a la misma hora.
    expect(ve({ modulo: "resumen", tieneGuia: true, lecturaAceptaciones: "cargando", aceptadas: new Set(),
                avisosLeidos: false, avisosVistos: new Set(), catalogo: TERMINOS }))
      .toEqual({ capa: "guia", bloquea: false });
  });

  it("cualquier otro módulo: ninguna capa, ningún bloqueo", () => {
    for (const modulo of ["dias", "turnos", "boletas", "firma", "dni", "disciplina"]) {
      expect(ve(entrada({ modulo, tieneGuia: false, catalogo: TERMINOS })), modulo).toEqual({ capa: null, bloquea: false });
    }
  });
});

describe("términos de uso", () => {
  const cat = [GENERAL];

  it("sin aceptar: es lo único que sale, y bloquea", () => {
    expect(ve(entrada({ catalogo: cat }))).toEqual({ capa: "terminos_de_uso", bloquea: true });
  });

  it("aceptados: se abre el camino y la guía puede salir", () => {
    expect(ve(entrada({ catalogo: cat, aceptadas: new Set(["general:1"]) }))).toEqual({ capa: "guia", bloquea: false });
  });

  it("subir la versión los vuelve a pedir a todo el mundo", () => {
    const v2 = [t("general", "aceptacion", { version: 2 })];
    expect(ve(entrada({ catalogo: v2, aceptadas: new Set(["general:1"]) }))).toEqual({ capa: "terminos_de_uso", bloquea: true });
  });
});

describe("«todavía no sé» no es «no ha aceptado»", () => {
  const cat = [GENERAL, FIRMA];

  it("mientras se lee la base: ni guía, ni términos, ni bloqueo", () => {
    expect(ve(entrada({ catalogo: cat, modulo: "firma", lecturaAceptaciones: "cargando" }))).toEqual({ capa: null, bloquea: false });
  });

  it("si la lectura falló: lo mismo — el módulo funciona y se reintenta en la próxima carga", () => {
    expect(ve(entrada({ catalogo: cat, modulo: "firma", lecturaAceptaciones: "error" }))).toEqual({ capa: null, bloquea: false });
  });

  it("un aviso no depende de la base: sale aunque la lectura haya fallado", () => {
    // Los avisos viven en el navegador. Si la red falla, el aviso de Boletas
    // no tiene por qué esconderse; lo que sí se calla es lo que dependía de la base.
    expect(ve(entrada({ catalogo: [BOLETAS], modulo: "boletas", tieneGuia: false, lecturaAceptaciones: "error" })))
      .toEqual({ capa: "terminos_del_modulo", bloquea: false });
  });

  it("hasta no leer el navegador no se sabe qué avisos se vieron", () => {
    expect(ve(entrada({ catalogo: [BOLETAS], modulo: "boletas", avisosLeidos: false }))).toEqual({ capa: null, bloquea: false });
  });
});

describe("términos de un módulo", () => {
  const cat = [GENERAL, FIRMA, BOLETAS, DNI];
  const uso = new Set(["general:1"]);

  it("con casilla pendiente: sale antes que la guía y bloquea el módulo", () => {
    expect(ve(entrada({ catalogo: cat, modulo: "firma", tieneGuia: true, aceptadas: uso })))
      .toEqual({ capa: "terminos_del_modulo", bloquea: true });
  });

  it("con la casilla ya aceptada: ya no sale ni bloquea", () => {
    expect(ve(entrada({ catalogo: cat, modulo: "firma", tieneGuia: false, aceptadas: new Set(["general:1", "firma:1"]) })))
      .toEqual({ capa: null, bloquea: false });
  });

  it("un aviso pendiente sale pero no bloquea: se puede dejar para después", () => {
    expect(ve(entrada({ catalogo: cat, modulo: "boletas", tieneGuia: false, aceptadas: uso })))
      .toEqual({ capa: "terminos_del_modulo", bloquea: false });
  });

  it("una constancia propia se trata como un aviso: no pide casilla ni bloquea", () => {
    expect(ve(entrada({ catalogo: cat, modulo: "dni", tieneGuia: false, aceptadas: uso })))
      .toEqual({ capa: "terminos_del_modulo", bloquea: false });
  });

  it("un aviso ya visto no vuelve a salir", () => {
    expect(ve(entrada({ catalogo: cat, modulo: "boletas", tieneGuia: false, aceptadas: uso, avisosVistos: new Set(["boletas:1"]) })))
      .toEqual({ capa: null, bloquea: false });
  });

  it("un módulo sin términos aprobados no tiene capa aunque otros sí", () => {
    expect(ve(entrada({ catalogo: cat, modulo: "turnos", tieneGuia: false, aceptadas: uso }))).toEqual({ capa: null, bloquea: false });
  });

  it("la guía espera a que los términos del módulo estén resueltos", () => {
    const sin = ve(entrada({ catalogo: cat, modulo: "boletas", tieneGuia: true, aceptadas: uso }));
    const con = ve(entrada({ catalogo: cat, modulo: "boletas", tieneGuia: true, aceptadas: uso, avisosVistos: new Set(["boletas:1"]) }));
    expect(sin.capa).toBe("terminos_del_modulo");
    expect(con.capa).toBe("guia");
  });

  it("lo aceptado en la v1 no vale para la v2 del mismo módulo", () => {
    const v2 = [GENERAL, t("firma", "aceptacion", { version: 2 })];
    expect(ve(entrada({ catalogo: v2, modulo: "firma", tieneGuia: false, aceptadas: new Set(["general:1", "firma:1"]) })))
      .toEqual({ capa: "terminos_del_modulo", bloquea: true });
  });

  it("un texto en borrador no cuenta, aunque la base tenga una aceptación vieja de él", () => {
    const borrador = [t("firma", "aceptacion", { estado: "borrador" })];
    expect(ve(entrada({ catalogo: borrador, modulo: "firma", tieneGuia: false, aceptadas: new Set(["firma:1"]) })))
      .toEqual({ capa: null, bloquea: false });
  });

  it("«general» no es además un módulo con términos propios: no se pide dos veces", () => {
    expect(estadoDeCapas(entrada({ catalogo: cat, modulo: "general", aceptadas: uso })).terminosDelModulo).toBe("sin_terminos");
  });
});

describe("las claves", () => {
  it("el Set de la base y el del navegador usan la misma clave: módulo y versión", () => {
    expect(claveDeTerminos({ modulo: "firma", version: 3 })).toBe("firma:3");
  });

  it("la llave del navegador lleva la versión: una versión nueva vuelve a mostrar el aviso", () => {
    expect(llaveDeAviso({ modulo: "boletas", version: 1 })).not.toBe(llaveDeAviso({ modulo: "boletas", version: 2 }));
  });
});
