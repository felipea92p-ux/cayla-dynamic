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
// Fechas de vacaciones son fechas planas (sin hora): se formatean en UTC para que
// no se corran un día al pasarlas por la zona horaria.
function fechaCorta(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "short", year: "numeric", timeZone: "UTC" })
    .format(new Date(Date.UTC(y, m - 1, d)));
}
// Días del periodo, ambos extremos incluidos (del 1 al 15 = 15 días).
function diasEntre(ini: string, fin: string): number {
  const a = Date.parse(`${ini}T00:00:00Z`);
  const b = Date.parse(`${fin}T00:00:00Z`);
  if (isNaN(a) || isNaN(b) || b < a) return 0;
  return Math.round((b - a) / 86_400_000) + 1;
}
function selloLima(iso: string): string {
  const d = new Date(iso);
  if (isNaN(d.getTime())) return iso;
  return new Intl.DateTimeFormat("es-PE", { timeZone: TZ, day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit", hour12: true }).format(d);
}

const soles = (n: number) => `S/ ${n.toFixed(2)}`;

interface Persona { id: string; nombres: string; apellidos: string; }
// Resumen por persona (fn_vacaciones_resumen). Es SOLO INFORMATIVO: el monto es
// un estimado para comparar contra el cálculo a mano, no se paga automáticamente.
interface Resumen {
  persona_id: string;
  nombre: string;
  dias_ganados: number;
  dias_tomados: number;
  dias_saldo: number;
  dias_con_marca: number;
  horas_marcadas: number;
  feriados_en_periodo: number;
  horas_feriados: number;
  horas_base: number;
  factor: number;
  salario: number | null;
  monto_estimado: number | null;
  aniversario_next: string;
}
interface Vacacion {
  id: string;
  persona_id: string;
  fecha_inicio: string;
  fecha_fin: string;
  observacion: string | null;
  creado_por: string;
  creado_at: string;
}

export default function VacacionesPage() {
  const router = useRouter();
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;
  const puedeGestionar = rol === "admin" || rol === "lider_do";

  const [personas, setPersonas] = useState<Persona[]>([]);
  const [vacaciones, setVacaciones] = useState<Vacacion[]>([]);
  const [resumen, setResumen] = useState<Resumen[]>([]);
  const [cargando, setCargando] = useState(true);
  const [msg, setMsg] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);

  // formulario
  const [personaId, setPersonaId] = useState("");
  const [inicio, setInicio] = useState(hoyLima());
  const [fin, setFin] = useState(hoyLima());
  const [observacion, setObservacion] = useState("");
  const [guardando, setGuardando] = useState(false);

  const supabase = useMemo(() => createAdminSupabaseClient(), []);

  const cargar = useCallback(async () => {
    setCargando(true);
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    // Sin embeds de PostgREST a propósito (el schema cache de este proyecto está
    // trabado para varias relaciones): el nombre se resuelve desde `personas`.
    const [{ data: p, error: eP }, { data: v, error: eV }, { data: r }] = await Promise.all([
      supabase.from("personas").select("id, nombres, apellidos").eq("estado", "activo").order("nombres"),
      supabase.from("vacaciones")
        .select("id, persona_id, fecha_inicio, fecha_fin, observacion, creado_por, creado_at")
        .order("fecha_inicio", { ascending: false }),
      // Resumen (saldo de días + monto estimado). Falla suave a propósito: es
      // informativo, y si no llega no debe bloquear el registro de vacaciones.
      supabase.rpc("fn_vacaciones_resumen", {}),
    ]);
    if (eP || eV) {
      setMsg({ tipo: "error", texto: `No se pudo cargar: ${(eP ?? eV)!.message}` });
      setCargando(false);
      return; // no pisa la lista con datos parciales
    }
    setPersonas((p as Persona[]) ?? []);
    setVacaciones((v as Vacacion[]) ?? []);
    setResumen(Array.isArray(r) ? (r as unknown as Resumen[]) : []);
    setCargando(false);
  }, [supabase, router]);

  useEffect(() => { void cargar(); }, [cargar]);

  const nombrePorId = useMemo(
    () => new Map(personas.map((x) => [x.id, `${x.nombres} ${x.apellidos}`])),
    [personas],
  );
  const diasForm = diasEntre(inicio, fin);

  async function registrar() {
    if (!personaId) { setMsg({ tipo: "error", texto: "Elige a la persona." }); return; }
    if (diasForm <= 0) { setMsg({ tipo: "error", texto: "La fecha de fin no puede ser anterior a la de inicio." }); return; }
    setGuardando(true);
    setMsg(null);
    const { error } = await supabase.rpc("fn_set_vacaciones", {
      p_persona_id: personaId,
      p_fecha_inicio: inicio,
      p_fecha_fin: fin,
      p_observacion: observacion.trim() || null,
    });
    setGuardando(false);
    if (error) { setMsg({ tipo: "error", texto: error.message }); return; }
    setObservacion("");
    await cargar();
    setMsg({ tipo: "ok", texto: `Vacaciones registradas: ${diasForm} día${diasForm === 1 ? "" : "s"}.` });
  }

  async function quitar(v: Vacacion) {
    setGuardando(true);
    setMsg(null);
    const { error } = await supabase.rpc("fn_quitar_vacaciones", { p_id: v.id });
    setGuardando(false);
    if (error) { setMsg({ tipo: "error", texto: error.message }); return; }
    await cargar();
    setMsg({ tipo: "ok", texto: "Periodo de vacaciones quitado." });
  }

  if (rol !== null && !puedeGestionar) {
    return (
      <div className="flex min-h-screen flex-col">
        <AdminNav />
        <main className="flex flex-1 items-center justify-center p-6">
          <p className="max-w-md text-center text-taupe">No tienes permiso para gestionar vacaciones.</p>
        </main>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <h1 className="mb-1 font-serif text-2xl">Vacaciones</h1>
        <p className="mb-5 max-w-2xl text-sm text-taupe">
          Registra los periodos de descanso vacacional. Marcar aquí las vacaciones evita dos problemas:
          que la persona figure como <strong>falta</strong> todos esos días, y que se le pague de menos
          (las vacaciones son descanso remunerado). Régimen Pequeña Empresa: <strong>15 días por año</strong> de servicios.
        </p>

        {msg && (
          <div className={`mb-4 max-w-2xl rounded-lg px-4 py-3 text-sm ${msg.tipo === "ok" ? "bg-sand/40 text-tinta" : "bg-rojo/10 text-rojo"}`}>
            {msg.texto}
          </div>
        )}

        {/* Registrar un periodo */}
        <div className="mb-6 max-w-3xl rounded-lg border bg-sand/50 p-4">
          <h2 className="mb-3 text-sm font-medium">Registrar un periodo</h2>
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
              Desde
              <input type="date" value={inicio} onChange={(e) => setInicio(e.target.value)} className="rounded-lg border px-3 py-2" />
            </label>
            <label className="flex flex-col gap-1 text-sm">
              Hasta
              <input type="date" value={fin} onChange={(e) => setFin(e.target.value)} className="rounded-lg border px-3 py-2" />
            </label>
            <span className={`pb-2 text-sm ${diasForm > 0 ? "text-tinta" : "text-rojo"}`}>
              {diasForm > 0 ? `${diasForm} día${diasForm === 1 ? "" : "s"}` : "rango inválido"}
            </span>
          </div>
          <label className="mt-3 flex max-w-xl flex-col gap-1 text-sm">
            Observación (opcional)
            <input value={observacion} onChange={(e) => setObservacion(e.target.value)}
              className="rounded-lg border px-3 py-2" placeholder="ej. vacaciones del periodo 2025-2026" />
          </label>
          <button onClick={registrar} disabled={guardando || diasForm <= 0}
            className="mt-3 rounded-lg bg-tinta px-5 py-2 text-sm font-medium text-crema disabled:opacity-50">
            {guardando ? "Guardando…" : "Registrar vacaciones"}
          </button>
        </div>

        {/* Periodos registrados */}
        <div className="max-w-3xl overflow-hidden rounded-lg border">
          <h2 className="border-b bg-sand/50 px-4 py-2 text-sm font-medium">
            Periodos registrados {vacaciones.length > 0 && <span className="font-normal text-taupe">· {vacaciones.length}</span>}
          </h2>
          {cargando ? (
            <p className="px-4 py-6 text-sm text-taupe">Cargando…</p>
          ) : vacaciones.length === 0 ? (
            <p className="px-4 py-6 text-sm text-taupe">Todavía no hay vacaciones registradas.</p>
          ) : (
            <ul className="divide-y">
              {vacaciones.map((v) => {
                const dias = diasEntre(v.fecha_inicio, v.fecha_fin);
                return (
                  <li key={v.id} className="px-4 py-3 text-sm">
                    <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
                      <span>
                        <strong>{nombrePorId.get(v.persona_id) ?? "—"}</strong>{" "}
                        <span className="text-taupe">
                          · {fechaCorta(v.fecha_inicio)} → {fechaCorta(v.fecha_fin)} · {dias} día{dias === 1 ? "" : "s"}
                        </span>
                      </span>
                      <button onClick={() => quitar(v)} disabled={guardando}
                        className="rounded border border-rojo/30 px-2 py-0.5 text-xs text-rojo hover:bg-rojo/10 disabled:opacity-40">
                        Quitar
                      </button>
                    </div>
                    {v.observacion && <p className="mt-1 text-taupe">“{v.observacion}”</p>}
                    <p className="mt-1 text-xs text-taupe/70">
                      Registrado {selloLima(v.creado_at)}
                      {nombrePorId.get(v.creado_por) && <> · por {nombrePorId.get(v.creado_por)}</>}
                    </p>
                  </li>
                );
              })}
            </ul>
          )}
        </div>

        {/* Saldo por persona — el cruce con Provisiones. SOLO INFORMATIVO. */}
        {resumen.length > 0 && (
          <div className="mt-6 max-w-4xl overflow-hidden rounded-lg border">
            <div className="border-b bg-sand/50 px-4 py-2">
              <h2 className="text-sm font-medium">Saldo por persona</h2>
              <p className="mt-0.5 text-xs text-taupe">
                Días ganados desde su aniversario de ingreso, menos los ya tomados. El monto es un{" "}
                <strong>estimado para que lo compares con tu cálculo</strong> — el sistema no paga nada solo.
              </p>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full min-w-[640px] text-sm">
                <thead className="bg-sand/30 text-left text-taupe">
                  <tr>
                    <th className="px-4 py-2 font-normal">Persona</th>
                    <th className="px-4 py-2 text-right font-normal">Ganados</th>
                    <th className="px-4 py-2 text-right font-normal">Tomados</th>
                    <th className="px-4 py-2 text-right font-normal">Saldo</th>
                    <th className="px-4 py-2 text-right font-normal">Factor</th>
                    <th className="px-4 py-2 text-right font-normal">Monto estimado</th>
                  </tr>
                </thead>
                <tbody>
                  {resumen.map((r) => (
                    <tr key={r.persona_id} className="border-t align-top">
                      <td className="px-4 py-2">
                        {r.nombre}
                        {/* Los componentes a la vista: un monto sin desglose no se puede auditar. */}
                        <div className="mt-0.5 text-xs text-taupe">
                          {r.horas_marcadas} h marcadas en {r.dias_con_marca} días · base {r.horas_base} h
                          {r.feriados_en_periodo > 0 && <> · {r.feriados_en_periodo} feriados (+{r.horas_feriados} h)</>}
                        </div>
                      </td>
                      <td className="px-4 py-2 text-right tabular-nums">{r.dias_ganados}</td>
                      <td className="px-4 py-2 text-right tabular-nums">{r.dias_tomados}</td>
                      <td className={`px-4 py-2 text-right font-medium tabular-nums ${r.dias_saldo < 0 ? "text-rojo" : ""}`}>
                        {r.dias_saldo}
                      </td>
                      <td className="px-4 py-2 text-right tabular-nums text-taupe">{r.factor}</td>
                      <td className="px-4 py-2 text-right font-medium tabular-nums">
                        {r.monto_estimado === null ? <span className="text-taupe/60">sin salario</span> : soles(r.monto_estimado)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}
      </main>
    </div>
  );
}
