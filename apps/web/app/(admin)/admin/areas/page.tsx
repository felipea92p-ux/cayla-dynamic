"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Cargando } from "@/components/cargando";
import { Boton } from "@/components/ui/boton";
import { Campo, CampoCasilla } from "@/components/ui/campo";
import { Insignia } from "@/components/ui/insignia";
import { Fila, Tabla, TablaEncabezado, Th } from "@/components/ui/tabla";
import { useRolActual } from "@/lib/admin/use-rol";
import { type Area, AREA_DEFAULT, parseAreas, slugDeNombre } from "@/lib/areas";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { puedeGestionarCatalogos } from "@cayla-dynamic/shared";
import { useToast } from "@/components/toast";

interface FormArea {
  nombre: string;
  operativa: boolean;
  orden: string; // vacío = no enviar p_orden (el server decide)
}

const FORM_VACIO: FormArea = { nombre: "", operativa: false, orden: "" };

export default function AreasPage() {
  const router = useRouter();
  const rol = useRolActual();
  const puedeGestionar = puedeGestionarCatalogos(rol);
  const { avisar } = useToast();

  const [areas, setAreas] = useState<Area[]>([]);
  const [cargando, setCargando] = useState(true);
  // Si fn_areas falla mostramos el respaldo local, pero NO dejamos editar:
  // guardar sobre datos de respaldo pisaría los valores reales del servidor.
  const [cargaError, setCargaError] = useState<string | null>(null);

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

  function empezarAlta() {
    setMostrandoAlta(true);
    setEditandoCodigo(null);
    setForm(FORM_VACIO);
  }

  function empezarEdicion(a: Area) {
    setEditandoCodigo(a.codigo);
    setMostrandoAlta(false);
    setForm({ nombre: a.nombre, operativa: a.operativa, orden: String(a.orden) });
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
      avisar("error", mensajeDeError(error, "guardar"));
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
      avisar("error", mensajeDeError(error));
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
        <div className="sm:col-span-2">
          <Campo
            etiqueta="Nombre"
            value={form.nombre}
            onChange={(e) => setForm({ ...form, nombre: e.target.value })}
            placeholder="ej. Logística y envíos"
          />
          <span className="mt-1 block text-xs text-taupe">
            Código: <span className="font-mono">{codigo || "—"}</span>{" "}
            {modo === "alta"
              ? "(se deriva del nombre; no editable)"
              : "(fijo — cambiar el nombre no cambia el código)"}
          </span>
        </div>
        <div className="sm:col-span-2">
          <CampoCasilla
            etiqueta="Es operativa de sede (cuenta para la cobertura de tienda)"
            checked={form.operativa}
            onChange={(e) => setForm({ ...form, operativa: e.target.checked })}
          />
        </div>
        <Campo
          etiqueta="Orden (opcional)"
          type="number"
          min="0"
          step="1"
          value={form.orden}
          onChange={(e) => setForm({ ...form, orden: e.target.value })}
        />
        <div className="flex items-end gap-3">
          <Boton variante="primario" onClick={guardarArea} disabled={guardando}>
            {guardando ? "Guardando…" : modo === "alta" ? "Agregar área" : "Guardar cambios"}
          </Boton>
          <Boton variante="secundario" onClick={cancelarForm}>Cancelar</Boton>
        </div>
      </div>
    );
  };

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6">
        <div className="mb-4 flex items-center justify-between">
          <h1 className="font-serif text-2xl">Áreas</h1>
          {puedeGestionar && edicionHabilitada && !mostrandoAlta && !editandoCodigo && (
            <Boton variante="primario" onClick={empezarAlta}>+ Agregar área</Boton>
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
            {cargaError && (
              <div className="mb-4 max-w-3xl rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo-profundo">
                No se pudo cargar el catálogo desde el servidor: {cargaError}. Se muestra el respaldo
                local y la edición queda deshabilitada (para no pisar los datos reales).{" "}
                <Boton variante="enlace" onClick={() => void cargar()}>Reintentar</Boton>
              </div>
            )}

            {mostrandoAlta && formulario("alta")}
            {editandoCodigo && formulario("edicion")}

            {cargando ? (
              <Cargando />
            ) : (
              <Tabla>
                <TablaEncabezado>
                  <Th>Nombre</Th>
                  <Th>Código</Th>
                  <Th>Operativa de sede</Th>
                  <Th>Orden</Th>
                  <Th>Estado</Th>
                  <Th>Acciones</Th>
                </TablaEncabezado>
                <tbody>
                  {areas.map((a) => (
                    <Fila key={a.codigo} className={!a.activa ? "text-taupe" : undefined}>
                      <td className="px-4 py-2">
                        {a.nombre}
                        {a.codigo === AREA_DEFAULT && (
                          <span className="ml-2 text-xs text-taupe">(área del sistema)</span>
                        )}
                      </td>
                      <td className="px-4 py-2 font-mono text-xs text-taupe">{a.codigo}</td>
                      <td className="px-4 py-2">{a.operativa ? "✓" : <span className="text-taupe">—</span>}</td>
                      <td className="px-4 py-2">{a.orden}</td>
                      <td className="px-4 py-2">
                        <Insignia atenuada={!a.activa}>{a.activa ? "activa" : "inactiva"}</Insignia>
                      </td>
                      <td className="px-4 py-2">
                        {edicionHabilitada && (
                          <div className="flex flex-wrap gap-2">
                            <Boton variante="secundario" tamano="sm" onClick={() => empezarEdicion(a)}>Editar</Boton>
                            {a.activa ? (
                              // 'calidad_servicio' no se puede desactivar (el server además lo bloquea).
                              a.codigo !== AREA_DEFAULT && (
                                <Boton variante="peligro" tamano="sm" onClick={() => cambiarActiva(a, false)}>Desactivar</Boton>
                              )
                            ) : (
                              <Boton variante="secundario" tamano="sm" onClick={() => cambiarActiva(a, true)}>Reactivar</Boton>
                            )}
                          </div>
                        )}
                      </td>
                    </Fila>
                  ))}
                </tbody>
              </Tabla>
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
