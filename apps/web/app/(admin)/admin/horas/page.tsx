"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { AdminNav } from "../nav";

function fechaLimaHoy(): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Lima" }).format(new Date());
}

function primerDiaDelMes(): string {
  return fechaLimaHoy().slice(0, 8) + "01";
}

interface ResumenPersona {
  personaId: string;
  nombre: string;
  sede: string;
  diasTrabajados: number;
  horasTotales: number;
  tardanzas: number;
  minutosTarde: number;
  incompletas: number; // jornadas sin salida final (abiertas/en pausa) — no suman horas
  pendientesRevision: number; // auto-cerradas sin revisar
}

export default function HorasPage() {
  const router = useRouter();
  const [desde, setDesde] = useState(primerDiaDelMes());
  const [hasta, setHasta] = useState(fechaLimaHoy());
  const [filas, setFilas] = useState<ResumenPersona[]>([]);
  const [cargando, setCargando] = useState(true);

  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) {
      router.replace("/admin/login");
      return;
    }
    setCargando(true);

    const [{ data: personas }, { data: jornadas }] = await Promise.all([
      supabase
        .from("personas")
        .select("id, nombres, apellidos, sedes:sede_base_id(codigo)")
        .order("nombres"),
      supabase
        .from("jornadas")
        .select("persona_id, fecha, horas_trabajadas, minutos_tarde, estado")
        .gte("fecha", desde)
        .lte("fecha", hasta),
    ]);

    const acumulado = new Map<string, ResumenPersona>();
    for (const p of personas ?? []) {
      acumulado.set(p.id, {
        personaId: p.id,
        nombre: `${p.nombres} ${p.apellidos}`,
        sede: (p as any).sedes?.codigo ?? "?",
        diasTrabajados: 0,
        horasTotales: 0,
        tardanzas: 0,
        minutosTarde: 0,
        incompletas: 0,
        pendientesRevision: 0,
      });
    }

    for (const j of jornadas ?? []) {
      const r = acumulado.get(j.persona_id);
      if (!r) continue;
      r.diasTrabajados++;
      if (j.horas_trabajadas !== null) r.horasTotales += Number(j.horas_trabajadas);
      else r.incompletas++;
      if ((j.minutos_tarde ?? 0) > 0) {
        r.tardanzas++;
        r.minutosTarde += j.minutos_tarde!;
      }
      if (j.estado === "auto_cerrada_pendiente") r.pendientesRevision++;
    }

    // solo mostrar quienes tuvieron actividad en el periodo
    setFilas([...acumulado.values()].filter((r) => r.diasTrabajados > 0));
    setCargando(false);
  }, [router, desde, hasta]);

  useEffect(() => {
    void cargar();
  }, [cargar]);

  const sedes = [...new Set(filas.map((f) => f.sede))].sort();
  const hayPendientes = filas.some((f) => f.incompletas > 0 || f.pendientesRevision > 0);

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <div className="mb-4 flex flex-wrap items-end justify-between gap-4">
          <h1 className="text-xl font-semibold">Horas por periodo</h1>
          <div className="flex items-end gap-3">
            <label className="flex flex-col gap-1 text-sm">
              Desde
              <input type="date" value={desde} onChange={(e) => setDesde(e.target.value)} className="rounded-lg border px-3 py-2" />
            </label>
            <label className="flex flex-col gap-1 text-sm">
              Hasta
              <input type="date" value={hasta} onChange={(e) => setHasta(e.target.value)} className="rounded-lg border px-3 py-2" />
            </label>
          </div>
        </div>

        {cargando && <p className="text-sm text-neutral-400">Cargando…</p>}
        {!cargando && filas.length === 0 && (
          <p className="text-sm text-neutral-500">Sin marcajes en este periodo.</p>
        )}

        {sedes.map((sede) => {
          const deSede = filas.filter((f) => f.sede === sede);
          return (
            <section key={sede} className="mb-8">
              <h2 className="mb-2 font-medium">{sede}</h2>
              <div className="overflow-x-auto rounded-lg border">
                <table className="w-full text-sm [font-variant-numeric:tabular-nums]">
                  <thead className="bg-neutral-50 text-left text-neutral-500">
                    <tr>
                      <th className="px-4 py-2 font-normal">Nombre</th>
                      <th className="px-4 py-2 font-normal">Días</th>
                      <th className="px-4 py-2 font-normal">Horas totales</th>
                      <th className="px-4 py-2 font-normal">Tardanzas</th>
                      <th className="px-4 py-2 font-normal">Min. tarde acum.</th>
                      <th className="px-4 py-2 font-normal">Observaciones</th>
                    </tr>
                  </thead>
                  <tbody>
                    {deSede.map((f) => (
                      <tr key={f.personaId} className="border-t">
                        <td className="px-4 py-2">{f.nombre}</td>
                        <td className="px-4 py-2">{f.diasTrabajados}</td>
                        <td className="px-4 py-2 font-medium">{f.horasTotales.toFixed(2)} h</td>
                        <td className="px-4 py-2">{f.tardanzas || <span className="text-neutral-300">—</span>}</td>
                        <td className="px-4 py-2">
                          {f.minutosTarde ? `${f.minutosTarde} min` : <span className="text-neutral-300">—</span>}
                        </td>
                        <td className="px-4 py-2 text-xs">
                          {f.incompletas > 0 && (
                            <span className="mr-2 rounded-full bg-amber-100 px-2 py-0.5 text-amber-800">
                              {f.incompletas} sin salida
                            </span>
                          )}
                          {f.pendientesRevision > 0 && (
                            <span className="rounded-full bg-red-100 px-2 py-0.5 text-red-700">
                              {f.pendientesRevision} por revisar
                            </span>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </section>
          );
        })}

        {hayPendientes && (
          <p className="max-w-2xl text-xs text-neutral-500">
            “Sin salida” = jornadas aún abiertas o en pausa: sus horas no se suman hasta que se
            cierren. “Por revisar” = jornadas cerradas automáticamente por olvido de marcar salida;
            sus horas se calcularon hasta la hora de salida programada.
          </p>
        )}
      </main>
    </div>
  );
}
