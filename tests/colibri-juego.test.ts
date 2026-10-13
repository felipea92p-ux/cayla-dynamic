// ============================================================================
// colibri-juego.test.ts — el motor del juego del colibrí
// ============================================================================
// El juego vive en `apps/web/public/colibri/juego.js` (suelto de React, para que
// el service worker lo guarde y se juegue sin red). Lo que se prueba acá es lo
// que NO se ve a simple vista y que un juego injusto rompe sin avisar:
//   · que el sorteo de los tres juegos respete 50 / 40 / 10 (lo pidió Felipe);
//   · que una partida con la misma semilla sea idéntica (si no, no se puede probar nada);
//   · que ningún tramo generado sea imposible — con un jugador automático que
//     tiene que sobrevivir 90 s a velocidad máxima en cada juego.
// El dibujo y el teclado (`montar`) no se prueban acá: son del navegador, y se
// miran en uno de verdad.
// ============================================================================
import { describe, it, expect } from "vitest";
import {
  MUNDO, VARIANTES, cajaDelPajaro, chocan, crearJuego, crearRng, elegirVariante, esVariante, paso,
} from "../apps/web/public/colibri/juego.js";

type Obstaculo = { tipo: string; x: number; y: number; w: number; h: number; puntua?: boolean };
type Juego = {
  variante: string; t: number; vivo: boolean; puntos: number; velocidad: number; distancia: number;
  pajaro: { x: number; y: number; vy: number; w: number; h: number };
  obstaculos: Obstaculo[]; falta: number; columnas: number;
};
const nuevo = (v: string, semilla = 1) => crearJuego(v, crearRng(semilla)) as Juego;
const dar = (j: Juego, segundos: number, entrada = { pulsado: false, pulso: false }) => {
  for (let i = 0; i < segundos * 60 && j.vivo; i++) paso(j, 1 / 60, entrada);
};

describe("el sorteo de los tres juegos", () => {
  it("está escrito 50 / 40 / 10 y suma 100", () => {
    expect(VARIANTES.map((v) => [v.id, v.peso])).toEqual([["vuelo", 50], ["salto", 40], ["flappy", 10]]);
  });

  it("con un azar parejo sale 50 % / 40 % / 10 %", () => {
    const rng = crearRng(2026);
    const cuenta: Record<string, number> = { vuelo: 0, salto: 0, flappy: 0 };
    const N = 20000;
    for (let i = 0; i < N; i++) cuenta[elegirVariante(rng)]++;
    expect(cuenta.vuelo / N).toBeGreaterThan(0.48);
    expect(cuenta.vuelo / N).toBeLessThan(0.52);
    expect(cuenta.salto / N).toBeGreaterThan(0.38);
    expect(cuenta.salto / N).toBeLessThan(0.42);
    expect(cuenta.flappy / N).toBeGreaterThan(0.09);
    expect(cuenta.flappy / N).toBeLessThan(0.11);
  });

  it("los bordes del sorteo caen donde deben", () => {
    expect(elegirVariante(() => 0)).toBe("vuelo");
    expect(elegirVariante(() => 0.4999)).toBe("vuelo");
    expect(elegirVariante(() => 0.5)).toBe("salto");
    expect(elegirVariante(() => 0.8999)).toBe("salto");
    expect(elegirVariante(() => 0.9)).toBe("flappy");
    expect(elegirVariante(() => 0.9999)).toBe("flappy");
  });

  it("esVariante rechaza lo que no es un juego (se usa con lo que llega por la dirección)", () => {
    expect(esVariante("salto")).toBe(true);
    for (const x of ["", "SALTO", "dino", null, undefined, 3]) expect(esVariante(x)).toBe(false);
  });
});

describe("las cajas", () => {
  it("dos cajas que solo se rozan no chocan", () => {
    expect(chocan({ x: 0, y: 0, w: 10, h: 10 }, { x: 10, y: 0, w: 10, h: 10 })).toBe(false);
    expect(chocan({ x: 0, y: 0, w: 10, h: 10 }, { x: 9, y: 9, w: 10, h: 10 })).toBe(true);
  });

  it("la caja de choque es el cuerpo: más chica que el dibujo", () => {
    const c = cajaDelPajaro({ x: 70, y: 100, w: 46, h: 31 });
    expect(c.w).toBeLessThan(46);
    expect(c.h).toBeLessThan(31);
    expect(c.x).toBeGreaterThan(70);
  });
});

describe("una partida", () => {
  it("con la misma semilla es idéntica, cuadro por cuadro", () => {
    for (const v of ["vuelo", "salto", "flappy"]) {
      const a = nuevo(v, 77), b = nuevo(v, 77);
      for (let i = 0; i < 600; i++) {
        const entrada = { pulsado: i % 40 < 15, pulso: i % 40 === 0 };
        paso(a, 1 / 60, entrada);
        paso(b, 1 / 60, entrada);
      }
      expect(JSON.stringify([a.pajaro, a.obstaculos, a.vivo, a.puntos])).toBe(JSON.stringify([b.pajaro, b.obstaculos, b.vivo, b.puntos]));
    }
  });

  it("un cuadro larguísimo (la pestaña estuvo oculta) no se traga la partida entera", () => {
    const j = nuevo("vuelo");
    paso(j, 30, { pulsado: false, pulso: false });
    expect(j.t).toBeLessThanOrEqual(0.0501);
  });

  it("chocar con un obstáculo termina la partida, y una partida terminada ya no avanza", () => {
    const j = nuevo("salto");
    j.obstaculos.push({ tipo: "carretes", x: j.pajaro.x, y: MUNDO.suelo - 40, w: 30, h: 40 });
    paso(j, 1 / 60, { pulsado: false, pulso: false });
    expect(j.vivo).toBe(false);
    const t = j.t;
    paso(j, 1 / 60, { pulsado: true, pulso: true });
    expect(j.t).toBe(t);
  });

  it("la velocidad sube con el tiempo pero tiene tope", () => {
    for (const v of ["vuelo", "salto"]) {
      const j = nuevo(v);
      const v0 = j.velocidad;
      j.obstaculos = [];
      for (let i = 0; i < 60 * 120; i++) { j.falta = 9999; j.obstaculos = []; paso(j, 1 / 60, { pulsado: false, pulso: false }); }
      expect(j.velocidad).toBeGreaterThan(v0);
      expect(j.velocidad).toBeLessThanOrEqual(450);
    }
  });
});

describe("vuelo: mantén pulsado para subir", () => {
  it("pulsado sube, soltado baja, y nunca sale del mundo", () => {
    const j = nuevo("vuelo");
    j.falta = 9999;
    const y0 = j.pajaro.y;
    dar(j, 0.4, { pulsado: true, pulso: false });
    expect(j.pajaro.y).toBeLessThan(y0);
    dar(j, 5, { pulsado: true, pulso: false });
    expect(j.pajaro.y).toBeGreaterThanOrEqual(0);
    j.falta = 9999;
    dar(j, 10, { pulsado: false, pulso: false });
    expect(j.pajaro.y + j.pajaro.h).toBeLessThanOrEqual(MUNDO.suelo + 0.001);
  });
});

describe("salto: pulsa para saltar", () => {
  it("salta desde el suelo, no en el aire (no hay doble salto), y vuelve a caer", () => {
    const j = nuevo("salto");
    j.falta = 9999;
    const suelo = j.pajaro.y;
    paso(j, 1 / 60, { pulsado: true, pulso: true });
    expect(j.pajaro.y).toBeLessThan(suelo);
    dar(j, 0.2);
    const vy = j.pajaro.vy;
    paso(j, 1 / 60, { pulsado: true, pulso: true }); // en el aire: no hace nada nuevo
    expect(j.pajaro.vy).toBeGreaterThan(vy - 1); // sigue la caída normal, sin un segundo impulso
    dar(j, 2);
    expect(j.pajaro.y).toBe(suelo);
  });
});

describe("flappy: aletea entre los hilos", () => {
  it("sin aletear se cae y la partida termina", () => {
    const j = nuevo("flappy");
    j.falta = 9999;
    dar(j, 5);
    expect(j.vivo).toBe(false);
  });

  it("cada columna cuenta una sola vez, al dejarla atrás (y no las dos mitades)", () => {
    const j = nuevo("flappy");
    j.falta = 9999;
    j.obstaculos.push({ tipo: "columna", x: 40, y: 0, w: 26, h: 20, puntua: true });
    j.obstaculos.push({ tipo: "columna", x: 40, y: 220, w: 26, h: 20 });
    j.pajaro.y = 100; // pasa por el hueco, entre 20 y 220
    for (let i = 0; i < 90 && j.vivo; i++) paso(j, 1 / 60, { pulsado: false, pulso: i % 14 === 0 });
    expect(j.columnas).toBe(1);
    expect(j.puntos).toBe(1);
  });
});

// ---------------------------------------------------------------------------
// El jugador automático. No es un jugador perfecto: es uno razonable. Si él no
// puede sobrevivir, el juego está generando tramos que ninguna persona cruzaría.
// ---------------------------------------------------------------------------
function jugar(variante: string, semilla: number, segundos: number): Juego {
  const j = nuevo(variante, semilla);
  // Se salta el arranque lento: se mide justo lo que importa, la velocidad máxima.
  j.t = 80;
  j.velocidad = variante === "flappy" ? 210 : variante === "salto" ? 440 : 400;
  const tope = MUNDO.suelo - j.pajaro.h;
  for (let i = 0; i < segundos * 60 && j.vivo; i++) {
    const c = cajaDelPajaro(j.pajaro);
    const sigue = j.obstaculos.filter((o) => o.x + o.w > c.x).sort((a, b) => a.x - b.x);
    let entrada = { pulsado: false, pulso: false };

    if (variante === "vuelo") {
      const o = sigue[0];
      let objetivo = 100;
      if (o && o.x - (c.x + c.w) < 300) {
        // Un margen de 6 px por encima o por debajo: una persona no roza las cosas a propósito.
        const libreArriba = o.y - 6 - 18 - 7; // y máxima del colibrí para ir por encima
        const libreAbajo = o.y + o.h + 6 - 7; // y mínima para ir por debajo
        const opciones = [libreArriba, libreAbajo].filter((y) => y >= 0 && y <= tope);
        objetivo = opciones.sort((a, b) => Math.abs(a - j.pajaro.y) - Math.abs(b - j.pajaro.y))[0] ?? 0;
      }
      // Frena con anticipación: si aun soltando ahora se pasaría del objetivo, sigue pulsando.
      const dondePararia = j.pajaro.y + (j.pajaro.vy * Math.abs(j.pajaro.vy)) / 2800;
      entrada = { pulsado: dondePararia > objetivo, pulso: false };
    } else if (variante === "salto") {
      const o = sigue[0];
      const enSuelo = j.pajaro.y >= tope;
      if (o && enSuelo && o.x - (c.x + c.w) < j.velocidad * 0.18) entrada = { pulsado: true, pulso: true };
    } else {
      const arriba = sigue.find((o) => o.puntua);
      const abajo = arriba && sigue.find((o) => !o.puntua && o.x === arriba.x);
      let objetivo = MUNDO.alto / 2;
      if (arriba && abajo) objetivo = (arriba.y + arriba.h + abajo.y) / 2 + 20; // apunta bajo en el hueco: cada aleteo sube ~47 px
      const centro = j.pajaro.y + j.pajaro.h / 2;
      if (centro > objetivo && j.pajaro.vy >= 0) entrada = { pulsado: true, pulso: true };
    }
    paso(j, 1 / 60, entrada);
  }
  return j;
}

describe("ningún tramo es imposible: un jugador automático sobrevive 90 s a velocidad máxima", () => {
  for (const v of ["vuelo", "salto", "flappy"]) {
    it(`${v}: 40 partidas distintas, ninguna muere`, () => {
      const muertas: number[] = [];
      for (let semilla = 1; semilla <= 40; semilla++) {
        const j = jugar(v, semilla, 90);
        if (!j.vivo) muertas.push(semilla);
      }
      expect(muertas).toEqual([]);
    });
  }
});
