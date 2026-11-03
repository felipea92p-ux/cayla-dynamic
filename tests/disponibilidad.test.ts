import { describe, it, expect } from "vitest";
import {
  aBloques, aplicarAtajo, avisoDeHoras, desdeBloques, horasDisponibles, opcionesHora, resumenEnPalabras,
  semanaSinRestricciones, semanaVacia, validar, type Ventana,
} from "@/lib/disponibilidad";

// La ventana de TRU: lunes a sábado 08:30–20:15; domingo 10:00–18:15.
const TRU: Ventana[] = [
  ...[1, 2, 3, 4, 5, 6].map((dia) => ({ dia, abre: "08:30:00", cierra: "20:15:00" })),
  { dia: 0, abre: "10:00:00", cierra: "18:15:00" },
];

describe("la semana tipo y los bloques", () => {
  it("ida y vuelta: lo que se guarda se vuelve a dibujar igual", () => {
    const s = semanaVacia();
    s[2] = { modo: "horas", tramos: [{ desde: "08:30", hasta: "14:00", estado: "no_puede" }] };
    s[0] = { modo: "prefiere_no", tramos: [] };
    const exc = [{ fecha: "2026-11-15", desde: null, hasta: null, estado: "no_puede" as const }];
    const bloques = aBloques(s, exc);
    expect(bloques).toEqual([
      { dia_semana: 2, desde: "08:30", hasta: "14:00", estado: "no_puede" },
      { dia_semana: 0, desde: null, hasta: null, estado: "prefiere_no" },
      { fecha: "2026-11-15", desde: null, hasta: null, estado: "no_puede" },
    ]);
    // Como vuelven de la base: con segundos.
    const devuelta = desdeBloques(bloques.map((b) => ({ ...b, desde: b.desde && `${b.desde}:00`, hasta: b.hasta && `${b.hasta}:00` })));
    expect(devuelta.semana).toEqual(s);
    expect(devuelta.excepciones).toEqual(exc);
  });

  it("sin nada marcado no hay restricciones", () => {
    expect(semanaSinRestricciones(semanaVacia())).toBe(true);
    expect(aBloques(semanaVacia(), [])).toEqual([]);
  });
});

describe("los atajos", () => {
  it("«Solo mañanas»: no puedo desde las 14:00 hasta que cierra (redondeado a la media hora)", () => {
    const s = aplicarAtajo(semanaVacia(), "solo_mananas", TRU);
    expect(s[1].tramos).toEqual([{ desde: "14:00", hasta: "20:30", estado: "no_puede" }]);
    expect(s[0].tramos).toEqual([{ desde: "14:00", hasta: "18:30", estado: "no_puede" }]);
  });
  it("«Solo tardes»: no puedo desde que abre hasta las 14:00", () => {
    const s = aplicarAtajo(semanaVacia(), "solo_tardes", TRU);
    expect(s[3].tramos).toEqual([{ desde: "08:30", hasta: "14:00", estado: "no_puede" }]);
  });
  it("«No domingos» solo toca el domingo, y «Puedo todo» limpia", () => {
    const s = aplicarAtajo(aplicarAtajo(semanaVacia(), "solo_tardes", TRU), "no_domingos", TRU);
    expect(s[0]).toEqual({ modo: "no_puede", tramos: [] });
    expect(s[1].modo).toBe("horas");
    expect(semanaSinRestricciones(aplicarAtajo(s, "puedo_todo", TRU))).toBe(true);
  });
  it("un día en que la sede no abre no se marca", () => {
    const s = aplicarAtajo(semanaVacia(), "solo_mananas", TRU.filter((v) => v.dia !== 0));
    expect(s[0].modo).toBe("puede");
  });
  it("las horas del selector van de 06:00 a 24:00, de media en media hora", () => {
    const o = opcionesHora();
    expect(o[0]).toBe("06:00");
    expect(o[o.length - 1]).toBe("24:00");
    expect(o).toContain("14:00");
    expect(o).not.toContain("14:15");
  });
});

describe("validar, igual que la base", () => {
  it("dos tramos del mismo día que se cruzan", () => {
    const s = semanaVacia();
    s[1] = { modo: "horas", tramos: [
      { desde: "08:30", hasta: "12:00", estado: "no_puede" },
      { desde: "11:00", hasta: "13:00", estado: "prefiere_no" },
    ] };
    expect(validar(s, [])).toContain("se cruzan");
  });
  it("un tramo al revés", () => {
    const s = semanaVacia();
    s[1] = { modo: "horas", tramos: [{ desde: "12:00", hasta: "10:00", estado: "no_puede" }] };
    expect(validar(s, [])).toContain("termina antes de empezar");
  });
  it("tocarse no es cruzarse", () => {
    const s = semanaVacia();
    s[1] = { modo: "horas", tramos: [
      { desde: "08:30", hasta: "12:00", estado: "no_puede" },
      { desde: "12:00", hasta: "13:00", estado: "prefiere_no" },
    ] };
    expect(validar(s, [])).toBeNull();
  });
  it("una fecha con «todo el día» y además un tramo", () => {
    expect(validar(semanaVacia(), [
      { fecha: "2026-11-15", desde: null, hasta: null, estado: "no_puede" },
      { fecha: "2026-11-15", desde: "10:00", hasta: "11:00", estado: "no_puede" },
    ])).toContain("todo el día");
  });
});

describe("las horas libres contra la jornada", () => {
  it("toda la ventana de TRU: 6 × 11.75 + 8.25 = 78.75 h", () => {
    expect(horasDisponibles(semanaVacia(), TRU)).toBeCloseTo(78.75);
  });
  it("solo mañanas: cada día queda de que abre a las 14:00", () => {
    // 6 × 5.5 (08:30–14:00) + 4 (10:00–14:00) = 37
    expect(horasDisponibles(aplicarAtajo(semanaVacia(), "solo_mananas", TRU), TRU)).toBeCloseTo(37);
  });
  it("«prefiero no» sigue contando como disponible; «no puedo» no", () => {
    const s = semanaVacia();
    s[0] = { modo: "prefiere_no", tramos: [] };
    expect(horasDisponibles(s, TRU)).toBeCloseTo(78.75);
    s[0] = { modo: "no_puede", tramos: [] };
    expect(horasDisponibles(s, TRU)).toBeCloseTo(70.5);
  });
  it("sin ventana no se mide, y el aviso solo sale si no alcanza", () => {
    expect(horasDisponibles(semanaVacia(), [])).toBeNull();
    expect(avisoDeHoras(37, 45)).toBe(
      "Con lo que marcaste quedan 37 h disponibles a la semana y tu jornada es de 45 h. Tu líder de equipo lo va a conversar contigo.");
    expect(avisoDeHoras(50, 45)).toBeNull();
    expect(avisoDeHoras(30, null)).toBeNull();
    expect(avisoDeHoras(32.5, 45, "ella")).toBe("Con lo que marcó quedan 32,5 h disponibles a la semana y su jornada es de 45 h.");
  });
});

describe("en palabras", () => {
  it("dice qué no puede, qué prefiere no y las fechas", () => {
    const s = semanaVacia();
    s[2] = { modo: "horas", tramos: [{ desde: "08:30", hasta: "14:00", estado: "no_puede" }] };
    s[4] = { modo: "horas", tramos: [{ desde: "08:30", hasta: "14:00", estado: "no_puede" }] };
    s[0] = { modo: "prefiere_no", tramos: [] };
    expect(resumenEnPalabras(s, [{ fecha: "2026-11-15", desde: "16:00", hasta: "20:00", estado: "no_puede" }])).toEqual([
      "No puedes: los martes de 08:30 a 14:00 y los jueves de 08:30 a 14:00.",
      "Prefieres no: los domingos todo el día.",
      "Además: el 15 nov no puedes de 16:00 a 20:00.",
    ]);
  });
  it("en el panel habla de ella, y sin nada dice que puede todo", () => {
    expect(resumenEnPalabras(semanaVacia(), [], "ella")).toEqual(["Puede cualquier día y hora."]);
    const s = semanaVacia();
    s[6] = { modo: "no_puede", tramos: [] };
    expect(resumenEnPalabras(s, [], "ella")).toEqual(["No puede: los sábados todo el día."]);
  });
});
