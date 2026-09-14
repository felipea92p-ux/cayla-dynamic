"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { Search } from "lucide-react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { Cargando } from "@/components/cargando";
import { useToast } from "@/components/toast";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { Boton } from "@/components/ui/boton";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { AreaTexto } from "@/components/ui/area-texto";
import { Tabla, TablaEncabezado, Th, Fila } from "@/components/ui/tabla";
import { Insignia } from "@/components/ui/insignia";
import { Modal } from "@/components/ui/modal";
import { ROLES_DO, hoyLima, puedeOperarEquipo, maximoSemanalPracticante } from "@cayla-dynamic/shared";
// horasDia() reimplementaba (salida − entrada) − refrigerio a mano, sin el
// ajuste "si la salida no es posterior a la entrada, el turno cruza
// medianoche" que horasEntre() ya resuelve (turnos/page.tsx también la
// reusa). Sin eso, un horario nocturno (p. ej. 21:00–05:00) daba 0 horas en
// vez de las ocho reales, escondiendo el aviso de exceso legal semanal de
// una practicante.
import { horasEntre as horasDia, esTurnoEspejoViejo, type HorarioTramo } from "@/lib/admin/jornada-esperada";

const META_SEMANA = 45; // horas objetivo por semana (7.5h × 6 días)
// Más allá de esto, corregir el pasado deja de ser "hace unos días" y empieza
// a oler a fecha mal puesta: el candado de verdad es el motivo obligatorio y
// el preview, pero un rango de años recorrería un día a la vez sin necesidad.
const MAX_DIAS_RETROACTIVO = 120;

function fmtH(h: number): string {
  return `${Math.round(h * 100) / 100} h`;
}

/** El día de ayer en Lima, como `2026-09-13` — el valor más probable al abrir
 * la corrección retroactiva: casi siempre el cambio real fue "hace poco". */
function ayerLima(): string {
  const [y, m, d] = hoyLima().split("-").map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  dt.setUTCDate(dt.getUTCDate() - 1);
  return dt.toISOString().slice(0, 10);
}

/** Días de calendario entre dos fechas ISO de Lima (positivo si `hasta` es posterior). */
function diasEntreLima(desde: string, hasta: string): number {
  const [y1, m1, d1] = desde.split("-").map(Number);
  const [y2, m2, d2] = hasta.split("-").map(Number);
  return Math.round((Date.UTC(y2, m2 - 1, d2) - Date.UTC(y1, m1 - 1, d1)) / 86_400_000);
}

type Dia = { e: string; s: string; r: number };
type PorDia = Record<number, Dia>;
interface Persona {
  id: string; nombres: string; apellidos: string; rol: string; sede_base_id: string;
  // Para avisar del máximo legal de una practicante (0324) — llegan por
  // fn_personas_funciones, no por el select directo de `personas`, porque el
  // schema cache de PostgREST no expone estas columnas.
  tipo_vinculo: string;
  practicante_modalidad: string | null;
}
interface Horario {
  persona_id: string; hora_entrada: string; hora_salida: string; vigente_desde: string;
  almuerzo_min_minutos: number; almuerzo_max_minutos: number; dias_laborables: number[];
  horario_por_dia: Record<string, { e: string; s: string; r?: number }> | null;
}
// Para el historial de tramos del modal — igual que Horario, con el cierre.
interface Tramo extends Horario {
  vigente_hasta: string | null;
}
interface FilaPreview {
  fecha: string;
  minutos_tarde_actual: number | null; minutos_tarde_nuevo: number | null;
  minutos_salida_temprana_actual: number | null; minutos_salida_temprana_nuevo: number | null;
  horas_extra_actual: number | null; horas_extra_nuevo: number | null;
  tiene_expediente_formal: boolean;
}
const DIAS = [{ v: 1, l: "L" }, { v: 2, l: "M" }, { v: 3, l: "X" }, { v: 4, l: "J" }, { v: 5, l: "V" }, { v: 6, l: "S" }, { v: 0, l: "D" }];
const NOMBRE_DIA: Record<number, string> = { 0: "domingo", 1: "lunes", 2: "martes", 3: "miércoles", 4: "jueves", 5: "viernes", 6: "sábado" };

// El refrigerio real de CAYLA es 60 o 75 minutos, nunca otro número — un campo
// libre dejaba pasar un "6" en vez de un "60" sin que nada lo detectara, y eso
// se cuela directo al cálculo de jornada. Auditoría 2026-09-14.
const REFRIGERIOS_MIN = [60, 75];

// Datos viejos pueden traer un refrigerio fuera de {60, 75} (el schema
// permite 45-75, el legacy por defecto era 45). En vez de esconderlo -el
// selector no puede mostrar "seleccionado" un valor que no está en sus
// opciones sin que el estado real quede desincronizado de lo que se ve- se
// agrega como una tercera opción visible, para no pisarlo sin que quien
// edita lo note.
function opcionesRefrigerio(actual: number): number[] {
  return REFRIGERIOS_MIN.includes(actual) ? REFRIGERIOS_MIN : [...REFRIGERIOS_MIN, actual].sort((a, b) => a - b);
}

// Buscar «Ramirez» tiene que encontrar a «Ramírez». Mismo normalizador que
// /admin/contratos, /admin/horas y el buscador global.
function sinTildes(t: string): string {
  return t.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase();
}

function textoDescanso(dias: number[]): string {
  const libres = [1, 2, 3, 4, 5, 6, 0].filter((d) => !dias.includes(d));
  if (libres.length === 0) return "sin descanso";
  return libres.map((d) => NOMBRE_DIA[d]).join(", ");
}

// Extrae el horario por día (jsonb nuevo con refrigerio, o legacy de una sola hora).
function analizar(h?: Horario): { porDia: PorDia; dias: number[]; uniforme: boolean; e: string; s: string; r: number } {
  const pd: PorDia = {};
  if (h?.horario_por_dia && typeof h.horario_por_dia === "object") {
    for (const [k, v] of Object.entries(h.horario_por_dia)) {
      const d = Number(k);
      if (!Number.isNaN(d) && v && typeof v === "object") {
        pd[d] = { e: (v.e ?? "08:00").slice(0, 5), s: (v.s ?? v.e ?? "18:00").slice(0, 5), r: Number(v.r ?? 60) };
      }
    }
  } else if (h) {
    const r = h.almuerzo_min_minutos ?? 60;
    for (const d of h.dias_laborables ?? [1, 2, 3, 4, 5, 6]) pd[d] = { e: h.hora_entrada.slice(0, 5), s: h.hora_salida.slice(0, 5), r };
  } else {
    for (const d of [1, 2, 3, 4, 5, 6]) pd[d] = { e: "08:00", s: "18:00", r: 60 };
  }
  const dias = Object.keys(pd).map(Number).sort((a, b) => a - b);
  const first = dias.length ? pd[dias[0]] : { e: "08:00", s: "18:00", r: 60 };
  const uniforme = dias.every((d) => pd[d].e === first.e && pd[d].s === first.s && pd[d].r === first.r);
  return { porDia: pd, dias, uniforme, e: first.e, s: first.s, r: first.r };
}

export default function HorariosPage() {
  const router = useRouter();
  const { avisar } = useToast();
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [horarios, setHorarios] = useState<Map<string, Horario>>(new Map());
  // Cuando el tramo abierto de `horarios` empieza a futuro (badge "Programado"),
  // este mapa trae el tramo que SÍ rige hoy — para no mostrar como vigente algo
  // que todavía no entró en efecto. Solo se completa para esas personas, no
  // para las ~30 en cada carga.
  const [vigentesHoy, setVigentesHoy] = useState<Map<string, Horario>>(new Map());
  const [sedes, setSedes] = useState<Record<string, string>>({});
  const [cargando, setCargando] = useState(true);
  const [busca, setBusca] = useState("");
  const [filtroSede, setFiltroSede] = useState("");
  const [filtroTipo, setFiltroTipo] = useState<"" | "sin_horario" | "fijo" | "varia">("");

  const [editando, setEditando] = useState<Persona | null>(null);
  const [modoPorDia, setModoPorDia] = useState(false);
  const [entrada, setEntrada] = useState("08:00");   // modo rápido
  const [salida, setSalida] = useState("18:00");     // modo rápido
  const [refri, setRefri] = useState(60);            // modo rápido (min)
  const [dias, setDias] = useState<number[]>([1, 2, 3, 4, 5, 6]);
  const [porDia, setPorDia] = useState<PorDia>({});  // modo por día
  const [desde, setDesde] = useState(hoyLima());
  const [motivo, setMotivo] = useState("");
  const [guardando, setGuardando] = useState(false);
  const [copiarDeId, setCopiarDeId] = useState("");
  // Tramos anteriores de la persona en edición, solo lectura (0389: el
  // historial ya vive en `horarios_asignados`, esto solo lo expone).
  const [historial, setHistorial] = useState<Tramo[]>([]);

  // ── Corrección retroactiva (0447): aparte del cambio normal a propósito —
  // ver CLAUDE.md, "un horario normal no puede pisar el pasado" (0444). Estado
  // propio, en el mismo estilo plano que el modal normal de arriba, para no
  // arriesgar ese flujo ya construido con un refactor a un hook compartido.
  const [retro, setRetro] = useState<Persona | null>(null);
  const [retroModoPorDia, setRetroModoPorDia] = useState(false);
  const [retroEntrada, setRetroEntrada] = useState("08:00");
  const [retroSalida, setRetroSalida] = useState("18:00");
  const [retroRefri, setRetroRefri] = useState(60);
  const [retroDias, setRetroDias] = useState<number[]>([1, 2, 3, 4, 5, 6]);
  const [retroPorDia, setRetroPorDia] = useState<PorDia>({});
  const [retroDesde, setRetroDesde] = useState(ayerLima());
  const [retroMotivo, setRetroMotivo] = useState("");
  const [retroPreview, setRetroPreview] = useState<FilaPreview[] | null>(null);
  const [retroPreviewCargando, setRetroPreviewCargando] = useState(false);
  const [retroConfirmando, setRetroConfirmando] = useState(false);

  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    setCargando(true);
    const [
      { data: p, error: errP },
      { data: h, error: errH },
      { data: s, error: errS },
      { data: f, error: errF },
    ] = await Promise.all([
      supabase.from("personas").select("id, nombres, apellidos, rol, sede_base_id").eq("estado", "activo").order("nombres"),
      supabase.from("horarios_asignados").select("persona_id, hora_entrada, hora_salida, vigente_desde, almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horario_por_dia").is("vigente_hasta", null),
      supabase.from("sedes").select("id, codigo"),
      // tipo_vinculo y practicante_modalidad no viajan en el select de arriba
      // (schema cache de PostgREST): para saber contra qué máximo avisar
      // hace falta esta RPC. Tolerante: si falla, nadie ve el aviso — no se
      // cae la pantalla entera por un dato que hoy es informativo.
      supabase.rpc("fn_personas_funciones"),
    ]);
    if (errP || errH || errS) {
      avisar("error", mensajeDeError((errP ?? errH ?? errS)!, "cargar los horarios"));
      setCargando(false);
      return; // no pisa `personas`/`horarios`/`sedes` con datos parciales
    }
    const vinculos = new Map(
      (errF ? [] : ((f as { persona_id: string; tipo_vinculo?: string; practicante_modalidad?: string | null }[] | null) ?? []))
        .map((x) => [x.persona_id, { tipo_vinculo: x.tipo_vinculo ?? "planilla", practicante_modalidad: x.practicante_modalidad ?? null }] as const),
    );
    setPersonas(
      ((p as Omit<Persona, "tipo_vinculo" | "practicante_modalidad">[]) ?? []).map((x) => {
        const v = vinculos.get(x.id);
        return { ...x, tipo_vinculo: v?.tipo_vinculo ?? "planilla", practicante_modalidad: v?.practicante_modalidad ?? null };
      }),
    );
    const abiertos = (h as Horario[]) ?? [];
    setHorarios(new Map(abiertos.map((x) => [x.persona_id, x])));
    setSedes(Object.fromEntries(((s as any[]) ?? []).map((x) => [x.id, x.codigo])));

    // El tramo abierto puede empezar a futuro (alguien programó un cambio de
    // horario). Para esas personas nada más, trae el tramo que cubre HOY —
    // si no se hace esto, la pantalla muestra un horario que todavía no rige
    // como si ya rigiera (auditoría 2026-09-14).
    const hoy = hoyLima();
    const idsFuturos = abiertos.filter((x) => x.vigente_desde > hoy).map((x) => x.persona_id);
    if (idsFuturos.length > 0) {
      const { data: vh } = await supabase
        .from("horarios_asignados")
        .select("persona_id, hora_entrada, hora_salida, vigente_desde, almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horario_por_dia")
        .in("persona_id", idsFuturos)
        .lte("vigente_desde", hoy)
        .or(`vigente_hasta.is.null,vigente_hasta.gte.${hoy}`);
      setVigentesHoy(new Map(((vh as Horario[]) ?? []).map((x) => [x.persona_id, x])));
    } else {
      setVigentesHoy(new Map());
    }
    setCargando(false);
  }, [router, avisar]);

  useEffect(() => { void cargar(); }, [cargar]);

  const puedeEditar = puedeOperarEquipo(rol);
  const esSupervisor = rol === "supervisor_sede";
  const editables = useMemo(() => {
    if (!esSupervisor || !yo) return personas;
    return personas.filter((p) => p.id !== yo.id && !ROLES_DO.includes(p.rol));
  }, [personas, esSupervisor, yo]);

  const hoy = hoyLima();
  // Lo que rige HOY para una persona: el tramo abierto, salvo que ese tramo
  // empiece a futuro — ahí rige lo que trajo `vigentesHoy` (o nada, si su
  // primer horario todavía no llegó).
  function horarioDeHoy(p: Persona): Horario | undefined {
    const abierto = horarios.get(p.id);
    if (!abierto) return undefined;
    return abierto.vigente_desde > hoy ? vigentesHoy.get(p.id) : abierto;
  }

  // Hook: tiene que llamarse siempre, incluso en el render donde más abajo
  // se corta con "no tienes permiso" — por eso vive antes de ese return.
  const filtrados = useMemo(() => {
    const q = sinTildes(busca.trim());
    return editables.filter((p) => {
      if (filtroSede && (sedes[p.sede_base_id] ?? "?") !== filtroSede) return false;
      if (q && !sinTildes(`${p.nombres} ${p.apellidos}`).includes(q)) return false;
      if (filtroTipo) {
        // analizar(undefined) NO significa "sin horario": rellena una semana
        // completa 08:00-18:00 de L a S para que el formulario de "Asignar"
        // arranque con algo editable. Sin este guard (el mismo que ya usa la
        // fila de la tabla), este filtro nunca encontraba a nadie.
        const h = horarioDeHoy(p);
        const a = h ? analizar(h) : null;
        const tipo = !a || a.dias.length === 0 ? "sin_horario" : a.uniforme ? "fijo" : "varia";
        if (tipo !== filtroTipo) return false;
      }
      return true;
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps -- horarioDeHoy lee horarios/vigentesHoy/hoy, ya listados
  }, [editables, busca, filtroSede, filtroTipo, sedes, horarios, vigentesHoy, hoy]);

  function aplicarAnalisis(a: ReturnType<typeof analizar>) {
    setPorDia(a.porDia);
    setDias(a.dias.length ? a.dias : [1, 2, 3, 4, 5, 6]);
    setEntrada(a.e);
    setSalida(a.s);
    setRefri(a.r);
    setModoPorDia(!a.uniforme);
  }

  function abrirEdicion(p: Persona) {
    aplicarAnalisis(analizar(horarios.get(p.id)));
    setEditando(p);
    setDesde(hoyLima());
    setMotivo("");
    setCopiarDeId("");
    setHistorial([]);
    void cargarHistorial(p.id);
  }

  async function cargarHistorial(personaId: string) {
    const supabase = createAdminSupabaseClient();
    const { data } = await supabase
      .from("horarios_asignados")
      .select("persona_id, hora_entrada, hora_salida, vigente_desde, vigente_hasta, almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horario_por_dia")
      .eq("persona_id", personaId)
      .order("vigente_desde", { ascending: false });
    setHistorial((data as Tramo[]) ?? []);
  }

  // "Copiar horario de →": precarga el formulario con el horario vigente de
  // otra persona. Sigue llamando a fn_set_horario_semanal solo para quien se
  // está editando — no toca a la persona de la que se copia.
  function copiarDe(personaId: string) {
    setCopiarDeId(personaId);
    if (!personaId) return;
    const h = horarios.get(personaId);
    if (!h) return;
    aplicarAnalisis(analizar(h));
  }

  function toggleDia(v: number) {
    setDias((prev) => (prev.includes(v) ? prev.filter((d) => d !== v) : [...prev, v]));
  }
  function toggleDiaPorDia(d: number) {
    setPorDia((prev) => {
      const next = { ...prev };
      if (next[d]) delete next[d];
      else next[d] = { e: entrada || "08:00", s: salida || "18:00", r: refri || 60 };
      return next;
    });
  }
  function setCampoPorDia(d: number, campo: "e" | "s", val: string) {
    setPorDia((prev) => ({ ...prev, [d]: { ...prev[d], [campo]: val } }));
  }
  function setRefriPorDia(d: number, val: string) {
    const r = Math.max(0, Math.round(Number(val) || 0));
    setPorDia((prev) => ({ ...prev, [d]: { ...prev[d], r } }));
  }
  function cambiarModo(porDiaOn: boolean) {
    if (porDiaOn) {
      const pd: PorDia = {};
      for (const d of dias) pd[d] = { e: entrada, s: salida, r: refri };
      setPorDia(pd);
    } else {
      const ds = Object.keys(porDia).map(Number).sort((a, b) => a - b);
      setDias(ds.length ? ds : [1, 2, 3, 4, 5, 6]);
      const first = ds.length ? porDia[ds[0]] : { e: entrada, s: salida, r: refri };
      setEntrada(first.e); setSalida(first.s); setRefri(first.r);
    }
    setModoPorDia(porDiaOn);
  }

  function construirHorario(): Record<string, Dia> {
    const out: Record<string, Dia> = {};
    if (modoPorDia) {
      for (const [d, v] of Object.entries(porDia)) out[d] = { e: v.e, s: v.s || v.e, r: v.r ?? 0 };
    } else {
      for (const d of dias) out[String(d)] = { e: entrada, s: salida || entrada, r: refri };
    }
    return out;
  }

  // Cambiar el horario base no toca la tabla `turnos` (fn_set_horario_semanal
  // es limpio en eso), pero puede dejar turnos puntuales VIEJOS apuntando a un
  // tramo que esta persona ya no tiene vigente — el caso de Diana (set-2026):
  // el turno del día MANDA sobre el horario base, así que un "espejo" así
  // sigue generando tardanzas falsas en silencio. Esto solo avisa; el único
  // camino para corregir sigue siendo la pantalla de Turnos, fila por fila.
  async function turnosDesactualizadosPor(supabase: ReturnType<typeof createAdminSupabaseClient>, personaId: string): Promise<string[]> {
    const { data: periodo } = await supabase.from("periodos_planilla")
      .select("fecha_ini").eq("estado", "abierto")
      .order("fecha_ini", { ascending: true }).limit(1).maybeSingle();
    // Sin periodo abierto (caso raro/borde) el piso es hoy, igual que el
    // comportamiento de siempre: no hay planilla corriendo a la que avisarle.
    const piso = periodo?.fecha_ini ?? hoyLima();
    const [{ data: turnosPersona }, { data: tramosHistoricos }] = await Promise.all([
      supabase.from("turnos").select("fecha, hora_entrada, hora_salida, es_descanso")
        .eq("persona_id", personaId).gte("fecha", piso).order("fecha"),
      // Sin filtrar vigente_hasta: hace falta el historial completo para que
      // esTurnoEspejoViejo pueda distinguir "coincide con el vigente" (nada
      // que avisar) de "coincide con uno que ya no lo es" (probable espejo).
      supabase.from("horarios_asignados")
        .select("persona_id, hora_entrada, hora_salida, dias_laborables, horario_por_dia, almuerzo_min_minutos, vigente_desde, vigente_hasta")
        .eq("persona_id", personaId),
    ]);
    const tramos = (tramosHistoricos as HorarioTramo[] | null) ?? [];
    const turnosTyped = (turnosPersona as { fecha: string; hora_entrada: string | null; hora_salida: string | null; es_descanso: boolean }[] | null) ?? [];
    return turnosTyped
      .filter((t) => esTurnoEspejoViejo(t.fecha, { hora_entrada: t.hora_entrada, hora_salida: t.hora_salida, es_descanso: t.es_descanso }, tramos))
      .map((t) => t.fecha);
  }

  async function guardar() {
    if (!editando) return;
    const horario = construirHorario();
    const keys = Object.keys(horario);
    if (keys.length === 0) { avisar("error", "Marca al menos un día de trabajo."); return; }
    const faltaEntrada = modoPorDia ? Object.values(porDia).some((v) => !v.e) : !entrada;
    const faltaSalida = modoPorDia ? Object.values(porDia).some((v) => !v.s) : !salida;
    if (faltaEntrada) { avisar("error", "Falta la hora de entrada de algún día."); return; }
    if (faltaSalida) { avisar("error", "Falta la hora de salida de algún día."); return; }
    if (motivo.trim().length < 3) { avisar("error", "Escribe el motivo del cambio (mínimo 3 caracteres)."); return; }
    const personaId = editando.id;
    setGuardando(true);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_set_horario_semanal", {
      p_persona_id: personaId, p_vigente_desde: desde, p_horario: horario, p_motivo: motivo.trim(),
    });
    setGuardando(false);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    setEditando(null);
    await cargar();
    let mensaje = "Horario guardado. Las tardanzas desde esa fecha se recalcularon.";
    try {
      const fechas = await turnosDesactualizadosPor(supabase, personaId);
      if (fechas.length > 0) {
        const esUno = fechas.length === 1;
        const turno = esUno ? "turno puntual" : "turnos puntuales";
        const coincide = esUno ? "coincide" : "coinciden";
        mensaje = `Horario guardado. Ojo: ${fechas.length} ${turno} de esta persona ya no ${coincide} con este horario (fechas: ${fechas.join(", ")}) — revísalos en la pantalla de Turnos.`;
      }
    } catch {
      // El horario ya se guardó bien; solo no se pudo avisar del cruce con turnos.
    }
    avisar("ok", mensaje);
  }

  // ── Corrección retroactiva: los mismos helpers de arriba, en su propio
  // estado (retro*) — ver el comentario junto a los useState de más arriba.
  function abrirRetro(p: Persona) {
    const a = analizar(horarios.get(p.id));
    setRetroPorDia(a.porDia);
    setRetroDias(a.dias.length ? a.dias : [1, 2, 3, 4, 5, 6]);
    setRetroEntrada(a.e);
    setRetroSalida(a.s);
    setRetroRefri(a.r);
    setRetroModoPorDia(!a.uniforme);
    setRetro(p);
    setRetroDesde(ayerLima());
    setRetroMotivo("");
    setRetroPreview(null);
  }
  function cerrarRetro() {
    setRetro(null);
    setRetroPreview(null);
    setRetroMotivo("");
  }
  function retroToggleDia(v: number) {
    setRetroDias((prev) => (prev.includes(v) ? prev.filter((d) => d !== v) : [...prev, v]));
  }
  function retroToggleDiaPorDia(d: number) {
    setRetroPorDia((prev) => {
      const next = { ...prev };
      if (next[d]) delete next[d];
      else next[d] = { e: retroEntrada || "08:00", s: retroSalida || "18:00", r: retroRefri || 60 };
      return next;
    });
  }
  function retroSetCampoPorDia(d: number, campo: "e" | "s", val: string) {
    setRetroPorDia((prev) => ({ ...prev, [d]: { ...prev[d], [campo]: val } }));
  }
  function retroSetRefriPorDia(d: number, val: string) {
    const r = Math.max(0, Math.round(Number(val) || 0));
    setRetroPorDia((prev) => ({ ...prev, [d]: { ...prev[d], r } }));
  }
  function retroCambiarModo(porDiaOn: boolean) {
    if (porDiaOn) {
      const pd: PorDia = {};
      for (const d of retroDias) pd[d] = { e: retroEntrada, s: retroSalida, r: retroRefri };
      setRetroPorDia(pd);
    } else {
      const ds = Object.keys(retroPorDia).map(Number).sort((a, b) => a - b);
      setRetroDias(ds.length ? ds : [1, 2, 3, 4, 5, 6]);
      const first = ds.length ? retroPorDia[ds[0]] : { e: retroEntrada, s: retroSalida, r: retroRefri };
      setRetroEntrada(first.e); setRetroSalida(first.s); setRetroRefri(first.r);
    }
    setRetroModoPorDia(porDiaOn);
  }
  function retroConstruirHorario(): Record<string, Dia> {
    const out: Record<string, Dia> = {};
    if (retroModoPorDia) {
      for (const [d, v] of Object.entries(retroPorDia)) out[d] = { e: v.e, s: v.s || v.e, r: v.r ?? 0 };
    } else {
      for (const d of retroDias) out[String(d)] = { e: retroEntrada, s: retroSalida || retroEntrada, r: retroRefri };
    }
    return out;
  }
  const retroFaltaEntrada = retroModoPorDia ? Object.values(retroPorDia).some((v) => !v.e) : !retroEntrada;
  const retroTotalSemana = retroModoPorDia
    ? Object.values(retroPorDia).reduce((acc, v) => acc + horasDia(v.e, v.s, v.r), 0)
    : horasDia(retroEntrada, retroSalida, retroRefri) * retroDias.length;
  const rangoRetroDemasiadoLargo = diasEntreLima(retroDesde, hoyLima()) > MAX_DIAS_RETROACTIVO;

  async function verQueCambiaria() {
    if (!retro) return;
    const horario = retroConstruirHorario();
    if (Object.keys(horario).length === 0) { avisar("error", "Marca al menos un día de trabajo."); return; }
    if (retroFaltaEntrada) { avisar("error", "Falta la hora de entrada de algún día."); return; }
    if (rangoRetroDemasiadoLargo) { avisar("error", `Elige una fecha dentro de los últimos ${MAX_DIAS_RETROACTIVO} días — revisa que sea la correcta.`); return; }
    setRetroPreviewCargando(true);
    setRetroPreview(null);
    const supabase = createAdminSupabaseClient();
    const { data, error } = await supabase.rpc("fn_horario_retroactivo_preview", {
      p_persona_id: retro.id, p_horario: horario, p_vigente_desde: retroDesde,
    });
    setRetroPreviewCargando(false);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    setRetroPreview((data as FilaPreview[]) ?? []);
  }

  async function confirmarRetro() {
    if (!retro) return;
    if (!retroMotivo || retroMotivo.trim().length < 3) { avisar("error", "El motivo es obligatorio (mínimo 3 caracteres)."); return; }
    const horario = retroConstruirHorario();
    setRetroConfirmando(true);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_corregir_horario_retroactivo", {
      p_persona_id: retro.id, p_horario: horario, p_vigente_desde: retroDesde, p_motivo: retroMotivo.trim(),
    });
    setRetroConfirmando(false);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    cerrarRetro();
    await cargar();
    avisar("ok", "Corrección retroactiva aplicada. Las jornadas del rango quedaron recalculadas y la corrección quedó auditada.");
  }

  if (rol !== null && !puedeEditar) {
    return (
      <div className="flex flex-1 flex-col">
        <main className="flex flex-1 items-center justify-center p-6">
          <p className="max-w-md text-center text-taupe">No tienes permiso para editar horarios.</p>
        </main>
      </div>
    );
  }

  const todasLasSedes = [...new Set(editables.map((p) => sedes[p.sede_base_id] ?? "?"))].sort();
  const sinHorario = filtrados.filter((p) => !horarios.has(p.id));
  const porSede = [...new Set(filtrados.map((p) => sedes[p.sede_base_id] ?? "?"))].sort();

  // total semanal del formulario abierto
  const totalSemana = modoPorDia
    ? Object.values(porDia).reduce((acc, v) => acc + horasDia(v.e, v.s, v.r), 0)
    : horasDia(entrada, salida, refri) * dias.length;

  const bloqueadoPorExpediente = (retroPreview ?? []).find((f) => f.tiene_expediente_formal);
  const filasConCambio = (retroPreview ?? []).filter(
    (f) => f.minutos_tarde_actual !== f.minutos_tarde_nuevo
      || f.minutos_salida_temprana_actual !== f.minutos_salida_temprana_nuevo
      || f.horas_extra_actual !== f.horas_extra_nuevo,
  );

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6">
        <h1 className="mb-1 font-serif text-2xl">Horarios base</h1>
        <p className="mb-5 max-w-2xl text-sm text-taupe">
          El horario de cada persona puede tener una hora distinta por día (martes 8:00, miércoles 14:00…),
          con su refrigerio, y se repite cada semana. La hora de entrada define la tardanza. Al cambiar un
          horario, elige la fecha desde la que aplica — el anterior se conserva y no altera tardanzas pasadas.
        </p>

        {!cargando && personas.length > 0 && (
          <div className="mb-5 grid grid-cols-1 gap-2 sm:grid-cols-[1fr_auto_auto]">
            <div className="relative">
              <Search size={15} strokeWidth={1.8} aria-hidden className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-taupe" />
              <input
                value={busca}
                onChange={(e) => setBusca(e.target.value)}
                placeholder="Buscar por nombre…"
                aria-label="Buscar por nombre"
                className="w-full rounded-lg border border-sand bg-hueso py-2 pl-9 pr-9 text-sm placeholder:text-taupe/60"
              />
              {busca && (
                <button onClick={() => setBusca("")} aria-label="Limpiar búsqueda" className="absolute right-2 top-1/2 -translate-y-1/2 px-1 leading-none text-taupe hover:text-tinta">
                  ×
                </button>
              )}
            </div>
            <CampoSelect value={filtroSede} onChange={(e) => setFiltroSede(e.target.value)} aria-label="Filtrar por sede">
              <option value="">Todas las sedes</option>
              {todasLasSedes.map((sd) => <option key={sd} value={sd}>{sd}</option>)}
            </CampoSelect>
            <CampoSelect value={filtroTipo} onChange={(e) => setFiltroTipo(e.target.value as typeof filtroTipo)} aria-label="Filtrar por tipo de horario">
              <option value="">Cualquier tipo</option>
              <option value="sin_horario">Sin horario hoy</option>
              <option value="fijo">Rango fijo</option>
              <option value="varia">Varía por día</option>
            </CampoSelect>
          </div>
        )}

        {/* Cruza las 4 sedes: sin esto, alguien "sin horario" se pierde bajando
            entre AQP/CCO/LIM/TRU y puede marcar días sin que ninguna tardanza
            se calcule (auditoría 2026-09-14). */}
        {!cargando && sinHorario.length > 0 && (
          <div className="mb-6 rounded-control border border-rojo/30 bg-rojo/10 px-4 py-3">
            <p className="mb-2 text-sm font-medium text-rojo-profundo">
              Sin horario asignado ({sinHorario.length})
            </p>
            <ul className="flex flex-wrap gap-x-4 gap-y-1.5">
              {sinHorario.map((p) => (
                <li key={p.id} className="flex items-center gap-2 text-sm text-tinta">
                  {p.nombres} {p.apellidos}
                  <Boton variante="secundario" tamano="sm" onClick={() => abrirEdicion(p)}>Asignar</Boton>
                </li>
              ))}
            </ul>
          </div>
        )}

        {cargando ? <Cargando /> : porSede.length === 0 ? (
          <p className="text-sm text-taupe">Ninguna persona coincide con la búsqueda o los filtros.</p>
        ) : porSede.map((sede) => {
          const deSede = filtrados.filter((p) => (sedes[p.sede_base_id] ?? "?") === sede);
          return (
            <section key={sede} className="mb-8">
              <h2 className="mb-2 font-serif text-lg">{sede}</h2>
              <Tabla className="[font-variant-numeric:tabular-nums]">
                <TablaEncabezado>
                  <Th>Nombre</Th>
                  <Th>Horario</Th>
                  <Th>Semana</Th>
                  <Th>Descanso</Th>
                  <Th>Vigente desde</Th>
                  <Th>{null}</Th>
                </TablaEncabezado>
                <tbody>
                  {deSede.map((p) => {
                    const abierto = horarios.get(p.id);
                    const programado = !!abierto && abierto.vigente_desde > hoy;
                    const h = horarioDeHoy(p);
                    const a = h ? analizar(h) : null;
                    const semana = a ? a.dias.reduce((acc, d) => acc + horasDia(a.porDia[d].e, a.porDia[d].s, a.porDia[d].r), 0) : 0;
                    // Máximo legal de una practicante (0324, art. 44 Ley 28518). `null`
                    // para cualquiera que no sea practicante, o que lo sea pero sin
                    // modalidad fijada todavía — en los dos casos no hay contra qué avisar.
                    const maxLegal = maximoSemanalPracticante(p.tipo_vinculo, p.practicante_modalidad);
                    const seExcede = maxLegal !== null && a && a.dias.length > 0 && semana > maxLegal + 0.01;
                    return (
                      <Fila key={p.id}>
                        <td className="px-4 py-2">{p.nombres} {p.apellidos}</td>
                        <td className="px-4 py-2">
                          {!a || a.dias.length === 0 ? <span className="text-taupe">sin horario{programado ? " hoy" : ""}</span>
                            : a.uniforme ? `${a.e}–${a.s}` : <span className="text-taupe">varía por día</span>}
                        </td>
                        <td className="px-4 py-2 text-taupe">
                          {a && a.dias.length ? fmtH(semana) : "—"}
                          {seExcede && (
                            // El título con la cita legal se conserva envolviendo la
                            // Insignia: el primitivo no reenvía props sueltas como
                            // `title` (ver components/ui/insignia.tsx).
                            <span title={`Supera el máximo legal de ${maxLegal} h/semana de una practicante ${p.practicante_modalidad} (art. 44, Ley 28518)`}>
                              <Insignia variante="alerta" className="ml-1.5">supera {maxLegal} h legales</Insignia>
                            </span>
                          )}
                          {maxLegal === null && p.tipo_vinculo === "practicante" && !p.practicante_modalidad && (
                            <span title="Sin modalidad fijada en Equipo, no se puede avisar de su máximo legal">
                              <Insignia variante="advertencia" className="ml-1.5">falta su modalidad</Insignia>
                            </span>
                          )}
                        </td>
                        <td className="px-4 py-2 text-taupe">{a ? textoDescanso(a.dias) : "—"}</td>
                        <td className="px-4 py-2 text-taupe">
                          {abierto ? abierto.vigente_desde : "—"}
                          {programado && (
                            <span title={`Este horario recién rige desde el ${abierto!.vigente_desde}. Hasta entonces sigue aplicando el de arriba.`}>
                              <Insignia variante="informativo" className="ml-1.5">Programado</Insignia>
                            </span>
                          )}
                        </td>
                        <td className="px-4 py-2">
                          <div className="flex items-center justify-end gap-3">
                            <Boton variante="secundario" tamano="sm" onClick={() => abrirEdicion(p)}>
                              {abierto ? "Cambiar" : "Asignar"}
                            </Boton>
                            <Boton variante="enlace" tamano="sm" onClick={() => abrirRetro(p)} title="El cambio ya ocurrió hace unos días y recién se registra hoy">
                              corregir pasado
                            </Boton>
                          </div>
                        </td>
                      </Fila>
                    );
                  })}
                </tbody>
              </Tabla>
            </section>
          );
        })}

        {/* ── Cambio normal: siempre hacia adelante (0444) ──────────────────── */}
        <Modal
          abierto={editando !== null}
          onCerrar={() => setEditando(null)}
          bloqueado={guardando}
          titulo={editando ? `Horario de ${editando.nombres} ${editando.apellidos}` : undefined}
        >
          <p className="mb-4 text-sm text-taupe">El nuevo horario aplica desde la fecha que elijas en adelante.</p>

          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <Campo etiqueta="Vigente desde" type="date" min={hoyLima()} value={desde} onChange={(e) => setDesde(e.target.value)} />
            <CampoSelect etiqueta="Copiar horario de →" value={copiarDeId} onChange={(e) => copiarDe(e.target.value)}>
              <option value="">(elegir a alguien)</option>
              {editables
                .filter((x) => x.id !== editando?.id && horarios.has(x.id))
                .map((x) => (
                  <option key={x.id} value={x.id}>{x.nombres} {x.apellidos}</option>
                ))}
            </CampoSelect>
          </div>
          <p className="mt-1 text-xs text-taupe">
            ¿El cambio ya ocurrió hace días? Esto ya no acepta una fecha pasada — cierra este modal y usa
            «corregir pasado» junto al nombre.
          </p>

          {historial.length > 1 && (
            <details className="mt-3 rounded-control bg-hueso px-3 py-2 text-sm">
              {/* El primer tramo de `historial` (orden desc por vigente_desde) es
                  siempre el vigente — ya está a la vista en el formulario de
                  arriba, por eso la lista arranca en el segundo. */}
              <summary className="cursor-pointer text-taupe">Ver horarios anteriores ({historial.length - 1})</summary>
              <ul className="mt-2 flex flex-col gap-1.5">
                {historial.slice(1).map((t) => {
                  const at = analizar(t);
                  const resumen = at.dias.length === 0 ? "sin días"
                    : at.uniforme ? `${at.e}–${at.s}, ${textoDescanso(at.dias)}` : "varía por día";
                  return (
                    <li key={`${t.vigente_desde}-${t.vigente_hasta ?? "abierto"}`} className="text-xs text-taupe">
                      <span className="text-tinta">{t.vigente_desde}</span> – {t.vigente_hasta ?? "hoy"} · {resumen}
                    </li>
                  );
                })}
              </ul>
            </details>
          )}

          <label className="mt-4 flex items-center gap-2 text-sm">
            {/* Casilla suelta: todavía no existe <CampoCasilla> en
                components/ui/campo.tsx (Fase A no la agregó pese a lo
                anunciado) — se deja con las clases que ese primitivo va a
                necesitar (accent-tinta, size-4) para que migrar sea trivial
                en cuanto exista. */}
            <input type="checkbox" checked={!modoPorDia} onChange={(e) => cambiarModo(!e.target.checked)} className="size-4 rounded border-sand accent-tinta" />
            Misma hora todos los días
          </label>

          {!modoPorDia ? (
            <>
              {/* grid-cols-1 en el teléfono: con grid-cols-3 fijo, a 375px cada
                  columna quedaba en ~85px y el input[type=time] nativo (que
                  necesita dibujar "--:--" y, en iOS, el indicador am/pm) se
                  recortaba — justo en el campo que fija la hora de entrada,
                  la que decide si a alguien se le cuenta una tardanza. */}
              <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-3">
                <Campo etiqueta="Entrada" type="time" value={entrada} onChange={(e) => setEntrada(e.target.value)} />
                <Campo etiqueta="Salida" type="time" value={salida} onChange={(e) => setSalida(e.target.value)} />
                <CampoSelect etiqueta="Refrigerio" value={refri} onChange={(e) => setRefri(Number(e.target.value))}>
                  {opcionesRefrigerio(refri).map((m) => <option key={m} value={m}>{m} min</option>)}
                </CampoSelect>
              </div>
              <p className="mt-2 text-xs text-taupe">Cada día: <span className="text-tinta">{fmtH(horasDia(entrada, salida, refri))}</span></p>
              <div className="mt-3">
                <p className="mb-1.5 text-sm">Días de trabajo <span className="text-taupe">(los que no marcas son descanso)</span></p>
                <div className="flex gap-1.5">
                  {DIAS.map((d) => {
                    const on = dias.includes(d.v);
                    return (
                      <button key={d.v} type="button" onClick={() => toggleDia(d.v)}
                        className={`h-9 w-9 rounded-control border text-sm ${on ? "border-tinta bg-tinta text-crema" : "border-sand text-taupe hover:bg-sand/40"}`}>
                        {d.l}
                      </button>
                    );
                  })}
                </div>
                <p className="mt-1.5 text-xs text-taupe">Descanso: {textoDescanso(dias)}</p>
              </div>
            </>
          ) : (
            <div className="mt-3">
              <p className="mb-2 text-sm">Horario por día <span className="text-taupe">(apaga el día para descanso)</span></p>
              <div className="flex flex-col gap-1.5">
                {DIAS.map((d) => {
                  const dd = porDia[d.v];
                  const activo = dd !== undefined;
                  return (
                    <div key={d.v} className="flex flex-wrap items-center gap-1.5">
                      <button type="button" onClick={() => toggleDiaPorDia(d.v)}
                        className={`h-8 w-14 shrink-0 rounded-control border text-xs capitalize ${activo ? "border-tinta bg-tinta text-crema" : "border-sand text-taupe hover:bg-sand/40"}`}>
                        {NOMBRE_DIA[d.v].slice(0, 3)}
                      </button>
                      {activo ? (
                        <>
                          <input type="time" value={dd.e} onChange={(e) => setCampoPorDia(d.v, "e", e.target.value)} className="w-[90px] rounded-control border px-1.5 py-1 text-sm" />
                          <span className="text-taupe">–</span>
                          <input type="time" value={dd.s} onChange={(e) => setCampoPorDia(d.v, "s", e.target.value)} className="w-[90px] rounded-control border px-1.5 py-1 text-sm" />
                          <select value={dd.r} onChange={(e) => setRefriPorDia(d.v, e.target.value)} title="refrigerio (min)" className="w-16 rounded-control border border-sand bg-hueso px-1 py-1 text-sm">
                            {opcionesRefrigerio(dd.r).map((m) => <option key={m} value={m}>{m}</option>)}
                          </select>
                          <span className="w-14 text-right text-xs text-tinta">{fmtH(horasDia(dd.e, dd.s, dd.r))}</span>
                        </>
                      ) : <span className="text-sm text-taupe">descanso</span>}
                    </div>
                  );
                })}
              </div>
              <p className="mt-1.5 text-xs text-taupe">La columna angosta es el refrigerio en minutos.</p>
            </div>
          )}

          {(() => {
            // Para una practicante, "meta 45h" no significa nada: lo que
            // importa es si se pasa del MÁXIMO LEGAL de su modalidad
            // (0324, art. 44 Ley 28518) — un número muy distinto de la
            // meta genérica de jornada del resto del equipo, y que si se
            // cruza no es un objetivo de más, es una jornada que no le
            // corresponde por ley.
            const maxLegal = editando ? maximoSemanalPracticante(editando.tipo_vinculo, editando.practicante_modalidad) : null;
            if (maxLegal !== null) {
              const seExcede = totalSemana > maxLegal + 0.01;
              return (
                <div className={`mt-4 rounded-control px-3 py-2 text-sm ${seExcede ? "bg-rojo/10" : "bg-sand/30"}`}>
                  Total semana: <span className="font-medium text-tinta">{fmtH(totalSemana)}</span>
                  <span className="text-taupe"> · máximo legal {maxLegal} h ({editando?.practicante_modalidad})</span>
                  {seExcede && (
                    <span className="text-rojo"> — supera el máximo del art. 44, Ley 28518, por {fmtH(totalSemana - maxLegal)}</span>
                  )}
                </div>
              );
            }
            if (editando?.tipo_vinculo === "practicante") {
              return (
                <div className="mt-4 rounded-control bg-ambar/10 px-3 py-2 text-sm text-ambar">
                  Total semana: {fmtH(totalSemana)} — falta fijarle la modalidad en Equipo (preprofesional o
                  profesional) para poder avisar si esto supera su máximo legal.
                </div>
              );
            }
            return (
              <div className="mt-4 rounded-control bg-sand/30 px-3 py-2 text-sm">
                Total semana: <span className="font-medium text-tinta">{fmtH(totalSemana)}</span>
                <span className="text-taupe"> · meta {META_SEMANA} h</span>
                {totalSemana > META_SEMANA + 0.01 && <span className="text-ambar"> (te pasas {fmtH(totalSemana - META_SEMANA)})</span>}
                {totalSemana < META_SEMANA - 0.01 && <span className="text-taupe"> (faltan {fmtH(META_SEMANA - totalSemana)})</span>}
              </div>
            );
          })()}

          <div className="mt-4">
            <AreaTexto
              etiqueta="Motivo del cambio"
              value={motivo}
              onChange={(e) => setMotivo(e.target.value)}
              placeholder="Por qué cambia — ej. lo pidió para estudiar, ajuste operativo de la sede…"
            />
          </div>

          <div className="mt-5 flex justify-end gap-3">
            <Boton variante="secundario" onClick={() => setEditando(null)} disabled={guardando}>Cancelar</Boton>
            <Boton variante="primario" onClick={guardar} cargando={guardando}>Guardar horario</Boton>
          </div>
        </Modal>

        {/* ── Corrección retroactiva (0447): aparte, con motivo y vista previa ── */}
        <Modal
          abierto={retro !== null}
          onCerrar={cerrarRetro}
          bloqueado={retroPreviewCargando || retroConfirmando}
          ancho="lg"
          titulo={retro ? `Corregir el horario pasado de ${retro.nombres} ${retro.apellidos}` : undefined}
        >
          <p className="mb-4 text-sm text-taupe">
            Para cuando el cambio de horario <strong className="text-tinta">de verdad ocurrió hace días</strong> y
            recién se registra hoy. Antes de guardar, revisa qué jornadas cambiarían — esto queda auditado con tu
            motivo.
          </p>

          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <Campo
              etiqueta="Vigente desde (una fecha pasada)"
              type="date"
              max={ayerLima()}
              value={retroDesde}
              onChange={(e) => { setRetroDesde(e.target.value); setRetroPreview(null); }}
            />
          </div>
          {rangoRetroDemasiadoLargo && (
            <p className="mt-1.5 text-xs text-rojo">
              Eso es más de {MAX_DIAS_RETROACTIVO} días atrás — revisa que la fecha sea la correcta.
            </p>
          )}

          <label className="mt-4 flex items-center gap-2 text-sm">
            <input type="checkbox" checked={!retroModoPorDia} onChange={(e) => retroCambiarModo(!e.target.checked)} className="size-4 rounded border-sand accent-tinta" />
            Misma hora todos los días
          </label>

          {!retroModoPorDia ? (
            <>
              <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-3">
                <Campo etiqueta="Entrada" type="time" value={retroEntrada} onChange={(e) => setRetroEntrada(e.target.value)} />
                <Campo etiqueta="Salida" type="time" value={retroSalida} onChange={(e) => setRetroSalida(e.target.value)} />
                <CampoSelect etiqueta="Refrigerio" value={retroRefri} onChange={(e) => setRetroRefri(Number(e.target.value))}>
                  {opcionesRefrigerio(retroRefri).map((m) => <option key={m} value={m}>{m} min</option>)}
                </CampoSelect>
              </div>
              <p className="mt-2 text-xs text-taupe">Cada día: <span className="text-tinta">{fmtH(horasDia(retroEntrada, retroSalida, retroRefri))}</span></p>
              <div className="mt-3">
                <p className="mb-1.5 text-sm">Días de trabajo <span className="text-taupe">(los que no marcas son descanso)</span></p>
                <div className="flex gap-1.5">
                  {DIAS.map((d) => {
                    const on = retroDias.includes(d.v);
                    return (
                      <button key={d.v} type="button" onClick={() => retroToggleDia(d.v)}
                        className={`h-9 w-9 rounded-control border text-sm ${on ? "border-tinta bg-tinta text-crema" : "border-sand text-taupe hover:bg-sand/40"}`}>
                        {d.l}
                      </button>
                    );
                  })}
                </div>
                <p className="mt-1.5 text-xs text-taupe">Descanso: {textoDescanso(retroDias)}</p>
              </div>
            </>
          ) : (
            <div className="mt-3">
              <p className="mb-2 text-sm">Horario por día <span className="text-taupe">(apaga el día para descanso)</span></p>
              <div className="flex flex-col gap-1.5">
                {DIAS.map((d) => {
                  const dd = retroPorDia[d.v];
                  const activo = dd !== undefined;
                  return (
                    <div key={d.v} className="flex flex-wrap items-center gap-1.5">
                      <button type="button" onClick={() => retroToggleDiaPorDia(d.v)}
                        className={`h-8 w-14 shrink-0 rounded-control border text-xs capitalize ${activo ? "border-tinta bg-tinta text-crema" : "border-sand text-taupe hover:bg-sand/40"}`}>
                        {NOMBRE_DIA[d.v].slice(0, 3)}
                      </button>
                      {activo ? (
                        <>
                          <input type="time" value={dd.e} onChange={(e) => retroSetCampoPorDia(d.v, "e", e.target.value)} className="w-[90px] rounded-control border px-1.5 py-1 text-sm" />
                          <span className="text-taupe">–</span>
                          <input type="time" value={dd.s} onChange={(e) => retroSetCampoPorDia(d.v, "s", e.target.value)} className="w-[90px] rounded-control border px-1.5 py-1 text-sm" />
                          <select value={dd.r} onChange={(e) => retroSetRefriPorDia(d.v, e.target.value)} title="refrigerio (min)" className="w-16 rounded-control border border-sand bg-hueso px-1 py-1 text-sm">
                            {opcionesRefrigerio(dd.r).map((m) => <option key={m} value={m}>{m}</option>)}
                          </select>
                          <span className="w-14 text-right text-xs text-tinta">{fmtH(horasDia(dd.e, dd.s, dd.r))}</span>
                        </>
                      ) : <span className="text-sm text-taupe">descanso</span>}
                    </div>
                  );
                })}
              </div>
              <p className="mt-1.5 text-xs text-taupe">La columna angosta es el refrigerio en minutos.</p>
            </div>
          )}

          <div className="mt-4 rounded-control bg-sand/30 px-3 py-2 text-sm">
            Total semana: <span className="font-medium text-tinta">{fmtH(retroTotalSemana)}</span>
            <span className="text-taupe"> · meta {META_SEMANA} h</span>
          </div>

          <div className="mt-4">
            <AreaTexto
              etiqueta="Motivo (obligatorio)"
              value={retroMotivo}
              onChange={(e) => { setRetroMotivo(e.target.value); }}
              placeholder="Por qué se corrige con vigencia pasada — por ejemplo: el horario cambió el lunes en la sede, recién se registra hoy."
            />
          </div>

          <div className="mt-4 flex justify-end">
            <Boton variante="secundario" onClick={verQueCambiaria} cargando={retroPreviewCargando} disabled={rangoRetroDemasiadoLargo}>
              Ver qué cambiaría
            </Boton>
          </div>

          {retroPreview && (
            <div className="mt-4 border-t border-sand pt-4">
              {retroPreview.length === 0 ? (
                <p className="text-sm text-taupe">No hay ninguna jornada en ese rango — no hay nada que recalcular.</p>
              ) : (
                <>
                  <p className="mb-2 text-sm">
                    <span className="font-medium text-tinta">{filasConCambio.length}</span> de {retroPreview.length}
                    {" "}día(s) del rango cambiarían.
                  </p>
                  {bloqueadoPorExpediente && (
                    <div className="mb-3 rounded-control bg-rojo/10 px-3 py-2 text-sm text-rojo">
                      El {bloqueadoPorExpediente.fecha} ya tiene un expediente disciplinario firmado o entregado.
                      No se puede confirmar esta corrección mientras ese expediente siga así — resuélvelo o
                      anúlalo en Disciplina primero.
                    </div>
                  )}
                  {filasConCambio.length > 0 && (
                    <Tabla className="mb-3 [font-variant-numeric:tabular-nums]">
                      <TablaEncabezado>
                        <Th>Fecha</Th>
                        <Th>Tardanza</Th>
                        <Th>Salida antic.</Th>
                        <Th>Tiempo extra</Th>
                        <Th>{null}</Th>
                      </TablaEncabezado>
                      <tbody>
                        {filasConCambio.map((f) => (
                          <Fila key={f.fecha}>
                            <td className="px-4 py-2">{f.fecha}</td>
                            <td className="px-4 py-2">{f.minutos_tarde_actual ?? 0} → <span className="text-tinta">{f.minutos_tarde_nuevo ?? 0} min</span></td>
                            <td className="px-4 py-2">{f.minutos_salida_temprana_actual ?? 0} → <span className="text-tinta">{f.minutos_salida_temprana_nuevo ?? 0} min</span></td>
                            <td className="px-4 py-2">{f.horas_extra_actual ?? 0} → <span className="text-tinta">{f.horas_extra_nuevo ?? 0} h</span></td>
                            <td className="px-4 py-2">
                              {f.tiene_expediente_formal && <Insignia variante="alerta">expediente formal</Insignia>}
                            </td>
                          </Fila>
                        ))}
                      </tbody>
                    </Tabla>
                  )}
                </>
              )}
            </div>
          )}

          <div className="mt-5 flex justify-end gap-3">
            <Boton variante="secundario" onClick={cerrarRetro} disabled={retroConfirmando}>Cancelar</Boton>
            <Boton
              variante="primario"
              onClick={confirmarRetro}
              cargando={retroConfirmando}
              disabled={!retroPreview || !!bloqueadoPorExpediente || retroMotivo.trim().length < 3}
            >
              Confirmar corrección
            </Boton>
          </div>
        </Modal>
      </main>
    </div>
  );
}
