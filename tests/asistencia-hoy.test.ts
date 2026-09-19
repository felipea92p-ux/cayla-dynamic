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
import { ESTADOS_JORNADA } from "@cayla-dynamic/shared";
import {
  calcularCoberturaSede,
  desdeLaHora,
  enPausaAhora,
  faltanTexto,
  fechaConDia,
  fechaCorta,
  horaCortaLima,
  loQueFalta,
  minutosDesde,
  motivoDePausa,
  pausaAbiertaDe,
  porPausaMasLarga,
  sinMarcarYaLeTocaba,
  subEstadoSinMarcar,
  textoEquipoDelDia,
  textoPausa,
  textoPausaDesde,
  textoSinMarcar,
  trabajandoAhora,
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

// ----------------------------------------------------------------------------
// El error que originó esta prueba (2026-09-18, 1:48 p. m.): el Dashboard decía
// «OTRU — 4 trabajando de 4 programadas hoy» con las 4 personas en pausa, y
// «14 trabajando ahora» arriba con nueve de esas catorce fuera del piso.
// Estar en pausa (refrigerio, trámite, médico…) NO es estar trabajando.
// ----------------------------------------------------------------------------
describe("trabajandoAhora / enPausaAhora — quien está en pausa no trabaja", () => {
  it("solo `abierta` está trabajando", () => {
    expect(trabajandoAhora("abierta")).toBe(true);
    expect(trabajandoAhora("en_pausa")).toBe(false);
  });

  it("solo `en_pausa` está en pausa", () => {
    expect(enPausaAhora("en_pausa")).toBe(true);
    expect(enPausaAhora("abierta")).toBe(false);
  });

  it("nadie está a la vez trabajando y en pausa, en ninguno de los estados que existen", () => {
    // Recorre el catálogo entero (más «sin_marcar», que no es un estado de
    // jornada sino la ausencia de una): si mañana aparece un estado nuevo, cae
    // acá y obliga a decidir a qué lado va.
    for (const estado of [...ESTADOS_JORNADA, "sin_marcar"]) {
      expect(trabajandoAhora(estado) && enPausaAhora(estado), estado).toBe(false);
    }
  });

  it("quien ya salió, o quedó auto-cerrado, o no marcó, no está trabajando ni en pausa", () => {
    for (const estado of ["cerrada", "revisada", "auto_cerrada_pendiente", "sin_marcar"]) {
      expect(trabajandoAhora(estado), estado).toBe(false);
      expect(enPausaAhora(estado), estado).toBe(false);
    }
  });
});

describe("calcularCoberturaSede — trabajando y en pausa por separado", () => {
  it("la captura de OTRU: cuatro programadas, las cuatro en pausa → nadie trabaja", () => {
    const equipo = [
      fila({ personaId: "a", estado: "en_pausa", entrada: "x" }),
      fila({ personaId: "b", estado: "en_pausa", entrada: "x" }),
      fila({ personaId: "c", estado: "en_pausa", entrada: "x" }),
      fila({ personaId: "d", estado: "en_pausa", entrada: "x" }),
      fila({ personaId: "e", entradaEsperadaHoy: null, origenEsperadoHoy: "turno" }), // descansa
    ];
    const cob = calcularCoberturaSede(equipo, META_0, false, 13.8);
    expect(cob.trabajando).toHaveLength(0);
    expect(cob.enPausa).toHaveLength(4);
    expect(cob.programadosHoy).toBe(4);
    expect(cob.opPiso).toBe(0);
  });

  it("la captura de LIM: dos personas en pausa contra una meta de 4 + 1 → falta todo", () => {
    const equipo = [
      fila({ personaId: "a", estado: "en_pausa", entrada: "x", esEncargada: true }),
      fila({ personaId: "b", estado: "en_pausa", entrada: "x" }),
    ];
    const cob = calcularCoberturaSede(equipo, { man: 4, tar: 4, enc: 1 }, false, 13.8);
    expect(cob.problema).toBe(true);
    expect(loQueFalta(cob)).toBe("4 operativas y 1 líder");
    expect(cob.enPausa).toHaveLength(2); // y la pantalla puede decir que están en el refrigerio
  });

  it("mezcla: quien trabaja y quien está en pausa van en listas distintas", () => {
    const equipo = [
      fila({ personaId: "a", estado: "abierta", entrada: "x" }),
      fila({ personaId: "b", estado: "abierta", entrada: "x" }),
      fila({ personaId: "c", estado: "en_pausa", entrada: "x" }),
      fila({ personaId: "d", estado: "cerrada", entrada: "x", salidaFinal: "y" }),
      fila({ personaId: "e" }), // sin marcar
    ];
    const cob = calcularCoberturaSede(equipo, META_0, false, 10);
    expect(cob.trabajando.map((f) => f.personaId)).toEqual(["a", "b"]);
    expect(cob.enPausa.map((f) => f.personaId)).toEqual(["c"]);
  });

  it("«en piso» sale de la misma lista que «trabajando»: las dos cifras no pueden discrepar", () => {
    const equipo = [
      fila({ personaId: "a", estado: "abierta", entrada: "x" }),
      fila({ personaId: "b", estado: "en_pausa", entrada: "x" }),
    ];
    const cob = calcularCoberturaSede(equipo, { man: 2, tar: 2, enc: 0 }, false, 13);
    expect(cob.opPiso).toBe(cob.trabajando.filter((f) => f.esOperativa).length);
  });

  it("quien trabaja en su día libre cuenta como trabajando, aunque no estuviera programado", () => {
    // Por eso el encabezado ya no dice «N de M programadas»: con este caso salía
    // «1 trabajando de 0 programadas», una razón imposible.
    const equipo = [fila({ estado: "abierta", entrada: "x", entradaEsperadaHoy: null, origenEsperadoHoy: "turno" })];
    const cob = calcularCoberturaSede(equipo, META_0, false, 10);
    expect(cob.trabajando).toHaveLength(1);
    expect(cob.programadosHoy).toBe(0);
  });
});

describe("textoEquipoDelDia — de dónde sale «programadas hoy»", () => {
  it("parte del equipo", () => {
    expect(textoEquipoDelDia(4, 5)).toBe("Hoy les tocaba trabajar a 4 de las 5 personas del equipo.");
    expect(textoEquipoDelDia(1, 5)).toBe("Hoy le tocaba trabajar a 1 de las 5 personas del equipo.");
  });

  it("todo el equipo — LIM en la captura: 2 de 2 NO puede decir «no todas tenían turno»", () => {
    expect(textoEquipoDelDia(2, 2)).toBe("Hoy les tocaba trabajar a las 2 personas del equipo.");
    expect(textoEquipoDelDia(2, 2)).not.toMatch(/no todas/i);
  });

  it("nadie del equipo", () => {
    expect(textoEquipoDelDia(0, 3)).toBe("A ninguna de las 3 personas del equipo le tocaba trabajar hoy.");
  });

  it("una sola persona en el equipo", () => {
    expect(textoEquipoDelDia(1, 1)).toBe("Hoy le tocaba trabajar a la única persona del equipo.");
    expect(textoEquipoDelDia(0, 1)).toBe("A la única persona del equipo no le tocaba trabajar hoy.");
  });

  it("sede sin equipo", () => {
    expect(textoEquipoDelDia(0, 0)).toBe("No hay personas en el equipo de esta sede.");
  });
});

describe("fechaCorta — «14 de diciembre», no «14-diciembre»", () => {
  it("escribe la frase entera, con «de»", () => {
    expect(fechaCorta("2026-12-14")).toBe("14 de diciembre");
  });

  it("nunca deja el guion que armaba el formato de dos dígitos", () => {
    // Era lo que decían los avisos de contratos: «vence en 87 días · 14-diciembre».
    for (const iso of ["2026-12-14", "2026-01-31", "2026-09-05"]) {
      expect(fechaCorta(iso), iso).not.toContain("-");
    }
  });

  it("el día de un dígito va sin cero", () => {
    // «setiembre» es como lo escribe el es-PE (y como se dice en Perú); la
    // expresión acepta las dos formas para no depender de la versión de ICU.
    expect(fechaCorta("2026-09-05")).toMatch(/^5 de sep?tiembre$/);
  });

  it("no corre el día por la zona horaria: 1 de enero sigue siendo 1 de enero", () => {
    expect(fechaCorta("2027-01-01")).toBe("1 de enero");
  });
});

describe("fechaConDia — la pantalla dice qué día es", () => {
  it("día de la semana + fecha, sin coma", () => {
    expect(fechaConDia("2026-12-14")).toBe("lunes 14 de diciembre");
    expect(fechaConDia("2026-09-18")).toMatch(/^viernes 18 de sep?tiembre$/);
  });
});

describe("textoSinMarcar — concordancia", () => {
  it("una persona: «le tocaba»", () => {
    expect(textoSinMarcar(1)).toBe("1 no ha marcado y ya le tocaba entrar");
  });

  it("varias: «les tocaba» (antes decía «2 … ya le tocaba»)", () => {
    expect(textoSinMarcar(2)).toBe("2 no han marcado y ya les tocaba entrar");
    expect(textoSinMarcar(12)).toBe("12 no han marcado y ya les tocaba entrar");
  });
});

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

  it("dice operativas y líderes juntos, en plural o singular según el número", () => {
    expect(loQueFalta(cob({ faltanOp: true, metaOp: 4, opPiso: 0, faltanEnc: true, metaEnc: 1, encPiso: 0 })))
      .toBe("4 operativas y 1 líder");
    expect(loQueFalta(cob({ faltanOp: true, metaOp: 2, opPiso: 1 }))).toBe("1 operativa");
    expect(loQueFalta(cob({ faltanEnc: true, metaEnc: 2, encPiso: 0 }))).toBe("2 líderes");
  });

  it("no dice nada de lo que no falta", () => {
    expect(loQueFalta(cob({}))).toBe("");
  });

  it("«Falta 1» / «Faltan 3»", () => {
    expect(faltanTexto(1)).toBe("Falta 1");
    expect(faltanTexto(3)).toBe("Faltan 3");
  });
});

// ----------------------------------------------------------------------------
// «Desde cuándo» está en pausa. Lima es UTC-5: 18:05Z = 1:05 p. m.
// ----------------------------------------------------------------------------
const marca = (tipo: string, timestamp_marca: string) => ({ tipo, timestamp_marca });
const T = {
  entrada: "2026-09-18T12:00:00Z", // 7:00 a. m.
  almuerzo: "2026-09-18T18:05:00Z", // 1:05 p. m.
  retorno: "2026-09-18T19:10:00Z", // 2:10 p. m.
  tramite: "2026-09-18T21:30:00Z", // 4:30 p. m.
  final: "2026-09-18T23:00:00Z", // 6:00 p. m.
};

describe("pausaAbiertaDe — qué salida sigue abierta", () => {
  it("sin marcas, o solo con la entrada, no hay pausa", () => {
    expect(pausaAbiertaDe([])).toBeNull();
    expect(pausaAbiertaDe([marca("entrada", T.entrada)])).toBeNull();
  });

  it("entró y salió a refrigerio: la pausa empezó en esa salida", () => {
    expect(pausaAbiertaDe([marca("entrada", T.entrada), marca("salida_almuerzo", T.almuerzo)])).toEqual({
      tipo: "salida_almuerzo",
      desde: T.almuerzo,
    });
  });

  it("si ya regresó, no hay pausa", () => {
    const dia = [marca("entrada", T.entrada), marca("salida_almuerzo", T.almuerzo), marca("retorno_almuerzo", T.retorno)];
    expect(pausaAbiertaDe(dia)).toBeNull();
  });

  it("una segunda salida, después de regresar, es OTRA pausa: cuenta desde ella, no desde la primera", () => {
    const dia = [
      marca("entrada", T.entrada),
      marca("salida_almuerzo", T.almuerzo),
      marca("retorno_almuerzo", T.retorno),
      marca("salida_tramite", T.tramite),
    ];
    expect(pausaAbiertaDe(dia)).toEqual({ tipo: "salida_tramite", desde: T.tramite });
  });

  it("con la salida final el día cerró: no hay pausa aunque no haya marcado el retorno", () => {
    const dia = [marca("entrada", T.entrada), marca("salida_almuerzo", T.almuerzo), marca("salida_final", T.final)];
    expect(pausaAbiertaDe(dia)).toBeNull();
  });

  it("dos salidas seguidas sin retorno: manda la última, igual que la base", () => {
    const dia = [marca("entrada", T.entrada), marca("salida_almuerzo", T.almuerzo), marca("salida_personal", T.tramite)];
    expect(pausaAbiertaDe(dia)?.desde).toBe(T.tramite);
  });

  it("un retorno sin salida antes no inventa una pausa", () => {
    expect(pausaAbiertaDe([marca("entrada", T.entrada), marca("retorno_almuerzo", T.retorno)])).toBeNull();
  });

  it("cualquier salida temporal cuenta, también «otra salida»", () => {
    expect(pausaAbiertaDe([marca("salida_otro", T.almuerzo)])?.tipo).toBe("salida_otro");
  });

  it("no depende del orden en que lleguen las marcas", () => {
    const desordenado = [marca("salida_almuerzo", T.almuerzo), marca("entrada", T.entrada), marca("retorno_almuerzo", T.retorno)];
    expect(pausaAbiertaDe(desordenado)).toBeNull();
  });
});

describe("desdeLaHora — «la una» pero «las dos»", () => {
  it("la 1 lleva «la»: es justo la hora del refrigerio", () => {
    expect(desdeLaHora(T.almuerzo)).toBe("desde la 1:05 p. m.");
    expect(desdeLaHora("2026-09-18T06:15:00Z")).toBe("desde la 1:15 a. m.");
  });

  it("el resto lleva «las», incluidas las 12", () => {
    expect(desdeLaHora(T.retorno)).toBe("desde las 2:10 p. m.");
    expect(desdeLaHora("2026-09-18T17:00:00Z")).toBe("desde las 12:00 p. m.");
    expect(desdeLaHora("2026-09-18T05:30:00Z")).toBe("desde las 12:30 a. m.");
  });

  it("la hora se dice en Lima, sin cero a la izquierda", () => {
    expect(horaCortaLima(T.almuerzo)).toBe("1:05 p. m.");
  });
});

describe("minutosDesde y textoPausa — cuánto lleva", () => {
  const ahora = new Date("2026-09-18T18:50:00Z"); // 1:50 p. m.

  it("cuenta minutos completos", () => {
    expect(minutosDesde(T.almuerzo, ahora)).toBe(45);
    expect(minutosDesde(T.almuerzo, new Date("2026-09-18T18:49:59Z"))).toBe(44);
  });

  it("nunca sale negativo si el reloj de la marca va adelantado", () => {
    expect(minutosDesde(T.almuerzo, new Date("2026-09-18T18:00:00Z"))).toBe(0);
  });

  it("en un papel impreso va solo la hora de salida: los minutos envejecen", () => {
    expect(textoPausaDesde({ tipo: "salida_almuerzo", desde: T.almuerzo })).toBe("refrigerio desde la 1:05 p. m.");
    expect(textoPausaDesde({ tipo: "salida_tramite", desde: T.tramite })).toBe("otra salida desde las 4:30 p. m.");
    expect(textoPausaDesde({ tipo: "salida_almuerzo", desde: T.almuerzo })).not.toMatch(/min/);
  });

  it("dice motivo, desde cuándo y cuánto", () => {
    expect(textoPausa({ tipo: "salida_almuerzo", desde: T.almuerzo }, ahora)).toBe("refrigerio desde la 1:05 p. m. · 45 min");
  });

  it("pasada la hora usa horas y minutos", () => {
    const tarde = new Date("2026-09-18T21:25:00Z"); // 4:25 p. m. → 3 h 20 min
    expect(textoPausa({ tipo: "salida_almuerzo", desde: T.almuerzo }, tarde)).toBe("refrigerio desde la 1:05 p. m. · 3h 20m");
  });
});

describe("motivoDePausa — el Dashboard no publica por qué salió", () => {
  it("«refrigerio» es refrigerio", () => {
    expect(motivoDePausa("salida_almuerzo")).toBe("refrigerio");
  });

  it("todo lo demás es «otra salida»: ni «médico» ni «asunto personal» salen en pantalla", () => {
    for (const tipo of ["salida_medico", "salida_personal", "salida_tramite", "salida_otro"]) {
      const dicho = motivoDePausa(tipo);
      expect(dicho, tipo).toBe("otra salida");
      expect(dicho, tipo).not.toMatch(/m[eé]dic|personal|tr[aá]mite/i);
    }
  });
});

describe("porPausaMasLarga — a quién mirar primero", () => {
  const p = (desde: string) => ({ pausa: { tipo: "salida_almuerzo", desde } });

  it("quien salió antes va primero", () => {
    const orden = [p(T.tramite), p(T.almuerzo), p(T.retorno)].sort(porPausaMasLarga);
    expect(orden.map((x) => x.pausa.desde)).toEqual([T.almuerzo, T.retorno, T.tramite]);
  });

  it("quien no tiene dato va al final, no mezclado", () => {
    const sinDato = { pausa: null };
    const orden = [sinDato, p(T.retorno), { }, p(T.almuerzo)].sort(porPausaMasLarga);
    expect(orden[0]).toEqual(p(T.almuerzo));
    expect(orden[1]).toEqual(p(T.retorno));
    expect(orden.slice(2)).toEqual([sinDato, {}]);
  });
});
