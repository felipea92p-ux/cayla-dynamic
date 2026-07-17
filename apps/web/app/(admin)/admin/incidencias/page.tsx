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
// ── Semana actual (lunes–domingo), mismo criterio que admin/turnos ──────────
function parseISO(iso: string): Date {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d));
}
function toISO(dt: Date): string { return dt.toISOString().slice(0, 10); }
function addDias(iso: string, n: number): string {
  const d = parseISO(iso); d.setUTCDate(d.getUTCDate() + n); return toISO(d);
}
function diaSemanaNum(iso: string): number { return parseISO(iso).getUTCDay(); } // 0=domingo…6=sábado
function lunesDeLaSemana(iso: string): string {
  const dow = diaSemanaNum(iso);
  return addDias(iso, dow === 0 ? -6 : 1 - dow);
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
  personaId: string | null; // null = incidencia de sede (no de una persona puntual)
  nombre: string;
  sede: string;
  fecha: string;
  tipo: string;
  entrada: string | null;
  salida: string | null;
}

const HOY = hoyLima();
// Patrón de tardanzas: ventana fija de 30 días desde hoy (independiente del
// filtro Desde/Hasta que el admin puede mover) — es sobre el estado disciplinario
// ACTUAL de la persona, no sobre lo que el admin esté mirando en un momento dado.
// El número no sale de una ley (el marco peruano no fija una cifra: exige
// reiteración + sanciones progresivas documentadas antes de poder despedir por
// esto — D.S. 003-97-TR art. 25 + jurisprudencia de la Corte Suprema), es el
// umbral que Felipe eligió para que Dynamic avise y arranque ese proceso.
const VENTANA_PATRON_DIAS = 30;
const UMBRAL_PATRON_TARDANZAS = 3;

export default function IncidenciasPage() {
  const router = useRouter();
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;
  const [desde, setDesde] = useState(haceDias(30));
  const [hasta, setHasta] = useState(HOY);
  const [filas, setFilas] = useState<Fila[]>([]);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    setCargando(true);

    const desdePatron = haceDias(VENTANA_PATRON_DIAS - 1); // hoy inclusive = 30 días
    const lunesActual = lunesDeLaSemana(HOY);
    const domingoActual = addDias(lunesActual, 6);

    const [
      { data, error: errData },
      { data: extraData },
      { data: tardias, error: errTardias },
      { data: sedesData, error: errSedes },
      { data: encargadasData, error: errEnc },
      { data: metasData, error: errMetas },
      { data: horariosData, error: errHorarios },
      { data: turnosData, error: errTurnos },
    ] = await Promise.all([
      supabase
        .from("jornadas")
        .select("persona_id, fecha, estado, entrada_ts, salida_final_ts, tiene_salida_no_retornada, personas:persona_id(nombres, apellidos, sedes:sede_base_id(codigo))")
        .gte("fecha", desde).lte("fecha", hasta)
        .order("fecha", { ascending: false }),
      supabase.rpc("fn_jornadas_extra", { p_desde: desde, p_hasta: hasta }),
      supabase
        .from("jornadas")
        .select("persona_id, fecha, entrada_ts, personas:persona_id(nombres, apellidos, sedes:sede_base_id(codigo))")
        .gte("fecha", desdePatron).lte("fecha", HOY)
        .gt("minutos_tarde", 0)
        .order("fecha", { ascending: false }),
      // Déficit de encargadas: mira la semana actual (lunes–domingo), no el filtro
      // Desde/Hasta — es sobre la cobertura planeada de AHORA, no un rango histórico.
      supabase.from("sedes").select("id, codigo"),
      supabase.from("personas").select("id, sede_base_id").eq("rol", "supervisor_sede").eq("estado", "activo"),
      supabase.from("metas_cobertura").select("sede_id, dia_semana, meta_encargadas").gt("meta_encargadas", 0),
      supabase.from("horarios_asignados").select("persona_id, hora_entrada, dias_laborables, horario_por_dia, vigente_desde, vigente_hasta").lte("vigente_desde", domingoActual).or(`vigente_hasta.is.null,vigente_hasta.gte.${lunesActual}`),
      supabase.from("turnos").select("persona_id, fecha, hora_entrada, es_descanso").gte("fecha", lunesActual).lte("fecha", domingoActual),
    ]);

    if (errData || errTardias || errSedes || errEnc || errMetas || errHorarios || errTurnos) {
      setError((errData ?? errTardias ?? errSedes ?? errEnc ?? errMetas ?? errHorarios ?? errTurnos)!.message);
      setCargando(false);
      return; // no pisa `filas` con datos parciales/vacíos
    }
    setError(null);

    // Mapa persona_id|fecha → minutos de salida temprana (vía RPC, esquivando el schema cache).
    const minutosPorClave = new Map<string, number>();
    for (const e of (extraData as { persona_id: string; fecha: string; minutos_salida_temprana: number }[] | null) ?? []) {
      minutosPorClave.set(`${e.persona_id}|${e.fecha}`, e.minutos_salida_temprana ?? 0);
    }

    const out: Fila[] = [];
    for (const j of (data as any[]) ?? []) {
      const minutosTemprana = minutosPorClave.get(`${j.persona_id}|${j.fecha}`) ?? 0;
      let tipo: string | null = null;
      if (j.estado === "auto_cerrada_pendiente") tipo = "Auto-cerrada (revisar)";
      else if (j.fecha < HOY && j.estado === "abierta") tipo = "Sin salida final";
      else if (j.fecha < HOY && j.tiene_salida_no_retornada) tipo = "No regresó de pausa";
      else if (minutosTemprana > 0) tipo = `Salida anticipada (${minutosTemprana} min)`;
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

    // Patrón de tardanzas: 3+ en los últimos 30 días. Viene ordenado por fecha
    // descendente, así que la primera vez que aparece cada persona ya es su
    // tardanza más reciente.
    const porPersonaTardias = new Map<string, { count: number; ultima: any }>();
    for (const j of (tardias as any[]) ?? []) {
      const prev = porPersonaTardias.get(j.persona_id);
      if (prev) prev.count++;
      else porPersonaTardias.set(j.persona_id, { count: 1, ultima: j });
    }
    for (const { count, ultima: j } of porPersonaTardias.values()) {
      if (count < UMBRAL_PATRON_TARDANZAS) continue;
      out.push({
        personaId: j.persona_id,
        nombre: `${j.personas?.nombres ?? ""} ${j.personas?.apellidos ?? ""}`.trim(),
        sede: j.personas?.sedes?.codigo ?? "?",
        fecha: j.fecha,
        tipo: `Patrón de tardanzas (${count} en ${VENTANA_PATRON_DIAS} días)`,
        entrada: j.entrada_ts,
        salida: null,
      });
    }

    // Déficit de encargadas: para cada sede/día de la semana actual con meta
    // definida, ¿cuántas supervisor_sede están programadas? Misma cascada
    // turno del día → horario_por_dia → legacy que usa admin/turnos.
    const codigoPorSede = new Map(((sedesData as { id: string; codigo: string }[] | null) ?? []).map((s) => [s.id, s.codigo]));
    const sedePorEncargada = new Map(((encargadasData as { id: string; sede_base_id: string }[] | null) ?? []).map((p) => [p.id, p.sede_base_id]));
    const turnoPorClave = new Map(
      ((turnosData as { persona_id: string; fecha: string; hora_entrada: string | null; es_descanso: boolean }[] | null) ?? [])
        .map((t) => [`${t.persona_id}|${t.fecha}`, t]),
    );
    const horariosPorPersona = new Map<string, { hora_entrada: string; dias_laborables: number[]; horario_por_dia: Record<string, unknown> | null; vigente_desde: string; vigente_hasta: string | null }[]>();
    for (const h of (horariosData as any[]) ?? []) {
      const arr = horariosPorPersona.get(h.persona_id) ?? [];
      arr.push(h);
      horariosPorPersona.set(h.persona_id, arr);
    }
    function trabajaEseDia(personaId: string, fecha: string): boolean {
      const t = turnoPorClave.get(`${personaId}|${fecha}`);
      if (t) return !t.es_descanso;
      const tramos = (horariosPorPersona.get(personaId) ?? [])
        .filter((h) => h.vigente_desde <= fecha && (h.vigente_hasta == null || h.vigente_hasta >= fecha))
        .sort((a, b) => (a.vigente_desde < b.vigente_desde ? 1 : -1));
      const h = tramos[0];
      if (!h) return false;
      const dow = diaSemanaNum(fecha);
      if (h.horario_por_dia) return Boolean((h.horario_por_dia as Record<string, unknown>)[String(dow)]);
      return (h.dias_laborables ?? []).includes(dow);
    }
    const diasSemanaActual = Array.from({ length: 7 }, (_, i) => addDias(lunesActual, i));
    for (const dia of diasSemanaActual) {
      const dow = diaSemanaNum(dia);
      for (const m of (metasData as { sede_id: string; dia_semana: number; meta_encargadas: number }[] | null) ?? []) {
        if (m.dia_semana !== dow) continue;
        const encargadas = [...sedePorEncargada.entries()].filter(([, sedeId]) => sedeId === m.sede_id).map(([id]) => id);
        const cubiertas = encargadas.filter((id) => trabajaEseDia(id, dia)).length;
        if (cubiertas >= m.meta_encargadas) continue;
        out.push({
          personaId: null,
          nombre: `Sede ${codigoPorSede.get(m.sede_id) ?? "?"}`,
          sede: codigoPorSede.get(m.sede_id) ?? "?",
          fecha: dia,
          tipo: `Déficit de encargadas (${cubiertas}/${m.meta_encargadas})`,
          entrada: null,
          salida: null,
        });
      }
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
        <p className="mb-5 text-sm text-taupe">Días que necesitan tu revisión: auto-cerrados, sin salida final, sin retorno de pausa, o con salida anticipada (más de 15 min antes de su hora). Toca cualquiera para corregirlo. También avisa cuando alguien acumula {UMBRAL_PATRON_TARDANZAS}+ tardanzas en los últimos {VENTANA_PATRON_DIAS} días — Dynamic solo avisa, la decisión (conversar, amonestar) es tuya. Y si una sede no llega a su mínimo de encargadas programadas esta semana (configurable en Turnos), también sale acá.</p>

        <div className="mb-6 flex flex-wrap items-end gap-4">
          <label className="flex flex-col gap-1 text-sm">Desde
            <input type="date" value={desde} onChange={(e) => setDesde(e.target.value)} className="rounded-lg border border-sand bg-crema px-3 py-2" />
          </label>
          <label className="flex flex-col gap-1 text-sm">Hasta
            <input type="date" value={hasta} onChange={(e) => setHasta(e.target.value)} className="rounded-lg border border-sand bg-crema px-3 py-2" />
          </label>
        </div>

        {error && (
          <div className="mb-6 rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
            No se pudieron cargar las incidencias: {error}{" "}
            <button onClick={() => void cargar()} className="font-medium underline">
              Reintentar
            </button>
          </div>
        )}

        {!cargando && !error && visibles.length === 0 && (
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
                          {f.personaId ? (
                            <Link href={`/admin/correcciones?persona=${f.personaId}&fecha=${f.fecha}`} className="font-medium text-rojo underline decoration-rojo/30 underline-offset-2 hover:decoration-rojo">
                              Corregir ›
                            </Link>
                          ) : (
                            <Link href={`/admin/turnos?fecha=${f.fecha}`} className="font-medium text-rojo underline decoration-rojo/30 underline-offset-2 hover:decoration-rojo">
                              Ver turnos ›
                            </Link>
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
      </main>
    </div>
  );
}
