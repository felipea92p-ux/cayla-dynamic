"use client";

import { Suspense, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Cargando } from "@/components/cargando";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { useToast } from "@/components/toast";
import { subirArchivoConProgreso } from "@/lib/subir-archivo";
import { abrirArchivoFirmado } from "@/lib/abrir-archivo-firmado";
import {
  ESTADO_CONSTANCIA, ESTADO_ENTREGA, ESTADO_SOLICITUD, FRECUENCIAS_PAGO, FRECUENCIA_PAGO_LABELS,
  MOTIVO_RECHAZO_LABELS, TIPOS_CONSTANCIA, TIPO_CONSTANCIA_LABELS, hoyLima, problemaDeArchivo,
  puedeVerPlanilla, sugerirProximaFecha,
  type EstadoSolicitud, type FrecuenciaPago, type TipoConstancia,
} from "@cayla-dynamic/shared";
import {
  BUCKET_COMPROBANTES, elegido, fechaCorta, subirArchivosDeEntrega, type ArchivoElegido,
} from "@/lib/educacion";
import { generarCsv, descargarCsv } from "@/lib/admin/csv";
import {
  GRUPOS_EDUCACION, estadoParaMostrar, grupoDeEstudio, nivelesDeApoyo, personasSinSolicitar, type GrupoEducacion,
} from "@/lib/admin/educacion-grupos";
import {
  CLAVES_DE_URL, FILTROS_VACIOS, MESES_INICIALES, MESES_POR_PASO, agruparEstudios, conteoTarjetas, entregaPasaFiltros,
  entregasDeEstudio, filtrosAUrl, filtrosDeUrl, mesDe, mesLargo, mesesConConstancia, mesesEntre,
  montoMensual, pasaFiltros, resumenPorSede, sedesDe, ventanaDeMeses, type ContextoDeFiltros, type Estudio, type Filtros,
} from "@/lib/admin/educacion-meses";
import { fechaHora, soles } from "@/lib/admin/educacion-formato";
import type { Entrega, EntregaDeFamilia, Pendiente, Situacion } from "@/lib/admin/educacion-tipos";
import { armarZip, descargarBlob, nombreLegible } from "@/lib/admin/zip-constancias";
import { Boton } from "@/components/ui/boton";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { AreaTexto } from "@/components/ui/area-texto";
import { Cifra } from "@/components/ui/cifra";
import { EstadoVacio } from "@/components/ui/estado-vacio";
import { Insignia } from "@/components/ui/insignia";
import { Modal } from "@/components/ui/modal";
import { Drawer } from "@/components/ui/drawer";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { BarraFiltros } from "@/components/educacion/barra-filtros";
import { CuadriculaMeses } from "@/components/educacion/cuadricula-meses";
import { LienzoArchivos } from "@/components/educacion/lienzo-archivos";
import { AccionesRevision } from "@/components/educacion/revision-entrega";
import { VisorConstancia } from "@/components/educacion/visor-constancia";

// ============================================================================
// Educación — los apoyos y las constancias que los sustentan (0450).
// ----------------------------------------------------------------------------
// DOS COSAS QUE ANTES COMPARTÍAN UNA COLUMNA, AHORA SEPARADAS:
//   BENEFICIO   la asignación: institución, monto, vigencia, calendario de pagos.
//   CONSTANCIA  la evidencia de cada pago: su estado, sus archivos, su revisión.
// La columna «Vigencia» decía a la vez «vence en 0 días» (el beneficio) y «pide
// el papel nuevo» (la constancia), en rojo, para una renovación normal.
//
// EL ESTADO NO SE CALCULA ACÁ: lo contesta fn_educacion_situacion, la misma
// que leen el portal, la Bandeja y el contador del menú.
//
// La asignación por educación (art. 19 f) D.S. 001-97-TR) no es remuneración
// SIEMPRE QUE esté sostenida por un comprobante. Aprobar o rechazar una
// constancia NO cambia lo que se paga (decisión «solo alerta», 2026-09-15).
// ============================================================================

interface SolicitudPendiente {
  id: string;
  persona_id: string;
  persona: string;
  sede: string;
  institucion: string;
  costo_declarado: number;
  vigente_desde: string;
  vigente_hasta: string;
  enviada_at: string;
  comprobante_url: string | null;
}

/**
 * Una solicitud YA RESUELTA (aprobada o rechazada). Aparte de la pendiente:
 * si se rechaza a alguien sin ninguna asignación, esa persona no vuelve a
 * aparecer en ningún lado — sin este historial, DO no tiene forma de
 * consultar qué pasó con ella.
 */
interface SolicitudHistorial {
  id: string;
  persona: string;
  institucion: string;
  costo_declarado: number;
  estado: EstadoSolicitud;
  enviada_at: string;
  revisada_at: string | null;
  motivo_rechazo: string | null;
}

/** Lo que el formulario de alta/corrección necesita y la situación no trae. */
interface Asignacion {
  id: string;
  persona_id: string;
  persona: string;
  institucion: string;
  costo_declarado: number;
  beneficiario: "trabajador" | "hijo";
  beneficiario_nombre: string | null;
  comprobante_url: string | null;
  vigente_desde: string;
  vigente_hasta: string;
  nota: string | null;
}

interface Candidato { persona_id: string; persona: string; sede: string; rango: string; tope: number | null }

interface Form {
  personaId: string;
  institucion: string;
  costoDeclarado: string;
  beneficiario: "trabajador" | "hijo";
  beneficiarioNombre: string;
  vigenteDesde: string;
  vigenteHasta: string;
  frecuencia: FrecuenciaPago | "";
  primeraFechaPago: string;
  nota: string;
  motivo: string;
}

const COBERTURA = 75;
const FORM_VACIO: Form = {
  personaId: "", institucion: "", costoDeclarado: "", beneficiario: "trabajador", beneficiarioNombre: "",
  vigenteDesde: "", vigenteHasta: "", frecuencia: "", primeraFechaPago: "", nota: "", motivo: "",
};
// Respaldo si la consulta del límite falla (fn_educacion_limite_comprobante, 0154).
const LIMITE_RESPALDO = { bytes: 10 * 1024 * 1024, tipos: "image/jpeg,image/png,application/pdf" };

function EducacionContenido() {
  const router = useRouter();
  const params = useSearchParams();
  const persona = usePersonaActual();
  const rol = persona?.rol ?? null;
  const puedeGestionar = puedeVerPlanilla(rol);
  const { avisar } = useToast();
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const hoy = hoyLima();

  const [situaciones, setSituaciones] = useState<Situacion[]>([]);
  const [pendientes, setPendientes] = useState<Pendiente[]>([]);
  const [solicitudesPendientes, setSolicitudesPendientes] = useState<SolicitudPendiente[]>([]);
  const [historialSolicitudes, setHistorialSolicitudes] = useState<SolicitudHistorial[] | null>(null);
  const [cargandoHistorialSol, setCargandoHistorialSol] = useState(false);
  const [asignaciones, setAsignaciones] = useState<Map<string, Asignacion>>(new Map());
  const [liquidadas, setLiquidadas] = useState<Set<string>>(new Set());
  const [candidatos, setCandidatos] = useState<Candidato[]>([]);
  const [limite, setLimite] = useState(LIMITE_RESPALDO);
  const [config, setConfig] = useState({ texto: "", plazo: 5, avisoColab: 7, avisoDo: 7 });
  const [cargando, setCargando] = useState(true);
  const [cargaError, setCargaError] = useState<string | null>(null);

  // Filtros: un solo objeto. Los que definen QUÉ conjunto se mira (sede, mes, estado…) viajan en
  // la dirección, para poder pasarle a alguien «las constancias de AQP en setiembre» como un enlace.
  const [filtros, setFiltros] = useState<Filtros>(() => filtrosDeUrl(params));
  const cambiar = useCallback((parcial: Partial<Filtros>) => setFiltros((f) => ({ ...f, ...parcial })), []);
  const [mesesPedidos, setMesesPedidos] = useState(MESES_INICIALES);
  const [descargando, setDescargando] = useState(false);

  // Las constancias de TODOS los estudios, para dibujar la cuadrícula de meses. null = todavía llegando.
  const [entregasPorFamilia, setEntregasPorFamilia] = useState<Map<string, EntregaDeFamilia[]> | null>(null);
  const [errorConstancias, setErrorConstancias] = useState<string | null>(null);

  // El visor grande de constancias. `visor` se conserva al cerrar para que se vea irse con su contenido.
  const [visor, setVisor] = useState<{ clave: string; entregaId: string | null } | null>(null);
  const [visorAbierto, setVisorAbierto] = useState(false);

  // Panel lateral
  const [abierta, setAbierta] = useState<string | null>(null);
  const [entregaFoco, setEntregaFoco] = useState<string | null>(null);
  const botonQueAbrio = useRef<HTMLElement | null>(null);
  const botonRegistrar = useRef<HTMLElement | null>(null);

  // Panel de una solicitud de apoyo (0461): vive aparte del de arriba porque
  // todavía no hay ninguna asignación/familia a la que colgarlo.
  const [solicitudAbierta, setSolicitudAbierta] = useState<string | null>(null);
  const botonSolicitud = useRef<HTMLElement | null>(null);

  // Formulario de alta/corrección
  const [mostrandoForm, setMostrandoForm] = useState(false);
  const [editandoId, setEditandoId] = useState<string | null>(null);
  const [form, setForm] = useState<Form>(FORM_VACIO);
  const [archivo, setArchivo] = useState<File | null>(null);
  const [guardando, setGuardando] = useState(false);
  const [progreso, setProgreso] = useState<number | null>(null);
  const [saldo, setSaldo] = useState<number | null | undefined>(undefined);
  const [configAbierta, setConfigAbierta] = useState(false);

  // Una consulta por estudio (`fn_educacion_entregas` se pide por familia), de a seis: es la misma
  // función que usa el panel, así que el permiso lo decide la base y no esta pantalla. Mientras
  // llega, la cuadrícula muestra casillas en espera; al recargar tras aprobar, deja las viejas
  // a la vista hasta que lleguen las nuevas, para que no parpadee.
  const cargaVigente = useRef(0);
  const cargarConstancias = useCallback(async (filas: Situacion[]) => {
    const mia = ++cargaVigente.current;
    const mapa = new Map<string, EntregaDeFamilia[]>();
    const cola = [...filas];
    let fallos = 0;
    async function trabajador() {
      for (let f = cola.shift(); f; f = cola.shift()) {
        const { data, error } = await supabase.rpc("fn_educacion_entregas", { p_familia_id: f.familia_id });
        if (error) { fallos += 1; continue; }
        mapa.set(f.familia_id, ((data ?? []) as unknown as Entrega[]).map((e) => ({ ...e, familia_id: f.familia_id })));
      }
    }
    await Promise.all(Array.from({ length: Math.min(6, Math.max(1, filas.length)) }, trabajador));
    if (mia !== cargaVigente.current) return; // llegó una carga más nueva: esta ya es vieja
    setEntregasPorFamilia(mapa);
    setErrorConstancias(fallos > 0
      ? `No se pudieron traer las constancias de ${fallos} estudio${fallos === 1 ? "" : "s"}. Lo que ves puede estar incompleto.`
      : null);
  }, [supabase]);

  const cargar = useCallback(async () => {
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }

    const [sit, pend, solPend, lista, cands, lim, pf, cfg] = await Promise.all([
      supabase.rpc("fn_educacion_situacion"),
      supabase.rpc("fn_educacion_entregas_pendientes"),
      supabase.rpc("fn_educacion_solicitudes_pendientes"),
      supabase.rpc("fn_educacion_listar"),
      supabase.rpc("fn_educacion_candidatos"),
      supabase.rpc("fn_educacion_limite_comprobante"),
      supabase.rpc("fn_personas_funciones"),
      supabase.from("configuracion").select("clave, valor").like("clave", "educacion_%"),
    ]);
    const filasSituacion = (sit.data ?? []) as unknown as Situacion[];
    setSituaciones(filasSituacion);
    void cargarConstancias(filasSituacion);
    setPendientes((pend.data ?? []) as unknown as Pendiente[]);
    setSolicitudesPendientes((solPend.data ?? []) as unknown as SolicitudPendiente[]);
    setAsignaciones(new Map(((lista.data ?? []) as unknown as Asignacion[]).map((a) => [a.id, a])));
    setCandidatos((cands.data ?? []) as unknown as Candidato[]);
    // Quién ya se liquidó (0421/0422): se ocultan por defecto. Si falla, no se oculta a nadie.
    setLiquidadas(new Set(((pf.data ?? []) as unknown as { persona_id: string; liquidada: boolean }[])
      .filter((f) => f.liquidada).map((f) => f.persona_id)));
    const l = (lim.data as { limite_bytes: number; tipos: string[] }[] | null)?.[0];
    if (l) setLimite({ bytes: Number(l.limite_bytes), tipos: l.tipos.join(",") });
    const c = new Map(((cfg.data ?? []) as { clave: string; valor: unknown }[]).map((x) => [x.clave, x.valor]));
    setConfig({
      texto: typeof c.get("educacion_constancias_validas") === "string" ? (c.get("educacion_constancias_validas") as string) : "",
      plazo: Number(c.get("educacion_dias_plazo_antes_cierre") ?? 5),
      avisoColab: Number(c.get("educacion_dias_aviso_colaboradora") ?? 7),
      avisoDo: Number(c.get("educacion_dias_aviso_do") ?? 7),
    });
    setCargaError(sit.error ? mensajeDeError(sit.error, "cargar educación") : null);
    setCargando(false);
  }, [supabase, router, cargarConstancias]);

  // eslint-disable-next-line react-hooks/set-state-in-effect -- cargar al montar, mismo patrón que el resto del panel.
  useEffect(() => { void cargar(); }, [cargar]);

  // El historial de TODAS las solicitudes (aprobadas y rechazadas), a pedido:
  // una rechazada de alguien sin ninguna asignación no vuelve a aparecer en
  // ningún otro lado de esta pantalla. RLS ya deja a DO leer la tabla entera;
  // los nombres se piden aparte (no hay ambigüedad de qué FK usar al incrustar,
  // porque persona_id y revisada_por apuntan los dos a personas).
  async function cargarHistorialSolicitudes() {
    if (historialSolicitudes !== null || cargandoHistorialSol) return;
    setCargandoHistorialSol(true);
    const { data: sols, error } = await supabase
      .from("educacion_solicitudes")
      .select("id, persona_id, institucion, costo_declarado, estado, enviada_at, revisada_at, motivo_rechazo")
      .in("estado", ["aprobada", "rechazada"])
      .order("enviada_at", { ascending: false })
      .limit(200);
    if (error) {
      setCargandoHistorialSol(false);
      avisar("error", mensajeDeError(error, "cargar el historial de solicitudes"));
      return;
    }
    const filas = (sols ?? []) as unknown as (Omit<SolicitudHistorial, "persona"> & { persona_id: string })[];
    const ids = Array.from(new Set(filas.map((f) => f.persona_id)));
    const { data: personasData } = ids.length > 0
      ? await supabase.from("personas").select("id, nombres, apellidos").in("id", ids)
      : { data: [] as { id: string; nombres: string; apellidos: string }[] };
    const nombres = new Map((personasData ?? []).map((p) => [p.id, `${p.nombres} ${p.apellidos}`]));
    setHistorialSolicitudes(filas.map((f) => ({ ...f, persona: nombres.get(f.persona_id) ?? "—" })));
    setCargandoHistorialSol(false);
  }

  // El enlace de la Bandeja: ?entrega=<id> abre el panel de esa entrega; ?familia=<id>, el del estudio.
  const entregaPedida = params.get("entrega");
  const familiaPedida = params.get("familia");
  // ?persona=<id> (ADR 0003): se llega desde otra pantalla a una persona. Manda
  // sobre los demás filtros —si su estudio ya terminó o ya se liquidó, «vigentes»
  // la escondería justo cuando alguien vino a verla.
  const personaPedida = params.get("persona");
  useEffect(() => {
    if (cargando) return;
    if (entregaPedida) {
      const p = pendientes.find((x) => x.id === entregaPedida);
      if (p) {
        // eslint-disable-next-line react-hooks/set-state-in-effect -- abrir el panel que pide la URL, una vez cargados los datos.
        setAbierta(p.familia_id); setEntregaFoco(p.id); return;
      }
      // Ya no está pendiente (alguien la revisó): se busca su estudio igual.
      void supabase.from("educacion_entregas").select("asignaciones_educacion(familia_id)").eq("id", entregaPedida).maybeSingle()
        .then(({ data }) => {
          const familia = (data?.asignaciones_educacion as { familia_id: string } | null)?.familia_id;
          if (familia) { setAbierta(familia); setEntregaFoco(entregaPedida); }
        });
    } else if (familiaPedida) {
      setAbierta(familiaPedida);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cargando, entregaPedida, familiaPedida]);

  const solicitudPedida = params.get("solicitud");
  useEffect(() => {
    if (cargando || !solicitudPedida) return;
    // eslint-disable-next-line react-hooks/set-state-in-effect -- abrir el panel que pide la URL, una vez cargados los datos.
    setSolicitudAbierta(solicitudPedida);
  }, [cargando, solicitudPedida]);

  // ── Estudios, filtros y conteos ──────────────────────────────────────────
  // Una fila por PERSONA E INSTITUCIÓN: el mismo estudio registrado dos veces es una línea con sus
  // meses seguidos. Cada tarjeta, chip y pestaña cuenta sobre las MISMAS filas que se dibujan.
  const estudios = useMemo(() => agruparEstudios(situaciones), [situaciones]);
  const familiasConPendiente = useMemo(() => new Set(pendientes.map((p) => p.familia_id)), [pendientes]);
  const ctx = useMemo<ContextoDeFiltros>(
    () => ({ liquidadas, familiasConPendiente, entregasPorFamilia, personaPedida }),
    [liquidadas, familiasConPendiente, entregasPorFamilia, personaPedida],
  );
  const cargandoConstancias = entregasPorFamilia === null && situaciones.length > 0;

  // Nunca una lista escrita a mano (regla #3): todo sale de los datos.
  const sedes = useMemo(() => sedesDe(estudios), [estudios]);
  const instituciones = useMemo(() => Array.from(new Set(estudios.map((e) => e.institucion))).sort(), [estudios]);
  const todasLasEntregas = useMemo(
    () => (entregasPorFamilia ? Array.from(entregasPorFamilia.values()).flat() : []),
    [entregasPorFamilia],
  );
  const periodos = useMemo(() => mesesConConstancia(todasLasEntregas).reverse(), [todasLasEntregas]);
  const revisores = useMemo(
    () => Array.from(new Set(todasLasEntregas.map((e) => e.revisada_por).filter(Boolean) as string[])).sort(),
    [todasLasEntregas],
  );

  // Cada pieza se cuenta con los DEMÁS filtros puestos: «AQP 3» tiene que ser lo que aparece al tocarlo.
  const delAlcance = estudios.filter((e) => pasaFiltros(e, filtros, ctx, ["tarjeta", "grupo"]));
  const conteo = conteoTarjetas(delAlcance, familiasConPendiente);
  const deLaBusqueda = estudios.filter((e) => pasaFiltros(e, filtros, ctx, ["grupo"]));
  const visibles = deLaBusqueda.filter((e) => filtros.grupo === null || filtros.grupo === "sin_solicitar" || grupoDeEstudio(e) === filtros.grupo);

  const sedesConConteo = useMemo(() => {
    const sinSede = estudios.filter((e) => pasaFiltros(e, filtros, ctx, ["sede"]));
    return { total: sinSede.length, porSede: sedes.map((sede) => ({ sede, n: sinSede.filter((e) => e.sede === sede).length })) };
  }, [estudios, filtros, ctx, sedes]);

  // Quién no pidió nada: personas activas sin estudio ni solicitud por revisar.
  const sinSolicitar = personasSinSolicitar(candidatos, situaciones, solicitudesPendientes, liquidadas, filtros.liquidadas)
    .filter((c) => (!filtros.sede || c.sede === filtros.sede) && (!filtros.buscar.trim() || c.persona.toLowerCase().includes(filtros.buscar.trim().toLowerCase())));
  const conteoGrupo: Record<GrupoEducacion, number> = {
    al_dia: 0, por_revisar: 0, por_completar: 0, en_falta: 0, sin_solicitar: sinSolicitar.length,
  };
  for (const e of deLaBusqueda) conteoGrupo[grupoDeEstudio(e)] += 1;
  const niveles = useMemo(() => nivelesDeApoyo(candidatos), [candidatos]);

  // La línea de tiempo: seis meses y «ver más». Si se pidió un mes más viejo que la ventana, se abre hasta él.
  const mesesConDatos = useMemo(
    () => [...mesesConConstancia(todasLasEntregas), ...estudios.map((e) => mesDe(e.desde))],
    [todasLasEntregas, estudios],
  );
  const ventana = useMemo(() => {
    const v = ventanaDeMeses(hoy, mesesConDatos, mesesPedidos);
    if (filtros.mes && filtros.mes < v.meses[0]) {
      return ventanaDeMeses(hoy, mesesConDatos, mesesEntre(filtros.mes, v.meses[v.meses.length - 1]) + 1);
    }
    return v;
  }, [hoy, mesesConDatos, mesesPedidos, filtros.mes]);

  // Una sola sede elegida, o una sola con datos: no hace falta partir la lista en bloques.
  const resumenes = useMemo(() => resumenPorSede(visibles, hoy, familiasConPendiente), [visibles, hoy, familiasConPendiente]);
  const resumenDelAlcance = useMemo(() => resumenPorSede(delAlcance, hoy, familiasConPendiente), [delAlcance, hoy, familiasConPendiente]);
  const totalMensual = resumenDelAlcance.reduce((t, r) => t + r.montoMensual, 0);
  const apoyosPagandose = resumenDelAlcance.reduce((t, r) => t + r.pagando, 0);

  function limpiarFiltros() { setFiltros(FILTROS_VACIOS); }

  // La dirección acompaña a los filtros, sin tocar lo que otras pantallas le pasan (?persona=, ?familia=…).
  useEffect(() => {
    const url = new URL(window.location.href);
    for (const k of CLAVES_DE_URL) url.searchParams.delete(k);
    for (const [k, v] of new URLSearchParams(filtrosAUrl(filtros))) url.searchParams.set(k, v);
    const nueva = `${url.pathname}${url.search}`;
    if (nueva !== `${window.location.pathname}${window.location.search}`) window.history.replaceState(null, "", nueva);
  }, [filtros]);

  // ── Formulario de alta/corrección (cuerpo de la pantalla anterior) ───────
  const candidato = candidatos.find((c) => c.persona_id === form.personaId) ?? null;
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- sin persona o fecha no hay saldo que pedir: se borra el anterior.
    if (!form.personaId || !form.vigenteDesde) { setSaldo(undefined); return; }
    let vivo = true;
    void supabase.rpc("fn_educacion_saldo", {
      p_persona_id: form.personaId, p_desde: form.vigenteDesde,
      p_hasta: form.vigenteHasta || form.vigenteDesde, p_excluir: editandoId,
    }).then(({ data, error }) => { if (vivo) setSaldo(error ? undefined : (data as number | null)); });
    return () => { vivo = false; };
  }, [supabase, form.personaId, form.vigenteDesde, form.vigenteHasta, editandoId]);

  const costo = Number(form.costoDeclarado) || 0;
  const delPapel = costo > 0 ? Math.round(costo * COBERTURA) / 100 : null;
  const techoLibre = saldo !== undefined ? saldo : (candidato?.tope ?? null);
  const monto = delPapel === null ? 0 : techoLibre === null ? delPapel : Math.min(delPapel, techoLibre);

  function empezarAlta() {
    setEditandoId(null); setArchivo(null); setMostrandoForm(true);
    // Las fechas que bloquean el envío nacen con valor (CLAUDE.md, 2026-08-26).
    const inicioMes = hoy.slice(0, 8) + "01";
    setForm({ ...FORM_VACIO, vigenteDesde: inicioMes, vigenteHasta: inicioMes });
  }
  function empezarEdicion(asignacionId: string) {
    const a = asignaciones.get(asignacionId);
    const s = situaciones.find((x) => x.asignacion_id === asignacionId);
    if (!a) { avisar("error", "No se encontró la asignación para editarla. Recarga la pantalla."); return; }
    setAbierta(null);
    // Se abre desde el otro cajón (que ya se está cerrando): no hay un botón
    // visible al que devolverle el foco, así que no se hereda el de "+ Registrar".
    botonRegistrar.current = null;
    setEditandoId(a.id); setArchivo(null); setMostrandoForm(true);
    setForm({
      personaId: a.persona_id, institucion: a.institucion, costoDeclarado: String(a.costo_declarado),
      beneficiario: a.beneficiario, beneficiarioNombre: a.beneficiario_nombre ?? "",
      vigenteDesde: a.vigente_desde, vigenteHasta: a.vigente_hasta,
      frecuencia: s?.frecuencia_pago ?? "", primeraFechaPago: s?.proxima_fecha_pago ?? "",
      nota: a.nota ?? "", motivo: "",
    });
  }
  function cancelarForm() { setMostrandoForm(false); setEditandoId(null); setForm(FORM_VACIO); setArchivo(null); }

  async function guardar() {
    const inst = form.institucion.trim();
    if (!form.personaId) { avisar("error", "Elige de quién es la asignación."); return; }
    if (inst.length < 3) { avisar("error", "Escribe qué institución emite el comprobante."); return; }
    if (costo <= 0) { avisar("error", "El costo que dice el comprobante tiene que ser mayor que cero."); return; }
    if (monto <= 0) { avisar("error", "No queda techo libre en esas fechas: lo que ya tiene vigente agota el tope de su rango."); return; }
    if (form.beneficiario === "hijo" && form.beneficiarioNombre.trim().length < 3) {
      avisar("error", "Si el comprobante es de un hijo o hija, escribe a nombre de quién está."); return;
    }
    if (!form.vigenteDesde || !form.vigenteHasta) { avisar("error", "Indica desde y hasta cuándo se paga."); return; }
    if (form.vigenteHasta < form.vigenteDesde) { avisar("error", "La fecha de fin es anterior a la de inicio."); return; }
    if (editandoId && form.motivo.trim().length < 3) { avisar("error", "Escribe por qué se corrige. Queda registrado."); return; }

    setGuardando(true);
    const args = {
      p_persona_id: form.personaId, p_institucion: inst, p_costo_declarado: costo, p_beneficiario: form.beneficiario,
      p_vigente_desde: form.vigenteDesde, p_vigente_hasta: form.vigenteHasta,
      p_beneficiario_nombre: form.beneficiarioNombre.trim() || null, p_nota: form.nota.trim() || null,
    };
    const { data: id, error } = await supabase.rpc("fn_educacion_registrar", {
      ...args, p_id: editandoId, p_motivo: form.motivo.trim() || null,
    });
    if (error) { setGuardando(false); avisar("error", mensajeDeError(error, "guardar")); return; }

    if (archivo) {
      const ext = archivo.name.split(".").pop()?.toLowerCase() ?? "bin";
      const ruta = `educacion/${form.personaId}/${id}-${Date.now()}.${ext}`;
      setProgreso(0);
      const errorSubida = await subirArchivoConProgreso(supabase, BUCKET_COMPROBANTES, ruta, archivo, setProgreso);
      setProgreso(null);
      if (errorSubida) {
        setGuardando(false);
        avisar("error", `La asignación se guardó, pero el comprobante no subió (${errorSubida}). Cárgalo desde su panel.`);
        await cargar(); return;
      }
      const { error: e3 } = await supabase.rpc("fn_educacion_registrar", {
        ...args, p_comprobante_url: ruta, p_id: id as string, p_motivo: "Se enlaza el comprobante recién subido",
      });
      if (e3) { setGuardando(false); avisar("error", `El comprobante subió pero no quedó enlazado (${mensajeDeError(e3)}).`); await cargar(); return; }
    }

    // El calendario de pagos va aparte: no mueve plata y no debe abrir vigencia nueva.
    if (form.frecuencia || form.primeraFechaPago) {
      const { error: eCal } = await supabase.rpc("fn_educacion_fijar_calendario", {
        p_asignacion_id: id as string, p_frecuencia: form.frecuencia || null, p_proxima: form.primeraFechaPago || null,
      });
      if (eCal) avisar("error", `Se guardó, pero no el calendario de pagos: ${mensajeDeError(eCal)}`);
    }

    setGuardando(false);
    cancelarForm();
    await cargar();
    avisar("ok", editandoId ? "Cambios guardados." : "Asignación registrada. Entra en el próximo cálculo de planilla si tiene su comprobante.");
  }

  const formulario = (
    <div className="grid gap-3 sm:grid-cols-2">
      <div className="sm:col-span-2">
        <CampoSelect etiqueta="¿De quién es?" value={form.personaId} disabled={editandoId !== null}
          onChange={(e) => setForm({ ...form, personaId: e.target.value })}>
          <option value="">— elige a la persona —</option>
          {candidatos.map((c) => <option key={c.persona_id} value={c.persona_id}>{c.persona} · {c.sede} · rango {c.rango}</option>)}
        </CampoSelect>
      </div>
      <Campo etiqueta="Institución" value={form.institucion} placeholder="ej. Instituto San Ignacio"
        onChange={(e) => setForm({ ...form, institucion: e.target.value })} />
      <CampoSelect etiqueta="¿De quién es el estudio?" value={form.beneficiario}
        onChange={(e) => setForm({ ...form, beneficiario: e.target.value as "trabajador" | "hijo" })}>
        <option value="trabajador">De la persona misma</option>
        <option value="hijo">De su hijo o hija</option>
      </CampoSelect>
      {form.beneficiario === "hijo" && (
        <Campo etiqueta="¿A nombre de quién está el comprobante?" value={form.beneficiarioNombre}
          onChange={(e) => setForm({ ...form, beneficiarioNombre: e.target.value })} />
      )}
      <div className="flex flex-col gap-1">
        <Campo etiqueta="Costo que dice el comprobante" type="number" min="0" step="0.01" inputMode="decimal"
          value={form.costoDeclarado} onChange={(e) => setForm({ ...form, costoDeclarado: e.target.value })} />
      </div>
      <div className="flex flex-col gap-1 text-sm">
        Apoyo mensual
        <div className="rounded-lg border border-dashed bg-hueso px-3 py-2 font-medium">{costo > 0 ? soles(monto) : "—"}</div>
        <span className="text-xs text-taupe">
          {costo <= 0 ? "Se calcula solo: el 75 % del comprobante, sin pasar el techo que le queda en su rango."
            : delPapel !== null && techoLibre !== null && techoLibre < delPapel
              ? `Manda el techo de su rango: el ${COBERTURA} % del comprobante daría ${soles(delPapel)}.`
              : `Es el ${COBERTURA} % de ${soles(costo)}.`}
        </span>
      </div>
      <Campo etiqueta="Se paga desde" type="date" value={form.vigenteDesde}
        onChange={(e) => setForm({ ...form, vigenteDesde: e.target.value })} />
      <Campo etiqueta="Hasta cuándo vale" type="date" value={form.vigenteHasta}
        onChange={(e) => setForm({ ...form, vigenteHasta: e.target.value })} />
      <CampoSelect etiqueta="¿Cada cuánto paga a su institución?" value={form.frecuencia}
        onChange={(e) => setForm({ ...form, frecuencia: e.target.value as FrecuenciaPago | "" })}>
        <option value="">— sin definir —</option>
        {FRECUENCIAS_PAGO.map((f) => <option key={f} value={f}>{FRECUENCIA_PAGO_LABELS[f]}</option>)}
      </CampoSelect>
      <div className="flex flex-col gap-1">
        <Campo etiqueta="Próxima fecha de pago" type="date" value={form.primeraFechaPago}
          onChange={(e) => setForm({ ...form, primeraFechaPago: e.target.value })} />
        <span className="text-xs text-taupe">Opcional. Con ella el sistema avisa antes del pago y pide la constancia después.</span>
      </div>
      <div className="flex flex-col gap-1 sm:col-span-2">
        <Campo etiqueta="Comprobante inicial (opcional)" type="file" accept={limite.tipos}
          onChange={(e) => {
            const f = e.target.files?.[0] ?? null;
            if (f && f.size > limite.bytes) { avisar("error", `«${f.name}» pesa más de lo permitido.`); return; }
            setArchivo(f);
          }} />
        <span className="text-xs text-taupe">
          Queda como constancia aprobada, cargada por ti. Sin ningún comprobante, <strong>no se paga</strong>: es lo que
          hace que este monto no sea remuneración.
        </span>
        {progreso !== null && <span className="text-xs text-taupe">Subiendo… {progreso}%</span>}
      </div>
      {editandoId && (
        <div className="sm:col-span-2">
          <Campo etiqueta="¿Por qué se corrige?" value={form.motivo} placeholder="ej. el comprobante decía 180 y se registró 200"
            onChange={(e) => setForm({ ...form, motivo: e.target.value })} />
        </div>
      )}
      <div className="sm:col-span-2">
        <Campo etiqueta="Nota (opcional)" value={form.nota} onChange={(e) => setForm({ ...form, nota: e.target.value })} />
      </div>
      <div className="flex gap-3 sm:col-span-2">
        <Boton variante="primario" cargando={guardando} onClick={() => void guardar()}>
          {editandoId ? "Guardar cambios" : "Registrar asignación"}
        </Boton>
        <Boton onClick={cancelarForm} disabled={guardando}>Cancelar</Boton>
      </div>
    </div>
  );

  // ── DESCARGAS PARA AUDITORÍA: lo que ves, no «todo el sistema» ───────────
  // Decisión de Felipe (2026-10-16): el cuadro respeta los filtros, y el ZIP junta los papeles de
  // la sede y el mes elegidos. Las dos usan las constancias que la pantalla YA trajo y la misma
  // regla (`entregaPasaFiltros`) que la lista, así que lo descargado coincide con lo que se ve.
  // Llevan datos personales: no se suben a git ni se reenvían.
  function armarAuditoria() {
    const filas: Record<string, unknown>[] = [];
    const archivos: { nombre: string; ruta: string }[] = [];
    // El índice tiene que decir el nombre que de verdad lleva el archivo dentro del ZIP: si dos
    // constancias del mismo día se llamaran igual, el segundo se renombra AQUÍ y no más adelante.
    const usados = new Set<string>();
    const unico = (n: string) => {
      const punto = n.lastIndexOf(".");
      let c = n;
      for (let k = 2; usados.has(c.toLowerCase()); k++) c = punto > 0 ? `${n.slice(0, punto)} (${k})${n.slice(punto)}` : `${n} (${k})`;
      usados.add(c.toLowerCase());
      return c;
    };
    for (const e of visibles) {
      const base = {
        persona: e.persona, sede: e.sede, rango: e.rango, institucion: e.institucion,
        beneficiario: e.beneficiario === "hijo" ? (e.beneficiario_nombre ?? "hijo/a") : "la persona misma",
        apoyo_mensual: montoMensual(e, hoy).monto.toFixed(2), se_paga: montoMensual(e, hoy).seEstaPagando ? "sí" : "no",
        vigente_desde: e.desde, vigente_hasta: e.hasta,
        estado_actual: estadoParaMostrar(e).etiqueta,
        grupo: GRUPOS_EDUCACION.find((g) => g.clave === grupoDeEstudio(e))?.etiqueta ?? "",
      };
      const entregas = entregasDeEstudio(e, entregasPorFamilia).filter((x) => entregaPasaFiltros(x, filtros));
      if (entregas.length === 0) { filas.push({ ...base }); continue; }
      for (const x of entregas) {
        const comunes = {
          ...base, fecha_de_pago: x.fecha_pago, tipo: TIPO_CONSTANCIA_LABELS[x.tipo], resultado: ESTADO_ENTREGA[x.estado].etiqueta,
          enviada: fechaHora(x.enviada_at), revisada: fechaHora(x.revisada_at), revisada_por: x.revisada_por ?? "",
          motivo_rechazo: x.motivo_categoria ? `${MOTIVO_RECHAZO_LABELS[x.motivo_categoria]}${x.motivo_comentario ? `: ${x.motivo_comentario}` : ""}` : "",
        };
        if (x.archivos.length === 0) filas.push({ ...comunes });
        x.archivos.forEach((a, i) => {
          const ext = (a.nombre.split(".").pop() ?? a.ruta.split(".").pop() ?? "bin").toLowerCase().replace(/[^a-z0-9]/g, "") || "bin";
          const nombre = unico(nombreLegible(`${e.persona} - ${e.institucion} - ${x.fecha_pago} - ${i + 1}.${ext}`));
          filas.push({ ...comunes, archivo: a.nombre, ruta_en_el_almacen: a.ruta, archivo_en_el_zip: x.estado === "retirada" ? "" : nombre });
          if (x.estado !== "retirada") archivos.push({ nombre, ruta: a.ruta });
        });
      }
    }
    return { filas, archivos };
  }

  const COLUMNAS_AUDITORIA = [
    "persona", "sede", "rango", "institucion", "beneficiario", "apoyo_mensual", "se_paga", "vigente_desde", "vigente_hasta",
    "estado_actual", "grupo", "fecha_de_pago", "tipo", "resultado", "enviada", "revisada", "revisada_por", "motivo_rechazo",
    "archivo", "ruta_en_el_almacen", "archivo_en_el_zip",
  ];

  function descargarCuadro() {
    if (entregasPorFamilia === null) { avisar("error", "Las constancias todavía se están trayendo. Espera un momento."); return; }
    const { filas } = armarAuditoria();
    descargarCsv(`educacion-constancias-${hoy}.csv`, generarCsv(filas, COLUMNAS_AUDITORIA));
    avisar("ok", `Cuadro descargado: ${filas.length} filas de ${visibles.length} estudios.`);
  }

  const zipDisponible = Boolean(filtros.mes || filtros.desde || filtros.hasta) && entregasPorFamilia !== null;
  async function descargarZip() {
    if (!zipDisponible) { avisar("error", "Elige un mes (o un rango de fechas) para armar el ZIP."); return; }
    const { filas, archivos } = armarAuditoria();
    if (archivos.length === 0) { avisar("error", "No hay archivos de constancias en lo que ves."); return; }
    setDescargando(true);
    avisar("ok", `Armando el ZIP: ${archivos.length} archivo${archivos.length === 1 ? "" : "s"}…`);
    const r = await armarZip(supabase, archivos, generarCsv(filas, COLUMNAS_AUDITORIA), () => {});
    setDescargando(false);
    if (!r.ok) { avisar("error", `No se armó el ZIP: ${r.error}.`); return; }
    const cuando = filtros.mes || `${filtros.desde || "inicio"}_a_${filtros.hasta || hoy}`;
    descargarBlob(nombreLegible(`Educación ${filtros.sede || "todas las sedes"} ${cuando}`) + ".zip", r.blob);
    avisar("ok", `ZIP listo: ${archivos.length} archivo${archivos.length === 1 ? "" : "s"} y su índice.`);
  }

  const seleccion = abierta ? situaciones.find((s) => s.familia_id === abierta) ?? null : null;
  const visorEstudio = visor ? estudios.find((e) => e.clave === visor.clave) ?? null : null;

  function abrirVisor(e: Estudio, entregaId: string | null) {
    setVisor({ clave: e.clave, entregaId });
    setVisorAbierto(true);
  }
  function abrirEstudio(e: Estudio, boton: HTMLElement | null) {
    botonQueAbrio.current = boton;
    setEntregaFoco(null);
    setAbierta(e.actual.familia_id);
  }

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-4 sm:p-6">
        <CabeceraPagina
          titulo="Educación"
          accion={puedeGestionar ? (
            <Boton variante="primario"
              onClick={(e) => { botonRegistrar.current = e.currentTarget; empezarAlta(); }}>
              + Registrar asignación
            </Boton>
          ) : undefined}
        />

        {rol === null ? <Cargando /> : !puedeGestionar ? (
          <div className="max-w-2xl rounded-lg bg-ambar/15 px-4 py-3 text-sm text-ambar">
            Solo Desarrollo Organizacional gestiona los apoyos educativos.
          </div>
        ) : (
          <>
            <p className="mb-5 max-w-3xl text-sm text-taupe">
              Gestiona los apoyos educativos y las constancias que los sustentan. Aprobar o rechazar una constancia no
              cambia lo que se paga: es el respaldo de que el apoyo no es remuneración.
            </p>

            {cargaError && (
              <div className="mb-4 max-w-3xl rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo-profundo">
                {cargaError} <Boton variante="enlace" onClick={() => void cargar()}>Reintentar</Boton>
              </div>
            )}

            {cargando ? <Cargando /> : (
              <>
                {personaPedida && (
                  <div className="mb-4 flex flex-wrap items-center gap-2 rounded-xl border border-sand bg-papel px-3 py-2 text-sm">
                    <span>
                      Mostrando solo los estudios de{" "}
                      <strong>{situaciones.find((s) => s.persona_id === personaPedida)?.persona ?? "esta persona"}</strong>, vigentes o no.
                    </span>
                    <Boton variante="enlace" onClick={() => router.replace("/admin/educacion")}>Ver todas</Boton>
                  </div>
                )}

                {/* ── RESUMEN: cinco cifras que cuentan lo MISMO que se dibuja abajo ─ */}
                {/* «Rechazadas» espera a la integrante —le toca enviar la corregida—, así que no pide
                    «atender» a Desarrollo Organizacional. Un cero no pinta punto: callado, está bien. */}
                <div className="mb-3 grid grid-cols-2 gap-3 lg:grid-cols-5">
                  {([
                    ["pendientes", "Pendientes de revisión", conteo.pendientes, "informativo", undefined],
                    ["vencidas", "Constancias vencidas", conteo.vencidas, "alerta", undefined],
                    ["por_vencer", "Por vencer", conteo.por_vencer, "advertencia", undefined],
                    ["rechazadas", "Constancias rechazadas", conteo.rechazadas, undefined, "esperando a la integrante"],
                    ["pagos", `Pagos en ${config.avisoDo} días`, conteo.pagos, undefined, undefined],
                  ] as const).map(([clave, etiqueta, n, tono, detalle]) => (
                    <Cifra key={clave} etiqueta={etiqueta} valor={n} tono={n > 0 ? tono : undefined}
                      detalle={n > 0 ? detalle : undefined} activa={filtros.tarjeta === clave}
                      onClick={() => cambiar({ tarjeta: filtros.tarjeta === clave ? null : clave })} />
                  ))}
                </div>

                <p className="mb-5 text-xs text-taupe">
                  <strong className="font-medium text-tinta">
                    {[filtros.sede || (sedes.length > 1 ? "Todas las sedes" : sedes[0] ?? ""), filtros.mes && `pagos de ${mesLargo(filtros.mes)}`]
                      .filter(Boolean).join(" · ")}
                  </strong>
                  {" · "}{apoyosPagandose} apoyo{apoyosPagandose === 1 ? "" : "s"} pagándose · suman {soles(totalMensual)} al mes
                  {conteo.sinCalendario > 0 && (
                    <> · <Boton variante="enlace" className="text-xs" onClick={() => setFiltros({ ...FILTROS_VACIOS, estado: "sin_calendario" })}>
                      {conteo.sinCalendario} sin calendario de pagos
                    </Boton></>
                  )}
                  {" · "}
                  <Boton variante="enlace" className="text-xs" onClick={() => setConfigAbierta(true)}>Texto y plazos de las constancias</Boton>
                </p>

                {/* ── SOLICITUDES DE APOYO (0461): quien todavía no tiene asignación ── */}
                {solicitudesPendientes.length > 0 && (
                  <div className="mb-5 rounded-2xl border border-sand bg-hueso p-4">
                    <h2 className="mb-2 font-serif text-base">
                      Solicitudes de apoyo por revisar ({solicitudesPendientes.length})
                    </h2>
                    <ul className="flex flex-col divide-y divide-sand">
                      {solicitudesPendientes.map((s) => (
                        <li key={s.id} className="flex flex-wrap items-center justify-between gap-2 py-2 text-sm">
                          <span>
                            <span className="font-medium">{s.persona}</span>
                            <span className="text-taupe"> · {s.sede} · {s.institucion} · costo declarado {soles(s.costo_declarado)}</span>
                          </span>
                          <Boton tamano="sm" variante="primario"
                            onClick={(e) => { botonSolicitud.current = e.currentTarget; setSolicitudAbierta(s.id); }}>
                            Revisar →
                          </Boton>
                        </li>
                      ))}
                    </ul>
                  </div>
                )}

                {/* ── FILTROS: sede primero, después el grupo, y las herramientas ──── */}
                <BarraFiltros
                  filtros={filtros} cambiar={cambiar} limpiar={limpiarFiltros}
                  opciones={{
                    sedes: sedesConConteo.porSede, totalSedes: sedesConConteo.total,
                    grupos: conteoGrupo, totalGrupos: deLaBusqueda.length,
                    meses: periodos, instituciones, revisores, cargandoConstancias,
                  }}
                  descargas={{ csv: descargarCuadro, zip: () => void descargarZip(), zipDisponible, ocupado: descargando }}
                />

                {errorConstancias && (
                  <div className="mb-4 flex flex-wrap items-center gap-2 rounded-control bg-ambar/15 px-4 py-3 text-sm text-ambar">
                    {errorConstancias} <Boton variante="enlace" onClick={() => void cargar()}>Reintentar</Boton>
                  </div>
                )}

                {filtros.grupo === "sin_solicitar" ? (
                  sinSolicitar.length === 0 ? (
                    <EstadoVacio>Todas las personas activas tienen un apoyo o una solicitud en curso.</EstadoVacio>
                  ) : (
                    <div className="overflow-x-auto rounded-superficie border border-sand">
                      <table className="w-full text-sm">
                        <thead className="bg-hueso text-left text-xs uppercase tracking-wide text-taupe">
                          <tr>
                            <th className="px-4 py-2 font-medium">Persona</th>
                            <th className="px-4 py-2 font-medium">Techo mensual de su rango</th>
                            <th className="px-4 py-2"><span className="sr-only">Acción</span></th>
                          </tr>
                        </thead>
                        <tbody>
                          {sinSolicitar.map((c) => (
                            <tr key={c.persona_id} className="border-t border-sand">
                              <td className="px-4 py-3">
                                <span className="font-medium">{c.persona}</span>
                                <span className="block text-xs text-taupe">{c.sede} · {c.rango === "—" ? "sin rango asignado" : c.rango}</span>
                              </td>
                              <td className="px-4 py-3 tabular-nums">{c.tope === null ? "sin techo cargado" : soles(c.tope)}</td>
                              <td className="px-4 py-3 text-right">
                                <Boton variante="secundario" tamano="sm"
                                  onClick={(e) => { botonRegistrar.current = e.currentTarget; empezarAlta(); setForm((f) => ({ ...f, personaId: c.persona_id })); }}>
                                  Registrar apoyo
                                </Boton>
                              </td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  )
                ) : situaciones.length === 0 ? (
                  <EstadoVacio>Todavía no hay ningún apoyo educativo registrado.</EstadoVacio>
                ) : visibles.length === 0 ? (
                  <EstadoVacio accion={<Boton variante="secundario" onClick={limpiarFiltros}>Limpiar filtros</Boton>}>
                    Nada coincide con estos filtros.
                  </EstadoVacio>
                ) : (
                  <CuadriculaMeses
                    estudios={visibles} meses={ventana.meses} hayMasMeses={ventana.hayMas}
                    onVerMasMeses={() => setMesesPedidos((n) => Math.max(n, ventana.meses.length) + MESES_POR_PASO)}
                    mesResaltado={filtros.mes} entregasPorFamilia={entregasPorFamilia} cargandoConstancias={cargandoConstancias}
                    pendientes={pendientes} hoy={hoy}
                    resumenesSede={filtros.sede === "" && resumenes.length > 1 ? resumenes : null}
                    onAbrirVisor={abrirVisor} onAbrirEstudio={abrirEstudio}
                  />
                )}

                {/* ── CÓMO FUNCIONA y DÓNDE ESTÁN: lo que pregunta quien llega nuevo o audita ── */}
                <div className="mb-5 mt-8 grid gap-3 lg:grid-cols-2">
                  <details className="rounded-2xl border border-sand p-4">
                    <summary className="cursor-pointer font-serif text-base">Cómo funciona el incentivo de educación</summary>
                    <div className="mt-3 space-y-3 text-sm">
                      <p>
                        Es un apoyo para los estudios de la integrante o de sus hijos. No es remuneración mientras lo
                        sostenga un comprobante (art. 19 f) del D.S. 001-97-TR): por eso cada pago lleva su constancia.
                      </p>
                      <div>
                        <p className="font-medium">Cuánto se paga</p>
                        <p className="text-taupe">
                          El {COBERTURA} % del costo que dice el comprobante, con un techo mensual según el rango. Si la
                          persona tiene varios estudios, el techo se reparte: el primero que se registró conserva su
                          monto y el siguiente recibe lo que queda.
                        </p>
                      </div>
                      <div>
                        <p className="font-medium">Techo mensual por rango</p>
                        {niveles.length === 0 ? (
                          <p className="text-taupe">No hay personas activas para mostrar sus rangos.</p>
                        ) : (
                          <table className="mt-1 w-full max-w-sm text-sm">
                            <thead className="text-left text-xs uppercase tracking-wide text-taupe">
                              <tr><th className="py-1 font-medium">Rango</th><th className="py-1 font-medium">Techo</th><th className="py-1 font-medium">Personas</th></tr>
                            </thead>
                            <tbody>
                              {niveles.map((n) => (
                                <tr key={n.rango} className="border-t border-sand">
                                  <td className="py-1">{n.rango === "—" ? "sin rango asignado" : n.rango}</td>
                                  <td className="py-1 tabular-nums">{n.tope === null ? "sin techo cargado" : soles(n.tope)}</td>
                                  <td className="py-1 tabular-nums">{n.personas}</td>
                                </tr>
                              ))}
                            </tbody>
                          </table>
                        )}
                        <p className="mt-1 text-xs text-taupe">Solo salen los rangos que hoy tienen personas activas.</p>
                      </div>
                      <div>
                        <p className="font-medium">La constancia</p>
                        <p className="text-taupe">
                          Una por cada pago a la institución. Vence {config.plazo} días antes del cierre del periodo en
                          que cae el pago. Se avisa a la integrante {config.avisoColab} días antes del plazo y a
                          Desarrollo Organizacional {config.avisoDo} días antes del pago.
                        </p>
                      </div>
                      <div>
                        <p className="font-medium">Qué pasa si falta</p>
                        <p className="text-taupe">
                          Un apoyo empieza a pagarse cuando tiene su primera constancia aprobada. Después, aprobar o
                          rechazar la de cada mes no cambia lo que se paga: es una alerta. Pero sin constancia el apoyo
                          pierde su respaldo, y por eso una vencida o rechazada pide atención.
                        </p>
                      </div>
                    </div>
                  </details>

                  <details className="rounded-2xl border border-sand p-4">
                    <summary className="cursor-pointer font-serif text-base">Dónde están las constancias</summary>
                    <div className="mt-3 space-y-3 text-sm">
                      <div>
                        <p className="font-medium">Los archivos</p>
                        <p className="text-taupe">
                          Se guardan en el almacén privado «{BUCKET_COMPROBANTES}», en la carpeta de cada persona
                          (educacion/&lt;persona&gt;/entregas/…). No hay enlace público: se abren con sesión y un
                          enlace que dura pocos minutos. Los ve Desarrollo Organizacional y la propia integrante.
                        </p>
                      </div>
                      <div>
                        <p className="font-medium">El registro</p>
                        <p className="text-taupe">
                          Cada constancia guarda quién la envió y cuándo, quién la revisó y cuándo, y el motivo si se
                          rechazó. Desde el sistema no se edita ni se borra: si algo está mal, se envía otra, y una
                          pendiente solo se retira y queda marcada. Se ven en la cuadrícula de meses: un toque en la casilla
                          abre el papel, con sus datos al lado.
                        </p>
                      </div>
                      <p className="rounded-lg bg-hueso px-3 py-2 tabular-nums">
                        {situaciones.length} estudios · {situaciones.reduce((t, s) => t + s.aprobadas, 0)} constancias aprobadas
                        · {pendientes.length} por revisar
                      </p>
                      <div>
                        <p className="font-medium">Para una auditoría</p>
                        <p className="text-taupe">
                          «Descargar», arriba de la lista, baja el cuadro (CSV) de lo que estás viendo —una fila por
                          constancia y archivo: persona, estado, fechas, quién revisó y la ruta del archivo— y, si
                          eliges un mes, un ZIP con los papeles de esa sede y ese mes. Llevan datos personales: no se
                          suben a git ni se reenvían.
                        </p>
                      </div>
                    </div>
                  </details>
                </div>

                {/* ── HISTORIAL DE SOLICITUDES (0461): aprobadas y rechazadas ──── */}
                <details className="mb-5 rounded-2xl border border-sand p-4"
                  onToggle={(e) => { if (e.currentTarget.open) void cargarHistorialSolicitudes(); }}>
                  <summary className="cursor-pointer font-serif text-base">Historial de solicitudes de apoyo</summary>
                  <div className="mt-3">
                    <p className="mb-2 text-xs text-taupe">
                      Son pedidos de apoyo resueltos, no constancias: una solicitud rechazada aquí no suma a la tarjeta
                      «Constancias rechazadas».
                    </p>
                    {cargandoHistorialSol ? (
                      <Cargando />
                    ) : historialSolicitudes === null ? null : historialSolicitudes.length === 0 ? (
                      <p className="text-sm text-taupe">Todavía no se resolvió ninguna solicitud.</p>
                    ) : (
                      <ul className="flex flex-col divide-y divide-sand text-sm">
                        {historialSolicitudes.map((h) => {
                          const est = ESTADO_SOLICITUD[h.estado];
                          return (
                            <li key={h.id} className="flex flex-wrap items-center justify-between gap-2 py-2">
                              <span>
                                <span className="font-medium">{h.persona}</span>
                                <span className="text-taupe"> · {h.institucion} · costo declarado {soles(h.costo_declarado)}</span>
                                <span className="block text-xs text-taupe">
                                  Pedida el {fechaCorta(h.enviada_at)}
                                  {h.revisada_at && ` · revisada el ${fechaCorta(h.revisada_at)}`}
                                  {h.estado === "rechazada" && h.motivo_rechazo && ` · «${h.motivo_rechazo}»`}
                                </span>
                              </span>
                              <Insignia variante={est.tono}>{est.etiqueta}</Insignia>
                            </li>
                          );
                        })}
                      </ul>
                    )}
                  </div>
                </details>
              </>
            )}
          </>
        )}

        <Drawer abierto={seleccion !== null} onCerrar={() => { setAbierta(null); setEntregaFoco(null); }}
          titulo={seleccion ? `${seleccion.persona} · ${seleccion.institucion}` : undefined}
          volverElFocoA={botonQueAbrio} ancho="amplio">
          {seleccion && (
            <PanelEstudio
              key={seleccion.familia_id}
              s={seleccion}
              entregaFoco={entregaFoco}
              miPersonaId={persona?.id ?? null}
              onEditar={() => empezarEdicion(seleccion.asignacion_id)}
              onCambio={async (texto) => { avisar("ok", texto); await cargar(); }}
              onError={(texto) => avisar("error", texto)}
            />
          )}
        </Drawer>

        <Drawer abierto={mostrandoForm} onCerrar={cancelarForm} bloqueado={guardando}
          titulo={editandoId ? "Corregir asignación" : "Registrar asignación"}
          volverElFocoA={botonRegistrar} ancho="amplio">
          {formulario}
        </Drawer>

        <Drawer abierto={solicitudAbierta !== null} onCerrar={() => setSolicitudAbierta(null)}
          titulo="Solicitud de apoyo educativo" volverElFocoA={botonSolicitud}>
          {solicitudAbierta && (
            <PanelSolicitud
              id={solicitudAbierta}
              solicitud={solicitudesPendientes.find((s) => s.id === solicitudAbierta) ?? null}
              onCambio={async (texto) => {
                setSolicitudAbierta(null); setHistorialSolicitudes(null); avisar("ok", texto); await cargar();
              }}
              onError={(texto) => avisar("error", texto)}
            />
          )}
        </Drawer>

        <ConfigConstancias abierto={configAbierta} config={config} onCerrar={() => setConfigAbierta(false)}
          onGuardado={async () => { setConfigAbierta(false); avisar("ok", "Configuración guardada."); await cargar(); }}
          onError={(t) => avisar("error", t)} />

        {visorEstudio && (
          <VisorConstancia
            abierto={visorAbierto}
            estudio={visorEstudio}
            entregas={entregasDeEstudio(visorEstudio, entregasPorFamilia)}
            entregaId={visor?.entregaId ?? null}
            miPersonaId={persona?.id ?? null}
            onCerrar={() => setVisorAbierto(false)}
            onResuelta={async (texto) => { avisar("ok", texto); await cargar(); }}
            onError={(texto) => avisar("error", texto)}
            onAbrirEstudio={() => { setVisorAbierto(false); abrirEstudio(visorEstudio, null); }}
          />
        )}
      </main>
    </div>
  );
}

// ── EL PANEL DE UN ESTUDIO: beneficio, constancia por revisar, historial ────
function PanelEstudio({
  s, entregaFoco, miPersonaId, onEditar, onCambio, onError,
}: {
  s: Situacion;
  entregaFoco: string | null;
  miPersonaId: string | null;
  onEditar: () => void;
  onCambio: (texto: string) => Promise<void>;
  onError: (texto: string) => void;
}) {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const [entregas, setEntregas] = useState<Entrega[] | null>(null);
  const [trabajando, setTrabajando] = useState(false);
  const [frecuencia, setFrecuencia] = useState<FrecuenciaPago | "">(s.frecuencia_pago ?? "");
  const [proxima, setProxima] = useState(s.proxima_fecha_pago ?? "");
  const [cargandoAlNombre, setCargandoAlNombre] = useState(false);
  const [cerrando, setCerrando] = useState(false);
  const [hastaCierre, setHastaCierre] = useState(hoyLima());
  const [anulando, setAnulando] = useState(false);

  const traer = useCallback(async () => {
    const { data, error } = await supabase.rpc("fn_educacion_entregas", { p_familia_id: s.familia_id });
    if (error) { onError(mensajeDeError(error, "leer las constancias")); setEntregas([]); return; }
    setEntregas((data ?? []) as unknown as Entrega[]);
  }, [supabase, s.familia_id, onError]);
  // eslint-disable-next-line react-hooks/set-state-in-effect -- pedir el historial al abrir el panel.
  useEffect(() => { void traer(); }, [traer]);

  const pendientesDe = (entregas ?? []).filter((e) => e.estado === "pendiente");
  const enRevision = pendientesDe.find((e) => e.id === entregaFoco) ?? pendientesDe[0] ?? null;
  const esPropia = miPersonaId !== null && miPersonaId === s.persona_id;

  async function guardarCalendario() {
    setTrabajando(true);
    const { error } = await supabase.rpc("fn_educacion_fijar_calendario", {
      p_asignacion_id: s.asignacion_id, p_frecuencia: frecuencia || null, p_proxima: proxima || null,
    });
    setTrabajando(false);
    if (error) { onError(mensajeDeError(error, "guardar el calendario")); return; }
    await onCambio("Calendario de pagos guardado.");
  }

  async function atenderAviso() {
    if (!s.aviso_fin_id) return;
    setTrabajando(true);
    const { error } = await supabase.rpc("fn_educacion_atender_aviso_fin", { p_id: s.aviso_fin_id, p_respuesta: null });
    setTrabajando(false);
    if (error) { onError(mensajeDeError(error, "marcar el aviso")); return; }
    await onCambio("Aviso marcado como atendido.");
  }

  async function cerrarAsignacion() {
    setTrabajando(true);
    const { error } = await supabase.rpc("fn_educacion_cerrar", {
      p_id: s.asignacion_id, p_hasta: hastaCierre, p_motivo: `Cierre desde Educación (${s.institucion})`,
    });
    setTrabajando(false);
    if (error) { onError(mensajeDeError(error)); return; }
    setCerrando(false);
    if (s.aviso_fin_id) await supabase.rpc("fn_educacion_atender_aviso_fin", { p_id: s.aviso_fin_id, p_respuesta: `Cerrada al ${fechaCorta(hastaCierre)}` });
    await onCambio(`Cerrada al ${fechaCorta(hastaCierre)}. Deja de pagarse en los periodos posteriores.`);
  }

  // Anular: lo mismo que cerrar (fn_educacion_cerrar, sin SQL nuevo — no hay
  // dos puertas para la misma cuenta), pero sin pedir fecha ni motivo. Hoy, o
  // el propio inicio si la asignación todavía no empezaba (una de prueba
  // registrada a futuro no puede cerrarse "desde hoy": `fn_educacion_cerrar`
  // exige `p_hasta >= vigente_desde`).
  async function anularAsignacion() {
    setTrabajando(true);
    const hoy = hoyLima();
    const hasta = s.vigente_desde > hoy ? s.vigente_desde : hoy;
    const { error } = await supabase.rpc("fn_educacion_cerrar", {
      p_id: s.asignacion_id, p_hasta: hasta, p_motivo: "Anulada",
    });
    setTrabajando(false);
    if (error) { onError(mensajeDeError(error)); return; }
    setAnulando(false);
    if (s.aviso_fin_id) await supabase.rpc("fn_educacion_atender_aviso_fin", { p_id: s.aviso_fin_id, p_respuesta: "Anulada" });
    await onCambio("Asignación anulada.");
  }

  return (
    <div className="flex flex-col gap-6 text-sm">
      {/* ── BENEFICIO ── */}
      <section>
        <h3 className="mb-2 text-xs font-medium uppercase tracking-wide text-taupe">Beneficio</h3>
        <dl className="grid grid-cols-2 gap-x-4 gap-y-2">
          <div><dt className="text-xs text-taupe">Sede</dt><dd>{s.sede} · rango {s.rango}</dd></div>
          <div><dt className="text-xs text-taupe">Estudia</dt><dd>{s.beneficiario === "hijo" ? (s.beneficiario_nombre ?? "su hijo/a") : "La persona misma"}</dd></div>
          <div><dt className="text-xs text-taupe">Apoyo mensual</dt><dd className="tabular-nums">{soles(s.monto)}{!s.paga && s.vigencia !== "terminada" ? " · no se paga" : ""}</dd></div>
          <div><dt className="text-xs text-taupe">Vigencia</dt><dd>{fechaCorta(s.vigente_desde)} al {fechaCorta(s.vigente_hasta)}</dd></div>
        </dl>
        <div className="mt-3 grid grid-cols-2 gap-2">
          <CampoSelect etiqueta="Paga a su institución" value={frecuencia} onChange={(e) => setFrecuencia(e.target.value as FrecuenciaPago | "")}>
            <option value="">— sin definir —</option>
            {FRECUENCIAS_PAGO.map((f) => <option key={f} value={f}>{FRECUENCIA_PAGO_LABELS[f]}</option>)}
          </CampoSelect>
          <Campo etiqueta="Próximo pago" type="date" value={proxima} onChange={(e) => setProxima(e.target.value)} />
        </div>
        <div className="mt-2 flex flex-wrap gap-2">
          <Boton tamano="sm" cargando={trabajando} onClick={() => void guardarCalendario()}
            disabled={frecuencia === (s.frecuencia_pago ?? "") && proxima === (s.proxima_fecha_pago ?? "")}>Guardar calendario</Boton>
          <Boton tamano="sm" variante="sutil" onClick={onEditar}>Editar asignación</Boton>
          {s.vigencia !== "terminada" && (
            <>
              <Boton tamano="sm" variante="peligro" onClick={() => setCerrando(true)}>Cerrar asignación</Boton>
              <Boton tamano="sm" variante="peligro" onClick={() => setAnulando(true)}>Anular</Boton>
            </>
          )}
        </div>
      </section>

      {s.aviso_fin_id && (
        <section className="rounded-xl border border-ambar/40 bg-ambar/10 p-3">
          <p className="font-medium">Avisó que ya no va a pagar este estudio</p>
          <p className="mt-1">«{s.aviso_fin_motivo}»</p>
          <div className="mt-2 flex flex-wrap gap-2">
            <Boton tamano="sm" variante="peligro" onClick={() => setCerrando(true)}>Cerrar asignación</Boton>
            <Boton tamano="sm" variante="peligro" onClick={() => setAnulando(true)}>Anular</Boton>
            <Boton tamano="sm" cargando={trabajando} onClick={() => void atenderAviso()}>Marcar atendido sin cerrar</Boton>
          </div>
        </section>
      )}

      {/* ── CONSTANCIA POR REVISAR ── */}
      <section>
        <div className="mb-2 flex items-center justify-between gap-2">
          <h3 className="text-xs font-medium uppercase tracking-wide text-taupe">Constancia</h3>
          <Insignia variante={ESTADO_CONSTANCIA[s.estado_constancia].tono}>{ESTADO_CONSTANCIA[s.estado_constancia].etiqueta}</Insignia>
        </div>
        {entregas === null ? <Cargando /> : enRevision ? (
          <div className="rounded-xl border border-sand p-3">
            <dl className="grid grid-cols-2 gap-x-4 gap-y-2">
              <div><dt className="text-xs text-taupe">Pago</dt><dd>{fechaCorta(enRevision.fecha_pago)} · {TIPO_CONSTANCIA_LABELS[enRevision.tipo]}</dd></div>
              <div><dt className="text-xs text-taupe">Enviada</dt><dd>{fechaHora(enRevision.enviada_at)}</dd></div>
              <div><dt className="text-xs text-taupe">Próximo pago declarado</dt><dd>{enRevision.proxima_fecha_pago ? fechaCorta(enRevision.proxima_fecha_pago) : "no lo sabe o fue el último"}</dd></div>
              {enRevision.reemplaza_a && <div><dt className="text-xs text-taupe">Es</dt><dd>una corrección de un envío anterior</dd></div>}
            </dl>
            {enRevision.nota && <p className="mt-2 rounded-lg bg-hueso p-2 text-xs">«{enRevision.nota}»</p>}
            <div className="mt-3"><LienzoArchivos archivos={enRevision.archivos} /></div>
            <div className="mt-3">
              <AccionesRevision
                entrega={enRevision} persona={s.persona} esPropia={esPropia}
                onResuelta={async (texto) => { await traer(); await onCambio(texto); }} onError={onError}
              />
            </div>
            {pendientesDe.length > 1 && <p className="mt-2 text-xs text-taupe">Hay {pendientesDe.length} constancias pendientes en este estudio; se revisan de a una.</p>}
          </div>
        ) : (
          <p className="text-taupe">
            {s.estado_constancia === "rechazada"
              ? "La última se rechazó; esperando que la integrante envíe la corregida."
              : s.fecha_pago_constancia && s.estado_constancia !== "al_dia"
                ? `Falta la constancia del pago del ${fechaCorta(s.fecha_pago_constancia)}${s.plazo ? `, plazo ${fechaCorta(s.plazo)}` : ""}.`
                : "No hay constancias por revisar."}
          </p>
        )}
        {!cargandoAlNombre ? (
          <Boton variante="enlace" className="mt-2 text-xs" onClick={() => setCargandoAlNombre(true)}>
            Cargar una constancia a su nombre
          </Boton>
        ) : (
          <CargaAlNombre s={s} onCancelar={() => setCargandoAlNombre(false)} onError={onError}
            onListo={async () => { setCargandoAlNombre(false); await traer(); await onCambio("Constancia cargada y aprobada."); }} />
        )}
      </section>

      {/* ── HISTORIAL ── */}
      <section>
        <h3 className="mb-2 text-xs font-medium uppercase tracking-wide text-taupe">Historial</h3>
        {entregas === null ? <Cargando /> : entregas.length === 0 ? (
          <p className="text-taupe">Sin constancias todavía.</p>
        ) : (
          <ul className="divide-y divide-sand">
            {entregas.map((e) => (
              <ItemHistorial key={e.id} e={e} abiertoAlInicio={e.id === entregaFoco && e.estado !== "pendiente"} />
            ))}
          </ul>
        )}
      </section>

      <Modal abierto={cerrando} onCerrar={() => setCerrando(false)} bloqueado={trabajando} titulo="Cerrar esta asignación" ancho="sm">
        <p className="mb-4 text-sm text-taupe">
          ¿Hasta qué día se le paga a {s.persona}? La asignación no se borra: sigue sosteniendo lo ya pagado.
        </p>
        <Campo etiqueta="Se paga hasta" type="date" value={hastaCierre} onChange={(e) => setHastaCierre(e.target.value)} />
        <div className="mt-4 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
          <Boton onClick={() => setCerrando(false)} disabled={trabajando}>Cancelar</Boton>
          <Boton variante="peligro" cargando={trabajando} onClick={() => void cerrarAsignacion()} disabled={!hastaCierre}>Cerrar</Boton>
        </div>
      </Modal>

      <Modal abierto={anulando} onCerrar={() => setAnulando(false)} bloqueado={trabajando} titulo="¿Anular esta asignación?" ancho="sm">
        <p className="mb-4 text-sm text-taupe">
          El apoyo de {s.persona} deja de pagarse desde hoy. La asignación no se borra: queda en su historial como
          anulada, y lo ya pagado antes no se toca.
        </p>
        <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
          <Boton onClick={() => setAnulando(false)} disabled={trabajando}>Cancelar</Boton>
          <Boton variante="peligro" cargando={trabajando} onClick={() => void anularAsignacion()}>Anular</Boton>
        </div>
      </Modal>
    </div>
  );
}

// Una constancia del historial: cerrada muestra su resumen; al abrirla, el papel ya dibujado.
// Los archivos se piden recién al abrirla: un estudio con veinte constancias no baja veinte fotos al entrar.
function ItemHistorial({ e, abiertoAlInicio }: { e: Entrega; abiertoAlInicio: boolean }) {
  const [abierto, setAbierto] = useState(abiertoAlInicio);
  return (
    <li className="py-2">
      <details open={abierto} onToggle={(ev) => setAbierto(ev.currentTarget.open)}>
        <summary className="flex cursor-pointer list-none flex-wrap items-center justify-between gap-2">
          <span>Pago del {fechaCorta(e.fecha_pago)} <span className="text-taupe">· {TIPO_CONSTANCIA_LABELS[e.tipo]}{e.reemplaza_a ? " · corrección" : ""}</span></span>
          <Insignia variante={ESTADO_ENTREGA[e.estado].tono}>{ESTADO_ENTREGA[e.estado].etiqueta}</Insignia>
        </summary>
        <div className="mt-2 rounded-xl bg-hueso p-3 text-xs text-taupe">
          <p>
            {e.origen === "colaboradora" ? `Enviada por la integrante el ${fechaHora(e.enviada_at)}`
              : e.origen === "do" ? `Cargada por ${e.enviada_por ?? "Desarrollo Organizacional"} el ${fechaHora(e.enviada_at)}`
                : "Cargada antes de la revisión de constancias"}
          </p>
          {e.revisada_at && e.origen === "colaboradora" && <p>{e.estado === "aprobada" ? "Aprobó" : "Rechazó"} {e.revisada_por ?? "—"} el {fechaHora(e.revisada_at)}</p>}
          {e.retirada_at && <p>La retiró la integrante el {fechaHora(e.retirada_at)}</p>}
          {e.estado === "rechazada" && (
            <p className="mt-1 text-rojo-profundo">{e.motivo_categoria ? MOTIVO_RECHAZO_LABELS[e.motivo_categoria] : ""}{e.motivo_comentario ? `: «${e.motivo_comentario}»` : ""}</p>
          )}
          {abierto && e.estado !== "pendiente" && <div className="mt-3"><LienzoArchivos archivos={e.archivos} /></div>}
        </div>
      </details>
    </li>
  );
}

// DO carga la constancia a nombre de alguien: queda aprobada, con su nombre.
function CargaAlNombre({ s, onCancelar, onListo, onError }: {
  s: Situacion; onCancelar: () => void; onListo: () => Promise<void>; onError: (t: string) => void;
}) {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const hoy = hoyLima();
  const [entregaId] = useState(() => crypto.randomUUID());
  const inicial = s.fecha_pago_constancia && s.fecha_pago_constancia <= hoy ? s.fecha_pago_constancia : hoy;
  const [fechaPago, setFechaPago] = useState(inicial);
  const [tipo, setTipo] = useState<TipoConstancia>("cuota_mensual");
  const [proxima, setProxima] = useState(sugerirProximaFecha(inicial, s.frecuencia_pago) ?? "");
  const [archivos, setArchivos] = useState<ArchivoElegido[]>([]);
  const [enviando, setEnviando] = useState(false);

  async function enviar() {
    if (archivos.length === 0) { onError("Elige al menos un archivo."); return; }
    setEnviando(true);
    const subida = await subirArchivosDeEntrega(supabase, s.persona_id, entregaId, archivos, () => {},
      (clave, subido) => setArchivos((prev) => prev.map((a) => (a.clave === clave ? { ...a, subido } : a))));
    if (!subida.ok) { setEnviando(false); onError(subida.error); return; }
    const { error } = await supabase.rpc("fn_educacion_enviar_entrega", {
      p_id: entregaId, p_asignacion_id: s.asignacion_id, p_fecha_pago: fechaPago, p_tipo: tipo,
      p_proxima_fecha_pago: proxima || null, p_archivos: subida.archivos, p_nota: null, p_reemplaza_a: null,
    });
    setEnviando(false);
    if (error) { onError(mensajeDeError(error, "cargar la constancia")); return; }
    await onListo();
  }

  return (
    <div className="mt-3 grid gap-2 rounded-xl border border-sand p-3 sm:grid-cols-2">
      <Campo etiqueta="Fecha de pago" type="date" value={fechaPago} max={hoy} onChange={(e) => setFechaPago(e.target.value)} />
      <CampoSelect etiqueta="Tipo" value={tipo} onChange={(e) => setTipo(e.target.value as TipoConstancia)}>
        {TIPOS_CONSTANCIA.map((t) => <option key={t} value={t}>{TIPO_CONSTANCIA_LABELS[t]}</option>)}
      </CampoSelect>
      <Campo etiqueta="Próximo pago (opcional)" type="date" value={proxima} onChange={(e) => setProxima(e.target.value)} />
      <Campo etiqueta="Archivos" type="file" multiple accept="application/pdf,image/*"
        onChange={(e) => {
          const nuevos: ArchivoElegido[] = [];
          for (const f of Array.from(e.target.files ?? [])) {
            const p = problemaDeArchivo({ nombre: f.name, tipo: f.type, bytes: f.size });
            if (p) { onError(p); continue; }
            nuevos.push(elegido(f));
          }
          setArchivos(nuevos.slice(0, 10));
        }} />
      <div className="flex gap-2 sm:col-span-2">
        <Boton variante="primario" tamano="sm" cargando={enviando} onClick={() => void enviar()}>Cargar y aprobar</Boton>
        <Boton tamano="sm" onClick={onCancelar} disabled={enviando}>Cancelar</Boton>
      </div>
    </div>
  );
}

/**
 * Revisar una solicitud de apoyo educativo (0461): aprobar nace la asignación
 * con el mismo cálculo de siempre (fn_educacion_registrar, por dentro de
 * fn_educacion_resolver_solicitud); rechazar exige motivo, que la integrante
 * lee y puede corregir.
 */
function PanelSolicitud({
  id, solicitud, onCambio, onError,
}: {
  id: string;
  solicitud: SolicitudPendiente | null;
  onCambio: (texto: string) => Promise<void>;
  onError: (texto: string) => void;
}) {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const [rechazando, setRechazando] = useState(false);
  const [motivo, setMotivo] = useState("");
  const [enviando, setEnviando] = useState(false);

  async function aprobar() {
    setEnviando(true);
    const { error } = await supabase.rpc("fn_educacion_resolver_solicitud", { p_id: id, p_aprobar: true });
    setEnviando(false);
    if (error) { onError(mensajeDeError(error, "aprobar la solicitud")); return; }
    await onCambio(`Solicitud de ${solicitud?.persona ?? "la integrante"} aprobada. La asignación ya está activa.`);
  }

  async function rechazar() {
    if (motivo.trim().length < 3) { onError("Escribe qué corregir: la integrante lo va a leer."); return; }
    setEnviando(true);
    const { error } = await supabase.rpc("fn_educacion_resolver_solicitud", {
      p_id: id, p_aprobar: false, p_motivo: motivo.trim(),
    });
    setEnviando(false);
    if (error) { onError(mensajeDeError(error, "rechazar la solicitud")); return; }
    await onCambio(`Solicitud de ${solicitud?.persona ?? "la integrante"} rechazada.`);
  }

  if (!solicitud) {
    return <p className="text-sm text-taupe">Ya no está pendiente: alguien más la revisó recién.</p>;
  }

  return (
    <div className="flex flex-col gap-4 text-sm">
      <div>
        <p className="font-medium">{solicitud.persona}</p>
        <p className="text-taupe">{solicitud.sede} · {solicitud.institucion}</p>
      </div>
      <dl className="grid grid-cols-2 gap-3">
        <div><dt className="text-xs text-taupe">Costo declarado</dt><dd className="tabular-nums">{soles(solicitud.costo_declarado)}</dd></div>
        <div><dt className="text-xs text-taupe">Pedida el</dt><dd>{fechaCorta(solicitud.enviada_at)}</dd></div>
        <div><dt className="text-xs text-taupe">Desde</dt><dd>{fechaCorta(solicitud.vigente_desde)}</dd></div>
        <div><dt className="text-xs text-taupe">Hasta</dt><dd>{fechaCorta(solicitud.vigente_hasta)}</dd></div>
      </dl>
      <p className="rounded-xl bg-hueso p-3 text-xs text-taupe">
        El apoyo mensual se calcula al aprobar (75 % del costo, sin pasar el techo del rango) — el mismo cálculo
        de siempre. No lo declara la integrante.
      </p>
      {solicitud.comprobante_url ? (
        <Boton variante="enlace" className="w-fit text-xs" onClick={async () => {
          const error = await abrirArchivoFirmado(supabase, BUCKET_COMPROBANTES, solicitud.comprobante_url!);
          if (error) onError(error);
        }}>
          Ver comprobante adjunto
        </Boton>
      ) : (
        <p className="text-xs text-taupe">No adjuntó comprobante todavía.</p>
      )}

      {!rechazando ? (
        <div className="flex gap-2">
          <Boton variante="primario" cargando={enviando} onClick={() => void aprobar()}>Aprobar</Boton>
          <Boton variante="peligro" onClick={() => setRechazando(true)} disabled={enviando}>Rechazar</Boton>
        </div>
      ) : (
        <div className="flex flex-col gap-2">
          <AreaTexto rows={3} value={motivo} onChange={(e) => setMotivo(e.target.value)} autoFocus
            placeholder="Qué tiene que corregir la integrante" aria-label="Motivo del rechazo" />
          <div className="flex gap-2">
            <Boton variante="peligro" cargando={enviando} onClick={() => void rechazar()}>Confirmar rechazo</Boton>
            <Boton onClick={() => { setRechazando(false); setMotivo(""); }} disabled={enviando}>Cancelar</Boton>
          </div>
        </div>
      )}
    </div>
  );
}

function ConfigConstancias({ abierto, config, onCerrar, onGuardado, onError }: {
  abierto: boolean;
  config: { texto: string; plazo: number; avisoColab: number; avisoDo: number };
  onCerrar: () => void; onGuardado: () => Promise<void>; onError: (t: string) => void;
}) {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const [texto, setTexto] = useState(config.texto);
  const [plazo, setPlazo] = useState(String(config.plazo));
  const [avisoColab, setAvisoColab] = useState(String(config.avisoColab));
  const [avisoDo, setAvisoDo] = useState(String(config.avisoDo));
  const [guardando, setGuardando] = useState(false);

  // eslint-disable-next-line react-hooks/set-state-in-effect -- al abrir, arranca con lo guardado.
  useEffect(() => { if (abierto) { setTexto(config.texto); setPlazo(String(config.plazo)); setAvisoColab(String(config.avisoColab)); setAvisoDo(String(config.avisoDo)); } }, [abierto, config]);

  async function guardar() {
    setGuardando(true);
    const { error } = await supabase.rpc("fn_educacion_configurar", {
      p_texto_valido: texto, p_dias_plazo: Number(plazo), p_dias_aviso_colab: Number(avisoColab), p_dias_aviso_do: Number(avisoDo),
    });
    setGuardando(false);
    if (error) { onError(mensajeDeError(error, "guardar la configuración")); return; }
    await onGuardado();
  }

  return (
    <Modal abierto={abierto} onCerrar={onCerrar} bloqueado={guardando} titulo="Texto y plazos de las constancias" ancho="lg">
      <label className="flex flex-col gap-1 text-sm">
        Qué constancias son válidas (lo lee la integrante al subir)
        <AreaTexto rows={4} value={texto} onChange={(e) => setTexto(e.target.value)} />
      </label>
      <div className="mt-3 grid gap-3 sm:grid-cols-3">
        <Campo etiqueta="Vence antes del cierre (días)" type="number" min="0" max="20" value={plazo} onChange={(e) => setPlazo(e.target.value)} />
        <Campo etiqueta="Aviso a la integrante (días)" type="number" min="0" max="30" value={avisoColab} onChange={(e) => setAvisoColab(e.target.value)} />
        <Campo etiqueta="Aviso a DO antes del pago (días)" type="number" min="0" max="30" value={avisoDo} onChange={(e) => setAvisoDo(e.target.value)} />
      </div>
      <div className="mt-4 flex justify-end gap-2">
        <Boton onClick={onCerrar} disabled={guardando}>Cancelar</Boton>
        <Boton variante="primario" cargando={guardando} onClick={() => void guardar()}>Guardar</Boton>
      </div>
    </Modal>
  );
}

export default function EducacionPage() {
  return (
    <Suspense fallback={<Cargando />}>
      <EducacionContenido />
    </Suspense>
  );
}
