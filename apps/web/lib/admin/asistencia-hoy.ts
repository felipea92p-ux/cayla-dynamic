// ============================================================================
// asistencia-hoy.ts — la cuenta de «quién está dónde AHORA» en una sede
// ============================================================================
// QUÉ PROMETE · dado el estado de hoy de cada persona de una sede, decir quién
//               está trabajando, a cuántas les tocaba venir y si la sede llega
//               a su meta de cobertura — igual en cualquier pantalla.
// QUÉ ASUME   · que `estado` sale de `jornadas.estado` de HOY (o «sin_marcar»
//               si no hay fila) y que `entradaEsperadaHoy` sale de
//               `jornada-esperada.ts`, nunca de un cálculo propio.
//
// «TRABAJANDO» Y «EN PAUSA» SON DOS RESPUESTAS, NO UNA (2026-09-18).
// El Dashboard contaba como «trabajando» a quien estaba en pausa. `en_pausa` es
// cualquier salida temporal abierta —refrigerio, trámite, médico, personal—: la
// jornada sigue abierta, pero la persona NO está en el piso ni cubriendo la sede.
// En pleno refrigerio la pantalla decía «14 trabajando ahora» con nueve de esas
// catorce fuera, y una sede entera en pausa aparecía como «4 trabajando de 4».
// Acá se dice una sola vez; ninguna pantalla escribe a mano `abierta || en_pausa`
// para contestar «¿está trabajando?».
//
// (Esa unión SÍ es la respuesta correcta a OTRA pregunta —«¿su jornada de hoy
// sigue sin cerrar?»— y por eso sigue en /mio y en la bandeja: ahí se decide si
// falta una salida, no se cuenta gente en piso.)
//
// Vive acá y no dentro de `admin/dashboard/page.tsx` porque una página de Next
// solo puede exportar la página: cualquier otra cosa rompe el build, y así nada
// de esto se podía probar sin abrir un navegador.
// ============================================================================

import { TZ_LIMA, formatoMinutos } from "@cayla-dynamic/shared";

// Margen antes de avisar que una sede entera no marcó nada. No es la tolerancia
// de tardanza (esa es cero: SIN tolerancia, por minuto, según fn_recalcular_jornada) —
// esta es una franja solo de aviso operativo, y avisar al minuto uno generaría
// más ruido que señal con cualquier desfase normal de la mañana. Se reutiliza
// también para decidir, fila por fila, si alguien "sin marcar" ya debía haber
// llegado o si todavía es pronto — mismo criterio, mismo margen.
export const MARGEN_ALERTA_SEDE_MIN = 30;

// "08:00" → 8.0, para comparar contra horaDecimalLimaAhora().
export function horaDecimalDe(hhmm: string): number {
  const [h, m] = hhmm.slice(0, 5).split(":").map(Number);
  return h + (m || 0) / 60;
}

export interface FilaPersona {
  personaId: string;
  nombre: string;
  sede: string;
  sedeId: string;
  estado: string;
  entrada: string | null;
  salidaFinal: string | null;
  minutosTarde: number | null;
  salidaTemprana: number | null;
  enPausaSinRetorno: boolean;
  esOperativa: boolean; // cuenta contra la meta de operativas
  esEncargada: boolean; // supervisor_sede o marca es_encargada_piso
  // Vacaciones, descanso médico u otra ausencia de `ausencias` que cubre HOY.
  // Sin esto, alguien de vacaciones se ve idéntico a un "sin marcar" real en
  // la única pantalla que se mira de un vistazo — el mismo riesgo de falso
  // positivo que la 0101 ya resolvió para el semáforo disciplinario, pero acá
  // nadie lo había cerrado porque esta franja no pasa por fn_faltas_resumen.
  ausenciaHoy: { nombre: string; pendiente: boolean } | null;
  // "08:00" si el horario/turno de hoy dice que le tocaba trabajar; null si le
  // tocaba descanso o no se pudo determinar (misma cascada de jornada-esperada.ts).
  entradaEsperadaHoy: string | null;
  // "18:00": hasta cuándo le tocaba hoy, de la MISMA cascada que la entrada. null
  // o ausente = no se sabe cuándo termina su día, y eso NO es «ya terminó»:
  // sin este dato la sede nunca se declara fuera de horario (ver fueraDeHorarioDeHoy).
  salidaEsperadaHoy?: string | null;
  // Desde cuándo está en pausa (solo si `estado` es `en_pausa` y se pudo saber:
  // ver `pausaAbiertaDe`). null/ausente = no hay dato, NO «no está en pausa».
  pausa?: PausaAbierta | null;
  // De dónde salió esa respuesta (turno puntual / horario_por_dia / legacy /
  // sin_horario) — solo importa cuando entradaEsperadaHoy es null, para
  // distinguir "hoy descansa" (una respuesta real) de "no hay con qué medirlo"
  // (no es una respuesta). Ver jornada-esperada.ts:estadoDelDia, que ya hace
  // esta misma distinción para Correcciones/Incidencias.
  origenEsperadoHoy: "turno" | "horario" | "legacy" | "sin_horario";
}

// El hallazgo central de la auditoría de sep-2026: "Sin marcar" cubría tres
// situaciones que no tienen nada que ver entre sí — alguien que entra a las
// 4pm siendo la 1pm se veía IGUAL que alguien que debía entrar a las 8am y no
// llegó. El dato para distinguirlas ya existía (entradaEsperadaHoy, calculado
// arriba con la misma cascada que usa el backend); lo que faltaba era usarlo
// acá. "sin_horario" se deja aparte a propósito: ahí no sabemos si le tocaba
// o no, así que no se afirma "descansa hoy" — sería una falsa tranquilidad
// tan peligrosa como el falso positivo que esto viene a arreglar.
export type SubEstadoSinMarcar = "aun_no_inicia" | "falta_real" | "descansa" | "desconocido";
export function subEstadoSinMarcar(f: FilaPersona, ahoraDecimal: number): SubEstadoSinMarcar {
  if (f.entradaEsperadaHoy) {
    const yaDebiaHaberLlegado = ahoraDecimal >= horaDecimalDe(f.entradaEsperadaHoy) + MARGEN_ALERTA_SEDE_MIN / 60;
    return yaDebiaHaberLlegado ? "falta_real" : "aun_no_inicia";
  }
  return f.origenEsperadoHoy === "sin_horario" ? "desconocido" : "descansa";
}

// Las preguntas que el resumen de arriba cuenta y que los filtros y la
// cobertura vuelven a hacer. Estaban escritas a mano en cada sitio —la de
// "sin marcar y ya le tocaba" tres veces—, y si una copia cambiaba, el número
// del resumen y la lista de personas iban a dejar de coincidir sin que nada
// avisara. Una sola vez, acá.
//
// Reciben el `estado` y no la fila entera: la Hoja de sede lo tiene como texto
// suelto y no arma un `FilaPersona`.

/** En el piso ahora: entró y no está fuera. Solo `abierta`. */
export function trabajandoAhora(estado: string): boolean {
  return estado === "abierta";
}
/** Salió temporalmente y no ha vuelto (refrigerio, trámite, médico…). No trabaja ahora. */
export function enPausaAhora(estado: string): boolean {
  return estado === "en_pausa";
}
export function llegoTarde(f: FilaPersona): boolean {
  return (f.minutosTarde ?? 0) > 0;
}
// Sin marcar, sin ausencia que lo cubra, y con la hora de entrada (más el
// margen) ya pasada. Quien aún no entra o descansa hoy NO cuenta.
export function sinMarcarYaLeTocaba(f: FilaPersona, ahoraDecimal: number): boolean {
  return f.estado === "sin_marcar" && !f.ausenciaHoy && subEstadoSinMarcar(f, ahoraDecimal) === "falta_real";
}

// Las opciones del filtro «Estado» y qué estados de jornada trae cada una.
//
// «Salió» filtraba solo `cerrada`, y la tabla escribe «Salió (revisada)» para
// quien tiene la jornada `revisada`: filtrando por «Salió», tres de las cuatro
// personas que se habían ido de OTRU (2026-09-18) no aparecían, con la misma
// palabra en pantalla. Las opciones viven acá, y no en el JSX, para que una
// prueba compruebe que NINGÚN estado queda sin una opción que lo encuentre.
export const OPCIONES_FILTRO_ESTADO = [
  { valor: "abierta", etiqueta: "Trabajando" },
  { valor: "en_pausa", etiqueta: "En pausa" },
  { valor: "cerrada", etiqueta: "Salió" },
  { valor: "sin_marcar", etiqueta: "Sin marcar" },
  { valor: "auto_cerrada_pendiente", etiqueta: "Auto-cerrada" },
] as const;

/** ¿Este estado de jornada lo trae la opción del filtro? `todos` trae a todos. */
export function coincideConFiltroDeEstado(estado: string, filtro: string): boolean {
  if (filtro === "todos") return true;
  // «Salió» = la jornada terminó, esté o no revisada (así la llama la tabla).
  if (filtro === "cerrada") return estado === "cerrada" || estado === "revisada";
  return estado === filtro;
}

export interface MetaSede { man: number; tar: number; enc: number; }

// Cobertura de una sede en este momento: cuánta gente hay EN PISO ahora vs la
// meta del tramo. Se calcula una sola vez por sede y se reutiliza para
// ordenar, para el resumen global y para la tarjeta — antes esta cuenta vivía
// solo dentro del .map() de render y no se podía usar para decidir el orden.
export interface CoberturaSede {
  /** En el piso ahora (`abierta`). Es lo que cuenta contra la meta. */
  trabajando: FilaPersona[];
  /** Con la jornada abierta pero fuera un rato. No cuentan en piso ni como «trabajando». */
  enPausa: FilaPersona[];
  opPiso: number;
  encPiso: number;
  metaOp: number;
  metaEnc: number;
  sinMetaOp: boolean;
  sinMetaEnc: boolean;
  faltanOp: boolean;
  faltanEnc: boolean;
  problema: boolean;
  sinMarcarReal: number;
  programadosHoy: number;
  alertaSinEntrada: string | null;
  /** Cuántas personas del EQUIPO —estén hoy o no— son de un área operativa. */
  equipoOperativas: number;
  /** Cuántas del EQUIPO cuentan como líder en piso (rol de líder de sede o marca de piso). */
  equipoLideres: number;
  /**
   * Si la sede está fuera de su horario de hoy Y no queda nadie en piso: la meta
   * no se mide y `faltanOp`/`faltanEnc`/`problema` salen en falso. null = dentro
   * de horario, o no se puede saber. Ver `fueraDeHorarioDeHoy`.
   */
  fueraDeHorario: FueraDeHorario | null;
  /** De quienes les tocaba hoy, dónde está cada quien ahora. La suma es `programadosHoy`. */
  desgloseProgramadas: DesgloseProgramadas;
  /**
   * Cuántas de las personas EN PISO ahora cuentan en las dos metas a la vez: una
   * líder de tienda es de un área operativa Y líder. Por eso «2 operativas + 1 líder»
   * pueden ser solo 2 personas — decisión de 2026-09-18.
   */
  lideresEnAmbasMetas: number;
  /** Quienes marcaron hoy sin horario ni turno contra qué medirlos. Ver `marcaronSinHorario`. */
  marcaronSinHorario: FilaPersona[];
  /** Falta esta meta Y no se puede cumplir aunque vengan todos: se revisa en Turnos. */
  metaOpImposible: boolean;
  metaEncImposible: boolean;
  /**
   * «alerta» = falta gente que SÍ podría venir (rojo). «revisar» = lo único que
   * falta son metas imposibles de cumplir (ámbar: es un dato de Turnos). null = no
   * falta nada, o la sede está fuera de horario. `problema` sigue diciendo «falta
   * algo» sea cual sea la causa; esto dice qué tan urgente es.
   *
   * Costo conocido, aceptado a propósito: una tienda que pierde a su ÚNICA líder
   * también queda en «revisar» —equipo 0 contra meta 1—, porque la función no
   * puede distinguirla de una meta mal cargada sin historia. La pantalla dice la
   * causa y «Requiere atención» la lista, pero ya no es rojo.
   */
  gravedad: GravedadCobertura;
}

export type GravedadCobertura = "alerta" | "revisar" | null;

/**
 * Quienes marcaron hoy SIN tener ni horario vigente ni turno: nada mide su
 * puntualidad ni su falta, y no entran en «les tocaba a N». En TRU (2026-09-18)
 * trabajaron 11 y la pantalla decía «10 de las 12», sin avisar que una integrante
 * ni siquiera tenía horario cargado.
 *
 * Solo personal operativo y líderes: un administrador de Central sin horario es
 * normal, y avisarlo todos los días enseñaría a ignorar el aviso.
 *
 * `sin_horario` es «no hay con qué medirlo» y no «hoy descansa» (ver
 * `origenEsperadoHoy`). Ojo: si la consulta de turnos u horarios FALLA, todas las
 * filas llegan como `sin_horario`; quien llama tiene que apagar el aviso en ese
 * caso, porque acá no hay forma de distinguirlo.
 */
export function marcaronSinHorario(deSede: FilaPersona[]): FilaPersona[] {
  return deSede.filter(
    (f) => f.origenEsperadoHoy === "sin_horario" && f.entrada !== null && (f.esOperativa || f.esEncargada),
  );
}

/** Dónde está ahora cada persona a la que le tocaba trabajar hoy. Se reparten TODAS, sin sobrar ni faltar. */
export interface DesgloseProgramadas {
  enPiso: number;
  enPausa: number;
  /** Su jornada de hoy ya cerró (`cerrada`, `revisada` o `auto_cerrada_pendiente`). */
  yaSalieron: number;
  /** Sin marcar, y todavía no es su hora de entrada (más el margen). */
  aunNoLlegan: number;
  /** Sin marcar, y su hora de entrada ya pasó. Es la única falta real de la lista. */
  noLlegaron: number;
}

export interface FueraDeHorario {
  /** «antes» de la primera entrada programada de hoy, o «despues» de la última salida. */
  cuando: "antes" | "despues";
  /** «HH:MM» del límite que se cruzó: la primera entrada o la última salida. */
  hora: string;
}

/**
 * ¿La sede está fuera de su horario de HOY, sin nadie en piso? Entonces «Faltan 8»
 * no dice que falte gente: dice que ya cerró (o aún no abre).
 *
 * El caso que la originó (2026-09-18, tras el cierre): TRU marcó «Cobertura
 * insuficiente · Faltan 8 · Faltan 2» con sus once personas ya idas —la última
 * a las 20:23— y la décima descansando. La meta «de la tarde» corría de 14:15 a
 * medianoche, sin fin: el Dashboard no sabía cuándo cierra una tienda. Turnos
 * ya lo sabía («no se pinta rojo antes de abrir ni después de cerrar»).
 *
 * El horario sale de los turnos y horarios de las personas de HOY, no de una
 * hora de cierre escrita a mano por sede: un dato más para mantener al día
 * habría podido contradecir los turnos cargados.
 *
 * Solo dice «fuera de horario» cuando está segura. Cada duda cae hacia el rojo,
 * porque callar una falta de cobertura real cuesta más que un aviso de más:
 * · queda alguien en piso o en pausa (decisión: «solo si ya no queda nadie»);
 * · a nadie le tocaba hoy → no hay horario contra qué medir, sigue como estaba;
 * · a alguien le falta la hora de salida → no se sabe cuándo termina el día;
 * · algún turno cruza medianoche → el día de la sede no acaba en su fecha.
 */
export function fueraDeHorarioDeHoy(
  programadas: FilaPersona[],
  hayAlguienEnPiso: boolean,
  ahoraDecimal: number,
): FueraDeHorario | null {
  if (hayAlguienEnPiso || programadas.length === 0) return null;

  const primeraEntrada = programadas
    .map((f) => f.entradaEsperadaHoy!)
    .reduce((a, b) => (horaDecimalDe(b) < horaDecimalDe(a) ? b : a));
  if (ahoraDecimal < horaDecimalDe(primeraEntrada)) return { cuando: "antes", hora: primeraEntrada };

  const salidas = programadas.map((f) => f.salidaEsperadaHoy ?? null);
  if (salidas.some((s) => s === null)) return null;
  const cruzaMedianoche = programadas.some(
    (f, i) => horaDecimalDe(salidas[i]!) <= horaDecimalDe(f.entradaEsperadaHoy!),
  );
  if (cruzaMedianoche) return null;

  const ultimaSalida = (salidas as string[]).reduce((a, b) => (horaDecimalDe(b) > horaDecimalDe(a) ? b : a));
  return ahoraDecimal >= horaDecimalDe(ultimaSalida) ? { cuando: "despues", hora: ultimaSalida } : null;
}

export function calcularCoberturaSede(deSede: FilaPersona[], meta: MetaSede, tramoTarde: boolean, ahoraDecimal: number): CoberturaSede {
  const trabajando = deSede.filter((f) => trabajandoAhora(f.estado));
  const enPausa = deSede.filter((f) => enPausaAhora(f.estado));
  const metaOp = tramoTarde ? meta.tar : meta.man;
  // Cobertura EN VIVO: "en piso" = trabajando ahora. Quien está en pausa no
  // cuenta — no está físicamente cubriendo. Sale de la MISMA lista que el
  // recuadro «Trabajando ahora», así que las dos cifras no pueden discrepar.
  const opPiso = trabajando.filter((f) => f.esOperativa).length;
  const encPiso = trabajando.filter((f) => f.esEncargada).length;
  const sinMetaOp = metaOp <= 0;
  const sinMetaEnc = meta.enc <= 0;
  // Quienes tenían HOY un horario/turno real que decía que trabajaban — el
  // denominador que faltaba: "de Y" antes mezclaba a todo el equipo
  // (vacaciones, descansos, quien ya salió) con quien de verdad tenía que estar.
  // Ver hallazgo de la auditoría, Fase 4.
  const programadas = deSede.filter((f) => f.entradaEsperadaHoy !== null && !f.ausenciaHoy);
  const programadosHoy = programadas.length;
  // La meta solo se mide dentro del horario: fuera de él, «faltan» no es cierto.
  const fueraDeHorario = fueraDeHorarioDeHoy(programadas, trabajando.length + enPausa.length > 0, ahoraDecimal);
  const faltanOp = fueraDeHorario === null && !sinMetaOp && opPiso < metaOp;
  const faltanEnc = fueraDeHorario === null && !sinMetaEnc && encPiso < meta.enc;
  const sinMarcarReal = deSede.filter((f) => sinMarcarYaLeTocaba(f, ahoraDecimal)).length;

  // Dónde está cada persona a la que le tocaba hoy. Todo lo que no es «en piso»,
  // «en pausa» ni «sin marcar» es una jornada ya cerrada, así que el reparto
  // cubre todos los estados posibles y la suma es siempre `programadosHoy`.
  const desgloseProgramadas: DesgloseProgramadas = { enPiso: 0, enPausa: 0, yaSalieron: 0, aunNoLlegan: 0, noLlegaron: 0 };
  for (const f of programadas) {
    if (trabajandoAhora(f.estado)) desgloseProgramadas.enPiso++;
    else if (enPausaAhora(f.estado)) desgloseProgramadas.enPausa++;
    else if (f.estado === "sin_marcar") {
      if (subEstadoSinMarcar(f, ahoraDecimal) === "falta_real") desgloseProgramadas.noLlegaron++;
      else desgloseProgramadas.aunNoLlegan++;
    } else desgloseProgramadas.yaSalieron++;
  }
  const lideresEnAmbasMetas = trabajando.filter((f) => f.esOperativa && f.esEncargada).length;

  // Alerta de sede sin actividad: a alguien ya le tocaba entrar (según su
  // horario u horario), con margen, y todavía nadie de la sede marcó nada.
  // Se excluye a quien tiene una ausencia hoy — mandar de vacaciones a todo
  // el equipo de una sede no es "nadie llegó", es que nadie tenía que llegar.
  const entradasEsperadasHoy = deSede
    .filter((f) => !f.ausenciaHoy && f.entradaEsperadaHoy)
    .map((f) => f.entradaEsperadaHoy!)
    .sort();
  const nadieMarcoTodavia = deSede.every((f) => f.entrada === null);
  let alertaSinEntrada: string | null = null;
  if (entradasEsperadasHoy.length > 0 && nadieMarcoTodavia) {
    const primeraEntrada = entradasEsperadasHoy[0];
    const minutosPasados = (ahoraDecimal - horaDecimalDe(primeraEntrada)) * 60;
    if (minutosPasados >= MARGEN_ALERTA_SEDE_MIN) alertaSinEntrada = primeraEntrada;
  }

  // El equipo que PODRÍA cubrir cada meta, esté hoy o no. Sin esto, «0 de 1» no
  // distingue «faltó alguien que sí existe» de «en esta sede no hay quién pueda».
  const equipoOperativas = deSede.filter((f) => f.esOperativa).length;
  const equipoLideres = deSede.filter((f) => f.esEncargada).length;

  // ¿Lo que falta es gente que podría venir, o una meta que NO se puede cumplir
  // por más que vengan todos? Lo segundo es un dato por revisar en Turnos, no una
  // sede con menos gente de la que debía: el mismo rojo para las dos era un rojo
  // que nadie podía apagar viniendo a trabajar (LIM: meta de 4 con 3 personas;
  // CCO: meta de 1 líder sin nadie que cuente como líder).
  const metaOpImposible = faltanOp && causaMetaImposible("operativas", metaOp, equipoOperativas) !== null;
  const metaEncImposible = faltanEnc && causaMetaImposible("lideres", meta.enc, equipoLideres) !== null;
  const hayFaltaPosible = (faltanOp && !metaOpImposible) || (faltanEnc && !metaEncImposible);
  const gravedad: GravedadCobertura = hayFaltaPosible ? "alerta" : faltanOp || faltanEnc ? "revisar" : null;

  return {
    trabajando, enPausa, opPiso, encPiso, metaOp, metaEnc: meta.enc, sinMetaOp, sinMetaEnc,
    faltanOp, faltanEnc, problema: faltanOp || faltanEnc, sinMarcarReal, programadosHoy, alertaSinEntrada,
    equipoOperativas, equipoLideres, fueraDeHorario, desgloseProgramadas, lideresEnAmbasMetas,
    marcaronSinHorario: marcaronSinHorario(deSede),
    metaOpImposible, metaEncImposible, gravedad,
  };
}

/**
 * Por qué una meta NO se va a poder cumplir por más gente que venga, o null si
 * sí se puede. `resumen` cabe en una línea de «Requiere atención»; `detalle`
 * dice además qué hacer.
 *
 * El caso que la originó (2026-09-18): Central es solo administración —nadie de
 * un área operativa, nadie marcado como líder de piso— y aun así tenía una meta
 * de 1 líder en piso. La tarjeta decía «Cobertura insuficiente · Falta 1» todos
 * los días, y nadie podía hacer nada para apagarla: el problema no era de
 * asistencia, era que la meta no le correspondía a esa sede. Una alarma que
 * nunca se apaga enseña a ignorar todas las demás.
 *
 * NO cambia el color ni la gravedad, y eso es a propósito: si a una tienda se le
 * fue su única líder, el rojo es correcto. Solo dice la causa, para que quien
 * mira sepa qué arreglar.
 */
export function causaMetaImposible(
  quien: "operativas" | "lideres",
  meta: number,
  equipo: number,
): { resumen: string; detalle: string } | null {
  if (meta <= 0 || equipo >= meta) return null;
  if (equipo === 0) {
    return quien === "operativas"
      ? {
          resumen: "nadie del equipo es de un área operativa",
          detalle: "Nadie del equipo es de un área operativa. Si esta sede no las necesita, pon la meta en 0 en Turnos.",
        }
      : {
          resumen: "nadie del equipo cuenta como líder",
          detalle: "Nadie del equipo cuenta como líder. Si esta sede no lo necesita, pon la meta en 0 en Turnos.",
        };
  }
  const detalle = equipo === 1
    ? `La meta (${meta}) es mayor que la única persona del equipo que cuenta: aunque venga, no se cumple.`
    : `La meta (${meta}) es mayor que las ${equipo} personas del equipo que cuentan: aunque vengan todas, no se cumple.`;
  return { resumen: "la meta es mayor que el equipo", detalle };
}

/**
 * Lo que dice «Requiere atención» de una sede cuya única falta son metas que no se
 * pueden cumplir. Dice qué meta y por qué, y dónde se arregla: «faltan 4
 * operativas» sería mentira aquí, porque no hay a quién pedirle que venga.
 */
export function textoMetaPorRevisar(cob: CoberturaSede): string {
  const partes: string[] = [];
  if (cob.metaOpImposible) partes.push(`personal operativo: ${causaMetaImposible("operativas", cob.metaOp, cob.equipoOperativas)!.resumen}`);
  if (cob.metaEncImposible) partes.push(`líderes: ${causaMetaImposible("lideres", cob.metaEnc, cob.equipoLideres)!.resumen}`);
  return `revisa la meta en Turnos — ${partes.join("; ")}`;
}

// "2 operativas y 1 encargada": lo que le falta a una sede para su meta de
// ahora. Lo dicen "Requiere atención" y el detalle de "Sedes bajo la meta", con
// las mismas palabras (y las dos le agregan «en piso»).
export function loQueFalta(cob: CoberturaSede): string {
  const partes: string[] = [];
  if (cob.faltanOp) partes.push(`${cob.metaOp - cob.opPiso} operativa${cob.metaOp - cob.opPiso === 1 ? "" : "s"}`);
  if (cob.faltanEnc) partes.push(`${cob.metaEnc - cob.encPiso} ${cob.metaEnc - cob.encPiso === 1 ? "líder" : "líderes"}`);
  return partes.join(" y ");
}

// "Faltan 3" / "Falta 1" — concordancia real, no un texto fijo por métrica.
export function faltanTexto(n: number): string {
  return n === 1 ? "Falta 1" : `Faltan ${n}`;
}

/**
 * «14 de diciembre». Con `day: "2-digit"` el es-PE arma «14-diciembre» —con
 * guion y sin «de»—, que es lo que se leía en los avisos de contratos. Con
 * `numeric` sale la frase entera. La zona es UTC porque `iso` es una fecha
 * (sin hora): en la de Lima, «2026-12-14» caería al día anterior.
 */
export function fechaCorta(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { day: "numeric", month: "long", timeZone: "UTC" }).format(
    new Date(Date.UTC(y, m - 1, d)),
  );
}

/** «viernes 18 de setiembre». Sin la coma que agrega el es-PE tras el día de la semana. */
export function fechaConDia(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  const dia = new Intl.DateTimeFormat("es-PE", { weekday: "long", timeZone: "UTC" }).format(
    new Date(Date.UTC(y, m - 1, d)),
  );
  return `${dia} ${fechaCorta(iso)}`;
}

/**
 * Lo que dice «Requiere atención» de quien no marcó y ya le tocaba. Antes era
 * «N sin marcar y ya le tocaba» con «le» fijo: con dos personas, «2 … ya le
 * tocaba». Y sin verbo tras «ya le tocaba» — ¿qué?: entrar.
 */
export function textoSinMarcar(n: number): string {
  return n === 1
    ? "1 no ha marcado y ya le tocaba entrar"
    : `${n} no han marcado y ya les tocaba entrar`;
}

/**
 * De dónde sale «programadas hoy» frente al equipo entero de la sede.
 *
 * Antes eran dos cosas mal atadas: el encabezado decía «N trabajando de M
 * programadas» —el N cuenta a cualquiera que esté trabajando, el M solo a quien
 * tenía turno, así que podía salir «5 de 4»— y el renglón de abajo imprimía
 * siempre «no todas tenían turno hoy», aunque TODAS lo tuvieran (una sede de 2
 * con las 2 programadas decía lo contrario de sus propios números).
 *
 * «Les tocaba trabajar» y no «tenían turno»: quien está de vacaciones o con
 * descanso médico tiene su turno en el papel, pero hoy no le tocaba venir.
 */
export function textoEquipoDelDia(programadas: number, equipo: number): string {
  if (equipo <= 0) return "No hay personas en el equipo de esta sede.";
  if (equipo === 1) {
    return programadas >= 1
      ? "Hoy le tocaba trabajar a la única persona del equipo."
      : "A la única persona del equipo no le tocaba trabajar hoy.";
  }
  if (programadas <= 0) return `A ninguna de las ${equipo} personas del equipo le tocaba trabajar hoy.`;
  if (programadas >= equipo) return `Hoy les tocaba trabajar a las ${equipo} personas del equipo.`;
  return `Hoy ${programadas === 1 ? "le" : "les"} tocaba trabajar a ${programadas} de las ${equipo} personas del equipo.`;
}

/**
 * «Según el horario de hoy: 6 ya salieron · 3 aún no llegan · 1 no llegó y ya le
 * tocaba». Es lo que sigue a «Nadie está trabajando en este momento»: un 0 en
 * piso es lo mismo a las 4 p. m. de un cambio de turno que tras el cierre o con
 * una falta real, y hasta el 2026-09-18 la tarjeta los mostraba idénticos.
 * Solo nombra lo que existe (sin «0 en pausa») y devuelve null si a nadie le tocaba.
 */
export function textoDesglose(d: DesgloseProgramadas): string | null {
  const partes: string[] = [];
  if (d.enPiso > 0) partes.push(`${d.enPiso} trabajando`);
  if (d.enPausa > 0) partes.push(`${d.enPausa} en pausa`);
  if (d.yaSalieron > 0) partes.push(d.yaSalieron === 1 ? "1 ya salió" : `${d.yaSalieron} ya salieron`);
  if (d.aunNoLlegan > 0) partes.push(d.aunNoLlegan === 1 ? "1 aún no llega" : `${d.aunNoLlegan} aún no llegan`);
  if (d.noLlegaron > 0) partes.push(d.noLlegaron === 1 ? "1 no llegó y ya le tocaba" : `${d.noLlegaron} no llegaron y ya les tocaba`);
  return partes.length === 0 ? null : `Según el horario de hoy: ${partes.join(" · ")}.`;
}

/**
 * Por qué la meta no se está midiendo. Recibe la hora ya formateada («8:15 p. m.»):
 * darle formato es de la pantalla, y este módulo no depende de ella.
 */
export function textoFueraDeHorario(f: FueraDeHorario, horaFormateada: string): string {
  return f.cuando === "despues"
    ? `Ya pasó la última salida programada de hoy (${horaFormateada}) y nadie sigue en piso: la meta no se mide.`
    : `Todavía no llega la primera entrada programada de hoy (${horaFormateada}): la meta no se mide.`;
}

/** «A y B marcaron hoy sin horario ni turno asignado…»: dice quién y dónde se arregla. */
export function textoSinHorario(nombres: string[]): string | null {
  if (nombres.length === 0) return null;
  const quienes = nombres.length === 1
    ? nombres[0]
    : `${nombres.slice(0, -1).join(", ")} y ${nombres[nombres.length - 1]}`;
  return `${quienes} ${nombres.length === 1 ? "marcó" : "marcaron"} hoy sin horario ni turno asignado, así que nada mide su puntualidad. Se arregla en Horarios.`;
}

/** Aviso de que los dos recuadros de cobertura pueden contar a la misma persona. */
export function textoLiderEnLasDosMetas(n: number): string | null {
  if (n <= 0) return null;
  return n === 1
    ? "1 líder de equipo cuenta en las dos metas: personal operativo y líderes."
    : `${n} líderes de equipo cuentan en las dos metas: personal operativo y líderes.`;
}

// ============================================================================
// «Desde cuándo» está en pausa cada persona
// ============================================================================
// `jornadas.estado = 'en_pausa'` dice QUE alguien está fuera, no desde cuándo.
// Sin eso, un refrigerio de 40 minutos y un retorno que nadie marcó hace tres
// horas se ven idénticos —el mismo «en pausa»— y son lo opuesto: el primero es
// lo normal, el segundo es una jornada que alguien tiene que corregir. La hora
// exacta de la salida vive en los marcajes, que son la fuente de verdad.
//
// QUÉ PROMETE · dadas las marcas NO anuladas de hoy de alguien que la base ya
//               marcó «en pausa», decir qué salida sigue abierta y desde cuándo.
// QUÉ ASUME   · que la persona ya está en pausa según `jornadas.estado`. Esto NO
//               decide SI está en pausa (lo decide la base, en un solo sitio):
//               solo cuándo empezó. Replica la regla de fn_recalcular_jornada —la
//               última `salida_*` que no sea la final, sin un `retorno_*` después—
//               y si no encuentra una salida abierta devuelve null, nunca inventa.

/** Lo mínimo de un marcaje que hace falta para saber si hay una pausa abierta. */
export interface MarcaDePausa { tipo: string; timestamp_marca: string }

export interface PausaAbierta {
  /** La salida que sigue abierta: `salida_almuerzo`, `salida_tramite`… */
  tipo: string;
  /** Cuándo salió: el `timestamp_marca` de esa salida, tal cual llega de la base. */
  desde: string;
}

export function pausaAbiertaDe(marcas: MarcaDePausa[]): PausaAbierta | null {
  const enOrden = [...marcas].sort((a, b) => Date.parse(a.timestamp_marca) - Date.parse(b.timestamp_marca));
  let abierta: PausaAbierta | null = null;
  for (const m of enOrden) {
    // Con la salida final el día cerró: la base ya no dice «en pausa» para él.
    if (m.tipo === "salida_final") return null;
    if (m.tipo.startsWith("salida_")) abierta = { tipo: m.tipo, desde: m.timestamp_marca };
    else if (m.tipo.startsWith("retorno_")) abierta = null;
  }
  return abierta;
}

/** Minutos que lleva algo abierto. Nunca negativo: un reloj adelantado no da «hace -3 min». */
export function minutosDesde(desde: string, ahora: Date = new Date()): number {
  return Math.max(0, Math.floor((ahora.getTime() - Date.parse(desde)) / 60_000));
}

/** «1:05 p. m.» — la hora de Lima de un instante, sin cero a la izquierda. */
export function horaCortaLima(iso: string): string {
  return new Intl.DateTimeFormat("es-PE", {
    timeZone: TZ_LIMA, hour: "numeric", minute: "2-digit", hour12: true,
  }).format(new Date(iso));
}

/**
 * «desde la 1:05 p. m.» / «desde las 2:40 p. m.». El artículo lo pide la hora:
 * es «la una» pero «las dos». Y es justo la hora del refrigerio la que cae en
 * «la una», así que escribir «desde las» a secas sería el error más frecuente.
 */
export function desdeLaHora(iso: string): string {
  const hora = Number(
    new Intl.DateTimeFormat("es-PE", { timeZone: TZ_LIMA, hour: "numeric", hour12: true })
      .formatToParts(new Date(iso)).find((p) => p.type === "hour")?.value,
  );
  return `desde ${hora === 1 ? "la" : "las"} ${horaCortaLima(iso)}`;
}

/**
 * Por qué salió, dicho sin detalle: «refrigerio» (lo esperado, y lo único que
 * tiene un tramo previsto) u «otra salida».
 *
 * A propósito NO se distingue «médico» ni «asunto personal». Esta pantalla se
 * mira de un vistazo, se comparte y se captura, y «fulana salió al médico» es un
 * dato de salud con nombre propio en un lugar que no lo necesita. El detalle
 * sigue en Correcciones, para quien lo tiene que resolver.
 */
export function motivoDePausa(tipo: string): string {
  return tipo === "salida_almuerzo" ? "refrigerio" : "otra salida";
}

/**
 * «refrigerio desde la 1:05 p. m.» — sin cuánto lleva. Es lo que va en un papel
 * impreso: la hora de salida es un hecho que no envejece, mientras que «45 min»
 * solo era cierto en el instante de imprimir y leído mañana afirma lo que no es.
 */
export function textoPausaDesde(p: PausaAbierta): string {
  return `${motivoDePausa(p.tipo)} ${desdeLaHora(p.desde)}`;
}

/** «refrigerio desde la 1:05 p. m. · 45 min» — para una pantalla que se refresca sola. */
export function textoPausa(p: PausaAbierta, ahora: Date = new Date()): string {
  return `${textoPausaDesde(p)} · ${formatoMinutos(minutosDesde(p.desde, ahora))}`;
}

/**
 * Para ordenar «En pausa»: quien lleva más tiempo fuera va primero —es a quien
 * hay que mirar—, y quien no tiene dato va al final en vez de mezclarse.
 */
export function porPausaMasLarga(a: { pausa?: PausaAbierta | null }, b: { pausa?: PausaAbierta | null }): number {
  const ta = a.pausa ? Date.parse(a.pausa.desde) : Infinity;
  const tb = b.pausa ? Date.parse(b.pausa.desde) : Infinity;
  if (ta === tb) return 0;
  return ta < tb ? -1 : 1;
}
