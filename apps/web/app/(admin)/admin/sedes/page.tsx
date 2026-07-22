"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { AdminNav } from "../nav";
import { useRolActual } from "@/lib/admin/use-rol";

interface Sede { id: string; codigo: string; nombre: string; activa: boolean }
interface FormSede { codigo: string; nombre: string }
const FORM_VACIO: FormSede = { codigo: "", nombre: "" };
const CODIGO_OK = /^[A-Z0-9]{2,8}$/;

export default function SedesPage() {
  const router = useRouter();
  const rol = useRolActual();
  const puedeGestionar = rol === "admin" || rol === "lider_do";

  const [sedes, setSedes] = useState<Sede[]>([]);
  const [cargando, setCargando] = useState(true);
  const [cargaError, setCargaError] = useState<string | null>(null);
  const [mensaje, setMensaje] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);

  const [mostrandoAlta, setMostrandoAlta] = useState(false);
  const [editandoCodigo, setEditandoCodigo] = useState<string | null>(null);
  const [form, setForm] = useState<FormSede>(FORM_VACIO);
  const [guardando, setGuardando] = useState(false);

  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    const { data, error } = await supabase.from("sedes").select("id, codigo, nombre, activa").order("codigo");
    setSedes((data as Sede[]) ?? []);
    setCargaError(error ? error.message : null);
    setCargando(false);
  }, [router]);

  useEffect(() => { void cargar(); }, [cargar]);

  const edicionHabilitada = !cargaError;
  const avisar = (tipo: "ok" | "error", texto: string) => setMensaje({ tipo, texto });

  function empezarAlta() { setMostrandoAlta(true); setEditandoCodigo(null); setForm(FORM_VACIO); setMensaje(null); }
  function empezarEdicion(s: Sede) { setEditandoCodigo(s.codigo); setMostrandoAlta(false); setForm({ codigo: s.codigo, nombre: s.nombre }); setMensaje(null); }
  function cancelarForm() { setMostrandoAlta(false); setEditandoCodigo(null); setForm(FORM_VACIO); }

  async function guardarSede() {
    const nombre = form.nombre.trim();
    const codigo = editandoCodigo ?? form.codigo.trim().toUpperCase();
    if (!nombre) { avisar("error", "El nombre es obligatorio."); return; }
    if (!editandoCodigo && !CODIGO_OK.test(codigo)) {
      avisar("error", "El código debe tener 2 a 8 letras o números, sin espacios (ej. LIMT).");
      return;
    }
    // En ALTA, un código ya existente pisaría esa sede en silencio (el guardado es upsert).
    if (!editandoCodigo && sedes.some((s) => s.codigo === codigo)) {
      avisar("error", `Ya existe una sede con el código “${codigo}”. Para modificarla, usa “Editar” en su fila.`);
      return;
    }
    const eraEdicion = editandoCodigo !== null;
    setGuardando(true);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_guardar_sede", { p_codigo: codigo, p_nombre: nombre });
    setGuardando(false);
    if (error) { avisar("error", `No se pudo guardar: ${error.message}`); return; }
    cancelarForm();
    await cargar();
    avisar("ok", eraEdicion ? "Cambios guardados." : `Sede “${nombre}” (${codigo}) creada.`);
  }

  async function cambiarActiva(s: Sede, activa: boolean) {
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_sede_activa", { p_codigo: s.codigo, p_activa: activa });
    if (error) { avisar("error", `No se pudo ${activa ? "reactivar" : "desactivar"} la sede: ${error.message}`); return; }
    await cargar();
    avisar("ok", activa
      ? `“${s.nombre}” reactivada: vuelve a ofrecerse al asignar personas.`
      : `“${s.nombre}” desactivada. Quien ya está asignado ahí lo conserva; solo deja de ofrecerse para nuevas asignaciones.`);
  }

  const formulario = (modo: "alta" | "edicion") => (
    <div className="mb-6 grid max-w-2xl gap-3 rounded-lg border bg-sand/50 p-4 sm:grid-cols-2">
      <label className="flex flex-col gap-1 text-sm">
        Código
        {modo === "alta" ? (
          <>
            <input
              value={form.codigo}
              onChange={(e) => setForm({ ...form, codigo: e.target.value.toUpperCase().replace(/[^A-Z0-9]/g, "") })}
              placeholder="ej. LIMT"
              maxLength={8}
              className="rounded-lg border px-3 py-2 font-mono uppercase"
            />
            <span className="text-xs text-taupe/70">Etiqueta corta que verás en tablas (2 a 8 letras/números). No cambia después.</span>
          </>
        ) : (
          <>
            <input value={form.codigo} disabled className="rounded-lg border bg-crema px-3 py-2 font-mono text-taupe" />
            <span className="text-xs text-taupe/70">Fijo — cambiar el nombre no cambia el código.</span>
          </>
        )}
      </label>
      <label className="flex flex-col gap-1 text-sm">
        Nombre
        <input
          value={form.nombre}
          onChange={(e) => setForm({ ...form, nombre: e.target.value })}
          placeholder="ej. Taller Lima"
          className="rounded-lg border px-3 py-2"
        />
      </label>
      <div className="flex items-end gap-3 sm:col-span-2">
        <button onClick={guardarSede} disabled={guardando} className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema disabled:opacity-50">
          {guardando ? "Guardando…" : modo === "alta" ? "Agregar sede" : "Guardar cambios"}
        </button>
        <button onClick={cancelarForm} className="rounded-lg border px-4 py-2 text-sm">Cancelar</button>
      </div>
    </div>
  );

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <div className="mb-4 flex items-center justify-between">
          <h1 className="font-serif text-2xl">Sedes</h1>
          {puedeGestionar && edicionHabilitada && !mostrandoAlta && !editandoCodigo && (
            <button onClick={empezarAlta} className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema">+ Agregar sede</button>
          )}
        </div>

        {rol === null ? (
          <p className="text-sm text-taupe">Cargando…</p>
        ) : !puedeGestionar ? (
          <div className="max-w-2xl rounded-lg bg-ambar/15 px-4 py-3 text-sm text-ambar">
            Solo administradores y líderes pueden gestionar sedes.
          </div>
        ) : (
          <>
            {mensaje && (
              <div className={`mb-4 max-w-3xl rounded-lg px-4 py-3 text-sm ${mensaje.tipo === "ok" ? "bg-sand/40 text-tinta" : "bg-rojo/10 text-rojo"}`}>
                {mensaje.texto}
              </div>
            )}
            {cargaError && (
              <div className="mb-4 max-w-3xl rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
                No se pudieron cargar las sedes: {cargaError}.{" "}
                <button onClick={() => void cargar()} className="font-medium underline">Reintentar</button>
              </div>
            )}

            {mostrandoAlta && formulario("alta")}
            {editandoCodigo && formulario("edicion")}

            {cargando ? (
              <p className="text-sm text-taupe">Cargando…</p>
            ) : (
              <div className="overflow-x-auto rounded-lg border">
                <table className="w-full text-sm">
                  <thead className="bg-sand/50 text-left text-taupe">
                    <tr>
                      <th className="px-4 py-2 font-normal">Nombre</th>
                      <th className="px-4 py-2 font-normal">Código</th>
                      <th className="px-4 py-2 font-normal">Estado</th>
                      <th className="px-4 py-2 font-normal">Acciones</th>
                    </tr>
                  </thead>
                  <tbody>
                    {sedes.map((s) => (
                      <tr key={s.codigo} className={`border-t ${s.activa ? "" : "text-taupe"}`}>
                        <td className="px-4 py-2">{s.nombre}</td>
                        <td className="px-4 py-2 font-mono text-xs text-taupe">{s.codigo}</td>
                        <td className="px-4 py-2">
                          <span className={`rounded-full px-2 py-0.5 text-xs ${s.activa ? "bg-sand text-tinta" : "bg-sand text-taupe"}`}>
                            {s.activa ? "activa" : "inactiva"}
                          </span>
                        </td>
                        <td className="px-4 py-2">
                          {edicionHabilitada && (
                            <div className="flex flex-wrap gap-2 text-xs">
                              <button onClick={() => empezarEdicion(s)} className="rounded border px-2 py-1 hover:bg-sand/50">Editar</button>
                              {s.activa ? (
                                <button onClick={() => cambiarActiva(s, false)} className="rounded border border-rojo/30 px-2 py-1 text-rojo hover:bg-rojo/10">Desactivar</button>
                              ) : (
                                <button onClick={() => cambiarActiva(s, true)} className="rounded border px-2 py-1 hover:bg-sand/50">Reactivar</button>
                              )}
                            </div>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}

            <p className="mt-4 max-w-2xl text-xs text-taupe">
              Cada <span className="font-medium">terminal</span> muestra a la gente de <span className="font-medium">su</span> sede
              (más quien esté marcado como “visible en todas las sedes” en Equipo). Por eso dos locales distintos —una tienda y un
              taller— van como dos sedes, cada una con su terminal. Las sedes <span className="font-medium">no se borran</span>:
              se desactivan, y quien ya está asignado ahí lo conserva.
            </p>
          </>
        )}
      </main>
    </div>
  );
}
