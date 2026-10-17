import { describe, expect, it } from "vitest";
import {
  ALETEO_MAXIMO,
  DURACION_DEL_VUELO,
  LINEA_DE_TIEMPO,
  TRAZOS_DEL_AVE,
  aleteo,
  alaDelAve,
  estadoDelVuelo,
  poseDelAve,
  ritmoDelSalto,
  ritmoDelVuelo,
  saludoDelDia,
  tintaDeLaPalabra,
  trazoDelVuelo,
} from "@/lib/login-vuelo";

const numeros = (d: string) => (d.match(/-?\d+(\.\d+)?/g) ?? []).map(Number);

// Nota: la prueba de Retail que compara los trazos con `IsotipoCayla.tsx` no viene: Dynamic pinta su colibrí como imagen (`.colibri`).
// Los trazos de aquí son una copia de los de Retail; si allá cambia la marca, cambian los dos.
describe("el colibrí del login es el de la marca", () => {
  it("con el ala en reposo, el ala es exactamente la del logo", () => {
    const [a, b] = alaDelAve(0, 1);
    expect(numeros(a)).toEqual(numeros(TRAZOS_DEL_AVE[0]));
    expect(numeros(b)).toEqual(numeros(TRAZOS_DEL_AVE[1]));
  });

  it("al aletear, la punta del ala sube y baja; el cuerpo no se mueve", () => {
    const yPunta = (ang: number) => numeros(alaDelAve(ang)[0])[1];
    expect(yPunta(ALETEO_MAXIMO)).toBeLessThan(yPunta(0)); // arriba = y menor
    expect(yPunta(-ALETEO_MAXIMO)).toBeGreaterThan(yPunta(0));
    const cuerpo = (d: string) => d.slice(d.indexOf("118,50"));
    expect(cuerpo(alaDelAve(ALETEO_MAXIMO)[0])).toBe(cuerpo(TRAZOS_DEL_AVE[0]));
  });

  it("el escorzo solo aparece cuando el ala sube", () => {
    expect(aleteo(Math.PI / 2, ALETEO_MAXIMO).largo).toBeLessThan(1);
    expect(aleteo(-Math.PI / 2, ALETEO_MAXIMO).largo).toBe(1);
    expect(aleteo(Math.PI / 2, 0)).toEqual({ angulo: 0, largo: 1 });
  });
});

describe("trazoDelVuelo", () => {
  const medidas = {
    ancho: 756,
    alto: 900,
    sedes: [
      { x: 64, y: 790 },
      { x: 262, y: 790 },
      { x: 436, y: 790 },
    ],
    destino: { x: 455, y: 286 },
  };

  it("sale de la primera sede y termina justo en la cola del ave", () => {
    const d = trazoDelVuelo(medidas);
    expect(d.startsWith("M64,790 ")).toBe(true);
    expect(d.endsWith(" 455,286")).toBe(true);
  });

  it("pasa en línea recta por las tres sedes antes de subir", () => {
    const tramoRecto = trazoDelVuelo(medidas).split(" C")[0];
    expect(tramoRecto).toMatch(/^M64,790 L\d+(\.\d)?,790$/);
    expect(Number(tramoRecto.split("L")[1].split(",")[0])).toBeGreaterThan(436);
  });

  it("no da números con decimales infinitos", () => {
    expect(trazoDelVuelo({ ...medidas, ancho: 733.3333, alto: 811.7777 })).not.toMatch(/\.\d{2,}/);
  });
});

describe("los ritmos no rebotan", () => {
  for (const [nombre, ritmo] of [
    ["ritmoDelVuelo", ritmoDelVuelo],
    ["ritmoDelSalto", ritmoDelSalto],
  ] as const) {
    it(`${nombre}: de 0 a 1, nunca se pasa ni retrocede`, () => {
      expect(ritmo(0)).toBe(0);
      expect(ritmo(1)).toBe(1);
      let previo = 0;
      for (let i = 1; i <= 100; i++) {
        const v = ritmo(i / 100);
        expect(v).toBeGreaterThanOrEqual(previo);
        expect(v).toBeLessThanOrEqual(1);
        previo = v;
      }
      expect(ritmo(-1)).toBe(0);
      expect(ritmo(2)).toBe(1);
    });
  }
});

describe("estadoDelVuelo", () => {
  const hilo = { largo: 1500, segunda: 200, tercera: 380 };

  it("el ave siempre avanza por el hilo, nunca vuelve atrás", () => {
    let previo = -1;
    for (let ms = 0; ms <= DURACION_DEL_VUELO + 200; ms += 10) {
      const e = estadoDelVuelo(ms, hilo);
      expect(e.recorrido).toBeGreaterThanOrEqual(previo);
      previo = e.recorrido;
    }
  });

  it("cose las sedes en orden: Trujillo al aparecer, Arequipa y Lima al llegar a cada una", () => {
    expect(estadoDelVuelo(0, hilo).cosidas).toBe(1);
    expect(estadoDelVuelo(LINEA_DE_TIEMPO.flotaSegunda[0] + 1, hilo)).toMatchObject({ cosidas: 2, recorrido: 200, flota: 1 });
    expect(estadoDelVuelo(LINEA_DE_TIEMPO.flotaTercera[0] + 1, hilo)).toMatchObject({ cosidas: 3, recorrido: 380, flota: 1 });
  });

  it("solo en el gran vuelo crece y sigue la curva", () => {
    expect(estadoDelVuelo(500, hilo)).toMatchObject({ escala: 0.3, enGranVuelo: false });
    const medio = estadoDelVuelo((LINEA_DE_TIEMPO.granVuelo[0] + LINEA_DE_TIEMPO.granVuelo[1]) / 2, hilo);
    expect(medio.enGranVuelo).toBe(true);
    expect(medio.escala).toBeGreaterThan(0.3);
    expect(medio.escala).toBeLessThan(1);
  });

  it("al terminar queda en su lugar, con su tamaño, quieta y con el ala en reposo", () => {
    const e = estadoDelVuelo(DURACION_DEL_VUELO, hilo);
    expect(e).toMatchObject({ recorrido: 1500, escala: 1, flota: 0, amplitud: 0, dibujado: 1, cosidas: 3, terminado: true, tiron: 1 });
  });

  it("dura algo más de 4 segundos y aparece dibujándose", () => {
    expect(DURACION_DEL_VUELO).toBe(4300);
    expect(estadoDelVuelo(0, hilo).dibujado).toBe(0);
    expect(estadoDelVuelo(LINEA_DE_TIEMPO.aparece[1], hilo).dibujado).toBe(1);
  });
});

describe("poseDelAve", () => {
  const vuelo = { enGranVuelo: true, inclinacionDelSalto: 0 };

  it("se voltea poco a poco cuando vuela hacia la izquierda en el gran vuelo", () => {
    let pose = { giro: 1, inclinacion: 0 };
    pose = poseDelAve(pose, { dx: -2, dy: 0 }, vuelo, 0.5);
    expect(pose.giro).toBeLessThan(1);
    expect(pose.giro).toBeGreaterThan(-1);
    for (let i = 0; i < 60; i++) pose = poseDelAve(pose, { dx: -2, dy: 0 }, vuelo, 0.5);
    expect(pose.giro).toBeCloseTo(-1, 2);
  });

  it("en los saltos mira siempre a la derecha y se inclina hacia adelante", () => {
    let pose = { giro: -1, inclinacion: 0 };
    for (let i = 0; i < 60; i++) pose = poseDelAve(pose, { dx: -2, dy: 0 }, { enGranVuelo: false, inclinacionDelSalto: 12 }, 0);
    expect(pose.giro).toBeCloseTo(1, 2);
    expect(pose.inclinacion).toBeCloseTo(12, 1);
  });

  it("nunca se inclina más de 22°", () => {
    let pose = { giro: 1, inclinacion: 0 };
    for (let i = 0; i < 200; i++) pose = poseDelAve(pose, { dx: 0.01, dy: -5 }, vuelo, 0);
    expect(Math.abs(pose.inclinacion)).toBeLessThanOrEqual(22);
  });
});

describe("tintaDeLaPalabra", () => {
  const palabra = { x: 100, y: 500, ancho: 200, alto: 60 };

  it("tiñe de derecha a izquierda hasta donde llega el ave, y no se destiñe", () => {
    let t = tintaDeLaPalabra(0, { x: 250, y: 520 }, palabra, 0.016, false);
    expect(t).toBeCloseTo(0.25);
    t = tintaDeLaPalabra(t, { x: 150, y: 520 }, palabra, 0.016, false);
    expect(t).toBeCloseTo(0.75);
    expect(tintaDeLaPalabra(t, { x: 290, y: 520 }, palabra, 0.016, false)).toBeCloseTo(0.75);
  });

  it("lejos de la palabra no tiñe, y al terminar el gran vuelo se completa sola", () => {
    expect(tintaDeLaPalabra(0, { x: 150, y: 100 }, palabra, 0.016, false)).toBe(0);
    let t = 0.4;
    for (let i = 0; i < 30; i++) t = tintaDeLaPalabra(t, { x: 600, y: 100 }, palabra, 0.016, true);
    expect(t).toBe(1);
  });
});

describe("saludoDelDia", () => {
  // Perú es UTC-5 todo el año (sin horario de verano).
  const en = (horaLima: number) => new Date(Date.UTC(2026, 9, 13, horaLima + 5, 30));

  it("saluda según la hora de Perú", () => {
    expect(saludoDelDia(en(7))).toMatch(/^Buenos días · /);
    expect(saludoDelDia(en(12))).toMatch(/^Buenas tardes · /);
    expect(saludoDelDia(en(18))).toMatch(/^Buenas tardes · /);
    expect(saludoDelDia(en(19))).toMatch(/^Buenas noches · /);
    // 1 a. m. del miércoles en Lima: en UTC ya son las 6 de la mañana, pero manda la hora de Perú.
    expect(saludoDelDia(new Date(Date.UTC(2026, 9, 14, 6, 0)))).toBe("Buenas noches · miércoles 14 de octubre");
  });

  it("dice el día y la fecha en palabras", () => {
    expect(saludoDelDia(en(9))).toBe("Buenos días · martes 13 de octubre");
  });
});
