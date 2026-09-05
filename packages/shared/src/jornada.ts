// ============================================================================
// jornada.ts — Los topes de jornada, en un solo sitio
// ============================================================================
// Están acá y no escritos a mano en cada pantalla por la misma razón que
// `permisos.ts` y `fecha-lima.ts`: son números que deciden si alguien está
// dentro o fuera de la ley, y no pueden tener dos versiones.
//
// La distinción entre los dos es lo que evita un pasivo, así que conviene
// tenerla clara antes de tocarlos:
//
//   MAXIMO_LEGAL_SEMANAL (48 h)  Tope constitucional (art. 25). Es la JORNADA
//                                ORDINARIA pactada en los contratos de CAYLA y
//                                declarada en el RIT. Pasarse de acá es
//                                infracción, no algo que se pueda pagar.
//
//   HORARIO_PROGRAMADO_SEMANAL   Lo que CAYLA efectivamente programa. Es una
//   (45 h)                       decisión de la empresa, revisable dentro de la
//                                jornada ordinaria, y NO es el umbral del
//                                sobretiempo.
//
// ⚠️ El sobretiempo se mide contra la jornada ORDINARIA (48), no contra el
// horario programado (45) — D.S. 007-2002-TR art. 9. Igualar estas dos
// constantes convertiría las horas 46 a 48 en sobretiempo con recargo del
// 25 % / 35 %, y hoy hay gente trabajando en ese rango.
//
// Si cambian, hay que cambiar a la vez: los contratos, el RIT (art. de jornada,
// v3.2) y la política salarial publicada. Los cuatro dicen lo mismo a propósito.
// ============================================================================

/** Tope constitucional y jornada ordinaria pactada. Pasarse es infracción. */
export const MAXIMO_LEGAL_SEMANAL = 48;

/** Lo que CAYLA programa. Por debajo del tope, por decisión de la empresa. */
export const HORARIO_PROGRAMADO_SEMANAL = 45;

/**
 * Recargo del sobretiempo sobre el valor de la hora ordinaria
 * (D.S. 007-2002-TR art. 10). Las dos primeras horas al 25 %, el resto al 35 %.
 */
export const RECARGO_SOBRETIEMPO = {
  /** Horas a las que aplica el primer tramo. */
  horasPrimerTramo: 2,
  primerTramo: 0.25,
  tramoSiguiente: 0.35,
} as const;

/**
 * Cuántas horas de una semana exceden la jornada ordinaria.
 * Devuelve 0 cuando no hay exceso — nunca un negativo.
 */
export function excesoSobreJornada(horasSemana: number): number {
  return Math.max(0, horasSemana - MAXIMO_LEGAL_SEMANAL);
}

// ── Descanso semanal ────────────────────────────────────────────────────────
// El D. Leg. 713 art. 1 da derecho a 24 horas consecutivas de descanso «en cada
// semana». Y el Informe 027-2021-MTPE/14 de la Dirección General de Trabajo
// —criterio VINCULANTE para la administración laboral— aclara qué es «semana»:
//
//   «la semana debe ser entendida como el período o ciclo de siete días,
//    indistintamente si dichos siete días se corresponden con los que se
//    ordenan cronológicamente en los calendarios: lunes a domingo»
//
// La diferencia no es teórica. Con semana calendario y descanso rotativo se
// puede cumplir «un descanso por semana» y encadenar doce días: descansar el
// lunes de una semana y el domingo de la siguiente. Cada semana cuadra, la
// persona trabajó doce días seguidos. Medido en CAYLA el 2026-08-08: 30 rachas
// desde enero, la peor de 20 días.
//
// Por eso el tope se cuenta en DÍAS CONSECUTIVOS y no por semana calendario.

/** Días seguidos que se pueden trabajar. El siguiente tiene que ser descanso. */
export const MAXIMO_DIAS_SIN_DESCANSO = 6;

/**
 * Cuántos días seguidos lleva trabajados una persona, contando hacia atrás desde
 * `hasta`. Devuelve 0 si ese día no trabajó — la racha se cortó, que es lo que
 * hace un descanso.
 *
 * `fechas` son los días CON horas marcadas, en formato ISO (YYYY-MM-DD). El
 * orden no importa. Vacaciones, permisos y descansos simplemente no están en la
 * lista, y por eso cortan la racha.
 */
export function diasSeguidosTrabajados(fechas: readonly string[], hasta: string): number {
  const set = new Set(fechas);
  if (!set.has(hasta)) return 0;
  let dias = 0;
  // Se cuenta en UTC a propósito: son fechas civiles (YYYY-MM-DD), no instantes.
  // Restar días sobre una fecha local cruzaría mal el cambio de día en Lima.
  const cursor = new Date(`${hasta}T00:00:00Z`);
  while (set.has(cursor.toISOString().slice(0, 10))) {
    dias++;
    cursor.setUTCDate(cursor.getUTCDate() - 1);
  }
  return dias;
}

/** Lo que hay que avisar sobre la racha de alguien, o `null` si no hay nada. */
export interface AvisoRacha {
  /** Días seguidos trabajados hasta `ultimo`. */
  seguidos: number;
  /** Último día con marcas: la fecha a la que se ancla el aviso. */
  ultimo: string;
  /** Ya pasó del tope — la infracción ocurrió y no se puede deshacer. */
  excedida: boolean;
}

/**
 * Qué avisar sobre los días seguidos de una persona, a partir de sus días CON
 * marcas. Devuelve `null` cuando no hay nada que decir.
 *
 * Lo que esta función agrega sobre `diasSeguidosTrabajados` es CUÁNDO callarse, y
 * es la parte que se aprendió tarde:
 *
 * Un descanso no deja rastro en `jornadas` — simplemente no hay fila ese día. Así
 * que lo único que distingue «lleva 6 seguidos y mañana le toca descansar» de
 * «llevó 6 seguidos y ya descansó» es si su último día marcado se quedó atrás.
 * Contar hacia atrás desde el último día marcado, sin mirar qué tan viejo es, da
 * el mismo 6 en los dos casos — y el aviso pide un descanso que ya ocurrió.
 *
 * Por eso el aviso de 6 caduca: con `ultimo` de anteayer o antes, ya sabemos qué
 * pasó al día siguiente —no trabajó— y sobra decir nada. Con `ultimo` de AYER se
 * avisa igual, porque puede que hoy trabaje y aún no haya marcado, y ese es justo
 * el momento en que mover el turno todavía sirve.
 *
 * El de 7+ NO caduca, y es a propósito: esa infracción ya ocurrió, y hacerla
 * desaparecer sola sería borrarla sin que nadie la mirara. Se saca de la pantalla
 * con visto bueno, que deja constancia de quién la revisó.
 */
export function avisoDeRacha(fechas: readonly string[], hoy: string): AvisoRacha | null {
  if (fechas.length === 0) return null;
  const ultimo = fechas.reduce((a, b) => (a > b ? a : b));
  const seguidos = diasSeguidosTrabajados(fechas, ultimo);
  if (seguidos < MAXIMO_DIAS_SIN_DESCANSO) return null;

  const excedida = seguidos > MAXIMO_DIAS_SIN_DESCANSO;
  if (!excedida) {
    // Ayer, en fechas civiles: restar sobre una fecha local cruzaría mal el
    // cambio de día en Lima, igual que en `diasSeguidosTrabajados`.
    const ayer = new Date(`${hoy}T00:00:00Z`);
    ayer.setUTCDate(ayer.getUTCDate() - 1);
    if (ultimo < ayer.toISOString().slice(0, 10)) return null;
  }
  return { seguidos, ultimo, excedida };
}

/**
 * Las horas de la ventana de 7 días consecutivos MÁS CARGADA que termina dentro
 * del rango mirado. Devuelve la ventana y sus horas, o `null` si no hay datos.
 *
 * Por qué una ventana móvil y no la semana de lunes a domingo: el mismo Informe
 * 027-2021-MTPE/14 dice que la semana, «para los efectos de la determinación del
 * tiempo de trabajo», es un ciclo de siete días y no el que ordena el calendario.
 *
 * La diferencia se ve con doce días seguidos de 8 h. Partidos en semanas de
 * calendario dan 48 y 48 —ninguna se pasa— pero cualquier ventana de siete días
 * de esa racha suma 56. Medir por calendario deja pasar justo el caso que hay
 * que ver.
 *
 * Pero «ventana móvil» no significa cruzar por encima de un descanso. Un día sin
 * horas registradas CORTA la racha, igual que corta el ciclo en el cálculo de
 * planilla (`ot_islas` en `sobretiempo_ciclo_por_ciclo.sql`) — si no se corta acá
 * también, la ventana suma la cola de una racha de trabajo con el arranque de la
 * siguiente, separadas por un descanso real, y reporta horas que ninguna semana
 * de verdad trabajó. Pasó el 2026-08-29 con Lizzelott Ramírez: 18-22 ago (45.36 h)
 * más 24-25 ago (15.6 h), puenteadas sobre el descanso del 23, dieron una alerta
 * de «53.2 h en 7 días» que la boleta nunca pagó porque el ciclo real jamás llegó
 * a 48.
 */
export function ventanaMasCargada(
  dias: readonly { fecha: string; horas: number }[],
  desde: string,
  hasta: string,
): { fin: string; horas: number } | null {
  const porFecha = new Map<string, number>();
  for (const d of dias) porFecha.set(d.fecha, (porFecha.get(d.fecha) ?? 0) + d.horas);

  let mejor: { fin: string; horas: number } | null = null;
  const cursor = new Date(`${desde}T00:00:00Z`);
  const tope = new Date(`${hasta}T00:00:00Z`);
  while (cursor <= tope) {
    const fin = cursor.toISOString().slice(0, 10);
    // La ventana es el día y los seis anteriores, pero solo mientras sigan
    // siendo racha: un día sin horas la corta, no se sigue sumando más atrás.
    let suma = 0;
    const atras = new Date(cursor);
    for (let i = 0; i < 7; i++) {
      const horasDia = porFecha.get(atras.toISOString().slice(0, 10)) ?? 0;
      if (horasDia <= 0) break;
      suma += horasDia;
      atras.setUTCDate(atras.getUTCDate() - 1);
    }
    if (mejor === null || suma > mejor.horas) mejor = { fin, horas: suma };
    cursor.setUTCDate(cursor.getUTCDate() + 1);
  }
  return mejor;
}

// ── El tope de la noche que cruza la medianoche ─────────────────────────────
//
// Quien cierra tienda a las 00:30 sigue dentro de la jornada de AYER: su salida
// pertenece a ese turno, no al día nuevo (migración 0240). Pero esa adopción no
// puede ser eterna, porque entonces una jornada que alguien olvidó cerrar se
// comería el día siguiente entero. Pasadas estas horas desde su ENTRADA, la
// marca vuelve a ser del día que dice el calendario y el auto-cierre hace su
// trabajo.
//
// ⚠️ ESTE NÚMERO VIVE EN DOS SITIOS Y TIENE QUE DECIR LO MISMO EN LOS DOS.
// El otro es `fn_registrar_marcaje`, en el `select` que adopta la jornada del
// día anterior: `p_timestamp_cliente <= j.entrada_ts + interval '16 hours'`.
// No se puede compartir el valor —uno es TypeScript en el navegador y el otro
// es plpgsql—, así que lo que sí se puede es que solo haya UNA copia de cada
// lado y que las dos se nombren mutuamente.
//
// Que se separaran costaba esto: el navegador seguía mostrando «tu jornada de
// ayer sigue en curso» y ofrecía un menú de SALIDAS pasadas las 16 h, mientras
// el servidor ya había cambiado de opinión y esperaba una `entrada`. La persona
// pulsaba, el servidor rechazaba —«tipo salida_final no válido en el estado
// actual (se esperaba entrada)»— y no había ninguna salida hacia adelante: el
// único botón que la pantalla ofrecía era el que el servidor iba a rechazar
// siempre. Quedaba sin poder marcar hasta que el auto-cierre corriera.
export const TOPE_JORNADA_CRUZA_MEDIANOCHE_HORAS = 16;
