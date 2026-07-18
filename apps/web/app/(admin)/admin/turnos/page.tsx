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

interface Persona { id: string; nombres: string; apellidos: string; rol: string; funcion: string; esEncargadaPiso: boolean; }
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
// Sin meta no hay contra qué medir: taupe neutro, no rojo (el rojo sin
// significado solo mete ruido de alarma).
const ROJO_RGB: [number, number, number] = [184, 65, 45];
const VERDE_RGB: [number, number, number] = [95, 122, 82];
function colorCobertura(n: number, meta: number): string {
  if (meta <= 0) return "rgb(164, 120, 101)"; // taupe
  const ratio = Math.min(n / meta, 1);
  const [r, g, b] = ROJO_RGB.map((c0, i) => Math.round(c0 + (VERDE_RGB[i] - c0) * ratio));
  return `rgb(${r}, ${g}, ${b})`;
}
// La meta cambia a media tarde: hasta 14:15 es la meta de la MAÑANA, después la
// de la TARDE (fijo por ahora, ambas sedes — decisión de Felipe).
const CORTE_TARDE = 14.25; // 14:15
const metaDeHora = (horaFranjaIni: number, metaMan: number, metaTar: number) =>
  horaFranjaIni >= CORTE_TARDE ? metaTar : metaMan;
// Degradado del mapa de calor (Vista Día), coloreando cada hora contra la meta
// de SU tramo (mañana o tarde).
function gradienteCoberturaBanda(horas: number[], metaMan: number, metaTar: number, hi0: number): string {
  const n = horas.length;
  const col = (i: number) => colorCobertura(horas[i], metaDeHora(hi0 + i, metaMan, metaTar));
  const paradas = horas.map((_, i) => `${col(i)} ${((i + 0.5) / n) * 100}%`);
  return `linear-gradient(to right, ${col(0)} 0%, ${paradas.join(", ")}, ${col(n - 1)} 100%)`;
}

// ── Silueta del día (Vista Semana): la forma de cuánta gente hay por hora ────
// 3 tonos: verde = cubierto (bajo la meta), rojo = falta (hueco), ámbar = sobra
// (por encima de la meta). La meta es una línea escalonada (sube en la tarde).
const SIL_W = 100, SIL_BASE = 46, SIL_TOP = 6;
function siluetaSVG(cov: number[], metaArr: number[], maxY: number) {
  const n = cov.length;
  const yF = (v: number) => SIL_BASE - (v / maxY) * (SIL_BASE - SIL_TOP);
  const xF = (i: number) => (i / (n - 1)) * SIL_W;
  const mn = (i: number) => Math.min(cov[i], metaArr[i]);
  const mx = (i: number) => Math.max(cov[i], metaArr[i]);
  // La meta / falta / sobra solo aplican en la VENTANA operativa (de la primera
  // a la última franja con gente), igual que el cálculo — así no se pinta rojo
  // antes de abrir ni después de cerrar.
  const nz = cov.map((v, i) => (v > 0 ? i : -1)).filter((i) => i >= 0);
  const i0 = nz.length ? nz[0] : 0, i1 = nz.length ? nz[nz.length - 1] : -1;
  const hayVentana = i1 >= i0;
  // verde: desde el piso hasta lo cubierto (min de cobertura y meta), todo el día
  let green = `M ${xF(0)} ${SIL_BASE}`;
  for (let i = 0; i < n; i++) green += ` L ${xF(i).toFixed(1)} ${yF(mn(i)).toFixed(1)}`;
  green += ` L ${xF(n - 1)} ${SIL_BASE} Z`;
  let deficit = "", surplus = "", metaLine = "";
  if (hayVentana) {
    let dTop = "", dBot = "", sTop = "", sBot = "", mL = "";
    for (let i = i0; i <= i1; i++) {
      const px = xF(i).toFixed(1);
      dTop += (i === i0 ? "M " : " L ") + `${px} ${yF(metaArr[i]).toFixed(1)}`;
      sTop += (i === i0 ? "M " : " L ") + `${px} ${yF(mx(i)).toFixed(1)}`;
      mL += (i === i0 ? "M " : " L ") + `${px} ${yF(metaArr[i]).toFixed(1)}`;
    }
    for (let i = i1; i >= i0; i--) {
      dBot += ` L ${xF(i).toFixed(1)} ${yF(mn(i)).toFixed(1)}`;
      sBot += ` L ${xF(i).toFixed(1)} ${yF(metaArr[i]).toFixed(1)}`;
    }
    deficit = dTop + dBot + " Z";
    surplus = sTop + sBot + " Z";
    metaLine = mL;
  }
  let line = "";
  for (let i = 0; i < n; i++) line += (i ? " L " : "M ") + `${xF(i).toFixed(1)} ${yF(cov[i]).toFixed(1)}`;
  return { green, deficit, surplus, metaLine, line };
}

// Resumen de OPERATIVAS: promedio de qué tan lleno corriste vs la meta del tramo
// (topado a 100% por franja para que la tarde de sobra NO tape una mañana vacía),
// más el motor de sugerencia: redistribuir (hay gente que mover) vs falta
// personal (déficit sin sobra en ningún lado → contratar).
function resumenOperativas(cov: number[], metaMan: number, metaTar: number, hi0: number, tam: number) {
  const idx = cov.map((v, i) => (v > 0 ? i : -1)).filter((i) => i >= 0);
  if (idx.length === 0) return { hayTurnos: false, sinMeta: false, pct: 0, supHoras: 0, sug: null as string | null, redistribuir: null as "adelantar" | "retrasar" | null };
  let suma = 0, n = 0, defMan = 0, defTar = 0, supMan = 0, supTar = 0, supFr = 0;
  for (let i = idx[0]; i <= idx[idx.length - 1]; i++) {
    const tarde = hi0 + i * tam >= CORTE_TARDE;
    const m = tarde ? metaTar : metaMan;
    if (m <= 0) continue;
    suma += Math.min(cov[i] / m, 1); n++;
    if (cov[i] < m) { if (tarde) defTar++; else defMan++; }
    else if (cov[i] > m) { if (tarde) supTar++; else supMan++; supFr++; }
  }
  if (n === 0) return { hayTurnos: true, sinMeta: true, pct: 0, supHoras: 0, sug: null, redistribuir: null };
  const hayDef = defMan + defTar > 0, haySup = supMan + supTar > 0;
  let sug: string | null = null;
  let redistribuir: "adelantar" | "retrasar" | null = null;
  if (hayDef && haySup) {
    if (defMan > 0 && supTar > 0) { sug = "Sobra gente en la tarde y falta en la mañana."; redistribuir = "adelantar"; }
    else if (defTar > 0 && supMan > 0) { sug = "Sobra gente en la mañana y falta en la tarde."; redistribuir = "retrasar"; }
    else sug = "Reparte mejor: hay horas con exceso y otras con falta.";
  } else if (hayDef && !haySup) {
    sug = "Te falta personal ese día — ni moviendo turnos alcanza.";
  }
  return { hayTurnos: true, sinMeta: false, pct: Math.round((suma / n) * 100), supHoras: Math.round(supFr * tam * 10) / 10, sug, redistribuir };
}

// Resumen de ENCARGADAS: promedio de llenado vs la meta (igual que operativas,
// con meta plana todo el día). Decisión de Felipe 2026-07-17: 1 encargada de
// una meta de 2 se lee "cubierto 50%", no piso estricto en 0%.
function resumenEncargadas(cov: number[], meta: number): { pct: number; hayTurnos: boolean; sinMeta: boolean } {
  const idx = cov.map((v, i) => (v > 0 ? i : -1)).filter((i) => i >= 0);
  if (idx.length === 0) return { pct: 0, hayTurnos: false, sinMeta: false };
  if (meta <= 0) return { pct: 0, hayTurnos: true, sinMeta: true };
  const ventana = cov.slice(idx[0], idx[idx.length - 1] + 1);
  const suma = ventana.reduce((s, v) => s + Math.min(v / meta, 1), 0);
  return { pct: Math.round((suma / ventana.length) * 100), hayTurnos: true, sinMeta: false };
}
// Verde ≥90 · ámbar 60-89 · rojo <60 (umbral elegido por Felipe).
const colorDePct = (pct: number) => (pct >= 90 ? "var(--color-verde)" : pct >= 60 ? "var(--color-ambar)" : "var(--color-rojo)");

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
  // La preferencia guardada se lee DESPUÉS de montar (no en el primer render):
  // el HTML llega del servidor con "dia" y leer localStorage durante la
  // hidratación haría chocar servidor y navegador (error de hidratación).
  const [vista, setVistaRaw] = useState<"dia" | "semana">("dia");
  useEffect(() => {
    const v = localStorage.getItem("turnos_vista");
    if (v === "semana") setVistaRaw("semana");
  }, []);
  const setVista = (v: "dia" | "semana") => { setVistaRaw(v); localStorage.setItem("turnos_vista", v); };
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
  const [metas, setMetas] = useState<Map<number, number>>(new Map()); // meta operativas MAÑANA
  const [metasTarde, setMetasTarde] = useState<Map<number, number>>(new Map()); // meta operativas TARDE
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
      supabase.from("metas_cobertura").select("dia_semana, meta, meta_tarde, meta_encargadas").eq("sede_id", sedeSel),
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
    const mapF = new Map(((f as { persona_id: string; funcion: string; es_encargada_piso?: boolean }[] | null) ?? []).map((x) => [x.persona_id, { funcion: x.funcion, esEncargadaPiso: Boolean(x.es_encargada_piso) }]));
    setPersonas((((p as Omit<Persona, "funcion" | "esEncargadaPiso">[]) ?? []).map((x) => ({ ...x, funcion: mapF.get(x.id)?.funcion ?? AREA_DEFAULT, esEncargadaPiso: mapF.get(x.id)?.esEncargadaPiso ?? false }))));
    const mapH = new Map<string, Horario[]>();
    for (const x of (h as any[]) ?? []) {
      const arr = mapH.get(x.persona_id) ?? [];
      arr.push({ hora_entrada: x.hora_entrada, hora_salida: x.hora_salida, dias_laborables: x.dias_laborables ?? [1, 2, 3, 4, 5], horario_por_dia: x.horario_por_dia ?? null, vigente_desde: x.vigente_desde, vigente_hasta: x.vigente_hasta ?? null });
      mapH.set(x.persona_id, arr);
    }
    setHorarios(mapH);
    setTurnos(new Map(((t as any[]) ?? []).map((x) => [`${x.persona_id}|${x.fecha}`, { es_descanso: x.es_descanso, hora_entrada: x.hora_entrada, hora_salida: x.hora_salida }])));
    setMetas(new Map(((m as any[]) ?? []).map((x) => [x.dia_semana, x.meta])));
    setMetasTarde(new Map(((m as any[]) ?? []).map((x) => [x.dia_semana, x.meta_tarde ?? x.meta ?? 0])));
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
  // Cuenta como encargada quien tiene el rol supervisor_sede O la marca
  // es_encargada_piso (un admin de confianza que además está en el piso, como
  // Janis — mantiene sus permisos de admin y de paso suma en la cobertura).
  const esEncargada = (p: Persona) => p.rol === "supervisor_sede" || p.esEncargadaPiso;
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
  function editarMeta(dia: number, tramo: "manana" | "tarde", valor: string) {
    const meta = Math.max(0, Math.round(Number(valor) || 0));
    (tramo === "manana" ? setMetas : setMetasTarde)((m) => new Map(m).set(dia, meta));
  }
  // Guarda de verdad al salir del campo — manda mañana + tarde juntas (una sola escritura).
  async function comprometerMeta(dia: number) {
    const { error } = await supabase.rpc("fn_set_meta_cobertura", {
      p_sede_id: sedeSel, p_dia_semana: dia,
      p_meta_manana: metas.get(dia) ?? 0, p_meta_tarde: metasTarde.get(dia) ?? 0,
    });
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
              descanso. La meta tiene dos tramos: mañana y tarde (el corte es 14:15) — la franja de abajo
              de cada día compara la gente de cada hora contra la meta de su tramo.
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
              { titulo: "Cobertura (áreas operativas)", tipo: "op", filtro: esOperativa },
              { titulo: "Encargadas (supervisor_sede)", tipo: "enc", filtro: esEncargada },
            ] as const).map(({ titulo, tipo, filtro }) => {
              const covPorDia = dias.map((iso) => coberturaPorFranja(iso, HORA_INICIO_SEMANA, N_FRANJAS_SEMANA, 0.5, filtro));
              // meta por franja de cada día: operativas cambia mañana/tarde; encargadas es plana.
              const metaArrDe = (dia: number): number[] =>
                tipo === "op"
                  ? Array.from({ length: N_FRANJAS_SEMANA }, (_, i) => metaDeHora(HORA_INICIO_SEMANA + i * 0.5, metas.get(dia) ?? 0, metasTarde.get(dia) ?? 0))
                  : Array.from({ length: N_FRANJAS_SEMANA }, () => metasEncargadas.get(dia) ?? 0);
              // Escala vertical propia de CADA tabla (si la de encargadas usara la
              // meta de operativas, sus siluetas de meta 2 saldrían aplastadas).
              const metaMax = Math.max(0, ...dias.map((iso) => {
                const dia = diaSemana(iso);
                return tipo === "op"
                  ? Math.max(metas.get(dia) ?? 0, metasTarde.get(dia) ?? 0)
                  : metasEncargadas.get(dia) ?? 0;
              }));
              const maxY = Math.max(tipo === "op" ? 6 : 3, ...covPorDia.flat(), metaMax + 1);
              const colorPct = colorDePct;
              return (
                <div key={titulo}>
                  <h2 className="font-serif text-lg">{titulo}</h2>
                  <p className="mb-2 text-xs text-taupe">
                    {tipo === "op"
                      ? "Verde = cubierto · rojo = falta · ámbar = sobra (la meta sube en la tarde, línea punteada). Abajo: qué tan lleno corriste vs tu meta, en promedio del día."
                      : "Abajo: qué tan lleno corriste vs tu meta de encargadas, en promedio del día (1 de 2 = 50%)."}
                  </p>
                  <div className="overflow-x-auto">
                    <div className="grid min-w-[640px] grid-cols-7 gap-2">
                      {dias.map((iso, di) => {
                        const { abr, num } = etiquetaDia(iso);
                        const hoy = iso === hoyLima();
                        const dia = diaSemana(iso);
                        const cov = covPorDia[di];
                        const metaArr = metaArrDe(dia);
                        const s = siluetaSVG(cov, metaArr, maxY);
                        const r = tipo === "op"
                          ? resumenOperativas(cov, metas.get(dia) ?? 0, metasTarde.get(dia) ?? 0, HORA_INICIO_SEMANA, 0.5)
                          : { ...resumenEncargadas(cov, metasEncargadas.get(dia) ?? 0), supHoras: 0, sug: null as string | null, redistribuir: null };
                        // Con meta puesta pero NADIE programado, el día no está "cerrado":
                        // alguien olvidó armar los turnos — eso se avisa en rojo, no en gris.
                        const metaDia = tipo === "op"
                          ? Math.max(metas.get(dia) ?? 0, metasTarde.get(dia) ?? 0)
                          : metasEncargadas.get(dia) ?? 0;
                        const nadieProgramado = !r.hayTurnos && metaDia > 0;
                        return (
                          <button key={iso} onClick={() => irADia(iso)}
                            className={`rounded-lg border p-2 text-center transition-opacity hover:opacity-80 ${hoy ? "border-tinta" : "border-sand"}`}
                            title={r.sug ?? undefined}>
                            <div className={`mb-1 text-sm ${hoy ? "text-tinta" : ""}`}>
                              <span className="font-serif">{abr}</span> <span className="text-xs text-taupe">{num}</span>
                            </div>
                            <svg viewBox={`0 0 ${SIL_W} 52`} width="100%" preserveAspectRatio="none" className="block h-12">
                              <path d={s.green} style={{ fill: "var(--color-verde)", fillOpacity: 0.18 }} />
                              <path d={s.deficit} style={{ fill: "var(--color-rojo)", fillOpacity: 0.32 }} />
                              {tipo === "op" && <path d={s.surplus} style={{ fill: "var(--color-ambar)", fillOpacity: 0.55 }} />}
                              <path d={s.metaLine} fill="none" style={{ stroke: "var(--color-taupe)", strokeWidth: 1, strokeDasharray: "3 2" }} />
                              <path d={s.line} fill="none" style={{ stroke: "var(--color-verde)", strokeWidth: 1.6, strokeLinejoin: "round" }} />
                            </svg>
                            <div className="mt-1.5 flex h-4 items-center justify-center text-xs">
                              {nadieProgramado ? (
                                <span className="font-medium text-rojo">¡nadie programado!</span>
                              ) : r.sinMeta ? (
                                <span className="text-[11px] text-taupe/60">sin meta</span>
                              ) : !r.hayTurnos ? (
                                <span className="text-[11px] text-taupe/60">sin turnos</span>
                              ) : (
                                <span className="font-medium" style={{ color: colorPct(r.pct) }}>cubierto {r.pct}%</span>
                              )}
                            </div>
                            {/* Aviso corto: redistribuir (ámbar) o falta personal (rojo) */}
                            <div className="flex h-3 items-center justify-center">
                              {r.redistribuir ? (
                                <span className="text-[10px] text-ambar">↔ reparte turnos</span>
                              ) : r.sug ? (
                                <span className="text-[10px] text-rojo">+ falta personal</span>
                              ) : r.supHoras > 0 ? (
                                <span className="text-[10px] text-taupe/60">sobra {r.supHoras}h</span>
                              ) : null}
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
                const metaMan = metas.get(dia) ?? 0;
                const metaTar = metasTarde.get(dia) ?? 0;
                const metaEnc = metasEncargadas.get(dia) ?? 0;
                const horas = coberturaPorHora(iso);
                const covFr = coberturaPorFranja(iso, HORA_INICIO_SEMANA, N_FRANJAS_SEMANA, 0.5, esOperativa);
                const covFrEnc = coberturaPorFranja(iso, HORA_INICIO_SEMANA, N_FRANJAS_SEMANA, 0.5, esEncargada);
                const r = resumenOperativas(covFr, metaMan, metaTar, HORA_INICIO_SEMANA, 0.5);
                const rEnc = resumenEncargadas(covFrEnc, metaEnc);
                // Candidato concreto a mover (para la sugerencia de redistribución)
                let candidato = "";
                if (r.redistribuir === "adelantar") {
                  const c = personas.find((p) => { if (!esOperativa(p)) return false; const cel = celda(p.id, iso); return (cel.tipo === "turno" || cel.tipo === "default") && horaADecimal(cel.entrada) >= CORTE_TARDE; });
                  if (c) candidato = `Ej. adelanta a ${c.nombres}.`;
                } else if (r.redistribuir === "retrasar") {
                  const c = personas.find((p) => { if (!esOperativa(p)) return false; const cel = celda(p.id, iso); return (cel.tipo === "turno" || cel.tipo === "default") && cel.salida !== null && cel.salida !== undefined && horaADecimal(cel.salida) <= CORTE_TARDE + 1; });
                  if (c) candidato = `Ej. retrasa la salida de ${c.nombres}.`;
                }
                return (
                  <section key={iso} id={`turnos-dia-${iso}`} className={`overflow-hidden rounded-lg border ${hoy ? "border-tinta" : "border-sand"}`}>
                    {/* Cabecera del día: fecha + metas editables (mañana/tarde) + resumen */}
                    <div className="flex flex-wrap items-center justify-between gap-3 bg-sand/50 px-4 py-2">
                      <div className={hoy ? "text-tinta" : ""}>
                        <span className="font-serif text-lg">{abr}</span>{" "}
                        <span className="text-sm text-taupe">{num}</span>
                      </div>
                      <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs">
                        <label className="flex items-center gap-1.5 text-taupe">
                          Meta op.
                          {esAdmin ? (
                            <>
                              <input type="number" min={0} value={metaMan} title="meta de la mañana (hasta 14:15)"
                                onChange={(e) => editarMeta(dia, "manana", e.target.value)} onBlur={() => comprometerMeta(dia)}
                                className="w-11 rounded border border-sand bg-crema px-1 py-0.5 text-center" />
                              <span className="text-taupe/60">/</span>
                              <input type="number" min={0} value={metaTar} title="meta de la tarde (desde 14:15)"
                                onChange={(e) => editarMeta(dia, "tarde", e.target.value)} onBlur={() => comprometerMeta(dia)}
                                className="w-11 rounded border border-sand bg-crema px-1 py-0.5 text-center" />
                            </>
                          ) : (
                            <span>{metaMan}/{metaTar}</span>
                          )}
                          <span className="text-taupe/60">mañ/tar</span>
                        </label>
                        <span className="font-medium" style={{ color: !r.hayTurnos && Math.max(metaMan, metaTar) > 0 ? "var(--color-rojo)" : r.sinMeta || !r.hayTurnos ? "var(--color-taupe)" : colorDePct(r.pct) }}>
                          {!r.hayTurnos && Math.max(metaMan, metaTar) > 0 ? "¡nadie programado!" : r.sinMeta ? "sin meta" : !r.hayTurnos ? "sin turnos" : `cubierto ${r.pct}%`}
                          {r.supHoras > 0 && <span className="text-ambar"> · sobra {r.supHoras}h</span>}
                        </span>
                        <label className="flex items-center gap-1.5 border-l border-sand pl-3 text-taupe">
                          Encargadas
                          {esAdmin ? (
                            <input type="number" min={0} value={metaEnc}
                              onChange={(e) => editarMetaEncargadas(dia, e.target.value)}
                              onBlur={(e) => comprometerMetaEncargadas(dia, e.target.value)}
                              className="w-11 rounded border border-sand bg-crema px-1 py-0.5 text-center" />
                          ) : (
                            <span>{metaEnc || "—"}</span>
                          )}
                        </label>
                        <span className="font-medium" style={{ color: !rEnc.hayTurnos && metaEnc > 0 ? "var(--color-rojo)" : rEnc.sinMeta || !rEnc.hayTurnos ? "var(--color-taupe)" : colorDePct(rEnc.pct) }}>
                          {!rEnc.hayTurnos && metaEnc > 0 ? "¡ninguna programada!" : rEnc.sinMeta ? "sin meta" : !rEnc.hayTurnos ? "sin turnos" : `cubierto ${rEnc.pct}%`}
                        </span>
                      </div>
                    </div>
                    {/* Sugerencia: redistribuir (hay gente que mover) o falta personal (contratar) */}
                    {r.sug && (
                      <div className="border-t border-sand/60 px-4 py-1.5 text-xs" style={{ color: r.redistribuir ? "var(--color-ambar)" : "var(--color-rojo)" }}>
                        {r.redistribuir ? "↔ " : "＋ "}{r.sug}{candidato && ` ${candidato}`}
                      </div>
                    )}

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
                      <div className="relative h-8 flex-1" style={{ background: gradienteCoberturaBanda(horas, metaMan, metaTar, HORA_INICIO) }}>
                        {horas.map((n, i) => {
                          const metaHora = metaDeHora(HORA_INICIO + i, metaMan, metaTar);
                          return (
                          <span
                            key={i}
                            className="absolute top-1/2 -translate-x-1/2 -translate-y-1/2 text-[10px] font-medium text-crema"
                            style={{ left: `${((i + 0.5) / horas.length) * 100}%`, textShadow: "0 1px 2px rgba(0,0,0,0.35)" }}
                            title={`${HORA_INICIO + i}h–${HORA_INICIO + i + 1}h: ${n} persona${n === 1 ? "" : "s"}${metaHora > 0 ? ` (meta ${metaHora})` : ""}`}
                          >
                            {n > 0 ? n : ""}
                          </span>
                          );
                        })}
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
          ) — más verde = más cerca de la meta de ese tramo (mañana o tarde). El área se cambia en Equipo.
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
