"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { AdminNav } from "../nav";

function fechaHoyLima() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Lima" }).format(new Date());
}

interface Persona { id: string; nombres: string; apellidos: string; rol: string; sede_base_id: string; }
interface Horario { persona_id: string; hora_entrada: string; hora_salida: string; vigente_desde: string; almuerzo_min_minutos: number; almuerzo_max_minutos: number; }
const ROLES_ADMIN = ["admin", "lider_do"];

export default function HorariosPage() {
  const router = useRouter();
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [horarios, setHorarios] = useState<Map<string, Horario>>(new Map());
  const [sedes, setSedes] = useState<Record<string, string>>({});
  const [cargando, setCargando] = useState(true);
  const [mensaje, setMensaje] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);

  const [editando, setEditando] = useState<Persona | null>(null);
  const [entrada, setEntrada] = useState("08:00");
  const [salida, setSalida] = useState("18:00");
  const [desde, setDesde] = useState(fechaHoyLima());
  const [guardando, setGuardando] = useState(false);

  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    setCargando(true);
    const [{ data: p }, { data: h }, { data: s }] = await Promise.all([
      supabase.from("personas").select("id, nombres, apellidos, rol, sede_base_id").eq("estado", "activo").order("nombres"),
      supabase.from("horarios_asignados").select("persona_id, hora_entrada, hora_salida, vigente_desde, almuerzo_min_minutos, almuerzo_max_minutos").is("vigente_hasta", null),
      supabase.from("sedes").select("id, codigo"),
    ]);
    setPersonas((p as Persona[]) ?? []);
    setHorarios(new Map(((h as Horario[]) ?? []).map((x) => [x.persona_id, x])));
    setSedes(Object.fromEntries(((s as any[]) ?? []).map((x) => [x.id, x.codigo])));
    setCargando(false);
  }, [router]);

  useEffect(() => { void cargar(); }, [cargar]);

  const puedeEditar = rol === "admin" || rol === "lider_do" || rol === "supervisor_sede";
  const esSupervisor = rol === "supervisor_sede";
  const editables = useMemo(() => {
    if (!esSupervisor || !yo) return personas;
    return personas.filter((p) => p.id !== yo.id && !ROLES_ADMIN.includes(p.rol));
  }, [personas, esSupervisor, yo]);

  function abrirEdicion(p: Persona) {
    const h = horarios.get(p.id);
    setEditando(p);
    setEntrada(h?.hora_entrada?.slice(0, 5) ?? "08:00");
    setSalida(h?.hora_salida?.slice(0, 5) ?? "18:00");
    setDesde(fechaHoyLima());
    setMensaje(null);
  }

  async function guardar() {
    if (!editando) return;
    setGuardando(true);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_set_horario", {
      p_persona_id: editando.id, p_hora_entrada: entrada, p_hora_salida: salida, p_vigente_desde: desde,
    });
    setGuardando(false);
    if (error) { setMensaje({ tipo: "error", texto: error.message }); return; }
    setEditando(null);
    await cargar();
    setMensaje({ tipo: "ok", texto: "Horario guardado. Las tardanzas desde esa fecha se recalcularon." });
  }

  if (rol !== null && !puedeEditar) {
    return (
      <div className="flex min-h-screen flex-col"><AdminNav />
        <main className="flex flex-1 items-center justify-center p-6">
          <p className="max-w-md text-center text-neutral-500">No tienes permiso para editar horarios.</p>
        </main>
      </div>
    );
  }

  const porSede = [...new Set(editables.map((p) => sedes[p.sede_base_id] ?? "?"))].sort();

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <h1 className="mb-1 text-xl font-semibold">Horarios de entrada</h1>
        <p className="mb-5 max-w-2xl text-sm text-neutral-500">
          La hora de entrada define la tardanza (cualquier minuto después cuenta como tarde). Cuando
          un turno cambie, edítalo con la fecha desde la que aplica — el horario anterior se conserva,
          así las tardanzas de días previos no se alteran.
        </p>

        {mensaje && (
          <div className={`mb-4 max-w-2xl rounded-lg px-4 py-3 text-sm ${mensaje.tipo === "ok" ? "bg-green-50 text-green-800" : "bg-red-50 text-red-700"}`}>{mensaje.texto}</div>
        )}

        {cargando ? <p className="text-sm text-neutral-400">Cargando…</p> : porSede.map((sede) => {
          const deSede = editables.filter((p) => (sedes[p.sede_base_id] ?? "?") === sede);
          return (
            <section key={sede} className="mb-8">
              <h2 className="mb-2 font-medium">{sede}</h2>
              <div className="overflow-x-auto rounded-lg border">
                <table className="w-full text-sm [font-variant-numeric:tabular-nums]">
                  <thead className="bg-neutral-50 text-left text-neutral-500">
                    <tr>
                      <th className="px-4 py-2 font-normal">Nombre</th>
                      <th className="px-4 py-2 font-normal">Entrada</th>
                      <th className="px-4 py-2 font-normal">Salida</th>
                      <th className="px-4 py-2 font-normal">Vigente desde</th>
                      <th className="px-4 py-2 font-normal"></th>
                    </tr>
                  </thead>
                  <tbody>
                    {deSede.map((p) => {
                      const h = horarios.get(p.id);
                      return (
                        <tr key={p.id} className="border-t">
                          <td className="px-4 py-2">{p.nombres} {p.apellidos}</td>
                          <td className="px-4 py-2">{h ? h.hora_entrada.slice(0, 5) : <span className="text-neutral-300">sin horario</span>}</td>
                          <td className="px-4 py-2">{h ? h.hora_salida.slice(0, 5) : "—"}</td>
                          <td className="px-4 py-2 text-neutral-500">{h ? h.vigente_desde : "—"}</td>
                          <td className="px-4 py-2">
                            <button onClick={() => abrirEdicion(p)} className="rounded border px-2 py-1 text-xs hover:bg-neutral-50">
                              {h ? "Cambiar" : "Asignar"}
                            </button>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </section>
          );
        })}

        {editando && (
          <div className="fixed inset-0 z-10 flex items-center justify-center bg-black/40 p-4" onClick={() => !guardando && setEditando(null)}>
            <div className="w-full max-w-md rounded-xl bg-white p-6 shadow-lg" onClick={(e) => e.stopPropagation()}>
              <h3 className="mb-1 font-semibold">Horario de {editando.nombres} {editando.apellidos}</h3>
              <p className="mb-4 text-sm text-neutral-500">El nuevo horario aplica desde la fecha que elijas en adelante.</p>
              <div className="grid grid-cols-2 gap-3">
                <label className="flex flex-col gap-1 text-sm">Hora de entrada
                  <input type="time" value={entrada} onChange={(e) => setEntrada(e.target.value)} className="rounded-lg border px-3 py-2" /></label>
                <label className="flex flex-col gap-1 text-sm">Hora de salida
                  <input type="time" value={salida} onChange={(e) => setSalida(e.target.value)} className="rounded-lg border px-3 py-2" /></label>
                <label className="col-span-2 flex flex-col gap-1 text-sm">Vigente desde
                  <input type="date" value={desde} onChange={(e) => setDesde(e.target.value)} className="rounded-lg border px-3 py-2" /></label>
              </div>
              <div className="mt-5 flex justify-end gap-3">
                <button onClick={() => setEditando(null)} disabled={guardando} className="rounded-lg border px-4 py-2 text-sm">Cancelar</button>
                <button onClick={guardar} disabled={guardando} className="rounded-lg bg-black px-4 py-2 text-sm font-medium text-white disabled:opacity-50">
                  {guardando ? "Guardando…" : "Guardar horario"}
                </button>
              </div>
            </div>
          </div>
        )}
      </main>
    </div>
  );
}
