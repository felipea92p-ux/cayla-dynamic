"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { AdminNav } from "../nav";
import { Cargando } from "@/components/cargando";
import { Boton } from "@/components/ui/boton";
import { Insignia } from "@/components/ui/insignia";
import { Tabla, TablaEncabezado, Th } from "@/components/ui/tabla";
import { useRolActual } from "@/lib/admin/use-rol";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { useToast } from "@/components/toast";
import { puedeGestionarCatalogos } from "@cayla-dynamic/shared";

type TipoSede = "central" | "taller" | "tienda";
interface Sede { id: string; codigo: string; nombre: string; activa: boolean; tipo: TipoSede }
interface FormSede { codigo: string; nombre: string; tipo: TipoSede }
const FORM_VACIO: FormSede = { codigo: "", nombre: "", tipo: "tienda" };

// Qué es cada local. No es una etiqueta decorativa: el reporte de costos separa
// lo que cuesta administrar de lo que cuesta operar una tienda, y sin esto los
// dos números se suman como si fueran lo mismo.
const TIPOS: Array<{ valor: TipoSede; label: string; ayuda: string }> = [
  { valor: "tienda",  label: "Tienda",  ayuda: "Atiende clientas." },
  { valor: "taller",  label: "Taller",  ayuda: "Produce; no atiende clientas." },
  { valor: "central", label: "Central", ayuda: "Administración y Desarrollo Organizacional. No vende." },
];
const ETIQUETA_TIPO: Record<TipoSede, string> = { tienda: "Tienda", taller: "Taller", central: "Central" };
const CODIGO_OK = /^[A-Z0-9]{2,8}$/;

export default function SedesPage() {
  const router = useRouter();
  const rol = useRolActual();
  const puedeGestionar = puedeGestionarCatalogos(rol);
  const { avisar } = useToast();

  const [sedes, setSedes] = useState<Sede[]>([]);
  const [cargando, setCargando] = useState(true);
  const [cargaError, setCargaError] = useState<string | null>(null);

  const [mostrandoAlta, setMostrandoAlta] = useState(false);
  const [editandoCodigo, setEditandoCodigo] = useState<string | null>(null);
  // El `id` de la sede que se está editando, además de su código. Desde la 0367
  // `fn_guardar_sede` distingue crear de editar, y en una edición lo que
  // identifica la fila es el id: el código es solo la etiqueta. Y el código de
  // una sede ya creada no se cambia — ni acá ni en la base, que se niega si le
  // llega uno distinto: tres columnas apuntan a la sede por texto y sin clave
  // foránea (la tarifa de movilidad por sede, la planilla ya pagada y el roster
  // del terminal), así que renombrarlo las dejaría huérfanas sin un solo error.
  const [editandoId, setEditandoId] = useState<string | null>(null);
  const [form, setForm] = useState<FormSede>(FORM_VACIO);
  const [guardando, setGuardando] = useState(false);

  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    const { data, error } = await supabase.from("sedes").select("id, codigo, nombre, activa, tipo").order("codigo");
    setSedes((data as Sede[]) ?? []);
    setCargaError(error ? error.message : null);
    setCargando(false);
  }, [router]);

  useEffect(() => { void cargar(); }, [cargar]);

  const edicionHabilitada = !cargaError;

  function empezarAlta() { setMostrandoAlta(true); setEditandoCodigo(null); setEditandoId(null); setForm(FORM_VACIO); }
  function empezarEdicion(s: Sede) { setEditandoCodigo(s.codigo); setEditandoId(s.id); setMostrandoAlta(false); setForm({ codigo: s.codigo, nombre: s.nombre, tipo: s.tipo }); }
  function cancelarForm() { setMostrandoAlta(false); setEditandoCodigo(null); setEditandoId(null); setForm(FORM_VACIO); }

  async function guardarSede() {
    const nombre = form.nombre.trim();
    const codigo = editandoCodigo ?? form.codigo.trim().toUpperCase();
    if (!nombre) { avisar("error", "El nombre es obligatorio."); return; }
    if (!editandoCodigo && !CODIGO_OK.test(codigo)) {
      avisar("error", "El código debe tener 2 a 8 letras o números, sin espacios (ej. LIMT).");
      return;
    }
    // Este aviso llega ANTES de guardar y solo por eso existe: la lista contra
    // la que compara se cargó al abrir la pantalla, así que no ve la sede que
    // otra persona creó hace un minuto. Quien garantiza es la base desde la
    // 0367 — `fn_guardar_sede` recibe `p_es_alta` y se niega a pisar un código
    // ocupado, con el índice único de `codigo` cerrando la carrera.
    if (!editandoCodigo && sedes.some((s) => s.codigo === codigo)) {
      avisar("error", `Ya existe una sede con el código “${codigo}”. Para modificarla, usa “Editar” en su fila.`);
      return;
    }
    const eraEdicion = editandoCodigo !== null;
    setGuardando(true);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_guardar_sede", {
      p_codigo: codigo,
      p_nombre: nombre,
      p_tipo: form.tipo,
      // Los dos que le dicen a la base qué se está haciendo. Sin ellos, crear
      // y editar se ven iguales desde el servidor y una de las dos pisa.
      p_id: editandoId,
      p_es_alta: !eraEdicion,
    });
    setGuardando(false);
    if (error) { avisar("error", mensajeDeError(error, "guardar")); return; }
    cancelarForm();
    await cargar();
    avisar("ok", eraEdicion ? "Cambios guardados." : `Sede “${nombre}” (${codigo}) creada.`);
  }

  async function cambiarActiva(s: Sede, activa: boolean) {
    if (!activa && !window.confirm(
      `¿Desactivar la sede "${s.nombre}"? Deja de ofrecerse para nuevas asignaciones. Quien ya está asignado ahí lo conserva — puedes reactivarla cuando quieras.`
    )) return;
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_sede_activa", { p_codigo: s.codigo, p_activa: activa });
    if (error) { avisar("error", mensajeDeError(error)); return; }
    await cargar();
    avisar("ok", activa
      ? `“${s.nombre}” reactivada: vuelve a ofrecerse al asignar personas.`
      : `“${s.nombre}” desactivada. Quien ya está asignado ahí lo conserva; solo deja de ofrecerse para nuevas asignaciones.`);
  }

  const formulario = (modo: "alta" | "edicion") => (
    <div className="mb-6 grid max-w-2xl gap-3 rounded-2xl border border-sand bg-papel p-5 sm:grid-cols-2">
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
            <span className="text-xs text-taupe">Etiqueta corta que verás en tablas (2 a 8 letras/números). No cambia después.</span>
          </>
        ) : (
          <>
            <input value={form.codigo} disabled className="rounded-lg border bg-crema px-3 py-2 font-mono text-taupe" />
            <span className="text-xs text-taupe">Fijo — cambiar el nombre no cambia el código.</span>
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
      <label className="flex flex-col gap-1 text-sm sm:col-span-2">
        Qué es esta sede
        <select
          value={form.tipo}
          onChange={(e) => setForm({ ...form, tipo: e.target.value as TipoSede })}
          className="rounded-lg border bg-crema px-3 py-2"
        >
          {TIPOS.map((t) => (
            <option key={t.valor} value={t.valor}>{t.label} — {t.ayuda}</option>
          ))}
        </select>
        <span className="text-xs text-taupe">
          El reporte de costos separa lo que cuesta administrar de lo que cuesta operar una tienda. Si se
          marcan igual, los dos números se suman como si fueran lo mismo.
        </span>
      </label>
      <div className="flex items-end gap-3 sm:col-span-2">
        <Boton variante="primario" onClick={guardarSede} disabled={guardando}>
          {guardando ? "Guardando…" : modo === "alta" ? "Agregar sede" : "Guardar cambios"}
        </Boton>
        <Boton variante="secundario" onClick={cancelarForm}>Cancelar</Boton>
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
            <Boton variante="primario" onClick={empezarAlta}>+ Agregar sede</Boton>
          )}
        </div>

        {rol === null ? (
          <Cargando />
        ) : !puedeGestionar ? (
          <div className="max-w-2xl rounded-lg bg-ambar/15 px-4 py-3 text-sm text-ambar">
            Solo administradores y líderes pueden gestionar sedes.
          </div>
        ) : (
          <>
            {cargaError && (
              <div className="mb-4 max-w-3xl rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
                No se pudieron cargar las sedes: {cargaError}.{" "}
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
                  <Th>Qué es</Th>
                  <Th>Estado</Th>
                  <Th>Acciones</Th>
                </TablaEncabezado>
                <tbody>
                  {sedes.map((s) => (
                    <tr key={s.codigo} className={`border-t ${s.activa ? "" : "text-taupe"}`}>
                      <td className="px-4 py-2">{s.nombre}</td>
                      <td className="px-4 py-2 font-mono text-xs text-taupe">{s.codigo}</td>
                      <td className="px-4 py-2 text-xs text-taupe">{ETIQUETA_TIPO[s.tipo] ?? s.tipo}</td>
                      <td className="px-4 py-2">
                        <Insignia atenuada={!s.activa}>{s.activa ? "activa" : "inactiva"}</Insignia>
                      </td>
                      <td className="px-4 py-2">
                        {edicionHabilitada && (
                          <div className="flex flex-wrap gap-2">
                            {/* CAMBIO · «Hoja» se ofrecía en TODAS las filas (hallazgo 31 de la
                                auditoría del 2026-09-03/04), y la Hoja de sede solo carga sedes
                                activas: desde una inactiva se llegaba a una pantalla en blanco,
                                sin datos y sin error. Queda deshabilitado en vez de desaparecer
                                a propósito: las acciones de la fila se quedan donde estaban, así
                                que la columna no baila según el estado y se ve que la acción
                                EXISTE pero hoy no aplica — que es lo que un botón ausente nunca
                                dice.
                                Lo que dice POR QUÉ no se puede es lo que ya se ve: la fila entera
                                atenuada y su insignia «inactiva», más el aviso de la Hoja de sede
                                si alguien llega igual escribiendo la dirección. El `title` de
                                abajo lo repite donde el navegador lo muestre, pero no se le confía
                                el mensaje: un <button disabled> queda fuera del orden de
                                tabulación y no todos los navegadores lo enseñan. */}
                            <Boton
                              variante="secundario"
                              tamano="sm"
                              disabled={!s.activa}
                              title={s.activa ? undefined : `“${s.nombre}” está desactivada y la Hoja de sede solo se arma para sedes activas. Reactívala para verla.`}
                              onClick={() => router.push(`/admin/reporte-sede?sede=${s.codigo}`)}
                            >
                              Hoja
                            </Boton>
                            <Boton variante="secundario" tamano="sm" onClick={() => empezarEdicion(s)}>Editar</Boton>
                            {s.activa ? (
                              <Boton variante="peligro" tamano="sm" onClick={() => cambiarActiva(s, false)}>Desactivar</Boton>
                            ) : (
                              <Boton variante="secundario" tamano="sm" onClick={() => cambiarActiva(s, true)}>Reactivar</Boton>
                            )}
                          </div>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </Tabla>
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
