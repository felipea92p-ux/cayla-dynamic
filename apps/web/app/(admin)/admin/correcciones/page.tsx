"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { TIPO_MARCA_LABELS, TIPOS_MARCA, type TipoMarca } from "@cayla-dynamic/shared";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { AdminNav } from "../nav";

const TZ = "America/Lima";

function fechaHoyLima() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: TZ }).format(new Date());
}
// "HH:MM" en hora Lima para el input de tipo time
function horaInput(tsISO: string) {
  return new Intl.DateTimeFormat("en-GB", { timeZone: TZ, hour: "2-digit", minute: "2-digit", hour12: false }).format(new Date(tsISO));
}
// fecha (YYYY-MM-DD) + "HH:MM" -> ISO con offset fijo de Perú (-05:00)
function construirTs(fecha: string, horaHHMM: string) {
  return `${fecha}T${horaHHMM}:00-05:00`;
}

interface Persona { id: string; nombres: string; apellidos: string; rol: string; sede_base_id: string; }
const ROLES_ADMIN = ["admin", "lider_do"];
interface Marcaje { id: string; tipo: TipoMarca; motivo_otro: string | null; timestamp_marca: string; origen: string; estado_revision: string; }
interface Jornada { estado: string; horas_trabajadas: number | null; minutos_tarde: number | null; }

// Tipos que un admin puede agregar manualmente (los pares salida/retorno y entrada/salida final)
const TIPOS_AGREGABLES = TIPOS_MARCA;

type Accion =
  | { modo: "editar"; marcaje: Marcaje; nuevaHora: string }
  | { modo: "eliminar"; marcaje: Marcaje }
  | { modo: "agregar"; tipo: TipoMarca; hora: string; motivoOtro: string };

export default function CorreccionesPage() {
  const router = useRouter();
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [personaId, setPersonaId] = useState("");
  const [fecha, setFecha] = useState(fechaHoyLima());
  const [marcajes, setMarcajes] = useState<Marcaje[]>([]);
  const [jornada, setJornada] = useState<Jornada | null>(null);
  const [cargado, setCargado] = useState(false);
  const [cargando, setCargando] = useState(false);
  const [mensaje, setMensaje] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);

  // edición local de horas por marcaje
  const [horasEditadas, setHorasEditadas] = useState<Record<string, string>>({});
  // acción pendiente de confirmar con motivo
  const [accion, setAccion] = useState<Accion | null>(null);
  const [motivo, setMotivo] = useState("");
  const [procesando, setProcesando] = useState(false);
  // formulario "agregar marcaje"
  const [agregarTipo, setAgregarTipo] = useState<TipoMarca>("entrada");
  const [agregarHora, setAgregarHora] = useState("08:00");
  const [agregarMotivoOtro, setAgregarMotivoOtro] = useState("");

  useEffect(() => {
    const supabase = createAdminSupabaseClient();
    supabase.auth.getSession().then(async ({ data }) => {
      if (!data.session) { router.replace("/admin/login"); return; }
      const { data: p } = await supabase
        .from("personas").select("id, nombres, apellidos, rol, sede_base_id").eq("estado", "activo").order("nombres");
      setPersonas((p as Persona[]) ?? []);
    });
  }, [router]);

  const cargarDia = useCallback(async () => {
    if (!personaId) return;
    setCargando(true);
    setMensaje(null);
    const supabase = createAdminSupabaseClient();
    const inicio = `${fecha}T00:00:00-05:00`;
    const fin = `${fecha}T23:59:59-05:00`;
    const [{ data: mk }, { data: jor }] = await Promise.all([
      supabase.from("marcajes")
        .select("id, tipo, motivo_otro, timestamp_marca, origen, estado_revision")
        .eq("persona_id", personaId).gte("timestamp_marca", inicio).lte("timestamp_marca", fin)
        .order("timestamp_marca"),
      supabase.from("jornadas")
        .select("estado, horas_trabajadas, minutos_tarde")
        .eq("persona_id", personaId).eq("fecha", fecha).maybeSingle(),
    ]);
    setMarcajes((mk as Marcaje[]) ?? []);
    setJornada((jor as Jornada) ?? null);
    setHorasEditadas(Object.fromEntries(((mk as Marcaje[]) ?? []).map((m) => [m.id, horaInput(m.timestamp_marca)])));
    setCargado(true);
    setCargando(false);
  }, [personaId, fecha]);

  function avisar(tipo: "ok" | "error", texto: string) { setMensaje({ tipo, texto }); }

  async function ejecutar() {
    if (!accion) return;
    if (motivo.trim().length < 3) { avisar("error", "Escribe un motivo (mínimo 3 caracteres)."); return; }
    setProcesando(true);
    const supabase = createAdminSupabaseClient();
    let error = null;
    if (accion.modo === "editar") {
      ({ error } = await supabase.rpc("fn_corregir_marcaje", {
        p_marcaje_id: accion.marcaje.id,
        p_nuevo_ts: construirTs(fecha, accion.nuevaHora),
        p_motivo: motivo.trim(),
      }));
    } else if (accion.modo === "eliminar") {
      ({ error } = await supabase.rpc("fn_eliminar_marcaje", {
        p_marcaje_id: accion.marcaje.id, p_motivo: motivo.trim(),
      }));
    } else {
      ({ error } = await supabase.rpc("fn_agregar_marcaje", {
        p_persona_id: personaId,
        p_tipo: accion.tipo,
        p_ts: construirTs(fecha, accion.hora),
        p_motivo: motivo.trim(),
        p_motivo_otro: accion.tipo === "salida_otro" ? (accion.motivoOtro || undefined) : undefined,
      }));
    }
    setProcesando(false);
    if (error) { avisar("error", error.message); return; }
    setAccion(null);
    setMotivo("");
    await cargarDia();
    avisar("ok", "Corrección guardada y registrada en la auditoría.");
  }

  const personaSel = useMemo(() => personas.find((p) => p.id === personaId), [personas, personaId]);
  const puedeCorregir = rol === "admin" || rol === "lider_do" || rol === "supervisor_sede";
  const esSupervisor = rol === "supervisor_sede";

  // Una encargada no puede corregir su propia asistencia ni la de un admin.
  const personasCorregibles = useMemo(() => {
    if (!esSupervisor || !yo) return personas;
    return personas.filter((p) => p.id !== yo.id && !ROLES_ADMIN.includes(p.rol));
  }, [personas, esSupervisor, yo]);

  if (rol !== null && !puedeCorregir) {
    return (
      <div className="flex min-h-screen flex-col">
        <AdminNav />
        <main className="flex flex-1 items-center justify-center p-6">
          <p className="max-w-md text-center text-taupe">
            No tienes permiso para corregir marcajes. Si necesitas un cambio, pídeselo a Felipe o Carlos.
          </p>
        </main>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <h1 className="mb-1 font-serif text-2xl">Corregir marcajes</h1>
        <p className="mb-5 max-w-2xl text-sm text-taupe">
          Ajusta la hora de entrada/salida, agrega un marcaje olvidado o elimina un duplicado.
          Cada cambio pide un motivo y queda registrado (quién, qué y cuándo).
        </p>

        <div className="mb-6 flex flex-wrap items-end gap-4">
          <label className="flex flex-col gap-1 text-sm">
            Persona
            <select value={personaId} onChange={(e) => { setPersonaId(e.target.value); setCargado(false); }} className="min-w-56 rounded-lg border bg-crema px-3 py-2">
              <option value="">Elegir…</option>
              {personasCorregibles.map((p) => <option key={p.id} value={p.id}>{p.nombres} {p.apellidos}</option>)}
            </select>
          </label>
          <label className="flex flex-col gap-1 text-sm">
            Fecha
            <input type="date" value={fecha} onChange={(e) => { setFecha(e.target.value); setCargado(false); }} className="rounded-lg border px-3 py-2" />
          </label>
          <button onClick={cargarDia} disabled={!personaId || cargando} className="rounded-lg bg-tinta px-5 py-2 text-sm font-medium text-crema disabled:opacity-50">
            {cargando ? "Cargando…" : "Ver el día"}
          </button>
        </div>

        {mensaje && (
          <div className={`mb-4 max-w-2xl rounded-lg px-4 py-3 text-sm ${mensaje.tipo === "ok" ? "bg-sand/40 text-tinta" : "bg-rojo/10 text-rojo"}`}>
            {mensaje.texto}
          </div>
        )}

        {cargado && personaSel && (
          <div className="max-w-3xl">
            {jornada && (
              <div className="mb-4 flex flex-wrap gap-x-6 gap-y-1 rounded-lg border bg-sand/50 px-4 py-3 text-sm">
                <span>Estado: <strong>{jornada.estado}</strong></span>
                <span>Horas: <strong>{jornada.horas_trabajadas ?? "—"}</strong></span>
                <span>Tardanza: <strong>{jornada.minutos_tarde ? `${jornada.minutos_tarde} min` : "—"}</strong></span>
              </div>
            )}

            {marcajes.length === 0 ? (
              <p className="mb-4 text-sm text-taupe">No hay marcajes ese día. Puedes agregar uno abajo.</p>
            ) : (
              <div className="mb-4 overflow-x-auto rounded-lg border">
                <table className="w-full text-sm">
                  <thead className="bg-sand/50 text-left text-taupe">
                    <tr>
                      <th className="px-4 py-2 font-normal">Tipo</th>
                      <th className="px-4 py-2 font-normal">Hora</th>
                      <th className="px-4 py-2 font-normal">Origen</th>
                      <th className="px-4 py-2 font-normal">Acciones</th>
                    </tr>
                  </thead>
                  <tbody>
                    {marcajes.map((m) => {
                      const horaLocal = horasEditadas[m.id] ?? horaInput(m.timestamp_marca);
                      const cambiada = horaLocal !== horaInput(m.timestamp_marca);
                      return (
                        <tr key={m.id} className="border-t">
                          <td className="px-4 py-2">
                            {TIPO_MARCA_LABELS[m.tipo]}
                            {m.origen === "auto_cierre" && <span className="ml-2 rounded bg-rojo/10 px-1.5 py-0.5 text-xs text-rojo">auto-cierre</span>}
                            {m.origen === "admin_correccion" && <span className="ml-2 rounded bg-taupe/15 px-1.5 py-0.5 text-xs text-taupe">manual</span>}
                          </td>
                          <td className="px-4 py-2">
                            <input type="time" value={horaLocal}
                              onChange={(e) => setHorasEditadas({ ...horasEditadas, [m.id]: e.target.value })}
                              className="rounded border px-2 py-1" />
                          </td>
                          <td className="px-4 py-2 text-taupe">{m.origen}</td>
                          <td className="px-4 py-2">
                            <div className="flex gap-2 text-xs">
                              <button
                                disabled={!cambiada}
                                onClick={() => { setAccion({ modo: "editar", marcaje: m, nuevaHora: horaLocal }); setMotivo(""); }}
                                className="rounded border px-2 py-1 hover:bg-sand/50 disabled:opacity-40">
                                Guardar hora
                              </button>
                              <button
                                onClick={() => { setAccion({ modo: "eliminar", marcaje: m }); setMotivo(""); }}
                                className="rounded border border-rojo/30 px-2 py-1 text-rojo hover:bg-rojo/10">
                                Eliminar
                              </button>
                            </div>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}

            {/* Agregar marcaje faltante */}
            <div className="rounded-lg border bg-sand/50 p-4">
              <h2 className="mb-3 text-sm font-medium">Agregar un marcaje faltante</h2>
              <div className="flex flex-wrap items-end gap-3">
                <label className="flex flex-col gap-1 text-sm">
                  Tipo
                  <select value={agregarTipo} onChange={(e) => setAgregarTipo(e.target.value as TipoMarca)} className="rounded-lg border bg-crema px-3 py-2">
                    {TIPOS_AGREGABLES.map((t) => <option key={t} value={t}>{TIPO_MARCA_LABELS[t]}</option>)}
                  </select>
                </label>
                <label className="flex flex-col gap-1 text-sm">
                  Hora
                  <input type="time" value={agregarHora} onChange={(e) => setAgregarHora(e.target.value)} className="rounded-lg border px-3 py-2" />
                </label>
                {agregarTipo === "salida_otro" && (
                  <label className="flex flex-col gap-1 text-sm">
                    Motivo de la salida
                    <input value={agregarMotivoOtro} onChange={(e) => setAgregarMotivoOtro(e.target.value)} className="rounded-lg border px-3 py-2" placeholder="ej. trámite banco" />
                  </label>
                )}
                <button
                  onClick={() => { setAccion({ modo: "agregar", tipo: agregarTipo, hora: agregarHora, motivoOtro: agregarMotivoOtro }); setMotivo(""); }}
                  className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema">
                  Agregar
                </button>
              </div>
            </div>
          </div>
        )}

        {/* Modal: motivo de la corrección */}
        {accion && (
          <div className="fixed inset-0 z-10 flex items-center justify-center bg-black/40 p-4" onClick={() => !procesando && setAccion(null)}>
            <div className="w-full max-w-md rounded-xl bg-crema p-6 border border-sand" onClick={(e) => e.stopPropagation()}>
              <h3 className="mb-2 font-serif text-lg">
                {accion.modo === "editar" && "Confirmar cambio de hora"}
                {accion.modo === "eliminar" && "Eliminar marcaje"}
                {accion.modo === "agregar" && "Agregar marcaje"}
              </h3>
              <p className="mb-4 text-sm text-taupe">
                {accion.modo === "editar" && `${TIPO_MARCA_LABELS[accion.marcaje.tipo]}: ${horaInput(accion.marcaje.timestamp_marca)} → ${accion.nuevaHora}`}
                {accion.modo === "eliminar" && `${TIPO_MARCA_LABELS[accion.marcaje.tipo]} de las ${horaInput(accion.marcaje.timestamp_marca)}. Esta acción no se puede deshacer.`}
                {accion.modo === "agregar" && `${TIPO_MARCA_LABELS[accion.tipo]} a las ${accion.hora}, para ${personaSel?.nombres} ${personaSel?.apellidos}.`}
              </p>
              <label className="mb-4 flex flex-col gap-1 text-sm">
                Motivo (obligatorio)
                <textarea value={motivo} onChange={(e) => setMotivo(e.target.value)} rows={2} autoFocus
                  className="rounded-lg border px-3 py-2" placeholder="ej. el reloj del terminal estaba adelantado" />
              </label>
              <div className="flex justify-end gap-3">
                <button onClick={() => setAccion(null)} disabled={procesando} className="rounded-lg border px-4 py-2 text-sm">Cancelar</button>
                <button onClick={ejecutar} disabled={procesando} className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema disabled:opacity-50">
                  {procesando ? "Guardando…" : "Confirmar"}
                </button>
              </div>
            </div>
          </div>
        )}
      </main>
    </div>
  );
}
