"use client";

import { Suspense, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { ChevronDown, ChevronLeft, ChevronRight, ChevronUp, Lock, MoreHorizontal } from "lucide-react";
import { Cargando } from "@/components/cargando";
import { usePersonaActual } from "@/lib/admin/use-rol";
import {
  MESES,
  estadoObjetivos,
  nivelColorObjetivos,
  type MesHistorial,
  type ObjetivoItem,
} from "@/lib/objetivos";
import { GraficoObjetivos } from "@/components/grafico-objetivos";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { useToast } from "@/components/toast";
import { TZ_LIMA, esRolEncargada, esRolIntegrante, puedeVerTodasLasSedes } from "@cayla-dynamic/shared";
import { Boton } from "@/components/ui/boton";
import { Insignia } from "@/components/ui/insignia";
import { Modal } from "@/components/ui/modal";
import { Drawer } from "@/components/ui/drawer";
import { Menu, MenuItem } from "@/components/ui/menu";
import { Campo, CampoCasilla, CampoSelect } from "@/components/ui/campo";
import { AreaTexto } from "@/components/ui/area-texto";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { BotonAyuda } from "@/components/ui/ayuda-pantalla";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { Tabla, TablaEncabezado, Th, Fila } from "@/components/ui/tabla";

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

/** Suma/resta meses a un año/mes calendario, sin `if (mes === 1)` a mano. */
function sumarMeses(anio: number, mes: number, delta: number): { anio: number; mes: number } {
  const d = new Date(Date.UTC(anio, mes - 1 + delta, 1));
  return { anio: d.getUTCFullYear(), mes: d.getUTCMonth() + 1 };
}

function fechaCorta(iso: string): string {
  return new Intl.DateTimeFormat("es-PE", { timeZone: TZ_LIMA, day: "numeric", month: "short" }).format(
    new Date(iso),
  );
}

interface Persona {
  id: string;
  nombres: string;
  apellidos: string;
  rol: string;
  sede_base_id: string;
  sedes: { codigo: string; nombre: string } | null;
}
interface ResumenMes {
  persona_id: string;
  cumplidos: number;
  total: number;
  con_checklist: boolean;
}

// ============================================================================
// Explicación general del módulo — vive en un Modal, no en un párrafo
// permanente: "no pagan nada, sirven de historial para promociones" es algo
// que se lee una vez, no en cada visita.
// ============================================================================
function ModalComoFunciona({ abierto, onCerrar }: { abierto: boolean; onCerrar: () => void }) {
  return (
    <Modal abierto={abierto} onCerrar={onCerrar} titulo="Cómo funcionan los objetivos" ancho="lg">
      <div className="space-y-3 text-sm text-taupe">
        <p>
          Cada persona tiene un checklist de objetivos por mes. <strong className="text-tinta">No pagan
          nada</strong>: son el historial que sostiene una promoción. La política salarial firmada pone
          «cumplió los objetivos que se le asignaron» entre los requisitos para cambiar de categoría, y esa
          política dice que la remuneración solo se mueve por categoría o por un ajuste general de la
          escala — nunca por un objetivo suelto.
        </p>
        <p>
          El cumplimiento del mes se calcula <strong className="text-tinta">por cantidad</strong> de
          objetivos marcados (cumplidos ÷ total), no por su dificultad ni por ningún porcentaje que se
          escriba en el título. Si escribes algo como «(40%)» en un objetivo, es solo texto para quien lo
          lee — no cambia el cálculo.
        </p>
        <p>
          Menos del 30% de cumplimiento marca <strong className="text-tinta">Observación</strong>: un aviso
          para conversar, nunca una sanción automática. La decisión de qué hacer con eso es siempre de una
          persona.
        </p>
        <p>
          Un mes cuya planilla ya fue <strong className="text-tinta">pagada</strong> queda en solo lectura —
          para corregirlo, un administrador reabre ese periodo desde Planilla.
        </p>
      </div>
    </Modal>
  );
}

// ============================================================================
// Bandeja de equipo — vista inicial cuando no hay persona elegida. Solo datos
// de objetivos (no duplica Asistencia/Horas, que ya vive en Desempeño):
// quién no tiene checklist este mes, quién está en observación, quién va a
// medias, quién ya cumplió.
// ============================================================================
function BandejaEquipo({
  personas,
  resumenPorPersona,
  anio,
  mes,
  verTodasLasSedes,
  onElegir,
}: {
  personas: Persona[];
  resumenPorPersona: Map<string, ResumenMes>;
  anio: number;
  mes: number;
  verTodasLasSedes: boolean;
  onElegir: (id: string) => void;
}) {
  const [filtroTexto, setFiltroTexto] = useState("");
  const [filtroSede, setFiltroSede] = useState("");
  const [filtroObjetivos, setFiltroObjetivos] = useState<"todos" | "con" | "sin">("todos");

  const sedes = useMemo(() => {
    const vistas = new Map<string, string>();
    for (const p of personas) if (p.sedes) vistas.set(p.sede_base_id, `${p.sedes.codigo} — ${p.sedes.nombre}`);
    return [...vistas.entries()].sort((a, b) => a[1].localeCompare(b[1]));
  }, [personas]);

  const filas = useMemo(() => {
    return personas.map((p) => {
      const r = resumenPorPersona.get(p.id);
      const cumplidos = r?.cumplidos ?? 0;
      const total = r?.total ?? 0;
      const estado = estadoObjetivos(cumplidos, total);
      // Prioridad de lectura: quien necesita atención primero.
      const prioridad = estado.variante === "alerta" ? 0 : estado.variante === "neutral" ? 1 : estado.variante === "advertencia" ? 2 : 3;
      return { persona: p, cumplidos, total, estado, prioridad };
    });
  }, [personas, resumenPorPersona]);

  const filasVisibles = useMemo(() => {
    const texto = filtroTexto.trim().toLowerCase();
    return filas
      .filter((f) => !filtroSede || f.persona.sede_base_id === filtroSede)
      .filter((f) => filtroObjetivos === "todos" || (filtroObjetivos === "con" ? f.total > 0 : f.total === 0))
      .filter((f) => !texto || `${f.persona.nombres} ${f.persona.apellidos}`.toLowerCase().includes(texto))
      .sort((a, b) => a.prioridad - b.prioridad || a.persona.nombres.localeCompare(b.persona.nombres));
  }, [filas, filtroTexto, filtroSede, filtroObjetivos]);

  const totalPersonas = filas.length;
  const conObjetivos = filas.filter((f) => f.total > 0).length;
  const sinObjetivos = totalPersonas - conObjetivos;
  const enObservacion = filas.filter((f) => f.estado.variante === "alerta").length;

  return (
    <div>
      <TarjetaInfo className="mb-4">
        <p className="mb-3 text-xs font-medium uppercase tracking-wide text-taupe">
          {MESES[mes - 1]} {anio}
        </p>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <div>
            <div className="font-serif text-2xl">{totalPersonas}</div>
            <div className="text-xs text-taupe">personas activas</div>
          </div>
          <div>
            <div className="font-serif text-2xl">{conObjetivos}</div>
            <div className="text-xs text-taupe">con objetivos</div>
          </div>
          <div>
            <div className="font-serif text-2xl">{sinObjetivos}</div>
            <div className="text-xs text-taupe">sin objetivos</div>
          </div>
          <div>
            <div className="font-serif text-2xl text-rojo">{enObservacion}</div>
            <div className="text-xs text-taupe">en observación</div>
          </div>
        </div>
      </TarjetaInfo>

      <div className="mb-3 flex flex-wrap items-end gap-3">
        <Campo
          etiqueta="Buscar persona"
          value={filtroTexto}
          onChange={(e) => setFiltroTexto(e.target.value)}
          placeholder="Nombre…"
          className="min-w-56"
        />
        {verTodasLasSedes && sedes.length > 1 && (
          <CampoSelect etiqueta="Sede" value={filtroSede} onChange={(e) => setFiltroSede(e.target.value)}>
            <option value="">Todas</option>
            {sedes.map(([id, etiqueta]) => (
              <option key={id} value={id}>
                {etiqueta}
              </option>
            ))}
          </CampoSelect>
        )}
        <CampoSelect
          etiqueta="Objetivos"
          value={filtroObjetivos}
          onChange={(e) => setFiltroObjetivos(e.target.value as "todos" | "con" | "sin")}
        >
          <option value="todos">Todos</option>
          <option value="con">Con objetivos</option>
          <option value="sin">Sin objetivos</option>
        </CampoSelect>
      </div>

      <Tabla>
        <TablaEncabezado>
          <Th>Persona</Th>
          {verTodasLasSedes && <Th>Sede</Th>}
          <Th className="text-right">Objetivos</Th>
          <Th className="text-right">Cumplimiento</Th>
          <Th>Estado</Th>
        </TablaEncabezado>
        <tbody>
          {filasVisibles.length === 0 ? (
            <tr>
              <td colSpan={verTodasLasSedes ? 5 : 4} className="px-4 py-6 text-center text-sm text-taupe">
                {filas.length === 0 ? "No hay personas activas." : "Nadie coincide con estos filtros."}
              </td>
            </tr>
          ) : (
            filasVisibles.map((f) => (
              <Fila key={f.persona.id}>
                <td className="px-4 py-2.5">
                  <button
                    onClick={() => onElegir(f.persona.id)}
                    className="text-left font-medium text-tinta hover:underline"
                  >
                    {f.persona.nombres} {f.persona.apellidos}
                  </button>
                </td>
                {verTodasLasSedes && (
                  <td className="px-4 py-2.5 text-taupe">{f.persona.sedes?.codigo ?? "—"}</td>
                )}
                <td className="px-4 py-2.5 text-right text-taupe">{f.total > 0 ? `${f.cumplidos}/${f.total}` : "—"}</td>
                <td className="px-4 py-2.5 text-right text-taupe">
                  {f.total > 0 ? `${Math.round((f.cumplidos / f.total) * 100)}%` : "—"}
                </td>
                <td className="px-4 py-2.5">
                  <Insignia variante={f.estado.variante} tamano="sm">
                    {f.estado.texto}
                  </Insignia>
                </td>
              </Fila>
            ))
          )}
        </tbody>
      </Tabla>
    </div>
  );
}

// ============================================================================
// Tarjeta compacta de un objetivo — expandible. El checklist entero se lee
// de un vistazo; el detalle (indicaciones + autoría) se abre solo si hace falta.
// ============================================================================
function TarjetaObjetivo({
  item,
  puedeGestionar,
  nombrePorId,
  onMarcar,
  onEditar,
  onEliminar,
}: {
  item: ObjetivoItem;
  puedeGestionar: boolean;
  nombrePorId: Map<string, string>;
  onMarcar: (item: ObjetivoItem, cumplido: boolean) => void;
  onEditar: (item: ObjetivoItem, boton: HTMLElement) => void;
  onEliminar: (item: ObjetivoItem) => void;
}) {
  const [abierto, setAbierto] = useState(false);

  const creadoPor = item.creado_por ? nombrePorId.get(item.creado_por) : null;
  const actualizadoPor = item.actualizado_por ? nombrePorId.get(item.actualizado_por) : null;
  const mismoAutor = item.creado_por === item.actualizado_por;

  return (
    <li className="px-4 py-3">
      <div className="flex items-start gap-3">
        <CampoCasilla
          checked={item.cumplido}
          disabled={!puedeGestionar}
          onChange={(e) => onMarcar(item, e.target.checked)}
          aria-label={`Marcar "${item.descripcion}" como cumplido`}
          className="mt-1"
        />
        <div className="min-w-0 flex-1">
          <div className="flex items-baseline justify-between gap-2">
            <span className={`text-sm ${item.cumplido ? "text-taupe line-through" : "text-tinta"}`}>
              {item.descripcion}
            </span>
            <Insignia variante={item.cumplido ? "positivo" : "neutral"} atenuada={!item.cumplido} tamano="sm">
              {item.cumplido ? "Cumplido" : "Pendiente"}
            </Insignia>
          </div>

          {item.indicaciones && !abierto && (
            <p className="mt-0.5 truncate text-xs text-taupe">{item.indicaciones.split("\n")[0]}</p>
          )}

          <div className="mt-1.5 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs">
            {item.indicaciones && (
              <button
                onClick={() => setAbierto((a) => !a)}
                className="inline-flex items-center gap-1 text-taupe hover:text-tinta"
              >
                {abierto ? <ChevronUp size={12} /> : <ChevronDown size={12} />}
                Ver detalles
              </button>
            )}
            {puedeGestionar && (
              <>
                <Boton
                  tamano="sm"
                  variante="sutil"
                  onClick={(e) => onEditar(item, e.currentTarget)}
                  className="px-2 py-0.5"
                >
                  Editar
                </Boton>
                <Menu
                  alinear="derecha"
                  trigger={({ alternar }) => (
                    <button
                      onClick={alternar}
                      aria-label="Más acciones sobre este objetivo"
                      className="rounded-control p-1 text-taupe hover:bg-sand/50 hover:text-tinta"
                    >
                      <MoreHorizontal size={16} />
                    </button>
                  )}
                >
                  <MenuItem variante="peligro" onClick={() => onEliminar(item)}>
                    Eliminar objetivo
                  </MenuItem>
                </Menu>
              </>
            )}
          </div>

          {abierto && (
            <div className="mt-2 space-y-2">
              {item.indicaciones && (
                <p className="whitespace-pre-wrap rounded-control bg-hueso/60 p-3 text-xs text-taupe">
                  {item.indicaciones}
                </p>
              )}
              {creadoPor && (
                <p className="text-[11px] text-taupe/70">
                  Creado por {creadoPor} el {fechaCorta(item.creado_at)}
                  {!mismoAutor && actualizadoPor && (
                    <> · última edición de {actualizadoPor} el {fechaCorta(item.actualizado_at)}</>
                  )}
                </p>
              )}
            </div>
          )}
        </div>
      </div>
    </li>
  );
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
  const sp = useSearchParams();
  const personaEnlace = sp.get("persona");
  const anioEnlace = Number(sp.get("anio"));
  const mesEnlace = Number(sp.get("mes"));

  const [personas, setPersonas] = useState<Persona[]>([]);
  // Estado crudo de lo que la persona ELIGIÓ. Cuando está vacío y solo hay
  // una persona visible (el caso integrante, que solo se ve a sí misma), se
  // deriva más abajo en vez de auto-seleccionar con un efecto — un valor que
  // se puede calcular a partir de otro no necesita su propio setState.
  const [personaIdElegida, setPersonaIdElegida] = useState(personaEnlace ?? "");
  const [anio, setAnio] = useState(Number.isInteger(anioEnlace) && anioEnlace > 2000 ? anioEnlace : hoy.anio);
  const [mes, setMes] = useState(Number.isInteger(mesEnlace) && mesEnlace >= 1 && mesEnlace <= 12 ? mesEnlace : hoy.mes);
  const [items, setItems] = useState<ObjetivoItem[]>([]);
  const [resumen, setResumen] = useState<ResumenMes[]>([]);
  const [mesPagado, setMesPagado] = useState(false);
  const [historial, setHistorial] = useState<MesHistorial[]>([]);
  const [rangoHistorial, setRangoHistorial] = useState(12);
  // La clave (persona|año|mes) del último `cargar()` que terminó — "cargado"
  // se deriva comparándola contra la clave actual, en vez de un booleano que
  // un efecto tendría que resetear a mano en cada cambio de selección.
  const [claveCargada, setClaveCargada] = useState<string | null>(null);
  const [infoAbierto, setInfoAbierto] = useState(false);

  // Drawer compartido para crear/editar — mismos campos, RPC distinta.
  const [drawer, setDrawer] = useState<{ modo: "crear" } | { modo: "editar"; item: ObjetivoItem } | null>(null);
  const [tituloForm, setTituloForm] = useState("");
  const [indicacionesForm, setIndicacionesForm] = useState("");
  const [guardando, setGuardando] = useState(false);
  const focoRetornoRef = useRef<HTMLElement | null>(null);

  const [copiando, setCopiando] = useState(false);
  const [prevMes, setPrevMes] = useState<{ personaId: string; anio: number; mes: number; items: ObjetivoItem[] } | null>(
    null,
  );

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
        .select("id, nombres, apellidos, rol, sede_base_id, sedes:sede_base_id(codigo, nombre)")
        .eq("estado", "activo").eq("cuenta_de_servicio", false)
        .order("nombres");
      setPersonas((p as unknown as Persona[]) ?? []);
    });
  }, [router]);

  // Si solo me veo a mí (integrante), autoseleccionarme — derivado, no vía
  // efecto: es un valor calculable a partir de `personas`, no un estado propio.
  const personaId = personaIdElegida || (personas.length === 1 ? personas[0].id : "");
  const setPersonaId = setPersonaIdElegida;

  const persona = personas.find((p) => p.id === personaId);
  const nombrePorId = useMemo(() => {
    const m = new Map<string, string>();
    for (const p of personas) m.set(p.id, `${p.nombres} ${p.apellidos}`);
    return m;
  }, [personas]);

  const verTodasLasSedes = rol !== null && puedeVerTodasLasSedes(rol);

  // admin/líder gestionan a cualquiera; la encargada SOLO integrantes de su
  // sede (los objetivos de las encargadas los gestiona admin/líder). El
  // servidor re-valida esto mismo en cada RPC.
  const tienePermisoDeRol = useMemo(() => {
    if (!persona || rol === null) return false;
    if (verTodasLasSedes) return true;
    if (esRolEncargada(rol) && yo) return esRolIntegrante(persona.rol) && persona.sede_base_id === yo.sedeBaseId;
    return false;
  }, [persona, rol, yo, verTodasLasSedes]);
  const puedeGestionar = tienePermisoDeRol && !mesPagado;

  // Resumen del mes (para la bandeja de equipo Y el aviso de "registro
  // manual sin checklist") — independiente de qué persona esté elegida.
  // `cargarResumen` la usan los manejadores de abajo para refrescar la
  // bandeja después de mutar algo (agregar/marcar/editar/eliminar/copiar);
  // el efecto de mount/cambio de mes no la llama, mismo motivo que `cargar`.
  const cargarResumen = useCallback(async () => {
    const { data } = await createAdminSupabaseClient().rpc("fn_objetivos_resumen", { p_anio: anio, p_mes: mes });
    setResumen((data as unknown as ResumenMes[] | null) ?? []);
  }, [anio, mes]);

  useEffect(() => {
    let cancelado = false;
    createAdminSupabaseClient()
      .rpc("fn_objetivos_resumen", { p_anio: anio, p_mes: mes })
      .then(({ data }) => {
        if (!cancelado) setResumen((data as unknown as ResumenMes[] | null) ?? []);
      });
    return () => {
      cancelado = true;
    };
  }, [anio, mes]);
  const resumenPorPersona = useMemo(() => new Map(resumen.map((r) => [r.persona_id, r])), [resumen]);

  // Función reusable para los manejadores de abajo (marcar, guardar, borrar,
  // copiar) que necesitan refrescar DESPUÉS de mutar algo. El efecto de
  // mount/cambio de selección, justo abajo, NO LA LLAMA — referenciar una
  // función useCallback desde un efecto dispara el lint set-state-in-effect
  // (mismo motivo que ya vale para cargarHistorial, ver su comentario) — pide
  // los mismos datos en línea.
  const cargar = useCallback(async () => {
    if (!personaId) return;
    const clave = `${personaId}|${anio}|${mes}`;
    const supabase = createAdminSupabaseClient();
    const [{ data, error }, { data: pagado }] = await Promise.all([
      supabase.rpc("fn_objetivos_checklist", { p_anio: anio, p_mes: mes, p_persona_id: personaId }),
      supabase.rpc("fn_mes_planilla_pagado", { p_anio: anio, p_mes: mes }),
    ]);
    if (error) {
      avisar("error", mensajeDeError(error));
    } else {
      setItems(((data as unknown as ObjetivoItem[] | null) ?? []).slice());
      setMesPagado(pagado === true);
    }
    setClaveCargada(clave);
  }, [personaId, anio, mes, avisar]);

  // "cargado" se deriva comparando la clave del último fetch que terminó
  // contra la selección actual; "cargando" (el spinner de página completa)
  // se deriva de lo mismo — ninguno de los dos necesita su propio setState.
  const claveActual = personaId ? `${personaId}|${anio}|${mes}` : null;
  const cargado = claveActual !== null && claveCargada === claveActual;
  const cargando = personaId !== "" && !cargado;

  useEffect(() => {
    if (!personaId) return;
    let cancelado = false;
    const clave = `${personaId}|${anio}|${mes}`;
    const supabase = createAdminSupabaseClient();
    // objetivos_items NUNCA se lee por REST (schema cache de PostgREST trabado):
    // solo vía RPC jsonb, patrón 0020.
    Promise.all([
      supabase.rpc("fn_objetivos_checklist", { p_anio: anio, p_mes: mes, p_persona_id: personaId }),
      // El servidor SÍ bloquea escribir sobre un mes con planilla pagada
      // (fn_mes_planilla_pagado); esto solo lo trae al cliente para avisar
      // ANTES de que alguien intente editar, no después con un toast de error.
      supabase.rpc("fn_mes_planilla_pagado", { p_anio: anio, p_mes: mes }),
    ]).then(([{ data, error }, { data: pagado }]) => {
      if (cancelado) return;
      if (error) {
        avisar("error", mensajeDeError(error));
      } else {
        setItems(((data as unknown as ObjetivoItem[] | null) ?? []).slice());
        setMesPagado(pagado === true);
      }
      setClaveCargada(clave);
    });
    return () => {
      cancelado = true;
    };
  }, [personaId, anio, mes, avisar]);

  // El historial se pide aparte: cambiar el rango (6/12/24 meses) no debe
  // reiniciar toda la pantalla a "Cargando…", solo refrescar el gráfico.
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

  // Vista previa de "Copiar del mes anterior" — se pide solo cuando hace
  // falta (mes vacío y con permiso), nunca cambia la regla del servidor. Sin
  // resetear `prevMes` a mano: lo que se MUESTRA se deriva más abajo
  // (prevMesMostrar), comparando contra la selección actual — así un fetch
  // en vuelo de una persona/mes anterior nunca se pinta encima de otra.
  useEffect(() => {
    if (!personaId || !cargado || items.length > 0 || !puedeGestionar) return;
    const { anio: pAnio, mes: pMes } = sumarMeses(anio, mes, -1);
    let cancelado = false;
    createAdminSupabaseClient()
      .rpc("fn_objetivos_checklist", { p_anio: pAnio, p_mes: pMes, p_persona_id: personaId })
      .then(({ data }) => {
        if (cancelado) return;
        setPrevMes({ personaId, anio: pAnio, mes: pMes, items: (data as unknown as ObjetivoItem[] | null) ?? [] });
      });
    return () => {
      cancelado = true;
    };
  }, [personaId, cargado, items.length, puedeGestionar, anio, mes]);

  const prevMesClave = sumarMeses(anio, mes, -1);
  const necesitaPrevMes = Boolean(personaId && cargado && items.length === 0 && puedeGestionar);
  const prevMesMostrar =
    necesitaPrevMes &&
    prevMes && prevMes.personaId === personaId && prevMes.anio === prevMesClave.anio && prevMes.mes === prevMesClave.mes
      ? prevMes
      : null;
  // Se deriva de lo mismo que decide si hace falta pedirlo, en vez de su
  // propio setState: "necesita el mes anterior y todavía no lo tenemos".
  const cargandoPrevMes = necesitaPrevMes && !prevMesMostrar;

  function abrirCrear(boton: HTMLElement) {
    focoRetornoRef.current = boton;
    setTituloForm("");
    setIndicacionesForm("");
    setDrawer({ modo: "crear" });
  }

  function abrirEditar(item: ObjetivoItem, boton: HTMLElement) {
    focoRetornoRef.current = boton;
    setTituloForm(item.descripcion);
    setIndicacionesForm(item.indicaciones ?? "");
    setDrawer({ modo: "editar", item });
  }

  async function guardarDrawer() {
    const texto = tituloForm.trim();
    if (!texto) {
      avisar("error", "Escribe el objetivo antes de guardarlo.");
      return;
    }
    if (!drawer) return;
    setGuardando(true);
    const supabase = createAdminSupabaseClient();
    const { error } =
      drawer.modo === "crear"
        ? await supabase.rpc("fn_objetivo_agregar", {
            p_persona_id: personaId,
            p_anio: anio,
            p_mes: mes,
            p_descripcion: texto,
            p_indicaciones: indicacionesForm.trim() || null,
          })
        : await supabase.rpc("fn_objetivo_editar", {
            p_item_id: drawer.item.id,
            p_descripcion: texto,
            p_indicaciones: indicacionesForm.trim() || null,
          });
    setGuardando(false);
    if (error) {
      avisar("error", mensajeDeError(error, drawer.modo === "crear" ? "agregar" : "editar"));
      return;
    }
    avisar("ok", drawer.modo === "crear" ? "Objetivo agregado." : "Objetivo actualizado.");
    setDrawer(null);
    await cargar();
    await cargarHistorial();
    await cargarResumen();
  }

  async function marcar(item: ObjetivoItem, cumplido: boolean) {
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_objetivo_marcar", { p_item_id: item.id, p_cumplido: cumplido });
    if (error) {
      avisar("error", mensajeDeError(error, "marcar"));
      // El checkbox es un input nativo: el navegador ya invirtió su estado
      // visual al hacer clic, antes de que este onChange corriera. Forzar una
      // copia nueva del array re-sincroniza el checkbox con item.cumplido,
      // que nunca cambió en el servidor.
      setItems((prev) => [...prev]);
      return;
    }
    await cargar();
    await cargarHistorial();
    await cargarResumen();
  }

  async function copiarMesAnterior() {
    if (copiando || !prevMesMostrar) return;
    const cuantos = prevMesMostrar.items.length;
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
    avisar("ok", `${cuantos} objetivo${cuantos === 1 ? "" : "s"} copiado${cuantos === 1 ? "" : "s"}, sin marcar.`);
    await cargar();
    await cargarHistorial();
    await cargarResumen();
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
    await cargarResumen();
  }

  const cumplidos = items.filter((i) => i.cumplido).length;
  const total = items.length;
  const estado = estadoObjetivos(cumplidos, total);
  const pct = total > 0 ? Math.round((cumplidos / total) * 100) : 0;

  // Aviso: el mes tiene un número manual (de Planilla) y todavía no hay checklist.
  const registroManual = resumen.find((r) => r.persona_id === personaId && !r.con_checklist);

  const mesLabel = `${MESES[mes - 1]} ${anio}`;
  const prevMesLabel = `${MESES[prevMesClave.mes - 1].toLowerCase()} ${prevMesClave.anio}`;

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6">
        <div className="mx-auto w-full max-w-5xl">
          <CabeceraPagina
            titulo="Objetivos"
            descripcion="Define y da seguimiento a los compromisos mensuales del equipo."
            ayuda={<BotonAyuda etiqueta="Cómo funcionan los objetivos" onClick={() => setInfoAbierto(true)} />}
          />

          {/* Periodo: contexto global — navegación mes a mes, y salto directo. */}
          <div className="mb-6 flex flex-wrap items-end gap-4">
            <div className="flex items-end gap-1">
              <Boton
                variante="sutil"
                tamano="sm"
                className="mb-[3px] px-2"
                onClick={() => {
                  const p = sumarMeses(anio, mes, -1);
                  setAnio(p.anio);
                  setMes(p.mes);
                }}
                aria-label="Mes anterior"
              >
                <ChevronLeft size={14} />
              </Boton>
              <span className="min-w-40 pb-2 text-center font-serif text-lg capitalize">{mesLabel.toLowerCase()}</span>
              <Boton
                variante="sutil"
                tamano="sm"
                className="mb-[3px] px-2"
                onClick={() => {
                  const s = sumarMeses(anio, mes, 1);
                  setAnio(s.anio);
                  setMes(s.mes);
                }}
                aria-label="Mes siguiente"
              >
                <ChevronRight size={14} />
              </Boton>
            </div>
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

            {personaId && (
              <CampoSelect
                etiqueta="Cambiar persona"
                value={personaId}
                onChange={(e) => setPersonaId(e.target.value)}
                className="min-w-56"
              >
                {personas.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.nombres} {p.apellidos}
                  </option>
                ))}
              </CampoSelect>
            )}
          </div>

          {!personaId ? (
            <BandejaEquipo
              personas={personas}
              resumenPorPersona={resumenPorPersona}
              anio={anio}
              mes={mes}
              verTodasLasSedes={verTodasLasSedes}
              onElegir={setPersonaId}
            />
          ) : cargando ? (
            <Cargando />
          ) : cargado ? (
            <div>
              {/* Cabecera de la persona + acción principal */}
              <div className="mb-4 flex flex-wrap items-start justify-between gap-3">
                <div>
                  <h2 className="font-serif text-xl">
                    {persona?.nombres} {persona?.apellidos}
                  </h2>
                  {persona?.sedes && <p className="text-sm text-taupe">{persona.sedes.nombre}</p>}
                </div>
                <div className="flex items-center gap-2">
                  <Boton variante="sutil" tamano="sm" onClick={() => setPersonaId("")}>
                    ← Ver a todo el equipo
                  </Boton>
                  {puedeGestionar && (
                    <Boton
                      variante="primario"
                      tamano="sm"
                      onClick={(e) => abrirCrear(e.currentTarget)}
                    >
                      + Nuevo objetivo
                    </Boton>
                  )}
                </div>
              </div>

              {mesPagado && tienePermisoDeRol && (
                <BannerAviso
                  variante="advertencia"
                  titulo={
                    <span className="inline-flex items-center gap-1.5">
                      <Lock size={16} aria-hidden /> {mesLabel} está cerrado
                    </span>
                  }
                  className="mb-4"
                >
                  La planilla de este periodo ya fue pagada. Los objetivos están en modo solo lectura. Para
                  corregir, un administrador reabre el periodo desde{" "}
                  <a href="/admin/planilla" className="underline">
                    Planilla
                  </a>
                  .
                </BannerAviso>
              )}
              {!tienePermisoDeRol && persona && (
                <BannerAviso variante="neutral" className="mb-4">
                  Solo lectura.{" "}
                  {esRolEncargada(rol)
                    ? "Como líder de equipo gestionas los objetivos de los integrantes de tu sede; los demás los gestiona un administrador."
                    : "Los objetivos los marca tu líder de equipo o un administrador."}
                </BannerAviso>
              )}
              {registroManual && total === 0 && (
                <BannerAviso variante="advertencia" className="mb-4">
                  Este mes tiene un registro manual de {registroManual.cumplidos}/{registroManual.total} (puesto
                  desde Planilla). Al agregar el primer objetivo del checklist, el checklist pasa a mandar y ese
                  número se recalcula.
                </BannerAviso>
              )}

              {/* Resumen de cumplimiento — compacto */}
              <TarjetaInfo className="mb-4">
                <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
                  <span className="text-sm">
                    <span className="font-serif text-xl">{cumplidos}</span>
                    <span className="text-taupe"> de </span>
                    <span className="font-serif text-xl">{total}</span>
                    <span className="text-taupe"> cumplidos{total > 0 ? ` (${pct}%)` : ""}</span>
                  </span>
                  <span
                    title={
                      estado.variante === "alerta"
                        ? "Cumplimiento por debajo del umbral definido. Requiere revisión o conversación — no genera medidas automáticas."
                        : undefined
                    }
                  >
                    <Insignia variante={estado.variante} tamano="sm">
                      {estado.texto}
                    </Insignia>
                  </span>
                </div>
                <div className="h-2 overflow-hidden rounded-pildora bg-sand">
                  <div
                    className={`h-full rounded-pildora transition-all ${CLASE_BG_NIVEL[nivelColorObjetivos(cumplidos, total)]}`}
                    style={{ width: `${pct}%` }}
                  />
                </div>
              </TarjetaInfo>

              {/* Objetivos del mes — antes del histórico: lo primero es qué toca hacer HOY */}
              <ul className="mb-4 divide-y divide-sand rounded-superficie border border-sand bg-papel">
                {items.length === 0 ? (
                  <li className="flex flex-col items-center gap-3 px-4 py-8 text-center">
                    <p className="text-sm text-taupe">
                      {persona?.nombres} todavía no tiene objetivos para {mesLabel.toLowerCase()}.
                    </p>
                    {puedeGestionar && (
                      <div className="flex flex-wrap items-center justify-center gap-2">
                        <Boton variante="primario" tamano="sm" onClick={(e) => abrirCrear(e.currentTarget)}>
                          + Crear primer objetivo
                        </Boton>
                        <Boton
                          tamano="sm"
                          onClick={() => void copiarMesAnterior()}
                          disabled={copiando || cargandoPrevMes || !prevMesMostrar || prevMesMostrar.items.length === 0}
                          cargando={copiando}
                        >
                          {cargandoPrevMes
                            ? "Revisando el mes anterior…"
                            : prevMesMostrar && prevMesMostrar.items.length > 0
                              ? `Copiar ${prevMesMostrar.items.length} de ${prevMesLabel}`
                              : `Sin objetivos en ${prevMesLabel} para copiar`}
                        </Boton>
                      </div>
                    )}
                    {puedeGestionar && prevMesMostrar && prevMesMostrar.items.length > 0 && (
                      <div className="mt-1 max-w-md text-left text-xs text-taupe">
                        <p className="mb-1">Se copiarán, sin marcar cumplido:</p>
                        <ul className="list-inside list-disc space-y-0.5">
                          {prevMesMostrar.items.map((i) => (
                            <li key={i.id} className="truncate">
                              {i.descripcion}
                            </li>
                          ))}
                        </ul>
                      </div>
                    )}
                  </li>
                ) : (
                  items.map((item) => (
                    <TarjetaObjetivo
                      key={item.id}
                      item={item}
                      puedeGestionar={puedeGestionar}
                      nombrePorId={nombrePorId}
                      onMarcar={marcar}
                      onEditar={abrirEditar}
                      onEliminar={setAEliminar}
                    />
                  ))
                )}
              </ul>

              {/* Histórico — contexto secundario, después de lo que toca este mes */}
              {historial.some((m) => m.total > 0) && (
                <TarjetaInfo className="mb-4">
                  <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
                    <p className="text-xs font-medium text-taupe">Historial de cumplimiento</p>
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
            </div>
          ) : null}

          {/* Drawer compartido: crear / editar objetivo */}
          <Drawer
            abierto={drawer !== null}
            onCerrar={() => setDrawer(null)}
            bloqueado={guardando}
            titulo={drawer?.modo === "editar" ? "Editar objetivo" : "Nuevo objetivo"}
            volverElFocoA={focoRetornoRef}
          >
            <div className="flex flex-col gap-4">
              <Campo
                etiqueta="Título"
                value={tituloForm}
                onChange={(e) => setTituloForm(e.target.value)}
                placeholder="ej. Completar la capacitación de atención al cliente"
                maxLength={300}
                autoFocus
              />
              <AreaTexto
                etiqueta="Indicaciones (opcional)"
                value={indicacionesForm}
                onChange={(e) => setIndicacionesForm(e.target.value)}
                placeholder="El detalle que ayuda a cumplirlo: qué se espera, cómo se mide, con quién coordinar"
                maxLength={2000}
                rows={4}
              />
              <p className="text-xs text-taupe">
                El cumplimiento del mes se calcula por cantidad de objetivos marcados, no por un porcentaje
                escrito acá.
              </p>
              <div className="flex justify-end gap-2">
                <Boton onClick={() => setDrawer(null)} disabled={guardando}>
                  Cancelar
                </Boton>
                <Boton variante="primario" onClick={() => void guardarDrawer()} cargando={guardando}>
                  {drawer?.modo === "editar" ? "Guardar cambios" : "Agregar"}
                </Boton>
              </div>
            </div>
          </Drawer>

          {/* Confirmar eliminación */}
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
                  ¿Eliminar el objetivo «{aEliminar.descripcion}»? Desaparece del checklist de {mesLabel.toLowerCase()}{" "}
                  y no se puede deshacer desde aquí.
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

          <ModalComoFunciona abierto={infoAbierto} onCerrar={() => setInfoAbierto(false)} />
        </div>
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
