"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import bcrypt from "bcryptjs";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { AdminNav } from "../nav";

const ROLES_OPCIONES = [
  { valor: "integrante", label: "Integrante" },
  { valor: "supervisor_sede", label: "Supervisor(a) de sede" },
  { valor: "lider_do", label: "Líder de Desarrollo Organizacional" },
  { valor: "admin", label: "Admin" },
] as const;

const PIN_TRIVIALES = new Set([
  "0000", "1111", "2222", "3333", "4444", "5555", "6666", "7777", "8888", "9999", "1234", "4321", "0123",
]);

function generarPin(): string {
  let pin: string;
  do {
    const n = new Uint32Array(1);
    crypto.getRandomValues(n);
    pin = String(n[0] % 10000).padStart(4, "0");
  } while (PIN_TRIVIALES.has(pin));
  return pin;
}

interface Sede {
  id: string;
  codigo: string;
}

interface Persona {
  id: string;
  nombres: string;
  apellidos: string;
  rol: string;
  estado: string;
  email: string | null;
  sede_base_id: string;
}

type Rol = "integrante" | "supervisor_sede" | "lider_do" | "admin";

interface FormPersona {
  nombres: string;
  apellidos: string;
  sedeId: string;
  rol: Rol;
  email: string;
}

const FORM_VACIO: FormPersona = { nombres: "", apellidos: "", sedeId: "", rol: "integrante", email: "" };

export default function EquipoPage() {
  const router = useRouter();
  const [sedes, setSedes] = useState<Sede[]>([]);
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [cargando, setCargando] = useState(true);
  const [mensaje, setMensaje] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);

  const [mostrandoAlta, setMostrandoAlta] = useState(false);
  const [form, setForm] = useState<FormPersona>(FORM_VACIO);
  const [editandoId, setEditandoId] = useState<string | null>(null);
  const [guardando, setGuardando] = useState(false);

  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) {
      router.replace("/admin/login");
      return;
    }
    const [{ data: sedesData }, { data: personasData }] = await Promise.all([
      supabase.from("sedes").select("id, codigo").order("codigo"),
      supabase.from("personas").select("id, nombres, apellidos, rol, estado, email, sede_base_id").order("nombres"),
    ]);
    setSedes(sedesData ?? []);
    setPersonas((personasData as Persona[]) ?? []);
    setCargando(false);
  }, [router]);

  useEffect(() => {
    void cargar();
  }, [cargar]);

  function codigoSede(id: string) {
    return sedes.find((s) => s.id === id)?.codigo ?? "?";
  }

  function avisar(tipo: "ok" | "error", texto: string) {
    setMensaje({ tipo, texto });
  }

  async function crearPersona() {
    if (!form.nombres.trim() || !form.apellidos.trim() || !form.sedeId) {
      avisar("error", "Nombres, apellidos y sede son obligatorios.");
      return;
    }
    setGuardando(true);
    const pin = generarPin();
    const pinHash = await bcrypt.hash(pin, 10);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.from("personas").insert({
      nombres: form.nombres.trim(),
      apellidos: form.apellidos.trim(),
      sede_base_id: form.sedeId,
      rol: form.rol,
      email: form.email.trim() || null,
      pin_hash: pinHash,
    });
    setGuardando(false);
    if (error) {
      avisar("error", `No se pudo crear: ${error.message}`);
      return;
    }
    setMostrandoAlta(false);
    setForm(FORM_VACIO);
    await cargar();
    avisar("ok", `${form.nombres} ${form.apellidos} agregado(a). Su PIN es ${pin} — anótalo ahora, no se vuelve a mostrar.`);
  }

  async function guardarEdicion() {
    if (!editandoId) return;
    setGuardando(true);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase
      .from("personas")
      .update({
        nombres: form.nombres.trim(),
        apellidos: form.apellidos.trim(),
        sede_base_id: form.sedeId,
        rol: form.rol,
        email: form.email.trim() || null,
      })
      .eq("id", editandoId);
    setGuardando(false);
    if (error) {
      avisar("error", `No se pudo guardar: ${error.message}`);
      return;
    }
    setEditandoId(null);
    setForm(FORM_VACIO);
    await cargar();
    avisar("ok", "Cambios guardados.");
  }

  async function cambiarEstado(p: Persona, nuevo: "activo" | "inactivo") {
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase
      .from("personas")
      .update({ estado: nuevo, fecha_estado_cambio: new Date().toISOString() })
      .eq("id", p.id);
    if (error) {
      avisar("error", `No se pudo cambiar el estado: ${error.message}`);
      return;
    }
    await cargar();
    avisar("ok", `${p.nombres} ${p.apellidos} ahora está ${nuevo === "activo" ? "activo(a)" : "inactivo(a)"}.`);
  }

  async function regenerarPin(p: Persona) {
    const pin = generarPin();
    const pinHash = await bcrypt.hash(pin, 10);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.from("personas").update({ pin_hash: pinHash }).eq("id", p.id);
    if (error) {
      avisar("error", `No se pudo regenerar el PIN: ${error.message}`);
      return;
    }
    avisar("ok", `Nuevo PIN de ${p.nombres} ${p.apellidos}: ${pin} — anótalo ahora, no se vuelve a mostrar.`);
  }

  function empezarEdicion(p: Persona) {
    setEditandoId(p.id);
    setMostrandoAlta(false);
    setForm({
      nombres: p.nombres,
      apellidos: p.apellidos,
      sedeId: p.sede_base_id,
      rol: p.rol as Rol,
      email: p.email ?? "",
    });
  }

  const formulario = (modo: "alta" | "edicion") => (
    <div className="mb-6 grid max-w-3xl gap-3 rounded-lg border bg-sand/50 p-4 sm:grid-cols-2">
      <label className="flex flex-col gap-1 text-sm">
        Nombres
        <input value={form.nombres} onChange={(e) => setForm({ ...form, nombres: e.target.value })} className="rounded-lg border px-3 py-2" />
      </label>
      <label className="flex flex-col gap-1 text-sm">
        Apellidos
        <input value={form.apellidos} onChange={(e) => setForm({ ...form, apellidos: e.target.value })} className="rounded-lg border px-3 py-2" />
      </label>
      <label className="flex flex-col gap-1 text-sm">
        Sede
        <select value={form.sedeId} onChange={(e) => setForm({ ...form, sedeId: e.target.value })} className="rounded-lg border bg-crema px-3 py-2">
          <option value="">Elegir…</option>
          {sedes.map((s) => (
            <option key={s.id} value={s.id}>{s.codigo}</option>
          ))}
        </select>
      </label>
      <label className="flex flex-col gap-1 text-sm">
        Rol
        <select value={form.rol} onChange={(e) => setForm({ ...form, rol: e.target.value as Rol })} className="rounded-lg border bg-crema px-3 py-2">
          {ROLES_OPCIONES.map((r) => (
            <option key={r.valor} value={r.valor}>{r.label}</option>
          ))}
        </select>
      </label>
      <label className="flex flex-col gap-1 text-sm sm:col-span-2">
        Correo (opcional)
        <input type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} className="rounded-lg border px-3 py-2" />
      </label>
      <div className="flex gap-3 sm:col-span-2">
        <button
          onClick={modo === "alta" ? crearPersona : guardarEdicion}
          disabled={guardando}
          className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema disabled:opacity-50"
        >
          {guardando ? "Guardando…" : modo === "alta" ? "Agregar (genera PIN)" : "Guardar cambios"}
        </button>
        <button
          onClick={() => { setMostrandoAlta(false); setEditandoId(null); setForm(FORM_VACIO); }}
          className="rounded-lg border px-4 py-2 text-sm"
        >
          Cancelar
        </button>
      </div>
    </div>
  );

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <div className="mb-4 flex items-center justify-between">
          <h1 className="font-serif text-2xl">Equipo</h1>
          {!mostrandoAlta && !editandoId && (
            <button
              onClick={() => { setMostrandoAlta(true); setForm(FORM_VACIO); setMensaje(null); }}
              className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema"
            >
              + Agregar persona
            </button>
          )}
        </div>

        {mensaje && (
          <div className={`mb-4 max-w-3xl rounded-lg px-4 py-3 text-sm ${mensaje.tipo === "ok" ? "bg-sand/40 text-tinta" : "bg-rojo/10 text-rojo"}`}>
            {mensaje.texto}
          </div>
        )}

        {mostrandoAlta && formulario("alta")}
        {editandoId && formulario("edicion")}

        {cargando ? (
          <p className="text-sm text-taupe">Cargando…</p>
        ) : (
          <div className="overflow-x-auto rounded-lg border">
            <table className="w-full text-sm">
              <thead className="bg-sand/50 text-left text-taupe">
                <tr>
                  <th className="px-4 py-2 font-normal">Nombre</th>
                  <th className="px-4 py-2 font-normal">Sede</th>
                  <th className="px-4 py-2 font-normal">Rol</th>
                  <th className="px-4 py-2 font-normal">Correo</th>
                  <th className="px-4 py-2 font-normal">Estado</th>
                  <th className="px-4 py-2 font-normal">Acciones</th>
                </tr>
              </thead>
              <tbody>
                {personas.map((p) => (
                  <tr key={p.id} className={`border-t ${p.estado === "inactivo" ? "text-taupe" : ""}`}>
                    <td className="px-4 py-2">{p.nombres} {p.apellidos}</td>
                    <td className="px-4 py-2">{codigoSede(p.sede_base_id)}</td>
                    <td className="px-4 py-2">{ROLES_OPCIONES.find((r) => r.valor === p.rol)?.label ?? p.rol}</td>
                    <td className="px-4 py-2">{p.email ?? <span className="text-taupe/50">—</span>}</td>
                    <td className="px-4 py-2">
                      <span className={`rounded-full px-2 py-0.5 text-xs ${p.estado === "activo" ? "bg-sand text-tinta" : "bg-sand text-taupe"}`}>
                        {p.estado}
                      </span>
                    </td>
                    <td className="px-4 py-2">
                      <div className="flex flex-wrap gap-2 text-xs">
                        <button onClick={() => empezarEdicion(p)} className="rounded border px-2 py-1 hover:bg-sand/50">Editar</button>
                        <button onClick={() => regenerarPin(p)} className="rounded border px-2 py-1 hover:bg-sand/50">Nuevo PIN</button>
                        {p.estado === "activo" ? (
                          <button onClick={() => cambiarEstado(p, "inactivo")} className="rounded border border-rojo/30 px-2 py-1 text-rojo hover:bg-rojo/10">Desactivar</button>
                        ) : (
                          <button onClick={() => cambiarEstado(p, "activo")} className="rounded border px-2 py-1 hover:bg-sand/50">Reactivar</button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        <p className="mt-4 max-w-2xl text-xs text-taupe">
          Al agregar una persona o regenerar un PIN, el PIN aparece una sola vez en el aviso verde —
          anótalo y entrégalo en privado. “Desactivar” no borra nada: la persona deja de aparecer en
          el terminal pero su historial se conserva.
        </p>
      </main>
    </div>
  );
}
