"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { AdminNav } from "../nav";

const TZ = "America/Lima";

function hoyLima(): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: TZ }).format(new Date());
}
// Fechas planas (sin hora): se formatean en UTC para que no se corran un día.
function fechaCorta(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "short", timeZone: "UTC" })
    .format(new Date(Date.UTC(y, m - 1, d)));
}
function diaSemana(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { weekday: "long", timeZone: "UTC" })
    .format(new Date(Date.UTC(y, m - 1, d)));
}
const soles = (n: number) => `S/ ${n.toFixed(2)}`;

interface Persona { id: string; nombres: string; apellidos: string; }
interface Feriado { fecha: string; nombre: string; }
// Una fila por persona que TRABAJÓ un feriado del rango, con su estado de
// compensación. `estado` en null = todavía se le está pagando la sobretasa.
interface Laborado {
  persona_id: string;
  nombre: string;
  sede: string;
  fecha_feriado: string;
  feriado_nombre: string;
  horas: number;
  sobretasa: number | null;
  dcs_id: string | null;
  fecha_descanso: string | null;
  estado: string | null;
  acta_ref: string | null;
}
interface Registro {
  id: string;
  persona_id: string;
  fecha_feriado: string;
  fecha_descanso_sustitutorio: string;
  estado: string;
  acta_ref: string | null;
}

const ESTADOS = ["PENDIENTE", "OTORGADO", "NO_OTORGADO"] as const;

// Primer día del mes en curso, en Lima.
function inicioDeMes(): string {
  return `${hoyLima().slice(0, 7)}-01`;
}
function finDeMes(): string {
  const [y, m] = hoyLima().split("-").map(Number);
  return new Intl.DateTimeFormat("en-CA", { timeZone: "UTC" }).format(new Date(Date.UTC(y, m, 0)));
}

export default function FeriadosPage() {
  const router = useRouter();
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;
  const puedeGestionar = rol === "admin" || rol === "lider_do";

  const [personas, setPersonas] = useState<Persona[]>([]);
  const [feriados, setFeriados] = useState<Feriado[]>([]);
  const [laborados, setLaborados] = useState<Laborado[]>([]);
  const [registros, setRegistros] = useState<Registro[]>([]);
  const [cargando, setCargando] = useState(true);
  const [msg, setMsg] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);

  // rango de consulta
  const [desde, setDesde] = useState(inicioDeMes());
  const [hasta, setHasta] = useState(finDeMes());

  // formulario
  const [personaId, setPersonaId] = useState("");
  const [fechaFeriado, setFechaFeriado] = useState("");
  const [fechaDescanso, setFechaDescanso] = useState("");
  const [estado, setEstado] = useState<string>("PENDIENTE");
  const [actaRef, setActaRef] = useState("");
  const [guardando, setGuardando] = useState(false);

  const supabase = useMemo(() => createAdminSupabaseClient(), []);

  const cargar = useCallback(async () => {
    setCargando(true);
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    const [{ data: p, error: eP }, { data: f }, { data: l, error: eL }, { data: r }] = await Promise.all([
      supabase.from("personas").select("id, nombres, apellidos")
        .eq("estado", "activo").eq("en_planilla", true).order("nombres"),
      supabase.from("feriados").select("fecha, nombre").order("fecha", { ascending: false }).limit(40),
      supabase.rpc("fn_feriados_laborados", { p_desde: desde, p_hasta: hasta }),
      supabase.from("feriados_descanso_sustitutorio")
        .select("id, persona_id, fecha_feriado, fecha_descanso_sustitutorio, estado, acta_ref")
        .order("fecha_feriado", { ascending: false }),
    ]);
    if (eP) {
      setMsg({ tipo: "error", texto: `No se pudo cargar: ${eP.message}` });
      setCargando(false);
      return;
    }
    setPersonas((p as Persona[]) ?? []);
    setFeriados((f as Feriado[]) ?? []);
    setLaborados(eL ? [] : ((l as unknown as Laborado[]) ?? []));
    setRegistros((r as Registro[]) ?? []);
    setCargando(false);
  }, [supabase, router, desde, hasta]);

  useEffect(() => { void cargar(); }, [cargar]);

  const nombrePorId = useMemo(
    () => new Map(personas.map((x) => [x.id, `${x.nombres} ${x.apellidos}`])),
    [personas],
  );

  // Lo que hoy se está pagando de más por no haber registrado la compensación.
  const sobretasaSinResolver = useMemo(
    () => laborados
      .filter((l) => l.estado !== "OTORGADO")
      .reduce((acc, l) => acc + (l.sobretasa ?? 0), 0),
    [laborados],
  );

  async function registrar() {
    if (!personaId) { setMsg({ tipo: "error", texto: "Elige a la persona." }); return; }
    if (!fechaFeriado) { setMsg({ tipo: "error", texto: "Elige el feriado laborado." }); return; }
    if (!fechaDescanso) { setMsg({ tipo: "error", texto: "Elige el día de descanso compensatorio." }); return; }
    setGuardando(true);
    setMsg(null);
    const { error } = await supabase.rpc("fn_otorgar_descanso_sustitutorio", {
      p_persona_id: personaId,
      p_fecha_feriado: fechaFeriado,
      p_fecha_descanso: fechaDescanso,
      p_estado: estado,
      p_acta_ref: actaRef.trim() || null,
    });
    setGuardando(false);
    // El mensaje de la base ya viene en lenguaje claro (día de descanso semanal,
    // acta faltante, feriado no laborado): se muestra tal cual.
    if (error) { setMsg({ tipo: "error", texto: error.message }); return; }
    setActaRef("");
    await cargar();
    setMsg({ tipo: "ok", texto: `Descanso sustitutorio registrado como ${estado}.` });
  }

  async function quitar(id: string) {
    setGuardando(true);
    setMsg(null);
    const { error } = await supabase.rpc("fn_quitar_descanso_sustitutorio", { p_id: id });
    setGuardando(false);
    if (error) { setMsg({ tipo: "error", texto: error.message }); return; }
    await cargar();
    setMsg({ tipo: "ok", texto: "Registro quitado. Ese feriado vuelve a pagar sobretasa." });
  }

  if (rol !== null && !puedeGestionar) {
    return (
      <div className="flex min-h-screen flex-col">
        <AdminNav />
        <main className="flex flex-1 items-center justify-center p-6">
          <p className="max-w-md text-center text-taupe">No tienes permiso para gestionar feriados.</p>
        </main>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <h1 className="mb-1 font-serif text-2xl">Feriados laborados</h1>
        <p className="mb-5 max-w-3xl text-sm text-taupe">
          Quien trabaja un feriado cobra <strong>triple</strong>, salvo que se le dé un{" "}
          <strong>día libre a cambio</strong>. Registrar aquí ese día libre hace dos cosas: quita la
          sobretasa de la planilla del periodo, y evita que ese día le salga como{" "}
          <strong>falta injustificada</strong> por no marcar.
        </p>

        {msg && (
          <div className={`mb-4 max-w-3xl rounded-lg px-4 py-3 text-sm ${msg.tipo === "ok" ? "bg-sand/40 text-tinta" : "bg-rojo/10 text-rojo"}`}>
            {msg.texto}
          </div>
        )}

        {/* Registrar */}
        <div className="mb-6 max-w-4xl rounded-2xl border border-sand bg-papel p-5">
          <h2 className="mb-3 text-sm font-medium">Registrar un día libre a cambio</h2>
          <div className="flex flex-wrap items-end gap-3">
            <label className="flex flex-col gap-1 text-sm">
              Persona
              <select value={personaId} onChange={(e) => setPersonaId(e.target.value)}
                className="min-w-56 rounded-lg border bg-crema px-3 py-2">
                <option value="">Elegir…</option>
                {personas.map((p) => <option key={p.id} value={p.id}>{p.nombres} {p.apellidos}</option>)}
              </select>
            </label>
            <label className="flex flex-col gap-1 text-sm">
              Feriado laborado
              <select value={fechaFeriado} onChange={(e) => setFechaFeriado(e.target.value)}
                className="min-w-56 rounded-lg border bg-crema px-3 py-2">
                <option value="">Elegir…</option>
                {feriados.map((f) => (
                  <option key={f.fecha} value={f.fecha}>{fechaCorta(f.fecha)} — {f.nombre}</option>
                ))}
              </select>
            </label>
            <label className="flex flex-col gap-1 text-sm">
              Día libre a cambio
              <input type="date" value={fechaDescanso} onChange={(e) => setFechaDescanso(e.target.value)}
                className="rounded-lg border px-3 py-2" />
              {fechaDescanso && (
                <span className="text-xs capitalize text-taupe">{diaSemana(fechaDescanso)}</span>
              )}
            </label>
            <label className="flex flex-col gap-1 text-sm">
              Estado
              <select value={estado} onChange={(e) => setEstado(e.target.value)}
                className="rounded-lg border bg-crema px-3 py-2">
                {ESTADOS.map((e) => <option key={e} value={e}>{e}</option>)}
              </select>
            </label>
          </div>
          <label className="mt-3 flex max-w-xl flex-col gap-1 text-sm">
            Acta firmada {estado === "OTORGADO" && <span className="text-rojo">· obligatoria para OTORGADO</span>}
            <input value={actaRef} onChange={(e) => setActaRef(e.target.value)}
              className="rounded-lg border px-3 py-2" placeholder="ej. Acta 2026-07-28 Taller LIM" />
          </label>

          {/* Qué significa cada estado, en el momento de elegirlo. */}
          <p className="mt-3 max-w-2xl text-xs text-taupe">
            {estado === "PENDIENTE" && "Acuerdo tomado, todavía sin confirmar. La planilla sigue pagando la sobretasa, pero el día libre ya NO cuenta como falta."}
            {estado === "OTORGADO" && "El descanso se dio y está respaldado. Quita la sobretasa de la planilla. Requiere acta firmada y que el feriado ya tenga horas marcadas."}
            {estado === "NO_OTORGADO" && "El descanso no se dio. La planilla vuelve a pagar la sobretasa y el día deja de estar justificado."}
          </p>

          <button onClick={registrar} disabled={guardando}
            className="mt-3 rounded-lg bg-tinta px-5 py-2 text-sm font-medium text-crema disabled:opacity-50">
            {guardando ? "Guardando…" : "Registrar"}
          </button>
        </div>

        {/* Quién trabajó feriados en el rango */}
        <div className="max-w-5xl overflow-hidden rounded-2xl border border-sand bg-papel">
          <div className="border-b bg-sand/50 px-4 py-2">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <h2 className="text-sm font-medium">Quién trabajó feriados</h2>
              <div className="flex items-center gap-2 text-xs">
                <input type="date" value={desde} onChange={(e) => setDesde(e.target.value)}
                  className="rounded border px-2 py-1" />
                <span className="text-taupe">→</span>
                <input type="date" value={hasta} onChange={(e) => setHasta(e.target.value)}
                  className="rounded border px-2 py-1" />
              </div>
            </div>
            {sobretasaSinResolver > 0 && (
              <p className="mt-1 text-xs text-taupe">
                Sobretasa que se pagaría hoy por los feriados sin compensación otorgada:{" "}
                <strong className="text-tinta">{soles(sobretasaSinResolver)}</strong>
              </p>
            )}
          </div>
          {cargando ? (
            <p className="px-4 py-6 text-sm text-taupe">Cargando…</p>
          ) : laborados.length === 0 ? (
            <p className="px-4 py-6 text-sm text-taupe">Nadie marcó horas en un feriado de este rango.</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full min-w-[720px] text-sm">
                <thead className="bg-sand/70 text-left text-taupe">
                  <tr>
                    <th className="px-4 py-2 font-normal">Persona</th>
                    <th className="px-4 py-2 font-normal">Feriado</th>
                    <th className="px-4 py-2 text-right font-normal">Horas</th>
                    <th className="px-4 py-2 text-right font-normal">Sobretasa</th>
                    <th className="px-4 py-2 font-normal">Compensación</th>
                  </tr>
                </thead>
                <tbody>
                  {laborados.map((l) => (
                    <tr key={`${l.persona_id}-${l.fecha_feriado}`} className="border-t align-top">
                      <td className="px-4 py-2">
                        {l.nombre}
                        <div className="text-xs text-taupe">{l.sede}</div>
                      </td>
                      <td className="px-4 py-2">
                        {fechaCorta(l.fecha_feriado)}
                        <div className="text-xs text-taupe">{l.feriado_nombre}</div>
                      </td>
                      <td className="px-4 py-2 text-right tabular-nums">{l.horas}</td>
                      <td className={`px-4 py-2 text-right tabular-nums ${l.estado === "OTORGADO" ? "text-taupe line-through" : ""}`}>
                        {l.sobretasa === null ? <span className="text-taupe/60">sin salario</span> : soles(l.sobretasa)}
                      </td>
                      <td className="px-4 py-2">
                        {l.estado === null ? (
                          <span className="text-taupe">— paga sobretasa</span>
                        ) : (
                          <>
                            <span className={l.estado === "OTORGADO" ? "font-medium text-tinta" : "text-taupe"}>
                              {l.estado}
                            </span>
                            {l.fecha_descanso && (
                              <div className="text-xs text-taupe">libre el {fechaCorta(l.fecha_descanso)}</div>
                            )}
                          </>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>

        {/* Registros existentes — incluye los de feriados futuros, que no salen arriba */}
        <div className="mt-6 max-w-4xl overflow-hidden rounded-2xl border border-sand bg-papel">
          <h2 className="border-b bg-sand/50 px-4 py-2 text-sm font-medium">
            Descansos registrados {registros.length > 0 && <span className="font-normal text-taupe">· {registros.length}</span>}
          </h2>
          {registros.length === 0 ? (
            <p className="px-4 py-6 text-sm text-taupe">Todavía no hay descansos sustitutorios registrados.</p>
          ) : (
            <ul className="divide-y">
              {registros.map((r) => (
                <li key={r.id} className="px-4 py-3 text-sm">
                  <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
                    <span>
                      <strong>{nombrePorId.get(r.persona_id) ?? "—"}</strong>{" "}
                      <span className="text-taupe">
                        · trabajó el {fechaCorta(r.fecha_feriado)} · libre el {fechaCorta(r.fecha_descanso_sustitutorio)}
                      </span>{" "}
                      <span className={r.estado === "OTORGADO" ? "font-medium" : "text-taupe"}>· {r.estado}</span>
                    </span>
                    <button onClick={() => quitar(r.id)} disabled={guardando}
                      className="rounded border border-rojo/30 px-2 py-0.5 text-xs text-rojo hover:bg-rojo/10 disabled:opacity-40">
                      Quitar
                    </button>
                  </div>
                  {r.acta_ref && <p className="mt-1 text-xs text-taupe">Acta: {r.acta_ref}</p>}
                </li>
              ))}
            </ul>
          )}
        </div>
      </main>
    </div>
  );
}
