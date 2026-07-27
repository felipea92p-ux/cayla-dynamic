"use client";

import { Suspense, useCallback, useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { parseAreas, esOperativaEn, AREA_DEFAULT, type Area } from "@/lib/areas";
import { AdminNav } from "../nav";
import { Cargando } from "@/components/cargando";

const TZ = "America/Lima";
const CORTE_TARDE = 14.25; // mismo corte mañana/tarde que Turnos/Dashboard
const MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"];

function hoyLima(): string { return new Intl.DateTimeFormat("en-CA", { timeZone: TZ }).format(new Date()); }
function mesActual(): string { return hoyLima().slice(0, 7); } // yyyy-mm
function finDeMes(mes: string): string {
  const [y, m] = mes.split("-").map(Number);
  return `${mes}-${String(new Date(Date.UTC(y, m, 0)).getUTCDate()).padStart(2, "0")}`;
}
function diaSemanaDe(iso: string): number {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d)).getUTCDay();
}
function horaDecimalLimaAhora(): number {
  const p = new Intl.DateTimeFormat("en-GB", { timeZone: TZ, hour: "2-digit", minute: "2-digit", hour12: false }).formatToParts(new Date());
  const h = Number(p.find((x) => x.type === "hour")?.value ?? 0) % 24;
  const m = Number(p.find((x) => x.type === "minute")?.value ?? 0);
  return h + m / 60;
}
function fmtHoras(h: number): string { const hh = Math.floor(h); const mm = Math.round((h - hh) * 60); return `${hh}h ${String(mm).padStart(2, "0")}m`; }

interface Sede { id: string; codigo: string; nombre: string }
interface Fila {
  personaId: string; nombre: string;
  estadoHoy: string; // abierta / en_pausa / cerrada / sin_marcar
  esOperativa: boolean; esEncargada: boolean;
  dias: number; horas: number; tardanzas: number; minTarde: number; salidasTemp: number;
}
interface Meta { man: number; tar: number; enc: number }
interface TardRow { persona_id: string; nombre: string; sede: string; tardanzas_mes: number; umbral: string }
interface FaltaRow { persona_id: string; nombre: string; sede: string; nivel: string }

function ReporteSedeContenido() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const supabase = useMemo(() => createAdminSupabaseClient(), []);

  const [sedes, setSedes] = useState<Sede[]>([]);
  const [sedeId, setSedeId] = useState<string>("");
  const [mes, setMes] = useState(mesActual());
  const [filas, setFilas] = useState<Fila[]>([]);
  const [meta, setMeta] = useState<Meta>({ man: 0, tar: 0, enc: 0 });
  const [tardAlerta, setTardAlerta] = useState<TardRow[]>([]);
  const [faltaAlerta, setFaltaAlerta] = useState<FaltaRow[]>([]);
  const [cargando, setCargando] = useState(false);
  const [cargado, setCargado] = useState(false);

  // Cargar sedes (para el selector). Pre-selecciona la del ?sede=CODIGO si viene.
  useEffect(() => {
    void (async () => {
      const { data: sesion } = await supabase.auth.getSession();
      if (!sesion.session) { router.replace("/admin/login"); return; }
      const { data } = await supabase.from("sedes").select("id, codigo, nombre").eq("activa", true).order("codigo");
      const lista = (data as Sede[]) ?? [];
      setSedes(lista);
      const cod = searchParams.get("sede")?.toUpperCase();
      const pre = cod ? lista.find((s) => s.codigo === cod) : lista[0];
      if (pre) setSedeId(pre.id);
    })();
  }, [supabase, router, searchParams]);

  const cargar = useCallback(async () => {
    if (!sedeId) return;
    setCargando(true);
    const hoy = hoyLima();
    const desde = `${mes}-01`;
    const hasta = mes === mesActual() ? hoy : finDeMes(mes);
    const diaHoy = diaSemanaDe(hoy);
    const codigoSede = sedes.find((s) => s.id === sedeId)?.codigo ?? "";

    const [
      { data: personas },
      { data: jornadas },
      { data: extras },
      { data: funciones },
      { data: areasRaw, error: errAreas },
      { data: metasRaw },
      { data: tardResumen },
      { data: faltasResumen },
    ] = await Promise.all([
      supabase.from("personas").select("id, nombres, apellidos, rol, sede_base_id")
        .eq("estado", "activo").eq("en_planilla", true).eq("sueldo_fijo", false).eq("sede_base_id", sedeId).order("nombres"),
      supabase.from("jornadas").select("persona_id, fecha, estado, minutos_tarde, horas_trabajadas").gte("fecha", desde).lte("fecha", hasta),
      supabase.rpc("fn_jornadas_extra", { p_desde: desde, p_hasta: hasta }),
      supabase.rpc("fn_personas_funciones"),
      supabase.rpc("fn_areas"),
      supabase.from("metas_cobertura").select("sede_id, meta, meta_tarde, meta_encargadas").eq("dia_semana", diaHoy).eq("sede_id", sedeId),
      supabase.rpc("fn_tardanzas_resumen", {}),
      supabase.rpc("fn_faltas_resumen", {}),
    ]);

    const areasList: Area[] = parseAreas(areasRaw, errAreas);
    const funcionPorPersona = new Map(
      ((funciones as { persona_id: string; funcion: string; es_encargada_piso?: boolean }[] | null) ?? [])
        .map((x) => [x.persona_id, { funcion: x.funcion, enc: Boolean(x.es_encargada_piso) }]));
    const m = ((metasRaw as { meta: number; meta_tarde: number | null; meta_encargadas: number | null }[] | null) ?? [])[0];
    setMeta({ man: m?.meta ?? 0, tar: m?.meta_tarde ?? m?.meta ?? 0, enc: m?.meta_encargadas ?? 0 });

    // Salidas anticipadas del mes (RPC; solo filas > 0).
    const salTemp = new Map<string, number>();
    for (const e of ((extras as { persona_id: string; fecha: string; minutos_salida_temprana: number }[] | null) ?? [])) {
      salTemp.set(e.persona_id, (salTemp.get(e.persona_id) ?? 0) + 1);
    }
    // Jornadas agrupadas por persona.
    const jorPorPersona = new Map<string, { fecha: string; estado: string; minutos_tarde: number | null; horas_trabajadas: number | null }[]>();
    for (const j of (jornadas as any[]) ?? []) {
      const arr = jorPorPersona.get(j.persona_id) ?? [];
      arr.push(j); jorPorPersona.set(j.persona_id, arr);
    }

    const filasCalc: Fila[] = ((personas as any[]) ?? []).map((p) => {
      const js = jorPorPersona.get(p.id) ?? [];
      const reales = js.filter((j) => (j.horas_trabajadas ?? 0) <= 24); // excluye agregados históricos 2025
      const hoyJ = js.find((j) => j.fecha === hoy);
      const f = funcionPorPersona.get(p.id);
      return {
        personaId: p.id,
        nombre: `${p.nombres} ${p.apellidos}`,
        estadoHoy: hoyJ?.estado ?? "sin_marcar",
        esOperativa: esOperativaEn(areasList, f?.funcion ?? AREA_DEFAULT),
        esEncargada: p.rol === "supervisor_sede" || Boolean(f?.enc),
        dias: reales.filter((j) => (j.horas_trabajadas ?? 0) > 0).length,
        horas: js.reduce((s, j) => s + (j.horas_trabajadas ?? 0), 0),
        tardanzas: js.filter((j) => (j.minutos_tarde ?? 0) > 0).length,
        minTarde: js.reduce((s, j) => s + (j.minutos_tarde ?? 0), 0),
        salidasTemp: salTemp.get(p.id) ?? 0,
      };
    });
    setFilas(filasCalc);
    setTardAlerta(((tardResumen as TardRow[]) ?? []).filter((t) => t.sede === codigoSede && t.umbral === "amonestacion"));
    setFaltaAlerta(((faltasResumen as FaltaRow[]) ?? []).filter((f) => f.sede === codigoSede && f.nivel === "rojo"));
    setCargado(true);
    setCargando(false);
  }, [supabase, sedeId, mes, sedes]);

  useEffect(() => { if (sedeId) void cargar(); }, [sedeId, cargar]);

  const sede = sedes.find((s) => s.id === sedeId);
  const tramoTarde = horaDecimalLimaAhora() >= CORTE_TARDE;
  const activos = filas.filter((f) => f.estadoHoy === "abierta" || f.estadoHoy === "en_pausa");
  const opPiso = filas.filter((f) => f.esOperativa && f.estadoHoy === "abierta").length;
  const encPiso = filas.filter((f) => f.esEncargada && f.estadoHoy === "abierta").length;
  const metaOp = tramoTarde ? meta.tar : meta.man;
  const mesLabel = `${MESES[Number(mes.slice(5, 7)) - 1]} ${mes.slice(0, 4)}`;

  const Cobertura = ({ label, n, m }: { label: string; n: number; m: number }) => {
    const sinMeta = m <= 0; const ok = !sinMeta && n >= m;
    const color = sinMeta ? "var(--color-taupe)" : ok ? "var(--color-verde)" : "var(--color-rojo)";
    return (
      <span className="flex items-center gap-1.5 text-sm">
        <span className="text-taupe">{label}</span>
        <span className="font-semibold tabular-nums" style={{ color }}>{n}{!sinMeta && <span className="font-normal text-taupe"> / meta {m}</span>}</span>
        {sinMeta ? <span className="text-xs text-taupe/60">sin meta</span> : <span className="text-xs font-medium" style={{ color }}>{ok ? "· completo" : `· faltan ${m - n}`}</span>}
      </span>
    );
  };

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6 sm:p-8">
        <style>{`
          .solo-print{display:none}
          @page{margin:15mm}
          @media print{
            header,.no-print{display:none!important}
            .solo-print{display:flex!important}
            body{background:#fff!important}
            main{padding:0!important}
            section{break-inside:avoid;background:#fff!important}
            .colibri{print-color-adjust:exact;-webkit-print-color-adjust:exact}
          }
        `}</style>

        {/* Controles — no salen en el PDF */}
        <div className="no-print mb-6 flex flex-wrap items-end justify-between gap-4">
          <div>
            <h1 className="font-serif text-2xl leading-tight">Hoja de sede</h1>
            <p className="mt-1 text-sm text-taupe">El estado de una sede en una página: hoy, el mes y lo que necesita atención.</p>
          </div>
          <div className="flex flex-wrap items-end gap-3">
            <label className="flex flex-col gap-1 text-sm">Sede
              <select value={sedeId} onChange={(e) => { setSedeId(e.target.value); setCargado(false); }} className="min-w-40 rounded-xl border border-sand bg-crema px-3 py-2">
                {sedes.map((s) => <option key={s.id} value={s.id}>{s.nombre}</option>)}
              </select>
            </label>
            <label className="flex flex-col gap-1 text-sm">Mes
              <input type="month" value={mes} onChange={(e) => { setMes(e.target.value); setCargado(false); }} className="rounded-xl border border-sand bg-crema px-3 py-2" />
            </label>
            <button onClick={() => window.print()} disabled={!cargado} className="rounded-xl bg-tinta px-4 py-2 text-sm font-medium text-crema disabled:opacity-50">Descargar PDF</button>
          </div>
        </div>

        {/* Cabecera impresa */}
        {sede && (
          <div className="solo-print mb-6 items-center gap-3 border-b border-sand pb-4">
            <span className="colibri w-10 text-rojo" aria-hidden />
            <div>
              <div className="font-serif text-xl">Estado de sede · {sede.nombre}</div>
              <div className="text-xs text-taupe">CAYLA · Dynamic · {mesLabel} · generado {new Date().toLocaleDateString("es-PE", { day: "2-digit", month: "long", year: "numeric" })}</div>
            </div>
          </div>
        )}

        {cargando && !cargado ? (
          <Cargando texto="Armando la hoja…" />
        ) : cargado && sede && (
          <>
            <h2 className="mb-4 font-serif text-2xl">
              {sede.nombre} <span className="text-lg font-normal text-taupe">· {mesLabel}</span>
            </h2>

            {/* HOY */}
            <section className="mb-6 rounded-2xl border border-verde/20 bg-verde/[0.06] p-5">
              <div className="etiqueta text-verde">Hoy · {activos.length} trabajando de {filas.length}</div>
              <div className="mt-3 flex flex-wrap gap-2">
                {activos.length === 0 ? <span className="text-sm text-taupe">Nadie marcado todavía.</span> :
                  activos.map((f) => (
                    <span key={f.personaId} className="rounded-full border border-sand bg-papel px-3 py-1 text-sm">
                      {f.nombre}{f.estadoHoy === "en_pausa" && <span className="ml-1 text-ambar">· en pausa</span>}
                    </span>
                  ))}
              </div>
              <div className="mt-4 flex flex-wrap items-center gap-x-6 gap-y-1 border-t border-verde/15 pt-3">
                <Cobertura label="Operativas en piso" n={opPiso} m={metaOp} />
                <Cobertura label="Encargadas" n={encPiso} m={meta.enc} />
              </div>
            </section>

            {/* EL MES */}
            <section className="mb-6">
              <h3 className="mb-2 font-serif text-lg">El mes · {mesLabel}</h3>
              <div className="overflow-x-auto rounded-2xl border border-sand bg-papel">
                <table className="w-full text-sm [font-variant-numeric:tabular-nums]">
                  <thead className="bg-sand/70 text-left text-taupe">
                    <tr>
                      <th className="px-4 py-2.5 font-medium">Nombre</th>
                      <th className="px-4 py-2.5 font-medium">Días</th>
                      <th className="px-4 py-2.5 font-medium">Horas</th>
                      <th className="px-4 py-2.5 font-medium">Tardanzas</th>
                      <th className="px-4 py-2.5 font-medium">Min. tarde</th>
                      <th className="px-4 py-2.5 font-medium">Sal. antic.</th>
                    </tr>
                  </thead>
                  <tbody>
                    {filas.length === 0 ? (
                      <tr><td colSpan={6} className="px-4 py-6 text-center text-taupe">Sin gente asignada a esta sede.</td></tr>
                    ) : filas.slice().sort((a, b) => b.horas - a.horas).map((f) => (
                      <tr key={f.personaId} className="border-t border-sand">
                        <td className="px-4 py-2.5">{f.nombre}</td>
                        <td className="px-4 py-2.5">{f.dias}</td>
                        <td className="px-4 py-2.5 font-medium">{fmtHoras(f.horas)}</td>
                        <td className="px-4 py-2.5">{f.tardanzas > 0 ? <span className="text-rojo">{f.tardanzas}</span> : <span className="text-taupe/40">—</span>}</td>
                        <td className="px-4 py-2.5">{f.minTarde > 0 ? `${f.minTarde} min` : <span className="text-taupe/40">—</span>}</td>
                        <td className="px-4 py-2.5">{f.salidasTemp > 0 ? f.salidasTemp : <span className="text-taupe/40">—</span>}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </section>

            {/* ATENCIÓN */}
            <section className="rounded-2xl border border-sand bg-rojo/[0.04] p-5">
              <div className="etiqueta mb-2 text-rojo">Necesita atención</div>
              {tardAlerta.length === 0 && faltaAlerta.length === 0 ? (
                <p className="text-sm text-taupe">Nada pendiente en disciplina. Buena señal.</p>
              ) : (
                <ul className="space-y-1.5 text-sm">
                  {tardAlerta.map((t) => (
                    <li key={t.persona_id}><strong>{t.nombre}</strong> — corresponde amonestación por tardanzas ({t.tardanzas_mes} este mes).</li>
                  ))}
                  {faltaAlerta.map((f) => (
                    <li key={f.persona_id}><strong>{f.nombre}</strong> — causal por faltas (art. 25-h). Acción inmediata.</li>
                  ))}
                </ul>
              )}
            </section>
          </>
        )}
      </main>
    </div>
  );
}

export default function ReporteSedePage() {
  return (
    <Suspense fallback={<main className="p-6"><p className="text-sm text-taupe">Cargando…</p></main>}>
      <ReporteSedeContenido />
    </Suspense>
  );
}
