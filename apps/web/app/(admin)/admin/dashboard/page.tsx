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

const ESTILO_ESTADO: Record<string, { label: string; clase: string }> = {
  abierta: { label: "Presente", clase: "bg-green-100 text-green-800" },
  en_pausa: { label: "En pausa", clase: "bg-amber-100 text-amber-800" },
  cerrada: { label: "Salió", clase: "bg-neutral-200 text-neutral-600" },
  auto_cerrada_pendiente: { label: "Auto-cerrada ⚠", clase: "bg-red-100 text-red-700" },
  revisada: { label: "Salió (revisada)", clase: "bg-neutral-200 text-neutral-600" },
  sin_marcar: { label: "Sin marcar", clase: "bg-neutral-100 text-neutral-400" },
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
        <div className="mb-4 flex items-center justify-between">
          <h1 className="text-xl font-semibold">Asistencia de hoy</h1>
          <span className="text-xs text-neutral-400">
            {cargando ? "Cargando…" : `Actualizado ${actualizado} · se refresca solo cada 30s`}
          </span>
        </div>

        {sedes.map((sede) => {
          const deSede = filas.filter((f) => f.sede === sede);
          const presentes = deSede.filter((f) => f.estado === "abierta" || f.estado === "en_pausa").length;
          return (
            <section key={sede} className="mb-8">
              <h2 className="mb-2 font-medium">
                {sede} <span className="text-sm font-normal text-neutral-400">— {presentes} presente{presentes === 1 ? "" : "s"} de {deSede.length}</span>
              </h2>
              <div className="overflow-x-auto rounded-lg border">
                <table className="w-full text-sm">
                  <thead className="bg-neutral-50 text-left text-neutral-500">
                    <tr>
                      <th className="px-4 py-2 font-normal">Nombre</th>
                      <th className="px-4 py-2 font-normal">Estado</th>
                      <th className="px-4 py-2 font-normal">Entrada</th>
                      <th className="px-4 py-2 font-normal">Tardanza</th>
                      <th className="px-4 py-2 font-normal">Salida final</th>
                    </tr>
                  </thead>
                  <tbody>
                    {deSede.map((f) => {
                      const estilo = ESTILO_ESTADO[f.estado] ?? ESTILO_ESTADO.sin_marcar;
                      return (
                        <tr key={f.personaId} className="border-t">
                          <td className="px-4 py-2">{f.nombre}</td>
                          <td className="px-4 py-2">
                            <span className={`rounded-full px-2 py-0.5 text-xs ${estilo.clase}`}>{estilo.label}</span>
                          </td>
                          <td className="px-4 py-2">{horaLima(f.entrada)}</td>
                          <td className="px-4 py-2">
                            {f.minutosTarde === null || f.minutosTarde === 0 ? (
                              <span className="text-neutral-300">—</span>
                            ) : (
                              <span className="font-medium text-red-600">{f.minutosTarde} min</span>
                            )}
                          </td>
                          <td className="px-4 py-2">{horaLima(f.salidaFinal)}</td>
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
