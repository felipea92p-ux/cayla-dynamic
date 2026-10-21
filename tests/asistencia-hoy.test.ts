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
  causaMetaImposible,
  coincideConFiltroDeEstado,
  desdeLaHora,
  enPausaAhora,
  faltanTexto,
  fechaConDia,
  fechaCorta,
  fueraDeHorarioDeHoy,
  horaCortaLima,
  llegaronTarde,
  llegoTarde,
  loQueFalta,
  diaDeLaSemanaEnPlural,
  metaDelDiaTexto,
  marcaronSinHorario,
  minutosDesde,
  motivoDePausa,
  OPCIONES_FILTRO_ESTADO,
  pausaAbiertaDe,
  porPausaMasLarga,
  sinMarcarYaLeTocaba,
  subEstadoSinMarcar,
  textoDesglose,
  textoEquipoDelDia,
  textoFueraDeHorario,
  textoLiderEnLasDosMetas,
  textoMetaPorRevisar,
  textoMetaSinTurnos,
  TEXTO_FERIADO_SIN_CONFIRMAR,
  textoPausa,
  textoPausaDesde,
  textoSinHorario,
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

// El espacio entre «1:05», «p.» y «m.» no lo escribe este código: lo pone el
// motor de idiomas que trae Node, y según su versión es uno normal o uno que no
// se corta (U+00A0, U+202F), para que «p.» y «m.» no queden en dos renglones.
// A la vista son idénticos, y en la sede lo decide el Safari de la Mac mini, no
// nosotros. Con Node 22 (CI) y 24 sale el normal; el 2026-10-01 un contenedor
// con otro Node sacó el especial y estas seis pruebas frenaron un push que solo
// traía documentación. Por eso se igualan ANTES de comparar — y solo esos dos:
// si el motor cambiara «p. m.» por «PM», la prueba lo tiene que seguir cazando.
const conEspacioNormal = (texto: string) => texto.replace(/[\u00a0\u202f]/g, " ");

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
    expect(conEspacioNormal(desdeLaHora(T.almuerzo))).toBe("desde la 1:05 p. m.");
    expect(conEspacioNormal(desdeLaHora("2026-09-18T06:15:00Z"))).toBe("desde la 1:15 a. m.");
  });

  it("el resto lleva «las», incluidas las 12", () => {
    expect(conEspacioNormal(desdeLaHora(T.retorno))).toBe("desde las 2:10 p. m.");
    expect(conEspacioNormal(desdeLaHora("2026-09-18T17:00:00Z"))).toBe("desde las 12:00 p. m.");
    expect(conEspacioNormal(desdeLaHora("2026-09-18T05:30:00Z"))).toBe("desde las 12:30 a. m.");
  });

  it("la hora se dice en Lima, sin cero a la izquierda", () => {
    expect(conEspacioNormal(horaCortaLima(T.almuerzo))).toBe("1:05 p. m.");
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
    expect(conEspacioNormal(textoPausaDesde({ tipo: "salida_almuerzo", desde: T.almuerzo }))).toBe("refrigerio desde la 1:05 p. m.");
    expect(conEspacioNormal(textoPausaDesde({ tipo: "salida_tramite", desde: T.tramite }))).toBe("otra salida desde las 4:30 p. m.");
    expect(textoPausaDesde({ tipo: "salida_almuerzo", desde: T.almuerzo })).not.toMatch(/min/);
  });

  it("dice motivo, desde cuándo y cuánto", () => {
    expect(conEspacioNormal(textoPausa({ tipo: "salida_almuerzo", desde: T.almuerzo }, ahora))).toBe("refrigerio desde la 1:05 p. m. · 45 min");
  });

  it("pasada la hora usa horas y minutos", () => {
    const tarde = new Date("2026-09-18T21:25:00Z"); // 4:25 p. m. → 3 h 20 min
    expect(conEspacioNormal(textoPausa({ tipo: "salida_almuerzo", desde: T.almuerzo }, tarde))).toBe("refrigerio desde la 1:05 p. m. · 3h 20m");
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

// ----------------------------------------------------------------------------
// Central (2026-09-18): solo administración. Nadie de un área operativa, nadie
// marcado como líder de piso —Felipe es admin, y la marca `es_encargada_piso`
// que haría contar a un admin no tiene ninguna pantalla para ponerla— y aun así
// la sede tenía una meta de 1 líder en piso. Resultado: «Cobertura insuficiente
// · Falta 1» todos los días, sin nada que nadie pudiera hacer para apagarla.
// ----------------------------------------------------------------------------
describe("el equipo que PODRÍA cubrir cada meta", () => {
  it("cuenta a quien es operativa o líder aunque hoy no esté", () => {
    const equipo = [
      fila({ personaId: "a", esOperativa: true, estado: "abierta", entrada: "x" }),
      fila({ personaId: "b", esOperativa: true }),                        // no ha llegado
      fila({ personaId: "c", esOperativa: false, esEncargada: true }),   // líder, hoy sin marcar
      fila({ personaId: "d", esOperativa: false, estado: "cerrada", entrada: "x", salidaFinal: "y" }),
    ];
    const cob = calcularCoberturaSede(equipo, META_0, false, 10);
    expect(cob.equipoOperativas).toBe(2);
    expect(cob.equipoLideres).toBe(1);
  });

  it("Central: dos administradores trabajando, ninguno operativo ni líder, meta de 1 líder", () => {
    const equipo = [
      fila({ personaId: "a", esOperativa: false, esEncargada: false, estado: "abierta", entrada: "x" }),
      fila({ personaId: "b", esOperativa: false, esEncargada: false, estado: "abierta", entrada: "x", entradaEsperadaHoy: null }),
    ];
    const cob = calcularCoberturaSede(equipo, { man: 0, tar: 0, enc: 1 }, false, 13);
    expect(cob.trabajando).toHaveLength(2);
    expect(cob.equipoOperativas).toBe(0);
    expect(cob.equipoLideres).toBe(0);
    // La falta sigue siendo cierta según la meta (`problema`), y se sabe POR QUÉ
    // (ver causaMetaImposible). Desde la decisión del 2026-09-18 ya no es ROJO: no
    // falta gente que pueda venir, falta que alguien revise la meta en Turnos.
    expect(cob.faltanEnc).toBe(true);
    expect(cob.problema).toBe(true);
    expect(cob.gravedad).toBe("revisar");
  });
});

describe("causaMetaImposible — por qué una meta no se cumple aunque vengan todos", () => {
  it("sin meta, o con equipo de sobra: no hay nada que explicar", () => {
    expect(causaMetaImposible("lideres", 0, 0)).toBeNull();
    expect(causaMetaImposible("operativas", 3, 3)).toBeNull();
    expect(causaMetaImposible("operativas", 3, 8)).toBeNull();
  });

  it("Central: meta de 1 líder y nadie del equipo cuenta como líder", () => {
    const c = causaMetaImposible("lideres", 1, 0)!;
    expect(c.resumen).toBe("nadie del equipo cuenta como líder");
    expect(c.detalle).toBe("Nadie del equipo cuenta como líder. Si esta sede no lo necesita, pon la meta en 0 en Turnos.");
  });

  it("meta de operativas y nadie del equipo es de un área operativa", () => {
    expect(causaMetaImposible("operativas", 2, 0)!.resumen).toBe("nadie del equipo es de un área operativa");
  });

  it("LIM: meta de 4 operativas con solo 2 personas que cuentan", () => {
    const c = causaMetaImposible("operativas", 4, 2)!;
    expect(c.resumen).toBe("la meta es mayor que el equipo");
    expect(c.detalle).toBe("La meta (4) es mayor que las 2 personas del equipo que cuentan: aunque vengan todas, no se cumple.");
  });

  it("una sola persona que cuenta, concordancia en singular", () => {
    expect(causaMetaImposible("operativas", 2, 1)!.detalle)
      .toBe("La meta (2) es mayor que la única persona del equipo que cuenta: aunque venga, no se cumple.");
  });
});

// ----------------------------------------------------------------------------
// El error de la captura de 2026-09-18, entre el cierre de TRU y el de AQP:
// «TRU — Cobertura insuficiente · Faltan 8 · Faltan 2», con sus doce personas
// ya idas (la última salió a las 20:23), una descansando y otra sin horario.
// La meta «de la tarde» corría de 14:15 a medianoche: el Dashboard no sabía
// cuándo cierra una tienda. Los números de estas pruebas salen de la base real.
// ----------------------------------------------------------------------------
describe("fueraDeHorarioDeHoy — la meta no se mide fuera del horario de la sede", () => {
  // Lo que ya salió: cerró su jornada y su horario de hoy terminaba a `salida`.
  const yaSalio = (id: string, salida = "20:15", o: Partial<FilaPersona> = {}) =>
    fila({ personaId: id, estado: "cerrada", entrada: "x", salidaFinal: "y", entradaEsperadaHoy: "07:45", salidaEsperadaHoy: salida, ...o });

  // TRU del viernes 2026-09-18: 10 programadas (todas ya salieron), Danitza descansa
  // (su día 5 no está en sus días) y María trabajó sin ningún horario vigente.
  const truTrasElCierre = () => [
    ...["a", "b", "c", "d", "e", "f", "g"].map((id) => yaSalio(id)),
    yaSalio("h", "19:45"), yaSalio("i", "19:45"), yaSalio("j", "13:45"),
    fila({ personaId: "k", entradaEsperadaHoy: null, origenEsperadoHoy: "horario" }), // descansa
    fila({ personaId: "l", estado: "cerrada", entrada: "x", salidaFinal: "y", entradaEsperadaHoy: null, origenEsperadoHoy: "sin_horario" }),
  ];
  const META_TRU = { man: 7, tar: 8, enc: 2 };

  it("TRU a las 21:00, ya sin nadie: no faltan 8 — está fuera de horario", () => {
    const cob = calcularCoberturaSede(truTrasElCierre(), META_TRU, true, 21);
    expect(cob.programadosHoy).toBe(10);
    expect(cob.fueraDeHorario).toEqual({ cuando: "despues", hora: "20:15" });
    expect(cob.faltanOp).toBe(false);
    expect(cob.faltanEnc).toBe(false);
    expect(cob.problema).toBe(false);
    expect(loQueFalta(cob)).toBe("");
  });

  it("TRU a las 15:00, misma gente ya idas, sigue siendo rojo: todavía es horario de tienda", () => {
    const cob = calcularCoberturaSede(truTrasElCierre(), META_TRU, true, 15);
    expect(cob.fueraDeHorario).toBeNull();
    expect(cob.problema).toBe(true);
    expect(loQueFalta(cob)).toBe("8 operativas y 2 líderes");
  });

  it("queda alguien en piso pasada la última salida: se sigue midiendo (solo si ya no queda nadie)", () => {
    const equipo = [...truTrasElCierre(), fila({ personaId: "z", estado: "abierta", entrada: "x", salidaEsperadaHoy: "20:15" })];
    const cob = calcularCoberturaSede(equipo, META_TRU, true, 20.2);
    expect(cob.fueraDeHorario).toBeNull();
    expect(cob.problema).toBe(true);
  });

  it("quien está en pausa también cuenta como «queda alguien»", () => {
    const equipo = [...truTrasElCierre(), fila({ personaId: "z", estado: "en_pausa", entrada: "x", salidaEsperadaHoy: "20:15" })];
    expect(calcularCoberturaSede(equipo, META_TRU, true, 21).fueraDeHorario).toBeNull();
  });

  it("antes de abrir: a las 6:30 con la primera entrada a las 7:45, no faltan las ocho", () => {
    const equipo = ["a", "b", "c"].map((id) => fila({ personaId: id, entradaEsperadaHoy: "07:45", salidaEsperadaHoy: "20:15" }));
    const cob = calcularCoberturaSede(equipo, META_TRU, false, 6.5);
    expect(cob.fueraDeHorario).toEqual({ cuando: "antes", hora: "07:45" });
    expect(cob.problema).toBe(false);
  });

  it("pasada la primera entrada con nadie en piso SIGUE siendo rojo: les tocaba y no llegaron", () => {
    // La otra cara: apagar el rojo aquí escondería una sede entera que no abrió.
    const equipo = ["a", "b", "c"].map((id) => fila({ personaId: id, entradaEsperadaHoy: "07:45", salidaEsperadaHoy: "20:15" }));
    const cob = calcularCoberturaSede(equipo, META_TRU, false, 9);
    expect(cob.fueraDeHorario).toBeNull();
    expect(cob.problema).toBe(true);
  });

  it("si a alguien le falta la hora de salida, no se sabe cuándo termina el día: no lo da por cerrado", () => {
    const equipo = [yaSalio("a"), yaSalio("b", "20:15", { salidaEsperadaHoy: null })];
    expect(calcularCoberturaSede(equipo, META_TRU, true, 21).fueraDeHorario).toBeNull();
    // Y sin el campo en absoluto (una fila armada por una pantalla que no lo manda), igual.
    const sinCampo = fila({ estado: "cerrada", entrada: "x", salidaFinal: "y", entradaEsperadaHoy: "07:45" });
    expect(calcularCoberturaSede([sinCampo], META_TRU, true, 21).fueraDeHorario).toBeNull();
  });

  it("a nadie le tocaba hoy: no hay horario contra qué medir, sigue como estaba", () => {
    const equipo = [fila({ personaId: "a", entradaEsperadaHoy: null, origenEsperadoHoy: "horario" })];
    const cob = calcularCoberturaSede(equipo, META_TRU, true, 21);
    expect(cob.fueraDeHorario).toBeNull();
    expect(cob.problema).toBe(true);
  });

  it("un turno que cruza medianoche no se da por cerrado a las 22:00", () => {
    // Entra a las 21:00 y sale a las 05:00: a las 22:00 sin haber llegado, es falta.
    const equipo = [fila({ personaId: "a", entradaEsperadaHoy: "21:00", salidaEsperadaHoy: "05:00" })];
    expect(calcularCoberturaSede(equipo, META_TRU, true, 22).fueraDeHorario).toBeNull();
  });

  it("quien está de vacaciones no fija el horario de la sede", () => {
    const equipo = [
      ...truTrasElCierre(),
      fila({ personaId: "v", entradaEsperadaHoy: "10:00", salidaEsperadaHoy: "23:00", ausenciaHoy: { nombre: "Vacaciones", pendiente: false } }),
    ];
    expect(calcularCoberturaSede(equipo, META_TRU, true, 21).fueraDeHorario).toEqual({ cuando: "despues", hora: "20:15" });
  });

  it("es una función pura del horario: sin gente programada no dice nada", () => {
    expect(fueraDeHorarioDeHoy([], false, 21)).toBeNull();
  });
});

describe("desgloseProgramadas — dónde está cada quien a quien le tocaba hoy", () => {
  it("reparte a todas las programadas, sin sobrar ni faltar", () => {
    const equipo = [
      fila({ personaId: "a", estado: "abierta", entrada: "x" }),
      fila({ personaId: "b", estado: "en_pausa", entrada: "x" }),
      fila({ personaId: "c", estado: "cerrada", entrada: "x", salidaFinal: "y" }),
      fila({ personaId: "d", estado: "cerrada", entrada: "x", salidaFinal: "y" }),
      fila({ personaId: "e", estado: "revisada", entrada: "x", salidaFinal: "y" }),
      fila({ personaId: "f", estado: "auto_cerrada_pendiente", entrada: "x" }),
      fila({ personaId: "g", entradaEsperadaHoy: "15:00" }),           // sin marcar, todavía no es su hora
      fila({ personaId: "h", entradaEsperadaHoy: "08:00" }),           // sin marcar, ya le tocaba
      fila({ personaId: "i", entradaEsperadaHoy: null, origenEsperadoHoy: "turno" }),   // descansa: no entra
      fila({ personaId: "j", ausenciaHoy: { nombre: "Vacaciones", pendiente: false } }), // ausente: no entra
    ];
    const cob = calcularCoberturaSede(equipo, META_0, false, 13);
    expect(cob.desgloseProgramadas).toEqual({ enPiso: 1, enPausa: 1, yaSalieron: 4, aunNoLlegan: 1, noLlegaron: 1 });
    const d = cob.desgloseProgramadas;
    expect(d.enPiso + d.enPausa + d.yaSalieron + d.aunNoLlegan + d.noLlegaron).toBe(cob.programadosHoy);
  });

  it("cualquier estado posible de la jornada cae en exactamente un grupo", () => {
    // Si mañana la base agrega un estado, esta prueba dice dónde cae en vez de
    // dejar a una persona sin contar.
    for (const estado of [...ESTADOS_JORNADA, "sin_marcar"]) {
      const cob = calcularCoberturaSede([fila({ estado })], META_0, false, 13);
      const d = cob.desgloseProgramadas;
      expect(d.enPiso + d.enPausa + d.yaSalieron + d.aunNoLlegan + d.noLlegaron, estado).toBe(1);
    }
  });

  it("TRU tras el cierre: las diez programadas ya salieron", () => {
    const equipo = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"].map((id) =>
      fila({ personaId: id, estado: "cerrada", entrada: "x", salidaFinal: "y" }),
    );
    expect(calcularCoberturaSede(equipo, META_0, false, 21).desgloseProgramadas).toEqual({
      enPiso: 0, enPausa: 0, yaSalieron: 10, aunNoLlegan: 0, noLlegaron: 0,
    });
  });
});

describe("textoDesglose — lo que sigue a «Nadie está trabajando en este momento»", () => {
  const cero = { enPiso: 0, enPausa: 0, yaSalieron: 0, aunNoLlegan: 0, noLlegaron: 0 };

  it("nombra solo lo que existe, con concordancia", () => {
    expect(textoDesglose({ ...cero, yaSalieron: 10 })).toBe("Según el horario de hoy: 10 ya salieron.");
    expect(textoDesglose({ ...cero, yaSalieron: 6, aunNoLlegan: 3, noLlegaron: 1 }))
      .toBe("Según el horario de hoy: 6 ya salieron · 3 aún no llegan · 1 no llegó y ya le tocaba.");
    expect(textoDesglose({ ...cero, yaSalieron: 1, aunNoLlegan: 1, noLlegaron: 2 }))
      .toBe("Según el horario de hoy: 1 ya salió · 1 aún no llega · 2 no llegaron y ya les tocaba.");
  });

  it("dice a quien está en pausa, para que la suma cuadre con el total de programadas", () => {
    expect(textoDesglose({ ...cero, enPausa: 2, yaSalieron: 1 })).toBe("Según el horario de hoy: 2 en pausa · 1 ya salió.");
  });

  it("si a nadie le tocaba hoy no hay nada que desglosar", () => {
    expect(textoDesglose(cero)).toBeNull();
  });
});

describe("textoFueraDeHorario — por qué la meta no se mide", () => {
  it("después de la última salida", () => {
    expect(textoFueraDeHorario({ cuando: "despues", hora: "20:15" }, "8:15 p. m."))
      .toBe("Ya pasó la última salida programada de hoy (8:15 p. m.) y nadie sigue en piso: la meta no se mide.");
  });
  it("antes de la primera entrada", () => {
    expect(textoFueraDeHorario({ cuando: "antes", hora: "07:45" }, "7:45 a. m."))
      .toBe("Todavía no llega la primera entrada programada de hoy (7:45 a. m.): la meta no se mide.");
  });
});

describe("la líder que cuenta en las dos metas (AQP, 2026-09-18)", () => {
  // «2 trabajando ahora» pero «2/2 operativas» + «1/1 líderes»: la líder de la
  // tienda es de un área operativa Y líder, y se cuenta en ambos recuadros.
  const aqp = [
    fila({ personaId: "sandra", estado: "abierta", entrada: "x", esOperativa: true, esEncargada: true }),
    fila({ personaId: "mateo", estado: "abierta", entrada: "x", esOperativa: true, esEncargada: false }),
  ];

  it("dos personas en piso llenan una meta de 2 operativas y 1 líder", () => {
    const cob = calcularCoberturaSede(aqp, { man: 2, tar: 2, enc: 1 }, true, 18);
    expect(cob.trabajando).toHaveLength(2);
    expect(cob.opPiso).toBe(2);
    expect(cob.encPiso).toBe(1);
    expect(cob.problema).toBe(false);
    expect(cob.lideresEnAmbasMetas).toBe(1);
  });

  it("solo cuenta a quien está en piso AHORA, no a toda el equipo", () => {
    const equipo = [{ ...aqp[0], estado: "cerrada" }, aqp[1]];
    expect(calcularCoberturaSede(equipo, META_0, true, 18).lideresEnAmbasMetas).toBe(0);
  });

  it("el aviso concuerda y calla cuando no aplica", () => {
    expect(textoLiderEnLasDosMetas(1)).toBe("1 líder de equipo cuenta en las dos metas: personal operativo y líderes.");
    expect(textoLiderEnLasDosMetas(2)).toBe("2 líderes de equipo cuentan en las dos metas: personal operativo y líderes.");
    expect(textoLiderEnLasDosMetas(0)).toBeNull();
  });
});

// ----------------------------------------------------------------------------
// El filtro «Estado» (2026-09-18): la tabla escribe «Salió (revisada)» para quien
// tiene la jornada `revisada`, pero el filtro «Salió» solo buscaba `cerrada`. En
// OTRU, tres de las cuatro personas que se habían ido no aparecían al filtrar.
// ----------------------------------------------------------------------------
describe("coincideConFiltroDeEstado — «Salió» también trae a quien tiene la jornada revisada", () => {
  it("OTRU: de cuatro que se fueron (tres revisadas, una cerrada), «Salió» trae a las cuatro", () => {
    const salieron = ["revisada", "revisada", "revisada", "cerrada"];
    expect(salieron.filter((e) => coincideConFiltroDeEstado(e, "cerrada"))).toHaveLength(4);
  });

  it("«Salió» no trae a quien sigue en el piso, en pausa, sin marcar ni auto-cerrada", () => {
    for (const estado of ["abierta", "en_pausa", "sin_marcar", "auto_cerrada_pendiente"]) {
      expect(coincideConFiltroDeEstado(estado, "cerrada"), estado).toBe(false);
    }
  });

  it("las demás opciones siguen siendo exactas: `revisada` no se cuela en ninguna", () => {
    for (const filtro of ["abierta", "en_pausa", "sin_marcar", "auto_cerrada_pendiente"]) {
      expect(coincideConFiltroDeEstado("revisada", filtro), filtro).toBe(false);
      expect(coincideConFiltroDeEstado(filtro, filtro), filtro).toBe(true);
    }
  });

  it("«Todos» trae a todos", () => {
    for (const estado of [...ESTADOS_JORNADA, "sin_marcar"]) {
      expect(coincideConFiltroDeEstado(estado, "todos"), estado).toBe(true);
    }
  });

  it("ningún estado de jornada queda sin una opción del filtro que lo encuentre", () => {
    // Si mañana la base agrega un estado, esta prueba dice que el filtro no lo
    // alcanza — en vez de descubrirlo cuando alguien no encuentre a una persona.
    for (const estado of [...ESTADOS_JORNADA, "sin_marcar"]) {
      expect(OPCIONES_FILTRO_ESTADO.some((o) => coincideConFiltroDeEstado(estado, o.valor)), estado).toBe(true);
    }
  });
});

// ----------------------------------------------------------------------------
// TRU, 2026-09-18: trabajaron 11 y la pantalla decía «les tocaba a 10 de las 12».
// La undécima marcó de 14:14 a 19:30 sin tener horario vigente NI turno: nada la
// medía —ni tardanza ni falta— y nadie se enteraba.
// ----------------------------------------------------------------------------
describe("marcaronSinHorario — quien trabajó sin nada contra qué medirlo", () => {
  const sinHorario = (o: Partial<FilaPersona> = {}) =>
    fila({ estado: "cerrada", entrada: "14:14", salidaFinal: "19:30", entradaEsperadaHoy: null, origenEsperadoHoy: "sin_horario", ...o });

  it("la de TRU: marcó, sin horario ni turno, y es del personal operativo", () => {
    const equipo = [sinHorario({ personaId: "maria", nombre: "María" }), fila({ personaId: "otra", estado: "cerrada", entrada: "x" })];
    const cob = calcularCoberturaSede(equipo, META_0, true, 21);
    expect(cob.marcaronSinHorario.map((f) => f.personaId)).toEqual(["maria"]);
    // Y por eso no está en «les tocaba»: el aviso existe para decirlo.
    expect(cob.programadosHoy).toBe(1);
  });

  it("quien descansa (horario o turno que dice que hoy no) NO es «sin horario»", () => {
    // Descansar es una respuesta; no tener horario, no. Confundirlas sería acusar a quien libra.
    const descansa = fila({ estado: "cerrada", entrada: "x", entradaEsperadaHoy: null, origenEsperadoHoy: "horario" });
    expect(marcaronSinHorario([descansa])).toEqual([]);
  });

  it("quien no marcó no cuenta: sin marcar y sin horario no es una falta, es un dato que falta", () => {
    expect(marcaronSinHorario([sinHorario({ entrada: null, estado: "sin_marcar" })])).toEqual([]);
  });

  it("un administrador de Central sin horario no dispara el aviso todos los días", () => {
    expect(marcaronSinHorario([sinHorario({ esOperativa: false, esEncargada: false })])).toEqual([]);
  });

  it("un líder que no es de un área operativa SÍ cuenta", () => {
    expect(marcaronSinHorario([sinHorario({ esOperativa: false, esEncargada: true })])).toHaveLength(1);
  });
});

describe("textoSinHorario — quién, y dónde se arregla", () => {
  it("concuerda con una, dos o tres personas", () => {
    expect(textoSinHorario(["María Orbegoso"]))
      .toBe("María Orbegoso marcó hoy sin horario ni turno asignado, así que nada mide su puntualidad. Se arregla en Horarios.");
    expect(textoSinHorario(["Ana", "Luz"]))
      .toBe("Ana y Luz marcaron hoy sin horario ni turno asignado, así que nada mide su puntualidad. Se arregla en Horarios.");
    expect(textoSinHorario(["Ana", "Luz", "Eva"]))
      .toBe("Ana, Luz y Eva marcaron hoy sin horario ni turno asignado, así que nada mide su puntualidad. Se arregla en Horarios.");
  });

  it("sin nadie, no dice nada", () => {
    expect(textoSinHorario([])).toBeNull();
  });
});

// ----------------------------------------------------------------------------
// Meta imposible = ámbar, no rojo (decisión del 2026-09-18). LIM tenía meta de 4
// operativas con 3 personas activas, y CCO meta de 1 líder sin nadie que cuente
// como líder: rojo todos los días, sin que nadie pudiera apagarlo trabajando.
// ----------------------------------------------------------------------------
describe("gravedad — rojo si falta gente que podría venir, ámbar si la meta no se puede cumplir", () => {
  const enPiso = (o: Partial<FilaPersona> = {}) => fila({ estado: "abierta", entrada: "x", ...o });

  it("LIM: meta de 4 con 2 operativas en piso y la líder cumplida → ámbar, aunque «falte»", () => {
    const equipo = [enPiso({ personaId: "raquel", esEncargada: true }), enPiso({ personaId: "joselyn" })];
    const cob = calcularCoberturaSede(equipo, { man: 4, tar: 4, enc: 1 }, false, 15);
    expect(cob.faltanOp).toBe(true);
    expect(cob.metaOpImposible).toBe(true);
    expect(cob.metaEncImposible).toBe(false);
    expect(cob.problema).toBe(true);
    expect(cob.gravedad).toBe("revisar");
  });

  it("CCO: meta de 1 líder sin nadie que cuente como líder → ámbar", () => {
    const equipo = [enPiso({ esOperativa: false, esEncargada: false })];
    const cob = calcularCoberturaSede(equipo, { man: 0, tar: 0, enc: 1 }, false, 15);
    expect(cob.metaEncImposible).toBe(true);
    expect(cob.gravedad).toBe("revisar");
  });

  it("LIM cuando la líder que SÍ existe se fue: falta gente que podría venir → rojo", () => {
    // Mezcla: la meta de operativas es imposible, pero la de líderes se podría
    // cumplir (hay una líder en el equipo) y hoy no está. Manda lo que es cierto.
    const equipo = [
      fila({ personaId: "raquel", estado: "cerrada", entrada: "x", salidaFinal: "y", esEncargada: true }),
      enPiso({ personaId: "joselyn" }),
    ];
    const cob = calcularCoberturaSede(equipo, { man: 4, tar: 4, enc: 1 }, false, 15);
    expect(cob.metaOpImposible).toBe(true);
    expect(cob.metaEncImposible).toBe(false);
    expect(cob.gravedad).toBe("alerta");
  });

  it("TRU a las 15:00 sin nadie en piso: falta gente real → rojo", () => {
    const equipo = Array.from({ length: 12 }, (_, i) => fila({ personaId: `p${i}`, estado: "cerrada", entrada: "x", salidaFinal: "y", esEncargada: i < 4 }));
    const cob = calcularCoberturaSede(equipo, { man: 7, tar: 8, enc: 2 }, true, 15);
    expect(cob.gravedad).toBe("alerta");
  });

  it("sin nada que falte, o fuera de horario, no hay gravedad", () => {
    const equipo = [enPiso({ personaId: "a" }), enPiso({ personaId: "b" })];
    expect(calcularCoberturaSede(equipo, { man: 2, tar: 2, enc: 0 }, false, 15).gravedad).toBeNull();
    const tarde = [fila({ estado: "cerrada", entrada: "x", salidaFinal: "y", salidaEsperadaHoy: "20:15" })];
    const cob = calcularCoberturaSede(tarde, { man: 4, tar: 4, enc: 1 }, true, 21);
    expect(cob.fueraDeHorario).not.toBeNull();
    expect(cob.gravedad).toBeNull();
    expect(cob.metaOpImposible).toBe(false); // fuera de horario nada «falta», ni siquiera lo imposible
  });

  it("COSTO CONOCIDO: una tienda que pierde a su única líder también sale ámbar", () => {
    // Equipo 0 contra meta 1 es lo mismo que una meta mal cargada: sin historia no
    // se distinguen. Está escrito acá para que nadie lo descubra por sorpresa.
    const equipo = [enPiso({ esEncargada: false })];
    expect(calcularCoberturaSede(equipo, { man: 0, tar: 0, enc: 1 }, false, 15).gravedad).toBe("revisar");
  });
});

describe("textoMetaPorRevisar — qué meta, por qué, y dónde se arregla", () => {
  it("LIM: meta de operativas mayor que el equipo", () => {
    const equipo = [
      fila({ personaId: "raquel", estado: "abierta", entrada: "x", esEncargada: true }),
      fila({ personaId: "joselyn", estado: "abierta", entrada: "x" }),
    ];
    const cob = calcularCoberturaSede(equipo, { man: 4, tar: 4, enc: 1 }, false, 15);
    expect(textoMetaPorRevisar(cob)).toBe("revisa la meta en Turnos — personal operativo: la meta es mayor que el equipo");
  });

  it("CCO: nadie cuenta como líder", () => {
    const cob = calcularCoberturaSede([fila({ estado: "abierta", entrada: "x", esOperativa: false })], { man: 0, tar: 0, enc: 1 }, false, 15);
    expect(textoMetaPorRevisar(cob)).toBe("revisa la meta en Turnos — líderes: nadie del equipo cuenta como líder");
  });
});

// ----------------------------------------------------------------------------
// Domingo 2026-09-20. El Dashboard decía «Sin meta configurada» de tres sedes que
// simplemente no abren los domingos —a nadie le toca, y su meta de ese día es 0
// a propósito— y «Cobertura insuficiente · falta 1 líder» de Central, donde
// tampoco le tocaba a nadie. Las dos cosas mentían: la primera pide configurar
// algo que ya está configurado, la segunda alarma por una falta que ninguna
// asistencia puede arreglar.
//
// «Hoy no abre» es un hecho del DÍA (nadie tiene turno y nadie marcó), y sale de
// calcularCoberturaSede como `sinTurnosHoy`. Con meta, es una contradicción de
// datos (`metaSinTurnos`) y se arregla en Turnos: ámbar, no rojo.
// ----------------------------------------------------------------------------
describe("sinTurnosHoy — una sede que hoy no abre", () => {
  // Quien hoy descansa según su horario: una respuesta real, no «sin horario».
  const descansa = (id: string, o: Partial<FilaPersona> = {}) =>
    fila({ personaId: id, entradaEsperadaHoy: null, origenEsperadoHoy: "horario", ...o });

  it("AQP un domingo: dos personas que descansan y meta 0 → no abre, y nada se alarma", () => {
    const cob = calcularCoberturaSede([descansa("a"), descansa("b")], META_0, false, 10);
    expect(cob.sinTurnosHoy).toBe(true);
    expect(cob.hayMetaHoy).toBe(false);
    expect(cob.noAbreHoy).toBe(true);
    expect(cob.metaSinTurnos).toBe(false);
    expect(cob.programadosHoy).toBe(0);
    expect(cob.gravedad).toBeNull();
    expect(cob.problema).toBe(false);
  });

  it("Central un domingo: meta de 1 líder y a nadie le toca → ámbar, NO rojo", () => {
    const equipo = [descansa("a", { esOperativa: false, esEncargada: true }), descansa("b", { esOperativa: false })];
    const cob = calcularCoberturaSede(equipo, { man: 0, tar: 0, enc: 1 }, false, 10);
    expect(cob.sinTurnosHoy).toBe(true);
    expect(cob.metaSinTurnos).toBe(true);
    expect(cob.noAbreHoy).toBe(false); // con meta no es «no abre»: es una contradicción por revisar
    // Sí «falta» contra la meta, pero no es gente que pueda venir: a nadie le tocaba.
    expect(cob.faltanEnc).toBe(true);
    expect(cob.problema).toBe(true);
    expect(cob.gravedad).toBe("revisar");
    // Sin el prefijo «revisa la meta en Turnos —» de las metas imposibles: el botón ya dice «Revisar meta».
    expect(textoMetaPorRevisar(cob)).toBe("hay meta de 1 líder para hoy, pero a nadie del equipo le tocaba trabajar");
  });

  it("es un hecho del día, no de la hora: la meta de la tarde no lo cambia a las 2:15 p. m.", () => {
    // Una sede que solo tiene meta de tarde (abre a las 14:00): por la mañana sinMetaOp
    // es true, y antes decía «Sin meta configurada» hasta el corte, y «Cobertura
    // insuficiente» después. Los dos tramos cuentan para saber si hoy hay meta.
    const equipo = [descansa("a"), descansa("b")];
    const meta = { man: 0, tar: 3, enc: 0 };
    const manana = calcularCoberturaSede(equipo, meta, false, 10);
    const tarde = calcularCoberturaSede(equipo, meta, true, 15);
    for (const cob of [manana, tarde]) {
      expect(cob.hayMetaHoy).toBe(true);
      // Con meta —aunque hoy sea solo de la tarde— NUNCA es «no abre»: sería un ámbar (o un rojo)
      // enterrado en gris, al final de la lista, con «esta sede no tiene meta para este día».
      expect(cob.noAbreHoy).toBe(false);
      expect(cob.metaSinTurnos).toBe(true);
      expect(cob.gravedad).toBe("revisar");
      expect(cob.problema).toBe(true);
    }
    expect(textoMetaSinTurnos(manana)).toBe("hay meta de 3 operativas para hoy, pero a nadie del equipo le tocaba trabajar");
  });

  it("un día normal NO es «no abre»: basta con que a una persona le toque", () => {
    const cob = calcularCoberturaSede([descansa("a"), fila({ personaId: "b" })], { man: 1, tar: 1, enc: 0 }, false, 10);
    expect(cob.sinTurnosHoy).toBe(false);
    expect(cob.metaSinTurnos).toBe(false);
  });

  it("todo el equipo de vacaciones PERO con turno hoy: la sede debía abrir → sigue siendo rojo", () => {
    // El otro lado de la moneda. Si «de vacaciones» contara como «no le toca», una
    // tienda sin nadie por vacaciones simultáneas saldría gris, y es un hueco real.
    const vac = { nombre: "Vacaciones", pendiente: false };
    const equipo = [fila({ personaId: "a", ausenciaHoy: vac }), fila({ personaId: "b", ausenciaHoy: vac })];
    const cob = calcularCoberturaSede(equipo, { man: 2, tar: 2, enc: 0 }, false, 10);
    expect(cob.programadosHoy).toBe(0);
    expect(cob.sinTurnosHoy).toBe(false);
    expect(cob.noAbreHoy).toBe(false);
    expect(cob.metaSinTurnos).toBe(false);
    expect(cob.gravedad).toBe("alerta");
  });

  it("si alguien marcó hoy, la sede abrió aunque nadie tuviera turno", () => {
    const equipo = [descansa("a", { estado: "cerrada", entrada: "x", salidaFinal: "y" }), descansa("b")];
    const cob = calcularCoberturaSede(equipo, { man: 1, tar: 1, enc: 0 }, false, 18);
    expect(cob.sinTurnosHoy).toBe(false);
    expect(cob.metaSinTurnos).toBe(false);
  });

  it("si la consulta de turnos u horarios falló, NO se afirma que está cerrada", () => {
    // Todas las filas llegan sin horario: «nadie tiene turno» aquí es «no se pudo mirar».
    const equipo = [descansa("a", { origenEsperadoHoy: "sin_horario" }), descansa("b", { origenEsperadoHoy: "sin_horario" })];
    const cob = calcularCoberturaSede(equipo, { man: 2, tar: 2, enc: 1 }, false, 10, false);
    expect(cob.sinTurnosHoy).toBe(false);
    expect(cob.metaSinTurnos).toBe(false);
    expect(cob.gravedad).toBe("alerta"); // como antes: ante la duda, el rojo de siempre
  });

  it("una sede sin nadie visible en su equipo NO se declara sin turnos: no hay respuesta que dar", () => {
    // Verdad vacía: «nadie tiene turno» sobre cero personas no dice que la sede no abra
    // (todo sueldo fijo o RxH, o RLS que le oculta las filas a quien mira).
    const cob = calcularCoberturaSede([], { man: 0, tar: 0, enc: 1 }, false, 10);
    expect(cob.sinTurnosHoy).toBe(false);
    expect(cob.metaSinTurnos).toBe(false);
    expect(cob.noAbreHoy).toBe(false);
  });

  it("TODOS sin horario cargado y con meta: no se sabe si le toca abrir → sigue en rojo, no baja a ámbar", () => {
    // El caso que la auditoría demostró: se venció un tramo de horario sin sucesor y toda la sede
    // pasa a `sin_horario`. Antes decía «revisa la meta en Turnos» —se arregla en Horarios— y
    // bajaba de rojo a ámbar sin base. Bajar la severidad exige una respuesta REAL de descanso.
    const sinHorario = (id: string) => descansa(id, { origenEsperadoHoy: "sin_horario" });
    const cob = calcularCoberturaSede([sinHorario("a"), sinHorario("b")], { man: 2, tar: 2, enc: 0 }, false, 10);
    expect(cob.sinTurnosHoy).toBe(true);
    expect(cob.noAbreHoy).toBe(false); // hay meta: no se apaga en gris, ni al final de la lista
    expect(cob.metaSinTurnos).toBe(false);
    expect(cob.gravedad).toBe("alerta");
  });

  it("TODOS sin horario cargado y con meta 0: no hay nada que alarmar, y «Sin turnos» es cierto", () => {
    // Con la meta en 0 no hay severidad que bajar: la palabra gris solo dice lo que se sabe.
    const sinHorario = (id: string) => descansa(id, { origenEsperadoHoy: "sin_horario" });
    const cob = calcularCoberturaSede([sinHorario("a"), sinHorario("b")], META_0, false, 10);
    expect(cob.sinTurnosHoy).toBe(true);
    expect(cob.noAbreHoy).toBe(true);
    expect(cob.gravedad).toBeNull();
  });

  it("con una respuesta real de descanso, aunque otra persona no tenga horario, la meta sí baja a ámbar", () => {
    const equipo = [descansa("a"), descansa("b", { origenEsperadoHoy: "sin_horario" })];
    expect(calcularCoberturaSede(equipo, META_0, false, 10).noAbreHoy).toBe(true);
    expect(calcularCoberturaSede(equipo, { man: 1, tar: 1, enc: 0 }, false, 10).metaSinTurnos).toBe(true);
  });

  it("con turnos, el resto sigue igual: las metas imposibles siguen ámbar y las faltas reales rojas", () => {
    const equipo = [fila({ personaId: "a" })];
    expect(calcularCoberturaSede(equipo, { man: 1, tar: 1, enc: 0 }, false, 10).gravedad).toBe("alerta");
    expect(calcularCoberturaSede(equipo, { man: 3, tar: 3, enc: 0 }, false, 10).gravedad).toBe("revisar");
  });
});

describe("textoMetaSinTurnos — dice los dos lados de la contradicción", () => {
  const cob = (meta: { man: number; tar: number; enc: number }) =>
    calcularCoberturaSede([fila({ entradaEsperadaHoy: null, origenEsperadoHoy: "horario" })], meta, false, 10);

  it("operativas y líderes juntos, con concordancia", () => {
    expect(textoMetaSinTurnos(cob({ man: 2, tar: 4, enc: 1 }))).toBe(
      "hay meta de 4 operativas y 1 líder para hoy, pero a nadie del equipo le tocaba trabajar",
    );
    expect(textoMetaSinTurnos(cob({ man: 1, tar: 1, enc: 2 }))).toBe(
      "hay meta de 1 operativa y 2 líderes para hoy, pero a nadie del equipo le tocaba trabajar",
    );
  });
});

describe("metaDelDiaTexto", () => {
  it("dice solo lo que tiene meta, con concordancia", () => {
    const sola = (meta: { man: number; tar: number; enc: number }) => calcularCoberturaSede([], meta, false, 10);
    expect(metaDelDiaTexto(sola({ man: 0, tar: 0, enc: 1 }))).toBe("1 líder");
    expect(metaDelDiaTexto(sola({ man: 1, tar: 3, enc: 0 }))).toBe("3 operativas");
    expect(metaDelDiaTexto(sola({ man: 2, tar: 2, enc: 2 }))).toBe("2 operativas y 2 líderes");
    expect(metaDelDiaTexto(sola(META_0))).toBe("");
  });
});

describe("diaDeLaSemanaEnPlural — la meta es por día de la semana, no por fecha", () => {
  it("dice el día en plural, sin cambiar los que ya terminan en «s»", () => {
    expect(diaDeLaSemanaEnPlural("2026-09-20")).toBe("domingos");
    expect(diaDeLaSemanaEnPlural("2026-09-19")).toBe("sábados");
    expect(diaDeLaSemanaEnPlural("2026-09-21")).toBe("lunes");
    expect(diaDeLaSemanaEnPlural("2026-09-23")).toBe("miércoles");
  });
});

describe("las banderas de «sin turnos» nunca se contradicen", () => {
  // Cuatro estados representados con varias banderas: el tipo deja combinarlas mal, así que se
  // barre un puñado de situaciones y se comprueban las relaciones que las pantallas dan por hechas.
  const equipos: Record<string, FilaPersona[]> = {
    descansan: [fila({ personaId: "a", entradaEsperadaHoy: null, origenEsperadoHoy: "horario" })],
    sinHorario: [fila({ personaId: "a", entradaEsperadaHoy: null, origenEsperadoHoy: "sin_horario" })],
    trabajan: [fila({ personaId: "a" })],
    vacio: [],
  };
  const metas = [META_0, { man: 2, tar: 2, enc: 0 }, { man: 0, tar: 3, enc: 0 }, { man: 0, tar: 0, enc: 1 }];

  it("noAbreHoy y metaSinTurnos nunca a la vez; noAbreHoy implica sin meta y sin gravedad; metaSinTurnos implica «revisar»", () => {
    for (const [nombre, equipo] of Object.entries(equipos)) {
      for (const meta of metas) {
        for (const tarde of [false, true]) {
          const cob = calcularCoberturaSede(equipo, meta, tarde, tarde ? 15 : 10);
          const caso = `${nombre} · meta ${JSON.stringify(meta)} · ${tarde ? "tarde" : "mañana"}`;
          expect(cob.noAbreHoy && cob.metaSinTurnos, caso).toBe(false);
          if (cob.noAbreHoy) {
            expect(cob.hayMetaHoy, caso).toBe(false);
            expect(cob.gravedad, caso).toBeNull();
            expect(cob.problema, caso).toBe(false);
          }
          if (cob.metaSinTurnos) {
            expect(cob.hayMetaHoy, caso).toBe(true);
            expect(cob.gravedad, caso).toBe("revisar");
            expect(cob.problema, caso).toBe(true);
          }
          if (cob.sinTurnosHoy) expect(cob.programadosHoy, caso).toBe(0);
        }
      }
    }
  });
});

// ----------------------------------------------------------------------------
// FERIADOS (2026-09-20). Un feriado con nadie marcado y sin turnos armados no es
// una falla que acusar: en 22 de 25 feriados trabajados las sedes abrieron con su
// horario base y sin turnos, y otros feriados se cierran. `fn_faltas` tampoco
// cuenta falta ese día (0051, 0070, 0414). Rojo sería falso cuando cierra; callar,
// falso cuando abre. Se PREGUNTA, en ámbar. Y donde sí hay turno, el rojo se queda.
// ----------------------------------------------------------------------------
describe("feriado — la persona: «le tocaba» no se convierte en «faltó»", () => {
  const feriado = (o: Partial<FilaPersona> = {}) => fila({ origenEsperadoHoy: "horario", feriadoSinTurnoHoy: true, ...o });

  it("pasada la hora, sin turno: «feriado», no «falta_real»", () => {
    expect(subEstadoSinMarcar(feriado(), 9)).toBe("feriado");
  });

  it("antes de la hora sigue siendo «aun_no_inicia»: el feriado no cambia lo que es temprano", () => {
    expect(subEstadoSinMarcar(feriado(), 7.5)).toBe("aun_no_inicia");
  });

  it("SIN la bandera es la falta real de siempre (también si no se pudo saber que era feriado)", () => {
    expect(subEstadoSinMarcar(fila({ origenEsperadoHoy: "horario" }), 9)).toBe("falta_real");
    expect(subEstadoSinMarcar(fila({ origenEsperadoHoy: "horario", feriadoSinTurnoHoy: false }), 9)).toBe("falta_real");
  });

  it("con un turno explícito el feriado no suaviza nada", () => {
    expect(subEstadoSinMarcar(fila({ origenEsperadoHoy: "turno", feriadoSinTurnoHoy: false }), 9)).toBe("falta_real");
  });

  it("no cuenta como «sin marcar y ya le tocaba»: el número del resumen coincide con lo que acusa la base", () => {
    expect(sinMarcarYaLeTocaba(feriado(), 9)).toBe(false);
    expect(sinMarcarYaLeTocaba(fila({ origenEsperadoHoy: "horario" }), 9)).toBe(true);
  });

  it("no cambia lo que le tocaba: la hora de entrada sigue ahí para poder decir «le tocaba 08:00»", () => {
    expect(feriado().entradaEsperadaHoy).toBe("08:00");
  });
});

describe("feriado — la sede: nadie marcó y nadie armó turnos", () => {
  const META_2 = { man: 2, tar: 2, enc: 1 };
  const soloHorario = (personaId: string, o: Partial<FilaPersona> = {}) =>
    fila({ personaId, origenEsperadoHoy: "horario", feriadoSinTurnoHoy: true, esEncargada: personaId === "a", ...o });
  const equipo = () => [soloHorario("a"), soloHorario("b"), soloHorario("c")];

  it("pasada la hora: NO hay rojo, hay la pregunta en ámbar", () => {
    const c = calcularCoberturaSede(equipo(), META_2, false, 9);
    expect(c.alertaSinEntrada).toBeNull();
    expect(c.feriadoSinConfirmar).toBe(true);
    expect(c.gravedad).toBe("revisar"); // ámbar, no «alerta»
    expect(textoMetaPorRevisar(c)).toBe(TEXTO_FERIADO_SIN_CONFIRMAR);
  });

  it("la pregunta es una pregunta: no afirma ni que abre ni que cierra", () => {
    expect(TEXTO_FERIADO_SIN_CONFIRMAR).toContain("¿abre hoy la sede?");
    expect(TEXTO_FERIADO_SIN_CONFIRMAR).not.toMatch(/falt|cerrad|insuficiente/i);
  });

  it("no lleva «:» propio: la lista la escribe detrás de «Tienda · Trujillo (TRU):» y quedaban dos seguidos", () => {
    expect(TEXTO_FERIADO_SIN_CONFIRMAR).toBe("es feriado y nadie ha marcado todavía — ¿abre hoy la sede?");
    expect(TEXTO_FERIADO_SIN_CONFIRMAR).not.toContain(":");
    expect(`Tienda · Trujillo (TRU): ${TEXTO_FERIADO_SIN_CONFIRMAR}`.match(/:/g)).toHaveLength(1);
  });

  it("no la confunde con «Sin turnos»: a nadie le tocaba NO es lo que se sabe", () => {
    const c = calcularCoberturaSede(equipo(), META_2, false, 9);
    expect(c.sinTurnosHoy).toBe(false);
    expect(c.noAbreHoy).toBe(false);
    expect(c.metaSinTurnos).toBe(false);
  });

  it("nadie se cuenta como «no llegó y ya le tocaba»: pasan a «aún no llegan»", () => {
    const c = calcularCoberturaSede(equipo(), META_2, false, 9);
    expect(c.sinMarcarReal).toBe(0);
    expect(c.desgloseProgramadas.noLlegaron).toBe(0);
    expect(c.desgloseProgramadas.aunNoLlegan).toBe(3);
    expect(textoDesglose(c.desgloseProgramadas)).not.toContain("no llegó");
  });

  it("dentro del margen de la hora todavía no pregunta: aún es temprano, como cualquier día", () => {
    const c = calcularCoberturaSede(equipo(), META_2, false, 8.2);
    expect(c.feriadoSinConfirmar).toBe(false);
    expect(c.alertaSinEntrada).toBeNull();
  });

  it("apenas alguien marca, la sede abrió: la pregunta se apaga y la meta vuelve a medirse como cualquier día", () => {
    const abierta = [soloHorario("a", { estado: "abierta", entrada: "x" }), soloHorario("b"), soloHorario("c")];
    const c = calcularCoberturaSede(abierta, META_2, false, 9);
    expect(c.feriadoSinConfirmar).toBe(false);
    expect(c.faltanOp).toBe(true);
    expect(c.gravedad).toBe("alerta");
    // …y aun así nadie del piso se acusa de «no llegó»: eso lo decide fn_faltas, y no lo cuenta.
    expect(c.sinMarcarReal).toBe(0);
  });

  it("sin la bandera en las filas —la consulta de feriados o de turnos falló— la alarma es la roja de siempre", () => {
    const sinSaber = [fila({ personaId: "a", origenEsperadoHoy: "horario" }), fila({ personaId: "b", origenEsperadoHoy: "horario" })];
    const c = calcularCoberturaSede(sinSaber, META_2, false, 9);
    expect(c.alertaSinEntrada).toBe("08:00");
    expect(c.feriadoSinConfirmar).toBe(false);
    expect(c.gravedad).toBe("alerta");
  });

  it("una sede que SÍ armó turnos en el feriado conserva el rojo: registrar el turno es decir «hoy abro»", () => {
    const conTurnos = [
      fila({ personaId: "a", origenEsperadoHoy: "turno", feriadoSinTurnoHoy: false }),
      fila({ personaId: "b", origenEsperadoHoy: "turno", feriadoSinTurnoHoy: false }),
    ];
    const c = calcularCoberturaSede(conTurnos, META_2, false, 9);
    expect(c.alertaSinEntrada).toBe("08:00");
    expect(c.feriadoSinConfirmar).toBe(false);
    expect(c.sinMarcarReal).toBe(2);
  });

  it("mezcla: con el turno de UNA persona la sede abre, y el rojo lo dice esa persona, no la de solo-horario", () => {
    const mezcla = [
      fila({ personaId: "a", origenEsperadoHoy: "turno", feriadoSinTurnoHoy: false, entradaEsperadaHoy: "10:00" }),
      soloHorario("b", { entradaEsperadaHoy: "08:00" }),
    ];
    const c = calcularCoberturaSede(mezcla, META_0, false, 11);
    expect(c.feriadoSinConfirmar).toBe(false);
    expect(c.alertaSinEntrada).toBe("10:00"); // no «08:00»: esa hora es de quien no tiene turno
    expect(c.sinMarcarReal).toBe(1); // solo la que tiene turno
  });

  it("si todo el equipo está de vacaciones nadie tenía que llegar: tampoco se pregunta si abre", () => {
    const vac = { nombre: "Vacaciones", pendiente: false };
    const c = calcularCoberturaSede([soloHorario("a", { ausenciaHoy: vac }), soloHorario("b", { ausenciaHoy: vac })], META_2, false, 10);
    expect(c.feriadoSinConfirmar).toBe(false);
    expect(c.alertaSinEntrada).toBeNull();
  });

  it("un feriado en que a nadie le tocaría por horario no inventa una pregunta", () => {
    const descansan = [fila({ entradaEsperadaHoy: null, origenEsperadoHoy: "horario", feriadoSinTurnoHoy: true })];
    expect(calcularCoberturaSede(descansan, META_0, false, 10).feriadoSinConfirmar).toBe(false);
  });
});

describe("textoEquipoDelDia en un feriado sin confirmar — «por horario», no «hoy les tocaba»", () => {
  it("a todos les tocaría por su horario", () => {
    expect(textoEquipoDelDia(3, 3, true)).toBe("Por horario les tocaba a las 3 personas del equipo; es feriado y no hay turnos armados.");
  });

  it("a una parte del equipo, con el singular y el plural en su sitio", () => {
    expect(textoEquipoDelDia(4, 5, true)).toBe("Por horario les tocaba a 4 de las 5 personas del equipo; es feriado y no hay turnos armados.");
    expect(textoEquipoDelDia(1, 5, true)).toBe("Por horario le tocaba a 1 de las 5 personas del equipo; es feriado y no hay turnos armados.");
  });

  it("a la única persona del equipo", () => {
    expect(textoEquipoDelDia(1, 1, true)).toBe("Por horario le tocaba a la única persona del equipo; es feriado y no hay turnos armados.");
  });

  it("no dice «Hoy … tocaba trabajar»: junto a «¿abre hoy?» se leía como una contradicción", () => {
    for (const [p, e] of [[3, 3], [4, 5], [1, 5], [1, 1]] as const) {
      expect(textoEquipoDelDia(p, e, true)).not.toMatch(/^Hoy|tocaba trabajar/);
    }
  });

  it("si a nadie le tocaba no hay a quién decirle «por horario»: la frase es la de siempre", () => {
    expect(textoEquipoDelDia(0, 3, true)).toBe(textoEquipoDelDia(0, 3));
    expect(textoEquipoDelDia(0, 1, true)).toBe(textoEquipoDelDia(0, 1));
    expect(textoEquipoDelDia(0, 0, true)).toBe(textoEquipoDelDia(0, 0));
  });

  it("SIN la bandera todas las frases son exactamente las de siempre", () => {
    for (const [p, e] of [[3, 3], [4, 5], [1, 5], [1, 1], [0, 3], [0, 1], [0, 0]] as const) {
      expect(textoEquipoDelDia(p, e, false)).toBe(textoEquipoDelDia(p, e));
    }
    expect(textoEquipoDelDia(3, 3)).toBe("Hoy les tocaba trabajar a las 3 personas del equipo.");
  });
});

describe("llegoTarde: una tardanza levantada ya no es tardanza", () => {
  it("llegó 30 min tarde y nadie la levantó: cuenta", () => {
    expect(llegoTarde(fila({ minutosTarde: 30 }))).toBe(true);
  });

  it("llegó 30 min tarde pero DO la levantó (fuerza mayor): NO cuenta, aunque los minutos sigan guardados", () => {
    expect(llegoTarde(fila({ minutosTarde: 30, tardanzaLevantada: true }))).toBe(false);
  });

  it("sin minutos de tardanza no cuenta, levantada o no", () => {
    expect(llegoTarde(fila({ minutosTarde: 0 }))).toBe(false);
    expect(llegoTarde(fila({ minutosTarde: null, tardanzaLevantada: true }))).toBe(false);
  });

  it("una fila que nunca trae el dato (ausente) se comporta como siempre", () => {
    expect(llegoTarde(fila({ minutosTarde: 5 }))).toBe(true);
  });
});

describe("llegaronTarde: la lista que abre el «1 tarde» de la sede", () => {
  it("trae solo a quien llegó tarde, y la más tarde primero", () => {
    const lista = llegaronTarde([
      fila({ personaId: "a", nombre: "Ana", minutosTarde: 5 }),
      fila({ personaId: "b", nombre: "Beto", minutosTarde: 0 }),
      fila({ personaId: "c", nombre: "Carla", minutosTarde: 40 }),
      fila({ personaId: "d", nombre: "Dora", minutosTarde: null }),
    ]);
    expect(lista.map((f) => f.personaId)).toEqual(["c", "a"]);
  });

  it("quien tiene la tardanza levantada no aparece: la lista y el «N tarde» de la fila no pueden discrepar", () => {
    const filas = [
      fila({ personaId: "a", nombre: "Ana", minutosTarde: 30, tardanzaLevantada: true }),
      fila({ personaId: "b", nombre: "Beto", minutosTarde: 3 }),
    ];
    expect(llegaronTarde(filas).map((f) => f.personaId)).toEqual(["b"]);
    expect(llegaronTarde(filas)).toHaveLength(filas.filter(llegoTarde).length);
  });

  it("a igual de minutos desempata por nombre, para que el refresco de 30 s no baraje la lista", () => {
    const lista = llegaronTarde([
      fila({ personaId: "z", nombre: "Zoila", minutosTarde: 10 }),
      fila({ personaId: "a", nombre: "Ángela", minutosTarde: 10 }),
      fila({ personaId: "m", nombre: "Marta", minutosTarde: 10 }),
    ]);
    expect(lista.map((f) => f.nombre)).toEqual(["Ángela", "Marta", "Zoila"]);
  });

  it("no toca el arreglo que recibe y sin tardanzas devuelve vacío", () => {
    const entrada = [fila({ personaId: "a", minutosTarde: 5 }), fila({ personaId: "b", minutosTarde: 20 })];
    const copia = [...entrada];
    llegaronTarde(entrada);
    expect(entrada).toEqual(copia);
    expect(llegaronTarde([fila({ minutosTarde: 0 })])).toEqual([]);
  });
});
