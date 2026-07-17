"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { AdminNav } from "../nav";

function fechaLimaHoy(): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Lima" }).format(new Date());
}
function primerDiaDelMes(iso = fechaLimaHoy()): string {
  return iso.slice(0, 8) + "01";
}
function rango(preset: "mes" | "mesPasado" | "anio"): { desde: string; hasta: string } {
  const hoy = fechaLimaHoy();
  const [y, m] = hoy.split("-").map(Number);
  if (preset === "mes") return { desde: primerDiaDelMes(hoy), hasta: hoy };
  if (preset === "anio") return { desde: `${y}-01-01`, hasta: hoy };
  const mp = m === 1 ? 12 : m - 1;
  const yp = m === 1 ? y - 1 : y;
  const ultimo = new Date(Date.UTC(yp, mp, 0)).getUTCDate();
  return { desde: `${yp}-${String(mp).padStart(2, "0")}-01`, hasta: `${yp}-${String(mp).padStart(2, "0")}-${ultimo}` };
}

interface ResumenPersona {
  personaId: string;
  nombre: string;
  sede: string;
  diasTrabajados: number;
  horasTotales: number;
  tardanzas: number;
  diasTardeMedidos: number;
  minutosTarde: number;
  salidasTempranas: number;
  horasExtra: number;
  incompletas: number;
  pendientesRevision: number;
}

export default function HorasPage() {
  const router = useRouter();
  const [desde, setDesde] = useState(primerDiaDelMes());
  const [hasta, setHasta] = useState(fechaLimaHoy());
  const [filas, setFilas] = useState<ResumenPersona[]>([]);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    setCargando(true);

    const [
      { data: personas, error: errPersonas },
      { data: jornadas, error: errJornadas },
      { data: salidasData },
    ] = await Promise.all([
      supabase.from("personas").select("id, nombres, apellidos, sedes:sede_base_id(codigo)").order("nombres"),
      supabase.from("jornadas").select("persona_id, horas_trabajadas, minutos_tarde, horas_extra_detectadas, estado").gte("fecha", desde).lte("fecha", hasta),
      supabase.rpc("fn_jornadas_extra", { p_desde: desde, p_hasta: hasta }),
    ]);

    if (errPersonas || errJornadas) {
      setError((errPersonas ?? errJornadas)!.message);
      setCargando(false);
      return; // no pisa `filas` con datos parciales/vacíos
    }
    setError(null);

    const acc = new Map<string, ResumenPersona>();
    for (const p of personas ?? []) {
      acc.set(p.id, {
        personaId: p.id, nombre: `${p.nombres} ${p.apellidos}`, sede: (p as any).sedes?.codigo ?? "?",
        diasTrabajados: 0, horasTotales: 0, tardanzas: 0, diasTardeMedidos: 0, minutosTarde: 0, salidasTempranas: 0, horasExtra: 0, incompletas: 0, pendientesRevision: 0,
      });
    }
    for (const j of jornadas ?? []) {
      const r = acc.get(j.persona_id);
      if (!r) continue;
      r.diasTrabajados++;
      if (j.horas_trabajadas !== null) r.horasTotales += Number(j.horas_trabajadas); else r.incompletas++;
      if (j.minutos_tarde !== null) r.diasTardeMedidos++;
      if ((j.minutos_tarde ?? 0) > 0) { r.tardanzas++; r.minutosTarde += j.minutos_tarde!; }
      if ((j.horas_extra_detectadas ?? 0) > 0) r.horasExtra += Number(j.horas_extra_detectadas);
      if (j.estado === "auto_cerrada_pendiente") r.pendientesRevision++;
    }
    // Salidas tempranas vía RPC (bypass del schema cache); solo devuelve filas con minutos > 0.
    const salidas = (salidasData as { persona_id: string; fecha: string; minutos_salida_temprana: number }[] | null) ?? [];
    for (const s of salidas) {
      const r = acc.get(s.persona_id);
      if (!r) continue;
      r.salidasTempranas++;
    }
    setFilas([...acc.values()].filter((r) => r.diasTrabajados > 0));
    setCargando(false);
  }, [router, desde, hasta]);

  useEffect(() => { void cargar(); }, [cargar]);

  const totales = useMemo(() => ({
    horas: filas.reduce((s, f) => s + f.horasTotales, 0),
    personas: filas.length,
    tardanzas: filas.reduce((s, f) => s + f.tardanzas, 0),
    salidasTempranas: filas.reduce((s, f) => s + f.salidasTempranas, 0),
    horasExtra: filas.reduce((s, f) => s + f.horasExtra, 0),
    porRevisar: filas.reduce((s, f) => s + f.pendientesRevision + f.incompletas, 0),
  }), [filas]);

  const sedes = useMemo(() => [...new Set(filas.map((f) => f.sede))].sort(), [filas]);
  const aplicarPreset = (p: "mes" | "mesPasado" | "anio") => { const r = rango(p); setDesde(r.desde); setHasta(r.hasta); };

  const Tile = ({ label, valor, tono = "neutral" }: { label: string; valor: string; tono?: "neutral" | "alerta" }) => (
    <div className="rounded-xl border bg-crema px-4 py-3">
      <div className="text-xs uppercase tracking-wide text-taupe">{label}</div>
      <div className={`mt-1 text-2xl font-semibold [font-variant-numeric:tabular-nums] ${tono === "alerta" && valor !== "0" ? "text-rojo" : ""}`}>{valor}</div>
    </div>
  );

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <div className="mb-4 flex flex-wrap items-end justify-between gap-4">
          <h1 className="font-serif text-2xl">Resumen de horas</h1>
          <div className="flex flex-wrap items-end gap-3">
            <div className="flex gap-1 rounded-lg border p-1 text-sm">
              <button onClick={() => aplicarPreset("mes")} className="rounded-md px-2.5 py-1 hover:bg-sand/60">Este mes</button>
              <button onClick={() => aplicarPreset("mesPasado")} className="rounded-md px-2.5 py-1 hover:bg-sand/60">Mes pasado</button>
              <button onClick={() => aplicarPreset("anio")} className="rounded-md px-2.5 py-1 hover:bg-sand/60">Todo el año</button>
            </div>
            <label className="flex flex-col gap-1 text-sm">Desde
              <input type="date" value={desde} onChange={(e) => setDesde(e.target.value)} className="rounded-lg border px-3 py-2" /></label>
            <label className="flex flex-col gap-1 text-sm">Hasta
              <input type="date" value={hasta} onChange={(e) => setHasta(e.target.value)} className="rounded-lg border px-3 py-2" /></label>
          </div>
        </div>

        <div className="mb-6 grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
          <Tile label="Horas totales" valor={`${totales.horas.toFixed(0)} h`} />
          <Tile label="Tiempo adicional" valor={`${totales.horasExtra.toFixed(1)} h`} />
          <Tile label="Tardanzas" valor={String(totales.tardanzas)} tono="alerta" />
          <Tile label="Salidas anticipadas" valor={String(totales.salidasTempranas)} tono="alerta" />
          <Tile label="Personas con actividad" valor={String(totales.personas)} />
          <Tile label="Jornadas por revisar" valor={String(totales.porRevisar)} tono="alerta" />
        </div>

        {error && (
          <div className="mb-4 rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
            No se pudo cargar el resumen de horas: {error}{" "}
            <button onClick={() => void cargar()} className="font-medium underline">
              Reintentar
            </button>
          </div>
        )}

        {cargando && <p className="text-sm text-taupe">Cargando…</p>}
        {!cargando && !error && filas.length === 0 && <p className="text-sm text-taupe">Sin marcajes en este periodo.</p>}

        {sedes.map((sede) => {
          const deSede = filas.filter((f) => f.sede === sede).sort((a, b) => b.horasTotales - a.horasTotales);
          const subHoras = deSede.reduce((s, f) => s + f.horasTotales, 0);
          return (
            <section key={sede} className="mb-8">
              <h2 className="mb-2 font-serif text-lg">
                {sede} <span className="text-sm font-normal text-taupe">— {deSede.length} personas · {subHoras.toFixed(0)} h</span>
              </h2>
              <div className="overflow-x-auto rounded-lg border">
                <table className="w-full text-sm [font-variant-numeric:tabular-nums]">
                  <thead className="bg-sand/50 text-left text-taupe">
                    <tr>
                      <th className="px-4 py-2 font-normal">Nombre</th>
                      <th className="px-4 py-2 font-normal">Días</th>
                      <th className="px-4 py-2 font-normal">Horas</th>
                      <th className="px-4 py-2 font-normal">Tardanzas</th>
                      <th className="px-4 py-2 font-normal">Min. tarde</th>
                      <th className="px-4 py-2 font-normal">Sal. antic.</th>
                      <th className="px-4 py-2 font-normal">T. adicional</th>
                      <th className="px-4 py-2 font-normal">Observaciones</th>
                    </tr>
                  </thead>
                  <tbody>
                    {deSede.map((f) => (
                      <tr key={f.personaId} className="border-t">
                        <td className="px-4 py-2">{f.nombre}</td>
                        <td className="px-4 py-2">{f.diasTrabajados}</td>
                        <td className="px-4 py-2 font-medium">{f.horasTotales.toFixed(1)}</td>
                        <td className="px-4 py-2">
                          {f.diasTardeMedidos === 0 ? (
                            <span className="text-taupe/50">sin medir</span>
                          ) : (
                            <>{f.tardanzas} <span className="text-taupe/50">/ {f.diasTardeMedidos}</span></>
                          )}
                        </td>
                        <td className="px-4 py-2">{f.minutosTarde ? `${f.minutosTarde} min` : <span className="text-taupe/50">—</span>}</td>
                        <td className="px-4 py-2">{f.salidasTempranas ? <span className="text-ambar">{f.salidasTempranas}</span> : <span className="text-taupe/50">—</span>}</td>
                        <td className="px-4 py-2">{f.horasExtra > 0 ? <span className="text-verde font-medium">{f.horasExtra.toFixed(1)}</span> : <span className="text-taupe/50">—</span>}</td>
                        <td className="px-4 py-2 text-xs">
                          {f.incompletas > 0 && <span className="mr-2 rounded-full bg-taupe/15 px-2 py-0.5 text-taupe">{f.incompletas} sin salida</span>}
                          {f.pendientesRevision > 0 && <span className="rounded-full bg-rojo/10 px-2 py-0.5 text-rojo">{f.pendientesRevision} por revisar</span>}
                        </td>
                      </tr>
                    ))}
                    <tr className="border-t bg-sand/50 font-medium">
                      <td className="px-4 py-2">Subtotal {sede}</td>
                      <td className="px-4 py-2">{deSede.reduce((s, f) => s + f.diasTrabajados, 0)}</td>
                      <td className="px-4 py-2">{subHoras.toFixed(1)}</td>
                      <td className="px-4 py-2">{deSede.reduce((s, f) => s + f.tardanzas, 0) || "—"}</td>
                      <td className="px-4 py-2"></td>
                      <td className="px-4 py-2">{deSede.reduce((s, f) => s + f.salidasTempranas, 0) || "—"}</td>
                      <td className="px-4 py-2">{(() => { const e = deSede.reduce((s, f) => s + f.horasExtra, 0); return e > 0 ? e.toFixed(1) : "—"; })()}</td>
                      <td className="px-4 py-2"></td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </section>
          );
        })}

        <p className="max-w-2xl text-xs text-taupe">
          Las horas descuentan los almuerzos y pausas. La tardanza, la salida anticipada y el tiempo
          adicional se calculan contra el horario de cada persona — mientras no haya horario cargado, esas
          columnas quedan en blanco. La salida anticipada y el tiempo adicional tienen una tolerancia de
          15 min (solo se marcan si pasan de eso); la tardanza es exacta pero por minuto (los segundos
          dentro del minuto no cuentan). “Sal. antic.” = días que cerró antes de su hora de salida;
          “T. adicional” = tiempo trabajado por encima de lo programado. “Por revisar” incluye jornadas
          sin salida marcada o cerradas automáticamente por olvido.
        </p>
      </main>
    </div>
  );
}
