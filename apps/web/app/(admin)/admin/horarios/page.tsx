"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { Cargando } from "@/components/cargando";
import { useToast } from "@/components/toast";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { Boton } from "@/components/ui/boton";
import { Campo } from "@/components/ui/campo";
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
import { horasEntre as horasDia } from "@/lib/admin/jornada-esperada";

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
  persona_id: string; hora_entrada: string; hora_salida: string;
  vigente_desde: string; vigente_hasta: string | null;
  almuerzo_min_minutos: number; almuerzo_max_minutos: number; dias_laborables: number[];
  horario_por_dia: Record<string, { e: string; s: string; r?: number }> | null;
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

/** Resumen corto de un tramo, para el historial: "L-S 08:00–17:00" o "varía por día". */
function resumenTramo(h: Horario): string {
  const a = analizar(h);
  if (!a.dias.length) return "sin días";
  return a.uniforme ? `${textoDescanso(a.dias) === "sin descanso" ? "todos los días" : a.dias.length + " días/sem."} ${a.e}–${a.s}` : "varía por día";
}

// El editor de horario (toggle + hora única o por día) es idéntico en el
// cambio normal y en la corrección retroactiva — antes de escribirlo dos
// veces, un solo hook con el estado y las funciones que lo tocan.
function useEditorHorario() {
  const [modoPorDia, setModoPorDia] = useState(false);
  const [entrada, setEntrada] = useState("08:00");
  const [salida, setSalida] = useState("18:00");
  const [refri, setRefri] = useState(60);
  const [dias, setDias] = useState<number[]>([1, 2, 3, 4, 5, 6]);
  const [porDia, setPorDia] = useState<PorDia>({});

  function cargarDesde(h?: Horario) {
    const a = analizar(h);
    setPorDia(a.porDia);
    setDias(a.dias.length ? a.dias : [1, 2, 3, 4, 5, 6]);
    setEntrada(a.e);
    setSalida(a.s);
    setRefri(a.r);
    setModoPorDia(!a.uniforme);
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
  const totalSemana = modoPorDia
    ? Object.values(porDia).reduce((acc, v) => acc + horasDia(v.e, v.s, v.r), 0)
    : horasDia(entrada, salida, refri) * dias.length;
  const faltaEntrada = modoPorDia ? Object.values(porDia).some((v) => !v.e) : !entrada;
  const faltaSalida = modoPorDia ? Object.values(porDia).some((v) => !v.s) : !salida;

  return {
    modoPorDia, entrada, salida, refri, dias, porDia, totalSemana, faltaEntrada, faltaSalida,
    setEntrada, setSalida, setRefri,
    cargarDesde, toggleDia, toggleDiaPorDia, setCampoPorDia, setRefriPorDia, cambiarModo,
    construirHorario,
  };
}
type EditorHorario = ReturnType<typeof useEditorHorario>;

function EditorHorarioPorDia({ editor }: { editor: EditorHorario }) {
  const { modoPorDia, entrada, salida, refri, dias, porDia } = editor;
  return (
    <>
      <label className="mt-4 flex items-center gap-2 text-sm">
        {/* Casilla suelta: todavía no existe <CampoCasilla> en
            components/ui/campo.tsx (Fase A no la agregó pese a lo
            anunciado) — se deja con las clases que ese primitivo va a
            necesitar (accent-tinta, size-4) para que migrar sea trivial
            en cuanto exista. */}
        <input type="checkbox" checked={!modoPorDia} onChange={(e) => editor.cambiarModo(!e.target.checked)} className="size-4 rounded border-sand accent-tinta" />
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
            <Campo etiqueta="Entrada" type="time" value={entrada} onChange={(e) => editor.setEntrada(e.target.value)} />
            <Campo etiqueta="Salida" type="time" value={salida} onChange={(e) => editor.setSalida(e.target.value)} />
            <Campo etiqueta="Refrig. (min)" type="number" min={0} value={refri} onChange={(e) => editor.setRefri(Math.max(0, Math.round(Number(e.target.value) || 0)))} />
          </div>
          <p className="mt-2 text-xs text-taupe">Cada día: <span className="text-tinta">{fmtH(horasDia(entrada, salida, refri))}</span></p>
          <div className="mt-3">
            <p className="mb-1.5 text-sm">Días de trabajo <span className="text-taupe">(los que no marcas son descanso)</span></p>
            <div className="flex gap-1.5">
              {DIAS.map((d) => {
                const on = dias.includes(d.v);
                return (
                  <button key={d.v} type="button" onClick={() => editor.toggleDia(d.v)}
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
                  <button type="button" onClick={() => editor.toggleDiaPorDia(d.v)}
                    className={`h-8 w-14 shrink-0 rounded-control border text-xs capitalize ${activo ? "border-tinta bg-tinta text-crema" : "border-sand text-taupe hover:bg-sand/40"}`}>
                    {NOMBRE_DIA[d.v].slice(0, 3)}
                  </button>
                  {activo ? (
                    <>
                      <input type="time" value={dd.e} onChange={(e) => editor.setCampoPorDia(d.v, "e", e.target.value)} className="w-[90px] rounded-control border px-1.5 py-1 text-sm" />
                      <span className="text-taupe">–</span>
                      <input type="time" value={dd.s} onChange={(e) => editor.setCampoPorDia(d.v, "s", e.target.value)} className="w-[90px] rounded-control border px-1.5 py-1 text-sm" />
                      <input type="number" min={0} value={dd.r} onChange={(e) => editor.setRefriPorDia(d.v, e.target.value)} title="refrigerio (min)" className="w-12 rounded-control border px-1 py-1 text-sm" />
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
    </>
  );
}

function ResumenHorasSemana({ editor, persona }: { editor: EditorHorario; persona: Persona | null }) {
  const maxLegal = persona ? maximoSemanalPracticante(persona.tipo_vinculo, persona.practicante_modalidad) : null;
  if (maxLegal !== null) {
    const seExcede = editor.totalSemana > maxLegal + 0.01;
    return (
      <div className={`mt-4 rounded-control px-3 py-2 text-sm ${seExcede ? "bg-rojo/10" : "bg-sand/30"}`}>
        Total semana: <span className="font-medium text-tinta">{fmtH(editor.totalSemana)}</span>
        <span className="text-taupe"> · máximo legal {maxLegal} h ({persona?.practicante_modalidad})</span>
        {seExcede && (
          <span className="text-rojo"> — supera el máximo del art. 44, Ley 28518, por {fmtH(editor.totalSemana - maxLegal)}</span>
        )}
      </div>
    );
  }
  if (persona?.tipo_vinculo === "practicante") {
    return (
      <div className="mt-4 rounded-control bg-ambar/10 px-3 py-2 text-sm text-ambar">
        Total semana: {fmtH(editor.totalSemana)} — falta fijarle la modalidad en Equipo (preprofesional o
        profesional) para poder avisar si esto supera su máximo legal.
      </div>
    );
  }
  return (
    <div className="mt-4 rounded-control bg-sand/30 px-3 py-2 text-sm">
      Total semana: <span className="font-medium text-tinta">{fmtH(editor.totalSemana)}</span>
      <span className="text-taupe"> · meta {META_SEMANA} h</span>
      {editor.totalSemana > META_SEMANA + 0.01 && <span className="text-ambar"> (te pasas {fmtH(editor.totalSemana - META_SEMANA)})</span>}
      {editor.totalSemana < META_SEMANA - 0.01 && <span className="text-taupe"> (faltan {fmtH(META_SEMANA - editor.totalSemana)})</span>}
    </div>
  );
}

export default function HorariosPage() {
  const router = useRouter();
  const { avisar } = useToast();
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [historiales, setHistoriales] = useState<Map<string, Horario[]>>(new Map());
  const [sedes, setSedes] = useState<Record<string, string>>({});
  const [cargando, setCargando] = useState(true);

  // El tramo VIGENTE de cada persona, derivado del historial completo — el
  // resto de la pantalla (tabla, modal normal) sigue mirando esto tal cual
  // miraba `horarios` antes de que existiera el historial.
  const horarios = useMemo(() => {
    const m = new Map<string, Horario>();
    for (const [id, tramos] of historiales) {
      const vigente = tramos.find((t) => t.vigente_hasta === null);
      if (vigente) m.set(id, vigente);
    }
    return m;
  }, [historiales]);

  const [editando, setEditando] = useState<Persona | null>(null);
  const editor = useEditorHorario();
  const [desde, setDesde] = useState(hoyLima());
  const [guardando, setGuardando] = useState(false);

  // ── Corrección retroactiva (0442): aparte del cambio normal a propósito ──
  const [retro, setRetro] = useState<Persona | null>(null);
  const editorRetro = useEditorHorario();
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
      // Todos los tramos, no solo el vigente — el historial de la 0442 lo
      // necesita. `vigente` se deriva más abajo con useMemo.
      supabase
        .from("horarios_asignados")
        .select("persona_id, hora_entrada, hora_salida, vigente_desde, vigente_hasta, almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horario_por_dia")
        .order("vigente_desde", { ascending: false }),
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
    const porPersona = new Map<string, Horario[]>();
    for (const x of (h as Horario[]) ?? []) {
      const arr = porPersona.get(x.persona_id) ?? [];
      arr.push(x);
      porPersona.set(x.persona_id, arr);
    }
    setHistoriales(porPersona);
    setSedes(Object.fromEntries(((s as any[]) ?? []).map((x) => [x.id, x.codigo])));
    setCargando(false);
  }, [router, avisar]);

  useEffect(() => { void cargar(); }, [cargar]);

  const puedeEditar = puedeOperarEquipo(rol);
  const esSupervisor = rol === "supervisor_sede";
  const editables = useMemo(() => {
    if (!esSupervisor || !yo) return personas;
    return personas.filter((p) => p.id !== yo.id && !ROLES_DO.includes(p.rol));
  }, [personas, esSupervisor, yo]);

  function abrirEdicion(p: Persona) {
    setEditando(p);
    editor.cargarDesde(horarios.get(p.id));
    setDesde(hoyLima());
  }

  function abrirRetro(p: Persona) {
    setRetro(p);
    editorRetro.cargarDesde(horarios.get(p.id));
    setRetroDesde(ayerLima());
    setRetroMotivo("");
    setRetroPreview(null);
  }
  function cerrarRetro() {
    setRetro(null);
    setRetroPreview(null);
    setRetroMotivo("");
  }

  async function guardar() {
    if (!editando) return;
    const horario = editor.construirHorario();
    if (Object.keys(horario).length === 0) { avisar("error", "Marca al menos un día de trabajo."); return; }
    if (editor.faltaEntrada) { avisar("error", "Falta la hora de entrada de algún día."); return; }
    if (editor.faltaSalida) { avisar("error", "Falta la hora de salida de algún día."); return; }
    setGuardando(true);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_set_horario_semanal", {
      p_persona_id: editando.id, p_vigente_desde: desde, p_horario: horario,
    });
    setGuardando(false);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    setEditando(null);
    await cargar();
    avisar("ok", "Horario guardado. Las tardanzas desde esa fecha se recalcularon.");
  }

  const rangoRetroDemasiadoLargo = diasEntreLima(retroDesde, hoyLima()) > MAX_DIAS_RETROACTIVO;

  async function verQueCambiaria() {
    if (!retro) return;
    const horario = editorRetro.construirHorario();
    if (Object.keys(horario).length === 0) { avisar("error", "Marca al menos un día de trabajo."); return; }
    if (editorRetro.faltaEntrada) { avisar("error", "Falta la hora de entrada de algún día."); return; }
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
    const horario = editorRetro.construirHorario();
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

  const porSede = [...new Set(editables.map((p) => sedes[p.sede_base_id] ?? "?"))].sort();

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

        {cargando ? <Cargando /> : porSede.map((sede) => {
          const deSede = editables.filter((p) => (sedes[p.sede_base_id] ?? "?") === sede);
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
                    const h = horarios.get(p.id);
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
                          {!a || a.dias.length === 0 ? <span className="text-taupe">sin horario</span>
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
                        <td className="px-4 py-2 text-taupe">{h ? h.vigente_desde : "—"}</td>
                        <td className="px-4 py-2">
                          <div className="flex items-center justify-end gap-3">
                            <Boton variante="secundario" tamano="sm" onClick={() => abrirEdicion(p)}>
                              {h ? "Cambiar" : "Asignar"}
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

        {/* ── Cambio normal: siempre hacia adelante (0439) ──────────────────── */}
        <Modal
          abierto={editando !== null}
          onCerrar={() => setEditando(null)}
          bloqueado={guardando}
          titulo={editando ? `Horario de ${editando.nombres} ${editando.apellidos}` : undefined}
        >
          <p className="mb-4 text-sm text-taupe">El nuevo horario aplica desde la fecha que elijas en adelante.</p>

          <Campo etiqueta="Vigente desde" type="date" min={hoyLima()} value={desde} onChange={(e) => setDesde(e.target.value)} />
          <p className="mt-1 text-xs text-taupe">
            ¿El cambio ya ocurrió hace días? Esto ya no acepta una fecha pasada — cierra este modal y usa
            «corregir pasado» junto al nombre.
          </p>

          <EditorHorarioPorDia editor={editor} />
          <ResumenHorasSemana editor={editor} persona={editando} />

          {editando && (historiales.get(editando.id)?.length ?? 0) > 1 && (
            <div className="mt-4 border-t border-sand pt-3">
              <p className="mb-1.5 text-sm text-taupe">Historial de horarios</p>
              <ul className="flex flex-col gap-1 text-xs text-taupe">
                {historiales.get(editando.id)!.map((h, i) => (
                  <li key={i}>
                    {h.vigente_hasta ? `${h.vigente_desde} → ${h.vigente_hasta}` : `${h.vigente_desde} → vigente`}
                    <span className="text-tinta"> · {resumenTramo(h)}</span>
                  </li>
                ))}
              </ul>
            </div>
          )}

          <div className="mt-5 flex justify-end gap-3">
            <Boton variante="secundario" onClick={() => setEditando(null)} disabled={guardando}>Cancelar</Boton>
            <Boton variante="primario" onClick={guardar} cargando={guardando}>Guardar horario</Boton>
          </div>
        </Modal>

        {/* ── Corrección retroactiva (0442): aparte, con motivo y vista previa ── */}
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

          <EditorHorarioPorDia editor={editorRetro} />
          <ResumenHorasSemana editor={editorRetro} persona={retro} />

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
