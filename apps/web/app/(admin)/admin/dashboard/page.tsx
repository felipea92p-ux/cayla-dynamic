"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { parseAreas, esOperativaEn, AREA_DEFAULT, AREAS_FALLBACK, type Area } from "@/lib/areas";
import { AdminNav } from "../nav";

const REFRESCO_MS = 30_000;
// Corte mañana/tarde de la meta de cobertura — mismo valor fijo que Turnos (14:15).
const CORTE_TARDE = 14.25;

function fechaLimaHoy(): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Lima" }).format(new Date());
}

// Día de la semana (0=domingo … 6=sábado) de un ISO — misma convención que
// metas_cobertura.dia_semana en Turnos.
function diaSemanaDe(iso: string): number {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d)).getUTCDay();
}

// Hora actual de Lima en decimal (13:30 → 13.5), para saber el tramo vigente.
function horaDecimalLimaAhora(): number {
  const p = new Intl.DateTimeFormat("en-GB", { timeZone: "America/Lima", hour: "2-digit", minute: "2-digit", hour12: false }).formatToParts(new Date());
  const h = Number(p.find((x) => x.type === "hour")?.value ?? 0) % 24;
  const m = Number(p.find((x) => x.type === "minute")?.value ?? 0);
  return h + m / 60;
}

interface MetaSede { man: number; tar: number; enc: number; }

// Una señal de cobertura en vivo: cuánta gente hay EN PISO ahora vs la meta del
// tramo. Sin meta = taupe neutro (no hay contra qué medir, no es alarma).
function LineaCobertura({ label, n, meta, tramo }: { label: string; n: number; meta: number; tramo?: string }) {
  const sinMeta = meta <= 0;
  const ok = !sinMeta && n >= meta;
  const color = sinMeta ? "var(--color-taupe)" : ok ? "var(--color-verde)" : "var(--color-rojo)";
  return (
    <span className="flex items-center gap-1.5">
      <span className="text-taupe">{label}</span>
      <span className="font-semibold tabular-nums" style={{ color }}>
        {n}
        {!sinMeta && <span className="font-normal text-taupe"> / meta {tramo ? tramo + " " : ""}{meta}</span>}
      </span>
      {sinMeta ? (
        <span className="text-xs text-taupe/60">sin meta</span>
      ) : (
        <span className="text-xs font-medium" style={{ color }}>{ok ? "· completo" : `· faltan ${meta - n}`}</span>
      )}
    </span>
  );
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
  sedeId: string;
  estado: string;
  entrada: string | null;
  salidaFinal: string | null;
  minutosTarde: number | null;
  salidaTemprana: number | null;
  enPausaSinRetorno: boolean;
  esOperativa: boolean; // cuenta contra la meta de operativas
  esEncargada: boolean; // supervisor_sede o marca es_encargada_piso
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
  const [metasPorSede, setMetasPorSede] = useState<Map<string, MetaSede>>(new Map());
  const [actualizado, setActualizado] = useState<string>("");
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) {
      router.replace("/admin/login");
      return;
    }

    const hoy = fechaLimaHoy();
    const diaHoy = diaSemanaDe(hoy);
    // minutos_salida_temprana va por RPC (fn_jornadas_extra) porque el schema cache
    // de PostgREST no expone la columna; el select directo fallaría entero.
    const [
      { data: personas, error: errPersonas },
      { data: jornadas, error: errJornadas },
      { data: extras }, // fn_jornadas_extra ya está diseñada para fallar en silencio (ver comentario abajo)
      { data: funciones }, // función + es_encargada_piso (RPC: el schema cache no expone la columna)
      { data: areasRaw, error: errAreas }, // catálogo de áreas (para saber cuáles son operativas)
      { data: metasRaw }, // metas de cobertura de hoy por sede (falla suave: sin meta = neutro)
    ] = await Promise.all([
      supabase
        .from("personas")
        .select("id, nombres, apellidos, rol, sede_base_id, sedes:sede_base_id(codigo)")
        .eq("estado", "activo")
        .eq("en_planilla", true)
        .eq("sueldo_fijo", false) // quien cobra fijo no marca: no se le mide asistencia
        .order("nombres"),
      supabase
        .from("jornadas")
        .select("persona_id, estado, entrada_ts, salida_final_ts, minutos_tarde, tiene_salida_no_retornada")
        .eq("fecha", hoy),
      supabase.rpc("fn_jornadas_extra", { p_desde: hoy, p_hasta: hoy }),
      supabase.rpc("fn_personas_funciones"),
      supabase.rpc("fn_areas"),
      supabase.from("metas_cobertura").select("sede_id, meta, meta_tarde, meta_encargadas").eq("dia_semana", diaHoy),
    ]);

    if (errPersonas || errJornadas) {
      setError((errPersonas ?? errJornadas)!.message);
      setCargando(false);
      return; // no pisa `filas` con datos parciales/vacíos
    }
    setError(null);

    // Función/área/encargada: si la RPC falla, degradamos a "todos operativos"
    // (misma política que Turnos) — la cobertura puede marcar de más pero la
    // página no se cae. Las metas fallan aún más suave: sin meta = neutro.
    const areasList: Area[] = parseAreas(areasRaw, errAreas);
    const funcionPorPersona = new Map(
      ((funciones as { persona_id: string; funcion: string; es_encargada_piso?: boolean }[] | null) ?? [])
        .map((x) => [x.persona_id, { funcion: x.funcion, enc: Boolean(x.es_encargada_piso) }]),
    );
    setMetasPorSede(new Map(
      ((metasRaw as { sede_id: string; meta: number; meta_tarde: number | null; meta_encargadas: number | null }[] | null) ?? [])
        .map((m) => [m.sede_id, { man: m.meta ?? 0, tar: m.meta_tarde ?? m.meta ?? 0, enc: m.meta_encargadas ?? 0 }]),
    ));

    const jornadaPorPersona = new Map((jornadas ?? []).map((j: any) => [j.persona_id, j]));
    // Solo llegan filas con minutos > 0 y la fecha es fija (hoy), así que basta persona_id → minutos.
    // Si la RPC falla, extras es null y el map queda vacío (sin badge, la página no se rompe).
    const salidaTempranaPorPersona = new Map(
      ((extras as { persona_id: string; fecha: string; minutos_salida_temprana: number }[] | null) ?? []).map(
        (e) => [e.persona_id, e.minutos_salida_temprana],
      ),
    );

    const resultado: FilaPersona[] = (personas ?? []).map((p: any) => {
      const j = jornadaPorPersona.get(p.id);
      const f = funcionPorPersona.get(p.id);
      return {
        personaId: p.id,
        nombre: `${p.nombres} ${p.apellidos}`,
        sede: p.sedes?.codigo ?? "?",
        sedeId: p.sede_base_id,
        estado: j?.estado ?? "sin_marcar",
        entrada: j?.entrada_ts ?? null,
        salidaFinal: j?.salida_final_ts ?? null,
        minutosTarde: j?.minutos_tarde ?? null,
        salidaTemprana: salidaTempranaPorPersona.get(p.id) ?? null,
        enPausaSinRetorno: j?.tiene_salida_no_retornada ?? false,
        esOperativa: esOperativaEn(areasList, f?.funcion ?? AREA_DEFAULT),
        esEncargada: p.rol === "supervisor_sede" || Boolean(f?.enc),
      };
    });

    setFilas(resultado);
    setActualizado(new Intl.DateTimeFormat("es-PE", { timeZone: "America/Lima", hour: "2-digit", minute: "2-digit", second: "2-digit" }).format(new Date()));
    setCargando(false);
  }, [router]);

  useEffect(() => {
    void cargar();
    const t = setInterval(() => void cargar(), REFRESCO_MS);
    // Refrescar también al volver a la pestaña (los navegadores pausan el interval en
    // segundo plano; así un cambio reciente —ej. una persona nueva— aparece al regresar).
    const alVolver = () => { if (document.visibilityState === "visible") void cargar(); };
    document.addEventListener("visibilitychange", alVolver);
    window.addEventListener("focus", alVolver);
    return () => {
      clearInterval(t);
      document.removeEventListener("visibilitychange", alVolver);
      window.removeEventListener("focus", alVolver);
    };
  }, [cargar]);

  // Agrupamos por sede_id (no por código) para poder cruzar con metas_cobertura.
  const sedes = [...new Map(filas.map((f) => [f.sedeId, f.sede])).entries()]
    .map(([sedeId, codigo]) => ({ sedeId, codigo }))
    .sort((a, b) => a.codigo.localeCompare(b.codigo));
  const tramoTarde = horaDecimalLimaAhora() >= CORTE_TARDE;
  const tramoLabel = tramoTarde ? "tarde" : "mañana";
  const hoy = fechaLimaHoy();
  // Un incidente (tardanza, auto-cierre) enlaza directo a Corregir de esa persona/fecha.
  const linkCorregir = (personaId: string) => `/admin/correcciones?persona=${personaId}&fecha=${hoy}`;

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <div className="mb-6 flex items-end justify-between">
          <h1 className="font-serif text-3xl">Asistencia de hoy</h1>
          <div className="flex items-center gap-4">
            <a
              href="https://docs.google.com/spreadsheets/d/19jhc5IN0LpbyG00jEwqt4ZB420Ob_rVcGRAdXR88riA/edit"
              target="_blank"
              rel="noopener noreferrer"
              className="rounded-lg border border-sand bg-crema px-4 py-2 text-sm font-medium text-tinta transition-colors hover:bg-sand/40"
            >
              📊 Ver en Google Sheets
            </a>
            <span className="text-xs text-taupe">
              {cargando ? "Cargando…" : `Actualizado ${actualizado} · se refresca solo cada 30s`}
            </span>
          </div>
        </div>

        {error && (
          <div className="mb-6 rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
            No se pudo cargar la asistencia de hoy: {error}{" "}
            <button onClick={() => void cargar()} className="font-medium underline">
              Reintentar
            </button>
          </div>
        )}

        {sedes.map(({ sedeId, codigo }) => {
          const deSede = filas.filter((f) => f.sedeId === sedeId);
          const activos = deSede.filter((f) => f.estado === "abierta" || f.estado === "en_pausa");
          // Cobertura EN VIVO: "en piso" = solo Presente (abierta). Quien está en
          // pausa/refrigerio no cuenta — no está físicamente cubriendo ahora.
          const meta = metasPorSede.get(sedeId) ?? { man: 0, tar: 0, enc: 0 };
          const opPiso = deSede.filter((f) => f.esOperativa && f.estado === "abierta").length;
          const encPiso = deSede.filter((f) => f.esEncargada && f.estado === "abierta").length;
          return (
            <section key={sedeId} className="mb-10">
              <h2 className="mb-3 font-serif text-xl">
                {codigo} <span className="text-base text-taupe">— {activos.length} trabajando de {deSede.length}</span>
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
                {/* Cobertura del momento: cuánta gente en piso ahora vs la meta del tramo vigente */}
                <div className="mt-3 flex flex-wrap items-center gap-x-5 gap-y-1 border-t border-verde/15 pt-2.5 text-sm">
                  <LineaCobertura label="Operativas en piso" n={opPiso} meta={tramoTarde ? meta.tar : meta.man} tramo={tramoLabel} />
                  <LineaCobertura label="Encargadas" n={encPiso} meta={meta.enc} />
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
                            {f.estado === "auto_cerrada_pendiente" ? (
                              <Link href={linkCorregir(f.personaId)} className={`rounded-full px-2 py-0.5 text-xs ${estilo.clase} transition-opacity hover:opacity-80`}>
                                {estilo.label} ›
                              </Link>
                            ) : (
                              <span className={`rounded-full px-2 py-0.5 text-xs ${estilo.clase}`}>{estilo.label}</span>
                            )}
                          </td>
                          <td className="px-4 py-2.5">{horaLima(f.entrada)}</td>
                          <td className="px-4 py-2.5">
                            {f.minutosTarde === null || f.minutosTarde === 0 ? (
                              <span className="text-taupe/40">—</span>
                            ) : (
                              <Link href={linkCorregir(f.personaId)} className="font-semibold text-rojo underline decoration-rojo/30 underline-offset-2 transition-colors hover:decoration-rojo">
                                {f.minutosTarde} min
                              </Link>
                            )}
                          </td>
                          <td className="px-4 py-2.5">
                            {horaLima(f.salidaFinal)}
                            {f.salidaTemprana ? (
                              <Link href={linkCorregir(f.personaId)} className="ml-2 rounded-full bg-ambar/15 px-1.5 py-0.5 text-[10px] text-ambar hover:opacity-80">
                                anticip. {f.salidaTemprana}m
                              </Link>
                            ) : null}
                          </td>
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
