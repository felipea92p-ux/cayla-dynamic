"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { AdminNav } from "../nav";

const REFRESCO_MS = 30_000;

function fechaLimaHoy(): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Lima" }).format(new Date());
}

function horaLima(ts: string | null): string {
  if (!ts) return "—";
  return new Intl.DateTimeFormat("es-PE", {
    timeZone: "America/Lima",
    hour: "2-digit",
    minute: "2-digit",
    hour12: true,
  }).format(new Date(ts));
}

interface FilaPersona {
  personaId: string;
  nombre: string;
  sede: string;
  estado: string;
  entrada: string | null;
  salidaFinal: string | null;
  minutosTarde: number | null;
  enPausaSinRetorno: boolean;
}

// Estados: verde/ámbar cálidos para lo operativo, Rojo lleno para la alerta crítica.
const ESTILO_ESTADO: Record<string, { label: string; clase: string }> = {
  abierta: { label: "Presente", clase: "bg-verde/15 text-verde" },
  en_pausa: { label: "En pausa", clase: "bg-ambar/15 text-ambar" },
  cerrada: { label: "Salió", clase: "bg-sand/50 text-taupe" },
  auto_cerrada_pendiente: { label: "Auto-cerrada ⚠", clase: "bg-rojo text-crema" },
  revisada: { label: "Salió (revisada)", clase: "bg-sand/50 text-taupe" },
  sin_marcar: { label: "Sin marcar", clase: "text-taupe/50" },
};

export default function DashboardPage() {
  const router = useRouter();
  const [filas, setFilas] = useState<FilaPersona[]>([]);
  const [actualizado, setActualizado] = useState<string>("");
  const [cargando, setCargando] = useState(true);

  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) {
      router.replace("/admin/login");
      return;
    }

    const hoy = fechaLimaHoy();
    const [{ data: personas }, { data: jornadas }] = await Promise.all([
      supabase
        .from("personas")
        .select("id, nombres, apellidos, sedes:sede_base_id(codigo)")
        .eq("estado", "activo")
        .order("nombres"),
      supabase
        .from("jornadas")
        .select("persona_id, estado, entrada_ts, salida_final_ts, minutos_tarde, tiene_salida_no_retornada")
        .eq("fecha", hoy),
    ]);

    const jornadaPorPersona = new Map((jornadas ?? []).map((j: any) => [j.persona_id, j]));

    const resultado: FilaPersona[] = (personas ?? []).map((p: any) => {
      const j = jornadaPorPersona.get(p.id);
      return {
        personaId: p.id,
        nombre: `${p.nombres} ${p.apellidos}`,
        sede: p.sedes?.codigo ?? "?",
        estado: j?.estado ?? "sin_marcar",
        entrada: j?.entrada_ts ?? null,
        salidaFinal: j?.salida_final_ts ?? null,
        minutosTarde: j?.minutos_tarde ?? null,
        enPausaSinRetorno: j?.tiene_salida_no_retornada ?? false,
      };
    });

    setFilas(resultado);
    setActualizado(new Intl.DateTimeFormat("es-PE", { timeZone: "America/Lima", hour: "2-digit", minute: "2-digit", second: "2-digit" }).format(new Date()));
    setCargando(false);
  }, [router]);

  useEffect(() => {
    void cargar();
    const t = setInterval(() => void cargar(), REFRESCO_MS);
    return () => clearInterval(t);
  }, [cargar]);

  const sedes = [...new Set(filas.map((f) => f.sede))].sort();

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <div className="mb-6 flex items-end justify-between">
          <h1 className="font-serif text-3xl">Asistencia de hoy</h1>
          <span className="text-xs text-taupe">
            {cargando ? "Cargando…" : `Actualizado ${actualizado} · se refresca solo cada 30s`}
          </span>
        </div>

        {sedes.map((sede) => {
          const deSede = filas.filter((f) => f.sede === sede);
          const activos = deSede.filter((f) => f.estado === "abierta" || f.estado === "en_pausa");
          return (
            <section key={sede} className="mb-10">
              <h2 className="mb-3 font-serif text-xl">
                {sede} <span className="text-base text-taupe">— {activos.length} trabajando de {deSede.length}</span>
              </h2>

              {/* Trabajando ahora — para que la encargada verifique contra quién está físicamente */}
              <div className="mb-4 rounded-lg border border-verde/25 bg-verde/[0.07] px-4 py-3">
                <div className="etiqueta text-verde">Trabajando ahora · {activos.length}</div>
                <div className="mt-2 flex flex-wrap gap-2">
                  {activos.length === 0 ? (
                    <span className="text-sm text-taupe/70">Nadie marcado todavía.</span>
                  ) : (
                    activos.map((f) => (
                      <span key={f.personaId} className="rounded-full border border-sand bg-crema px-3 py-1 text-sm">
                        {f.nombre}
                        {f.estado === "en_pausa" && <span className="ml-1 text-ambar">· en pausa</span>}
                      </span>
                    ))
                  )}
                </div>
              </div>

              <div className="overflow-x-auto rounded-lg border border-sand">
                <table className="w-full text-sm">
                  <thead className="bg-sand text-left">
                    <tr className="etiqueta text-taupe">
                      <th className="px-4 py-2.5 font-medium">Nombre</th>
                      <th className="px-4 py-2.5 font-medium">Estado</th>
                      <th className="px-4 py-2.5 font-medium">Entrada</th>
                      <th className="px-4 py-2.5 font-medium">Tardanza</th>
                      <th className="px-4 py-2.5 font-medium">Salida final</th>
                    </tr>
                  </thead>
                  <tbody>
                    {deSede.map((f) => {
                      const estilo = ESTILO_ESTADO[f.estado] ?? ESTILO_ESTADO.sin_marcar;
                      return (
                        <tr key={f.personaId} className="border-t border-sand">
                          <td className="px-4 py-2.5">{f.nombre}</td>
                          <td className="px-4 py-2.5">
                            <span className={`rounded-full px-2 py-0.5 text-xs ${estilo.clase}`}>{estilo.label}</span>
                          </td>
                          <td className="px-4 py-2.5">{horaLima(f.entrada)}</td>
                          <td className="px-4 py-2.5">
                            {f.minutosTarde === null || f.minutosTarde === 0 ? (
                              <span className="text-taupe/40">—</span>
                            ) : (
                              <span className="font-semibold text-rojo">{f.minutosTarde} min</span>
                            )}
                          </td>
                          <td className="px-4 py-2.5">{horaLima(f.salidaFinal)}</td>
                        </tr>
                      );
                    })}
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
