"use client";

import { Suspense, useCallback, useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { AdminNav } from "../nav";
import { Cargando } from "@/components/cargando";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { MESES, lecturaObjetivos, nivelColorObjetivos, type MesHistorial, type ObjetivoItem } from "@/lib/objetivos";
import { GraficoObjetivos } from "@/components/grafico-objetivos";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { useToast } from "@/components/toast";
import { TZ_LIMA, puedeVerTodasLasSedes } from "@cayla-dynamic/shared";


// Mapa explícito (no `bg-${nivel}` interpolado) para que Tailwind encuentre
// las clases literales al escanear el archivo.
const CLASE_BG_NIVEL: Record<"verde" | "ambar" | "rojo", string> = {
  verde: "bg-verde",
  ambar: "bg-ambar",
  rojo: "bg-rojo",
};

function mesActualLima(): { anio: number; mes: number } {
  const f = new Intl.DateTimeFormat("en-CA", { timeZone: TZ_LIMA }).format(new Date());
  return { anio: Number(f.slice(0, 4)), mes: Number(f.slice(5, 7)) };
}

interface Persona {
  id: string;
  nombres: string;
  apellidos: string;
  rol: string;
  sede_base_id: string;
}
interface ResumenMes {
  persona_id: string;
  cumplidos: number;
  total: number;
  con_checklist: boolean;
}

function ObjetivosContenido() {
  const router = useRouter();
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;
  const hoy = useMemo(() => mesActualLima(), []);
  const { avisar } = useToast();

  // Enlace directo: /admin/objetivos?persona=<uuid>&anio=2026&mes=9 llega con
  // la persona y el mes ya elegidos. Lo usa Desempeño, donde ves que a alguien
  // le faltan los objetivos del mes y quieres cargárselos sin volver a buscarla.
  // Se lee con useSearchParams —no con window.location— porque esto también se
  // renderiza en el servidor, donde `window` no existe.
  const sp = useSearchParams();
  const personaEnlace = sp.get("persona");
  const anioEnlace = Number(sp.get("anio"));
  const mesEnlace = Number(sp.get("mes"));

  const [personas, setPersonas] = useState<Persona[]>([]);
  const [personaId, setPersonaId] = useState(personaEnlace ?? "");
  const [anio, setAnio] = useState(Number.isInteger(anioEnlace) && anioEnlace > 2000 ? anioEnlace : hoy.anio);
  const [mes, setMes] = useState(Number.isInteger(mesEnlace) && mesEnlace >= 1 && mesEnlace <= 12 ? mesEnlace : hoy.mes);
  const [items, setItems] = useState<ObjetivoItem[]>([]);
  const [resumen, setResumen] = useState<ResumenMes[]>([]);
  const [historial, setHistorial] = useState<MesHistorial[]>([]);
  const [cargando, setCargando] = useState(false);
  const [cargado, setCargado] = useState(false);

  const [nuevoTexto, setNuevoTexto] = useState("");
  const [nuevasIndicaciones, setNuevasIndicaciones] = useState("");
  const [guardando, setGuardando] = useState(false);
  const [copiando, setCopiando] = useState(false);
  const [editandoId, setEditandoId] = useState<string | null>(null);
  const [textoEdicion, setTextoEdicion] = useState("");
  const [indicacionesEdicion, setIndicacionesEdicion] = useState("");

  useEffect(() => {
    const supabase = createAdminSupabaseClient();
    supabase.auth.getSession().then(async ({ data }) => {
      if (!data.session) {
        router.replace("/admin/login");
        return;
      }
      // RLS ya limita: admin/líder ven a todos, encargada su sede, integrante solo a sí.
      const { data: p } = await supabase
        .from("personas")
        .select("id, nombres, apellidos, rol, sede_base_id")
        .eq("estado", "activo")
        .order("nombres");
      setPersonas((p as Persona[]) ?? []);
    });
  }, [router]);

  // Si solo me veo a mí (integrante), autoseleccionarme.
  useEffect(() => {
    if (!personaId && personas.length === 1) setPersonaId(personas[0].id);
  }, [personas, personaId]);

  const persona = personas.find((p) => p.id === personaId);

  // admin/líder gestionan a cualquiera; la encargada SOLO integrantes de su
  // sede (los objetivos de las encargadas los gestiona admin/líder). El
  // servidor re-valida esto mismo en cada RPC.
  const puedeGestionar = useMemo(() => {
    if (!persona || rol === null) return false;
    if (puedeVerTodasLasSedes(rol)) return true;
    if (rol === "supervisor_sede" && yo)
      return persona.rol === "integrante" && persona.sede_base_id === yo.sedeBaseId;
    return false;
  }, [persona, rol, yo]);

  const cargar = useCallback(async () => {
    if (!personaId) return;
    setCargando(true);
    const supabase = createAdminSupabaseClient();
    // objetivos_items NUNCA se lee por REST (schema cache de PostgREST trabado):
    // solo vía RPC jsonb, patrón 0020.
    const [{ data, error }, { data: res }, { data: hist }] = await Promise.all([
      supabase.rpc("fn_objetivos_checklist", { p_anio: anio, p_mes: mes, p_persona_id: personaId }),
      supabase.rpc("fn_objetivos_resumen", { p_anio: anio, p_mes: mes }),
      supabase.rpc("fn_objetivos_historial", { p_persona_id: personaId, p_anio: anio, p_mes: mes, p_meses: 12 }),
    ]);
    if (error) {
      avisar("error", mensajeDeError(error));
    } else {
      setItems(((data as unknown as ObjetivoItem[] | null) ?? []).slice());
      setResumen((res as unknown as ResumenMes[] | null) ?? []);
      setHistorial((hist as unknown as MesHistorial[] | null) ?? []);
    }
    setCargado(true);
    setCargando(false);
  }, [personaId, anio, mes, avisar]);

  useEffect(() => {
    setCargado(false);
    if (personaId) void cargar();
  }, [personaId, anio, mes, cargar]);

  async function agregar() {
    const texto = nuevoTexto.trim();
    if (!texto) {
      avisar("error", "Escribe el objetivo antes de agregarlo.");
      return;
    }
    setGuardando(true);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_objetivo_agregar", {
      p_persona_id: personaId,
      p_anio: anio,
      p_mes: mes,
      p_descripcion: texto,
      p_indicaciones: nuevasIndicaciones.trim() || null,
    });
    setGuardando(false);
    if (error) {
      avisar("error", mensajeDeError(error, "agregar"));
      return;
    }
    setNuevoTexto("");
    setNuevasIndicaciones("");
    await cargar();
  }

  async function marcar(item: ObjetivoItem, cumplido: boolean) {
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_objetivo_marcar", {
      p_item_id: item.id,
      p_cumplido: cumplido,
    });
    if (error) {
      avisar("error", mensajeDeError(error, "marcar"));
      return;
    }
    await cargar();
  }

  async function guardarEdicion(item: ObjetivoItem) {
    const texto = textoEdicion.trim();
    if (!texto) {
      avisar("error", "El objetivo no puede quedar vacío.");
      return;
    }
    setGuardando(true);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_objetivo_editar", {
      p_item_id: item.id,
      p_descripcion: texto,
      p_indicaciones: indicacionesEdicion.trim() || null,
    });
    setGuardando(false);
    if (error) {
      avisar("error", mensajeDeError(error, "editar"));
      return;
    }
    setEditandoId(null);
    await cargar();
  }

  async function copiarMesAnterior() {
    setCopiando(true);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_objetivos_copiar_mes_anterior", {
      p_persona_id: personaId,
      p_anio: anio,
      p_mes: mes,
    });
    setCopiando(false);
    if (error) {
      avisar("error", mensajeDeError(error, "copiar"));
      return;
    }
    await cargar();
  }

  async function eliminar(item: ObjetivoItem) {
    if (!window.confirm(`¿Eliminar el objetivo “${item.descripcion}”?`)) return;
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_objetivo_eliminar", { p_item_id: item.id });
    if (error) {
      avisar("error", mensajeDeError(error, "eliminar"));
      return;
    }
    await cargar();
  }

  const cumplidos = items.filter((i) => i.cumplido).length;
  const total = items.length;
  const nivel = lecturaObjetivos(cumplidos, total);
  const pct = total > 0 ? Math.round((cumplidos / total) * 100) : 0;

  // Aviso: el mes tiene un número manual (de Planilla) y todavía no hay checklist.
  const registroManual = resumen.find((r) => r.persona_id === personaId && !r.con_checklist);

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <h1 className="mb-1 font-serif text-2xl">Objetivos del mes</h1>
        <p className="mb-5 text-sm text-taupe">
          Checklist de objetivos por persona. <strong>No pagan nada</strong>: son el historial
          que sostiene una promoción. La política salarial firmada pone «cumplió los objetivos
          que se le asignaron» entre los requisitos para cambiar de categoría, y dice que la
          remuneración solo se mueve por categoría o por un ajuste general de la escala.
        </p>

        <div className="mb-6 flex flex-wrap items-end gap-4">
          <label className="flex flex-col gap-1 text-sm">
            Persona
            <select
              value={personaId}
              onChange={(e) => setPersonaId(e.target.value)}
              className="min-w-56 rounded-lg border border-sand bg-crema px-3 py-2"
            >
              <option value="">Elegir…</option>
              {personas.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.nombres} {p.apellidos}
                </option>
              ))}
            </select>
          </label>
          <label className="flex flex-col gap-1 text-sm">
            Mes
            <select
              value={mes}
              onChange={(e) => setMes(Number(e.target.value))}
              className="rounded-lg border border-sand bg-crema px-3 py-2"
            >
              {MESES.map((m, i) => (
                <option key={m} value={i + 1}>
                  {m}
                </option>
              ))}
            </select>
          </label>
          <label className="flex flex-col gap-1 text-sm">
            Año
            <select
              value={anio}
              onChange={(e) => setAnio(Number(e.target.value))}
              className="rounded-lg border border-sand bg-crema px-3 py-2"
            >
              {[hoy.anio - 1, hoy.anio, hoy.anio + 1].map((a) => (
                <option key={a} value={a}>
                  {a}
                </option>
              ))}
            </select>
          </label>
        </div>

        {!personaId ? (
          <p className="text-sm text-taupe">Elige una persona para ver o gestionar sus objetivos.</p>
        ) : cargando && !cargado ? (
          <Cargando />
        ) : cargado ? (
          <div className="max-w-3xl">
            {/* Barra de progreso + nivel del plus */}
            <div className="mb-4 rounded-2xl border border-sand bg-papel p-5">
              <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
                <span className="text-sm">
                  <span className="font-serif text-xl">{cumplidos}</span>
                  <span className="text-taupe"> de </span>
                  <span className="font-serif text-xl">{total}</span>
                  <span className="text-taupe"> cumplidos{total > 0 ? ` (${pct}%)` : ""}</span>
                </span>
                <span className="flex items-center gap-2 text-sm">
                  {/* La etiqueta «Plus 21%» salió el 2026-08-06 (mig 0171): decía
                      un monto que ya no se paga. La observación por bajo
                      desempeño se queda — nunca fue un pago, es un aviso para
                      conversar. */}
                  {total > 0 && nivel.observacion && (
                    <span
                      className="rounded-full bg-rojo/10 px-3 py-0.5 text-rojo"
                      title="Menos del 30% de objetivos — amerita conversación (principios CAYLA)"
                    >
                      Observación
                    </span>
                  )}
                </span>
              </div>
              <div className="h-2 overflow-hidden rounded-full bg-sand">
                <div
                  className={`h-full rounded-full transition-all ${CLASE_BG_NIVEL[nivelColorObjetivos(cumplidos, total)]}`}
                  style={{ width: `${pct}%` }}
                />
              </div>
            </div>

            {/* Historial: la tendencia de los últimos 12 meses, no solo el actual */}
            {historial.some((m) => m.total > 0) && (
              <div className="mb-4 rounded-2xl border border-sand bg-papel p-5">
                <p className="mb-2 text-xs font-medium text-taupe">Historial (últimos 12 meses)</p>
                <GraficoObjetivos historial={historial} />
              </div>
            )}

            {registroManual && total === 0 && (
              <div className="mb-4 rounded-lg bg-ambar/15 px-4 py-3 text-sm text-ambar">
                Este mes tiene un registro manual de {registroManual.cumplidos}/{registroManual.total} (puesto
                desde Planilla). Al agregar el primer objetivo del checklist, el checklist pasa a mandar y ese
                número se recalcula.
              </div>
            )}

            {!puedeGestionar && persona && (
              <div className="mb-4 rounded-lg bg-sand/40 px-4 py-3 text-sm text-taupe">
                Solo lectura. {rol === "supervisor_sede"
                  ? "Como líder de equipo gestionas los objetivos de los integrantes de tu sede; los demás los gestiona un administrador."
                  : "Los objetivos los marca tu líder de equipo o un administrador."}
              </div>
            )}

            {/* Lista */}
            <ul className="mb-4 divide-y divide-sand rounded-2xl border border-sand bg-papel">
              {items.length === 0 ? (
                <li className="flex flex-col items-center gap-3 px-4 py-6 text-center text-sm text-taupe">
                  <span>Sin objetivos registrados para {MESES[mes - 1].toLowerCase()} {anio}.</span>
                  {puedeGestionar && (
                    <button
                      onClick={() => void copiarMesAnterior()}
                      disabled={copiando}
                      className="rounded-lg border border-sand px-3 py-1.5 text-xs font-medium text-tinta hover:bg-sand/40 disabled:opacity-50"
                    >
                      {copiando ? "Copiando…" : "Copiar del mes anterior"}
                    </button>
                  )}
                </li>
              ) : (
                items.map((item) => (
                  <li key={item.id} className="flex items-start gap-3 px-4 py-2.5">
                    <input
                      type="checkbox"
                      checked={item.cumplido}
                      disabled={!puedeGestionar}
                      onChange={(e) => void marcar(item, e.target.checked)}
                      className="mt-1 h-4 w-4 rounded border"
                    />
                    {editandoId === item.id ? (
                      <div className="flex-1">
                        <input
                          value={textoEdicion}
                          onChange={(e) => setTextoEdicion(e.target.value)}
                          onKeyDown={(e) => {
                            if (e.key === "Escape") setEditandoId(null);
                          }}
                          autoFocus
                          maxLength={300}
                          placeholder="El objetivo"
                          className="w-full rounded-lg border border-sand bg-crema px-3 py-1.5 text-sm"
                        />
                        <textarea
                          value={indicacionesEdicion}
                          onChange={(e) => setIndicacionesEdicion(e.target.value)}
                          placeholder="Indicaciones (opcional) — el detalle que ayuda a cumplirlo"
                          maxLength={2000}
                          rows={2}
                          className="mt-2 w-full rounded-lg border border-sand bg-crema px-3 py-1.5 text-sm"
                        />
                        <div className="mt-2 flex gap-2">
                          <button
                            onClick={() => void guardarEdicion(item)}
                            disabled={guardando}
                            className="rounded-lg bg-tinta px-3 py-1.5 text-xs font-medium text-crema disabled:opacity-50"
                          >
                            Guardar
                          </button>
                          <button
                            onClick={() => setEditandoId(null)}
                            className="rounded-lg border px-3 py-1.5 text-xs"
                          >
                            Cancelar
                          </button>
                        </div>
                      </div>
                    ) : (
                      <>
                        <div className="flex-1">
                          <span className={`text-sm ${item.cumplido ? "text-taupe line-through" : ""}`}>
                            {item.descripcion}
                          </span>
                          {item.indicaciones && (
                            <p className="mt-0.5 whitespace-pre-wrap text-xs text-taupe">{item.indicaciones}</p>
                          )}
                        </div>
                        {puedeGestionar && (
                          <div className="flex shrink-0 gap-2 text-xs">
                            <button
                              onClick={() => {
                                setEditandoId(item.id);
                                setTextoEdicion(item.descripcion);
                                setIndicacionesEdicion(item.indicaciones ?? "");
                              }}
                              className="rounded border px-2 py-1 hover:bg-sand/50"
                            >
                              Editar
                            </button>
                            <button
                              onClick={() => void eliminar(item)}
                              className="rounded border border-rojo/30 px-2 py-1 text-rojo hover:bg-rojo/10"
                            >
                              Eliminar
                            </button>
                          </div>
                        )}
                      </>
                    )}
                  </li>
                ))
              )}
            </ul>

            {/* Agregar */}
            {puedeGestionar && (
              <div className="flex flex-col gap-2 rounded-2xl border border-sand bg-papel p-3">
                <input
                  value={nuevoTexto}
                  onChange={(e) => setNuevoTexto(e.target.value)}
                  placeholder="ej. Completar la capacitación de atención al cliente"
                  maxLength={300}
                  className="rounded-lg border border-sand bg-crema px-3 py-2 text-sm"
                />
                <textarea
                  value={nuevasIndicaciones}
                  onChange={(e) => setNuevasIndicaciones(e.target.value)}
                  placeholder="Indicaciones (opcional) — el detalle que ayuda a cumplirlo: qué se espera, cómo se mide, con quién coordinar"
                  maxLength={2000}
                  rows={2}
                  className="rounded-lg border border-sand bg-crema px-3 py-2 text-sm"
                />
                <button
                  onClick={() => void agregar()}
                  disabled={guardando || !nuevoTexto.trim()}
                  className="self-start rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema disabled:opacity-50"
                >
                  {guardando ? "Agregando…" : "+ Agregar"}
                </button>
              </div>
            )}

            <p className="mt-4 text-xs text-taupe">
              Mes con planilla PAGADA = solo lectura (para corregir, un administrador reabre el periodo en
              Planilla). Menos del 30% de objetivos genera una observación por bajo desempeño — amerita
              conversación, nunca es automático.
            </p>
          </div>
        ) : null}
      </main>
    </div>
  );
}

export default function ObjetivosPage() {
  return (
    <Suspense fallback={<main className="p-6"><p className="text-sm text-taupe">Cargando…</p></main>}>
      <ObjetivosContenido />
    </Suspense>
  );
}
