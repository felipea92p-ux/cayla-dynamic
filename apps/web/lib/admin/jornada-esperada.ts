// Qué le tocaba a una persona un día concreto: si trabajaba, entre qué horas y
// cuántas horas eran una vez descontado el refrigerio.
//
// POR QUÉ EXISTE: sin esto, «50 h» y «8 días» no significan nada. Un total solo
// se vuelve información cuando al lado dice **de cuánto**. Sandra con 8 días
// puede haber faltado dos o haber trabajado los 8 que le tocaban, y la tabla no
// tenía cómo distinguirlo.
//
// ESPEJA LA CASCADA DEL BACKEND (fn_recalcular_jornada, y la misma que usan
// fn_faltas y fn_auto_cierre):
//     turno puntual del día  →  horario_por_dia (jsonb)  →  dias_laborables
// El turno del día MANDA: es la excepción que alguien registró a mano para esa
// fecha. Solo si no hay turno se cae al horario base, y solo si el horario base
// no tiene `horario_por_dia` se usa el resumen legacy `dias_laborables`.
//
// SE ROMPE SI: alguien cambia esa prioridad en la base y no acá. Es el riesgo de
// tener la regla escrita más de una vez, y ya se estuvo así: `admin/correcciones/page.tsx`
// tenía su propia copia (`calcularEsperado`), solo para la hora de entrada, y con
// un bug real —su rama legacy no comprobaba `dias_laborables`, porque su consulta
// nunca pedía esa columna—. `admin/incidencias/page.tsx` tenía otra (`trabajaEseDia`,
// solo booleano, para cobertura de encargadas), con un bug menor: comprobaba que
// el día EXISTIERA en `horario_por_dia`, no que tuviera hora de entrada (`.e`),
// así que un día de descanso guardado como `{}` en vez de ausente habría contado
// como trabajado. Las dos se unificaron el 2026-08-25.
//
// La cuarta copia (`admin/turnos/page.tsx`: `horasDeTramo` y la cascada dentro
// de `celda`, para dibujar la grilla de turnos) se unificó el 2026-09-03. No
// tenía un bug propio, pero sí una divergencia silenciosa: al cargar el tramo
// de horario rellenaba `dias_laborables` con `[1,2,3,4,5]` cuando venía vacío,
// un default que esta cascada nunca aplica. La columna es NOT NULL en
// `horarios_asignados`, así que nunca disparaba — pero el día que alguien
// insertara un tramo a mano sin esa columna, Turnos habría mostrado lunes a
// viernes mientras el resto del sistema mostraba descanso todos los días.
//
// LO QUE ESTA CASCADA NO SABE, A PROPÓSITO: los FERIADOS. Parece un hueco —`fn_faltas`
// sí los conoce— y una revisión de código lo señaló el 2026-09-20, pero no lo es:
// la base tampoco los aplica al medir lo que le tocaba. `fn_recalcular_jornada`
// (0446) no nombra ni una vez la palabra: mide tardanza y horas contra el horario
// base también en feriado, por decisión de Felipe del 2026-08-18 con datos —22 de 25
// feriados trabajados no tenían ni un turno, o sea que las sedes abren con su horario
// normal (docs/hallazgos-abiertos.md, A4)—. Lo único que la base condiciona a «hay
// turno explícito» es ACUSAR: `fn_faltas` no cuenta falta un feriado sin turno.
// Son dos preguntas —«¿qué le tocaba?» y «¿se le puede exigir?»— y esta función
// contesta la primera; la segunda es `esFeriadoSinTurno`, más abajo.
//
// Hacer que esta función devolviera `trabaja:false` en feriado la volvería
// contradictoria con la base, y se midió qué rompe: quien vino un feriado pasaría
// de «ok» a «extra» en Horas y Mío, y Correcciones diría «ya no hay horario: alguien
// lo cambió» en cada jornada trabajada en feriado. Si algún día el laboralista
// obliga a cambiar la práctica (hallazgos-abiertos, Consulta 5), cambia la base y
// esta función a la vez — no una sola.
//
// ANTES DE ESCRIBIR UNA QUINTA COPIA que responda «¿le tocaba trabajar ese
// día?», usar ésta.

export interface TurnoDia {
  hora_entrada: string | null;
  hora_salida: string | null;
  es_descanso: boolean;
}

export interface HorarioTramo {
  persona_id: string;
  vigente_desde: string;
  vigente_hasta: string | null;
  hora_entrada: string | null;
  hora_salida: string | null;
  dias_laborables: number[] | null;
  horario_por_dia: Record<string, { e?: string; s?: string; r?: number }> | null;
  almuerzo_min_minutos: number | null;
}

export interface Esperado {
  /** ¿Le tocaba trabajar ese día? */
  trabaja: boolean;
  /** "08:00" — contra esto se mide la tardanza. */
  entrada: string | null;
  salida: string | null;
  /** Horas de la jornada ya sin refrigerio. 0 si no le tocaba o no se sabe. */
  horas: number;
  /** De dónde salió la respuesta, para poder decirlo en pantalla. */
  origen: "turno" | "horario" | "legacy" | "sin_horario";
}

const NADA: Esperado = { trabaja: false, entrada: null, salida: null, horas: 0, origen: "sin_horario" };

/** Día de la semana de una fecha ISO, 0=domingo … 6=sábado, en hora de Lima. */
export function dowDe(iso: string): number {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d)).getUTCDay();
}

/** El tramo de horario vigente en esa fecha (el más reciente que la cubre). */
export function horarioVigente(tramos: HorarioTramo[], fecha: string): HorarioTramo | null {
  let mejor: HorarioTramo | null = null;
  for (const t of tramos) {
    if (t.vigente_desde > fecha) continue;
    if (t.vigente_hasta !== null && t.vigente_hasta < fecha) continue;
    if (!mejor || t.vigente_desde > mejor.vigente_desde) mejor = t;
  }
  return mejor;
}

function minutosDe(hhmm: string): number {
  const [h, m] = hhmm.slice(0, 5).split(":").map(Number);
  return h * 60 + (m || 0);
}

/**
 * Horas entre dos horas del reloj, menos el refrigerio.
 * Si la salida no es posterior a la entrada se asume que cruza medianoche: un
 * turno 21:00–05:00 son ocho horas, no menos dieciséis.
 */
export function horasEntre(entrada: string, salida: string, refrigerioMin: number): number {
  let mins = minutosDe(salida) - minutosDe(entrada);
  if (mins <= 0) mins += 24 * 60;
  return Math.max(0, (mins - Math.max(0, refrigerioMin)) / 60);
}

/**
 * Qué le tocaba ese día. `turno` es el turno puntual de esa fecha (o null), y
 * `horario` el tramo de horario base vigente (o null).
 */
export function esperadoDelDia(fecha: string, turno: TurnoDia | null, horario: HorarioTramo | null): Esperado {
  const dow = String(dowDe(fecha));
  const delDia = horario?.horario_por_dia?.[dow] ?? null;
  // El refrigerio del día sale del horario base aunque el turno lo pise: un
  // turno guarda entrada y salida, nunca cuánto se almuerza.
  const refrigerio = delDia?.r ?? horario?.almuerzo_min_minutos ?? 0;

  // 1 · El turno del día manda.
  if (turno) {
    if (turno.es_descanso) return { trabaja: false, entrada: null, salida: null, horas: 0, origen: "turno" };
    if (turno.hora_entrada) {
      const e = turno.hora_entrada.slice(0, 5);
      const s = turno.hora_salida?.slice(0, 5) ?? delDia?.s?.slice(0, 5) ?? horario?.hora_salida?.slice(0, 5) ?? null;
      return { trabaja: true, entrada: e, salida: s, horas: s ? horasEntre(e, s, refrigerio) : 0, origen: "turno" };
    }
  }

  if (!horario) return NADA;

  // 2 · El horario base por día. Un día AUSENTE del jsonb es descanso — y eso
  //     es una respuesta, no un «no sé»: por eso no se cae al legacy.
  if (horario.horario_por_dia) {
    if (!delDia?.e) return { trabaja: false, entrada: null, salida: null, horas: 0, origen: "horario" };
    const e = delDia.e.slice(0, 5);
    const s = delDia.s?.slice(0, 5) ?? null;
    return { trabaja: true, entrada: e, salida: s, horas: s ? horasEntre(e, s, refrigerio) : 0, origen: "horario" };
  }

  // 3 · El resumen legacy, para los horarios que nunca se migraron al jsonb.
  if (horario.dias_laborables && horario.hora_entrada) {
    const toca = horario.dias_laborables.includes(Number(dow));
    if (!toca) return { trabaja: false, entrada: null, salida: null, horas: 0, origen: "legacy" };
    const e = horario.hora_entrada.slice(0, 5);
    const s = horario.hora_salida?.slice(0, 5) ?? null;
    return { trabaja: true, entrada: e, salida: s, horas: s ? horasEntre(e, s, refrigerio) : 0, origen: "legacy" };
  }

  return NADA;
}

// ============================================================================
// El día de una SEDE — la pregunta de esperadoDelDia, un piso más arriba
// ============================================================================
// «¿A alguien de esta sede le toca trabajar ese día?» la contestaban tres
// pantallas por su cuenta, y la falsa alarma volvía en cada una (2026-09-20):
// Central tiene meta de 1 líder el domingo pero el domingo nadie tiene turno, y
// el Dashboard decía «Cobertura insuficiente», Incidencias «Déficit de líderes
// 0/1» y la Hoja de sede impresa «faltan 1» en rojo — por una falta que ninguna
// asistencia podía arreglar, porque a nadie le tocaba ir. Se dice acá, una vez.
//
// Cuatro respuestas, porque «nadie tiene turno» significa cosas distintas:
//   · «trabaja»     — a alguien le toca.
//   · «no_trabaja»  — a nadie le toca, y hay al menos UNA respuesta real de que
//                     descansa (un turno de descanso, o un horario que no incluye
//                     ese día). Es lo único que autoriza a callar una alarma.
//   · «sin_horario» — a nadie le toca, pero es porque NO HAY con qué medirlo
//                     (un tramo venció sin sucesor, una sede nueva, un equipo
//                     vacío). No dice «hoy no abre»: dice «no se sabe», y ahí
//                     cada alarma sigue como estaba.
//   · «feriado_sin_confirmar» — por su horario base a alguien le tocaría, pero es
//                     FERIADO y NADIE de la sede tiene turno explícito. No es
//                     «trabaja»: la base no exige ese día sin un turno (`fn_faltas`,
//                     ver `esFeriadoSinTurno`), y las sedes abren en feriado unas
//                     veces sí y otras no. Tampoco es «no_trabaja»: ninguna respuesta
//                     dice que descansan. Es «no se sabe si abre», y por eso las
//                     pantallas PREGUNTAN («¿abre hoy?») en vez de acusar o de callar.
// ============================================================================

/** La palabra de pantalla para «ese día esta sede no tiene turnos». Una sola, en todas las pantallas. */
export const SEDE_SIN_TURNOS = "Sin turnos";

export type DiaDeLaSede = "trabaja" | "no_trabaja" | "sin_horario" | "feriado_sin_confirmar";

/**
 * ¿Es feriado y a esta persona nadie le armó un turno para ese día? — el gemelo en
 * pantalla de la cláusula de `fn_faltas` «feriado sin turno explícito no cuenta»
 * (0051, 0070, vigente en la 0414: `not (fer.es is not null and not tb.hay_turno)`).
 *
 * Contesta «¿se le puede EXIGIR?», no «¿qué le tocaba?»: esa es `esperadoDelDia`, que
 * a propósito no sabe de feriados (ver el encabezado). Se usa SOLO donde se alarma
 * —«sin marcar», «sede sin marcajes», «faltan N»—, nunca para medir tardanzas ni horas.
 *
 * «Hay turno» es `origen === "turno"`: un turno puntual —de trabajo o de descanso—
 * fue lo que decidió el día, que es exactamente lo que la base entiende por «turno
 * explícito».
 */
export function esFeriadoSinTurno(esFeriado: boolean, esperado: Pick<Esperado, "origen">): boolean {
  return esFeriado && esperado.origen !== "turno";
}

/**
 * La respuesta de esperadoDelDia de cada persona del equipo → la de la sede.
 * `feriadoSinTurno` (ver `esFeriadoSinTurno`) es opcional y su ausencia es «no»: quien
 * no lo pasa, o falló al saber si hoy es feriado, obtiene la respuesta de siempre —
 * y una duda cae hacia la alarma, nunca hacia el silencio.
 */
export function diaDeLaSede(
  esperados: readonly (Pick<Esperado, "trabaja" | "origen"> & { feriadoSinTurno?: boolean })[],
): DiaDeLaSede {
  let respuestaRealDeDescanso = false;
  let soloPorHorarioEnFeriado = false;
  for (const e of esperados) {
    if (e.trabaja) {
      // Le tocaría por su horario base, pero es feriado y nadie le armó turno: eso no
      // prueba que la sede abra. Un turno explícito de OTRA persona sí lo prueba, y
      // gana porque se sigue recorriendo.
      if (e.feriadoSinTurno) { soloPorHorarioEnFeriado = true; continue; }
      return "trabaja";
    }
    if (e.origen !== "sin_horario") respuestaRealDeDescanso = true;
  }
  if (soloPorHorarioEnFeriado) return "feriado_sin_confirmar";
  return respuestaRealDeDescanso ? "no_trabaja" : "sin_horario";
}

/**
 * Lo mismo a partir de las personas y sus turnos/horarios, para las pantallas que
 * no traen un `Esperado` por persona. Un equipo vacío es «sin_horario»: sin gente
 * no hay a quién preguntarle. `esFeriado` es «¿`fecha` está en la tabla `feriados`?»;
 * por defecto `false`, así que quien no lo pasa (Turnos) no cambia de respuesta.
 */
export function diaDeLaSedeDe(
  personaIds: readonly string[],
  fecha: string,
  turnoDe: (personaId: string) => TurnoDia | null,
  tramosDe: (personaId: string) => HorarioTramo[],
  esFeriado = false,
): DiaDeLaSede {
  return diaDeLaSede(
    personaIds.map((id) => {
      const esperado = esperadoDelDia(fecha, turnoDe(id), horarioVigente(tramosDe(id), fecha));
      return { ...esperado, feriadoSinTurno: esFeriadoSinTurno(esFeriado, esperado) };
    }),
  );
}

/**
 * ¿Este turno puntual es un "espejo viejo"? — coincide con un tramo de
 * horario que la persona YA NO TIENE VIGENTE, y probablemente solo sigue ahí
 * porque nadie lo retiró cuando el horario cambió. El turno del día manda
 * sobre el horario base (arriba, `esperadoDelDia`), así que un espejo viejo
 * sigue mandando en silencio sobre una tardanza o un tiempo adicional real,
 * aunque el horario de esa persona haya cambiado hace tiempo.
 *
 * Es "probable", no seguro — coincidir con un tramo viejo por casualidad es
 * posible — así que esto no borra ni corrige nada, solo señala.
 *
 * "Viejo" quiere decir ANTERIOR al vigente, no "cualquiera que no sea el
 * vigente". El caso TRU (set-2026): los horarios de la sede rigen desde el
 * 2026-07-12 y el periodo abierto arranca el 2026-06-28. Los turnos de esas
 * dos semanas eran la única referencia de esos días, el horario de julio se
 * armó copiándolos, y la versión anterior de esta función los marcaba como
 * espejos viejos de un horario que TODAVÍA NO EMPEZABA — 76 de ellos, con un
 * botón al lado para quitarlos todos juntos. Por eso: sin horario vigente ese
 * día no hay nada de lo que el turno pueda haberse quedado atrás.
 *
 * Nació como lógica interna de RevisionTurnos en admin/turnos/page.tsx
 * (commit d409cc42, "caso Janis": turno 07:45 vs horario base 08:15), pero
 * esa pantalla solo mira turnos de hoy en adelante y solo la abre quien va a
 * Turnos. El caso de Diana (set-2026) mostró que hace falta verlo también
 * donde se nota el síntoma (la tardanza, en Correcciones) y donde se origina
 * el cambio (Horarios) — de ahí que viva acá y no solo en esa pantalla.
 */
export function esTurnoEspejoViejo(fecha: string, turno: TurnoDia, todosLosTramos: HorarioTramo[]): boolean {
  const vigente = horarioVigente(todosLosTramos, fecha);
  if (!vigente) return false;
  const tE = turno.es_descanso ? null : (turno.hora_entrada?.slice(0, 5) ?? null);
  const tS = turno.es_descanso ? null : (turno.hora_salida?.slice(0, 5) ?? null);
  return todosLosTramos.some((x) => {
    // Solo los que empezaron antes que el vigente: el vigente mismo no, y uno
    // posterior tampoco — de un horario que aún no rige no se queda atrás nadie.
    if (x.vigente_desde >= vigente.vigente_desde) return false;
    const h = esperadoDelDia(fecha, null, x);
    return tE === null ? h.entrada === null : h.entrada === tE && h.salida === tS;
  });
}

export interface HorasSemanales {
  /** Horas semanales pactadas, o null si no se pudo determinar desde el horario. */
  horas: number | null;
  origen: "horario" | "legacy" | "sin_horario";
}

/**
 * Las horas semanales del horario PACTADO de una persona — para un contrato,
 * no para un día concreto. A diferencia de `esperadoDelDia`, no mira ningún
 * turno puntual: un cambio de turno excepcional de una fecha no debe alterar
 * lo que un contrato declara como jornada semanal.
 *
 * `horas: null` (nunca `0`) cuando no se puede determinar — imprimir «0 horas
 * semanales» en una cláusula legal es peor que dejar el campo pendiente de
 * completar a mano, que es lo que pasa hoy sin esto.
 */
export function horasSemanalesVigentes(horario: HorarioTramo | null): HorasSemanales {
  if (!horario) return { horas: null, origen: "sin_horario" };

  if (horario.horario_por_dia) {
    let total = 0;
    let huboDia = false;
    for (let dow = 0; dow <= 6; dow++) {
      const dia = horario.horario_por_dia[String(dow)];
      if (!dia?.e || !dia?.s) continue;
      huboDia = true;
      const refrigerio = dia.r ?? horario.almuerzo_min_minutos ?? 0;
      total += horasEntre(dia.e.slice(0, 5), dia.s.slice(0, 5), refrigerio);
    }
    return huboDia ? { horas: total, origen: "horario" } : { horas: null, origen: "sin_horario" };
  }

  // El resumen legacy, para los horarios que nunca se migraron al jsonb.
  if (horario.dias_laborables && horario.dias_laborables.length > 0 && horario.hora_entrada && horario.hora_salida) {
    const horasDia = horasEntre(
      horario.hora_entrada.slice(0, 5),
      horario.hora_salida.slice(0, 5),
      horario.almuerzo_min_minutos ?? 0
    );
    return { horas: horario.dias_laborables.length * horasDia, origen: "legacy" };
  }

  return { horas: null, origen: "sin_horario" };
}

// ─────────────────────────────────────────────────────────────────────────────
// En qué quedó un día. Es lo que decide el color del cuadrito en el panel y lo
// que se cuenta en los totales, así que vive acá y no dentro de la pantalla:
// una regla que decide si alguien «faltó» tiene que poder probarse sola.
//
// EL ORDEN DE LOS CASOS ES LA REGLA. Un día puede ser varias cosas a la vez y
// solo se pinta una:
//   1. Un agregado histórico de 2025 no es un día — no se pinta como tal.
//   2. Una FALTA manda sobre todo: no vino.
//   3. Un marcaje roto manda sobre la tardanza: hasta arreglarlo, las horas de
//      ese día no se saben, así que no se puede afirmar nada más de él.
//   4. Recién entonces la tardanza, y solo si nadie la justificó.
// ─────────────────────────────────────────────────────────────────────────────

export type EstadoDia =
  | "falta"        // le tocaba, no marcó, y nadie registró un motivo
  | "revisar"      // marcó pero el día quedó sin cerrar o lo cerró el sistema
  | "tarde"        // llegó tarde y la tardanza no está justificada
  | "justificada"  // no marcó, pero hay motivo (vacaciones, permiso, suspensión…)
  | "ok"           // trabajó su día sin novedad
  | "extra"        // trabajó un día que su horario marca como descanso
  | "sin_marca"    // le tocaba, no marcó, y la base no lo cuenta como falta
  | "descanso"     // no le tocaba
  | "sin_horario"  // no hay contra qué medirlo
  | "futuro";      // todavía no llega

export interface JornadaDelDia {
  horas: number | null;
  minutosTarde: number | null;
  estado: string; // estado_jornada de la base
}

export function estadoDelDia(opciones: {
  fecha: string;
  hoy: string;
  esperado: Esperado;
  jornada: JornadaDelDia | null;
  /** Fila de fn_faltas para ese día, si la hay. */
  falta: { justificada: boolean } | null;
  /** ¿La tardanza de ese día fue levantada? */
  tardanzaJustificada: boolean;
  /** Más de 24 h en una fecha = un mes entero del histórico 2025. */
  agregado: boolean;
}): EstadoDia {
  const { fecha, hoy, esperado, jornada, falta, tardanzaJustificada, agregado } = opciones;
  if (agregado) return "sin_marca";
  if (falta && !falta.justificada) return "falta";
  if (jornada && (jornada.estado === "auto_cerrada_pendiente" || jornada.horas === null)) return "revisar";
  if (jornada && (jornada.minutosTarde ?? 0) > 0 && !tardanzaJustificada) return "tarde";
  if (jornada && (jornada.horas ?? 0) > 0) return esperado.trabaja ? "ok" : "extra";
  if (falta) return "justificada";
  if (!esperado.trabaja) return esperado.origen === "sin_horario" ? "sin_horario" : "descanso";
  if (fecha > hoy) return "futuro";
  return "sin_marca";
}

/**
 * ¿Es su jornada de HOY, todavía abierta? Está trabajando en este momento.
 *
 * `estadoDelDia` la devuelve como "revisar" —marcó y el día no está cerrado—,
 * y para un día PASADO eso es exactamente lo que hay que decir: se fue sin
 * marcar la salida. Para HOY no falta nada, y llamarlo «por revisar» acusa de
 * un problema a quien está cumpliendo su turno. El corte por fecha es lo que
 * hace segura la excepción: una jornada abierta de AYER sigue avisando.
 *
 * Borde conocido y a propósito: un turno que cruza la medianoche cuelga de la
 * fecha de ayer, así que entre las 00:00 y su salida vuelve a leerse como
 * incompleto (ver `lib/terminal/jornada-en-curso.ts` y la 0240).
 *
 * Vivía copiada en «Lo mío» y en la Bandeja; Desempeño la necesitó el
 * 2026-09-26 —acusaba de «marcaje sin cerrar» a las seis personas que a
 * mediodía estaban en su turno— y se mudó acá para no escribir una tercera.
 */
export function esJornadaEnCurso(fecha: string, hoy: string, estadoJornada: string | null | undefined): boolean {
  return fecha === hoy && (estadoJornada === "abierta" || estadoJornada === "en_pausa");
}

/**
 * ¿Este día ya entra en «lo que le tocaba»?
 *
 * Los días pasados, siempre. Los futuros, nunca. Y HOY solo cuando su jornada
 * ya cerró con horas: mientras el día no termine, sumar sus horas esperadas
 * contra cero horas trabajadas pinta en deuda a todo el equipo al mediodía —
 * las horas de hoy entran abajo recién al marcar la salida, así que arriba
 * tienen que entrar a la vez.
 */
export function cuentaEnLoQueLeTocaba(fecha: string, hoy: string, jornada: JornadaDelDia | null): boolean {
  if (fecha < hoy) return true;
  if (fecha > hoy) return false;
  return jornada !== null && jornada.horas !== null && !esJornadaEnCurso(fecha, hoy, jornada.estado);
}

/** Las fechas ISO de un rango, ambas incluidas. */
export function fechasDelRango(desde: string, hasta: string): string[] {
  const out: string[] = [];
  const [y1, m1, d1] = desde.split("-").map(Number);
  const [y2, m2, d2] = hasta.split("-").map(Number);
  const fin = Date.UTC(y2, m2 - 1, d2);
  for (let t = Date.UTC(y1, m1 - 1, d1); t <= fin; t += 86_400_000) {
    out.push(new Date(t).toISOString().slice(0, 10));
  }
  return out;
}
