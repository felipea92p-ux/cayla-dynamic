"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import Link from "next/link";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { AdminNav } from "../../nav";

const TZ = "America/Lima";
function fechaCorta(iso: string | null): string {
  if (!iso) return "—";
  const [y, m, d] = iso.slice(0, 10).split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "long", year: "numeric", timeZone: "UTC" }).format(new Date(Date.UTC(y, m - 1, d)));
}
function selloLima(iso: string): string {
  const d = new Date(iso);
  return isNaN(d.getTime()) ? iso : new Intl.DateTimeFormat("es-PE", { timeZone: TZ, day: "2-digit", month: "short", year: "numeric" }).format(d);
}
const soles = (n: number) => `S/ ${n.toLocaleString("es-PE", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

const NIVEL: Record<string, string> = { verbal: "Llamada verbal", amonestacion: "Amonestación escrita", suspension: "Suspensión", imputacion: "Imputación", despido: "Despido" };
const CAUSAL: Record<string, string> = { tardanza: "Tardanzas", falta: "Faltas", conducta: "Conducta" };
const ESTADO_DOC: Record<string, string> = { borrador: "Borrador", firmado: "Firmado", entregado: "Entregado", anulado: "Anulado" };

interface Persona { id: string; nombres: string; apellidos: string; documento: string | null; funcion: string; sede_base_id: string; fecha_ingreso: string; email: string | null; estado: string; en_planilla: boolean; sueldo_fijo: boolean }
interface Ficha { nombre_dni: string | null; fecha_nacimiento: string | null; estado_civil: string | null; direccion: string | null; celular: string | null; entidad_bancaria: string | null; numero_cuenta: string | null; grado_instruccion: string | null; hijos_menores: boolean | null; foto_personal_url: string | null }
interface Salario { rango: string; salario_mensual_soles: number; vigente_desde: string; vigente_hasta: string | null }
interface DocLite { id: string; correlativo: string | null; tipo_causal: string; nivel: string; estado: string; creado_at: string; firmado_at: string | null }

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

  const [persona, setPersona] = useState<Persona | null>(null);
  const [ficha, setFicha] = useState<Ficha | null>(null);
  const [sede, setSede] = useState<string>("");
  const [salario, setSalario] = useState<Salario | null>(null);
  const [docs, setDocs] = useState<DocLite[]>([]);
  const [cargando, setCargando] = useState(true);
  const [err, setErr] = useState<string | null>(null);

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

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <button onClick={() => router.back()} className="mb-4 text-sm text-taupe hover:text-tinta">← Volver</button>

        {cargando ? (
          <p className="text-sm text-taupe">Cargando…</p>
        ) : err ? (
          <p className="max-w-xl rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">{err}</p>
        ) : persona && (
          <>
            {/* Cabecera */}
            <div className="mb-6 flex flex-wrap items-center gap-4">
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

            <div className="grid gap-5 lg:grid-cols-2">
              {/* Datos personales */}
              <section className="rounded-lg border p-4">
                <div className="mb-2 flex items-baseline justify-between">
                  <h2 className="font-serif text-lg">Datos personales</h2>
                  <Link href="/admin/datos-personales" className="text-xs text-tinta hover:underline">Editar →</Link>
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
              <section className="rounded-lg border p-4">
                <div className="mb-2 flex items-baseline justify-between">
                  <h2 className="font-serif text-lg">Compensación</h2>
                  <Link href="/admin/planilla" className="text-xs text-tinta hover:underline">Planilla →</Link>
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
              <section className="rounded-lg border p-4 lg:col-span-2">
                <div className="mb-2 flex items-baseline justify-between">
                  <h2 className="font-serif text-lg">Legajo disciplinario {docs.length > 0 && <span className="text-sm font-normal text-taupe">· {docs.length}</span>}</h2>
                  <Link href="/admin/disciplina" className="text-xs text-tinta hover:underline">Disciplina →</Link>
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
            <div className="mt-6 flex flex-wrap items-center gap-2 text-sm">
              <span className="py-1 text-taupe">Registro de {persona.nombres}:</span>
              <Link href={`/admin/horas?persona=${persona.id}`} className="rounded-lg border px-3 py-1 hover:bg-sand/40">Horas y tardanzas</Link>
              <Link href={`/admin/incidencias?persona=${persona.id}`} className="rounded-lg border px-3 py-1 hover:bg-sand/40">Incidencias</Link>
            </div>
          </>
        )}
      </main>
    </div>
  );
}
