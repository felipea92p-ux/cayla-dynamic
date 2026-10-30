import { describe, it, expect } from "vitest";
import {
  REFRIGERIOS_MIN, opcionesRefrigerio, etiquetaRefrigerio, yaLlegaAlmorzada, diasQueYaLlegaAlmorzada,
} from "@/lib/admin/refrigerio";
import { horasEntre } from "@/lib/admin/jornada-esperada";

describe("opciones de refrigerio", () => {
  it("ofrece «sin refrigerio» además de los 60 y 75 de siempre", () => {
    expect(opcionesRefrigerio(60)).toEqual([0, 60, 75]);
    expect(opcionesRefrigerio(0)).toEqual([0, 60, 75]);
  });

  it("un valor viejo fuera de la lista se muestra, no se esconde ni se pisa", () => {
    // 45 era el default del esquema legacy: si el select no lo mostrara,
    // guardar el horario lo cambiaría sin que quien edita lo note.
    expect(opcionesRefrigerio(45)).toEqual([0, 45, 60, 75]);
    // Y no se duplica ni cambia la lista compartida.
    expect(REFRIGERIOS_MIN).toEqual([0, 60, 75]);
  });

  it("el 0 se lee como «Ninguno»; en columna angosta, solo el número", () => {
    expect(etiquetaRefrigerio(0)).toBe("Ninguno");
    expect(etiquetaRefrigerio(60)).toBe("60 min");
    expect(etiquetaRefrigerio(0, true)).toBe("0");
  });
});

describe("¿ya llega almorzada? (sugerencia)", () => {
  it("el caso real: entra 14:15 con refrigerio puesto → se sugiere quitarlo", () => {
    expect(yaLlegaAlmorzada({ e: "14:15", s: "21:45", r: 60 })).toBe(true);
  });

  it("quien trabaja de mañana nunca ve la sugerencia", () => {
    expect(yaLlegaAlmorzada({ e: "08:05", s: "18:05", r: 60 })).toBe(false);
    expect(yaLlegaAlmorzada({ e: "12:59", s: "21:00", r: 60 })).toBe(false);
  });

  it("13:00 en punto ya cuenta; es el umbral", () => {
    expect(yaLlegaAlmorzada({ e: "13:00", s: "20:00", r: 60 })).toBe(true);
  });

  it("si ya está en 0 no hay nada que sugerir", () => {
    expect(yaLlegaAlmorzada({ e: "14:15", s: "21:45", r: 0 })).toBe(false);
  });

  it("un turno nocturno que cruza medianoche no se asume almorzado", () => {
    // 21:00–05:00: la salida es «menor» que la entrada.
    expect(yaLlegaAlmorzada({ e: "21:00", s: "05:00", r: 60 })).toBe(false);
  });

  it("sin hora de entrada o de salida no se opina", () => {
    expect(yaLlegaAlmorzada({ e: "", s: "21:45", r: 60 })).toBe(false);
    expect(yaLlegaAlmorzada({ e: "14:15", s: "", r: 60 })).toBe(false);
  });

  it("por día: solo los días de tarde, y ordenados", () => {
    const porDia = {
      4: { e: "14:15", s: "21:45", r: 60 }, // jueves, tarde
      1: { e: "08:00", s: "17:00", r: 60 }, // lunes, mañana
      2: { e: "14:15", s: "21:45", r: 0 },  // martes, tarde pero ya sin refrigerio
      6: { e: "14:15", s: "21:45", r: 75 }, // sábado, tarde
    };
    expect(diasQueYaLlegaAlmorzada(porDia)).toEqual([4, 6]);
  });
});

describe("lo que cambia en el número: el caso de la captura", () => {
  it("14:15–21:45 son 7.5 h sin refrigerio, y seis días llegan a las 45 h de meta", () => {
    expect(horasEntre("14:15", "21:45", 60)).toBe(6.5);
    expect(horasEntre("14:15", "21:45", 0)).toBe(7.5);
    expect(horasEntre("14:15", "21:45", 0) * 6).toBe(45);
    // Con el refrigerio puesto de más eran 39 h: «faltan 6 h» que sí se trabajan.
    expect(horasEntre("14:15", "21:45", 60) * 6).toBe(39);
  });
});
