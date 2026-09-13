"use client";

import { Suspense, useCallback, useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import Link from "next/link";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { Cargando, EsqueletoSecciones, SinDatos } from "@/components/cargando";
import { Boton } from "@/components/ui/boton";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { AreaTexto } from "@/components/ui/area-texto";
import { Modal } from "@/components/ui/modal";
import { Fila as FilaTabla, Tabla, TablaEncabezado, Th } from "@/components/ui/tabla";
import { traerTodo } from "@/lib/admin/traer-todo";
import { esperadoDelDia, horarioVigente, type HorarioTramo, type TurnoDia } from "@/lib/admin/jornada-esperada";
import {
  TZ_LIMA, hoyLima, MAXIMO_LEGAL_SEMANAL,
  MAXIMO_DIAS_SIN_DESCANSO, avisoDeRacha, ventanaMasCargada,
  maximoSemanalPracticante,
} from "@cayla-dynamic/shared";

function haceDias(n: number): string {
  const d = new Date(); d.setDate(d.getDate() - n);
  return new Intl.DateTimeFormat("en-CA", { timeZone: TZ_LIMA }).format(d);
}
// ── Semana actual (lunes–domingo), mismo criterio que admin/turnos ──────────
function parseISO(iso: string): Date {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d));
}
function toISO(dt: Date): string { return dt.toISOString().slice(0, 10); }
function addDias(iso: string, n: number): string {
  const d = parseISO(iso); d.setUTCDate(d.getUTCDate() + n); return toISO(d);
}
function diaSemanaNum(iso: string): number { return parseISO(iso).getUTCDay(); } // 0=domingo…6=sábado
function lunesDeLaSemana(iso: string): string {
  const dow = diaSemanaNum(iso);
  return addDias(iso, dow === 0 ? -6 : 1 - dow);
}
function fechaLarga(f: string): string {
  const [y, m, d] = f.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { timeZone: TZ_LIMA, weekday: "short", day: "2-digit", month: "short" }).format(new Date(Date.UTC(y, m - 1, d, 12)));
}
function horaLima(ts: string | null): string {
  if (!ts) return "—";
  return new Intl.DateTimeFormat("es-PE", { timeZone: TZ_LIMA, hour: "2-digit", minute: "2-digit", hour12: true }).format(new Date(ts));
}
function fechaHoraLima(ts: string): string {
  return new Intl.DateTimeFormat("es-PE", {
    timeZone: TZ_LIMA, day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit", hour12: true,
  }).format(new Date(ts));
}

interface Fila {
  personaId: string | null; // null = incidencia de sede (no de una persona puntual)
  nombre: string;
  sede: string;
  fecha: string;
  tipo: string;
  entrada: string | null;
  salida: string | null;
  aceptable?: string; // clave de tipo (p. ej. 'salida_anticipada') si se puede "Aceptar"
  esFalta?: boolean;
  justificada?: boolean;
  motivoFalta?: string | null;
  severidad: "alta" | "media" | "baja";
}

// Triage visual: mismo criterio de color que ya usa esta pantalla para el
// desfase del reloj (rojo = grave, ámbar = aviso menor) — no un esquema nuevo.
// "Alta" es lo que exige acción sobre una persona puntual (falta, sin salida,
// patrón de tardanzas, exceso de jornada vigente, racha ya consumada). "Media"
// es lo que pide una confirmación de un hecho puntual del día (auto-cierre,
// almuerzo sin marcar, salida anticipada) o es operativo y no de una persona
// (déficit de encargadas). "Baja" es lo que ya quedó resuelto o es solo un
// aviso preventivo que todavía no es infracción.
const COLOR_SEVERIDAD: Record<Fila["severidad"], string> = {
  alta: "text-rojo",
  media: "text-ambar",
  baja: "text-taupe",
};

// Tipos "aceptable" que son un simple acuse de "lo vi" (no afirman un hecho
// nuevo sobre el día de una persona) — los únicos que se pueden revisar en
// lote. `sin_retorno_almuerzo` afirma "trabajó de corrido" y `salida_anticipada`
// afirma "está bien que se fuera antes": dos hechos que solo puede confirmar
// quien revisó CADA día, y agruparlos en un botón de "aprobar todo" haría que
// la pantalla firmara por Felipe algo que no vio. Racha y exceso "ya ocurrido"
// son distintos: la infracción ya pasó y no se puede deshacer, así que
// "Revisado" no afirma nada — solo dice que no se le escapó a nadie.
const LOTEABLES = new Set(["racha_sin_descanso", "jornada_excedida"]);

// Motivos del desplegable de justificación (mismo enum que fn_set_justificacion).
const MOTIVOS: { valor: string; label: string }[] = [
  { valor: "permiso_concedido", label: "Permiso concedido" },
  { valor: "cumpleanos", label: "Cumpleaños" },
  { valor: "estudios", label: "Estudios" },
  { valor: "descanso_medico", label: "Descanso médico" },
  { valor: "otro", label: "Otro" },
];
interface RevisionPedida {
  id: string; persona_id: string; nombre: string; sede: string;
  fecha: string; comentario: string; pedida_at: string;
}

// Fila de fn_contratos_tablero (0336) que interesa acá: una practicante cuyo
// convenio ya superó, o está por superar, el tope legal de 12 meses.
interface PracticanteSobreTope {
  persona_id: string; persona: string; sede: string;
  estado: string; dias_restantes: number | null;
}

const MOTIVO_LABEL = (m: string | null | undefined) => MOTIVOS.find((x) => x.valor === m)?.label ?? m ?? "";

// Qué dice el botón de visto bueno en cada incidencia. El texto no es decoración:
// quien lo pulsa tiene que saber QUÉ está afirmando, porque en el caso del almuerzo
// esa afirmación decide cuántas horas se pagan.
const ACEPTAR_UI: Record<string, { boton: string; ayuda: string }> = {
  salida_anticipada: {
    boton: "Aceptar",
    ayuda: "Dar por buena esta salida anticipada y quitarla de la lista.",
  },
  sin_retorno_almuerzo: {
    boton: "Trabajó de corrido",
    ayuda:
      "Confirmar que no tomó refrigerio y siguió trabajando: el día se paga tal como está calculado. " +
      "Si sí almorzó, no uses este botón — registra en Correcciones la hora en que salió y la hora en que " +
      "volvió, y las horas se recalculan solas.",
  },
  racha_sin_descanso: {
    boton: "Revisado",
    ayuda:
      "Dejar constancia de que viste esta racha y la sacaste de la lista. No la borra: queda registrado " +
      "quién la revisó y cuándo. La racha ya pasó y no se puede deshacer — esto solo dice que no se te escapó. " +
      "Si la racha sigue creciendo, el aviso vuelve a salir mañana con el día nuevo.",
  },
  // Mismo trato que la racha, y por la misma razón: la infracción ya ocurrió, no
  // se puede deshacer, y desaparecer sola por antigüedad sería borrarla sin que
  // nadie la mirara. Solo lo lleva la variante «ya ocurrió»: el exceso VIVO pide
  // mover un turno, y darle un botón de «visto» sería ofrecer callar el aviso en
  // vez de atenderlo.
  jornada_excedida: {
    boton: "Revisado",
    ayuda:
      "Dejar constancia de que viste este exceso y sacarlo de la lista. No lo borra: queda registrado quién " +
      "lo revisó y cuándo. El exceso ya ocurrió y no se puede deshacer — esto solo dice que no se te escapó. " +
      "Pasar de 48 h no se arregla pagando el recargo: es un tope, y el recargo ya se pagó aparte.",
  },
};
const ACEPTAR_BOTON = (t: string | undefined) => (t && ACEPTAR_UI[t]?.boton) || "Aceptar";
const ACEPTAR_AYUDA = (t: string | undefined) =>
  (t && ACEPTAR_UI[t]?.ayuda) || "Dar por buena esta incidencia y quitarla de la lista.";

// Etiqueta legible de cada tipo aceptable, para el historial (distinta del
// texto del botón: el botón dice qué vas a afirmar, esto describe qué fue).
const TIPO_LABEL: Record<string, string> = {
  salida_anticipada: "Salida anticipada",
  sin_retorno_almuerzo: "Sin retorno de almuerzo (trabajó de corrido)",
  racha_sin_descanso: "Racha sin descanso",
  jornada_excedida: "Jornada excedida (ya ocurrió)",
};

// Una incidencia aceptada, con su rastro completo. `incidencias_aceptadas` ya
// guarda quién y cuándo desde que existe (0052) — lo que faltaba era una
// pantalla que lo mostrara. Sin esto, saber "quién aceptó esto y por qué"
// exigía entrar a Supabase a mano.
interface HistorialItem {
  personaId: string;
  nombre: string;
  sede: string;
  fecha: string;
  tipo: string;
  nota: string | null;
  aceptadoPor: string;
  aceptadoAt: string;
}

const HOY = hoyLima();
// Patrón de tardanzas: ventana fija de 30 días desde hoy (independiente del
// filtro Desde/Hasta que el admin puede mover) — es sobre el estado disciplinario
// ACTUAL de la persona, no sobre lo que el admin esté mirando en un momento dado.
// El número no sale de una ley (el marco peruano no fija una cifra: exige
// reiteración + sanciones progresivas documentadas antes de poder despedir por
// esto — D.S. 003-97-TR art. 25 + jurisprudencia de la Corte Suprema), es el
// umbral que Felipe eligió para que Dynamic avise y arranque ese proceso.
const VENTANA_PATRON_DIAS = 30;
const UMBRAL_PATRON_TARDANZAS = 3;
// Exceso de jornada: cuántos días hacia atrás se buscan ventanas de 7 días que
// pasen de 48 h. Antes eran 7 —solo ventanas que TERMINABAN en la última
// semana— y eso hacía desaparecer excesos reales sin que nadie los viera nunca.
// El caso que lo destapó: 58.96 h en 7 días seguidos (31 jul → 6 ago 2026), el
// exceso más grande del periodo, invisible en esta pantalla desde el 13 de
// agosto porque su ventana había terminado hacía más de 7 días.
//
// 30 días es la misma ventana que ya usa el patrón de tardanzas, y cubre de
// sobra el periodo de planilla (29 → 28) que es donde se cierra la cuenta.
const VENTANA_EXCESO_DIAS = 30;
// A partir de cuántos días atrás el exceso deja de ser evitable y pasa a ser
// solo documentable. Siete: mientras la ventana toque la semana en curso,
// todavía se puede mover un turno y que no siga creciendo.
const EXCESO_AUN_EVITABLE_DIAS = 6;
// Cuántos días de marcaje se traen para medir la racha en curso. Tres semanas
// alcanzan: la racha más larga medida en CAYLA fue de 20 días. Tiene nombre
// porque lo usan DOS consultas —los días marcados y los vistos buenos ya
// dados— y si se separan, un aviso que diste por revisado reaparece.
const VENTANA_RACHA_DIAS = 20;

function IncidenciasContenido() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const personaFiltro = searchParams.get("persona");
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;
  const [desde, setDesde] = useState(haceDias(30));
  const [hasta, setHasta] = useState(HOY);
  // Resumen | Detalle: qué tan literal se muestra la lista de abajo. Arranca en
  // Resumen a propósito — la primera pregunta al abrir esta pantalla es "¿cómo
  // estamos?", no "dame cada fila"; el detalle completo (idéntico al de antes
  // de este toggle) sigue a un clic.
  const [vistaModo, setVistaModo] = useState<"resumen" | "detalle">("resumen");
  const [filas, setFilas] = useState<Fila[]>([]);
  const [codigoPorSedeId, setCodigoPorSedeId] = useState<Map<string, string>>(new Map());
  const [cargando, setCargando] = useState(true);
  // DOS estados de error, y la distinción no es cosmética. Antes había uno solo,
  // y el banner que lo pintaba decía «No se pudieron cargar las incidencias»
  // pasara lo que pasara — así que un rechazo del servidor al GUARDAR salía con
  // el texto de un fallo de carga, y encima detrás del modal, que es `fixed
  // inset-0`. Quien pulsaba «Justificar» con motivo «Descanso médico» no veía
  // nada: el servidor lo rechaza a propósito, con un mensaje escrito para
  // enseñar («regístralo en Ausencias con documento»), y ese mensaje no llegaba
  // a nadie. El error de una acción se muestra DONDE se hizo la acción.
  const [error, setError] = useState<string | null>(null);
  const [errorAccion, setErrorAccion] = useState<string | null>(null);
  // Aviso parcial: la consulta de tardanzas levantadas falló. Sin ella no se
  // puede distinguir una tardanza perdonada de una real, así que "patrón de
  // tardanzas" se apaga entero mientras dure — y se dice, para que no se lea
  // como "todo en orden" cuando en realidad no se pudo comprobar.
  const [avisoLevantadas, setAvisoLevantadas] = useState<string | null>(null);

  // Lo que la gente pidió revisar desde «Lo mío» (0257). Va PRIMERO en esta
  // pantalla y no al final: es la única lista de acá que no la generó el
  // sistema mirando datos, sino una persona que sabe qué pasó ese día.
  const [revisiones, setRevisiones] = useState<RevisionPedida[]>([]);
  const [respuestas, setRespuestas] = useState<Record<string, string>>({});
  const [atendiendo, setAtendiendo] = useState<string | null>(null);
  const [practicantesSobreTope, setPracticantesSobreTope] = useState<PracticanteSobreTope[]>([]);

  // Historial de incidencias ya aceptadas (hallazgo: el rastro ya existía en
  // la base desde la 0052 — quién, cuándo, con qué nota — y esta pantalla
  // nunca lo mostraba. Colapsado por defecto: no compite con lo urgente.
  const [historial, setHistorial] = useState<HistorialItem[]>([]);
  const [mostrarHistorial, setMostrarHistorial] = useState(false);
  const [quitando, setQuitando] = useState<string | null>(null);

  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    setCargando(true);

    const desdePatron = haceDias(VENTANA_PATRON_DIAS - 1); // hoy inclusive = 30 días
    const lunesActual = lunesDeLaSemana(HOY);
    const domingoActual = addDias(lunesActual, 6);

    const [
      { data, error: errData },
      { data: extraData },
      { data: tardias, error: errTardias },
      { data: sedesData, error: errSedes },
      { data: encargadasData, error: errEnc },
      { data: metasData, error: errMetas },
      { data: horariosData, error: errHorarios },
      { data: turnosData, error: errTurnos },
      { data: aceptadasData },
      { data: personasData },
      { data: faltasData },
      { data: revisionesData },
      { data: levTardData, error: errLevTard },
      { data: horasSemanaData },
      { data: diasRachaData },
      { data: contratosData },
    ] = await Promise.all([
      // Las dos consultas a jornadas van por lotes: PostgREST cortaba en 1000
      // filas sin avisar, así que incidencias reales dejaban de listarse — y la
      // del patrón de tardanzas barre desde `desdePatron` hasta hoy, que es el
      // rango más ancho de esta pantalla.
      traerTodo<any>((ini, fin) =>
        supabase
          .from("jornadas")
          .select("persona_id, fecha, estado, entrada_ts, salida_final_ts, tiene_salida_no_retornada, personas:persona_id(nombres, apellidos, sedes:sede_base_id(codigo))")
          .gte("fecha", desde).lte("fecha", hasta)
          .order("fecha", { ascending: false })
          .order("persona_id")
          .range(ini, fin),
      ),
      supabase.rpc("fn_jornadas_extra", { p_desde: desde, p_hasta: hasta }),
      traerTodo<any>((ini, fin) =>
        supabase
          .from("jornadas")
          // `en_planilla` viaja para filtrar el patrón automático más abajo (0413):
          // desde que un practicante también acumula minutos_tarde (informativo,
          // para Desempeño), este "patrón" —que sí convierte el número en un aviso
          // de "incidencia alta" sin que nadie lo pida— se queda exclusivo de quien
          // está en_planilla. Un RxH nunca llega hasta acá: sigue sin minutos_tarde.
          .select("persona_id, fecha, entrada_ts, personas:persona_id(nombres, apellidos, en_planilla, sedes:sede_base_id(codigo))")
          .gte("fecha", desdePatron).lte("fecha", HOY)
          .gt("minutos_tarde", 0)
          .order("fecha", { ascending: false })
          .order("persona_id")
          .range(ini, fin),
      ),
      // Déficit de encargadas: mira la semana actual (lunes–domingo), no el filtro
      // Desde/Hasta — es sobre la cobertura planeada de AHORA, no un rango histórico.
      supabase.from("sedes").select("id, codigo"),
      supabase.from("personas").select("id, sede_base_id").eq("rol", "supervisor_sede").eq("estado", "activo"),
      supabase.from("metas_cobertura").select("sede_id, dia_semana, meta_encargadas").gt("meta_encargadas", 0),
      supabase.from("horarios_asignados").select("persona_id, hora_entrada, hora_salida, dias_laborables, horario_por_dia, almuerzo_min_minutos, vigente_desde, vigente_hasta").lte("vigente_desde", domingoActual).or(`vigente_hasta.is.null,vigente_hasta.gte.${lunesActual}`),
      supabase.from("turnos").select("persona_id, fecha, hora_entrada, hora_salida, es_descanso").gte("fecha", lunesActual).lte("fecha", domingoActual),
      // Incidencias ya aceptadas (visto bueno): para no volver a mostrarlas.
      // Se pide desde el filtro O desde la ventana fija más profunda, lo que sea
      // más atrás: los avisos de racha y de exceso NO respetan Desde/Hasta —se
      // miden sobre ventanas fijas—, así que con el filtro estrecho su aceptación
      // no se cargaría y el aviso que ya diste por revisado volvería a aparecer
      // solo por haber movido una fecha.
      //
      // El `min` de las tres es a propósito y no un adorno: cuando la 0185 trajo
      // el exceso «ya ocurrió» con 30 días de ventana, esta línea seguía mirando
      // los 20 de la racha y un exceso revisado hace tres semanas reaparecía.
      // Columnas ampliadas (nota, aceptado_por, aceptado_at) para el historial:
      // el rastro ya se escribía desde la 0052, esta pantalla solo no lo leía.
      supabase.from("incidencias_aceptadas")
        .select("persona_id, fecha, tipo, nota, aceptado_por, aceptado_at, personas:persona_id(nombres, apellidos, sedes:sede_base_id(codigo))")
        .gte("fecha", [desde, haceDias(VENTANA_RACHA_DIAS), haceDias(VENTANA_EXCESO_DIAS)]
          .reduce((a, b) => (a < b ? a : b)))
        .lte("fecha", hasta > HOY ? hasta : HOY)
        .order("aceptado_at", { ascending: false }),
      // Nombres para resolver "aceptado por" en el historial de arriba. Mismo
      // patrón que ya usa admin/correcciones (`nombrePorId`): una lista chica
      // de personas, resuelta en el cliente, en vez de un segundo embed de
      // `personas` sobre la misma tabla en la misma consulta.
      supabase.from("personas").select("id, nombres, apellidos"),
      // Faltas del rango (le tocaba y no marcó). Falla suave: si no llega, no se muestran.
      supabase.rpc("fn_faltas", { p_desde: desde, p_hasta: hasta }),
      // Pendientes de la 0257. Falla suave: mientras la migración no esté
      // pegada, PostgREST devuelve error, `data` viene null y la sección
      // simplemente no aparece. El resto de Incidencias no se entera.
      supabase.rpc("fn_revisiones_pedidas", { p_solo_pendientes: true }),
      // Tardanzas levantadas (perdonadas): no cuentan para el patrón. Ventana del patrón.
      // Falla DURA para el aviso que depende de ella (no para el resto de la
      // pantalla): si esta consulta no llega, no hay forma de saber qué
      // tardanza ya fue perdonada, y mostrar "patrón" igual reabriría un caso
      // ya resuelto — el falso positivo que este repositorio nombra como su
      // peor error. Se apaga solo ESE aviso más abajo; ver `errLevTard`.
      supabase.from("tardanzas_justificadas").select("persona_id, fecha").gte("fecha", desdePatron).lte("fecha", HOY),
      // Horas para el tope de jornada. NO se piden por semana de calendario: el
      // tope de 48 h se mide sobre CUALQUIER ventana de siete días consecutivos
      // (Informe 027-2021-MTPE/14), y para evaluar una ventana que termina hoy
      // hacen falta los seis días anteriores.
      //
      // El rango cubre la ventana de aviso (VENTANA_EXCESO_DIAS) MÁS seis días
      // de arrastre, porque la ventana más vieja que se evalúa también necesita
      // sus seis días previos. Antes se pedían 20 días y se evaluaban 7: los
      // otros 13 se descargaban para nada.
      traerTodo<any>((ini, fin) =>
        supabase
          .from("jornadas")
          // CAMBIO 0284 — `estado` viaja para poder decir cuándo el exceso se
          // apoya en una hora que puso el sistema y nadie confirmó.
          // `tipo_vinculo, practicante_modalidad` viajan para el tope de una
          // practicante (art. 44 Ley 28518: 30 h preprofesional, 48 h
          // profesional) — antes esta pantalla medía a TODO el mundo contra
          // las 48 h del art. 25, así que una preprofesional podía llegar a
          // 47 h sin que nada avisara, seis por encima de su propio máximo.
          .select("persona_id, fecha, horas_trabajadas, estado, personas:persona_id(nombres, apellidos, tipo_vinculo, practicante_modalidad, sedes:sede_base_id(codigo))")
          .gte("fecha", haceDias(VENTANA_EXCESO_DIAS + 5)).lte("fecha", HOY)
          .gt("horas_trabajadas", 0)
          .order("persona_id")
          .range(ini, fin),
      ),
      // Días CON marcaje de las últimas 3 semanas, para medir la racha en curso.
      // Tres semanas alcanzan: la racha más larga medida en CAYLA fue de 20 días
      // y con 21 se ve entera. Si alguna llegara más lejos, el aviso igual salta
      // — solo diría «21+» en vez del número exacto, y a esa altura el número
      // exacto ya no cambia nada.
      traerTodo<any>((ini, fin) =>
        supabase
          .from("jornadas")
          .select("persona_id, fecha, personas:persona_id(nombres, apellidos, sedes:sede_base_id(codigo))")
          .gte("fecha", haceDias(VENTANA_RACHA_DIAS)).lte("fecha", HOY)
          .gt("horas_trabajadas", 0)
          .order("persona_id")
          .range(ini, fin),
      ),
      // Tope de 12 meses del convenio de una practicante (Ley 28518 art. 30,
      // 0336). No es un dato nuevo: `fn_contratos_tablero` ya lo calcula para
      // el tablero de Contratos — acá solo se filtra a las filas que importan
      // en ESTA pantalla. Falla suave: si no llega, no se muestra el aviso.
      supabase.rpc("fn_contratos_tablero"),
    ]);

    if (errData || errTardias || errSedes || errEnc || errMetas || errHorarios || errTurnos) {
      setError((errData ?? errTardias ?? errSedes ?? errEnc ?? errMetas ?? errHorarios ?? errTurnos)!.message);
      setCargando(false);
      return; // no pisa `filas` con datos parciales/vacíos
    }
    setError(null);
    setAvisoLevantadas(
      errLevTard
        ? `No se pudo comprobar qué tardanzas ya fueron levantadas (${errLevTard.message}). ` +
          `El aviso de «patrón de tardanzas» se ocultó mientras tanto, para no volver a acusar una tardanza ya perdonada.`
        : null,
    );
    interface AceptadaRow {
      persona_id: string; fecha: string; tipo: string;
      nota: string | null; aceptado_por: string; aceptado_at: string;
      personas: { nombres: string; apellidos: string; sedes: { codigo: string } | null } | null;
    }
    const aceptadasRows = (aceptadasData as AceptadaRow[] | null) ?? [];
    // Set de claves aceptadas: `persona|fecha|tipo`. Falla suave (si no llega, no oculta nada).
    const aceptadas = new Set(aceptadasRows.map((a) => `${a.persona_id}|${a.fecha}|${a.tipo}`));

    const nombrePorId = new Map(
      ((personasData as { id: string; nombres: string; apellidos: string }[] | null) ?? [])
        .map((p) => [p.id, `${p.nombres} ${p.apellidos}`.trim()]),
    );
    setHistorial(
      aceptadasRows.map((a) => ({
        personaId: a.persona_id,
        nombre: `${a.personas?.nombres ?? ""} ${a.personas?.apellidos ?? ""}`.trim(),
        sede: a.personas?.sedes?.codigo ?? "?",
        fecha: a.fecha,
        tipo: a.tipo,
        nota: a.nota,
        aceptadoPor: nombrePorId.get(a.aceptado_por) ?? "otra persona",
        aceptadoAt: a.aceptado_at,
      })),
    );

    // Mapa persona_id|fecha → minutos de salida temprana (vía RPC, esquivando el schema cache).
    const minutosPorClave = new Map<string, number>();
    for (const e of (extraData as { persona_id: string; fecha: string; minutos_salida_temprana: number }[] | null) ?? []) {
      minutosPorClave.set(`${e.persona_id}|${e.fecha}`, e.minutos_salida_temprana ?? 0);
    }

    const out: Fila[] = [];
    for (const j of (data as any[]) ?? []) {
      const minutosTemprana = minutosPorClave.get(`${j.persona_id}|${j.fecha}`) ?? 0;
      // Un mismo día puede tener VARIAS incidencias a la vez: por ejemplo un día
      // auto-cerrado en el que ADEMÁS falta la marca de retorno del almuerzo.
      // Antes esto era una cadena de `else if` y solo se veía la primera, así que
      // los demás avisos de ese día se perdían sin que nadie los llegara a ver.
      const delDia: { tipo: string; aceptable?: string; severidad: Fila["severidad"] }[] = [];
      if (j.estado === "auto_cerrada_pendiente") delDia.push({ tipo: "Auto-cerrada (revisar)", severidad: "media" });
      if (j.fecha < HOY && j.estado === "abierta") delDia.push({ tipo: "Sin salida final", severidad: "alta" });
      if (j.fecha < HOY && j.tiene_salida_no_retornada) {
        // Se nombra el HECHO observable —falta una marca— y no una interpretación:
        // el sistema no puede saber si la persona se fue, si volvió sin marcar, o si
        // no tomó refrigerio y siguió trabajando. Las tres cosas pasan. Decide quien
        // revisa: registrando las marcas reales (y la jornada se recalcula sola), o
        // aceptando el día tal como está si de verdad trabajó de corrido.
        delDia.push({ tipo: "Sin marca de retorno del almuerzo", aceptable: "sin_retorno_almuerzo", severidad: "media" });
      }
      if (minutosTemprana > 0) delDia.push({ tipo: `Salida anticipada (${minutosTemprana} min)`, aceptable: "salida_anticipada", severidad: "media" });

      for (const inc of delDia) {
        // Si ya la aceptaste (visto bueno), no la muestres.
        if (inc.aceptable && aceptadas.has(`${j.persona_id}|${j.fecha}|${inc.aceptable}`)) continue;
        out.push({
          personaId: j.persona_id,
          nombre: `${j.personas?.nombres ?? ""} ${j.personas?.apellidos ?? ""}`.trim(),
          sede: j.personas?.sedes?.codigo ?? "?",
          fecha: j.fecha,
          tipo: inc.tipo,
          entrada: j.entrada_ts,
          salida: j.salida_final_ts,
          aceptable: inc.aceptable,
          severidad: inc.severidad,
        });
      }
    }

    // Patrón de tardanzas: 3+ en los últimos 30 días. Viene ordenado por fecha
    // descendente, así que la primera vez que aparece cada persona ya es su
    // tardanza más reciente.
    //
    // Todo el bloque se salta si `errLevTard` está presente: sin la lista de
    // tardanzas LEVANTADAS no hay forma de saber cuáles ya fueron perdonadas,
    // y contarlas igual reabriría como "patrón" algo que una encargada ya
    // resolvió — el falso positivo que este repositorio nombra como su peor
    // error. `avisoLevantadas`, seteado arriba, es lo que se lee en pantalla.
    if (!errLevTard) {
    // Días con tardanza LEVANTADA: no cuentan para el patrón.
    const levantadas = new Set(
      ((levTardData as { persona_id: string; fecha: string }[] | null) ?? []).map((t) => `${t.persona_id}|${t.fecha}`),
    );
    const porPersonaTardias = new Map<string, { count: number; ultima: any }>();
    for (const j of (tardias as any[]) ?? []) {
      if (levantadas.has(`${j.persona_id}|${j.fecha}`)) continue; // tardanza perdonada
      // 0413: el aviso automático de "patrón" es fiscalización activa del
      // sistema, no solo un número mostrado — se queda para quien está
      // en_planilla. Un practicante sigue viendo su tardanza en Desempeño;
      // acá no genera ninguna incidencia.
      if (j.personas?.en_planilla !== true) continue;
      const prev = porPersonaTardias.get(j.persona_id);
      if (prev) prev.count++;
      else porPersonaTardias.set(j.persona_id, { count: 1, ultima: j });
    }
    for (const { count, ultima: j } of porPersonaTardias.values()) {
      if (count < UMBRAL_PATRON_TARDANZAS) continue;
      out.push({
        personaId: j.persona_id,
        nombre: `${j.personas?.nombres ?? ""} ${j.personas?.apellidos ?? ""}`.trim(),
        sede: j.personas?.sedes?.codigo ?? "?",
        fecha: j.fecha,
        // «días corridos» y no «días» a secas: el umbral que arma el memo se
        // cuenta por MES CALENDARIO (art. 19.2-b del RIT) y vive en Disciplina.
        // Los dos números difieren cuando hay una tardanza del mes pasado
        // todavía dentro de la ventana, y sin nombrar el periodo esa diferencia
        // se lee como que una de las dos pantallas está rota.
        //
        // Acá NO se pone además el conteo del mes. Esta pantalla no conoce el
        // corte del expediente (non bis in idem) ni descarta las tardanzas de
        // más de tres horas, así que el número que calculara podría salir más
        // alto que el de Disciplina — y sería el falso positivo de siempre,
        // ahora con dos cifras propias en vez de una prestada.
        tipo: `Patrón de tardanzas (${count} en ${VENTANA_PATRON_DIAS} días corridos)`,
        entrada: j.entrada_ts,
        salida: null,
        severidad: "alta",
      });
    }
    } // fin if (!errLevTard)

    // ── Exceso de jornada ─────────────────────────────────────────────────
    // Las 48 h son el MÁXIMO LEGAL (Const. art. 25), no un objetivo: pasarse es
    // infracción y no se arregla pagando después.
    //
    // Se mide sobre la ventana de SIETE DÍAS CONSECUTIVOS más cargada de la
    // última semana, no sobre la semana de calendario. Antes se sumaba de lunes
    // a domingo, y así doce días seguidos de 8 h daban 48 y 48 —ninguna semana
    // se pasaba— cuando cualquier ventana de siete días de esa racha suma 56.
    // El Informe 027-2021-MTPE/14 es explícito: la semana, para determinar el
    // tiempo de trabajo, es un ciclo de siete días y no el del calendario.
    //
    // Y se mide contra 48, NO contra las 45 que CAYLA programa: 45 es el horario,
    // 48 la jornada ordinaria pactada. Avisar a las 45 llenaría la pantalla de
    // gente que está dentro de su contrato, y un aviso que salta siempre se
    // ignora a la semana.
    // CAMBIO 0284 — `sinConfirmar` guarda los días cuya salida la puso el
    // sistema y nadie confirmó todavía. NO se excluyen del cálculo a propósito:
    // el objetivo de este aviso es no perderse ningún tramo cargado, y sacar el
    // día podría esconder una sobrecarga real. Lo que se corrige es la
    // AFIRMACIÓN: el aviso deja de dar por hecho un exceso que puede descansar
    // en una hora que nadie marcó, y lo dice. Antes esta pantalla podía decir a
    // la vez «Auto-cerrada (revisar)» y «pasó el máximo legal» sobre el mismo
    // día — un falso positivo, que es el peor error según CLAUDE.md.
    const porPersonaHoras = new Map<
      string,
      { dias: { fecha: string; horas: number }[]; sinConfirmar: Set<string>; fila: any }
    >();
    for (const j of (horasSemanaData as any[]) ?? []) {
      const prev = porPersonaHoras.get(j.persona_id);
      const dia = { fecha: j.fecha as string, horas: Number(j.horas_trabajadas) || 0 };
      const pendiente = j.estado === "auto_cerrada_pendiente";
      if (prev) {
        prev.dias.push(dia);
        if (pendiente) prev.sinConfirmar.add(dia.fecha);
      } else {
        porPersonaHoras.set(j.persona_id, {
          dias: [dia],
          sinConfirmar: new Set(pendiente ? [dia.fecha] : []),
          fila: j,
        });
      }
    }
    // ¿La ventana de siete días que termina en `fin` contiene algún día así?
    const apoyadoEnHoraInventada = (sinConfirmar: Set<string>, fin: string) => {
      if (sinConfirmar.size === 0) return false;
      const cursor = new Date(`${fin}T00:00:00Z`);
      for (let i = 0; i < 7; i++) {
        if (sinConfirmar.has(cursor.toISOString().slice(0, 10))) return true;
        cursor.setUTCDate(cursor.getUTCDate() - 1);
      }
      return false;
    };
    for (const { dias, sinConfirmar, fila: j } of porPersonaHoras.values()) {
      const quien = {
        personaId: j.persona_id,
        nombre: `${j.personas?.nombres ?? ""} ${j.personas?.apellidos ?? ""}`.trim(),
        sede: j.personas?.sedes?.codigo ?? "?",
        entrada: null,
        salida: null,
      };
      // Una practicante tiene su propio tope (art. 44 Ley 28518), más bajo que
      // el máximo legal general — 30 h preprofesional, 48 h profesional. `null`
      // (no practicante, o practicante sin modalidad fijada) cae al de siempre.
      const maxLegal = maximoSemanalPracticante(j.personas?.tipo_vinculo, j.personas?.practicante_modalidad)
        ?? MAXIMO_LEGAL_SEMANAL;
      // Dos preguntas distintas, y por eso dos ventanas.
      //
      // La primera: ¿se está pasando AHORA? Ventana que termina en los últimos
      // siete días — todavía se puede mover un turno y frenarlo.
      const v = ventanaMasCargada(dias, haceDias(EXCESO_AUN_EVITABLE_DIAS), HOY);
      const hayExcesoVivo = v !== null && v.horas > maxLegal;
      if (hayExcesoVivo) {
        out.push({
          ...quien,
          fecha: v!.fin,
          tipo: `Jornada excedida: ${v!.horas.toFixed(1)} h en 7 días (máx. ${maxLegal})`
            + (apoyadoEnHoraInventada(sinConfirmar, v!.fin)
                 ? " · incluye días cuya salida puso el sistema y falta confirmar"
                 : ""),
          severidad: "alta",
        });
      }
      // La segunda: ¿se pasó ANTES y nadie lo vio? Ya no se puede evitar, pero
      // sigue siendo infracción del art. 25 y tiene que quedar registro — y si
      // generó sobretiempo, la boleta ya lo está pagando. Que el aviso caducara
      // no borra el hecho.
      //
      // Solo si no hay uno vivo: con los dos, quien tiene una racha larga vería
      // dos filas que dicen lo mismo y la de arriba ya pide la acción.
      if (hayExcesoVivo) continue;
      const vieja = ventanaMasCargada(
        dias,
        haceDias(VENTANA_EXCESO_DIAS - 1),
        haceDias(EXCESO_AUN_EVITABLE_DIAS + 1),
      );
      if (vieja === null || vieja.horas <= maxLegal) continue;
      if (aceptadas.has(`${j.persona_id}|${vieja.fin}|jornada_excedida`)) continue;
      out.push({
        ...quien,
        fecha: vieja.fin,
        tipo: `Jornada excedida (ya ocurrió): ${vieja.horas.toFixed(1)} h en 7 días (máx. ${maxLegal})`,
        aceptable: "jornada_excedida",
        severidad: "media",
      });
    }

    // ── Días seguidos sin descansar ───────────────────────────────────────
    // El D. Leg. 713 art. 1 da 24 h de descanso «en cada semana», y el Informe
    // 027-2021-MTPE/14 —vinculante— define semana como CICLO DE 7 DÍAS, no como
    // semana calendario. Por eso se cuentan días consecutivos y no se mira el
    // lunes: con descanso rotativo se puede cumplir «uno por semana calendario»
    // y encadenar doce días igual.
    //
    // Dos niveles a propósito. Al sexto día todavía se puede mover el turno del
    // día siguiente; al séptimo la infracción ya ocurrió y el aviso solo sirve
    // para no repetirla. El que evita el problema es el primero.
    const porPersonaDias = new Map<string, { fechas: string[]; fila: any }>();
    for (const j of (diasRachaData as any[]) ?? []) {
      const prev = porPersonaDias.get(j.persona_id);
      if (prev) prev.fechas.push(j.fecha);
      else porPersonaDias.set(j.persona_id, { fechas: [j.fecha], fila: j });
    }
    for (const { fechas, fila: j } of porPersonaDias.values()) {
      // Cuándo se avisa y cuándo el aviso ya caducó vive en `avisoDeRacha`, con
      // sus pruebas: la regla decide si esta pantalla dice una verdad o una
      // mentira, y el 2026-08-15 dijo una mentira por no tener dónde probarse.
      const aviso = avisoDeRacha(fechas, HOY);
      if (aviso === null) continue;

      // El aviso de 7+ se saca con visto bueno, no por antigüedad: la infracción
      // ya ocurrió y desaparecer sola sería borrarla sin que nadie la mirara. Si
      // la racha sigue creciendo, `ultimo` cambia y vuelve a salir — aceptar el
      // día 7 no tapa el día 8, que es justo lo que se quiere.
      const aceptable = aviso.excedida ? "racha_sin_descanso" : undefined;
      if (aceptable && aceptadas.has(`${j.persona_id}|${aviso.ultimo}|${aceptable}`)) continue;

      out.push({
        personaId: j.persona_id,
        nombre: `${j.personas?.nombres ?? ""} ${j.personas?.apellidos ?? ""}`.trim(),
        sede: j.personas?.sedes?.codigo ?? "?",
        fecha: aviso.ultimo,
        tipo: aviso.excedida
          ? `${aviso.seguidos} días seguidos sin descanso semanal`
          : `Lleva ${aviso.seguidos} días seguidos — el próximo le toca descansar`,
        entrada: null,
        salida: null,
        aceptable,
        // Excedida = infracción ya consumada (alta). Preventiva = todavía no es
        // infracción, solo un aviso de que mañana toca descansar (baja).
        severidad: aviso.excedida ? "alta" : "baja",
      });
    }

    // Déficit de encargadas: para cada sede/día de la semana actual con meta
    // definida, ¿cuántas supervisor_sede están programadas? Misma cascada
    // turno del día → horario_por_dia → legacy que usa admin/turnos.
    const codigoPorSede = new Map(((sedesData as { id: string; codigo: string }[] | null) ?? []).map((s) => [s.id, s.codigo]));
    setCodigoPorSedeId(codigoPorSede);
    const sedePorEncargada = new Map(((encargadasData as { id: string; sede_base_id: string }[] | null) ?? []).map((p) => [p.id, p.sede_base_id]));
    const turnoPorClave = new Map(
      ((turnosData as { persona_id: string; fecha: string; hora_entrada: string | null; hora_salida: string | null; es_descanso: boolean }[] | null) ?? [])
        .map((t) => [`${t.persona_id}|${t.fecha}`, t as TurnoDia]),
    );
    const horariosPorPersona = new Map<string, HorarioTramo[]>();
    for (const h of (horariosData as HorarioTramo[] | null) ?? []) {
      const arr = horariosPorPersona.get(h.persona_id) ?? [];
      arr.push(h);
      horariosPorPersona.set(h.persona_id, arr);
    }
    function trabajaEseDia(personaId: string, fecha: string): boolean {
      const turno = turnoPorClave.get(`${personaId}|${fecha}`) ?? null;
      const horario = horarioVigente(horariosPorPersona.get(personaId) ?? [], fecha);
      return esperadoDelDia(fecha, turno, horario).trabaja;
    }
    const diasSemanaActual = Array.from({ length: 7 }, (_, i) => addDias(lunesActual, i));
    for (const dia of diasSemanaActual) {
      const dow = diaSemanaNum(dia);
      for (const m of (metasData as { sede_id: string; dia_semana: number; meta_encargadas: number }[] | null) ?? []) {
        if (m.dia_semana !== dow) continue;
        const encargadas = [...sedePorEncargada.entries()].filter(([, sedeId]) => sedeId === m.sede_id).map(([id]) => id);
        const cubiertas = encargadas.filter((id) => trabajaEseDia(id, dia)).length;
        if (cubiertas >= m.meta_encargadas) continue;
        out.push({
          personaId: null,
          nombre: `Sede ${codigoPorSede.get(m.sede_id) ?? "?"}`,
          sede: codigoPorSede.get(m.sede_id) ?? "?",
          fecha: dia,
          tipo: `Déficit de encargadas (${cubiertas}/${m.meta_encargadas})`,
          entrada: null,
          salida: null,
          severidad: "media",
        });
      }
    }

    // Faltas: le tocaba y no marcó. Injustificadas en rojo (cuentan), justificadas
    // atenuadas (no cuentan, con su motivo). Vienen de fn_faltas (ya scopeada por rol).
    setRevisiones(((revisionesData as unknown as RevisionPedida[] | null) ?? []));

    for (const f of (faltasData as { persona_id: string; nombre: string; sede: string; fecha: string; justificada: boolean; motivo: string | null }[] | null) ?? []) {
      out.push({
        personaId: f.persona_id,
        nombre: f.nombre,
        sede: f.sede,
        fecha: f.fecha,
        tipo: f.justificada ? `Falta justificada · ${MOTIVO_LABEL(f.motivo)}` : "Falta injustificada",
        entrada: null,
        salida: null,
        esFalta: true,
        justificada: f.justificada,
        motivoFalta: f.motivo,
        severidad: f.justificada ? "baja" : "alta",
      });
    }

    // Practicantes sobre (o cerca de) el tope de 12 meses de su convenio.
    // `fn_contratos_tablero` ya distingue esto con `tipo = 'convenio_practicas'`
    // y un `estado` que, para una practicante, viene calculado contra el tope
    // legal — no contra la fecha que tenga escrita el convenio (0336). No es
    // un conteo de incidencias: es un aviso aparte, porque el riesgo de
    // desnaturalización existe aunque la practicante venga marcando todos
    // los días con normalidad.
    setPracticantesSobreTope(
      ((contratosData as { persona_id: string; persona: string; sede: string; tipo: string; estado: string; dias_restantes: number | null }[] | null) ?? [])
        .filter((c) => c.tipo === "convenio_practicas" && (c.estado === "vencido" || c.estado === "por_vencer"))
        .map((c) => ({ persona_id: c.persona_id, persona: c.persona, sede: c.sede, estado: c.estado, dias_restantes: c.dias_restantes })),
    );

    setFilas(out);
    setCargando(false);
  }, [router, desde, hasta]);

  useEffect(() => { void cargar(); }, [cargar]);

  const [aceptando, setAceptando] = useState<string | null>(null);
  // "Aceptar" (visto bueno): registra la incidencia como revisada y la saca de la
  // lista. Deja rastro (quién/cuándo), no la borra.
  //
  // Ojo con lo que significa aceptar en cada caso:
  //   salida_anticipada    → "sé que se fue antes y está bien".
  //   sin_retorno_almuerzo → "trabajó de corrido, no tomó refrigerio": el día se paga
  //     tal como está calculado. Si NO trabajó de corrido, esto no se acepta: se
  //     registran las marcas reales en Correcciones y la jornada se recalcula sola.
  //
  // Pasa por un modal chico (en vez de escribir directo al pulsar) para poder
  // pedir una nota opcional — el campo ya existía en incidencias_aceptadas desde
  // la 0052 y nunca se llenaba porque nada en pantalla lo pedía. El lote
  // (aprobarLote, abajo) NO pasa por acá a propósito: es un acuse masivo de "lo
  // vi", no una afirmación puntual que amerite explicación caso por caso.
  const [aceptarModal, setAceptarModal] = useState<{ personaId: string; fecha: string; tipo: string; nombre: string } | null>(null);
  const [notaAceptar, setNotaAceptar] = useState("");
  const [guardandoAceptar, setGuardandoAceptar] = useState(false);
  const [errorAceptarModal, setErrorAceptarModal] = useState<string | null>(null);

  function abrirAceptar(f: Fila) {
    if (!f.personaId || !f.aceptable) return;
    setAceptarModal({ personaId: f.personaId, fecha: f.fecha, tipo: f.aceptable, nombre: f.nombre });
    setNotaAceptar("");
    setErrorAceptarModal(null);
  }

  async function confirmarAceptar() {
    if (!aceptarModal) return;
    const clave = `${aceptarModal.personaId}|${aceptarModal.fecha}|${aceptarModal.tipo}`;
    setGuardandoAceptar(true);
    setAceptando(clave);
    const supabase = createAdminSupabaseClient();
    const { error: e } = await supabase.rpc("fn_aceptar_incidencia", {
      p_persona_id: aceptarModal.personaId, p_fecha: aceptarModal.fecha, p_tipo: aceptarModal.tipo,
      p_nota: notaAceptar.trim() || null,
    });
    setGuardandoAceptar(false);
    setAceptando(null);
    if (e) { setErrorAceptarModal(e.message); return; }
    setAceptarModal(null);
    setNotaAceptar("");
    await cargar(); // refresca la lista Y el historial (misma consulta trae ambos)
  }

  /** Deshacer una aceptación desde el historial — por si se aceptó por error. */
  async function quitarAceptacion(h: HistorialItem) {
    const clave = `${h.personaId}|${h.fecha}|${h.tipo}`;
    setQuitando(clave);
    const supabase = createAdminSupabaseClient();
    const { error: e } = await supabase.rpc("fn_quitar_aceptacion", {
      p_persona_id: h.personaId, p_fecha: h.fecha, p_tipo: h.tipo,
    });
    setQuitando(null);
    if (e) { setErrorAccion(`No se pudo deshacer: ${e.message}`); return; }
    await cargar();
  }

  const [loteando, setLoteando] = useState<string | null>(null); // sede en curso
  // Revisar en lote: SOLO para racha/exceso "ya ocurrido" (ver LOTEABLES arriba
  // — son acuse de "lo vi", no una afirmación sobre el día de nadie). Nunca
  // incluye salida anticipada ni almuerzo sin marcar: esas dos sí afirman un
  // hecho puntual y solo las puede dar por buenas quien revisó ESE día.
  async function aprobarLote(sede: string, filasSede: Fila[]) {
    const objetivo = filasSede.filter((f) => f.personaId && f.aceptable && LOTEABLES.has(f.aceptable));
    if (objetivo.length === 0) return;
    setLoteando(sede);
    const supabase = createAdminSupabaseClient();
    for (const f of objetivo) {
      if (!f.personaId || !f.aceptable) continue; // ya filtrado arriba; TS no lo sabe
      const { error: e } = await supabase.rpc("fn_aceptar_incidencia", {
        p_persona_id: f.personaId, p_fecha: f.fecha, p_tipo: f.aceptable,
      });
      if (e) { setError(`Se detuvo la revisión en lote: ${e.message}`); break; }
    }
    setLoteando(null);
    await cargar();
  }

  /** Cerrar una revisión pedida desde «Lo mío». La respuesta es opcional pero
   *  vale la pena: al otro lado hay alguien esperando saber en qué quedó. */
  async function atenderRevision(id: string) {
    setAtendiendo(id);
    const supabase = createAdminSupabaseClient();
    const { error: e } = await supabase.rpc("fn_atender_revision", {
      p_id: id, p_respuesta: (respuestas[id] ?? "").trim() || null,
    });
    setAtendiendo(null);
    if (e) { setErrorAccion(e.message); return; }
    setErrorAccion(null);
    setRespuestas((r) => ({ ...r, [id]: "" }));
    await cargar();
  }

  // ── Justificar una falta ─────────────────────────────────────────────────
  const [justif, setJustif] = useState<{ personaId: string; fecha: string; nombre: string } | null>(null);
  const [motivoSel, setMotivoSel] = useState("permiso_concedido");
  // El error de ESTE diálogo, dentro de ESTE diálogo. El servidor rechaza
  // «Descanso médico» acá a propósito (0124): ese motivo PAGA y exige documento,
  // y degradarlo en silencio a uno que no paga sería quitarle el día a quien
  // entregó su certificado. El rechazo trae la instrucción de qué hacer en su
  // lugar, así que tiene que leerse — y el único sitio donde se lee es acá.
  const [errorJustif, setErrorJustif] = useState<string | null>(null);

  const [observ, setObserv] = useState("");
  const [guardandoJustif, setGuardandoJustif] = useState(false);

  async function guardarJustificacion() {
    if (!justif) return;
    if (motivoSel === "otro" && observ.trim().length < 3) { setErrorJustif("Para 'Otro' la observación es obligatoria."); return; }
    setErrorJustif(null);
    setGuardandoJustif(true);
    const supabase = createAdminSupabaseClient();
    const { error: e } = await supabase.rpc("fn_set_justificacion", {
      p_persona_id: justif.personaId, p_fecha: justif.fecha, p_motivo: motivoSel,
      p_observacion: observ.trim() || null,
    });
    setGuardandoJustif(false);
    if (e) { setErrorJustif(e.message); return; }
    setJustif(null); setObserv(""); setMotivoSel("permiso_concedido"); setErrorJustif(null);
    await cargar();
  }

  async function quitarJustificacion(f: Fila) {
    if (!f.personaId) return;
    const supabase = createAdminSupabaseClient();
    const { error: e } = await supabase.rpc("fn_quitar_justificacion", { p_persona_id: f.personaId, p_fecha: f.fecha });
    if (e) { setErrorAccion(`No se pudo quitar la justificación: ${e.message}`); return; }
    await cargar();
  }

  // Encargada: solo su sede. RLS ya limita a su sede; esto es una salvaguarda visual.
  const visibles = useMemo(() => {
    if (rol === "supervisor_sede" && yo) {
      const miCodigo = codigoPorSedeId.get(yo.sedeBaseId);
      return filas.filter((f) => f.sede === miCodigo);
    }
    return filas;
  }, [filas, rol, yo, codigoPorSedeId]);

  // Vista filtrada por persona (viene del perfil vía ?persona=id). Filtra en memoria
  // lo ya cargado; personaId null (incidencias de sede) queda fuera al filtrar por persona.
  const vista = useMemo(
    () => (personaFiltro ? visibles.filter((f) => f.personaId === personaFiltro) : visibles),
    [visibles, personaFiltro],
  );
  const nombreFiltro = vista.length > 0 && personaFiltro ? vista[0].nombre : null;
  const porSede = [...new Set(vista.map((f) => f.sede))].sort();

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6">
        <div className="mb-1 flex flex-wrap items-end justify-between gap-3">
          <div className="flex items-center gap-3">
            <h1 className="font-serif text-2xl">Incidencias</h1>
            <div role="tablist" aria-label="Modo de vista" className="flex rounded-full border border-sand p-0.5">
              <button
                type="button"
                role="tab"
                aria-selected={vistaModo === "resumen"}
                onClick={() => setVistaModo("resumen")}
                className={`etiqueta rounded-full px-3 py-1 transition-colors ${
                  vistaModo === "resumen" ? "bg-tinta text-crema" : "text-taupe hover:bg-sand/40"
                }`}
              >
                Resumen
              </button>
              <button
                type="button"
                role="tab"
                aria-selected={vistaModo === "detalle"}
                onClick={() => setVistaModo("detalle")}
                className={`etiqueta rounded-full px-3 py-1 transition-colors ${
                  vistaModo === "detalle" ? "bg-tinta text-crema" : "text-taupe hover:bg-sand/40"
                }`}
              >
                Detalle
              </button>
            </div>
          </div>
          <span className="text-xs text-taupe">{cargando ? "Cargando…" : `${vista.length} por revisar`}</span>
        </div>
        {/* El toggle Resumen/Detalle vive ACÁ, no en la tabla de abajo: lo único
            que cambia de tamaño es esta explicación. La tabla de incidencias
            (y sus acciones) es siempre la misma, completa, en los dos modos —
            resumirla escondería justo lo que exige revisión. */}
        {vistaModo === "detalle" ? (
          <p className="mb-5 text-sm text-taupe">Días que necesitan tu revisión: auto-cerrados, sin salida final, sin retorno de pausa, o con salida anticipada (más de 15 min antes de su hora). Toca cualquiera para corregirlo. También avisa cuando alguien acumula {UMBRAL_PATRON_TARDANZAS}+ tardanzas en los últimos {VENTANA_PATRON_DIAS} <strong>días corridos</strong> — Dynamic solo avisa, la decisión (conversar, amonestar) es tuya. Ese conteo <strong>no es el que arma un memo</strong>: el umbral del RIT se cuenta por <strong>mes calendario</strong> y sale en Disciplina, así que acá el número puede ser mayor cuando queda una tardanza del mes pasado dentro de la ventana. Y si una sede no llega a su mínimo de encargadas programadas esta semana (configurable en Turnos), también sale acá. Avisa además cuando alguien pasa de {MAXIMO_LEGAL_SEMANAL} h en <strong>cualquier ventana de siete días seguidos</strong> — no por semana de calendario, porque así doce días corridos de 8 h darían 48 y 48 sin que nada saltara. Ese es el <strong>máximo legal</strong>, no un objetivo. Ese aviso viene en dos tonos: si la ventana termina esta semana todavía se puede mover un turno, y si dice <strong>«ya ocurrió»</strong> es un exceso de hasta {VENTANA_EXCESO_DIAS} días atrás que ya no se evita — se saca con <strong>Revisado</strong>, que deja constancia de quién lo miró. Y cuando alguien lleva {MAXIMO_DIAS_SIN_DESCANSO} días seguidos trabajando, porque el siguiente le toca descansar — el descanso semanal se cuenta en <strong>ciclos de 7 días</strong>, no por semana de calendario (Informe 027-2021-MTPE/14), así que con turnos rotativos se puede cumplir «uno por semana» y encadenar doce días igual. Ese aviso <strong>se va solo en cuanto descansa</strong>: si su último día trabajado ya quedó atrás, el descanso ocurrió y no hay nada que pedir. El de <strong>{MAXIMO_DIAS_SIN_DESCANSO + 1}+ días</strong> no se va solo —esa infracción ya ocurrió— y se saca con <strong>Revisado</strong>, que deja constancia de quién la miró. Ninguno de los dos límites —las {MAXIMO_LEGAL_SEMANAL} h ni el descanso— <strong>se arregla pagando después</strong>: el recargo del sobretiempo se paga aparte y no levanta el tope. Las <strong>faltas</strong> (le tocaba y no marcó) salen en rojo; usa <strong>Justificar</strong> para registrar el motivo (permiso, descanso médico, etc.) y sacarlas del conteo.</p>
        ) : (
          <p className="mb-5 text-sm text-taupe">
            Días que necesitan tu revisión: cierres mal hechos (auto-cierre, sin salida, sin retorno de almuerzo,
            salida anticipada), patrones de tardanza, exceso de las {MAXIMO_LEGAL_SEMANAL} h legales en 7 días
            seguidos, {MAXIMO_DIAS_SIN_DESCANSO}+ días sin descanso, sedes por debajo de su mínimo de encargadas, y
            faltas sin justificar. <strong>Dynamic solo avisa</strong> — conversar, amonestar o justificar es
            decisión tuya. Toca cualquier fila para corregirla; pasa a <strong>Detalle</strong> para las reglas
            completas de cada aviso (qué cuenta, qué no, y por qué).
          </p>
        )}

        <div className="mb-6 flex flex-wrap items-end gap-4">
          <Campo etiqueta="Desde" type="date" value={desde} onChange={(e) => setDesde(e.target.value)} />
          <Campo etiqueta="Hasta" type="date" value={hasta} onChange={(e) => setHasta(e.target.value)} />
        </div>

        {/* ── Lo que tu equipo pidió revisar ──────────────────────────────────
            Va PRIMERO, y no es orden alfabético: es la única lista de esta
            pantalla que no la generó el sistema mirando datos, sino una persona
            que estuvo ahí ese día. Un aviso automático puede esperar; alguien
            que escribió «ese día sí vine» no. */}
        {revisiones.length > 0 && (
          <section className="mb-6 rounded-2xl border border-tinta/25 bg-papel p-5">
            <h2 className="mb-1 font-serif text-lg">Tu equipo pidió revisar {revisiones.length} día{revisiones.length === 1 ? "" : "s"}</h2>
            <p className="mb-4 text-sm text-taupe">
              Lo escribieron desde «Lo mío». Corrige el día en Correcciones si hace falta y cierra acá diciendo
              en qué quedó — esa respuesta la va a leer la persona.
            </p>
            <ul className="space-y-3">
              {revisiones.map((r) => (
                <li key={r.id} className="rounded-xl border border-sand p-3 text-sm">
                  <div className="flex flex-wrap items-baseline justify-between gap-2">
                    <span><strong>{r.nombre}</strong> <span className="text-taupe">· {r.sede} · {r.fecha}</span></span>
                    <Link href={`/admin/correcciones?persona=${r.persona_id}&fecha=${r.fecha}`}
                      className="text-rojo hover:underline">Abrir ese día en Correcciones →</Link>
                  </div>
                  <p className="mt-1.5">«{r.comentario}»</p>
                  <div className="mt-2 flex flex-wrap items-center gap-2">
                    <div className="min-w-56 flex-1">
                      <Campo
                        value={respuestas[r.id] ?? ""}
                        onChange={(e) => setRespuestas((x) => ({ ...x, [r.id]: e.target.value }))}
                        placeholder="En qué quedó (lo va a leer la persona)"
                      />
                    </div>
                    <Boton variante="primario" onClick={() => void atenderRevision(r.id)} cargando={atendiendo === r.id}>
                      Marcar atendida
                    </Boton>
                  </div>
                </li>
              ))}
            </ul>
          </section>
        )}

        {/* Tope de 12 meses del convenio (0336) — aviso, no conteo. Una
            practicante puede venir marcando con normalidad todos los días y
            aun así estar en riesgo de que su convenio se considere
            desnaturalizado (Ley 28518, art. 30); eso no se ve en ninguna
            falta ni tardanza, así que necesita su propio aviso acá, donde DO
            ya está mirando la asistencia de esa persona. La acción vive en
            Contratos, no acá: renovar o cerrar un convenio no es cosa de
            Incidencias. */}
        {practicantesSobreTope.length > 0 && (
          <section className="mb-6 rounded-2xl border border-ambar/40 bg-ambar/5 p-5">
            <h2 className="mb-1 font-serif text-lg">
              {practicantesSobreTope.length} convenio{practicantesSobreTope.length === 1 ? "" : "s"} de prácticas en el tope de 12 meses
            </h2>
            <p className="mb-3 text-sm text-taupe">
              Ley 28518, art. 30: pasado el tope, la relación arriesga considerarse desnaturalizada —
              aunque siga viniendo con normalidad. Se revisa en Contratos, no acá.
            </p>
            <ul className="space-y-1.5 text-sm">
              {practicantesSobreTope.map((p) => (
                <li key={p.persona_id} className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
                  <span>
                    <strong>{p.persona}</strong> <span className="text-taupe">· {p.sede}</span>
                    {" — "}
                    {p.estado === "vencido"
                      ? "superó el tope de 12 meses"
                      : `se acerca al tope de 12 meses${p.dias_restantes !== null ? ` · ${p.dias_restantes} días` : ""}`}
                  </span>
                  {/* admin/contratos no lee ningún parámetro de la URL para
                      preseleccionar a alguien — un enlace con "?persona=" ahí
                      prometería un salto que no existe. */}
                  <Link href="/admin/contratos" className="shrink-0 text-taupe underline underline-offset-2 hover:text-tinta">
                    Ver en Contratos →
                  </Link>
                </li>
              ))}
            </ul>
          </section>
        )}

        {personaFiltro && (
          <div className="mb-6 flex flex-wrap items-center justify-between gap-2 rounded-lg border border-rojo/30 bg-rojo/5 px-4 py-2.5 text-sm">
            <span>
              {nombreFiltro
                ? <>Mostrando solo las incidencias de <strong>{nombreFiltro}</strong> en este periodo.</>
                : "La persona seleccionada no tiene incidencias por revisar en este periodo."}
            </span>
            <Boton variante="enlace" className="shrink-0 text-rojo" onClick={() => router.push("/admin/incidencias")}>Ver todas →</Boton>
          </div>
        )}

        {error && (
          <div className="mb-6 rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
            No se pudieron cargar las incidencias: {error}{" "}
            <Boton variante="enlace" onClick={() => void cargar()}>Reintentar</Boton>
          </div>
        )}

        {/* Aviso parcial, distinto del error de arriba: el resto de la
            pantalla sí cargó, pero el aviso de "patrón de tardanzas" se apagó
            porque no se pudo comprobar cuáles ya fueron perdonadas. */}
        {avisoLevantadas && (
          <div className="mb-6 rounded-lg border border-ambar/30 bg-ambar/10 px-4 py-3 text-sm">
            {avisoLevantadas}{" "}
            <Boton variante="enlace" onClick={() => void cargar()}>Reintentar</Boton>
          </div>
        )}

        {/* Lo que falló al ACTUAR, dicho como lo que es. Antes compartía estado
            con el de arriba, así que un rechazo al guardar salía anunciado como
            un fallo de carga y con un botón «Reintentar» que recargaba la
            pantalla en vez de repetir la acción — dos mentiras seguidas. */}
        {errorAccion && (
          <div className="mb-6 flex items-start gap-3 rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
            <span className="flex-1">{errorAccion}</span>
            <Boton variante="enlace" className="shrink-0" onClick={() => setErrorAccion(null)}>Entendido</Boton>
          </div>
        )}

        {!cargando && !error && vista.length === 0 && !personaFiltro && (
          <SinDatos texto="Sin incidencias por revisar en el periodo." />
        )}

        {/* Antes esta lista no tenía ningún estado de carga: mientras `cargando`
            era true, `vista` estaba vacía y `porSede.map` no dibujaba nada — la
            pantalla se quedaba en blanco hasta que llegaban los datos. */}
        {cargando && <EsqueletoSecciones anchos={["w-32", "w-24", "w-24", "w-12", "w-12", "w-20"]} />}

        {porSede.map((sede) => {
          const deSede = vista.filter((f) => f.sede === sede);
          if (deSede.length === 0) return null;
          const loteables = deSede.filter((f) => f.personaId && f.aceptable && LOTEABLES.has(f.aceptable));
          return (
            <section key={sede} className="mb-8">
              <div className="mb-3 flex flex-wrap items-baseline justify-between gap-2">
                <h2 className="font-serif text-lg">{sede} <span className="text-base text-taupe">· {deSede.length}</span></h2>
                {loteables.length >= 2 && (
                  <Boton
                    variante="sutil"
                    tamano="sm"
                    onClick={() => void aprobarLote(sede, deSede)}
                    disabled={loteando === sede}
                    title="Marca como revisadas todas las rachas y excesos de jornada de esta sede que ya solo necesitan constancia de que se vieron. No toca faltas, salidas anticipadas ni almuerzos sin marcar — esas afirman un hecho del día y se revisan una por una."
                  >
                    {loteando === sede ? "Revisando…" : `Marcar ${loteables.length} como revisadas`}
                  </Boton>
                )}
              </div>
              <Tabla>
                <TablaEncabezado>
                  <Th>Persona</Th>
                  <Th>Fecha</Th>
                  <Th>Incidencia</Th>
                  <Th>Entrada</Th>
                  <Th>Salida</Th>
                  <Th></Th>
                </TablaEncabezado>
                <tbody>
                  {deSede.map((f, i) => (
                    <FilaTabla key={`${f.personaId}-${f.fecha}-${i}`}>
                      <td className="px-4 py-2.5">{f.nombre}</td>
                      <td className="px-4 py-2.5 capitalize">{fechaLarga(f.fecha)}</td>
                      <td className="px-4 py-2.5">
                        <span className={`font-medium ${COLOR_SEVERIDAD[f.severidad]}`}>{f.tipo}</span>
                      </td>
                      <td className="px-4 py-2.5">{horaLima(f.entrada)}</td>
                      <td className="px-4 py-2.5">{horaLima(f.salida)}</td>
                      <td className="px-4 py-2.5 text-right">
                        <div className="flex items-center justify-end gap-3">
                          {f.aceptable && f.personaId && (
                            <Boton
                              variante="sutil"
                              tamano="sm"
                              onClick={() => abrirAceptar(f)}
                              disabled={aceptando === `${f.personaId}|${f.fecha}|${f.aceptable}`}
                              title={ACEPTAR_AYUDA(f.aceptable)}
                            >
                              {aceptando === `${f.personaId}|${f.fecha}|${f.aceptable}` ? "…" : ACEPTAR_BOTON(f.aceptable)}
                            </Boton>
                          )}
                          {f.esFalta && f.personaId && !f.justificada && (
                            <Boton
                              variante="sutil"
                              tamano="sm"
                              onClick={() => { setJustif({ personaId: f.personaId!, fecha: f.fecha, nombre: f.nombre }); setMotivoSel("permiso_concedido"); setObserv(""); setErrorJustif(null); }}
                              title="Registrar el motivo de esta falta (permiso, descanso médico, etc.)"
                            >
                              Justificar
                            </Boton>
                          )}
                          {f.esFalta && f.personaId && f.justificada && (
                            <Boton
                              variante="enlace"
                              className="text-xs text-taupe hover:text-tinta"
                              onClick={() => void quitarJustificacion(f)}
                              title="Quitar la justificación (vuelve a contar como falta)"
                            >
                              quitar justif.
                            </Boton>
                          )}
                          {/* Un solo enlace a "resolver este día": antes había
                              además un botón "Corregir" corto acá al lado,
                              con el mismo href — dos controles iguales que
                              solo se distinguían probando cuál era cuál. */}
                          {f.personaId ? (
                            <Link href={`/admin/correcciones?persona=${f.personaId}&fecha=${f.fecha}`} className="font-medium text-rojo underline decoration-rojo/30 underline-offset-2 hover:decoration-rojo">
                              Corregir ›
                            </Link>
                          ) : (
                            <Link href={`/admin/turnos?fecha=${f.fecha}`} className="font-medium text-rojo underline decoration-rojo/30 underline-offset-2 hover:decoration-rojo">
                              Ver turnos ›
                            </Link>
                          )}
                        </div>
                      </td>
                    </FilaTabla>
                  ))}
                </tbody>
              </Tabla>
            </section>
          );
        })}

        {/* Historial de lo ya aceptado — colapsado por defecto, para no competir
            con lo urgente. El dato (quién, cuándo, con qué nota) existe desde
            la 0052; lo único nuevo acá es mostrarlo. */}
        {historial.length > 0 && (
          <section className="mb-8">
            <button
              type="button"
              onClick={() => setMostrarHistorial((v) => !v)}
              className="etiqueta text-taupe underline underline-offset-2 hover:text-tinta"
            >
              {mostrarHistorial ? "Ocultar historial" : `Ver historial de incidencias aceptadas (${historial.length})`}
            </button>
            {mostrarHistorial && (
              <Tabla className="mt-3">
                <TablaEncabezado>
                  <Th>Persona</Th>
                  <Th>Fecha</Th>
                  <Th>Incidencia</Th>
                  <Th>Aceptado por</Th>
                  <Th>Nota</Th>
                  <Th></Th>
                </TablaEncabezado>
                <tbody>
                  {historial.map((h, i) => {
                    const clave = `${h.personaId}|${h.fecha}|${h.tipo}`;
                    return (
                      <FilaTabla key={`${clave}-${i}`}>
                        <td className="px-4 py-2.5">{h.nombre} <span className="text-taupe">· {h.sede}</span></td>
                        <td className="px-4 py-2.5 capitalize">{fechaLarga(h.fecha)}</td>
                        <td className="px-4 py-2.5">{TIPO_LABEL[h.tipo] ?? h.tipo}</td>
                        <td className="px-4 py-2.5 text-taupe">{h.aceptadoPor} · {fechaHoraLima(h.aceptadoAt)}</td>
                        <td className="px-4 py-2.5 text-taupe">{h.nota ?? "—"}</td>
                        <td className="px-4 py-2.5 text-right">
                          <Boton
                            variante="enlace"
                            className="text-xs text-taupe hover:text-rojo"
                            onClick={() => void quitarAceptacion(h)}
                            disabled={quitando === clave}
                            title="Deshacer esta aceptación (vuelve a aparecer en la lista de arriba si sigue vigente)."
                          >
                            {quitando === clave ? "…" : "Deshacer"}
                          </Boton>
                        </td>
                      </FilaTabla>
                    );
                  })}
                </tbody>
              </Tabla>
            )}
          </section>
        )}

        {/* Modal: justificar una falta. Antes era una reimplementación a mano
            (z-20, uno de los pisos distintos que convivían en el panel), sin
            role="dialog", sin cierre con Escape y sin foco al abrir — ahora
            usa <Modal>, que fija un solo piso (z-40) para todos los diálogos
            del sistema y cubre eso. */}
        <Modal
          abierto={!!justif}
          onCerrar={() => { setJustif(null); setErrorJustif(null); }}
          bloqueado={guardandoJustif}
          titulo="Justificar falta"
          ancho="sm"
        >
          {justif && (
            <>
              <p className="mb-4 text-sm text-taupe">{justif.nombre} · {fechaLarga(justif.fecha)}</p>
              <div className="mb-3">
                <CampoSelect etiqueta="Motivo" value={motivoSel} onChange={(e) => setMotivoSel(e.target.value)}>
                  {MOTIVOS.map((m) => <option key={m.valor} value={m.valor}>{m.label}</option>)}
                </CampoSelect>
              </div>
              {/* El aviso ANTES del choque, no después. El servidor rechaza este
                  motivo siempre (0124) y con razón —paga, y exige el documento
                  que este diálogo no pide—, pero ofrecerlo en la lista y
                  rechazarlo al pulsar es un callejón: la persona eligió bien lo
                  que le pasó a su compañera, y la pantalla la deja sin salida.
                  Acá se dice antes, y se dice a dónde ir. */}
              {motivoSel === "descanso_medico" && (
                <p className="mb-4 rounded-lg bg-sand/60 px-3 py-2 text-sm text-tinta">
                  El descanso médico <strong>se paga</strong>, así que necesita su documento
                  (profesional o institución, colegiatura y fecha) y se registra en{" "}
                  <a href="/admin/ausencias" className="font-medium underline">Ausencias</a>.
                  Si no hay documento, ahí mismo está «Descanso por salud»: no cuenta como falta,
                  pero no paga.
                </p>
              )}
              <label className="mb-4 flex flex-col gap-1 text-sm">
                Observación {motivoSel === "otro" ? <span className="text-rojo">(obligatoria)</span> : <span className="text-taupe">(opcional)</span>}
                <AreaTexto value={observ} onChange={(e) => setObserv(e.target.value)} rows={2} placeholder="ej. permiso por trámite" />
              </label>
              {/* Acá, y no en el banner de la página: este diálogo tapa la
                  pantalla entera mientras está abierto. Un rechazo pintado
                  detrás no lo ve nadie — quien pulsaba «Justificar» con
                  «Descanso médico» se quedaba mirando el mismo formulario, sin
                  saber si había funcionado. `whitespace-pre-line` porque el
                  mensaje del servidor explica qué hacer en su lugar y merece
                  leerse entero. */}
              {errorJustif && (
                <p className="mb-3 whitespace-pre-line rounded-lg bg-rojo/10 px-3 py-2 text-sm text-rojo">
                  {errorJustif}
                </p>
              )}
              <div className="flex justify-end gap-2">
                <Boton onClick={() => { setJustif(null); setErrorJustif(null); }} disabled={guardandoJustif}>Cancelar</Boton>
                <Boton
                  variante="primario"
                  onClick={() => void guardarJustificacion()}
                  disabled={motivoSel === "descanso_medico"}
                  cargando={guardandoJustif}
                >
                  Justificar
                </Boton>
              </div>
            </>
          )}
        </Modal>

        {/* Modal: aceptar una incidencia, con nota opcional. La nota queda en el
            historial de arriba — sirve para que quien revise después entienda
            por qué se dio por buena, sin tener que recordarlo. */}
        <Modal
          abierto={!!aceptarModal}
          onCerrar={() => { setAceptarModal(null); setErrorAceptarModal(null); }}
          bloqueado={guardandoAceptar}
          titulo={aceptarModal ? ACEPTAR_BOTON(aceptarModal.tipo) : "Aceptar"}
          ancho="sm"
        >
          {aceptarModal && (
            <>
              <p className="mb-3 text-sm text-taupe">{aceptarModal.nombre} · {fechaLarga(aceptarModal.fecha)}</p>
              <p className="mb-4 text-sm">{ACEPTAR_AYUDA(aceptarModal.tipo)}</p>
              <label className="mb-4 flex flex-col gap-1 text-sm">
                Nota <span className="text-taupe">(opcional — queda en el historial)</span>
                <AreaTexto
                  value={notaAceptar}
                  onChange={(e) => setNotaAceptar(e.target.value)}
                  rows={2}
                  placeholder="ej. avisó por WhatsApp que salía antes por cita médica"
                />
              </label>
              {errorAceptarModal && (
                <p className="mb-3 whitespace-pre-line rounded-lg bg-rojo/10 px-3 py-2 text-sm text-rojo">
                  {errorAceptarModal}
                </p>
              )}
              <div className="flex justify-end gap-2">
                <Boton onClick={() => { setAceptarModal(null); setErrorAceptarModal(null); }} disabled={guardandoAceptar}>Cancelar</Boton>
                <Boton variante="primario" onClick={() => void confirmarAceptar()} cargando={guardandoAceptar}>
                  {ACEPTAR_BOTON(aceptarModal.tipo)}
                </Boton>
              </div>
            </>
          )}
        </Modal>
      </main>
    </div>
  );
}

export default function IncidenciasPage() {
  return (
    <Suspense fallback={<main className="p-6"><Cargando /></main>}>
      <IncidenciasContenido />
    </Suspense>
  );
}
