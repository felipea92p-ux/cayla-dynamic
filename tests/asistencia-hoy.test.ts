// ============================================================================
// asistencia-hoy.test.ts — la cuenta de «quién está dónde AHORA» en una sede
// ============================================================================
// Esta lógica vivía dentro de la página del Dashboard y no tenía ni una prueba:
// una página de Next no puede exportar funciones, así que probarla exigía abrir
// un navegador. De ella sale el aviso rojo de «sede sin marcajes», el conteo de
// «sin marcar y ya les tocaba» y la cobertura contra la meta — o sea, qué se le
// dice a quien administra sobre la gente de hoy.
//
// El principio que sostiene casi todo lo de acá: los falsos positivos son el
// peor error. Decir «faltó» de quien está de vacaciones, o «sin marcar» de
// quien todavía no le toca entrar, cuesta más que dejar pasar una falta real.
// ============================================================================
import { describe, expect, it } from "vitest";
import {
  calcularCoberturaSede,
  faltanTexto,
  loQueFalta,
  sinMarcarYaLeTocaba,
  subEstadoSinMarcar,
  type FilaPersona,
} from "@/lib/admin/asistencia-hoy";

// Una persona de hoy con valores neutros: sin marcar, le tocaba entrar a las 8.
const fila = (o: Partial<FilaPersona> = {}): FilaPersona => ({
  personaId: "p",
  nombre: "Persona",
  sede: "TRU",
  sedeId: "s1",
  estado: "sin_marcar",
  entrada: null,
  salidaFinal: null,
  minutosTarde: null,
  salidaTemprana: null,
  enPausaSinRetorno: false,
  esOperativa: true,
  esEncargada: false,
  ausenciaHoy: null,
  entradaEsperadaHoy: "08:00",
  origenEsperadoHoy: "turno",
  ...o,
});

const META_0 = { man: 0, tar: 0, enc: 0 };

describe("subEstadoSinMarcar — «sin marcar» son cuatro cosas distintas", () => {
  it("dentro del margen de 30 min todavía es pronto", () => {
    expect(subEstadoSinMarcar(fila(), 8.25)).toBe("aun_no_inicia"); // 8:15
    expect(subEstadoSinMarcar(fila(), 8.49)).toBe("aun_no_inicia"); // 8:29
  });

  it("a las 8:30 en punto ya es una falta real — el margen es inclusivo", () => {
    expect(subEstadoSinMarcar(fila(), 8.5)).toBe("falta_real");
  });

  it("quien entra a las 4 p. m. no es una falta a la 1 p. m.", () => {
    expect(subEstadoSinMarcar(fila({ entradaEsperadaHoy: "16:00" }), 13)).toBe("aun_no_inicia");
  });

  it("si hoy le tocaba descanso, descansa", () => {
    const descansa = fila({ entradaEsperadaHoy: null, origenEsperadoHoy: "turno" });
    expect(subEstadoSinMarcar(descansa, 10)).toBe("descansa");
  });

  it("sin horario NO se afirma que descansa: no se sabe", () => {
    // Decir «descansa hoy» sin saberlo sería una falsa tranquilidad tan mala
    // como el falso positivo que esta distinción existe para evitar.
    const sinHorario = fila({ entradaEsperadaHoy: null, origenEsperadoHoy: "sin_horario" });
    expect(subEstadoSinMarcar(sinHorario, 10)).toBe("desconocido");
  });
});

describe("sinMarcarYaLeTocaba — lo que cuenta el número del resumen", () => {
  it("sin marcar, sin ausencia y ya pasada la hora: cuenta", () => {
    expect(sinMarcarYaLeTocaba(fila(), 9)).toBe(true);
  });

  it("de vacaciones no cuenta, aunque la hora ya haya pasado", () => {
    const vacaciones = fila({ ausenciaHoy: { nombre: "Vacaciones", pendiente: false } });
    expect(sinMarcarYaLeTocaba(vacaciones, 9)).toBe(false);
  });

  it("una ausencia todavía por confirmar tampoco cuenta como falta", () => {
    const porConfirmar = fila({ ausenciaHoy: { nombre: "Descanso médico", pendiente: true } });
    expect(sinMarcarYaLeTocaba(porConfirmar, 9)).toBe(false);
  });

  it("quien ya marcó no cuenta", () => {
    expect(sinMarcarYaLeTocaba(fila({ estado: "abierta", entrada: "2026-09-18T13:00:00Z" }), 9)).toBe(false);
  });

  it("antes de su hora no cuenta", () => {
    expect(sinMarcarYaLeTocaba(fila(), 8.2)).toBe(false);
  });
});

describe("calcularCoberturaSede — la sede contra su meta", () => {
  it("quien está en pausa NO cuenta en piso: no está cubriendo ahora", () => {
    const equipo = [
      fila({ personaId: "a", estado: "abierta", entrada: "x" }),
      fila({ personaId: "b", estado: "en_pausa", entrada: "x" }),
    ];
    const cob = calcularCoberturaSede(equipo, { man: 2, tar: 2, enc: 0 }, false, 13);
    expect(cob.opPiso).toBe(1);
    expect(cob.faltanOp).toBe(true);
    expect(cob.problema).toBe(true);
  });

  it("usa la meta de la tarde después del corte, y la de la mañana antes", () => {
    const equipo = [fila({ estado: "abierta", entrada: "x" })];
    const meta = { man: 1, tar: 3, enc: 0 };
    expect(calcularCoberturaSede(equipo, meta, false, 10).metaOp).toBe(1);
    expect(calcularCoberturaSede(equipo, meta, true, 15).metaOp).toBe(3);
  });

  it("sin meta configurada no es un problema — es neutro", () => {
    const cob = calcularCoberturaSede([fila({ estado: "abierta", entrada: "x" })], META_0, false, 10);
    expect(cob.sinMetaOp).toBe(true);
    expect(cob.sinMetaEnc).toBe(true);
    expect(cob.problema).toBe(false);
  });

  it("cuenta encargadas por su lado", () => {
    const equipo = [
      fila({ personaId: "a", estado: "abierta", entrada: "x", esEncargada: true }),
      fila({ personaId: "b", estado: "abierta", entrada: "x" }),
    ];
    const cob = calcularCoberturaSede(equipo, { man: 0, tar: 0, enc: 2 }, false, 10);
    expect(cob.encPiso).toBe(1);
    expect(cob.faltanEnc).toBe(true);
  });

  it("«programadas hoy» excluye a quien descansa y a quien tiene una ausencia", () => {
    const equipo = [
      fila({ personaId: "a" }),
      fila({ personaId: "b" }),
      fila({ personaId: "c", entradaEsperadaHoy: null, origenEsperadoHoy: "turno" }), // descansa
      fila({ personaId: "d", ausenciaHoy: { nombre: "Vacaciones", pendiente: false } }),
    ];
    expect(calcularCoberturaSede(equipo, META_0, false, 10).programadosHoy).toBe(2);
  });

  it("cuenta los «sin marcar y ya les tocaba» de la sede", () => {
    const equipo = [fila({ personaId: "a" }), fila({ personaId: "b" }), fila({ personaId: "c", estado: "abierta", entrada: "x" })];
    expect(calcularCoberturaSede(equipo, META_0, false, 9).sinMarcarReal).toBe(2);
  });
});

describe("calcularCoberturaSede — la alerta roja de «sede sin marcajes»", () => {
  it("nadie marcó y ya pasó el margen desde la primera entrada esperada: avisa", () => {
    const equipo = [fila({ personaId: "a", entradaEsperadaHoy: "09:00" }), fila({ personaId: "b", entradaEsperadaHoy: "08:00" })];
    expect(calcularCoberturaSede(equipo, META_0, false, 8.5).alertaSinEntrada).toBe("08:00");
  });

  it("todavía dentro del margen: no avisa", () => {
    expect(calcularCoberturaSede([fila()], META_0, false, 8.2).alertaSinEntrada).toBeNull();
  });

  it("si alguien ya marcó, la sede no está «sin marcajes»", () => {
    const equipo = [fila({ personaId: "a" }), fila({ personaId: "b", estado: "abierta", entrada: "x" })];
    expect(calcularCoberturaSede(equipo, META_0, false, 10).alertaSinEntrada).toBeNull();
  });

  it("si todo el equipo está de vacaciones, nadie tenía que llegar: no avisa", () => {
    const vac = { nombre: "Vacaciones", pendiente: false };
    const equipo = [fila({ personaId: "a", ausenciaHoy: vac }), fila({ personaId: "b", ausenciaHoy: vac })];
    expect(calcularCoberturaSede(equipo, META_0, false, 10).alertaSinEntrada).toBeNull();
  });

  it("si a nadie le tocaba trabajar hoy, no avisa", () => {
    const equipo = [fila({ entradaEsperadaHoy: null, origenEsperadoHoy: "turno" })];
    expect(calcularCoberturaSede(equipo, META_0, false, 10).alertaSinEntrada).toBeNull();
  });
});

describe("loQueFalta y faltanTexto — concordancia", () => {
  const cob = (o: Partial<ReturnType<typeof calcularCoberturaSede>>) => ({
    ...calcularCoberturaSede([], META_0, false, 10),
    ...o,
  });

  it("dice operativas y encargadas juntas, en plural o singular según el número", () => {
    expect(loQueFalta(cob({ faltanOp: true, metaOp: 4, opPiso: 0, faltanEnc: true, metaEnc: 1, encPiso: 0 })))
      .toBe("4 operativas y 1 encargada");
    expect(loQueFalta(cob({ faltanOp: true, metaOp: 2, opPiso: 1 }))).toBe("1 operativa");
    expect(loQueFalta(cob({ faltanEnc: true, metaEnc: 2, encPiso: 0 }))).toBe("2 encargadas");
  });

  it("no dice nada de lo que no falta", () => {
    expect(loQueFalta(cob({}))).toBe("");
  });

  it("«Falta 1» / «Faltan 3»", () => {
    expect(faltanTexto(1)).toBe("Falta 1");
    expect(faltanTexto(3)).toBe("Faltan 3");
  });
});
