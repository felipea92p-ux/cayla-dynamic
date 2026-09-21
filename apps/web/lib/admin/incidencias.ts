import {
  MAXIMO_LEGAL_SEMANAL, avisoDeRacha, cuentaEnCobertura, ventanaMasCargada, maximoSemanalPracticante,
} from "@cayla-dynamic/shared";
import { diaDeLaSedeDe, esperadoDelDia, horarioVigente, type HorarioTramo, type TurnoDia } from "./jornada-esperada";
import { loQueNoSePudo } from "./lo-que-no-se-pudo";

/**
 * QUÉ INCIDENCIAS DE ASISTENCIA HAY QUE MIRAR.
 *
 * QUÉ PROMETE. Con las filas que la pantalla de Incidencias ya trae de la base,
 * devuelve la lista de avisos: cada uno con su tipo, su texto, su severidad, la
 * categoría del resumen y, si se puede dar por revisado, el valor que se estaría
 * aceptando. Es la misma detección que vivía dentro de
 * `admin/incidencias/page.tsx` hasta el 2026-09-15, movida sin cambiar ninguna
 * regla, para que se pueda probar y para que otra pantalla no tenga que copiarla.
 *
 * QUÉ ASUME. Que las fechas son días de calendario de Lima (YYYY-MM-DD) y que
 * los permisos ya los aplicó la base: RLS y las RPC con alcance por rol. Acá no
 * se decide quién ve qué.
 *
 * QUÉ NO HACE. No consulta nada, no escribe nada y no sanciona nada. Dynamic
 * detecta y avisa; la decisión es de una persona.
 *
 * Por qué las VENTANAS de consulta viven también acá (`ventanasDeConsulta`): la
 * consulta de aceptaciones tiene que mirar al menos tan atrás como el aviso más
 * profundo, o un aviso que ya diste por revisado reaparece solo por mover una
 * fecha. Pasó cuando la 0185 subió el exceso a 30 días y esa consulta seguía en
 * 20. Con los números escritos en un solo sitio no se pueden separar.
 */

// ── Umbrales (ninguno sale de una ley salvo donde se dice) ─────────────────

/** Patrón de tardanzas: ventana fija desde hoy, independiente de Desde/Hasta.
 * Mira el estado disciplinario ACTUAL de la persona, no lo que se esté filtrando.
 * La ley peruana no fija una cifra (D.S. 003-97-TR art. 25 exige reiteración y
 * sanciones progresivas documentadas): es el umbral que eligió Felipe para que
 * Dynamic avise. El que arma un memo se cuenta por mes calendario en Disciplina. */
export const VENTANA_PATRON_DIAS = 30;
export const UMBRAL_PATRON_TARDANZAS = 3;
/** Cuántos días atrás se buscan ventanas de 7 días que pasen el tope. Antes eran
 * 7, y un exceso de 58.96 h (31 jul → 6 ago 2026) desapareció sin que nadie lo viera. */
export const VENTANA_EXCESO_DIAS = 30;
/** Mientras la ventana toque la última semana, todavía se puede mover un turno. */
export const EXCESO_AUN_EVITABLE_DIAS = 6;
/** Días de marcaje para medir la racha en curso: la más larga medida en CAYLA fue de 20. */
export const VENTANA_RACHA_DIAS = 20;

// ── Fechas civiles (UTC a propósito: son días, no instantes) ───────────────

function parseISO(iso: string): Date {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d));
}
export function addDias(iso: string, n: number): string {
  const d = parseISO(iso);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}
/** 0 = domingo … 6 = sábado. */
function diaSemanaNum(iso: string): number {
  return parseISO(iso).getUTCDay();
}
/** Lunes de la semana de `iso` (lunes–domingo), el mismo criterio que admin/turnos. */
export function lunesDeLaSemana(iso: string): string {
  const dow = diaSemanaNum(iso);
  return addDias(iso, dow === 0 ? -6 : 1 - dow);
}

/** Qué rango pide cada consulta de la pantalla. Ver el encabezado. */
export function ventanasDeConsulta(hoy: string, desde: string, hasta: string) {
  const lunesActual = lunesDeLaSemana(hoy);
  return {
    /** Hoy inclusive = 30 días. */
    desdePatron: addDias(hoy, -(VENTANA_PATRON_DIAS - 1)),
    /** El déficit de encargadas mira esta semana y la siguiente. */
    lunesActual,
    domingoSiguiente: addDias(lunesActual, 13),
    /** Lo más atrás entre el filtro y las ventanas fijas que no lo respetan. */
    desdeAceptadas: [desde, addDias(hoy, -VENTANA_RACHA_DIAS), addDias(hoy, -VENTANA_EXCESO_DIAS)]
      .reduce((a, b) => (a < b ? a : b)),
    hastaAceptadas: hasta > hoy ? hasta : hoy,
    /** La ventana más vieja evaluada también necesita sus seis días previos. */
    desdeHoras: addDias(hoy, -(VENTANA_EXCESO_DIAS + 5)),
    desdeRacha: addDias(hoy, -VENTANA_RACHA_DIAS),
  };
}

// ── Qué devuelve ───────────────────────────────────────────────────────────

export type TipoIncidencia =
  | "auto_cierre"
  | "sin_salida"
  | "sin_retorno_almuerzo"
  | "salida_anticipada"
  | "patron_tardanzas"
  | "jornada_excedida_viva"
  | "jornada_excedida"
  | "racha_preventiva"
  | "racha_sin_descanso"
  | "deficit_encargadas"
  | "falta_injustificada"
  | "falta_justificada";

/** Los tipos que se sacan de la lista con un visto bueno (`incidencias_aceptadas.tipo`). */
export type TipoAceptable = "salida_anticipada" | "sin_retorno_almuerzo" | "racha_sin_descanso" | "jornada_excedida";

/** Las cuatro cajas del resumen. Solo agrupaciones que existen en los datos. */
export type Categoria = "faltas" | "marcaciones" | "patrones" | "otros";

/** El criterio de severidad que ya usaba la pantalla, sin tocar:
 * alta = exige acción sobre una persona puntual (falta, sin salida, patrón,
 * exceso vigente, racha consumada); media = confirma un hecho puntual del día o
 * es operativo de una sede; baja = ya resuelto, o preventivo que aún no es infracción. */
export type Severidad = "alta" | "media" | "baja";

export interface Aceptacion {
  nota: string | null;
  aceptadoPor: string;
  aceptadoAt: string;
  /** El número que se dio por bueno; null en los vistos buenos anteriores a la 0451. */
  valor: number | null;
}

export interface Incidencia {
  /** Única dentro de una misma lista. */
  clave: string;
  tipo: TipoIncidencia;
  /** null = incidencia de una sede, no de una persona. */
  personaId: string | null;
  nombre: string;
  sede: string;
  fecha: string;
  /** Qué pasó, en pocas palabras: «Salida anticipada». */
  titulo: string;
  /** El dato que lo mide, o null: «142 min», «5 en 30 días corridos». */
  detalle: string | null;
  /** El texto de una línea que mostraba la pantalla antes del rediseño. */
  texto: string;
  entrada: string | null;
  salida: string | null;
  aceptable?: TipoAceptable;
  /** El número que se estaría dando por bueno al aceptar (minutos, horas, días), o null. */
  valor: number | null;
  justificada?: boolean;
  motivoFalta?: string | null;
  severidad: Severidad;
  categoria: Categoria;
  /** Si ya tiene visto bueno vigente. La lista activa las oculta; el historial las muestra. */
  aceptacion?: Aceptacion;
  /** Hubo un visto bueno, pero sobre OTRO número (0451): una corrección cambió el
   * hecho después de aceptarlo. El aviso vuelve a la lista y esto dice qué se había aceptado. */
  aceptacionCaducada?: Aceptacion;
}

// ── Qué recibe (las filas tal como las devuelve la base) ───────────────────

interface PersonaEmbebida {
  nombres: string;
  apellidos: string;
  en_planilla?: boolean | null;
  tipo_vinculo?: string | null;
  practicante_modalidad?: string | null;
  /** Personal de dirección (0187): el D.S. 007-2002-TR art. 5 lo excluye de la jornada máxima. */
  personal_direccion?: boolean | null;
  estado?: string | null;
  sedes: { codigo: string } | null;
}
interface ConPersona {
  persona_id: string;
  personas: PersonaEmbebida | null;
}

export interface DatosDeteccion {
  hoy: string;
  jornadasRango: (ConPersona & {
    fecha: string; estado: string; entrada_ts: string | null; salida_final_ts: string | null;
    tiene_salida_no_retornada: boolean | null;
  })[];
  salidaTemprana: { persona_id: string; fecha: string; minutos_salida_temprana: number | null }[];
  tardanzas: (ConPersona & { fecha: string; entrada_ts: string | null })[];
  /** null = no se pudo comprobar cuáles fueron levantadas: el patrón se apaga
   * entero, porque contarlas igual reabriría un caso ya perdonado. */
  tardanzasLevantadas: { persona_id: string; fecha: string }[] | null;
  horasVentana: (ConPersona & { fecha: string; horas_trabajadas: number | string | null; estado: string })[];
  diasRacha: (ConPersona & { fecha: string })[];
  aceptadas: {
    persona_id: string; fecha: string; tipo: string;
    nota: string | null; aceptado_por: string; aceptado_at: string;
    /** numeric llega como número o como texto según el cliente. */
    valor?: number | string | null;
  }[];
  /** `tipo` es `sedes.tipo` (central, taller, tienda): decide si un administrador cuenta como líder. */
  sedes: { id: string; codigo: string; tipo?: string | null }[];
  /** Personas activas que PODRÍAN contar como líder de su sede. Quién cuenta de
   * verdad lo decide `cuentaEnCobertura` (packages/shared), no esta lista. */
  encargadas: { id: string; sede_base_id: string; rol: string | null; tipo_vinculo: string | null; es_encargada_piso: boolean }[];
  /** El EQUIPO de cada sede: quien está activo y marca (en planilla o practicante, sin
   * sueldo fijo) —la misma población que el Dashboard—. De aquí sale «¿a alguien de la
   * sede le tocaba trabajar ese día?» (`diaDeLaSedeDe`), que decide si un déficit de
   * líderes es real. NO es la lista de líderes (esa es `encargadas`): un día sin turnos
   * se reconoce mirando a TODA la sede, no solo a quien podría liderarla. Vacío = no se
   * sabe: el aviso sale como siempre. */
  equipo: { id: string; sede_base_id: string }[];
  metas: { sede_id: string; dia_semana: number; meta_encargadas: number }[];
  horarios: HorarioTramo[];
  turnos: (TurnoDia & { persona_id: string; fecha: string })[];
  faltas: { persona_id: string; nombre: string; sede: string; fecha: string; justificada: boolean; motivo: string | null }[];
  /** Cómo se lee el motivo de una falta justificada. */
  etiquetaMotivo: (motivo: string | null) => string;
}

function quien(p: ConPersona) {
  return {
    personaId: p.persona_id,
    nombre: `${p.personas?.nombres ?? ""} ${p.personas?.apellidos ?? ""}`.trim(),
    sede: p.personas?.sedes?.codigo ?? "?",
  };
}

/** Quien ya cesó no vuelve a aparecer en un aviso nuevo: la detección corre en
 * vivo (ver encabezado), así que sin este corte un patrón de sus últimos días
 * trabajados quedaría "por revisar" para siempre, sin nadie que pueda darlo
 * por resuelto. El historial de disciplina y de planilla sigue viendo a
 * quien cesó por su cuenta: esto solo afecta esta bandeja operativa. */
function estaActiva(p: ConPersona): boolean {
  return p.personas?.estado === "activo";
}

// ── La detección ───────────────────────────────────────────────────────────

export function detectarIncidencias(d: DatosDeteccion): Incidencia[] {
  const { hoy } = d;
  const out: Incidencia[] = [];
  const aceptacionPorClave = new Map(
    d.aceptadas.map((a) => [
      `${a.persona_id}|${a.fecha}|${a.tipo}`,
      {
        nota: a.nota, aceptadoPor: a.aceptado_por, aceptadoAt: a.aceptado_at,
        valor: a.valor === null || a.valor === undefined ? null : Number(a.valor),
      } satisfies Aceptacion,
    ]),
  );
  // Un visto bueno vale para el número que se aceptó (0451). Los anteriores a
  // esa migración no guardaron número y valen para cualquiera: reabrirlos
  // pediría revisar otra vez lo que alguien ya miró.
  const conAceptacion = (i: Omit<Incidencia, "clave" | "aceptacion" | "aceptacionCaducada">): Incidencia => {
    const a = i.aceptable && i.personaId
      ? aceptacionPorClave.get(`${i.personaId}|${i.fecha}|${i.aceptable}`)
      : undefined;
    const vigente = a !== undefined && (a.valor === null || i.valor === null || a.valor === i.valor);
    return {
      ...i,
      clave: `${i.tipo}|${i.personaId ?? i.sede}|${i.fecha}`,
      ...(a && vigente ? { aceptacion: a } : {}),
      ...(a && !vigente ? { aceptacionCaducada: a } : {}),
    };
  };

  // ── Cierres del día ─────────────────────────────────────────────────────
  // Un mismo día puede tener VARIAS incidencias a la vez (un auto-cierre en el
  // que además falta el retorno del almuerzo). Antes era un `else if` y solo se
  // veía la primera.
  const minutosPorClave = new Map<string, number>();
  for (const e of d.salidaTemprana) minutosPorClave.set(`${e.persona_id}|${e.fecha}`, e.minutos_salida_temprana ?? 0);

  for (const j of d.jornadasRango) {
    if (!estaActiva(j)) continue;
    const base = { ...quien(j), fecha: j.fecha, entrada: j.entrada_ts, salida: j.salida_final_ts, valor: null };
    if (j.estado === "auto_cerrada_pendiente") {
      out.push(conAceptacion({
        ...base, tipo: "auto_cierre", titulo: "Auto-cerrada", detalle: "salida puesta por el sistema",
        texto: "Auto-cerrada (revisar)", severidad: "media", categoria: "marcaciones",
      }));
    }
    if (j.fecha < hoy && j.estado === "abierta") {
      out.push(conAceptacion({
        ...base, tipo: "sin_salida", titulo: "Sin salida final", detalle: null,
        texto: "Sin salida final", severidad: "alta", categoria: "marcaciones",
      }));
    }
    if (j.fecha < hoy && j.tiene_salida_no_retornada) {
      // Se nombra el HECHO —falta una marca— y no una interpretación: el sistema
      // no sabe si se fue, si volvió sin marcar o si trabajó de corrido.
      out.push(conAceptacion({
        ...base, tipo: "sin_retorno_almuerzo", titulo: "Sin marca de retorno del almuerzo", detalle: null,
        texto: "Sin marca de retorno del almuerzo", aceptable: "sin_retorno_almuerzo",
        severidad: "media", categoria: "marcaciones",
      }));
    }
    const minutos = minutosPorClave.get(`${j.persona_id}|${j.fecha}`) ?? 0;
    if (minutos > 0) {
      out.push(conAceptacion({
        ...base, tipo: "salida_anticipada", titulo: "Salida anticipada", detalle: `${minutos} min`,
        texto: `Salida anticipada (${minutos} min)`, aceptable: "salida_anticipada", valor: minutos,
        severidad: "media", categoria: "marcaciones",
      }));
    }
  }

  // ── Patrón de tardanzas ─────────────────────────────────────────────────
  // Llegan ordenadas por fecha descendente: la primera de cada persona es la
  // más reciente. Solo quien está en_planilla (0413): a un practicante se le
  // mide la tardanza para Desempeño, pero no genera un aviso de fiscalización.
  if (d.tardanzasLevantadas !== null) {
    const levantadas = new Set(d.tardanzasLevantadas.map((t) => `${t.persona_id}|${t.fecha}`));
    const porPersona = new Map<string, { count: number; ultima: DatosDeteccion["tardanzas"][number] }>();
    for (const j of d.tardanzas) {
      if (levantadas.has(`${j.persona_id}|${j.fecha}`)) continue;
      if (j.personas?.en_planilla !== true) continue;
      if (!estaActiva(j)) continue;
      const prev = porPersona.get(j.persona_id);
      if (prev) prev.count++;
      else porPersona.set(j.persona_id, { count: 1, ultima: j });
    }
    for (const { count, ultima: j } of porPersona.values()) {
      if (count < UMBRAL_PATRON_TARDANZAS) continue;
      // «días corridos» y no «días»: el umbral del memo se cuenta por mes
      // calendario (RIT 19.2-b) y vive en Disciplina. Acá no se calcula ese
      // otro número: esta detección no conoce el corte del expediente.
      out.push(conAceptacion({
        ...quien(j), fecha: j.fecha, entrada: j.entrada_ts, salida: null,
        tipo: "patron_tardanzas", titulo: "Patrón de tardanzas",
        detalle: `${count} en ${VENTANA_PATRON_DIAS} días corridos`,
        texto: `Patrón de tardanzas (${count} en ${VENTANA_PATRON_DIAS} días corridos)`,
        valor: count, severidad: "alta", categoria: "patrones",
      }));
    }
  }

  // ── Exceso de jornada ───────────────────────────────────────────────────
  // 48 h es el MÁXIMO LEGAL (Const. art. 25), medido sobre cualquier ventana de
  // siete días consecutivos (Informe 027-2021-MTPE/14), no por semana de
  // calendario. Se mide contra 48 y no contra las 45 que CAYLA programa.
  // Los días auto-cerrados sin confirmar NO se sacan del cálculo (podría
  // esconder una sobrecarga real): se dice que el exceso se apoya en ellos (0284).
  const porPersonaHoras = new Map<string, { dias: { fecha: string; horas: number }[]; sinConfirmar: Set<string>; fila: ConPersona }>();
  for (const j of d.horasVentana) {
    if (!estaActiva(j)) continue;
    // Decisión de Felipe (2026-09-19): al personal de dirección no se le avisa el
    // exceso de 48 h, porque la ley lo excluye de la jornada máxima. Sigue en la
    // racha sin descanso, que es otra norma y que sí se le paga (0187 y 0280).
    if (j.personas?.personal_direccion === true) continue;
    const dia = { fecha: j.fecha, horas: Number(j.horas_trabajadas) || 0 };
    const pendiente = j.estado === "auto_cerrada_pendiente";
    const prev = porPersonaHoras.get(j.persona_id);
    if (prev) {
      prev.dias.push(dia);
      if (pendiente) prev.sinConfirmar.add(dia.fecha);
    } else {
      porPersonaHoras.set(j.persona_id, { dias: [dia], sinConfirmar: new Set(pendiente ? [dia.fecha] : []), fila: j });
    }
  }
  const apoyadoEnHoraSinConfirmar = (sinConfirmar: Set<string>, fin: string) => {
    for (let i = 0; i < 7; i++) if (sinConfirmar.has(addDias(fin, -i))) return true;
    return false;
  };
  for (const { dias, sinConfirmar, fila } of porPersonaHoras.values()) {
    // Una practicante tiene su propio tope (art. 44 Ley 28518): 30 h
    // preprofesional, 48 h profesional. null cae al máximo general.
    const maxLegal = maximoSemanalPracticante(fila.personas?.tipo_vinculo, fila.personas?.practicante_modalidad)
      ?? MAXIMO_LEGAL_SEMANAL;
    // Dos preguntas, dos ventanas: ¿se está pasando AHORA (todavía se puede
    // mover un turno)? y ¿se pasó ANTES y nadie lo vio?
    const viva = ventanaMasCargada(dias, addDias(hoy, -EXCESO_AUN_EVITABLE_DIAS), hoy);
    if (viva !== null && viva.horas > maxLegal) {
      const sinConfirmarTxt = apoyadoEnHoraSinConfirmar(sinConfirmar, viva.fin)
        ? " · incluye días cuya salida puso el sistema y falta confirmar"
        : "";
      out.push(conAceptacion({
        ...quien(fila), fecha: viva.fin, entrada: null, salida: null,
        tipo: "jornada_excedida_viva", titulo: "Jornada excedida",
        detalle: `${viva.horas.toFixed(1)} h en 7 días (máx. ${maxLegal})${sinConfirmarTxt}`,
        texto: `Jornada excedida: ${viva.horas.toFixed(1)} h en 7 días (máx. ${maxLegal})${sinConfirmarTxt}`,
        valor: Number(viva.horas.toFixed(1)), severidad: "alta", categoria: "patrones",
      }));
      // Con un exceso vivo no se agrega también el viejo: dirían lo mismo.
      continue;
    }
    const vieja = ventanaMasCargada(dias, addDias(hoy, -(VENTANA_EXCESO_DIAS - 1)), addDias(hoy, -(EXCESO_AUN_EVITABLE_DIAS + 1)));
    if (vieja === null || vieja.horas <= maxLegal) continue;
    // Se saca con visto bueno, no por antigüedad: la infracción ya ocurrió.
    out.push(conAceptacion({
      ...quien(fila), fecha: vieja.fin, entrada: null, salida: null,
      tipo: "jornada_excedida", titulo: "Jornada excedida (ya ocurrió)",
      detalle: `${vieja.horas.toFixed(1)} h en 7 días (máx. ${maxLegal})`,
      texto: `Jornada excedida (ya ocurrió): ${vieja.horas.toFixed(1)} h en 7 días (máx. ${maxLegal})`,
      aceptable: "jornada_excedida", valor: Number(vieja.horas.toFixed(1)),
      severidad: "media", categoria: "patrones",
    }));
  }

  // ── Días seguidos sin descanso ──────────────────────────────────────────
  // D. Leg. 713 art. 1: 24 h de descanso en cada semana, y la semana es un
  // CICLO DE 7 DÍAS (Informe 027-2021-MTPE/14). Cuándo avisar y cuándo el aviso
  // caduca vive en `avisoDeRacha`, con sus pruebas.
  const porPersonaDias = new Map<string, { fechas: string[]; fila: ConPersona }>();
  for (const j of d.diasRacha) {
    if (!estaActiva(j)) continue;
    const prev = porPersonaDias.get(j.persona_id);
    if (prev) prev.fechas.push(j.fecha);
    else porPersonaDias.set(j.persona_id, { fechas: [j.fecha], fila: j });
  }
  for (const { fechas, fila } of porPersonaDias.values()) {
    const aviso = avisoDeRacha(fechas, hoy);
    if (aviso === null) continue;
    // El de 7+ se saca con visto bueno. Si la racha sigue creciendo, `ultimo`
    // cambia y vuelve a salir: aceptar el día 7 no tapa el día 8.
    out.push(conAceptacion(
      aviso.excedida
        ? {
            ...quien(fila), fecha: aviso.ultimo, entrada: null, salida: null,
            tipo: "racha_sin_descanso", titulo: `${aviso.seguidos} días seguidos sin descanso`, detalle: null,
            texto: `${aviso.seguidos} días seguidos sin descanso semanal`,
            aceptable: "racha_sin_descanso", valor: aviso.seguidos, severidad: "alta", categoria: "patrones",
          }
        : {
            ...quien(fila), fecha: aviso.ultimo, entrada: null, salida: null,
            tipo: "racha_preventiva", titulo: `Lleva ${aviso.seguidos} días seguidos`, detalle: "el próximo le toca descansar",
            texto: `Lleva ${aviso.seguidos} días seguidos — el próximo le toca descansar`,
            valor: aviso.seguidos, severidad: "baja", categoria: "patrones",
          },
    ));
  }

  // ── Déficit de encargadas ───────────────────────────────────────────────
  // Esta semana Y la siguiente: con el horario de la próxima ya asignado, el
  // aviso llega mientras todavía se puede reprogramar (auditoría 2026-09-13).
  // «¿Le toca trabajar?» se pregunta a jornada-esperada, nunca se reescribe.
  //
  // Un día en que A NADIE de la sede le toca trabajar no le falta ningún líder que
  // pudiera venir: lo que sobra es la meta («1 líder el domingo» en una sede que ese
  // día no abre), y eso lo dicen Turnos y el Dashboard, que es donde se arregla.
  // Central es el caso que lo destapó (2026-09-20): trabaja de lunes a sábado, el
  // domingo es opcional, y la bandeja abría «Déficit de líderes (0/1)» todos los
  // domingos —dos por visita— por una falta que ninguna asistencia podía arreglar.
  // Solo se calla con una respuesta REAL de descanso (`no_trabaja`): con
  // `sin_horario` —nadie tiene horario cargado, un tramo venció, la sede es nueva—
  // no se sabe, y ahí el aviso sale como siempre. Y con `trabaja` (a alguien le toca
  // pero no hay líder: una tienda con operativas y sin líder) es un déficit de verdad.
  //
  // FERIADOS: este aviso no los conoce, y no debe (2026-09-20). Es una alarma de
  // PLANEACIÓN —pregunta si el horario cubre a un líder ese día, esta semana y la próxima—,
  // y en un feriado con horario base contesta «cubierto», que es la dirección segura. La
  // falsa alarma de feriado nace donde se ACUSA una ausencia el mismo día (el Dashboard y la
  // Hoja de sede: `esFeriadoSinTurno`), no donde se revisa un horario. Enseñarle feriados
  // aquí solo lo haría callar más — y este aviso existe justo para reprogramar a tiempo.
  const codigoPorSede = new Map(d.sedes.map((s) => [s.id, s.codigo]));
  const tipoPorSede = new Map(d.sedes.map((s) => [s.id, s.tipo ?? null]));
  const turnoPorClave = new Map(d.turnos.map((t) => [`${t.persona_id}|${t.fecha}`, t as TurnoDia]));
  const horariosPorPersona = new Map<string, HorarioTramo[]>();
  for (const h of d.horarios) {
    const arr = horariosPorPersona.get(h.persona_id) ?? [];
    arr.push(h);
    horariosPorPersona.set(h.persona_id, arr);
  }
  const equipoPorSede = new Map<string, string[]>();
  for (const p of d.equipo) {
    const arr = equipoPorSede.get(p.sede_base_id) ?? [];
    arr.push(p.id);
    equipoPorSede.set(p.sede_base_id, arr);
  }
  const tramosDe = (personaId: string) => horariosPorPersona.get(personaId) ?? [];
  const trabajaEseDia = (personaId: string, fecha: string) =>
    esperadoDelDia(fecha, turnoPorClave.get(`${personaId}|${fecha}`) ?? null, horarioVigente(tramosDe(personaId), fecha)).trabaja;
  const lunesActual = lunesDeLaSemana(hoy);
  for (let i = 0; i < 14; i++) {
    const dia = addDias(lunesActual, i);
    const proximaSemana = i >= 7;
    const dow = diaSemanaNum(dia);
    for (const m of d.metas) {
      if (m.dia_semana !== dow) continue;
      // Misma definición que el Dashboard, Turnos y Reporte de sede: en Central
      // manda un administrador; en una tienda solo cuenta quien es líder o
      // lleva la marca de piso. Tener la propia aquí hacía que Central saliera
      // «0 de 1» todos los días.
      const tipoSede = tipoPorSede.get(m.sede_id) ?? null;
      const cubiertas = d.encargadas.filter((e) =>
        e.sede_base_id === m.sede_id
        && cuentaEnCobertura(
          { rol: e.rol, tipoVinculo: e.tipo_vinculo, esEncargadaPiso: e.es_encargada_piso, areaOperativa: false },
          tipoSede,
        ).lider
        && trabajaEseDia(e.id, dia)).length;
      if (cubiertas >= m.meta_encargadas) continue;
      // Solo se pregunta cuando ya habría aviso: es la excepción, no el camino común.
      // Y solo con `cubiertas === 0`: un líder que SÍ trabaja ese día prueba que la
      // sede abre, aunque no esté en `equipo` (un líder con sueldo fijo no marca y el
      // equipo no lo lista). Con meta 2 y un solo líder trabajando, callar diría «hoy
      // no abre» sobre una sede que tiene a alguien adentro y le falta el segundo.
      //
      // COSTO CONOCIDO (revisión del 2026-09-20), igual para toda sede: una tienda que SÍ
      // debía abrir ese día, con meta, cuyo horario base no lo incluye y a la que nadie le
      // armó turnos (ni siquiera la semana siguiente, donde este aviso servía justo para
      // reprogramar), ya no avisa aquí. La red que queda es el ámbar «Meta sin turnos» del
      // Dashboard —solo el mismo día— y el rojo de Turnos. Se aceptó a propósito: no se
      // distingue una meta que sobra (Central el domingo) de unos turnos que faltan, y
      // hacer una excepción por tipo de sede sería un caso especial más.
      if (cubiertas === 0 && diaDeLaSedeDe(
        equipoPorSede.get(m.sede_id) ?? [], dia,
        (id) => turnoPorClave.get(`${id}|${dia}`) ?? null, tramosDe,
      ) === "no_trabaja") continue;
      const codigo = codigoPorSede.get(m.sede_id) ?? "?";
      const sufijo = proximaSemana ? " · próxima semana, todavía se puede reprogramar" : "";
      out.push(conAceptacion({
        personaId: null, nombre: `Sede ${codigo}`, sede: codigo, fecha: dia, entrada: null, salida: null,
        tipo: "deficit_encargadas", titulo: "Déficit de líderes",
        detalle: `${cubiertas} de ${m.meta_encargadas}${proximaSemana ? " · próxima semana" : ""}`,
        texto: `Déficit de líderes (${cubiertas}/${m.meta_encargadas})${sufijo}`,
        valor: cubiertas, severidad: "media", categoria: "otros",
      }));
    }
  }

  // ── Faltas (fn_faltas, ya con alcance por rol) ──────────────────────────
  for (const f of d.faltas) {
    const motivo = d.etiquetaMotivo(f.motivo);
    out.push(conAceptacion({
      personaId: f.persona_id, nombre: f.nombre, sede: f.sede, fecha: f.fecha, entrada: null, salida: null,
      tipo: f.justificada ? "falta_justificada" : "falta_injustificada",
      titulo: f.justificada ? "Falta justificada" : "Falta injustificada",
      detalle: f.justificada ? motivo : null,
      texto: f.justificada ? `Falta justificada · ${motivo}` : "Falta injustificada",
      valor: null, justificada: f.justificada, motivoFalta: f.motivo,
      severidad: f.justificada ? "baja" : "alta", categoria: "faltas",
    }));
  }

  return out;
}

// ── Estado y orden (lo que la pantalla necesita para ser una bandeja) ──────

/**
 * En qué punto está una incidencia. No hay una columna de estado en la base, y
 * no se agrega a propósito: la detección corre en vivo, así que una incidencia
 * cuya causa se corrigió simplemente deja de existir. El estado se DEDUCE de
 * lo que sí se guardó — una justificación o un visto bueno.
 *
 * - resuelta: ya tiene una decisión (falta justificada, o visto bueno vigente).
 * - preventivo: todavía no es infracción (lleva 6 días seguidos).
 * - pendiente: todo lo demás.
 *
 * El contador «por revisar» suma pendientes y preventivos (decisión de Felipe,
 * 2026-09-15): un preventivo también pide una acción, mover un turno.
 */
export type EstadoIncidencia = "pendiente" | "preventivo" | "resuelta";

export function estadoDe(i: Incidencia): EstadoIncidencia {
  if (i.tipo === "falta_justificada" || i.aceptacion) return "resuelta";
  if (i.tipo === "racha_preventiva") return "preventivo";
  return "pendiente";
}

const RANGO_SEVERIDAD: Record<Severidad, number> = { alta: 0, media: 1, baja: 2 };

/**
 * Severidad → fecha más reciente → persona → clave (decisión de Felipe,
 * 2026-09-15). Usa la severidad que ya existía; no inventa un puntaje de
 * gravedad. La clave cierra como ancla: dos cargas dan siempre el mismo orden.
 */
export function compararIncidencias(a: Incidencia, b: Incidencia): number {
  return RANGO_SEVERIDAD[a.severidad] - RANGO_SEVERIDAD[b.severidad]
    || (a.fecha < b.fecha ? 1 : a.fecha > b.fecha ? -1 : 0)
    || a.nombre.localeCompare(b.nombre, "es")
    || (a.clave < b.clave ? -1 : a.clave > b.clave ? 1 : 0);
}

// ── Qué no se pudo comprobar ───────────────────────────────────────────────
//
// QUÉ PROMETE. Que la pantalla distinga «no hay nada» de «no pude mirar». Un
// «Todo revisado» sobre una consulta que falló es una AFIRMACIÓN falsa: dice
// que se comprobó y no se comprobó (ver `lo-que-no-se-pudo.ts`).
//
// DURA o SUAVE. Es dura la fuente sin la cual no se puede afirmar que no hay
// nada de ese tipo: si `fn_faltas` falla, no se puede decir «sin faltas». Esa
// categoría pasa a «sin comprobar» y «Todo revisado» deja de mostrarse. Es suave
// la que solo empobrece la pantalla (un nombre, un aviso aparte): se avisa, pero
// el resto se puede seguir revisando.
//
// Por qué no bloquear todo ante cualquier error: una falla de `contratos` (solo
// pinta el aviso de convenios de prácticas) dejaría a la líder de equipo sin
// poder revisar faltas.
//
// SE ROMPE SI alguien agrega una consulta a `cargar()` y no la declara acá: se
// vuelve a tirar su `error` sin que nada lo note. Por eso la lista vive aparte
// y tiene su prueba.

export type FuenteDeIncidencias =
  | "faltas" | "salidas" | "excesos" | "rachas"
  | "vistos_buenos" | "revisiones" | "convenios" | "nombres" | "motivos" | "equipo";

const FUENTES: Record<FuenteDeIncidencias, { que: string; categoria: Categoria | null; dura: boolean }> = {
  faltas: { que: "las faltas", categoria: "faltas", dura: true },
  salidas: { que: "las salidas anticipadas", categoria: "marcaciones", dura: true },
  excesos: { que: "los excesos de jornada", categoria: "patrones", dura: true },
  rachas: { que: "los días seguidos sin descanso", categoria: "patrones", dura: true },
  vistos_buenos: { que: "los vistos buenos ya dados (avisos ya revisados pueden volver a salir y el historial no se muestra)", categoria: null, dura: false },
  revisiones: { que: "los días que tu equipo pidió revisar", categoria: null, dura: false },
  convenios: { que: "los convenios de prácticas cerca del tope de 12 meses", categoria: null, dura: false },
  nombres: { que: "los nombres de quienes dieron un visto bueno", categoria: null, dura: false },
  motivos: { que: "los nombres de los motivos de justificación", categoria: null, dura: false },
  // Suave y sin categoría: si el equipo no llega, el déficit de líderes vuelve a avisar
  // TAMBIÉN los días en que la sede no trabaja (más avisos, nunca menos), así que «todo
  // revisado» sigue siendo cierto y ninguna caja queda sin comprobar.
  equipo: { que: "qué sedes tenían turno cada día (el déficit de líderes puede avisar también un día en que nadie de la sede trabajaba)", categoria: null, dura: false },
};

export interface CoberturaDeCarga {
  /** Todo lo que no se pudo traer, en el orden en que se declaró. */
  faltantes: string[];
  /** Solo lo que impide afirmar «no hay nada» (subconjunto de `faltantes`). */
  duras: string[];
  /** Las cajas del resumen que no se pueden contar. */
  categoriasSinComprobar: ReadonlySet<Categoria>;
}

export const CARGA_COMPLETA: CoberturaDeCarga = { faltantes: [], duras: [], categoriasSinComprobar: new Set() };

/** `errores` = el `error` que devolvió cada consulta (null/undefined si contestó). */
export function coberturaDeCarga(errores: Partial<Record<FuenteDeIncidencias, unknown>>): CoberturaDeCarga {
  const fuentes = (Object.keys(FUENTES) as FuenteDeIncidencias[]).filter((f) => Boolean(errores[f]));
  if (fuentes.length === 0) return CARGA_COMPLETA;
  const faltantes = loQueNoSePudo(fuentes.map((f) => ({ error: errores[f], que: FUENTES[f].que })));
  return {
    faltantes,
    duras: fuentes.filter((f) => FUENTES[f].dura).map((f) => FUENTES[f].que),
    categoriasSinComprobar: new Set(
      fuentes.map((f) => FUENTES[f].categoria).filter((c): c is Categoria => c !== null),
    ),
  };
}

/** «a», «a y b», «a, b y c». */
export function enFrase(items: readonly string[]): string {
  if (items.length <= 1) return items[0] ?? "";
  return `${items.slice(0, -1).join(", ")} y ${items[items.length - 1]}`;
}

/** Los tipos que se pueden marcar revisados en lote: solo afirman «lo vi», nada
 * sobre el día de nadie. Salida anticipada y almuerzo afirman un hecho puntual
 * y se revisan uno por uno. */
export const TIPOS_EN_LOTE: ReadonlySet<TipoAceptable> = new Set(["racha_sin_descanso", "jornada_excedida"]);
