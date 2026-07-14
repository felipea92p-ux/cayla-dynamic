"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { AdminNav } from "../nav";
import { GraficoHoras, type DiaGrafico } from "@/components/grafico-horas";

const TZ = "America/Lima";
const META_DIA = 7.5; // horas objetivo por día (45h/semana)

function hoyLima(): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: TZ }).format(new Date());
}
function inicioMes(): string {
  return hoyLima().slice(0, 8) + "01";
}
function horaLima(ts: string | null): string {
  if (!ts) return "—";
  return new Intl.DateTimeFormat("es-PE", { timeZone: TZ, hour: "2-digit", minute: "2-digit", hour12: true }).format(new Date(ts));
}
function fechaLarga(f: string): string {
  const [y, m, d] = f.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { timeZone: TZ, weekday: "short", day: "2-digit", month: "short" }).format(new Date(Date.UTC(y, m - 1, d, 12)));
}
function fmtHoras(h: number): string {
  const hh = Math.floor(h);
  const mm = Math.round((h - hh) * 60);
  return `${hh}h ${String(mm).padStart(2, "0")}m`;
}

interface Persona { id: string; nombres: string; apellidos: string; rol: string; sede_base_id: string; }
interface Jornada {
  fecha: string;
  entrada_ts: string | null;
  salida_final_ts: string | null;
  horas_trabajadas: number | null;
  minutos_tarde: number | null;
  minutos_salida_temprana: number | null;
  horas_extra_detectadas: number | null;
  estado: string;
}

const ROLES_ADMIN = ["admin", "lider_do"];

export default function PerfilPage() {
  const router = useRouter();
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [personaId, setPersonaId] = useState("");
  const [desde, setDesde] = useState(inicioMes());
  const [hasta, setHasta] = useState(hoyLima());
  const [jornadas, setJornadas] = useState<Jornada[]>([]);
  const [cargando, setCargando] = useState(false);
  const [cargado, setCargado] = useState(false);

  useEffect(() => {
    const supabase = createAdminSupabaseClient();
    supabase.auth.getSession().then(async ({ data }) => {
      if (!data.session) { router.replace("/admin/login"); return; }
      const { data: p } = await supabase
        .from("personas").select("id, nombres, apellidos, rol, sede_base_id").eq("estado", "activo").order("nombres");
      setPersonas((p as Persona[]) ?? []);
    });
  }, [router]);

  // Encargada: solo su sede. Admin/líder: todos.
  const personasVisibles = useMemo(() => {
    if (rol === "supervisor_sede" && yo) return personas.filter((p) => p.sede_base_id === yo.sedeBaseId);
    return personas;
  }, [personas, rol, yo]);

  const cargar = useCallback(async () => {
    if (!personaId) return;
    setCargando(true);
    const supabase = createAdminSupabaseClient();
    // minutos_salida_temprana no está en el schema cache de PostgREST: se lee vía RPC en paralelo.
    const [{ data }, { data: extra }] = await Promise.all([
      supabase
        .from("jornadas")
        .select("fecha, entrada_ts, salida_final_ts, horas_trabajadas, minutos_tarde, horas_extra_detectadas, estado")
        .eq("persona_id", personaId).gte("fecha", desde).lte("fecha", hasta)
        .order("fecha"),
      supabase.rpc("fn_jornadas_extra", { p_desde: desde, p_hasta: hasta, p_persona_id: personaId }),
    ]);
    const filasExtra = (extra as { persona_id: string; fecha: string; minutos_salida_temprana: number }[] | null) ?? [];
    const minutosPorFecha = new Map(filasExtra.map((e) => [e.fecha, e.minutos_salida_temprana]));
    const filas = ((data as Omit<Jornada, "minutos_salida_temprana">[] | null) ?? []).map((j) => ({
      ...j,
      minutos_salida_temprana: minutosPorFecha.get(j.fecha) ?? null,
    }));
    setJornadas(filas);
    setCargado(true);
    setCargando(false);
  }, [personaId, desde, hasta]);

  const persona = personas.find((p) => p.id === personaId);
  const totalHoras = jornadas.reduce((s, j) => s + (j.horas_trabajadas ?? 0), 0);
  const diasTrabajados = jornadas.filter((j) => (j.horas_trabajadas ?? 0) > 0).length;
  const tardanzas = jornadas.filter((j) => (j.minutos_tarde ?? 0) > 0).length;
  const salidasTempranas = jornadas.filter((j) => (j.minutos_salida_temprana ?? 0) > 0).length;
  const horasExtra = jornadas.reduce((s, j) => s + (j.horas_extra_detectadas ?? 0), 0);
  const datosGrafico: DiaGrafico[] = jornadas.map((j) => ({ fecha: j.fecha, horas: j.horas_trabajadas ?? 0 }));

  function incidencia(j: Jornada): string | null {
    if (j.estado === "auto_cerrada_pendiente") return "Auto-cerrada";
    if (j.entrada_ts && !j.salida_final_ts) return "Sin salida";
    return null;
  }

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <h1 className="mb-1 font-serif text-2xl">Perfil individual</h1>
        <p className="mb-5 text-sm text-taupe">Historial de horas por persona en el periodo que elijas.</p>

        <div className="mb-6 flex flex-wrap items-end gap-4">
          <label className="flex flex-col gap-1 text-sm">
            Persona
            <select value={personaId} onChange={(e) => { setPersonaId(e.target.value); setCargado(false); }} className="min-w-56 rounded-lg border border-sand bg-crema px-3 py-2">
              <option value="">Elegir…</option>
              {personasVisibles.map((p) => <option key={p.id} value={p.id}>{p.nombres} {p.apellidos}</option>)}
            </select>
          </label>
          <label className="flex flex-col gap-1 text-sm">
            Desde
            <input type="date" value={desde} onChange={(e) => { setDesde(e.target.value); setCargado(false); }} className="rounded-lg border border-sand bg-crema px-3 py-2" />
          </label>
          <label className="flex flex-col gap-1 text-sm">
            Hasta
            <input type="date" value={hasta} onChange={(e) => { setHasta(e.target.value); setCargado(false); }} className="rounded-lg border border-sand bg-crema px-3 py-2" />
          </label>
          <button onClick={cargar} disabled={!personaId || cargando} className="rounded-lg bg-tinta px-5 py-2 text-sm font-medium text-crema disabled:opacity-50">
            {cargando ? "Cargando…" : "Ver"}
          </button>
        </div>

        {cargado && persona && (
          <>
            {/* Resumen del periodo */}
            <div className="mb-6 grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
              {[
                { label: "Total del periodo", valor: fmtHoras(totalHoras) },
                { label: "Días trabajados", valor: String(diasTrabajados) },
                { label: "Promedio por día", valor: diasTrabajados ? fmtHoras(totalHoras / diasTrabajados) : "—" },
                { label: "Días con tardanza", valor: String(tardanzas) },
                { label: "Salidas anticipadas", valor: String(salidasTempranas) },
                { label: "Tiempo adicional", valor: horasExtra > 0 ? fmtHoras(horasExtra) : "—" },
              ].map((c) => (
                <div key={c.label} className="rounded-lg border border-sand bg-sand/30 px-4 py-3">
                  <div className="etiqueta text-taupe">{c.label}</div>
                  <div className="mt-1 font-serif text-2xl">{c.valor}</div>
                </div>
              ))}
            </div>

            {/* Gráfico */}
            <div className="mb-8 rounded-lg border border-sand p-4">
              <h2 className="mb-3 font-serif text-lg">{persona.nombres} {persona.apellidos} · horas por día</h2>
              <GraficoHoras dias={datosGrafico} meta={META_DIA} />
            </div>

            {/* Tabla detalle */}
            <div className="overflow-x-auto rounded-lg border border-sand">
              <table className="w-full text-sm">
                <thead className="bg-sand text-left">
                  <tr className="etiqueta text-taupe">
                    <th className="px-4 py-2.5 font-medium">Fecha</th>
                    <th className="px-4 py-2.5 font-medium">Entrada</th>
                    <th className="px-4 py-2.5 font-medium">Salida</th>
                    <th className="px-4 py-2.5 font-medium">Horas</th>
                    <th className="px-4 py-2.5 font-medium">Tardanza</th>
                    <th className="px-4 py-2.5 font-medium">Sal. antic.</th>
                    <th className="px-4 py-2.5 font-medium">T. adicional</th>
                    <th className="px-4 py-2.5 font-medium">Incidencia</th>
                  </tr>
                </thead>
                <tbody>
                  {jornadas.length === 0 ? (
                    <tr><td colSpan={8} className="px-4 py-6 text-center text-taupe">Sin jornadas en el periodo.</td></tr>
                  ) : (
                    jornadas.map((j) => {
                      const inc = incidencia(j);
                      return (
                        <tr key={j.fecha} className="border-t border-sand">
                          <td className="px-4 py-2.5 capitalize">{fechaLarga(j.fecha)}</td>
                          <td className="px-4 py-2.5">{horaLima(j.entrada_ts)}</td>
                          <td className="px-4 py-2.5">{horaLima(j.salida_final_ts)}</td>
                          <td className="px-4 py-2.5">{j.horas_trabajadas != null ? fmtHoras(j.horas_trabajadas) : "—"}</td>
                          <td className="px-4 py-2.5">
                            {j.minutos_tarde ? <span className="font-medium text-rojo">{j.minutos_tarde} min</span> : <span className="text-taupe/40">—</span>}
                          </td>
                          <td className="px-4 py-2.5">
                            {j.minutos_salida_temprana ? <span className="text-ambar">{j.minutos_salida_temprana} min</span> : <span className="text-taupe/40">—</span>}
                          </td>
                          <td className="px-4 py-2.5">
                            {j.horas_extra_detectadas && j.horas_extra_detectadas > 0 ? <span className="font-medium text-verde">{fmtHoras(j.horas_extra_detectadas)}</span> : <span className="text-taupe/40">—</span>}
                          </td>
                          <td className="px-4 py-2.5">
                            {inc ? (
                              <Link href={`/admin/correcciones?persona=${personaId}&fecha=${j.fecha}`} className="font-medium text-rojo underline decoration-rojo/30 underline-offset-2 hover:decoration-rojo">
                                {inc} ›
                              </Link>
                            ) : (
                              <span className="text-taupe/40">—</span>
                            )}
                          </td>
                        </tr>
                      );
                    })
                  )}
                </tbody>
              </table>
            </div>
          </>
        )}
      </main>
    </div>
  );
}
