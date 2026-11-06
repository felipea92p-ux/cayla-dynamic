import { describe, expect, it } from "vitest";
import {
  FONDO_ALEJADO,
  FONDO_DE_LADO,
  TOPE_GOMA,
  decidirGesto,
  duracionHacia,
  fondoDeLadoSegun,
  fondoSegun,
  goma,
  posicionAlArrastrar,
  progresoDeCierre,
  seVaAlSoltar,
  velocidad,
} from "../apps/web/lib/hoja-gesto";

describe("de quién es el gesto", () => {
  it("todavía no se sabe si el dedo se movió menos de 6 px", () => {
    expect(decidirGesto(3, 5, true)).toBeNull();
  });
  it("hacia abajo con todo arriba, es de la hoja", () => {
    expect(decidirGesto(1, 20, true)).toBe("hoja");
  });
  it("hacia abajo con la lista a medio correr, es de la lista: se desplaza, no se cierra", () => {
    expect(decidirGesto(1, 20, false)).toBe("contenido");
  });
  it("de lado, una tabla que corre, es del contenido", () => {
    expect(decidirGesto(30, 10, true)).toBe("contenido");
  });
  it("hacia arriba es del contenido", () => {
    expect(decidirGesto(0, -20, true)).toBe("contenido");
  });
});

describe("dónde va la hoja mientras el dedo la lleva", () => {
  it("hacia abajo, uno a uno", () => {
    expect(posicionAlArrastrar(120)).toBe(120);
  });
  it("hacia arriba resiste y nunca pasa del tope", () => {
    expect(posicionAlArrastrar(-5000)).toBeGreaterThan(-TOPE_GOMA);
    expect(posicionAlArrastrar(-30)).toBeLessThan(0);
  });
  it("mientras guarda, la hoja oye el dedo pero no se va", () => {
    expect(posicionAlArrastrar(5000, true)).toBeLessThan(TOPE_GOMA);
    expect(posicionAlArrastrar(5000, true)).toBeGreaterThan(0);
  });
  it("la goma no cede con cero ni con menos", () => {
    expect(goma(0)).toBe(0);
    expect(goma(-10)).toBe(0);
  });
});

describe("al soltar", () => {
  it("pasado un tercio se va, y antes vuelve", () => {
    expect(seVaAlSoltar(201, 600, 0)).toBe(true);
    expect(seVaAlSoltar(199, 600, 0)).toBe(false);
  });
  it("un tirón hacia abajo se va aunque haya recorrido poco", () => {
    expect(seVaAlSoltar(40, 600, 0.8)).toBe(true);
  });
  it("un tirón hacia arriba vuelve aunque haya recorrido mucho", () => {
    expect(seVaAlSoltar(400, 600, -0.8)).toBe(false);
  });
  it("la velocidad mira solo los últimos 100 ms: un dedo que se detuvo no da un tirón", () => {
    expect(velocidad([{ t: 0, y: 0 }, { t: 50, y: 200 }, { t: 400, y: 200 }, { t: 450, y: 200 }])).toBe(0);
    expect(velocidad([{ t: 0, y: 0 }, { t: 50, y: 50 }])).toBe(1);
    expect(velocidad([{ t: 0, y: 0 }])).toBe(0);
  });
  it("llega entre 180 y 420 ms, venga como venga", () => {
    expect(duracionHacia(1000, 0)).toBe(420);
    expect(duracionHacia(10, 2)).toBe(180);
    expect(duracionHacia(300, 1)).toBe(300);
  });
});

describe("lo de atrás", () => {
  it("el progreso va de 0 a 1 y no se sale", () => {
    expect(progresoDeCierre(300, 600)).toBe(0.5);
    expect(progresoDeCierre(-5, 600)).toBe(0);
    expect(progresoDeCierre(900, 600)).toBe(1);
    expect(progresoDeCierre(10, 0)).toBe(0);
  });
  it("abierta del todo está alejado, y cerrada vuelve a su lugar sin dejar nada", () => {
    expect(fondoSegun(0)).toEqual(FONDO_ALEJADO);
    expect(fondoSegun(1)).toEqual({ escala: 1, bajada: 0, radio: 0 });
    expect(fondoDeLadoSegun(0)).toEqual(FONDO_DE_LADO);
    expect(fondoDeLadoSegun(1)).toEqual({ escala: 1, corrida: 0, radio: 0 });
  });
});
