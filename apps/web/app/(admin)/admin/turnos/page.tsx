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
interface Horario { hora_entrada: string; hora_salida: string; dias_laborables: number[]; horario_por_dia: Record<string, { e: string; s: string }> | null; vigente_desde: string; vigente_hasta: string | null; }
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
  | { tipo: "turno"; entrada: string; salida: string | null }
  | { tipo: "default"; entrada: string; salida: string | null }
  | { tipo: "descanso" }
  | { tipo: "libre" };

const ROLES_ADMIN = ["admin", "lider_do"];
const hhmm = (t?: string | null) => (t ? t.slice(0, 5) : "");

export default function TurnosPage() {
  const router = useRouter();
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;
  const esAdmin = rol === "admin" || rol === "lider_do";
  const puedeVer = esAdmin || rol === "supervisor_sede";

  const [sedes, setSedes] = useState<Sede[]>([]);
  const [sedeSel, setSedeSel] = useState<string>("");
  const [lunes, setLunes] = useState<string>(() => lunesDeLaSemana(hoyLima()));

  const [personas, setPersonas] = useState<Persona[]>([]);
  const [areas, setAreas] = useState<Area[]>(AREAS_FALLBACK);
  const [funcionesFallo, setFuncionesFallo] = useState(false);
  const [horarios, setHorarios] = useState<Map<string, Horario[]>>(new Map());
  const [turnos, setTurnos] = useState<Map<string, Turno>>(new Map());
  const [metas, setMetas] = useState<Map<number, number>>(new Map());
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
      supabase.from("metas_cobertura").select("dia_semana, meta").eq("sede_id", sedeSel),
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
        if (d) return { tipo: "default", entrada: hhmm(d.e), salida: hhmm(d.s) };
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
              Arma la semana por sede. Toca una celda para poner el turno o marcar descanso. La fila de abajo
              te dice si la sede está cubierta según la meta del día.
            </p>
          </div>
          <div className="flex items-center gap-2">
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

        {cargando ? <p className="text-sm text-taupe">Cargando…</p> : (
          <div className="overflow-x-auto rounded-lg border border-sand">
            <table className="w-full border-collapse text-sm [font-variant-numeric:tabular-nums]">
              <thead>
                <tr className="bg-sand/50 text-left text-taupe">
                  <th className="sticky left-0 z-10 bg-sand/50 px-3 py-2 font-normal">Persona</th>
                  {dias.map((iso) => {
                    const { abr, num } = etiquetaDia(iso);
                    const hoy = iso === hoyLima();
                    return (
                      <th key={iso} className={`px-2 py-2 text-center font-normal ${hoy ? "text-tinta" : ""}`}>
                        <div className={hoy ? "font-medium" : ""}>{abr}</div>
                        <div className="text-xs text-taupe">{num}</div>
                      </th>
                    );
                  })}
                </tr>
              </thead>
              <tbody>
                {personas.length === 0 ? (
                  <tr><td colSpan={8} className="px-3 py-6 text-center text-taupe">No hay personas activas en esta sede.</td></tr>
                ) : personas.map((p) => (
                  <tr key={p.id} className="border-t border-sand">
                    <td className="sticky left-0 z-10 bg-crema px-3 py-2 whitespace-nowrap">
                      {p.nombres} {p.apellidos}
                      {!esOperativaEn(areas, p.funcion) && (
                        <span className="ml-2 whitespace-nowrap rounded-full bg-ambar/15 px-1.5 py-0.5 text-[10px] text-ambar">{areaCorto(areas, p.funcion)}</span>
                      )}
                    </td>
                    {dias.map((iso) => {
                      const c = celda(p.id, iso);
                      return (
                        <td key={iso} className="border-l border-sand/60 p-1 text-center">
                          <button onClick={() => abrir(p.id, iso)} className="w-full rounded px-1 py-1.5 text-xs transition-colors hover:bg-sand/40">
                            {c.tipo === "turno" && <span className="text-tinta">{c.entrada}{c.salida ? `–${c.salida}` : ""}</span>}
                            {c.tipo === "default" && <span className="italic text-taupe">{c.entrada}{c.salida ? `–${c.salida}` : ""}</span>}
                            {c.tipo === "descanso" && <span className="rounded bg-sand px-1.5 py-0.5 text-taupe">descanso</span>}
                            {c.tipo === "libre" && <span className="text-taupe/40">+</span>}
                          </button>
                        </td>
                      );
                    })}
                  </tr>
                ))}
              </tbody>
              <tfoot>
                <tr className="border-t-2 border-sand bg-crema">
                  <td className="sticky left-0 z-10 bg-crema px-3 py-2 text-taupe">Programados / meta</td>
                  {dias.map((iso) => {
                    const prog = cobertura(iso);
                    const meta = metas.get(diaSemana(iso)) ?? 0;
                    let clase = "text-taupe";
                    if (meta > 0 && prog < meta) clase = "text-rojo font-medium";
                    else if (meta > 0 && prog === meta) clase = "text-verde font-medium";
                    else if (meta > 0 && prog > meta) clase = "text-ambar font-medium";
                    return (
                      <td key={iso} className="border-l border-sand/60 px-2 py-2 text-center">
                        <div className={clase}>{prog}{meta > 0 ? ` / ${meta}` : ""}</div>
                        {meta > 0 && prog < meta && <div className="text-[10px] text-rojo">faltan {meta - prog}</div>}
                        {meta > 0 && prog > meta && <div className="text-[10px] text-ambar">sobran {prog - meta}</div>}
                      </td>
                    );
                  })}
                </tr>
                <tr className="border-t border-sand bg-crema">
                  <td className="sticky left-0 z-10 bg-crema px-3 py-2 text-taupe">Meta de la sede</td>
                  {dias.map((iso) => {
                    const dia = diaSemana(iso);
                    return (
                      <td key={iso} className="border-l border-sand/60 px-2 py-1.5 text-center">
                        {esAdmin ? (
                          <input type="number" min={0} value={metas.get(dia) ?? 0}
                            onChange={(e) => editarMeta(dia, e.target.value)}
                            onBlur={(e) => comprometerMeta(dia, e.target.value)}
                            className="w-12 rounded border border-sand bg-crema px-1 py-0.5 text-center text-xs" />
                        ) : (
                          <span className="text-xs text-taupe">{metas.get(dia) ?? "—"}</span>
                        )}
                      </td>
                    );
                  })}
                </tr>
              </tfoot>
            </table>
          </div>
        )}

        <p className="mt-3 text-xs text-taupe">
          <span className="italic">En cursiva</span> = horario por defecto del periodo (no se ha fijado turno ese día).
          La cobertura cuenta solo a las <strong>áreas operativas de sede</strong> ({areas.filter((a) => a.operativa && a.activa).map((a) => a.nombre).join(", ")})
          que trabajan; el descanso y las demás áreas (etiqueta ámbar) no cuentan. El área se cambia en Equipo.
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
