"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import Link from "next/link";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { AdminNav } from "../../nav";
import { GraficoHoras, type DiaGrafico } from "@/components/grafico-horas";
import { MESES, nivelPlus, type ObjetivoItem } from "@/lib/objetivos";

const TZ = "America/Lima";
const META_DIA = 7.5; // horas objetivo por día (45h/semana)

function fechaCorta(iso: string | null): string {
  if (!iso) return "—";
  const [y, m, d] = iso.slice(0, 10).split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "long", year: "numeric", timeZone: "UTC" }).format(new Date(Date.UTC(y, m - 1, d)));
}
function selloLima(iso: string): string {
  const d = new Date(iso);
  return isNaN(d.getTime()) ? iso : new Intl.DateTimeFormat("es-PE", { timeZone: TZ, day: "2-digit", month: "short", year: "numeric" }).format(d);
}
function hoyLima(): string { return new Intl.DateTimeFormat("en-CA", { timeZone: TZ }).format(new Date()); }
function inicioMes(): string { return hoyLima().slice(0, 8) + "01"; }
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
const soles = (n: number) => `S/ ${n.toLocaleString("es-PE", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

const NIVEL: Record<string, string> = { verbal: "Llamada verbal", amonestacion: "Amonestación escrita", suspension: "Suspensión", imputacion: "Imputación", despido: "Despido" };
const CAUSAL: Record<string, string> = { tardanza: "Tardanzas", falta: "Faltas", conducta: "Conducta" };
const ESTADO_DOC: Record<string, string> = { borrador: "Borrador", firmado: "Firmado", entregado: "Entregado", anulado: "Anulado" };

interface Persona { id: string; nombres: string; apellidos: string; documento: string | null; funcion: string; sede_base_id: string; fecha_ingreso: string; email: string | null; estado: string; en_planilla: boolean; sueldo_fijo: boolean }
interface Ficha { nombre_dni: string | null; fecha_nacimiento: string | null; estado_civil: string | null; direccion: string | null; celular: string | null; entidad_bancaria: string | null; numero_cuenta: string | null; grado_instruccion: string | null; hijos_menores: boolean | null; foto_personal_url: string | null }
interface Salario { rango: string; salario_mensual_soles: number; vigente_desde: string; vigente_hasta: string | null }
interface DocLite { id: string; correlativo: string | null; tipo_causal: string; nivel: string; estado: string; creado_at: string; firmado_at: string | null }
interface Jornada { fecha: string; entrada_ts: string | null; salida_final_ts: string | null; horas_trabajadas: number | null; minutos_tarde: number | null; minutos_salida_temprana: number | null; horas_extra_detectadas: number | null; estado: string }

type Tab = "ficha" | "desempeno";

export default function PerfilPersonaPage() {
  const params = useParams();
  const id = (params?.id as string) ?? "";
  const router = useRouter();
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;
  const puede = rol === "admin" || rol === "lider_do" || rol === "supervisor_sede";
  // El sueldo solo lo ve DO (la fn_historial_salario ya lo bloquea en BD; aquí ocultamos
  // la sección para que a la encargada no le aparezca "sin salario" — que sería mentira).
  const puedeSalario = rol === "admin" || rol === "lider_do";
  const supabase = useMemo(() => createAdminSupabaseClient(), []);

  const [tab, setTab] = useState<Tab>("ficha");

  // ── Ficha ──────────────────────────────────────────────────────────────
  const [persona, setPersona] = useState<Persona | null>(null);
  const [ficha, setFicha] = useState<Ficha | null>(null);
  const [sede, setSede] = useState<string>("");
  const [salario, setSalario] = useState<Salario | null>(null);
  const [docs, setDocs] = useState<DocLite[]>([]);
  const [cargando, setCargando] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [incluirSueldo, setIncluirSueldo] = useState(true); // controla si el sueldo entra al PDF

  const cargar = useCallback(async () => {
    setCargando(true); setErr(null);
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    const { data: p, error: eP } = await supabase.from("personas")
      .select("id, nombres, apellidos, documento, funcion, sede_base_id, fecha_ingreso, email, estado, en_planilla, sueldo_fijo")
      .eq("id", id).maybeSingle();
    if (eP || !p) { setErr("No se encontró a la persona (o no tienes permiso para verla)."); setCargando(false); return; }
    setPersona(p as Persona);
    const [{ data: s }, { data: dp }, { data: sal }, { data: dd }] = await Promise.all([
      supabase.from("sedes").select("id, codigo"),
      supabase.from("datos_personales")
        .select("nombre_dni, fecha_nacimiento, estado_civil, direccion, celular, entidad_bancaria, numero_cuenta, grado_instruccion, hijos_menores, foto_personal_url")
        .eq("persona_id", id).maybeSingle(),
      supabase.rpc("fn_historial_salario", { p_persona_id: id }),
      supabase.from("expediente_disciplinario")
        .select("id, correlativo, tipo_causal, nivel, estado, creado_at, firmado_at")
        .eq("persona_id", id).order("creado_at", { ascending: false }),
    ]);
    const smap = new Map(((s as Array<{ id: string; codigo: string }>) ?? []).map((x) => [x.id, x.codigo]));
    setSede(smap.get((p as Persona).sede_base_id) ?? "");
    setFicha((dp as Ficha) ?? null);
    const hist = (sal as Salario[]) ?? [];
    setSalario(hist.find((x) => !x.vigente_hasta) ?? hist[0] ?? null);
    setDocs((dd as DocLite[]) ?? []);
    setCargando(false);
  }, [supabase, router, id]);

  useEffect(() => { void cargar(); }, [cargar]);

  // ── Desempeño (se carga solo al abrir su pestaña) ────────────────────────
  const [desde, setDesde] = useState(inicioMes());
  const [hasta, setHasta] = useState(hoyLima());
  const [jornadas, setJornadas] = useState<Jornada[]>([]);
  const [levTard, setLevTard] = useState<Map<string, string>>(new Map());
  const [objetivos, setObjetivos] = useState<ObjetivoItem[]>([]);
  const [cargandoDes, setCargandoDes] = useState(false);
  const [desCargado, setDesCargado] = useState(false);
  const [errDes, setErrDes] = useState<string | null>(null);

  const cargarDesempeno = useCallback(async () => {
    setCargandoDes(true); setErrDes(null);
    const [{ data, error: eJ }, { data: extra }, { data: objs }, { data: levData }] = await Promise.all([
      supabase.from("jornadas")
        .select("fecha, entrada_ts, salida_final_ts, horas_trabajadas, minutos_tarde, horas_extra_detectadas, estado")
        .eq("persona_id", id).gte("fecha", desde).lte("fecha", hasta).order("fecha"),
      supabase.rpc("fn_jornadas_extra", { p_desde: desde, p_hasta: hasta, p_persona_id: id }),
      supabase.rpc("fn_objetivos_checklist", { p_anio: Number(hasta.slice(0, 4)), p_mes: Number(hasta.slice(5, 7)), p_persona_id: id }),
      supabase.from("tardanzas_justificadas").select("fecha, motivo").eq("persona_id", id).gte("fecha", desde).lte("fecha", hasta),
    ]);
    if (eJ) { setErrDes(eJ.message); setCargandoDes(false); return; }
    setObjetivos(((objs as unknown as ObjetivoItem[] | null) ?? []).slice());
    const filasExtra = (extra as { fecha: string; minutos_salida_temprana: number }[] | null) ?? [];
    const minutosPorFecha = new Map(filasExtra.map((e) => [e.fecha, e.minutos_salida_temprana]));
    const filas = ((data as Omit<Jornada, "minutos_salida_temprana">[] | null) ?? []).map((j) => ({ ...j, minutos_salida_temprana: minutosPorFecha.get(j.fecha) ?? null }));
    setJornadas(filas);
    setLevTard(new Map(((levData as { fecha: string; motivo: string }[] | null) ?? []).map((t) => [t.fecha, t.motivo])));
    setDesCargado(true);
    setCargandoDes(false);
  }, [supabase, id, desde, hasta]);

  // Primera vez que se abre la pestaña Desempeño, se carga con el rango por defecto.
  useEffect(() => {
    if (tab === "desempeno" && !desCargado && !cargandoDes) void cargarDesempeno();
  }, [tab, desCargado, cargandoDes, cargarDesempeno]);

  // Un día no puede tener más de 24 h: si las tiene, es un AGREGADO del histórico 2025
  // (mes entero en una fecha). Suma al total pero no al promedio ni al gráfico.
  const stats = useMemo(() => {
    const esAgregado = (j: Jornada) => (j.horas_trabajadas ?? 0) > 24;
    const agregados = jornadas.filter(esAgregado);
    const reales = jornadas.filter((j) => !esAgregado(j));
    const totalHoras = jornadas.reduce((s, j) => s + (j.horas_trabajadas ?? 0), 0);
    const horasAgregadas = agregados.reduce((s, j) => s + (j.horas_trabajadas ?? 0), 0);
    const diasTrabajados = reales.filter((j) => (j.horas_trabajadas ?? 0) > 0).length;
    return {
      esAgregado, agregados, totalHoras, horasAgregadas,
      horasReales: totalHoras - horasAgregadas,
      diasTrabajados,
      diasTardeMedidos: jornadas.filter((j) => j.minutos_tarde !== null).length,
      tardanzas: jornadas.filter((j) => (j.minutos_tarde ?? 0) > 0 && !levTard.has(j.fecha)).length,
      diasSalidaMedidos: jornadas.filter((j) => j.minutos_salida_temprana !== null).length,
      salidasTempranas: jornadas.filter((j) => (j.minutos_salida_temprana ?? 0) > 0).length,
      horasExtra: jornadas.reduce((s, j) => s + (j.horas_extra_detectadas ?? 0), 0),
      datosGrafico: reales.map((j) => ({ fecha: j.fecha, horas: j.horas_trabajadas ?? 0 })) as DiaGrafico[],
    };
  }, [jornadas, levTard]);

  const objCumplidos = objetivos.filter((o) => o.cumplido).length;
  const objNivel = nivelPlus(objCumplidos, objetivos.length);
  const objPct = objetivos.length > 0 ? Math.round((objCumplidos / objetivos.length) * 100) : 0;
  const objMesLabel = `${MESES[Number(hasta.slice(5, 7)) - 1]} ${hasta.slice(0, 4)}`;

  function incidencia(j: Jornada): string | null {
    if (j.estado === "auto_cerrada_pendiente") return "Auto-cerrada";
    if (j.entrada_ts && !j.salida_final_ts) return "Sin salida";
    return null;
  }

  if (rol !== null && !puede) {
    return (
      <div className="flex min-h-screen flex-col"><AdminNav />
        <main className="flex flex-1 items-center justify-center p-6"><p className="max-w-md text-center text-taupe">No tienes permiso para ver perfiles.</p></main>
      </div>
    );
  }

  const nombre = persona ? `${persona.nombres} ${persona.apellidos}` : "";
  const iniciales = persona ? `${persona.nombres[0] ?? ""}${persona.apellidos[0] ?? ""}` : "";

  function Dato({ label, valor }: { label: string; valor: React.ReactNode }) {
    return (
      <div className="flex justify-between gap-3 border-b border-sand/50 py-1.5 text-sm last:border-0">
        <span className="text-taupe">{label}</span>
        <span className="text-right">{valor ?? "—"}</span>
      </div>
    );
  }

  const TabBtn = ({ valor, children }: { valor: Tab; children: React.ReactNode }) => (
    <button
      onClick={() => setTab(valor)}
      className={`-mb-px border-b-2 px-4 py-2 text-sm transition-colors ${
        tab === valor ? "border-rojo font-medium text-tinta" : "border-transparent text-taupe hover:text-tinta"}`}
    >
      {children}
    </button>
  );

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <style>{`
          .solo-print{display:none}
          @page{margin:16mm}
          @media print{
            header,.no-print{display:none!important}
            .solo-print{display:flex!important}
            body{background:#fff!important}
            main{padding:0!important}
            section{break-inside:avoid;background:#fff!important}
            .colibri{print-color-adjust:exact;-webkit-print-color-adjust:exact}
          }
        `}</style>
        <div className="no-print mb-4 flex flex-wrap items-center justify-between gap-3">
          <button onClick={() => router.back()} className="text-sm text-taupe hover:text-tinta">← Volver</button>
          {persona && (
            <div className="flex items-center gap-3">
              {puedeSalario && (
                <label className="flex items-center gap-1.5 text-xs text-taupe">
                  <input type="checkbox" checked={incluirSueldo} onChange={(e) => setIncluirSueldo(e.target.checked)} className="h-3.5 w-3.5 accent-tinta" />
                  Incluir sueldo en el PDF
                </label>
              )}
              <button onClick={() => { setTab("ficha"); setTimeout(() => window.print(), 60); }} className="rounded-xl bg-tinta px-3 py-1.5 text-xs font-medium text-crema">Descargar PDF</button>
            </div>
          )}
        </div>
        {persona && (
          <div className="solo-print mb-6 items-center gap-3 border-b border-sand pb-4">
            <span className="colibri w-10 text-rojo" aria-hidden />
            <div>
              <div className="font-serif text-xl">Ficha de {ficha?.nombre_dni || nombre}</div>
              <div className="text-xs text-taupe">CAYLA · Dynamic · {new Date().toLocaleDateString("es-PE", { day: "2-digit", month: "long", year: "numeric" })}</div>
            </div>
          </div>
        )}

        {cargando ? (
          <div className="flex flex-col items-center gap-4 py-24 text-taupe">
            <span className="colibri aletea w-12 text-rojo/70" aria-hidden />
            <span className="text-sm">Cargando el perfil…</span>
          </div>
        ) : err ? (
          <p className="max-w-xl rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">{err}</p>
        ) : persona && (
          <>
            {/* Cabecera */}
            <div className="mb-4 flex flex-wrap items-center gap-4">
              <div className="flex h-16 w-16 shrink-0 items-center justify-center rounded-full bg-rojo/10 font-serif text-2xl text-rojo">{iniciales.toUpperCase()}</div>
              <div className="min-w-0">
                <h1 className="font-serif text-2xl leading-tight">{ficha?.nombre_dni || nombre}</h1>
                <p className="text-sm text-taupe">
                  {persona.funcion} · Sede {sede || "—"}
                  {persona.estado !== "activo" && <span className="ml-2 rounded-full bg-sand/60 px-2 py-0.5 text-xs">{persona.estado}</span>}
                  {persona.sueldo_fijo && <span className="ml-2 rounded-full bg-sand/60 px-2 py-0.5 text-xs">sueldo fijo</span>}
                  {!persona.en_planilla && <span className="ml-2 rounded-full bg-amber-100 px-2 py-0.5 text-xs text-amber-800">fuera de planilla</span>}
                </p>
                <p className="mt-0.5 text-xs text-taupe">DNI {persona.documento ?? "—"} · Ingresó {fechaCorta(persona.fecha_ingreso)}</p>
              </div>
            </div>

            {/* Pestañas */}
            <div className="no-print mb-6 flex gap-1 border-b border-sand">
              <TabBtn valor="ficha">Ficha</TabBtn>
              <TabBtn valor="desempeno">Desempeño</TabBtn>
            </div>

            {tab === "ficha" ? (
              <>
                <div className="grid gap-5 lg:grid-cols-2">
                  {/* Datos personales */}
                  <section className="rounded-2xl border border-sand bg-papel p-5">
                    <div className="mb-2 flex items-baseline justify-between">
                      <h2 className="font-serif text-lg">Datos personales</h2>
                      <Link href="/admin/datos-personales" className="no-print text-xs text-tinta hover:underline">Editar →</Link>
                    </div>
                    {ficha ? (
                      <div>
                        <Dato label="Celular" valor={ficha.celular} />
                        <Dato label="Correo" valor={persona.email} />
                        <Dato label="Dirección" valor={ficha.direccion} />
                        <Dato label="Nacimiento" valor={ficha.fecha_nacimiento ? fechaCorta(ficha.fecha_nacimiento) : "—"} />
                        <Dato label="Estado civil" valor={ficha.estado_civil} />
                        <Dato label="Grado de instrucción" valor={ficha.grado_instruccion} />
                        <Dato label="Hijos menores" valor={ficha.hijos_menores == null ? "—" : ficha.hijos_menores ? "Sí" : "No"} />
                        <Dato label="Banco" valor={ficha.entidad_bancaria} />
                        <Dato label="N.° de cuenta" valor={ficha.numero_cuenta} />
                        {ficha.foto_personal_url && <Dato label="Foto" valor={<a href={ficha.foto_personal_url} target="_blank" rel="noreferrer" className="text-tinta underline">ver</a>} />}
                      </div>
                    ) : (
                      <p className="text-sm text-taupe">Sin ficha cargada. <Link href="/admin/datos-personales" className="text-tinta hover:underline">Completar</Link>.</p>
                    )}
                  </section>

                  {/* Compensación — solo DO */}
                  {puedeSalario && (
                  <section className={`rounded-2xl border border-sand bg-papel p-5 ${!incluirSueldo ? "no-print" : ""}`}>
                    <div className="mb-2 flex items-baseline justify-between">
                      <h2 className="font-serif text-lg">Compensación</h2>
                      <Link href="/admin/planilla" className="no-print text-xs text-tinta hover:underline">Planilla →</Link>
                    </div>
                    {salario ? (
                      <div>
                        <Dato label="Sueldo vigente" valor={<strong>{soles(salario.salario_mensual_soles)}</strong>} />
                        <Dato label="Rango" valor={salario.rango} />
                        <Dato label="Desde" valor={selloLima(salario.vigente_desde)} />
                      </div>
                    ) : (
                      <p className="text-sm text-taupe">Sin salario asignado.</p>
                    )}
                  </section>
                  )}

                  {/* Disciplina / legajo */}
                  <section className="rounded-2xl border border-sand bg-papel p-5 lg:col-span-2">
                    <div className="mb-2 flex items-baseline justify-between">
                      <h2 className="font-serif text-lg">Legajo disciplinario {docs.length > 0 && <span className="text-sm font-normal text-taupe">· {docs.length}</span>}</h2>
                      <Link href="/admin/disciplina" className="no-print text-xs text-tinta hover:underline">Disciplina →</Link>
                    </div>
                    {docs.length === 0 ? (
                      <p className="text-sm text-taupe">Sin antecedentes disciplinarios. Buena señal.</p>
                    ) : (
                      <ul className="divide-y">
                        {docs.map((d) => (
                          <li key={d.id} className="flex flex-wrap items-center justify-between gap-x-3 gap-y-1 py-2 text-sm">
                            <span>
                              <strong>{NIVEL[d.nivel] ?? d.nivel}</strong> <span className="text-taupe">· {CAUSAL[d.tipo_causal] ?? d.tipo_causal}</span>
                              {d.correlativo && <span className="ml-2 text-xs text-taupe">{d.correlativo}</span>}
                            </span>
                            <span className="flex items-center gap-2 text-xs text-taupe">
                              {selloLima(d.firmado_at ?? d.creado_at)}
                              <span className={`rounded-full px-2 py-0.5 ${d.estado === "anulado" ? "bg-sand/50 text-taupe" : d.estado === "borrador" ? "bg-amber-100 text-amber-800" : "bg-sand/60 text-tinta"}`}>{ESTADO_DOC[d.estado] ?? d.estado}</span>
                              <Link href={`/admin/disciplina/memo/${d.id}`} className="text-tinta hover:underline">ver</Link>
                            </span>
                          </li>
                        ))}
                      </ul>
                    )}
                  </section>
                </div>

                {/* El perfil consolida; el detalle vive en cada módulo. Solo enlazamos lo que
                    abre YA filtrado por esta persona (si no filtrara, el enlace mentiría). */}
                <div className="no-print mt-6 flex flex-wrap items-center gap-2 text-sm">
                  <span className="py-1 text-taupe">Registro de {persona.nombres}:</span>
                  <Link href={`/admin/horas?persona=${persona.id}`} className="rounded-xl border border-sand bg-papel px-3 py-1 transition-all hover:-translate-y-0.5 hover:border-taupe">Horas y tardanzas</Link>
                  <Link href={`/admin/incidencias?persona=${persona.id}`} className="rounded-xl border border-sand bg-papel px-3 py-1 transition-all hover:-translate-y-0.5 hover:border-taupe">Incidencias</Link>
                </div>
              </>
            ) : (
              /* ── Pestaña Desempeño ── */
              <>
                <div className="mb-6 flex flex-wrap items-end gap-4">
                  <label className="flex flex-col gap-1 text-sm">Desde
                    <input type="date" value={desde} onChange={(e) => setDesde(e.target.value)} className="rounded-lg border border-sand bg-crema px-3 py-2" />
                  </label>
                  <label className="flex flex-col gap-1 text-sm">Hasta
                    <input type="date" value={hasta} onChange={(e) => setHasta(e.target.value)} className="rounded-lg border border-sand bg-crema px-3 py-2" />
                  </label>
                  <button onClick={() => void cargarDesempeno()} disabled={cargandoDes} className="rounded-lg bg-tinta px-5 py-2 text-sm font-medium text-crema disabled:opacity-50">
                    {cargandoDes ? "Cargando…" : "Actualizar"}
                  </button>
                </div>

                {errDes && (
                  <div className="mb-6 max-w-2xl rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
                    No se pudo cargar el desempeño: {errDes}{" "}
                    <button onClick={() => void cargarDesempeno()} className="font-medium underline">Reintentar</button>
                  </div>
                )}

                {!desCargado && cargandoDes && <p className="text-sm text-taupe">Cargando…</p>}

                {desCargado && (
                  <>
                    <div className="mb-6 grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
                      {[
                        { label: "Total del periodo", valor: fmtHoras(stats.totalHoras) },
                        { label: "Días trabajados", valor: String(stats.diasTrabajados) },
                        { label: "Promedio por día", valor: stats.diasTrabajados ? fmtHoras(stats.horasReales / stats.diasTrabajados) : "—" },
                        { label: "Días con tardanza", valor: `${stats.tardanzas} de ${stats.diasTardeMedidos} medidos` },
                        { label: "Salidas anticipadas", valor: `${stats.salidasTempranas} de ${stats.diasSalidaMedidos} medidos` },
                        { label: "Tiempo adicional", valor: stats.horasExtra > 0 ? fmtHoras(stats.horasExtra) : "—" },
                      ].map((c) => (
                        <div key={c.label} className="rounded-2xl border border-sand bg-papel px-4 py-3 transition-all hover:-translate-y-0.5 hover:border-taupe">
                          <div className="etiqueta text-taupe">{c.label}</div>
                          <div className="mt-1 font-serif text-2xl">{c.valor}</div>
                        </div>
                      ))}
                    </div>

                    {stats.agregados.length > 0 && (
                      <p className="mb-6 -mt-3 max-w-3xl text-xs text-taupe">
                        Incluye <strong>{stats.agregados.length} registro{stats.agregados.length === 1 ? "" : "s"} histórico{stats.agregados.length === 1 ? "" : "s"} de 2025</strong> ({fmtHoras(stats.horasAgregadas)}):
                        el total de un mes completo guardado en una sola fecha, porque en 2025 todavía no había marcaje diario.
                        Suman al <strong>total del periodo</strong> (y la planilla los usó para CTS y gratificación),
                        pero no cuentan como día, así que quedan fuera del promedio y del gráfico.
                      </p>
                    )}

                    {objetivos.length > 0 && (
                      <div className="mb-6 max-w-3xl rounded-2xl border border-sand bg-papel p-5">
                        <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
                          <h2 className="font-serif text-lg">Objetivos de {objMesLabel.toLowerCase()}</h2>
                          <span className="flex items-center gap-2 text-sm">
                            <span className="text-taupe">{objCumplidos}/{objetivos.length} cumplidos</span>
                            <span className={`rounded-full px-3 py-0.5 ${objNivel.etiqueta === "Sin plus" || objNivel.etiqueta === "—" ? "bg-sand text-taupe" : "bg-verde/15 font-medium text-verde"}`}>{objNivel.etiqueta}</span>
                          </span>
                        </div>
                        <div className="mb-3 h-2 overflow-hidden rounded-full bg-sand">
                          <div className={`h-full rounded-full ${objPct >= 60 ? "bg-verde" : objPct >= 30 ? "bg-ambar" : "bg-rojo"}`} style={{ width: `${objPct}%` }} />
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

                    <div className="mb-8 rounded-2xl border border-sand bg-papel p-5">
                      <h2 className="mb-3 font-serif text-lg">Horas por día</h2>
                      <GraficoHoras dias={stats.datosGrafico} meta={META_DIA} />
                    </div>

                    <div className="overflow-x-auto rounded-2xl border border-sand">
                      <table className="w-full text-sm">
                        <thead className="bg-sand/70 text-left">
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
                                <tr key={j.fecha} className="border-t border-sand bg-papel transition-colors hover:bg-crema">
                                  <td className="px-4 py-2.5 capitalize">
                                    {fechaLarga(j.fecha)}
                                    {stats.esAgregado(j) && (
                                      <span className="ml-2 whitespace-nowrap rounded-full bg-taupe/15 px-2 py-0.5 text-[10px] normal-case text-taupe">total del mes · histórico 2025</span>
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
                                      <Link href={`/admin/correcciones?persona=${id}&fecha=${j.fecha}`} className="font-medium text-rojo underline decoration-rojo/30 underline-offset-2 hover:decoration-rojo">{inc} ›</Link>
                                    ) : <span className="text-taupe/40">—</span>}
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
              </>
            )}
          </>
        )}
      </main>
    </div>
  );
}
