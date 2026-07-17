"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { AREA_DEFAULT, AREAS_FALLBACK, parseAreas, areaCorto, esOperativaEn, type Area } from "@/lib/areas";
import { AdminNav } from "../nav";

// ── Fechas (todo en ISO yyyy-mm-dd, semana de lunes a domingo) ──────────────
function hoyLima(): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Lima" }).format(new Date());
}
function parseISO(iso: string): Date {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d));
}
function toISO(dt: Date): string {
  return dt.toISOString().slice(0, 10);
}
function addDays(iso: string, n: number): string {
  const d = parseISO(iso);
  d.setUTCDate(d.getUTCDate() + n);
  return toISO(d);
}
function diaSemana(iso: string): number {
  return parseISO(iso).getUTCDay(); // 0=domingo … 6=sábado
}
function lunesDeLaSemana(iso: string): string {
  const dow = diaSemana(iso);
  return addDays(iso, dow === 0 ? -6 : 1 - dow);
}
const DIAS_ABR = ["Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"];
const MESES = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];
function etiquetaDia(iso: string): { abr: string; num: string } {
  const d = parseISO(iso);
  return { abr: DIAS_ABR[d.getUTCDay()], num: `${d.getUTCDate()} ${MESES[d.getUTCMonth()]}` };
}

interface Persona { id: string; nombres: string; apellidos: string; rol: string; funcion: string; }
interface Horario { hora_entrada: string; hora_salida: string; dias_laborables: number[]; horario_por_dia: Record<string, { e: string; s: string; r?: number }> | null; vigente_desde: string; vigente_hasta: string | null; }
// De los tramos de una persona, el vigente en `fecha` (mismo criterio que fn_recalcular_jornada).
function tramoVigente(lista: Horario[] | undefined, fecha: string): Horario | undefined {
  if (!lista) return undefined;
  return lista
    .filter((h) => h.vigente_desde <= fecha && (h.vigente_hasta == null || h.vigente_hasta >= fecha))
    .sort((a, b) => (a.vigente_desde < b.vigente_desde ? 1 : -1))[0];
}
interface Turno { es_descanso: boolean; hora_entrada: string | null; hora_salida: string | null; }
interface Sede { id: string; codigo: string; nombre: string }

type Celda =
  | { tipo: "turno"; entrada: string; salida: string | null; refrigerio?: number }
  | { tipo: "default"; entrada: string; salida: string | null; refrigerio?: number }
  | { tipo: "descanso" }
  | { tipo: "libre" };

const ROLES_ADMIN = ["admin", "lider_do"];
const hhmm = (t?: string | null) => (t ? t.slice(0, 5) : "");

// ── Línea de tiempo / mapa de calor de cobertura (7h–21h) ───────────────────
const HORA_INICIO = 7;
const HORA_FIN = 21;
const MARCAS_HORA = [7, 9, 11, 13, 15, 17, 19, 21];
// Vista Semana: franjas de 30 min ancladas a :15/:45 (7:45, 8:15, 8:45…), igual
// que las horas de entrada reales del equipo — fijo, no automático (decisión
// de Felipe: más simple y predecible que recalcularlo cada vez).
const HORA_INICIO_SEMANA = 7.75; // 07:45
const N_FRANJAS_SEMANA = 27; // hasta 21:15
function horaADecimal(hm: string): number {
  const [h, m] = hm.split(":").map(Number);
  return (h ?? 0) + (m ?? 0) / 60;
}
// % horizontal dentro del rango visible, recortado a [0, 100] para turnos que
// empiezan antes de las 7 o terminan después de las 21.
function pctEnRango(horaDec: number): number {
  return Math.min(100, Math.max(0, ((horaDec - HORA_INICIO) / (HORA_FIN - HORA_INICIO)) * 100));
}
// Rojo (#b8412d) → Verde (#5f7a52) según qué tan cerca está de la meta; a partir
// de la meta queda verde sólido (el excedente ya no necesita más degradado).
const ROJO_RGB: [number, number, number] = [184, 65, 45];
const VERDE_RGB: [number, number, number] = [95, 122, 82];
function colorCobertura(n: number, meta: number): string {
  const ratio = meta > 0 ? Math.min(n / meta, 1) : Math.min(n / 6, 1);
  const [r, g, b] = ROJO_RGB.map((c0, i) => Math.round(c0 + (VERDE_RGB[i] - c0) * ratio));
  return `rgb(${r}, ${g}, ${b})`;
}
// Degradado continuo (sin cuadritos) para la franja de cobertura: un color por
// hora, con el punto de color anclado al MEDIO de cada hora para que el
// degradado se sienta suave en vez de a bloques.
function gradienteCobertura(horas: number[], meta: number): string {
  const n = horas.length;
  const paradas = horas.map((h, i) => `${colorCobertura(h, meta)} ${((i + 0.5) / n) * 100}%`);
  return `linear-gradient(to right, ${colorCobertura(horas[0], meta)} 0%, ${paradas.join(", ")}, ${colorCobertura(horas[n - 1], meta)} 100%)`;
}
// ── Silueta del día (Vista Semana): la forma de cuánta gente hay por hora ────
// El área rellena es la cobertura; el área roja entre la línea de cobertura y la
// meta es el DÉFICIT (lo que falta) — se ve el hueco, no solo un número.
const SIL_W = 100, SIL_BASE = 46, SIL_TOP = 6;
function siluetaSVG(cov: number[], meta: number, maxY: number) {
  const n = cov.length;
  const yF = (v: number) => SIL_BASE - (v / maxY) * (SIL_BASE - SIL_TOP);
  const xF = (i: number) => (i / (n - 1)) * SIL_W;
  let area = `M ${xF(0)} ${SIL_BASE}`;
  for (let i = 0; i < n; i++) area += ` L ${xF(i).toFixed(1)} ${yF(cov[i]).toFixed(1)}`;
  area += ` L ${xF(n - 1)} ${SIL_BASE} Z`;
  let line = "";
  for (let i = 0; i < n; i++) line += (i ? " L " : "M ") + `${xF(i).toFixed(1)} ${yF(cov[i]).toFixed(1)}`;
  let deficit = "";
  if (meta > 0) {
    let t = "", b = "";
    for (let i = 0; i < n; i++) t += (i ? " L " : "M ") + `${xF(i).toFixed(1)} ${yF(meta).toFixed(1)}`;
    for (let i = n - 1; i >= 0; i--) b += ` L ${xF(i).toFixed(1)} ${yF(Math.min(cov[i], meta)).toFixed(1)}`;
    deficit = t + b + " Z";
  }
  return { area, line, deficit, metaY: yF(meta) };
}
// El momento más flojo del día en HORAS CENTRALES (10:00–19:45), para los
// puntitos. Se saltan el arranque y el cierre (franjas del inicio/fin) porque
// ahí siempre hay menos gente por el ramp-up natural — si contáramos eso, TODOS
// los días se verían cortos y el indicador perdería su señal. Pero un hueco real
// de media tarde (ej. domingo sin nadie) sí cae dentro de esta ventana y se
// refleja. Índices anclados a reloj sobre franjas de 0.5h desde HORA_INICIO_SEMANA.
const FR_CORE_INI = Math.round((10 - HORA_INICIO_SEMANA) / 0.5);
const FR_CORE_FIN = Math.round((19.75 - HORA_INICIO_SEMANA) / 0.5);
function minEnHorario(cov: number[]): number {
  const core = cov.slice(FR_CORE_INI, FR_CORE_FIN + 1);
  return core.length ? Math.min(...core) : 0;
}

export default function TurnosPage() {
  const router = useRouter();
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;
  const esAdmin = rol === "admin" || rol === "lider_do";
  const puedeVer = esAdmin || rol === "supervisor_sede";

  const [sedes, setSedes] = useState<Sede[]>([]);
  const [sedeSel, setSedeSel] = useState<string>("");
  const [lunes, setLunes] = useState<string>(() => lunesDeLaSemana(hoyLima()));
  // Vista Día (línea de tiempo por persona) o Vista Semana (mapa de calor
  // hora × día, para comparar cobertura entre los 7 días de un vistazo).
  // Recuerda la preferencia entre visitas.
  const [vista, setVista] = useState<"dia" | "semana">(() => {
    if (typeof window === "undefined") return "dia";
    return (localStorage.getItem("turnos_vista") as "dia" | "semana" | null) ?? "dia";
  });
  useEffect(() => { localStorage.setItem("turnos_vista", vista); }, [vista]);
  // Clic en una celda de Vista Semana → salta a Vista Día y hace scroll a ese
  // día específico (se limpia solo después de saltar, para no repetir el
  // scroll si luego el usuario navega manualmente dentro de Vista Día).
  const [diaFoco, setDiaFoco] = useState<string | null>(null);
  function irADia(iso: string) {
    setDiaFoco(iso);
    setVista("dia");
  }
  useEffect(() => {
    if (vista !== "dia" || !diaFoco) return;
    const el = document.getElementById(`turnos-dia-${diaFoco}`);
    el?.scrollIntoView({ behavior: "smooth", block: "start" });
    setDiaFoco(null);
  }, [vista, diaFoco]);

  const [personas, setPersonas] = useState<Persona[]>([]);
  const [areas, setAreas] = useState<Area[]>(AREAS_FALLBACK);
  const [funcionesFallo, setFuncionesFallo] = useState(false);
  const [horarios, setHorarios] = useState<Map<string, Horario[]>>(new Map());
  const [turnos, setTurnos] = useState<Map<string, Turno>>(new Map());
  const [metas, setMetas] = useState<Map<number, number>>(new Map());
  const [metasEncargadas, setMetasEncargadas] = useState<Map<number, number>>(new Map());
  const [cargando, setCargando] = useState(true);
  const [msg, setMsg] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);

  // edición de celda
  const [edit, setEdit] = useState<{ personaId: string; fecha: string } | null>(null);
  const [entrada, setEntrada] = useState("");
  const [salida, setSalida] = useState("");
  const [guardando, setGuardando] = useState(false);

  const dias = useMemo(() => Array.from({ length: 7 }, (_, i) => addDays(lunes, i)), [lunes]);
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const reqId = useRef(0); // "última carga gana": descarta respuestas fuera de orden

  // Deep-link: al llegar con ?fecha=<YYYY-MM-DD> (desde Incidencias, ej. déficit
  // de encargadas), salta directo a la semana de esa fecha.
  useEffect(() => {
    const sp = new URLSearchParams(window.location.search);
    const f = sp.get("fecha");
    if (f) setLunes(lunesDeLaSemana(f));
  }, []);

  // sedes + sede inicial
  useEffect(() => {
    supabase.auth.getSession().then(async ({ data }) => {
      if (!data.session) { router.replace("/admin/login"); return; }
      const { data: s } = await supabase.from("sedes").select("id, codigo, nombre").order("codigo");
      const lista = (s as Sede[]) ?? [];
      setSedes(lista);
      // La encargada queda FIJA en su sede (su selector está oculto): forzamos su sede
      // en cuanto `yo` resuelve, sin dejar que el fallback lista[0] la ancle a otra.
      // El admin sí puede elegir, así que solo ponemos un valor inicial si no hay uno.
      if (esAdmin) setSedeSel((prev) => prev || (lista[0]?.id ?? ""));
      else if (yo) setSedeSel(yo.sedeBaseId);
    });
  }, [supabase, router, yo, esAdmin]);

  const cargar = useCallback(async () => {
    if (!sedeSel) return;
    const mi = ++reqId.current;
    setCargando(true);
    const domingo = addDays(lunes, 6);
    const [
      { data: p, error: pErr },
      { data: h, error: hErr },
      { data: t, error: tErr },
      { data: m, error: mErr },
      { data: f, error: fErr },
      { data: ar, error: arErr },
    ] = await Promise.all([
      supabase.from("personas").select("id, nombres, apellidos, rol").eq("sede_base_id", sedeSel).eq("estado", "activo").order("nombres"),
      supabase.from("horarios_asignados").select("persona_id, hora_entrada, hora_salida, dias_laborables, horario_por_dia, vigente_desde, vigente_hasta").lte("vigente_desde", domingo).or(`vigente_hasta.is.null,vigente_hasta.gte.${lunes}`),
      supabase.from("turnos").select("persona_id, fecha, hora_entrada, hora_salida, es_descanso").gte("fecha", lunes).lte("fecha", domingo),
      supabase.from("metas_cobertura").select("dia_semana, meta, meta_encargadas").eq("sede_id", sedeSel),
      supabase.rpc("fn_personas_funciones"), // "funcion" vía RPC: el schema cache de PostgREST no expone la columna
      supabase.rpc("fn_areas"), // catálogo dinámico de áreas (nunca .from("areas"): schema cache trabado)
    ]);
    if (mi !== reqId.current) return; // llegó una carga más nueva; descarto ésta
    if (pErr || hErr || tErr || mErr) {
      setMsg({ tipo: "error", texto: `No se pudo cargar la semana: ${(pErr ?? hErr ?? tErr ?? mErr)!.message}` });
      setCargando(false);
      return; // no pisa personas/horarios/turnos/metas con datos parciales/vacíos
    }
    setAreas(parseAreas(ar, arErr));
    // Si falla la RPC de funciones O la del catálogo de áreas, la cobertura puede
    // contar mal (degrada a defaults) — se avisa en pantalla en vez de fallar en silencio.
    setFuncionesFallo(Boolean(fErr) || Boolean(arErr));
    const mapF = new Map(((f as { persona_id: string; funcion: string }[] | null) ?? []).map((x) => [x.persona_id, x.funcion]));
    setPersonas((((p as Omit<Persona, "funcion">[]) ?? []).map((x) => ({ ...x, funcion: mapF.get(x.id) ?? AREA_DEFAULT }))));
    const mapH = new Map<string, Horario[]>();
    for (const x of (h as any[]) ?? []) {
      const arr = mapH.get(x.persona_id) ?? [];
      arr.push({ hora_entrada: x.hora_entrada, hora_salida: x.hora_salida, dias_laborables: x.dias_laborables ?? [1, 2, 3, 4, 5], horario_por_dia: x.horario_por_dia ?? null, vigente_desde: x.vigente_desde, vigente_hasta: x.vigente_hasta ?? null });
      mapH.set(x.persona_id, arr);
    }
    setHorarios(mapH);
    setTurnos(new Map(((t as any[]) ?? []).map((x) => [`${x.persona_id}|${x.fecha}`, { es_descanso: x.es_descanso, hora_entrada: x.hora_entrada, hora_salida: x.hora_salida }])));
    setMetas(new Map(((m as any[]) ?? []).map((x) => [x.dia_semana, x.meta])));
    setMetasEncargadas(new Map(((m as any[]) ?? []).map((x) => [x.dia_semana, x.meta_encargadas ?? 0])));
    setCargando(false);
  }, [supabase, sedeSel, lunes]);

  useEffect(() => { void cargar(); }, [cargar]);

  const celda = useCallback((personaId: string, fecha: string): Celda => {
    const t = turnos.get(`${personaId}|${fecha}`);
    if (t) return t.es_descanso ? { tipo: "descanso" } : { tipo: "turno", entrada: hhmm(t.hora_entrada), salida: hhmm(t.hora_salida) };
    const h = tramoVigente(horarios.get(personaId), fecha);
    if (h) {
      const dow = String(diaSemana(fecha));
      if (h.horario_por_dia) {
        const d = h.horario_por_dia[dow];
        // el refrigerio (r, en minutos) solo se conoce para el horario base con
        // jsonb — un turno puntual (arriba) no guarda esa hora, así que su barra
        // queda sin hueco (dato que no tenemos, mejor no inventarlo).
        if (d) return { tipo: "default", entrada: hhmm(d.e), salida: hhmm(d.s), refrigerio: d.r };
        return { tipo: "libre" }; // ese día no está en el horario base = descanso
      }
      // legacy sin jsonb: hora única + dias_laborables
      if ((h.dias_laborables ?? []).includes(diaSemana(fecha))) return { tipo: "default", entrada: hhmm(h.hora_entrada), salida: hhmm(h.hora_salida) };
    }
    return { tipo: "libre" };
  }, [turnos, horarios]);

  const trabaja = (c: Celda) => c.tipo === "turno" || c.tipo === "default";
  // La cobertura solo cuenta a las áreas OPERATIVAS DE SEDE (según el catálogo
  // dinámico de áreas); las demás áreas no.
  const cobertura = useCallback((fecha: string) => personas.reduce((n, p) => n + (esOperativaEn(areas, p.funcion) && trabaja(celda(p.id, fecha)) ? 1 : 0), 0), [personas, celda, areas]);
  // Cuántas encargadas (supervisor_sede) están programadas ese día — independiente
  // del área, es por rol.
  const encargadasCubiertas = useCallback((fecha: string) => personas.reduce((n, p) => n + (p.rol === "supervisor_sede" && trabaja(celda(p.id, fecha)) ? 1 : 0), 0), [personas, celda]);
  // Cuántas personas (según `filtro`) cubren cada franja del día — reusada para
  // la franja de la Vista Día (operativas, 1h) y las 2 tablas de la Vista
  // Semana (operativas y encargadas, 30 min ancladas a :15/:45).
  const coberturaPorFranja = useCallback((fecha: string, horaInicio: number, nFranjas: number, tamHoras: number, filtro: (p: Persona) => boolean): number[] => {
    const franjas = Array.from({ length: nFranjas }, () => 0);
    for (const p of personas) {
      if (!filtro(p)) continue;
      const c = celda(p.id, fecha);
      if (c.tipo !== "turno" && c.tipo !== "default") continue;
      const e = horaADecimal(c.entrada);
      const s = c.salida ? horaADecimal(c.salida) : HORA_FIN;
      for (let i = 0; i < franjas.length; i++) {
        const hi = horaInicio + i * tamHoras, hf = hi + tamHoras;
        if (e < hf && s > hi) franjas[i]++;
      }
    }
    return franjas;
  }, [personas, celda]);
  const esOperativa = useCallback((p: Persona) => esOperativaEn(areas, p.funcion), [areas]);
  const esEncargada = (p: Persona) => p.rol === "supervisor_sede";
  const coberturaPorHora = useCallback(
    (fecha: string) => coberturaPorFranja(fecha, HORA_INICIO, HORA_FIN - HORA_INICIO, 1, esOperativa),
    [coberturaPorFranja, esOperativa],
  );

  function abrir(personaId: string, fecha: string) {
    const c = celda(personaId, fecha);
    setEdit({ personaId, fecha });
    setEntrada(c.tipo === "turno" || c.tipo === "default" ? c.entrada : "");
    setSalida((c.tipo === "turno" || c.tipo === "default") && c.salida ? c.salida : "");
    setMsg(null);
  }

  async function ejecutar(fn: () => PromiseLike<{ error: any }>) {
    setGuardando(true);
    const { error } = await fn();
    setGuardando(false);
    if (error) { setMsg({ tipo: "error", texto: error.message }); return; }
    setEdit(null);
    await cargar();
  }

  const guardarTurno = () => {
    if (!edit || !entrada) { setMsg({ tipo: "error", texto: "Pon al menos la hora de entrada." }); return; }
    return ejecutar(() => supabase.rpc("fn_set_turno", { p_persona_id: edit.personaId, p_fecha: edit.fecha, p_hora_entrada: entrada, p_hora_salida: salida || null }));
  };
  const marcarDescanso = () => edit && ejecutar(() => supabase.rpc("fn_set_descanso", { p_persona_id: edit.personaId, p_fecha: edit.fecha }));
  const quitar = () => edit && ejecutar(() => supabase.rpc("fn_quitar_turno", { p_persona_id: edit.personaId, p_fecha: edit.fecha }));

  // Al teclear solo actualiza el estado local (para que el semáforo reaccione en vivo).
  function editarMeta(dia: number, valor: string) {
    const meta = Math.max(0, Math.round(Number(valor) || 0));
    setMetas((m) => new Map(m).set(dia, meta));
  }
  // Guarda de verdad al salir del campo — una sola escritura, sin carrera por tecla.
  async function comprometerMeta(dia: number, valor: string) {
    const meta = Math.max(0, Math.round(Number(valor) || 0));
    const { error } = await supabase.rpc("fn_set_meta_cobertura", { p_sede_id: sedeSel, p_dia_semana: dia, p_meta: meta });
    if (error) { setMsg({ tipo: "error", texto: `No se pudo guardar la meta: ${error.message}` }); await cargar(); }
  }

  function editarMetaEncargadas(dia: number, valor: string) {
    const meta = Math.max(0, Math.round(Number(valor) || 0));
    setMetasEncargadas((m) => new Map(m).set(dia, meta));
  }
  async function comprometerMetaEncargadas(dia: number, valor: string) {
    const meta = Math.max(0, Math.round(Number(valor) || 0));
    const { error } = await supabase.rpc("fn_set_meta_encargadas", { p_sede_id: sedeSel, p_dia_semana: dia, p_meta: meta });
    if (error) { setMsg({ tipo: "error", texto: `No se pudo guardar la meta de encargadas: ${error.message}` }); await cargar(); }
  }

  if (rol !== null && !puedeVer) {
    return (
      <div className="flex min-h-screen flex-col"><AdminNav />
        <main className="flex flex-1 items-center justify-center p-6"><p className="max-w-md text-center text-taupe">No tienes permiso para ver los turnos.</p></main>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
          <div>
            <h1 className="mb-1 font-serif text-2xl">Turnos y cobertura</h1>
            <p className="max-w-2xl text-sm text-taupe">
              Arma la semana por sede. Toca la fila de una persona en un día para poner su turno o marcar
              descanso. La barra de cada quien muestra su rango de horario; la franja de abajo de cada día es
              el mapa de calor de cobertura hora por hora (más verde = más gente).
            </p>
          </div>
          <div className="flex items-center gap-2">
            <div className="flex rounded-lg border border-sand p-0.5 text-sm">
              <button onClick={() => setVista("dia")} className={`rounded px-3 py-1.5 ${vista === "dia" ? "bg-tinta text-crema" : "text-taupe hover:bg-sand/40"}`}>Día</button>
              <button onClick={() => setVista("semana")} className={`rounded px-3 py-1.5 ${vista === "semana" ? "bg-tinta text-crema" : "text-taupe hover:bg-sand/40"}`}>Semana</button>
            </div>
            {esAdmin && (
              <select value={sedeSel} onChange={(e) => setSedeSel(e.target.value)} className="rounded-lg border border-sand bg-crema px-3 py-2 text-sm">
                {sedes.map((s) => <option key={s.id} value={s.id}>{s.codigo}</option>)}
              </select>
            )}
            <div className="flex items-center gap-1">
              <button onClick={() => setLunes(addDays(lunes, -7))} disabled={cargando} className="rounded-lg border border-sand px-3 py-2 text-sm hover:bg-sand/40 disabled:opacity-50">←</button>
              <button onClick={() => setLunes(lunesDeLaSemana(hoyLima()))} disabled={cargando} className="rounded-lg border border-sand px-3 py-2 text-sm hover:bg-sand/40 disabled:opacity-50">Hoy</button>
              <button onClick={() => setLunes(addDays(lunes, 7))} disabled={cargando} className="rounded-lg border border-sand px-3 py-2 text-sm hover:bg-sand/40 disabled:opacity-50">→</button>
            </div>
          </div>
        </div>

        {msg && <div className={`mb-4 max-w-2xl rounded-lg px-4 py-3 text-sm ${msg.tipo === "ok" ? "bg-sand/40 text-tinta" : "bg-rojo/10 text-rojo"}`}>{msg.texto}</div>}

        {funcionesFallo && !cargando && (
          <div className="mb-4 max-w-2xl rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
            No se pudo cargar el área del personal: la cobertura está contando a <strong>todos</strong> como
            operativos y puede marcar de más. <button onClick={() => void cargar()} className="font-medium underline">Reintentar</button>
          </div>
        )}

        {cargando ? <p className="text-sm text-taupe">Cargando…</p> : vista === "semana" ? (
          <div className="space-y-6">
            {([
              { titulo: "Cobertura (áreas operativas)", metaPorDia: metas, filtro: esOperativa },
              { titulo: "Encargadas (supervisor_sede)", metaPorDia: metasEncargadas, filtro: esEncargada },
            ] as const).map(({ titulo, metaPorDia, filtro }) => {
              // Cobertura por franja de cada día + escala vertical común (para que
              // los 7 días sean comparables de un vistazo).
              const covPorDia = dias.map((iso) => coberturaPorFranja(iso, HORA_INICIO_SEMANA, N_FRANJAS_SEMANA, 0.5, filtro));
              const metaMax = Math.max(0, ...dias.map((iso) => metaPorDia.get(diaSemana(iso)) ?? 0));
              const maxY = Math.max(6, ...covPorDia.flat(), metaMax + 1);
              return (
                <div key={titulo}>
                  <h2 className="font-serif text-lg">{titulo}</h2>
                  <p className="mb-2 text-xs text-taupe">
                    Verde = gente que trabaja a cada hora · rojo = lo que falta para tu meta (línea punteada). Abajo: cuánta gente te falta en la hora más floja del día.
                  </p>
                  <div className="overflow-x-auto">
                    <div className="grid min-w-[640px] grid-cols-7 gap-2">
                      {dias.map((iso, di) => {
                        const { abr, num } = etiquetaDia(iso);
                        const hoy = iso === hoyLima();
                        const dia = diaSemana(iso);
                        const meta = metaPorDia.get(dia) ?? 0;
                        const cov = covPorDia[di];
                        const s = siluetaSVG(cov, meta, maxY);
                        const min = minEnHorario(cov);
                        const falta = Math.max(0, meta - min);
                        return (
                          <button key={iso} onClick={() => irADia(iso)}
                            className={`rounded-lg border p-2 text-center transition-opacity hover:opacity-80 ${hoy ? "border-tinta" : "border-sand"}`}>
                            <div className={`mb-1 text-sm ${hoy ? "text-tinta" : ""}`}>
                              <span className="font-serif">{abr}</span> <span className="text-xs text-taupe">{num}</span>
                            </div>
                            <svg viewBox={`0 0 ${SIL_W} 52`} width="100%" preserveAspectRatio="none" className="block h-12">
                              <path d={s.area} style={{ fill: "var(--color-verde)", fillOpacity: 0.18 }} />
                              {s.deficit && <path d={s.deficit} style={{ fill: "var(--color-rojo)", fillOpacity: 0.32 }} />}
                              {meta > 0 && <line x1="0" y1={s.metaY} x2={SIL_W} y2={s.metaY} style={{ stroke: "var(--color-taupe)", strokeWidth: 1, strokeDasharray: "3 2" }} />}
                              <path d={s.line} fill="none" style={{ stroke: "var(--color-verde)", strokeWidth: 1.6, strokeLinejoin: "round" }} />
                            </svg>
                            {/* Estado en una sola línea clara: cubierto, o cuánta gente falta */}
                            <div className="mt-1.5 flex h-4 items-center justify-center gap-1 text-xs">
                              {meta === 0 ? (
                                <span className="text-[11px] text-taupe/60">sin meta</span>
                              ) : falta === 0 ? (
                                <span className="font-medium text-verde">✓ cubierto</span>
                              ) : (
                                <>
                                  {meta <= 6 && (
                                    <span className="flex gap-0.5">
                                      {Array.from({ length: meta }, (_, i) => (
                                        <span key={i} className="inline-block h-2 w-2 rounded-full"
                                          style={i < min ? { backgroundColor: "var(--color-verde)" } : { border: "1.5px solid var(--color-rojo)", boxSizing: "border-box" }} />
                                      ))}
                                    </span>
                                  )}
                                  <span className="font-medium text-rojo">{falta === 1 ? "falta 1" : `faltan ${falta}`}</span>
                                </>
                              )}
                            </div>
                          </button>
                        );
                      })}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        ) : (
          <div className="overflow-x-auto">
            <div className="min-w-[700px] space-y-4">
              {personas.length === 0 ? (
                <p className="rounded-lg border border-sand px-4 py-6 text-center text-sm text-taupe">No hay personas activas en esta sede.</p>
              ) : dias.map((iso) => {
                const { abr, num } = etiquetaDia(iso);
                const hoy = iso === hoyLima();
                const dia = diaSemana(iso);
                const meta = metas.get(dia) ?? 0;
                const prog = cobertura(iso);
                const horas = coberturaPorHora(iso);
                let claseProg = "text-taupe";
                if (meta > 0 && prog < meta) claseProg = "text-rojo font-medium";
                else if (meta > 0 && prog === meta) claseProg = "text-verde font-medium";
                else if (meta > 0 && prog > meta) claseProg = "text-ambar font-medium";
                const metaEnc = metasEncargadas.get(dia) ?? 0;
                const enc = encargadasCubiertas(iso);
                const claseEnc = metaEnc > 0 && enc < metaEnc ? "text-rojo font-medium" : "text-verde font-medium";
                return (
                  <section key={iso} id={`turnos-dia-${iso}`} className={`overflow-hidden rounded-lg border ${hoy ? "border-tinta" : "border-sand"}`}>
                    {/* Cabecera del día: fecha + meta editable + progreso */}
                    <div className="flex flex-wrap items-center justify-between gap-3 bg-sand/50 px-4 py-2">
                      <div className={hoy ? "text-tinta" : ""}>
                        <span className="font-serif text-lg">{abr}</span>{" "}
                        <span className="text-sm text-taupe">{num}</span>
                      </div>
                      <div className="flex items-center gap-3 text-xs">
                        <label className="flex items-center gap-1.5 text-taupe">
                          Meta
                          {esAdmin ? (
                            <input type="number" min={0} value={meta}
                              onChange={(e) => editarMeta(dia, e.target.value)}
                              onBlur={(e) => comprometerMeta(dia, e.target.value)}
                              className="w-12 rounded border border-sand bg-crema px-1 py-0.5 text-center" />
                          ) : (
                            <span>{meta || "—"}</span>
                          )}
                        </label>
                        <span className={claseProg}>
                          {prog}{meta > 0 ? ` / ${meta}` : ""} cubiertos
                          {meta > 0 && prog < meta && ` · faltan ${meta - prog}`}
                          {meta > 0 && prog > meta && ` · sobran ${prog - meta}`}
                        </span>
                        <label className="flex items-center gap-1.5 border-l border-sand pl-3 text-taupe">
                          Encargadas
                          {esAdmin ? (
                            <input type="number" min={0} value={metaEnc}
                              onChange={(e) => editarMetaEncargadas(dia, e.target.value)}
                              onBlur={(e) => comprometerMetaEncargadas(dia, e.target.value)}
                              className="w-12 rounded border border-sand bg-crema px-1 py-0.5 text-center" />
                          ) : (
                            <span>{metaEnc || "—"}</span>
                          )}
                        </label>
                        <span className={claseEnc}>
                          {enc}{metaEnc > 0 ? ` / ${metaEnc}` : ""}
                          {metaEnc > 0 && enc < metaEnc && ` · faltan ${metaEnc - enc}`}
                        </span>
                      </div>
                    </div>

                    {/* Eje de horas */}
                    <div className="relative ml-[176px] h-4 border-b border-sand/60 text-[10px] text-taupe">
                      {MARCAS_HORA.map((h) => (
                        <span key={h} className="absolute -translate-x-1/2" style={{ left: `${pctEnRango(h)}%` }}>{h}h</span>
                      ))}
                    </div>

                    {/* Una fila por persona: barra = su rango de turno ese día */}
                    {personas.map((p) => {
                      const c = celda(p.id, iso);
                      const operativa = esOperativaEn(areas, p.funcion);
                      return (
                        <button key={p.id} onClick={() => abrir(p.id, iso)}
                          className="flex w-full items-center border-t border-sand/60 text-left transition-colors hover:bg-sand/20">
                          <span className="w-[176px] shrink-0 truncate px-3 py-2 text-xs">
                            {p.nombres} {p.apellidos}
                            {!operativa && (
                              <span className="ml-1.5 whitespace-nowrap rounded-full bg-ambar/15 px-1.5 py-0.5 text-[10px] text-ambar">{areaCorto(areas, p.funcion)}</span>
                            )}
                          </span>
                          <span className="relative h-7 flex-1">
                            {(c.tipo === "turno" || c.tipo === "default") && (() => {
                              const left = pctEnRango(horaADecimal(c.entrada));
                              const right = pctEnRango(c.salida ? horaADecimal(c.salida) : HORA_FIN);
                              const claseColor = `${operativa ? "bg-verde" : "bg-ambar"} ${c.tipo === "default" ? "opacity-50" : ""}`;
                              const tituloBase = `${c.entrada}${c.salida ? `–${c.salida}` : ""}`;
                              // Hueco de refrigerio: no sabemos la hora exacta en que empieza (el
                              // sistema solo guarda cuántos minutos dura), así que se dibuja
                              // aproximado, centrado a la mitad del turno — no es literal.
                              if (c.refrigerio && c.refrigerio > 0) {
                                const durHoras = c.refrigerio / 60;
                                const salidaDec = c.salida ? horaADecimal(c.salida) : HORA_FIN;
                                const centro = (horaADecimal(c.entrada) + salidaDec) / 2;
                                const huecoIni = pctEnRango(centro - durHoras / 2);
                                const huecoFin = pctEnRango(centro + durHoras / 2);
                                return (
                                  <>
                                    <span className={`absolute top-1.5 h-4 rounded-l ${claseColor}`}
                                      style={{ left: `${left}%`, width: `${Math.max(0.5, huecoIni - left)}%` }}
                                      title={`${tituloBase} (refrigerio ~${c.refrigerio}min hacia la mitad)`} />
                                    <span className={`absolute top-1.5 h-4 rounded-r ${claseColor}`}
                                      style={{ left: `${huecoFin}%`, width: `${Math.max(0.5, right - huecoFin)}%` }}
                                      title={`${tituloBase} (refrigerio ~${c.refrigerio}min hacia la mitad)`} />
                                  </>
                                );
                              }
                              return (
                                <span className={`absolute top-1.5 h-4 rounded ${claseColor}`}
                                  style={{ left: `${left}%`, width: `${Math.max(1, right - left)}%` }}
                                  title={tituloBase} />
                              );
                            })()}
                            {c.tipo === "descanso" && <span className="absolute left-2 top-1.5 rounded bg-sand px-1.5 py-0.5 text-[10px] text-taupe">descanso</span>}
                            {c.tipo === "libre" && <span className="absolute left-2 top-1.5 text-[10px] text-taupe/40">+</span>}
                          </span>
                        </button>
                      );
                    })}

                    {/* Mapa de calor de cobertura por hora: degradado continuo rojo→verde
                        (rojo = lejos de la meta, verde = la alcanza o la pasa), con el
                        número exacto de cada hora superpuesto para no perder precisión. */}
                    <div className="flex items-stretch border-t-2 border-sand">
                      <span className="w-[176px] shrink-0 px-3 py-2 text-xs text-taupe">Cobertura</span>
                      <div className="relative h-8 flex-1" style={{ background: gradienteCobertura(horas, meta) }}>
                        {horas.map((n, i) => (
                          <span
                            key={i}
                            className="absolute top-1/2 -translate-x-1/2 -translate-y-1/2 text-[10px] font-medium text-crema"
                            style={{ left: `${((i + 0.5) / horas.length) * 100}%`, textShadow: "0 1px 2px rgba(0,0,0,0.35)" }}
                            title={`${HORA_INICIO + i}h–${HORA_INICIO + i + 1}h: ${n} persona${n === 1 ? "" : "s"}${meta > 0 ? ` (meta ${meta})` : ""}`}
                          >
                            {n > 0 ? n : ""}
                          </span>
                        ))}
                      </div>
                    </div>
                  </section>
                );
              })}
            </div>
          </div>
        )}

        <p className="mt-3 text-xs text-taupe">
          Cada barra es el rango de entrada–salida del turno de esa persona ese día (más clarita = horario por
          defecto del periodo, no se fijó turno puntual). El mapa de calor de abajo cuenta solo a las{" "}
          <strong>áreas operativas de sede</strong> ({areas.filter((a) => a.operativa && a.activa).map((a) => a.nombre).join(", ")}
          ) — más verde = más gente cubriendo esa hora frente a la meta del día. El área se cambia en Equipo.
        </p>

        {edit && (() => {
          const p = personas.find((x) => x.id === edit.personaId);
          const { abr, num } = etiquetaDia(edit.fecha);
          const propio = yo && edit.personaId === yo.id && !esAdmin;
          return (
            <div className="fixed inset-0 z-20 flex items-center justify-center bg-black/40 p-4" onClick={() => !guardando && setEdit(null)}>
              <div className="w-full max-w-sm rounded-xl border border-sand bg-crema p-6" onClick={(e) => e.stopPropagation()}>
                <h3 className="mb-1 font-serif text-lg">{p?.nombres} {p?.apellidos}</h3>
                <p className="mb-4 text-sm text-taupe">{abr} {num}</p>
                {propio ? (
                  <p className="mb-2 rounded-lg bg-rojo/10 px-3 py-2 text-sm text-rojo">
                    No puedes fijar tu propio turno (la hora de entrada define tu tardanza). Pídeselo a un administrador.
                  </p>
                ) : (
                  <>
                    <div className="grid grid-cols-2 gap-3">
                      <label className="flex flex-col gap-1 text-sm">Entrada
                        <input type="time" value={entrada} onChange={(e) => setEntrada(e.target.value)} className="rounded-lg border border-sand bg-crema px-3 py-2" /></label>
                      <label className="flex flex-col gap-1 text-sm">Salida
                        <input type="time" value={salida} onChange={(e) => setSalida(e.target.value)} className="rounded-lg border border-sand bg-crema px-3 py-2" /></label>
                    </div>
                    <div className="mt-5 flex flex-wrap justify-between gap-2">
                      <div className="flex gap-2">
                        <button onClick={marcarDescanso} disabled={guardando} className="rounded-lg border border-sand px-3 py-2 text-sm hover:bg-sand/40">Descanso</button>
                        <button onClick={quitar} disabled={guardando} className="rounded-lg border border-sand px-3 py-2 text-sm text-taupe hover:bg-sand/40">Quitar</button>
                      </div>
                      <div className="flex gap-2">
                        <button onClick={() => setEdit(null)} disabled={guardando} className="rounded-lg border border-sand px-3 py-2 text-sm">Cancelar</button>
                        <button onClick={guardarTurno} disabled={guardando} className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema disabled:opacity-50">
                          {guardando ? "…" : "Guardar"}
                        </button>
                      </div>
                    </div>
                  </>
                )}
              </div>
            </div>
          );
        })()}
      </main>
    </div>
  );
}
