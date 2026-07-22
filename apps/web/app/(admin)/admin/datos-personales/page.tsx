"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { AdminNav } from "../nav";

interface Persona { id: string; nombres: string; apellidos: string; documento: string | null; sede_base_id: string; email: string | null }
interface Ficha {
  persona_id: string; nombre_dni: string | null; fecha_nacimiento: string | null; estado_civil: string | null;
  direccion: string | null; celular: string | null; entidad_bancaria: string | null; numero_cuenta: string | null;
  grado_instruccion: string | null; hijos_menores: boolean | null;
  foto_dni_url: string | null; foto_personal_url: string | null; foto_profesional_url: string | null;
}
interface Form {
  nombre_dni: string; fecha_nacimiento: string; estado_civil: string; direccion: string; celular: string;
  entidad_bancaria: string; numero_cuenta: string; grado_instruccion: string;
  hijos_menores: "" | "si" | "no";
  foto_dni_url: string; foto_personal_url: string; foto_profesional_url: string;
}

const VACIO: Form = {
  nombre_dni: "", fecha_nacimiento: "", estado_civil: "", direccion: "", celular: "",
  entidad_bancaria: "", numero_cuenta: "", grado_instruccion: "", hijos_menores: "",
  foto_dni_url: "", foto_personal_url: "", foto_profesional_url: "",
};

export default function DatosPersonalesPage() {
  const router = useRouter();
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;
  const puede = rol === "admin" || rol === "lider_do" || rol === "supervisor_sede";

  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [sedes, setSedes] = useState<Map<string, string>>(new Map());
  const [fichas, setFichas] = useState<Map<string, Ficha>>(new Map());
  const [sel, setSel] = useState<string>("");
  const [form, setForm] = useState<Form>(VACIO);
  const [cargando, setCargando] = useState(true);
  const [guardando, setGuardando] = useState(false);
  const [msg, setMsg] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);
  const [q, setQ] = useState("");
  const [soloSinFicha, setSoloSinFicha] = useState(false);
  const fichaRef = useRef<HTMLDivElement>(null);

  const cargar = useCallback(async () => {
    setCargando(true);
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    const [{ data: p }, { data: s }, { data: dp }] = await Promise.all([
      supabase.from("personas").select("id, nombres, apellidos, documento, sede_base_id, email").eq("estado", "activo").order("nombres"),
      supabase.from("sedes").select("id, codigo"),
      supabase.from("datos_personales").select("persona_id, nombre_dni, fecha_nacimiento, estado_civil, direccion, celular, entidad_bancaria, numero_cuenta, grado_instruccion, hijos_menores, foto_dni_url, foto_personal_url, foto_profesional_url"),
    ]);
    setPersonas((p as Persona[]) ?? []);
    setSedes(new Map(((s as Array<{ id: string; codigo: string }>) ?? []).map((x) => [x.id, x.codigo])));
    setFichas(new Map(((dp as Ficha[]) ?? []).map((x) => [x.persona_id, x])));
    setCargando(false);
  }, [supabase, router]);

  useEffect(() => { void cargar(); }, [cargar]);

  function seleccionar(id: string) {
    setSel(id); setMsg(null);
    // En móvil la ficha queda debajo de la lista: la traemos a la vista
    // (respetando la preferencia de "reducir movimiento" del sistema).
    if (typeof window !== "undefined" && window.innerWidth < 768) {
      const suave = !window.matchMedia("(prefers-reduced-motion: reduce)").matches;
      setTimeout(() => fichaRef.current?.scrollIntoView({ behavior: suave ? "smooth" : "auto", block: "start" }), 60);
    }
    const f = fichas.get(id);
    setForm(f ? {
      nombre_dni: f.nombre_dni ?? "", fecha_nacimiento: f.fecha_nacimiento ?? "", estado_civil: f.estado_civil ?? "",
      direccion: f.direccion ?? "", celular: f.celular ?? "", entidad_bancaria: f.entidad_bancaria ?? "",
      numero_cuenta: f.numero_cuenta ?? "", grado_instruccion: f.grado_instruccion ?? "",
      hijos_menores: f.hijos_menores === true ? "si" : f.hijos_menores === false ? "no" : "",
      foto_dni_url: f.foto_dni_url ?? "", foto_personal_url: f.foto_personal_url ?? "", foto_profesional_url: f.foto_profesional_url ?? "",
    } : { ...VACIO });
  }

  async function guardar() {
    if (!sel) return;
    setGuardando(true); setMsg(null);
    const { error } = await supabase.rpc("fn_set_datos_personales", {
      p_persona_id: sel,
      p_nombre_dni: form.nombre_dni.trim() || null,
      p_fecha_nacimiento: form.fecha_nacimiento || null,
      p_estado_civil: form.estado_civil.trim() || null,
      p_direccion: form.direccion.trim() || null,
      p_celular: form.celular.trim() || null,
      p_entidad_bancaria: form.entidad_bancaria.trim() || null,
      p_numero_cuenta: form.numero_cuenta.trim() || null,
      p_grado_instruccion: form.grado_instruccion.trim() || null,
      p_hijos_menores: form.hijos_menores === "" ? null : form.hijos_menores === "si",
      p_foto_dni_url: form.foto_dni_url.trim() || null,
      p_foto_personal_url: form.foto_personal_url.trim() || null,
      p_foto_profesional_url: form.foto_profesional_url.trim() || null,
    });
    setGuardando(false);
    if (error) { setMsg({ tipo: "error", texto: error.message }); return; }
    await cargar();
    setMsg({ tipo: "ok", texto: "Ficha guardada." });
  }

  const personaSel = personas.find((p) => p.id === sel) ?? null;
  const lista = personas.filter((p) =>
    `${p.nombres} ${p.apellidos}`.toLowerCase().includes(q.trim().toLowerCase())
    && (!soloSinFicha || !fichas.has(p.id)));
  const sinFicha = personas.filter((p) => !fichas.has(p.id)).length;

  if (rol !== null && !puede) {
    return (
      <div className="flex min-h-screen flex-col">
        <AdminNav />
        <main className="flex flex-1 items-center justify-center p-6">
          <p className="max-w-md text-center text-taupe">No tienes permiso para ver datos personales.</p>
        </main>
      </div>
    );
  }

  function campo(label: string, key: keyof Form, tipo: "text" | "date" = "text") {
    return (
      <label className="flex flex-col gap-1 text-sm">
        <span className="text-taupe">{label}</span>
        <input type={tipo} value={form[key]} onChange={(e) => setForm((f) => ({ ...f, [key]: e.target.value }))}
          className="rounded-lg border px-3 py-2" />
      </label>
    );
  }
  function campoFoto(label: string, key: keyof Form) {
    return (
      <label className="flex flex-col gap-1 text-sm">
        <span className="text-taupe">{label} {form[key] && <a href={form[key] as string} target="_blank" rel="noreferrer" className="text-tinta underline">ver</a>}</span>
        <input value={form[key]} onChange={(e) => setForm((f) => ({ ...f, [key]: e.target.value }))}
          className="rounded-lg border px-3 py-2" placeholder="Enlace de Drive" />
      </label>
    );
  }

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <h1 className="mb-1 font-serif text-2xl">Datos personales</h1>
        <p className="mb-5 max-w-2xl text-sm text-taupe">
          Ficha personal de cada integrante: DNI, contacto, banco, nacimiento y documentos.
          Datos sensibles — visibles solo para Desarrollo Organizacional, la encargada de tu sede y cada persona sobre sí misma.
        </p>

        {msg && (
          <div className={`mb-4 max-w-2xl rounded-lg px-4 py-3 text-sm ${msg.tipo === "ok" ? "bg-sand/40 text-tinta" : "bg-rojo/10 text-rojo"}`}>
            {msg.texto}
          </div>
        )}

        <div className="grid gap-6 md:grid-cols-[260px_1fr]">
          {/* Lista de personas */}
          <div className="overflow-hidden rounded-lg border">
            <div className="border-b bg-sand/50 px-3 py-2">
              <div className="flex items-baseline justify-between">
                <h2 className="text-sm font-medium">Equipo {personas.length > 0 && <span className="font-normal text-taupe">· {personas.length}</span>}</h2>
                {sinFicha > 0 && (
                  <button onClick={() => setSoloSinFicha((v) => !v)} aria-pressed={soloSinFicha}
                    className={`rounded-full px-2 py-0.5 text-xs transition-colors ${soloSinFicha ? "bg-amber-200 text-amber-900" : "text-amber-800 hover:bg-amber-100"}`}>
                    {sinFicha} sin ficha
                  </button>
                )}
              </div>
              <div className="relative mt-2">
                <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Buscar por nombre…"
                  className="w-full rounded-lg border bg-crema px-3 py-1.5 pr-8 text-sm" />
                {q && (
                  <button onClick={() => setQ("")} aria-label="Limpiar búsqueda"
                    className="absolute right-2 top-1/2 -translate-y-1/2 leading-none text-taupe hover:text-tinta">×</button>
                )}
              </div>
            </div>
            {cargando ? (
              <p className="px-3 py-4 text-sm text-taupe">Cargando…</p>
            ) : lista.length === 0 ? (
              <p className="px-3 py-4 text-sm text-taupe">Nadie coincide con “{q}”.</p>
            ) : (
              <ul className="max-h-[70vh] divide-y overflow-y-auto">
                {lista.map((p) => (
                  <li key={p.id}>
                    <button onClick={() => seleccionar(p.id)}
                      className={`flex w-full items-center justify-between px-3 py-2 text-left text-sm ${sel === p.id ? "bg-sand/60 font-medium text-tinta" : "hover:bg-sand/30"}`}>
                      <span>{p.nombres} {p.apellidos}</span>
                      <span className="flex items-center gap-1 text-xs text-taupe">
                        {sedes.get(p.sede_base_id)}
                        {!fichas.has(p.id) && <span className="rounded-full bg-amber-100 px-1.5 text-amber-800">sin ficha</span>}
                      </span>
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>

          {/* Ficha */}
          <div ref={fichaRef} className="scroll-mt-4 rounded-lg border p-4">
            {!personaSel ? (
              <p className="text-sm text-taupe">Elige a alguien de la lista para ver o editar su ficha.</p>
            ) : (
              <>
                <div className="mb-3 flex flex-wrap items-baseline justify-between gap-x-3">
                  <h2 className="font-serif text-lg">{personaSel.nombres} {personaSel.apellidos}</h2>
                  <div className="flex items-center gap-3 text-xs">
                    <span className="text-taupe">DNI: {personaSel.documento ?? "—"} · {sedes.get(personaSel.sede_base_id)}</span>
                    <button onClick={() => router.push(`/admin/personas/${personaSel.id}`)} className="text-tinta hover:underline">Ver perfil →</button>
                  </div>
                </div>
                <div className="space-y-4">
                  <section>
                    <p className="mb-2 text-[11px] uppercase tracking-wider text-taupe/70">Identidad</p>
                    <div className="grid gap-3 sm:grid-cols-2">
                      {campo("Nombre completo (como en el DNI)", "nombre_dni")}
                      {campo("Fecha de nacimiento", "fecha_nacimiento", "date")}
                      {campo("Estado civil", "estado_civil")}
                      {campo("Grado de instrucción", "grado_instruccion")}
                      <label className="flex flex-col gap-1 text-sm">
                        <span className="text-taupe">¿Hijos menores a cargo?</span>
                        <select value={form.hijos_menores} onChange={(e) => setForm((f) => ({ ...f, hijos_menores: e.target.value as Form["hijos_menores"] }))}
                          className="rounded-lg border bg-crema px-3 py-2">
                          <option value="">—</option>
                          <option value="si">Sí</option>
                          <option value="no">No</option>
                        </select>
                      </label>
                    </div>
                  </section>
                  <section>
                    <p className="mb-2 text-[11px] uppercase tracking-wider text-taupe/70">Contacto</p>
                    <div className="grid gap-3 sm:grid-cols-2">
                      {campo("Celular", "celular")}
                      <label className="flex flex-col gap-1 text-sm sm:col-span-2">
                        <span className="text-taupe">Dirección</span>
                        <input value={form.direccion} onChange={(e) => setForm((f) => ({ ...f, direccion: e.target.value }))} className="rounded-lg border px-3 py-2" />
                      </label>
                    </div>
                  </section>
                  <section>
                    <p className="mb-2 text-[11px] uppercase tracking-wider text-taupe/70">Banco</p>
                    <div className="grid gap-3 sm:grid-cols-2">
                      {campo("Entidad bancaria", "entidad_bancaria")}
                      {campo("N.° de cuenta", "numero_cuenta")}
                    </div>
                  </section>
                  <section>
                    <p className="mb-2 text-[11px] uppercase tracking-wider text-taupe/70">Documentos</p>
                    <div className="grid gap-3 sm:grid-cols-2">
                      {campoFoto("Foto DNI", "foto_dni_url")}
                      {campoFoto("Foto personal", "foto_personal_url")}
                      {campoFoto("Foto profesional", "foto_profesional_url")}
                    </div>
                  </section>
                </div>
                <button onClick={guardar} disabled={guardando}
                  className="mt-4 rounded-lg bg-tinta px-5 py-2 text-sm font-medium text-crema disabled:opacity-50">
                  {guardando ? "Guardando…" : "Guardar ficha"}
                </button>
              </>
            )}
          </div>
        </div>
      </main>
    </div>
  );
}
