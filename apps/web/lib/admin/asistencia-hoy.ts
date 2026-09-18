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
// Vivía dentro de `admin/dashboard/page.tsx`. Una página de Next solo puede
// exportar la página (cualquier otra cosa rompe el build), así que ninguna de
// estas reglas se podía probar sin abrir un navegador. Esta mudanza no cambia
// lo que nada hace: mueve el código tal cual, para poder probarlo ANTES de
// tocarlo.
// ============================================================================

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

// Las tres preguntas que el resumen de arriba cuenta y que los filtros y la
// cobertura vuelven a hacer. Estaban escritas a mano en cada sitio —la de
// "sin marcar y ya le tocaba" tres veces—, y si una copia cambiaba, el número
// del resumen y la lista de personas iban a dejar de coincidir sin que nada
// avisara. Una sola vez, acá.
export function estaTrabajando(f: FilaPersona): boolean {
  return f.estado === "abierta" || f.estado === "en_pausa";
}
export function llegoTarde(f: FilaPersona): boolean {
  return (f.minutosTarde ?? 0) > 0;
}
// Sin marcar, sin ausencia que lo cubra, y con la hora de entrada (más el
// margen) ya pasada. Quien aún no entra o descansa hoy NO cuenta.
export function sinMarcarYaLeTocaba(f: FilaPersona, ahoraDecimal: number): boolean {
  return f.estado === "sin_marcar" && !f.ausenciaHoy && subEstadoSinMarcar(f, ahoraDecimal) === "falta_real";
}

export interface MetaSede { man: number; tar: number; enc: number; }

// Cobertura de una sede en este momento: cuánta gente hay EN PISO ahora vs la
// meta del tramo. Se calcula una sola vez por sede y se reutiliza para
// ordenar, para el resumen global y para la tarjeta — antes esta cuenta vivía
// solo dentro del .map() de render y no se podía usar para decidir el orden.
export interface CoberturaSede {
  activos: FilaPersona[];
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
}
export function calcularCoberturaSede(deSede: FilaPersona[], meta: MetaSede, tramoTarde: boolean, ahoraDecimal: number): CoberturaSede {
  const activos = deSede.filter(estaTrabajando);
  const metaOp = tramoTarde ? meta.tar : meta.man;
  // Cobertura EN VIVO: "en piso" = solo Presente (abierta). Quien está en
  // pausa/refrigerio no cuenta — no está físicamente cubriendo ahora.
  const opPiso = deSede.filter((f) => f.esOperativa && f.estado === "abierta").length;
  const encPiso = deSede.filter((f) => f.esEncargada && f.estado === "abierta").length;
  const sinMetaOp = metaOp <= 0;
  const sinMetaEnc = meta.enc <= 0;
  const faltanOp = !sinMetaOp && opPiso < metaOp;
  const faltanEnc = !sinMetaEnc && encPiso < meta.enc;
  const sinMarcarReal = deSede.filter((f) => sinMarcarYaLeTocaba(f, ahoraDecimal)).length;
  // Cuántas de las personas asignadas a esta sede tenían HOY un horario/turno
  // real que decía que trabajaban — el denominador que faltaba: "de Y" antes
  // mezclaba a todo el equipo (vacaciones, descansos, quien ya salió) con
  // quien de verdad tenía que estar. Ver hallazgo de la auditoría, Fase 4.
  const programadosHoy = deSede.filter((f) => f.entradaEsperadaHoy !== null && !f.ausenciaHoy).length;

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

  return {
    activos, opPiso, encPiso, metaOp, metaEnc: meta.enc, sinMetaOp, sinMetaEnc,
    faltanOp, faltanEnc, problema: faltanOp || faltanEnc, sinMarcarReal, programadosHoy, alertaSinEntrada,
  };
}

// "2 operativas y 1 encargada": lo que le falta a una sede para su meta de
// ahora. Lo dicen "Requiere atención" y el detalle de "Sedes bajo mínimo", con
// las mismas palabras.
export function loQueFalta(cob: CoberturaSede): string {
  const partes: string[] = [];
  if (cob.faltanOp) partes.push(`${cob.metaOp - cob.opPiso} operativa${cob.metaOp - cob.opPiso === 1 ? "" : "s"}`);
  if (cob.faltanEnc) partes.push(`${cob.metaEnc - cob.encPiso} encargada${cob.metaEnc - cob.encPiso === 1 ? "" : "s"}`);
  return partes.join(" y ");
}

// "Faltan 3" / "Falta 1" — concordancia real, no un texto fijo por métrica.
export function faltanTexto(n: number): string {
  return n === 1 ? "Falta 1" : `Faltan ${n}`;
}
