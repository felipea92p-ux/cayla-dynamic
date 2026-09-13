"use client";

import { Suspense, useCallback, useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Cargando } from "@/components/cargando";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { MESES, lecturaObjetivos, nivelColorObjetivos, type MesHistorial, type ObjetivoItem } from "@/lib/objetivos";
import { GraficoObjetivos } from "@/components/grafico-objetivos";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { useToast } from "@/components/toast";
import { TZ_LIMA, puedeVerTodasLasSedes } from "@cayla-dynamic/shared";
import { Boton } from "@/components/ui/boton";
import { Insignia } from "@/components/ui/insignia";
import { Modal } from "@/components/ui/modal";
import { Campo, CampoCasilla, CampoSelect } from "@/components/ui/campo";
import { AreaTexto } from "@/components/ui/area-texto";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";


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
  const [mesPagado, setMesPagado] = useState(false);
  const [historial, setHistorial] = useState<MesHistorial[]>([]);
  const [rangoHistorial, setRangoHistorial] = useState(12);
  const [cargando, setCargando] = useState(false);
  const [cargado, setCargado] = useState(false);

  const [nuevoTexto, setNuevoTexto] = useState("");
  const [nuevasIndicaciones, setNuevasIndicaciones] = useState("");
  const [guardando, setGuardando] = useState(false);
  const [copiando, setCopiando] = useState(false);
  const [editandoId, setEditandoId] = useState<string | null>(null);
  const [textoEdicion, setTextoEdicion] = useState("");
  const [indicacionesEdicion, setIndicacionesEdicion] = useState("");
  // Reemplaza el window.confirm() que pedía esta misma confirmación en un
  // diálogo nativo del navegador — Felipe aprobó migrar todos los diálogos
  // nativos del panel a <Modal> (ver CLAUDE.md).
  const [aEliminar, setAEliminar] = useState<ObjetivoItem | null>(null);
  const [eliminando, setEliminando] = useState(false);

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
  const tienePermisoDeRol = useMemo(() => {
    if (!persona || rol === null) return false;
    if (puedeVerTodasLasSedes(rol)) return true;
    if (rol === "supervisor_sede" && yo)
      return persona.rol === "integrante" && persona.sede_base_id === yo.sedeBaseId;
    return false;
  }, [persona, rol, yo]);
  // El mes con planilla pagada es solo lectura aunque el rol sí tenga
  // permiso — mismo criterio que ya usa correcciones/page.tsx con
  // periodo_pagado, para avisar ANTES de dejar editar, no después.
  const puedeGestionar = tienePermisoDeRol && !mesPagado;

  const cargar = useCallback(async () => {
    if (!personaId) return;
    setCargando(true);
    const supabase = createAdminSupabaseClient();
    // objetivos_items NUNCA se lee por REST (schema cache de PostgREST trabado):
    // solo vía RPC jsonb, patrón 0020.
    const [{ data, error }, { data: res }, { data: pagado }] = await Promise.all([
      supabase.rpc("fn_objetivos_checklist", { p_anio: anio, p_mes: mes, p_persona_id: personaId }),
      supabase.rpc("fn_objetivos_resumen", { p_anio: anio, p_mes: mes }),
      // El servidor SÍ bloquea escribir sobre un mes con planilla pagada
      // (fn_mes_planilla_pagado, 0032); esto solo lo trae al cliente para
      // avisar ANTES de que alguien intente editar, no después con un toast
      // de error — a diferencia de antes, que nunca pedía este dato.
      supabase.rpc("fn_mes_planilla_pagado", { p_anio: anio, p_mes: mes }),
    ]);
    if (error) {
      avisar("error", mensajeDeError(error));
    } else {
      setItems(((data as unknown as ObjetivoItem[] | null) ?? []).slice());
      setResumen((res as unknown as ResumenMes[] | null) ?? []);
      setMesPagado(pagado === true);
    }
    setCargado(true);
    setCargando(false);
  }, [personaId, anio, mes, avisar]);

  useEffect(() => {
    setCargado(false);
    if (personaId) void cargar();
  }, [personaId, anio, mes, cargar]);

  // El historial se pide aparte: cambiar el rango (6/12/24 meses) no debe
  // reiniciar toda la pantalla a "Cargando…", solo refrescar el gráfico.
  // `cargarHistorial` la usan los manejadores de abajo después de mutar algo;
  // el efecto de mount/cambio de rango no LA LLAMA (referenciar una función
  // useCallback desde un efecto dispara el lint set-state-in-effect) — pide
  // los mismos datos en línea, igual que el efecto de sesión de arriba.
  //
  // "Cargando" del gráfico se DERIVA (estado con la clave del último
  // historial que llegó, no un ref: leer un ref durante el render es otro
  // lint prohibido, react-hooks/refs) en vez de un setState al ENTRAR al
  // efecto — eso dispararía set-state-in-effect. Actualizarlo adentro del
  // `.then()` no cuenta: ahí ya vive `setHistorial`, que tampoco lo dispara.
  // Mientras la clave no coincide con la selección actual, el gráfico se
  // atenúa en vez de desaparecer (refetch mantiene el dibujo anterior).
  const [historialClave, setHistorialClave] = useState<string | null>(null);
  const historialClaveActual = personaId ? `${personaId}|${anio}|${mes}|${rangoHistorial}` : null;
  const historialDesactualizado = historialClaveActual !== historialClave;

  const cargarHistorial = useCallback(async () => {
    if (!personaId) return;
    const supabase = createAdminSupabaseClient();
    const { data: hist } = await supabase.rpc("fn_objetivos_historial", {
      p_persona_id: personaId,
      p_anio: anio,
      p_mes: mes,
      p_meses: rangoHistorial,
    });
    setHistorial((hist as unknown as MesHistorial[] | null) ?? []);
    setHistorialClave(`${personaId}|${anio}|${mes}|${rangoHistorial}`);
  }, [personaId, anio, mes, rangoHistorial]);

  useEffect(() => {
    if (!personaId) return;
    let cancelado = false;
    const clave = `${personaId}|${anio}|${mes}|${rangoHistorial}`;
    createAdminSupabaseClient()
      .rpc("fn_objetivos_historial", { p_persona_id: personaId, p_anio: anio, p_mes: mes, p_meses: rangoHistorial })
      .then(({ data: hist }) => {
        if (!cancelado) {
          setHistorial((hist as unknown as MesHistorial[] | null) ?? []);
          setHistorialClave(clave);
        }
      });
    return () => {
      cancelado = true;
    };
  }, [personaId, anio, mes, rangoHistorial]);

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
    await cargarHistorial();
  }

  async function marcar(item: ObjetivoItem, cumplido: boolean) {
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_objetivo_marcar", {
      p_item_id: item.id,
      p_cumplido: cumplido,
    });
    if (error) {
      avisar("error", mensajeDeError(error, "marcar"));
      // El checkbox es un input nativo: el navegador ya invirtió su estado
      // visual al hacer clic, antes de que este onChange corriera. Sin un
      // re-render, queda mostrando lo que la persona intentó marcar, no lo
      // que en verdad se guardó (que el rechazo del servidor no cambió).
      // Forzar una copia nueva del array re-sincroniza el checkbox
      // controlado con item.cumplido, que nunca cambió.
      setItems((prev) => [...prev]);
      return;
    }
    await cargar();
    await cargarHistorial();
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
    // Pestillo barato contra un segundo clic mientras la copia anterior
    // sigue en vuelo. Lee el estado del render, así que cubre lo mismo que
    // `disabled` y nada más; la defensa real es el candado por persona de
    // la 0361 en el servidor, que pone en fila las llamadas y niega la
    // segunda con «ya tiene objetivos».
    if (copiando) return;
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
    await cargarHistorial();
  }

  async function eliminar(item: ObjetivoItem) {
    setEliminando(true);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_objetivo_eliminar", { p_item_id: item.id });
    setEliminando(false);
    if (error) {
      avisar("error", mensajeDeError(error, "eliminar"));
      return;
    }
    setAEliminar(null);
    await cargar();
    await cargarHistorial();
  }

  const cumplidos = items.filter((i) => i.cumplido).length;
  const total = items.length;
  const nivel = lecturaObjetivos(cumplidos, total);
  const pct = total > 0 ? Math.round((cumplidos / total) * 100) : 0;

  // Aviso: el mes tiene un número manual (de Planilla) y todavía no hay checklist.
  const registroManual = resumen.find((r) => r.persona_id === personaId && !r.con_checklist);

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6">
        <h1 className="mb-1 font-serif text-2xl">Objetivos del mes</h1>
        <p className="mb-5 text-sm text-taupe">
          Checklist de objetivos por persona. <strong>No pagan nada</strong>: son el historial
          que sostiene una promoción. La política salarial firmada pone «cumplió los objetivos
          que se le asignaron» entre los requisitos para cambiar de categoría, y dice que la
          remuneración solo se mueve por categoría o por un ajuste general de la escala.
        </p>

        <div className="mb-6 flex flex-wrap items-end gap-4">
          <CampoSelect
            etiqueta="Persona"
            value={personaId}
            onChange={(e) => setPersonaId(e.target.value)}
            className="min-w-56"
          >
            <option value="">Elegir…</option>
            {personas.map((p) => (
              <option key={p.id} value={p.id}>
                {p.nombres} {p.apellidos}
              </option>
            ))}
          </CampoSelect>
          <CampoSelect etiqueta="Mes" value={mes} onChange={(e) => setMes(Number(e.target.value))}>
            {MESES.map((m, i) => (
              <option key={m} value={i + 1}>
                {m}
              </option>
            ))}
          </CampoSelect>
          <CampoSelect etiqueta="Año" value={anio} onChange={(e) => setAnio(Number(e.target.value))}>
            {[hoy.anio - 1, hoy.anio, hoy.anio + 1].map((a) => (
              <option key={a} value={a}>
                {a}
              </option>
            ))}
          </CampoSelect>
        </div>

        {!personaId ? (
          <p className="text-sm text-taupe">Elige una persona para ver o gestionar sus objetivos.</p>
        ) : cargando && !cargado ? (
          <Cargando />
        ) : cargado ? (
          <div className="max-w-3xl">
            {/* Barra de progreso + nivel del plus */}
            <TarjetaInfo className="mb-4">
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
                    <span title="Menos del 30% de objetivos — amerita conversación (principios CAYLA)">
                      <Insignia variante="alerta">Observación</Insignia>
                    </span>
                  )}
                </span>
              </div>
              <div className="h-2 overflow-hidden rounded-pildora bg-sand">
                <div
                  className={`h-full rounded-pildora transition-all ${CLASE_BG_NIVEL[nivelColorObjetivos(cumplidos, total)]}`}
                  style={{ width: `${pct}%` }}
                />
              </div>
            </TarjetaInfo>

            {/* Historial: la tendencia, no solo el mes actual. El rango se elige,
                no queda fijo en 12 meses — fn_objetivos_historial ya aceptaba
                p_meses desde el principio, esto solo lo expone en pantalla. */}
            {historial.some((m) => m.total > 0) && (
              <TarjetaInfo className="mb-4">
                <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
                  <p className="text-xs font-medium text-taupe">
                    Historial ({rangoHistorial === 1 ? "1 mes" : `${rangoHistorial} meses`})
                  </p>
                  <CampoSelect
                    etiqueta="Rango"
                    value={rangoHistorial}
                    onChange={(e) => setRangoHistorial(Number(e.target.value))}
                  >
                    <option value={1}>Último mes</option>
                    <option value={2}>Últimos 2 meses</option>
                    <option value={3}>Últimos 3 meses</option>
                    <option value={6}>Últimos 6 meses</option>
                    <option value={12}>Últimos 12 meses</option>
                    <option value={24}>Últimos 24 meses</option>
                  </CampoSelect>
                </div>
                <GraficoObjetivos
                  key={historialClave ?? "sin-historial"}
                  historial={historial}
                  cargando={historialDesactualizado}
                />
              </TarjetaInfo>
            )}

            {registroManual && total === 0 && (
              <div className="mb-4 rounded-control bg-ambar/15 px-4 py-3 text-sm text-ambar">
                Este mes tiene un registro manual de {registroManual.cumplidos}/{registroManual.total} (puesto
                desde Planilla). Al agregar el primer objetivo del checklist, el checklist pasa a mandar y ese
                número se recalcula.
              </div>
            )}

            {mesPagado && tienePermisoDeRol && (
              <div className="mb-4 rounded-control bg-ambar/15 px-4 py-3 text-sm text-ambar">
                Solo lectura: la planilla de {MESES[mes - 1].toLowerCase()} {anio} ya está PAGADA. Para
                corregir, un administrador reabre el periodo en Planilla.
              </div>
            )}
            {!tienePermisoDeRol && persona && (
              <div className="mb-4 rounded-control bg-sand/40 px-4 py-3 text-sm text-taupe">
                Solo lectura. {rol === "supervisor_sede"
                  ? "Como líder de equipo gestionas los objetivos de los integrantes de tu sede; los demás los gestiona un administrador."
                  : "Los objetivos los marca tu líder de equipo o un administrador."}
              </div>
            )}

            {/* Lista */}
            <ul className="mb-4 divide-y divide-sand rounded-superficie border border-sand bg-papel">
              {items.length === 0 ? (
                <li className="flex flex-col items-center gap-3 px-4 py-6 text-center text-sm text-taupe">
                  <span>Sin objetivos registrados para {MESES[mes - 1].toLowerCase()} {anio}.</span>
                  {puedeGestionar && (
                    <Boton
                      tamano="sm"
                      onClick={() => void copiarMesAnterior()}
                      disabled={copiando}
                      cargando={copiando}
                    >
                      {copiando ? "Copiando…" : "Copiar del mes anterior"}
                    </Boton>
                  )}
                </li>
              ) : (
                items.map((item) => (
                  <li key={item.id} className="flex items-start gap-3 px-4 py-2.5">
                    <CampoCasilla
                      checked={item.cumplido}
                      disabled={!puedeGestionar}
                      onChange={(e) => void marcar(item, e.target.checked)}
                      className="mt-1 rounded border-sand"
                    />
                    {editandoId === item.id ? (
                      <div className="flex-1">
                        <Campo
                          value={textoEdicion}
                          onChange={(e) => setTextoEdicion(e.target.value)}
                          onKeyDown={(e) => {
                            if (e.key === "Escape") setEditandoId(null);
                          }}
                          autoFocus
                          maxLength={300}
                          placeholder="El objetivo"
                        />
                        <AreaTexto
                          value={indicacionesEdicion}
                          onChange={(e) => setIndicacionesEdicion(e.target.value)}
                          placeholder="Indicaciones (opcional) — el detalle que ayuda a cumplirlo"
                          maxLength={2000}
                          rows={2}
                          className="mt-2 w-full"
                        />
                        <div className="mt-2 flex gap-2">
                          <Boton variante="primario" tamano="sm" onClick={() => void guardarEdicion(item)} disabled={guardando} cargando={guardando}>
                            Guardar
                          </Boton>
                          <Boton tamano="sm" onClick={() => setEditandoId(null)}>
                            Cancelar
                          </Boton>
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
                            <Boton
                              tamano="sm"
                              onClick={() => {
                                setEditandoId(item.id);
                                setTextoEdicion(item.descripcion);
                                setIndicacionesEdicion(item.indicaciones ?? "");
                              }}
                            >
                              Editar
                            </Boton>
                            <Boton variante="peligro" tamano="sm" onClick={() => setAEliminar(item)}>
                              Eliminar
                            </Boton>
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
              <div className="flex flex-col gap-2 rounded-superficie border border-sand bg-papel p-3">
                <Campo
                  value={nuevoTexto}
                  onChange={(e) => setNuevoTexto(e.target.value)}
                  placeholder="ej. Completar la capacitación de atención al cliente"
                  maxLength={300}
                />
                <AreaTexto
                  value={nuevasIndicaciones}
                  onChange={(e) => setNuevasIndicaciones(e.target.value)}
                  placeholder="Indicaciones (opcional) — el detalle que ayuda a cumplirlo: qué se espera, cómo se mide, con quién coordinar"
                  maxLength={2000}
                  rows={2}
                />
                <Boton
                  variante="primario"
                  onClick={() => void agregar()}
                  disabled={guardando || !nuevoTexto.trim()}
                  cargando={guardando}
                  className="self-start"
                >
                  {guardando ? "Agregando…" : "+ Agregar"}
                </Boton>
              </div>
            )}

            {/* Confirmar eliminación: reemplaza el window.confirm() nativo. */}
            <Modal
              abierto={aEliminar !== null}
              onCerrar={() => setAEliminar(null)}
              bloqueado={eliminando}
              titulo="Eliminar objetivo"
              ancho="sm"
            >
              {aEliminar && (
                <>
                  <p className="mb-4 text-sm text-taupe">
                    ¿Eliminar el objetivo “{aEliminar.descripcion}”? No se puede deshacer.
                  </p>
                  <div className="flex justify-end gap-2">
                    <Boton onClick={() => setAEliminar(null)} disabled={eliminando}>
                      Cancelar
                    </Boton>
                    <Boton variante="peligro" onClick={() => void eliminar(aEliminar)} cargando={eliminando}>
                      Eliminar
                    </Boton>
                  </div>
                </>
              )}
            </Modal>

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
