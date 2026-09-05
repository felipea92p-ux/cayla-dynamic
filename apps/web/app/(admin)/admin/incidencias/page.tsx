"use client";

import { Suspense, useCallback, useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import Link from "next/link";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { AdminNav } from "../nav";
import { Cargando, EsqueletoSecciones } from "@/components/cargando";
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

interface Fila {
  personaId: string | null; // null = incidencia de sede (no de una persona puntual)
  nombre: string;
  sede: string;
  fecha: string;
  tipo: string;
  entrada: string | null;
  salida: string | null;
  aceptable?: string; // clave de tipo (p. ej. 'salida_anticipada') si se puede "Aceptar"
  corregible?: boolean; // incidencia de marcaje: se resuelve registrando las marcas reales
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

  // Lo que la gente pidió revisar desde «Lo mío» (0257). Va PRIMERO en esta
  // pantalla y no al final: es la única lista de acá que no la generó el
  // sistema mirando datos, sino una persona que sabe qué pasó ese día.
  const [revisiones, setRevisiones] = useState<RevisionPedida[]>([]);
  const [respuestas, setRespuestas] = useState<Record<string, string>>({});
  const [atendiendo, setAtendiendo] = useState<string | null>(null);

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
      { data: faltasData },
      { data: revisionesData },
      { data: levTardData },
      { data: horasSemanaData },
      { data: diasRachaData },
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
          .select("persona_id, fecha, entrada_ts, personas:persona_id(nombres, apellidos, sedes:sede_base_id(codigo))")
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
      supabase.from("incidencias_aceptadas").select("persona_id, fecha, tipo")
        .gte("fecha", [desde, haceDias(VENTANA_RACHA_DIAS), haceDias(VENTANA_EXCESO_DIAS)]
          .reduce((a, b) => (a < b ? a : b)))
        .lte("fecha", hasta > HOY ? hasta : HOY),
      // Faltas del rango (le tocaba y no marcó). Falla suave: si no llega, no se muestran.
      supabase.rpc("fn_faltas", { p_desde: desde, p_hasta: hasta }),
      // Pendientes de la 0257. Falla suave: mientras la migración no esté
      // pegada, PostgREST devuelve error, `data` viene null y la sección
      // simplemente no aparece. El resto de Incidencias no se entera.
      supabase.rpc("fn_revisiones_pedidas", { p_solo_pendientes: true }),
      // Tardanzas levantadas (perdonadas): no cuentan para el patrón. Ventana del patrón.
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
    ]);

    if (errData || errTardias || errSedes || errEnc || errMetas || errHorarios || errTurnos) {
      setError((errData ?? errTardias ?? errSedes ?? errEnc ?? errMetas ?? errHorarios ?? errTurnos)!.message);
      setCargando(false);
      return; // no pisa `filas` con datos parciales/vacíos
    }
    setError(null);
    // Set de claves aceptadas: `persona|fecha|tipo`. Falla suave (si no llega, no oculta nada).
    const aceptadas = new Set(
      (aceptadasData as { persona_id: string; fecha: string; tipo: string }[] | null ?? [])
        .map((a) => `${a.persona_id}|${a.fecha}|${a.tipo}`),
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
          corregible: true, // todas estas se arreglan registrando las marcas que faltan
          severidad: inc.severidad,
        });
      }
    }

    // Patrón de tardanzas: 3+ en los últimos 30 días. Viene ordenado por fecha
    // descendente, así que la primera vez que aparece cada persona ya es su
    // tardanza más reciente.
    // Días con tardanza LEVANTADA: no cuentan para el patrón.
    const levantadas = new Set(
      ((levTardData as { persona_id: string; fecha: string }[] | null) ?? []).map((t) => `${t.persona_id}|${t.fecha}`),
    );
    const porPersonaTardias = new Map<string, { count: number; ultima: any }>();
    for (const j of (tardias as any[]) ?? []) {
      if (levantadas.has(`${j.persona_id}|${j.fecha}`)) continue; // tardanza perdonada
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
  async function aceptar(f: Fila) {
    if (!f.personaId || !f.aceptable) return;
    const clave = `${f.personaId}|${f.fecha}|${f.aceptable}`;
    setAceptando(clave);
    const supabase = createAdminSupabaseClient();
    const { error: e } = await supabase.rpc("fn_aceptar_incidencia", {
      p_persona_id: f.personaId, p_fecha: f.fecha, p_tipo: f.aceptable,
    });
    setAceptando(null);
    if (e) { setErrorAccion(`No se pudo aceptar: ${e.message}`); return; }
    setFilas((prev) => prev.filter((x) => !(x.personaId === f.personaId && x.fecha === f.fecha && x.aceptable === f.aceptable)));
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
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <div className="mb-1 flex items-end justify-between">
          <h1 className="font-serif text-2xl">Incidencias</h1>
          <span className="text-xs text-taupe">{cargando ? "Cargando…" : `${vista.length} por revisar`}</span>
        </div>
        <p className="mb-5 text-sm text-taupe">Días que necesitan tu revisión: auto-cerrados, sin salida final, sin retorno de pausa, o con salida anticipada (más de 15 min antes de su hora). Toca cualquiera para corregirlo. También avisa cuando alguien acumula {UMBRAL_PATRON_TARDANZAS}+ tardanzas en los últimos {VENTANA_PATRON_DIAS} <strong>días corridos</strong> — Dynamic solo avisa, la decisión (conversar, amonestar) es tuya. Ese conteo <strong>no es el que arma un memo</strong>: el umbral del RIT se cuenta por <strong>mes calendario</strong> y sale en Disciplina, así que acá el número puede ser mayor cuando queda una tardanza del mes pasado dentro de la ventana. Y si una sede no llega a su mínimo de encargadas programadas esta semana (configurable en Turnos), también sale acá. Avisa además cuando alguien pasa de {MAXIMO_LEGAL_SEMANAL} h en <strong>cualquier ventana de siete días seguidos</strong> — no por semana de calendario, porque así doce días corridos de 8 h darían 48 y 48 sin que nada saltara. Ese es el <strong>máximo legal</strong>, no un objetivo. Ese aviso viene en dos tonos: si la ventana termina esta semana todavía se puede mover un turno, y si dice <strong>«ya ocurrió»</strong> es un exceso de hasta {VENTANA_EXCESO_DIAS} días atrás que ya no se evita — se saca con <strong>Revisado</strong>, que deja constancia de quién lo miró. Y cuando alguien lleva {MAXIMO_DIAS_SIN_DESCANSO} días seguidos trabajando, porque el siguiente le toca descansar — el descanso semanal se cuenta en <strong>ciclos de 7 días</strong>, no por semana de calendario (Informe 027-2021-MTPE/14), así que con turnos rotativos se puede cumplir «uno por semana» y encadenar doce días igual. Ese aviso <strong>se va solo en cuanto descansa</strong>: si su último día trabajado ya quedó atrás, el descanso ocurrió y no hay nada que pedir. El de <strong>{MAXIMO_DIAS_SIN_DESCANSO + 1}+ días</strong> no se va solo —esa infracción ya ocurrió— y se saca con <strong>Revisado</strong>, que deja constancia de quién la miró. Ninguno de los dos límites —las {MAXIMO_LEGAL_SEMANAL} h ni el descanso— <strong>se arregla pagando después</strong>: el recargo del sobretiempo se paga aparte y no levanta el tope. Las <strong>faltas</strong> (le tocaba y no marcó) salen en rojo; usa <strong>Justificar</strong> para registrar el motivo (permiso, descanso médico, etc.) y sacarlas del conteo.</p>

        <div className="mb-6 flex flex-wrap items-end gap-4">
          <label className="flex flex-col gap-1 text-sm">Desde
            <input type="date" value={desde} onChange={(e) => setDesde(e.target.value)} className="rounded-lg border border-sand bg-crema px-3 py-2" />
          </label>
          <label className="flex flex-col gap-1 text-sm">Hasta
            <input type="date" value={hasta} onChange={(e) => setHasta(e.target.value)} className="rounded-lg border border-sand bg-crema px-3 py-2" />
          </label>
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
                    <input
                      value={respuestas[r.id] ?? ""}
                      onChange={(e) => setRespuestas((x) => ({ ...x, [r.id]: e.target.value }))}
                      placeholder="En qué quedó (lo va a leer la persona)"
                      className="min-w-56 flex-1 rounded-lg border border-sand bg-crema px-3 py-1.5"
                    />
                    <button onClick={() => void atenderRevision(r.id)} disabled={atendiendo === r.id}
                      className="rounded-lg bg-tinta px-4 py-1.5 font-medium text-crema disabled:opacity-50">
                      {atendiendo === r.id ? "Guardando…" : "Marcar atendida"}
                    </button>
                  </div>
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
            <button onClick={() => router.push("/admin/incidencias")} className="shrink-0 font-medium text-rojo hover:underline">Ver todas →</button>
          </div>
        )}

        {error && (
          <div className="mb-6 rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
            No se pudieron cargar las incidencias: {error}{" "}
            <button onClick={() => void cargar()} className="font-medium underline">
              Reintentar
            </button>
          </div>
        )}

        {/* Lo que falló al ACTUAR, dicho como lo que es. Antes compartía estado
            con el de arriba, así que un rechazo al guardar salía anunciado como
            un fallo de carga y con un botón «Reintentar» que recargaba la
            pantalla en vez de repetir la acción — dos mentiras seguidas. */}
        {errorAccion && (
          <div className="mb-6 flex items-start gap-3 rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
            <span className="flex-1">{errorAccion}</span>
            <button onClick={() => setErrorAccion(null)} className="shrink-0 font-medium underline">
              Entendido
            </button>
          </div>
        )}

        {!cargando && !error && vista.length === 0 && !personaFiltro && (
          <div className="rounded-lg border border-sand bg-sand/30 px-4 py-8 text-center text-taupe">
            🎉 Sin incidencias en el periodo. Todo en orden.
          </div>
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
                  <button
                    onClick={() => void aprobarLote(sede, deSede)}
                    disabled={loteando === sede}
                    title="Marca como revisadas todas las rachas y excesos de jornada de esta sede que ya solo necesitan constancia de que se vieron. No toca faltas, salidas anticipadas ni almuerzos sin marcar — esas afirman un hecho del día y se revisan una por una."
                    className="rounded-lg border border-sand px-2.5 py-1 text-xs text-taupe hover:bg-sand/40 disabled:opacity-50"
                  >
                    {loteando === sede ? "Revisando…" : `Marcar ${loteables.length} como revisadas`}
                  </button>
                )}
              </div>
              <div className="overflow-x-auto rounded-2xl border border-sand bg-papel">
                <table className="w-full text-sm">
                  <thead className="bg-sand/70 text-left">
                    <tr className="etiqueta text-taupe">
                      <th className="px-4 py-2.5 font-medium">Persona</th>
                      <th className="px-4 py-2.5 font-medium">Fecha</th>
                      <th className="px-4 py-2.5 font-medium">Incidencia</th>
                      <th className="px-4 py-2.5 font-medium">Entrada</th>
                      <th className="px-4 py-2.5 font-medium">Salida</th>
                      <th className="px-4 py-2.5 font-medium"></th>
                    </tr>
                  </thead>
                  <tbody>
                    {deSede.map((f, i) => (
                      <tr key={`${f.personaId}-${f.fecha}-${i}`} className="border-t border-sand">
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
                              <button
                                onClick={() => void aceptar(f)}
                                disabled={aceptando === `${f.personaId}|${f.fecha}|${f.aceptable}`}
                                title={ACEPTAR_AYUDA(f.aceptable)}
                                className="rounded-lg border border-sand px-2.5 py-1 text-xs text-taupe hover:bg-sand/40 disabled:opacity-50"
                              >
                                {aceptando === `${f.personaId}|${f.fecha}|${f.aceptable}` ? "…" : ACEPTAR_BOTON(f.aceptable)}
                              </button>
                            )}
                            {f.corregible && f.personaId && (
                              <Link
                                href={`/admin/correcciones?persona=${f.personaId}&fecha=${f.fecha}`}
                                title="Abrir este día en Correcciones para registrar las marcas que faltan"
                                className="rounded-lg border border-sand px-2.5 py-1 text-xs text-taupe hover:bg-sand/40"
                              >
                                Corregir
                              </Link>
                            )}
                            {f.esFalta && f.personaId && !f.justificada && (
                              <button
                                onClick={() => { setJustif({ personaId: f.personaId!, fecha: f.fecha, nombre: f.nombre }); setMotivoSel("permiso_concedido"); setObserv(""); setErrorJustif(null); }}
                                title="Registrar el motivo de esta falta (permiso, descanso médico, etc.)"
                                className="rounded-lg border border-sand px-2.5 py-1 text-xs text-taupe hover:bg-sand/40"
                              >
                                Justificar
                              </button>
                            )}
                            {f.esFalta && f.personaId && f.justificada && (
                              <button
                                onClick={() => void quitarJustificacion(f)}
                                title="Quitar la justificación (vuelve a contar como falta)"
                                className="text-xs text-taupe underline hover:text-tinta"
                              >
                                quitar justif.
                              </button>
                            )}
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
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </section>
          );
        })}

        {/* Modal: justificar una falta */}
        {justif && (
          <div className="fixed inset-0 z-20 flex items-center justify-center bg-black/40 p-4" onClick={() => { if (!guardandoJustif) { setJustif(null); setErrorJustif(null); } }}>
            <div className="w-full max-w-sm rounded-xl border border-sand bg-crema p-6" onClick={(e) => e.stopPropagation()}>
              <h3 className="mb-1 font-serif text-lg">Justificar falta</h3>
              <p className="mb-4 text-sm text-taupe">{justif.nombre} · {fechaLarga(justif.fecha)}</p>
              <label className="mb-3 flex flex-col gap-1 text-sm">
                Motivo
                <select value={motivoSel} onChange={(e) => setMotivoSel(e.target.value)} className="rounded-lg border border-sand bg-crema px-3 py-2">
                  {MOTIVOS.map((m) => <option key={m.valor} value={m.valor}>{m.label}</option>)}
                </select>
              </label>
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
                <textarea value={observ} onChange={(e) => setObserv(e.target.value)} rows={2}
                  className="rounded-lg border border-sand bg-crema px-3 py-2" placeholder="ej. permiso por trámite" />
              </label>
              {/* Acá, y no en el banner de la página: este diálogo es `fixed
                  inset-0` y tapa la página entera. Un rechazo pintado detrás no
                  lo ve nadie — quien pulsaba «Justificar» con «Descanso médico»
                  se quedaba mirando el mismo formulario, sin saber si había
                  funcionado. `whitespace-pre-line` porque el mensaje del
                  servidor explica qué hacer en su lugar y merece leerse entero. */}
              {errorJustif && (
                <p className="mb-3 whitespace-pre-line rounded-lg bg-rojo/10 px-3 py-2 text-sm text-rojo">
                  {errorJustif}
                </p>
              )}
              <div className="flex justify-end gap-2">
                <button onClick={() => { setJustif(null); setErrorJustif(null); }} disabled={guardandoJustif} className="rounded-lg border border-sand px-3 py-2 text-sm">Cancelar</button>
                <button onClick={() => void guardarJustificacion()}
                  disabled={guardandoJustif || motivoSel === "descanso_medico"}
                  className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema disabled:opacity-50">
                  {guardandoJustif ? "Guardando…" : "Justificar"}
                </button>
              </div>
            </div>
          </div>
        )}
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
