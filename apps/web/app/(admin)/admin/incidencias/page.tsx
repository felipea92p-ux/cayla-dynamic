"use client";

import { Suspense, useCallback, useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import Link from "next/link";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { AdminNav } from "../nav";
import { Cargando } from "@/components/cargando";
import { traerTodo } from "@/lib/admin/traer-todo";
import {
  TZ_LIMA, hoyLima, MAXIMO_LEGAL_SEMANAL,
  MAXIMO_DIAS_SIN_DESCANSO, diasSeguidosTrabajados, ventanaMasCargada,
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
}

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

function IncidenciasContenido() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const personaFiltro = searchParams.get("persona");
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;
  const [desde, setDesde] = useState(haceDias(30));
  const [hasta, setHasta] = useState(HOY);
  const [filas, setFilas] = useState<Fila[]>([]);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);

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
      supabase.from("horarios_asignados").select("persona_id, hora_entrada, dias_laborables, horario_por_dia, vigente_desde, vigente_hasta").lte("vigente_desde", domingoActual).or(`vigente_hasta.is.null,vigente_hasta.gte.${lunesActual}`),
      supabase.from("turnos").select("persona_id, fecha, hora_entrada, es_descanso").gte("fecha", lunesActual).lte("fecha", domingoActual),
      // Incidencias ya aceptadas (visto bueno): para no volver a mostrarlas.
      supabase.from("incidencias_aceptadas").select("persona_id, fecha, tipo").gte("fecha", desde).lte("fecha", hasta),
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
          .select("persona_id, fecha, horas_trabajadas, personas:persona_id(nombres, apellidos, sedes:sede_base_id(codigo))")
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
          .gte("fecha", haceDias(20)).lte("fecha", HOY)
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
      const delDia: { tipo: string; aceptable?: string }[] = [];
      if (j.estado === "auto_cerrada_pendiente") delDia.push({ tipo: "Auto-cerrada (revisar)" });
      if (j.fecha < HOY && j.estado === "abierta") delDia.push({ tipo: "Sin salida final" });
      if (j.fecha < HOY && j.tiene_salida_no_retornada) {
        // Se nombra el HECHO observable —falta una marca— y no una interpretación:
        // el sistema no puede saber si la persona se fue, si volvió sin marcar, o si
        // no tomó refrigerio y siguió trabajando. Las tres cosas pasan. Decide quien
        // revisa: registrando las marcas reales (y la jornada se recalcula sola), o
        // aceptando el día tal como está si de verdad trabajó de corrido.
        delDia.push({ tipo: "Sin marca de retorno del almuerzo", aceptable: "sin_retorno_almuerzo" });
      }
      if (minutosTemprana > 0) delDia.push({ tipo: `Salida anticipada (${minutosTemprana} min)`, aceptable: "salida_anticipada" });

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
    const porPersonaHoras = new Map<string, { dias: { fecha: string; horas: number }[]; fila: any }>();
    for (const j of (horasSemanaData as any[]) ?? []) {
      const prev = porPersonaHoras.get(j.persona_id);
      const dia = { fecha: j.fecha as string, horas: Number(j.horas_trabajadas) || 0 };
      if (prev) prev.dias.push(dia);
      else porPersonaHoras.set(j.persona_id, { dias: [dia], fila: j });
    }
    for (const { dias, fila: j } of porPersonaHoras.values()) {
      const quien = {
        personaId: j.persona_id,
        nombre: `${j.personas?.nombres ?? ""} ${j.personas?.apellidos ?? ""}`.trim(),
        sede: j.personas?.sedes?.codigo ?? "?",
        entrada: null,
        salida: null,
      };
      // Dos preguntas distintas, y por eso dos ventanas.
      //
      // La primera: ¿se está pasando AHORA? Ventana que termina en los últimos
      // siete días — todavía se puede mover un turno y frenarlo.
      const v = ventanaMasCargada(dias, haceDias(EXCESO_AUN_EVITABLE_DIAS), HOY);
      const hayExcesoVivo = v !== null && v.horas > MAXIMO_LEGAL_SEMANAL;
      if (hayExcesoVivo) {
        out.push({
          ...quien,
          fecha: v!.fin,
          tipo: `Jornada excedida: ${v!.horas.toFixed(1)} h en 7 días (máx. ${MAXIMO_LEGAL_SEMANAL})`,
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
      if (vieja === null || vieja.horas <= MAXIMO_LEGAL_SEMANAL) continue;
      out.push({
        ...quien,
        fecha: vieja.fin,
        tipo: `Jornada excedida (ya ocurrió): ${vieja.horas.toFixed(1)} h en 7 días (máx. ${MAXIMO_LEGAL_SEMANAL})`,
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
      // La racha que importa es la que sigue viva: se mide desde el último día
      // con marcaje. Si fue hace tres días, ya descansó y no hay nada que avisar.
      const ultimo = fechas.reduce((a, b) => (a > b ? a : b));
      const seguidos = diasSeguidosTrabajados(fechas, ultimo);
      if (seguidos < MAXIMO_DIAS_SIN_DESCANSO) continue;
      out.push({
        personaId: j.persona_id,
        nombre: `${j.personas?.nombres ?? ""} ${j.personas?.apellidos ?? ""}`.trim(),
        sede: j.personas?.sedes?.codigo ?? "?",
        fecha: ultimo,
        tipo: seguidos === MAXIMO_DIAS_SIN_DESCANSO
          ? `Lleva ${seguidos} días seguidos — el próximo le toca descansar`
          : `${seguidos} días seguidos sin descanso semanal`,
        entrada: null,
        salida: null,
      });
    }

    // Déficit de encargadas: para cada sede/día de la semana actual con meta
    // definida, ¿cuántas supervisor_sede están programadas? Misma cascada
    // turno del día → horario_por_dia → legacy que usa admin/turnos.
    const codigoPorSede = new Map(((sedesData as { id: string; codigo: string }[] | null) ?? []).map((s) => [s.id, s.codigo]));
    const sedePorEncargada = new Map(((encargadasData as { id: string; sede_base_id: string }[] | null) ?? []).map((p) => [p.id, p.sede_base_id]));
    const turnoPorClave = new Map(
      ((turnosData as { persona_id: string; fecha: string; hora_entrada: string | null; es_descanso: boolean }[] | null) ?? [])
        .map((t) => [`${t.persona_id}|${t.fecha}`, t]),
    );
    const horariosPorPersona = new Map<string, { hora_entrada: string; dias_laborables: number[]; horario_por_dia: Record<string, unknown> | null; vigente_desde: string; vigente_hasta: string | null }[]>();
    for (const h of (horariosData as any[]) ?? []) {
      const arr = horariosPorPersona.get(h.persona_id) ?? [];
      arr.push(h);
      horariosPorPersona.set(h.persona_id, arr);
    }
    function trabajaEseDia(personaId: string, fecha: string): boolean {
      const t = turnoPorClave.get(`${personaId}|${fecha}`);
      if (t) return !t.es_descanso;
      const tramos = (horariosPorPersona.get(personaId) ?? [])
        .filter((h) => h.vigente_desde <= fecha && (h.vigente_hasta == null || h.vigente_hasta >= fecha))
        .sort((a, b) => (a.vigente_desde < b.vigente_desde ? 1 : -1));
      const h = tramos[0];
      if (!h) return false;
      const dow = diaSemanaNum(fecha);
      if (h.horario_por_dia) return Boolean((h.horario_por_dia as Record<string, unknown>)[String(dow)]);
      return (h.dias_laborables ?? []).includes(dow);
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
    if (e) { setError(`No se pudo aceptar: ${e.message}`); return; }
    setFilas((prev) => prev.filter((x) => !(x.personaId === f.personaId && x.fecha === f.fecha && x.aceptable === f.aceptable)));
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
    if (e) { setError(e.message); return; }
    setError(null);
    setRespuestas((r) => ({ ...r, [id]: "" }));
    await cargar();
  }

  // ── Justificar una falta ─────────────────────────────────────────────────
  const [justif, setJustif] = useState<{ personaId: string; fecha: string; nombre: string } | null>(null);
  const [motivoSel, setMotivoSel] = useState("permiso_concedido");

  const [observ, setObserv] = useState("");
  const [guardandoJustif, setGuardandoJustif] = useState(false);

  async function guardarJustificacion() {
    if (!justif) return;
    if (motivoSel === "otro" && observ.trim().length < 3) { setError("Para 'Otro' la observación es obligatoria."); return; }
    setGuardandoJustif(true);
    const supabase = createAdminSupabaseClient();
    const { error: e } = await supabase.rpc("fn_set_justificacion", {
      p_persona_id: justif.personaId, p_fecha: justif.fecha, p_motivo: motivoSel,
      p_observacion: observ.trim() || null,
    });
    setGuardandoJustif(false);
    if (e) { setError(`No se pudo justificar: ${e.message}`); return; }
    setJustif(null); setObserv(""); setMotivoSel("permiso_concedido");
    await cargar();
  }

  async function quitarJustificacion(f: Fila) {
    if (!f.personaId) return;
    const supabase = createAdminSupabaseClient();
    const { error: e } = await supabase.rpc("fn_quitar_justificacion", { p_persona_id: f.personaId, p_fecha: f.fecha });
    if (e) { setError(`No se pudo quitar la justificación: ${e.message}`); return; }
    await cargar();
  }

  // Encargada: solo su sede.
  const visibles = useMemo(() => {
    if (rol === "supervisor_sede" && yo) {
      // filtra por sede base de la encargada (comparando por código no disponible aquí);
      // RLS ya limita a su sede, así que esto es una salvaguarda visual mínima.
      return filas;
    }
    return filas;
  }, [filas, rol, yo]);

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
        <p className="mb-5 text-sm text-taupe">Días que necesitan tu revisión: auto-cerrados, sin salida final, sin retorno de pausa, o con salida anticipada (más de 15 min antes de su hora). Toca cualquiera para corregirlo. También avisa cuando alguien acumula {UMBRAL_PATRON_TARDANZAS}+ tardanzas en los últimos {VENTANA_PATRON_DIAS} <strong>días corridos</strong> — Dynamic solo avisa, la decisión (conversar, amonestar) es tuya. Ese conteo <strong>no es el que arma un memo</strong>: el umbral del RIT se cuenta por <strong>mes calendario</strong> y sale en Disciplina, así que acá el número puede ser mayor cuando queda una tardanza del mes pasado dentro de la ventana. Y si una sede no llega a su mínimo de encargadas programadas esta semana (configurable en Turnos), también sale acá. Avisa además cuando alguien pasa de {MAXIMO_LEGAL_SEMANAL} h en <strong>cualquier ventana de siete días seguidos</strong> — no por semana de calendario, porque así doce días corridos de 8 h darían 48 y 48 sin que nada saltara. Ese es el <strong>máximo legal</strong>, no un objetivo. Y cuando alguien lleva {MAXIMO_DIAS_SIN_DESCANSO} días seguidos trabajando, porque el siguiente le toca descansar — el descanso semanal se cuenta en <strong>ciclos de 7 días</strong>, no por semana de calendario (Informe 027-2021-MTPE/14), así que con turnos rotativos se puede cumplir «uno por semana» y encadenar doce días igual. Los dos avisos llegan mientras todavía se puede mover el turno: ninguno de los dos se arregla pagando después. Las <strong>faltas</strong> (le tocaba y no marcó) salen en rojo; usa <strong>Justificar</strong> para registrar el motivo (permiso, descanso médico, etc.) y sacarlas del conteo.</p>

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
                      placeholder="En qué quedó (lo va a leer ella)"
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

        {!cargando && !error && vista.length === 0 && !personaFiltro && (
          <div className="rounded-lg border border-sand bg-sand/30 px-4 py-8 text-center text-taupe">
            🎉 Sin incidencias en el periodo. Todo en orden.
          </div>
        )}

        {porSede.map((sede) => {
          const deSede = vista.filter((f) => f.sede === sede);
          if (deSede.length === 0) return null;
          return (
            <section key={sede} className="mb-8">
              <h2 className="mb-3 font-serif text-lg">{sede} <span className="text-base text-taupe">· {deSede.length}</span></h2>
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
                          <span className={`font-medium ${f.justificada ? "text-taupe" : "text-rojo"}`}>{f.tipo}</span>
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
                                onClick={() => { setJustif({ personaId: f.personaId!, fecha: f.fecha, nombre: f.nombre }); setMotivoSel("permiso_concedido"); setObserv(""); }}
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
          <div className="fixed inset-0 z-20 flex items-center justify-center bg-black/40 p-4" onClick={() => !guardandoJustif && setJustif(null)}>
            <div className="w-full max-w-sm rounded-xl border border-sand bg-crema p-6" onClick={(e) => e.stopPropagation()}>
              <h3 className="mb-1 font-serif text-lg">Justificar falta</h3>
              <p className="mb-4 text-sm text-taupe">{justif.nombre} · {fechaLarga(justif.fecha)}</p>
              <label className="mb-3 flex flex-col gap-1 text-sm">
                Motivo
                <select value={motivoSel} onChange={(e) => setMotivoSel(e.target.value)} className="rounded-lg border border-sand bg-crema px-3 py-2">
                  {MOTIVOS.map((m) => <option key={m.valor} value={m.valor}>{m.label}</option>)}
                </select>
              </label>
              <label className="mb-4 flex flex-col gap-1 text-sm">
                Observación {motivoSel === "otro" ? <span className="text-rojo">(obligatoria)</span> : <span className="text-taupe">(opcional)</span>}
                <textarea value={observ} onChange={(e) => setObserv(e.target.value)} rows={2}
                  className="rounded-lg border border-sand bg-crema px-3 py-2" placeholder="ej. permiso por trámite" />
              </label>
              <div className="flex justify-end gap-2">
                <button onClick={() => setJustif(null)} disabled={guardandoJustif} className="rounded-lg border border-sand px-3 py-2 text-sm">Cancelar</button>
                <button onClick={() => void guardarJustificacion()} disabled={guardandoJustif} className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema disabled:opacity-50">
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
