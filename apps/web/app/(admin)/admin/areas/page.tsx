"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { AdminNav } from "../nav";
import { Cargando } from "@/components/cargando";
import { useRolActual } from "@/lib/admin/use-rol";
import { type Area, AREA_DEFAULT, parseAreas, slugDeNombre } from "@/lib/areas";

interface FormArea {
  nombre: string;
  operativa: boolean;
  orden: string; // vacío = no enviar p_orden (el server decide)
}

const FORM_VACIO: FormArea = { nombre: "", operativa: false, orden: "" };

export default function AreasPage() {
  const router = useRouter();
  const rol = useRolActual();
  const puedeGestionar = rol === "admin" || rol === "lider_do";

  const [areas, setAreas] = useState<Area[]>([]);
  const [cargando, setCargando] = useState(true);
  // Si fn_areas falla mostramos el respaldo local, pero NO dejamos editar:
  // guardar sobre datos de respaldo pisaría los valores reales del servidor.
  const [cargaError, setCargaError] = useState<string | null>(null);
  const [mensaje, setMensaje] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);

  const [mostrandoAlta, setMostrandoAlta] = useState(false);
  const [editandoCodigo, setEditandoCodigo] = useState<string | null>(null);
  const [form, setForm] = useState<FormArea>(FORM_VACIO);
  const [guardando, setGuardando] = useState(false);

  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) {
      router.replace("/admin/login");
      return;
    }
    // La tabla `areas` NUNCA se lee por REST (.from) — el schema cache de
    // PostgREST está trabado; SOLO se lee por la RPC fn_areas.
    const { data, error } = await supabase.rpc("fn_areas");
    setAreas(parseAreas(data, error));
    setCargaError(error ? error.message : null);
    setCargando(false);
  }, [router]);

  useEffect(() => {
    void cargar();
  }, [cargar]);

  const edicionHabilitada = !cargaError;

  function avisar(tipo: "ok" | "error", texto: string) {
    setMensaje({ tipo, texto });
  }

  function empezarAlta() {
    setMostrandoAlta(true);
    setEditandoCodigo(null);
    setForm(FORM_VACIO);
    setMensaje(null);
  }

  function empezarEdicion(a: Area) {
    setEditandoCodigo(a.codigo);
    setMostrandoAlta(false);
    setForm({ nombre: a.nombre, operativa: a.operativa, orden: String(a.orden) });
    setMensaje(null);
  }

  function cancelarForm() {
    setMostrandoAlta(false);
    setEditandoCodigo(null);
    setForm(FORM_VACIO);
  }

  async function guardarArea() {
    const nombre = form.nombre.trim();
    if (!nombre) {
      avisar("error", "El nombre es obligatorio.");
      return;
    }
    // En edición el código es FIJO: cambiar el nombre NO cambia el código.
    const codigo = editandoCodigo ?? slugDeNombre(nombre);
    if (!codigo) {
      avisar("error", "El nombre debe contener al menos una letra o número (para derivar el código).");
      return;
    }
    // En ALTA, un código ya existente pisaría esa área en silencio (el guardado
    // del servidor es upsert). Se bloquea: para modificarla está "Editar".
    if (editandoCodigo === null && areas.some((a) => a.codigo === codigo)) {
      avisar("error", `Ya existe un área con el código “${codigo}”. Si quieres modificarla, usa “Editar” en su fila.`);
      return;
    }
    let orden: number | undefined;
    if (form.orden.trim() !== "") {
      orden = Number(form.orden);
      if (!Number.isInteger(orden) || orden < 0) {
        avisar("error", "El orden debe ser un número entero (0 o más).");
        return;
      }
    }
    const eraEdicion = editandoCodigo !== null;
    setGuardando(true);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_guardar_area", {
      p_codigo: codigo,
      p_nombre: nombre,
      p_operativa: form.operativa,
      p_orden: orden,
    });
    setGuardando(false);
    if (error) {
      avisar("error", `No se pudo guardar: ${error.message}`);
      return;
    }
    cancelarForm();
    await cargar();
    avisar("ok", eraEdicion ? "Cambios guardados." : `Área “${nombre}” creada.`);
  }

  async function cambiarActiva(a: Area, activa: boolean) {
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_area_activa", { p_codigo: a.codigo, p_activa: activa });
    if (error) {
      avisar("error", `No se pudo ${activa ? "reactivar" : "desactivar"} el área: ${error.message}`);
      return;
    }
    await cargar();
    avisar(
      "ok",
      activa
        ? `“${a.nombre}” reactivada: vuelve a ofrecerse al asignar áreas.`
        : `“${a.nombre}” desactivada. Quien ya la tiene asignada la conserva; solo deja de ofrecerse para nuevas asignaciones.`,
    );
  }

  const formulario = (modo: "alta" | "edicion") => {
    const codigo = modo === "alta" ? slugDeNombre(form.nombre) : editandoCodigo ?? "";
    return (
      <div className="mb-6 grid max-w-2xl gap-3 rounded-2xl border border-sand bg-papel p-5 sm:grid-cols-2">
        <label className="flex flex-col gap-1 text-sm sm:col-span-2">
          Nombre
          <input
            value={form.nombre}
            onChange={(e) => setForm({ ...form, nombre: e.target.value })}
            placeholder="ej. Logística y envíos"
            className="rounded-lg border px-3 py-2"
          />
          <span className="text-xs text-taupe/70">
            Código: <span className="font-mono">{codigo || "—"}</span>{" "}
            {modo === "alta"
              ? "(se deriva del nombre; no editable)"
              : "(fijo — cambiar el nombre no cambia el código)"}
          </span>
        </label>
        <label className="flex items-center gap-2 text-sm sm:col-span-2">
          <input
            type="checkbox"
            checked={form.operativa}
            onChange={(e) => setForm({ ...form, operativa: e.target.checked })}
            className="h-4 w-4 rounded border"
          />
          Es operativa de sede (cuenta para la cobertura de tienda)
        </label>
        <label className="flex flex-col gap-1 text-sm">
          Orden (opcional)
          <input
            type="number"
            min="0"
            step="1"
            value={form.orden}
            onChange={(e) => setForm({ ...form, orden: e.target.value })}
            className="rounded-lg border px-3 py-2"
          />
        </label>
        <div className="flex items-end gap-3">
          <button
            onClick={guardarArea}
            disabled={guardando}
            className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema disabled:opacity-50"
          >
            {guardando ? "Guardando…" : modo === "alta" ? "Agregar área" : "Guardar cambios"}
          </button>
          <button onClick={cancelarForm} className="rounded-lg border px-4 py-2 text-sm">
            Cancelar
          </button>
        </div>
      </div>
    );
  };

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <div className="mb-4 flex items-center justify-between">
          <h1 className="font-serif text-2xl">Áreas</h1>
          {puedeGestionar && edicionHabilitada && !mostrandoAlta && !editandoCodigo && (
            <button onClick={empezarAlta} className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema">
              + Agregar área
            </button>
          )}
        </div>

        {rol === null ? (
          <Cargando />
        ) : !puedeGestionar ? (
          <div className="max-w-2xl rounded-lg bg-ambar/15 px-4 py-3 text-sm text-ambar">
            Solo administradores y líderes pueden gestionar áreas.
          </div>
        ) : (
          <>
            {mensaje && (
              <div
                className={`mb-4 max-w-3xl rounded-lg px-4 py-3 text-sm ${
                  mensaje.tipo === "ok" ? "bg-sand/40 text-tinta" : "bg-rojo/10 text-rojo"
                }`}
              >
                {mensaje.texto}
              </div>
            )}

            {cargaError && (
              <div className="mb-4 max-w-3xl rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
                No se pudo cargar el catálogo desde el servidor: {cargaError}. Se muestra el respaldo
                local y la edición queda deshabilitada (para no pisar los datos reales).{" "}
                <button onClick={() => void cargar()} className="font-medium underline">
                  Reintentar
                </button>
              </div>
            )}

            {mostrandoAlta && formulario("alta")}
            {editandoCodigo && formulario("edicion")}

            {cargando ? (
              <Cargando />
            ) : (
              <div className="overflow-x-auto rounded-2xl border border-sand bg-papel">
                <table className="w-full text-sm">
                  <thead className="bg-sand/70 text-left text-taupe">
                    <tr>
                      <th className="px-4 py-2 font-normal">Nombre</th>
                      <th className="px-4 py-2 font-normal">Código</th>
                      <th className="px-4 py-2 font-normal">Operativa de sede</th>
                      <th className="px-4 py-2 font-normal">Orden</th>
                      <th className="px-4 py-2 font-normal">Estado</th>
                      <th className="px-4 py-2 font-normal">Acciones</th>
                    </tr>
                  </thead>
                  <tbody>
                    {areas.map((a) => (
                      <tr key={a.codigo} className={`border-t ${a.activa ? "" : "text-taupe"}`}>
                        <td className="px-4 py-2">
                          {a.nombre}
                          {a.codigo === AREA_DEFAULT && (
                            <span className="ml-2 text-xs text-taupe/60">(área del sistema)</span>
                          )}
                        </td>
                        <td className="px-4 py-2 font-mono text-xs text-taupe">{a.codigo}</td>
                        <td className="px-4 py-2">{a.operativa ? "✓" : <span className="text-taupe/50">—</span>}</td>
                        <td className="px-4 py-2">{a.orden}</td>
                        <td className="px-4 py-2">
                          <span className={`rounded-full px-2 py-0.5 text-xs ${a.activa ? "bg-sand text-tinta" : "bg-sand text-taupe"}`}>
                            {a.activa ? "activa" : "inactiva"}
                          </span>
                        </td>
                        <td className="px-4 py-2">
                          {edicionHabilitada && (
                            <div className="flex flex-wrap gap-2 text-xs">
                              <button onClick={() => empezarEdicion(a)} className="rounded border px-2 py-1 hover:bg-sand/50">
                                Editar
                              </button>
                              {a.activa ? (
                                // 'calidad_servicio' no se puede desactivar (el server además lo bloquea).
                                a.codigo !== AREA_DEFAULT && (
                                  <button
                                    onClick={() => cambiarActiva(a, false)}
                                    className="rounded border border-rojo/30 px-2 py-1 text-rojo hover:bg-rojo/10"
                                  >
                                    Desactivar
                                  </button>
                                )
                              ) : (
                                <button onClick={() => cambiarActiva(a, true)} className="rounded border px-2 py-1 hover:bg-sand/50">
                                  Reactivar
                                </button>
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
              Las áreas <span className="font-medium">operativas de sede</span> son las que cuentan para
              la cobertura de tienda en Turnos. Desactivar un área no le quita nada a nadie: quien ya la
              tiene asignada la conserva; solo deja de ofrecerse para nuevas asignaciones.
            </p>
          </>
        )}
      </main>
    </div>
  );
}
