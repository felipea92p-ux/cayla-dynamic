"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { AdminNav } from "../nav";
import { Cargando } from "@/components/cargando";

const META_SEMANA = 45; // horas objetivo por semana (7.5h × 6 días)

function fechaHoyLima() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Lima" }).format(new Date());
}
function toMin(hhmm: string): number {
  const [h, m] = (hhmm || "0:0").split(":").map(Number);
  return (h || 0) * 60 + (m || 0);
}
// horas netas del día = (salida − entrada) − refrigerio
function horasDia(e: string, s: string, r: number): number {
  return Math.max(0, toMin(s) - toMin(e) - (r || 0)) / 60;
}
function fmtH(h: number): string {
  return `${Math.round(h * 100) / 100} h`;
}

type Dia = { e: string; s: string; r: number };
type PorDia = Record<number, Dia>;
interface Persona { id: string; nombres: string; apellidos: string; rol: string; sede_base_id: string; }
interface Horario {
  persona_id: string; hora_entrada: string; hora_salida: string; vigente_desde: string;
  almuerzo_min_minutos: number; almuerzo_max_minutos: number; dias_laborables: number[];
  horario_por_dia: Record<string, { e: string; s: string; r?: number }> | null;
}
const ROLES_ADMIN = ["admin", "lider_do"];
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

export default function HorariosPage() {
  const router = useRouter();
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [horarios, setHorarios] = useState<Map<string, Horario>>(new Map());
  const [sedes, setSedes] = useState<Record<string, string>>({});
  const [cargando, setCargando] = useState(true);
  const [mensaje, setMensaje] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);

  const [editando, setEditando] = useState<Persona | null>(null);
  const [modoPorDia, setModoPorDia] = useState(false);
  const [entrada, setEntrada] = useState("08:00");   // modo rápido
  const [salida, setSalida] = useState("18:00");     // modo rápido
  const [refri, setRefri] = useState(60);            // modo rápido (min)
  const [dias, setDias] = useState<number[]>([1, 2, 3, 4, 5, 6]);
  const [porDia, setPorDia] = useState<PorDia>({});  // modo por día
  const [desde, setDesde] = useState(fechaHoyLima());
  const [guardando, setGuardando] = useState(false);

  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    setCargando(true);
    const [
      { data: p, error: errP },
      { data: h, error: errH },
      { data: s, error: errS },
    ] = await Promise.all([
      supabase.from("personas").select("id, nombres, apellidos, rol, sede_base_id").eq("estado", "activo").order("nombres"),
      supabase.from("horarios_asignados").select("persona_id, hora_entrada, hora_salida, vigente_desde, almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horario_por_dia").is("vigente_hasta", null),
      supabase.from("sedes").select("id, codigo"),
    ]);
    if (errP || errH || errS) {
      setMensaje({ tipo: "error", texto: `No se pudo cargar: ${(errP ?? errH ?? errS)!.message}` });
      setCargando(false);
      return; // no pisa `personas`/`horarios`/`sedes` con datos parciales
    }
    setPersonas((p as Persona[]) ?? []);
    setHorarios(new Map(((h as Horario[]) ?? []).map((x) => [x.persona_id, x])));
    setSedes(Object.fromEntries(((s as any[]) ?? []).map((x) => [x.id, x.codigo])));
    setCargando(false);
  }, [router]);

  useEffect(() => { void cargar(); }, [cargar]);

  const puedeEditar = rol === "admin" || rol === "lider_do" || rol === "supervisor_sede";
  const esSupervisor = rol === "supervisor_sede";
  const editables = useMemo(() => {
    if (!esSupervisor || !yo) return personas;
    return personas.filter((p) => p.id !== yo.id && !ROLES_ADMIN.includes(p.rol));
  }, [personas, esSupervisor, yo]);

  function abrirEdicion(p: Persona) {
    const a = analizar(horarios.get(p.id));
    setEditando(p);
    setPorDia(a.porDia);
    setDias(a.dias.length ? a.dias : [1, 2, 3, 4, 5, 6]);
    setEntrada(a.e);
    setSalida(a.s);
    setRefri(a.r);
    setModoPorDia(!a.uniforme);
    setDesde(fechaHoyLima());
    setMensaje(null);
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

  async function guardar() {
    if (!editando) return;
    const horario = construirHorario();
    const keys = Object.keys(horario);
    if (keys.length === 0) { setMensaje({ tipo: "error", texto: "Marca al menos un día de trabajo." }); return; }
    const faltaEntrada = modoPorDia ? Object.values(porDia).some((v) => !v.e) : !entrada;
    const faltaSalida = modoPorDia ? Object.values(porDia).some((v) => !v.s) : !salida;
    if (faltaEntrada) { setMensaje({ tipo: "error", texto: "Falta la hora de entrada de algún día." }); return; }
    if (faltaSalida) { setMensaje({ tipo: "error", texto: "Falta la hora de salida de algún día." }); return; }
    setGuardando(true);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_set_horario_semanal", {
      p_persona_id: editando.id, p_vigente_desde: desde, p_horario: horario,
    });
    setGuardando(false);
    if (error) { setMensaje({ tipo: "error", texto: error.message }); return; }
    setEditando(null);
    await cargar();
    setMensaje({ tipo: "ok", texto: "Horario guardado. Las tardanzas desde esa fecha se recalcularon." });
  }

  if (rol !== null && !puedeEditar) {
    return (
      <div className="flex min-h-screen flex-col"><AdminNav />
        <main className="flex flex-1 items-center justify-center p-6">
          <p className="max-w-md text-center text-taupe">No tienes permiso para editar horarios.</p>
        </main>
      </div>
    );
  }

  const porSede = [...new Set(editables.map((p) => sedes[p.sede_base_id] ?? "?"))].sort();

  // total semanal del formulario abierto
  const totalSemana = modoPorDia
    ? Object.values(porDia).reduce((acc, v) => acc + horasDia(v.e, v.s, v.r), 0)
    : horasDia(entrada, salida, refri) * dias.length;

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <h1 className="mb-1 font-serif text-2xl">Horarios base</h1>
        <p className="mb-5 max-w-2xl text-sm text-taupe">
          El horario de cada persona puede tener una hora distinta por día (martes 8:00, miércoles 14:00…),
          con su refrigerio, y se repite cada semana. La hora de entrada define la tardanza. Al cambiar un
          horario, elige la fecha desde la que aplica — el anterior se conserva y no altera tardanzas pasadas.
        </p>

        {mensaje && (
          <div className={`mb-4 max-w-2xl rounded-lg px-4 py-3 text-sm ${mensaje.tipo === "ok" ? "bg-sand/40 text-tinta" : "bg-rojo/10 text-rojo"}`}>{mensaje.texto}</div>
        )}

        {cargando ? <Cargando /> : porSede.map((sede) => {
          const deSede = editables.filter((p) => (sedes[p.sede_base_id] ?? "?") === sede);
          return (
            <section key={sede} className="mb-8">
              <h2 className="mb-2 font-serif text-lg">{sede}</h2>
              <div className="overflow-x-auto rounded-lg border">
                <table className="w-full text-sm [font-variant-numeric:tabular-nums]">
                  <thead className="bg-sand/50 text-left text-taupe">
                    <tr>
                      <th className="px-4 py-2 font-normal">Nombre</th>
                      <th className="px-4 py-2 font-normal">Horario</th>
                      <th className="px-4 py-2 font-normal">Semana</th>
                      <th className="px-4 py-2 font-normal">Descanso</th>
                      <th className="px-4 py-2 font-normal">Vigente desde</th>
                      <th className="px-4 py-2 font-normal"></th>
                    </tr>
                  </thead>
                  <tbody>
                    {deSede.map((p) => {
                      const h = horarios.get(p.id);
                      const a = h ? analizar(h) : null;
                      const semana = a ? a.dias.reduce((acc, d) => acc + horasDia(a.porDia[d].e, a.porDia[d].s, a.porDia[d].r), 0) : 0;
                      return (
                        <tr key={p.id} className="border-t">
                          <td className="px-4 py-2">{p.nombres} {p.apellidos}</td>
                          <td className="px-4 py-2">
                            {!a || a.dias.length === 0 ? <span className="text-taupe/50">sin horario</span>
                              : a.uniforme ? `${a.e}–${a.s}` : <span className="text-taupe">varía por día</span>}
                          </td>
                          <td className="px-4 py-2 text-taupe">{a && a.dias.length ? fmtH(semana) : "—"}</td>
                          <td className="px-4 py-2 text-taupe">{a ? textoDescanso(a.dias) : "—"}</td>
                          <td className="px-4 py-2 text-taupe">{h ? h.vigente_desde : "—"}</td>
                          <td className="px-4 py-2">
                            <button onClick={() => abrirEdicion(p)} className="rounded border px-2 py-1 text-xs hover:bg-sand/50">
                              {h ? "Cambiar" : "Asignar"}
                            </button>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </section>
          );
        })}

        {editando && (
          <div className="fixed inset-0 z-10 flex items-center justify-center bg-black/40 p-4" onClick={() => !guardando && setEditando(null)}>
            <div className="max-h-[90vh] w-full max-w-md overflow-y-auto rounded-xl border border-sand bg-crema p-6" onClick={(e) => e.stopPropagation()}>
              <h3 className="mb-1 font-serif text-lg">Horario de {editando.nombres} {editando.apellidos}</h3>
              <p className="mb-4 text-sm text-taupe">El nuevo horario aplica desde la fecha que elijas en adelante.</p>

              <label className="flex flex-col gap-1 text-sm">Vigente desde
                <input type="date" value={desde} onChange={(e) => setDesde(e.target.value)} className="rounded-lg border px-3 py-2" /></label>

              <label className="mt-4 flex items-center gap-2 text-sm">
                <input type="checkbox" checked={!modoPorDia} onChange={(e) => cambiarModo(!e.target.checked)} />
                Misma hora todos los días
              </label>

              {!modoPorDia ? (
                <>
                  <div className="mt-3 grid grid-cols-3 gap-3">
                    <label className="flex flex-col gap-1 text-sm">Entrada
                      <input type="time" value={entrada} onChange={(e) => setEntrada(e.target.value)} className="rounded-lg border px-2 py-2" /></label>
                    <label className="flex flex-col gap-1 text-sm">Salida
                      <input type="time" value={salida} onChange={(e) => setSalida(e.target.value)} className="rounded-lg border px-2 py-2" /></label>
                    <label className="flex flex-col gap-1 text-sm">Refrig. (min)
                      <input type="number" min={0} value={refri} onChange={(e) => setRefri(Math.max(0, Math.round(Number(e.target.value) || 0)))} className="rounded-lg border px-2 py-2" /></label>
                  </div>
                  <p className="mt-2 text-xs text-taupe">Cada día: <span className="text-tinta">{fmtH(horasDia(entrada, salida, refri))}</span></p>
                  <div className="mt-3">
                    <p className="mb-1.5 text-sm">Días de trabajo <span className="text-taupe">(los que no marcas son descanso)</span></p>
                    <div className="flex gap-1.5">
                      {DIAS.map((d) => {
                        const on = dias.includes(d.v);
                        return (
                          <button key={d.v} type="button" onClick={() => toggleDia(d.v)}
                            className={`h-9 w-9 rounded-lg border text-sm ${on ? "border-tinta bg-tinta text-crema" : "border-sand text-taupe hover:bg-sand/40"}`}>
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
                            className={`h-8 w-14 shrink-0 rounded-lg border text-xs capitalize ${activo ? "border-tinta bg-tinta text-crema" : "border-sand text-taupe hover:bg-sand/40"}`}>
                            {NOMBRE_DIA[d.v].slice(0, 3)}
                          </button>
                          {activo ? (
                            <>
                              <input type="time" value={dd.e} onChange={(e) => setCampoPorDia(d.v, "e", e.target.value)} className="w-[90px] rounded-lg border px-1.5 py-1 text-sm" />
                              <span className="text-taupe">–</span>
                              <input type="time" value={dd.s} onChange={(e) => setCampoPorDia(d.v, "s", e.target.value)} className="w-[90px] rounded-lg border px-1.5 py-1 text-sm" />
                              <input type="number" min={0} value={dd.r} onChange={(e) => setRefriPorDia(d.v, e.target.value)} title="refrigerio (min)" className="w-12 rounded-lg border px-1 py-1 text-sm" />
                              <span className="w-14 text-right text-xs text-tinta">{fmtH(horasDia(dd.e, dd.s, dd.r))}</span>
                            </>
                          ) : <span className="text-sm text-taupe/60">descanso</span>}
                        </div>
                      );
                    })}
                  </div>
                  <p className="mt-1.5 text-xs text-taupe">La columna angosta es el refrigerio en minutos.</p>
                </div>
              )}

              <div className="mt-4 rounded-lg bg-sand/30 px-3 py-2 text-sm">
                Total semana: <span className="font-medium text-tinta">{fmtH(totalSemana)}</span>
                <span className="text-taupe"> · meta {META_SEMANA} h</span>
                {totalSemana > META_SEMANA + 0.01 && <span className="text-ambar"> (te pasas {fmtH(totalSemana - META_SEMANA)})</span>}
                {totalSemana < META_SEMANA - 0.01 && <span className="text-taupe"> (faltan {fmtH(META_SEMANA - totalSemana)})</span>}
              </div>

              <div className="mt-5 flex justify-end gap-3">
                <button onClick={() => setEditando(null)} disabled={guardando} className="rounded-lg border px-4 py-2 text-sm">Cancelar</button>
                <button onClick={guardar} disabled={guardando} className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema disabled:opacity-50">
                  {guardando ? "Guardando…" : "Guardar horario"}
                </button>
              </div>
            </div>
          </div>
        )}
      </main>
    </div>
  );
}
