// ============================================================================
// capa-activa.test.ts — el orden «términos primero, guía después», comprobado
// ============================================================================
// La regla que importa no es un caso suelto sino una propiedad: DE TODAS las
// combinaciones posibles de lo que se sabe, la guía jamás sale antes que los
// términos, y «todavía no sé» jamás se lee como «no hay nada pendiente». Por
// eso hay una prueba que recorre las combinaciones enteras, además de los casos
// con nombre que explican por qué.
// ============================================================================
import { describe, it, expect } from "vitest";
import {
  bloqueaElModulo, capaActiva,
  type EstadoDeCapas, type EstadoGuia, type EstadoTerminosModulo,
} from "@cayla-dynamic/shared";

const USO: ReadonlyArray<boolean | null> = [null, false, true];
const MODULO: ReadonlyArray<EstadoTerminosModulo | null> =
  [null, "sin_terminos", "aceptacion_pendiente", "aviso_pendiente", "resueltos"];
const GUIA: ReadonlyArray<EstadoGuia | null> = [null, "sin_guia", "pendiente", "hecha"];

function todas(): EstadoDeCapas[] {
  const lista: EstadoDeCapas[] = [];
  for (const terminosDeUso of USO)
    for (const terminosDelModulo of MODULO)
      for (const guiaDelModulo of GUIA) lista.push({ terminosDeUso, terminosDelModulo, guiaDelModulo });
  return lista;
}

const base: EstadoDeCapas = { terminosDeUso: true, terminosDelModulo: "resueltos", guiaDelModulo: "hecha" };

describe("el orden: términos de uso, términos del módulo, guía", () => {
  it("sin aceptar los términos de uso, es lo único que sale — aunque el módulo y la guía estén pendientes", () => {
    expect(capaActiva({ terminosDeUso: false, terminosDelModulo: "aceptacion_pendiente", guiaDelModulo: "pendiente" }))
      .toBe("terminos_de_uso");
  });

  it("con los de uso aceptados, salen los del módulo antes que la guía", () => {
    expect(capaActiva({ ...base, terminosDelModulo: "aceptacion_pendiente", guiaDelModulo: "pendiente" }))
      .toBe("terminos_del_modulo");
    expect(capaActiva({ ...base, terminosDelModulo: "aviso_pendiente", guiaDelModulo: "pendiente" }))
      .toBe("terminos_del_modulo");
  });

  it("la guía sale solo cuando todo lo anterior está resuelto", () => {
    expect(capaActiva({ ...base, guiaDelModulo: "pendiente" })).toBe("guia");
    expect(capaActiva({ ...base, terminosDelModulo: "sin_terminos", guiaDelModulo: "pendiente" })).toBe("guia");
  });

  it("un módulo sin guía, o con la guía ya hecha, no muestra nada", () => {
    expect(capaActiva({ ...base, guiaDelModulo: "sin_guia" })).toBeNull();
    expect(capaActiva({ ...base, guiaDelModulo: "hecha" })).toBeNull();
  });
});

describe("«todavía no sé» no es «no hay nada pendiente»", () => {
  it("mientras no se sabe si aceptó los términos de uso, no sale ni la guía ni el módulo", () => {
    expect(capaActiva({ terminosDeUso: null, terminosDelModulo: "resueltos", guiaDelModulo: "pendiente" })).toBeNull();
    expect(capaActiva({ terminosDeUso: null, terminosDelModulo: "aceptacion_pendiente", guiaDelModulo: "pendiente" })).toBeNull();
  });

  it("si lo de uso consta pero se ignora lo del módulo, la guía espera", () => {
    // El defecto de hoy en una línea: la guía arrancaba aquí, sin saber si
    // había términos del módulo por delante.
    expect(capaActiva({ terminosDeUso: true, terminosDelModulo: null, guiaDelModulo: "pendiente" })).toBeNull();
  });

  it("si el estado de la guía aún no se conoce (la página se está armando), tampoco sale", () => {
    expect(capaActiva({ ...base, guiaDelModulo: null })).toBeNull();
  });

  it("pero lo que ya se sabe que falta sí sale, aunque lo demás se ignore", () => {
    // No aceptó los de uso: no hace falta saber nada más para ponerlos.
    expect(capaActiva({ terminosDeUso: false, terminosDelModulo: null, guiaDelModulo: null })).toBe("terminos_de_uso");
  });
});

describe("las propiedades, sobre TODAS las combinaciones", () => {
  const combinaciones = todas();

  it("recorre las 60 combinaciones (3 × 5 × 4)", () => {
    expect(combinaciones).toHaveLength(60);
  });

  it("la guía solo sale con los términos de uso aceptados y los del módulo resueltos o inexistentes", () => {
    for (const e of combinaciones) {
      if (capaActiva(e) !== "guia") continue;
      expect(e.terminosDeUso).toBe(true);
      expect(["sin_terminos", "resueltos"]).toContain(e.terminosDelModulo);
      expect(e.guiaDelModulo).toBe("pendiente");
    }
  });

  it("los términos del módulo solo salen con los de uso aceptados y algo pendiente", () => {
    for (const e of combinaciones) {
      if (capaActiva(e) !== "terminos_del_modulo") continue;
      expect(e.terminosDeUso).toBe(true);
      expect(["aceptacion_pendiente", "aviso_pendiente"]).toContain(e.terminosDelModulo);
    }
  });

  it("los términos de uso salen únicamente cuando consta que NO se aceptaron — nunca por ignorancia", () => {
    for (const e of combinaciones) {
      if (capaActiva(e) === "terminos_de_uso") expect(e.terminosDeUso).toBe(false);
    }
  });

  it("es una función: la misma entrada da la misma respuesta", () => {
    for (const e of combinaciones) expect(capaActiva({ ...e })).toBe(capaActiva(e));
  });
});

describe("qué bloquea el módulo — solo lo acordado", () => {
  it("bloquea sin los términos de uso aceptados", () => {
    expect(bloqueaElModulo({ ...base, terminosDeUso: false })).toBe(true);
  });

  it("bloquea un módulo cuyos términos exigen aceptación, ya con los de uso aceptados", () => {
    expect(bloqueaElModulo({ ...base, terminosDelModulo: "aceptacion_pendiente" })).toBe(true);
  });

  it("un aviso se puede dejar para después: no bloquea", () => {
    expect(bloqueaElModulo({ ...base, terminosDelModulo: "aviso_pendiente" })).toBe(false);
  });

  it("la guía nunca bloquea", () => {
    expect(bloqueaElModulo({ ...base, guiaDelModulo: "pendiente" })).toBe(false);
  });

  it("una lectura que falló nunca bloquea — se degrada callando", () => {
    expect(bloqueaElModulo({ terminosDeUso: null, terminosDelModulo: null, guiaDelModulo: null })).toBe(false);
    expect(bloqueaElModulo({ terminosDeUso: true, terminosDelModulo: null, guiaDelModulo: null })).toBe(false);
  });

  it("bloquear implica que hay una capa de términos para mostrar — nunca un bloqueo mudo", () => {
    for (const e of todas()) {
      if (bloqueaElModulo(e)) expect(["terminos_de_uso", "terminos_del_modulo"]).toContain(capaActiva(e));
    }
  });
});
