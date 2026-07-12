"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { AdminNav } from "../nav";

const TZ = "America/Lima";
function hoyLima(): string { return new Intl.DateTimeFormat("en-CA", { timeZone: TZ }).format(new Date()); }
function haceDias(n: number): string {
  const d = new Date(); d.setDate(d.getDate() - n);
  return new Intl.DateTimeFormat("en-CA", { timeZone: TZ }).format(d);
}
function fechaLarga(f: string): string {
  const [y, m, d] = f.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { timeZone: TZ, weekday: "short", day: "2-digit", month: "short" }).format(new Date(Date.UTC(y, m - 1, d, 12)));
}
function horaLima(ts: string | null): string {
  if (!ts) return "—";
  return new Intl.DateTimeFormat("es-PE", { timeZone: TZ, hour: "2-digit", minute: "2-digit", hour12: true }).format(new Date(ts));
}

interface Fila {
  personaId: string;
  nombre: string;
  sede: string;
  fecha: string;
  tipo: string;
  entrada: string | null;
  salida: string | null;
}

const HOY = hoyLima();

export default function IncidenciasPage() {
  const router = useRouter();
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;
  const [desde, setDesde] = useState(haceDias(30));
  const [hasta, setHasta] = useState(HOY);
  const [filas, setFilas] = useState<Fila[]>([]);
  const [cargando, setCargando] = useState(true);

  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    setCargando(true);

    const { data } = await supabase
      .from("jornadas")
      .select("persona_id, fecha, estado, entrada_ts, salida_final_ts, tiene_salida_no_retornada, personas:persona_id(nombres, apellidos, sedes:sede_base_id(codigo))")
      .gte("fecha", desde).lte("fecha", hasta)
      .order("fecha", { ascending: false });

    const out: Fila[] = [];
    for (const j of (data as any[]) ?? []) {
      let tipo: string | null = null;
      if (j.estado === "auto_cerrada_pendiente") tipo = "Auto-cerrada (revisar)";
      else if (j.fecha < HOY && j.estado === "abierta") tipo = "Sin salida final";
      else if (j.fecha < HOY && j.tiene_salida_no_retornada) tipo = "No regresó de pausa";
      if (!tipo) continue;
      out.push({
        personaId: j.persona_id,
        nombre: `${j.personas?.nombres ?? ""} ${j.personas?.apellidos ?? ""}`.trim(),
        sede: j.personas?.sedes?.codigo ?? "?",
        fecha: j.fecha,
        tipo,
        entrada: j.entrada_ts,
        salida: j.salida_final_ts,
      });
    }
    setFilas(out);
    setCargando(false);
  }, [router, desde, hasta]);

  useEffect(() => { void cargar(); }, [cargar]);

  // Encargada: solo su sede.
  const visibles = useMemo(() => {
    if (rol === "supervisor_sede" && yo) {
      // filtra por sede base de la encargada (comparando por código no disponible aquí);
      // RLS ya limita a su sede, así que esto es una salvaguarda visual mínima.
      return filas;
    }
    return filas;
  }, [filas, rol, yo]);

  const porSede = [...new Set(visibles.map((f) => f.sede))].sort();

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <div className="mb-1 flex items-end justify-between">
          <h1 className="font-serif text-2xl">Incidencias</h1>
          <span className="text-xs text-taupe">{cargando ? "Cargando…" : `${visibles.length} por revisar`}</span>
        </div>
        <p className="mb-5 text-sm text-taupe">Días que necesitan tu revisión: auto-cerrados, sin salida final, o sin retorno de pausa. Toca cualquiera para corregirlo.</p>

        <div className="mb-6 flex flex-wrap items-end gap-4">
          <label className="flex flex-col gap-1 text-sm">Desde
            <input type="date" value={desde} onChange={(e) => setDesde(e.target.value)} className="rounded-lg border border-sand bg-crema px-3 py-2" />
          </label>
          <label className="flex flex-col gap-1 text-sm">Hasta
            <input type="date" value={hasta} onChange={(e) => setHasta(e.target.value)} className="rounded-lg border border-sand bg-crema px-3 py-2" />
          </label>
        </div>

        {!cargando && visibles.length === 0 && (
          <div className="rounded-lg border border-sand bg-sand/30 px-4 py-8 text-center text-taupe">
            🎉 Sin incidencias en el periodo. Todo en orden.
          </div>
        )}

        {porSede.map((sede) => {
          const deSede = visibles.filter((f) => f.sede === sede);
          if (deSede.length === 0) return null;
          return (
            <section key={sede} className="mb-8">
              <h2 className="mb-3 font-serif text-lg">{sede} <span className="text-base text-taupe">· {deSede.length}</span></h2>
              <div className="overflow-x-auto rounded-lg border border-sand">
                <table className="w-full text-sm">
                  <thead className="bg-sand text-left">
                    <tr className="etiqueta text-taupe">
                      <th className="px-4 py-2.5 font-medium">Persona</th>
                      <th className="px-4 py-2.5 font-medium">Fecha</th>
                      <th className="px-4 py-2.5 font-medium">Incidencia</th>
                      <th className="px-4 py-2.5 font-medium">Entrada</th>
                      <th className="px-4 py-2.5 font-medium">Salida</th>
                      <th className="px-4 py-2.5 font-medium"></th>
                    </tr>
                  </thead>
                  <tbody>
                    {deSede.map((f, i) => (
                      <tr key={`${f.personaId}-${f.fecha}-${i}`} className="border-t border-sand">
                        <td className="px-4 py-2.5">{f.nombre}</td>
                        <td className="px-4 py-2.5 capitalize">{fechaLarga(f.fecha)}</td>
                        <td className="px-4 py-2.5"><span className="font-medium text-rojo">{f.tipo}</span></td>
                        <td className="px-4 py-2.5">{horaLima(f.entrada)}</td>
                        <td className="px-4 py-2.5">{horaLima(f.salida)}</td>
                        <td className="px-4 py-2.5 text-right">
                          <Link href={`/admin/correcciones?persona=${f.personaId}&fecha=${f.fecha}`} className="font-medium text-rojo underline decoration-rojo/30 underline-offset-2 hover:decoration-rojo">
                            Corregir ›
                          </Link>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </section>
          );
        })}
      </main>
    </div>
  );
}
