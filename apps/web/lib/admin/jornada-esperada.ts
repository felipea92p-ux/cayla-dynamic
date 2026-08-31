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
// `admin/turnos/page.tsx` (`horasDeTramo` y `celda`, la grilla de turnos) se
// unificó el 2026-08-31 — era la última copia, y CLAUDE.md ya prohíbe una quinta.
// Su matiz: la grilla necesitaba DOS respuestas distintas para la salida de un
// turno puntual sin `hora_salida` propia — la cruda (para precargar el formulario
// de edición, que nunca debe mostrar una hora inventada como si alguien la
// hubiera tecleado) y la de esta cascada (`Esperado.salida`, que si hace falta
// cae al horario base — es la única rama de la cascada que de verdad infiere
// algo; la del horario base sin turno nunca inventa, ver más abajo). `celda`
// guarda las dos por separado (`salida` cruda y `salidaEstimada` de la cascada)
// y decide caso por caso cuál usar: el formulario, la cruda; el cálculo de
// cobertura y el dibujo de la barra, la estimada.
//
// Antes de escribir una función nueva que responda «¿le tocaba trabajar ese
// día?», usar ésta.

export interface TurnoDia {
  hora_entrada: string | null;
  hora_salida: string | null;
  es_descanso: boolean;
}

/**
 * Los campos de un horario que hace falta conocer para la cascada — sin
 * vigencia ni persona, que solo le interesan a `horarioVigente` (quién elige
 * QUÉ tramo rige, un problema distinto). Separado para que una pantalla como
 * `admin/turnos/page.tsx`, que ya trae sus propios tramos con otro shape,
 * pueda usar la cascada sin tener que adoptar `HorarioTramo` completo.
 */
export interface HorarioBase {
  hora_entrada: string | null;
  hora_salida: string | null;
  dias_laborables: number[] | null;
  horario_por_dia: Record<string, { e?: string; s?: string; r?: number }> | null;
  almuerzo_min_minutos: number | null;
}

export interface HorarioTramo extends HorarioBase {
  persona_id: string;
  vigente_desde: string;
  vigente_hasta: string | null;
}

export interface Esperado {
  /** ¿Le tocaba trabajar ese día? */
  trabaja: boolean;
  /** "08:00" — contra esto se mide la tardanza. */
  entrada: string | null;
  salida: string | null;
  /** Horas de la jornada ya sin refrigerio. 0 si no le tocaba o no se sabe. */
  horas: number;
  /** Minutos de refrigerio de ese día — para dibujar el hueco en una barra. Ya está descontado de `horas`, esto es solo para mostrarlo. */
  refrigerioMin: number;
  /** De dónde salió la respuesta, para poder decirlo en pantalla. */
  origen: "turno" | "horario" | "legacy" | "sin_horario";
}

const NADA: Esperado = { trabaja: false, entrada: null, salida: null, horas: 0, refrigerioMin: 0, origen: "sin_horario" };

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
export function esperadoDelDia(fecha: string, turno: TurnoDia | null, horario: HorarioBase | null): Esperado {
  const dow = String(dowDe(fecha));
  const delDia = horario?.horario_por_dia?.[dow] ?? null;
  // El refrigerio del día sale del horario base aunque el turno lo pise: un
  // turno guarda entrada y salida, nunca cuánto se almuerza.
  const refrigerio = delDia?.r ?? horario?.almuerzo_min_minutos ?? 0;

  // 1 · El turno del día manda. Es la ÚNICA rama que de verdad infiere algo: si
  //     el turno no trajo su propia salida, cae al horario base para no dejar
  //     la jornada sin fin conocido. Quien muestre este resultado en un campo
  //     editable (no solo en un cálculo) debe decidir si le sirve una salida
  //     inferida o si prefiere la cruda del turno — ver `admin/turnos/page.tsx`.
  if (turno) {
    if (turno.es_descanso) return { trabaja: false, entrada: null, salida: null, horas: 0, refrigerioMin: refrigerio, origen: "turno" };
    if (turno.hora_entrada) {
      const e = turno.hora_entrada.slice(0, 5);
      const s = turno.hora_salida?.slice(0, 5) ?? delDia?.s?.slice(0, 5) ?? horario?.hora_salida?.slice(0, 5) ?? null;
      return { trabaja: true, entrada: e, salida: s, horas: s ? horasEntre(e, s, refrigerio) : 0, refrigerioMin: refrigerio, origen: "turno" };
    }
  }

  if (!horario) return NADA;

  // 2 · El horario base por día. Un día AUSENTE del jsonb es descanso — y eso
  //     es una respuesta, no un «no sé»: por eso no se cae al legacy. Y si el
  //     día SÍ está pero sin `.s`, tampoco se inventa una salida de otro lado:
  //     esta rama no tiene, a propósito, el mismo fallback que la del turno.
  if (horario.horario_por_dia) {
    if (!delDia?.e) return { trabaja: false, entrada: null, salida: null, horas: 0, refrigerioMin: refrigerio, origen: "horario" };
    const e = delDia.e.slice(0, 5);
    const s = delDia.s?.slice(0, 5) ?? null;
    return { trabaja: true, entrada: e, salida: s, horas: s ? horasEntre(e, s, refrigerio) : 0, refrigerioMin: refrigerio, origen: "horario" };
  }

  // 3 · El resumen legacy, para los horarios que nunca se migraron al jsonb.
  if (horario.dias_laborables && horario.hora_entrada) {
    const toca = horario.dias_laborables.includes(Number(dow));
    if (!toca) return { trabaja: false, entrada: null, salida: null, horas: 0, refrigerioMin: refrigerio, origen: "legacy" };
    const e = horario.hora_entrada.slice(0, 5);
    const s = horario.hora_salida?.slice(0, 5) ?? null;
    return { trabaja: true, entrada: e, salida: s, horas: s ? horasEntre(e, s, refrigerio) : 0, refrigerioMin: refrigerio, origen: "legacy" };
  }

  return NADA;
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
