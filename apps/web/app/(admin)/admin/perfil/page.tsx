"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { AdminNav } from "../nav";
import { GraficoHoras, type DiaGrafico } from "@/components/grafico-horas";
import { MESES, nivelPlus, type ObjetivoItem } from "@/lib/objetivos";

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
  const [levTard, setLevTard] = useState<Map<string, string>>(new Map()); // fecha → motivo (tardanza levantada)
  const [objetivos, setObjetivos] = useState<ObjetivoItem[]>([]);
  const [cargando, setCargando] = useState(false);
  const [cargado, setCargado] = useState(false);
  const [error, setError] = useState<string | null>(null);

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
    setError(null);
    const supabase = createAdminSupabaseClient();
    // minutos_salida_temprana no está en el schema cache de PostgREST: se lee vía RPC en paralelo.
    // Objetivos: los del mes de la fecha "Hasta" (checklist 0032, solo lectura aquí).
    const [{ data, error: errJornadas }, { data: extra }, { data: objs }, { data: levData }] = await Promise.all([
      supabase
        .from("jornadas")
        .select("fecha, entrada_ts, salida_final_ts, horas_trabajadas, minutos_tarde, horas_extra_detectadas, estado")
        .eq("persona_id", personaId).gte("fecha", desde).lte("fecha", hasta)
        .order("fecha"),
      supabase.rpc("fn_jornadas_extra", { p_desde: desde, p_hasta: hasta, p_persona_id: personaId }),
      supabase.rpc("fn_objetivos_checklist", {
        p_anio: Number(hasta.slice(0, 4)),
        p_mes: Number(hasta.slice(5, 7)),
        p_persona_id: personaId,
      }),
      // Tardanzas levantadas del rango: se muestran tachadas (falla suave).
      supabase.from("tardanzas_justificadas").select("fecha, motivo").eq("persona_id", personaId).gte("fecha", desde).lte("fecha", hasta),
    ]);
    if (errJornadas) {
      setError(errJornadas.message);
      setCargando(false);
      return; // no pisa `jornadas`/`cargado` con datos parciales
    }
    setObjetivos(((objs as unknown as ObjetivoItem[] | null) ?? []).slice());
    const filasExtra = (extra as { persona_id: string; fecha: string; minutos_salida_temprana: number }[] | null) ?? [];
    const minutosPorFecha = new Map(filasExtra.map((e) => [e.fecha, e.minutos_salida_temprana]));
    const filas = ((data as Omit<Jornada, "minutos_salida_temprana">[] | null) ?? []).map((j) => ({
      ...j,
      minutos_salida_temprana: minutosPorFecha.get(j.fecha) ?? null,
    }));
    setJornadas(filas);
    setLevTard(new Map(((levData as { fecha: string; motivo: string }[] | null) ?? []).map((t) => [t.fecha, t.motivo])));
    setCargado(true);
    setCargando(false);
  }, [personaId, desde, hasta]);

  const persona = personas.find((p) => p.id === personaId);
  // Un día no puede tener más de 24 horas: si las tiene, no es un día — es un
  // AGREGADO. Vienen de la carga del histórico 2025, donde las horas de todo un
  // mes se guardaron en una sola fecha (15-nov y 15-dic) porque en 2025 no había
  // marcas diarias; solo se tenía el total mensual de la hoja de gratificaciones.
  // Son horas REALES y la planilla las usó, así que suman al total del periodo —
  // pero no son un día, así que no entran al promedio ni al gráfico (una barra
  // de 270 h aplasta la escala y vuelve el gráfico ilegible).
  const esAgregado = (j: Jornada) => (j.horas_trabajadas ?? 0) > 24;
  const agregados = jornadas.filter(esAgregado);
  const jornadasReales = jornadas.filter((j) => !esAgregado(j));
  const totalHoras = jornadas.reduce((s, j) => s + (j.horas_trabajadas ?? 0), 0);
  const horasAgregadas = agregados.reduce((s, j) => s + (j.horas_trabajadas ?? 0), 0);
  const horasReales = totalHoras - horasAgregadas;
  const diasTrabajados = jornadasReales.filter((j) => (j.horas_trabajadas ?? 0) > 0).length;
  const diasTardeMedidos = jornadas.filter((j) => j.minutos_tarde !== null).length;
  const tardanzas = jornadas.filter((j) => (j.minutos_tarde ?? 0) > 0 && !levTard.has(j.fecha)).length;
  const diasSalidaMedidos = jornadas.filter((j) => j.minutos_salida_temprana !== null).length;
  const salidasTempranas = jornadas.filter((j) => (j.minutos_salida_temprana ?? 0) > 0).length;
  const horasExtra = jornadas.reduce((s, j) => s + (j.horas_extra_detectadas ?? 0), 0);
  const datosGrafico: DiaGrafico[] = jornadasReales.map((j) => ({ fecha: j.fecha, horas: j.horas_trabajadas ?? 0 }));
  const objCumplidos = objetivos.filter((o) => o.cumplido).length;
  const objNivel = nivelPlus(objCumplidos, objetivos.length);
  const objPct = objetivos.length > 0 ? Math.round((objCumplidos / objetivos.length) * 100) : 0;
  const objMesLabel = `${MESES[Number(hasta.slice(5, 7)) - 1]} ${hasta.slice(0, 4)}`;

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

        {error && (
          <div className="mb-6 max-w-2xl rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
            No se pudo cargar el historial: {error}{" "}
            <button onClick={() => void cargar()} className="font-medium underline">
              Reintentar
            </button>
          </div>
        )}

        {cargado && persona && (
          <>
            {/* Resumen del periodo */}
            <div className="mb-6 grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
              {[
                { label: "Total del periodo", valor: fmtHoras(totalHoras) },
                { label: "Días trabajados", valor: String(diasTrabajados) },
                { label: "Promedio por día", valor: diasTrabajados ? fmtHoras(horasReales / diasTrabajados) : "—" },
                { label: "Días con tardanza", valor: `${tardanzas} de ${diasTardeMedidos} medidos` },
                { label: "Salidas anticipadas", valor: `${salidasTempranas} de ${diasSalidaMedidos} medidos` },
                { label: "Tiempo adicional", valor: horasExtra > 0 ? fmtHoras(horasExtra) : "—" },
              ].map((c) => (
                <div key={c.label} className="rounded-lg border border-sand bg-sand/30 px-4 py-3">
                  <div className="etiqueta text-taupe">{c.label}</div>
                  <div className="mt-1 font-serif text-2xl">{c.valor}</div>
                </div>
              ))}
            </div>

            {/* Los agregados históricos se explican, no se esconden: sus horas son
                reales y la planilla las usó, así que deben seguir sumando al total. */}
            {agregados.length > 0 && (
              <p className="mb-6 -mt-3 max-w-3xl text-xs text-taupe">
                Incluye <strong>{agregados.length} registro{agregados.length === 1 ? "" : "s"} histórico{agregados.length === 1 ? "" : "s"} de 2025</strong> ({fmtHoras(horasAgregadas)}):
                el total de un mes completo guardado en una sola fecha, porque en 2025 todavía no había marcaje diario.
                Suman al <strong>total del periodo</strong> (y la planilla los usó para CTS y gratificación),
                pero no cuentan como día, así que quedan fuera del promedio y del gráfico.
              </p>
            )}

            {/* Objetivos del mes (checklist, solo lectura — se gestionan en Objetivos) */}
            {objetivos.length > 0 && (
              <div className="mb-6 max-w-3xl rounded-lg border border-sand p-4">
                <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
                  <h2 className="font-serif text-lg">Objetivos de {objMesLabel.toLowerCase()}</h2>
                  <span className="flex items-center gap-2 text-sm">
                    <span className="text-taupe">
                      {objCumplidos}/{objetivos.length} cumplidos
                    </span>
                    <span
                      className={`rounded-full px-3 py-0.5 ${
                        objNivel.etiqueta === "Sin plus" || objNivel.etiqueta === "—"
                          ? "bg-sand text-taupe"
                          : "bg-verde/15 font-medium text-verde"
                      }`}
                    >
                      {objNivel.etiqueta}
                    </span>
                  </span>
                </div>
                <div className="mb-3 h-2 overflow-hidden rounded-full bg-sand">
                  <div
                    className={`h-full rounded-full ${objPct >= 60 ? "bg-verde" : objPct >= 30 ? "bg-ambar" : "bg-rojo"}`}
                    style={{ width: `${objPct}%` }}
                  />
                </div>
                <ul className="space-y-1 text-sm">
                  {objetivos.map((o) => (
                    <li key={o.id} className="flex items-start gap-2">
                      <span className={o.cumplido ? "text-verde" : "text-taupe/50"}>{o.cumplido ? "✓" : "○"}</span>
                      <span className={o.cumplido ? "text-taupe line-through" : ""}>{o.descripcion}</span>
                    </li>
                  ))}
                </ul>
              </div>
            )}

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
                          <td className="px-4 py-2.5 capitalize">
                            {fechaLarga(j.fecha)}
                            {esAgregado(j) && (
                              <span className="ml-2 whitespace-nowrap rounded-full bg-taupe/15 px-2 py-0.5 text-[10px] normal-case text-taupe">
                                total del mes · histórico 2025
                              </span>
                            )}
                          </td>
                          <td className="px-4 py-2.5">{horaLima(j.entrada_ts)}</td>
                          <td className="px-4 py-2.5">{horaLima(j.salida_final_ts)}</td>
                          <td className="px-4 py-2.5">{j.horas_trabajadas != null ? fmtHoras(j.horas_trabajadas) : "—"}</td>
                          <td className="px-4 py-2.5">
                            {j.minutos_tarde ? (
                              levTard.has(j.fecha)
                                ? <span className="text-taupe" title="Tardanza levantada"><s>{j.minutos_tarde} min</s> · levantada</span>
                                : <span className="font-medium text-rojo">{j.minutos_tarde} min</span>
                            ) : <span className="text-taupe/40">—</span>}
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
