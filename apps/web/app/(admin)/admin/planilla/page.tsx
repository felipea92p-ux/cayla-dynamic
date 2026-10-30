"use client";

// ── Planilla: el espacio donde se revisa y se cierra un periodo ─────────────
//
// Rediseñada el 2026-09-15 tras la auditoría
// `docs/auditoria-pantalla-planilla-2026-09-15.md`. Lo que ordena todo:
//
// 1. LO QUE SE VE NO ES LO QUE SE PAGA, y la pantalla ya no los mezcla. Los
//    filtros (sede, búsqueda, «solo lo que hay que revisar») cambian la TABLA
//    y nada más. Pestañas, conteos, totales, el panel de pendientes, la
//    revisión de cierre y el CSV se calculan siempre sobre el periodo completo,
//    que es lo que `fn_periodo_pagado` congela. Hasta hoy el filtro «Solo el
//    equipo actual» escondía a quien cesó, y pagar con él puesto registraba
//    como pagadas a personas que nadie había visto.
// 2. QUIEN CESÓ SE QUEDA EN LA TABLA, con su insignia relativa al periodo.
// 3. EL ESTADO ES POR GRUPO, porque en la base es por grupo (0323).
// 4. SOLO BLOQUEA LO QUE LA BASE BLOQUEA; el resto se revisa y se marca.
//
// Ninguna fórmula, estado, regla de cierre ni llamada a la base cambió: mismas
// funciones y mismos parámetros que la pantalla anterior. La lógica pura vive
// en `lib/admin/planilla/revision.ts` (con pruebas en tests/), y los
// componentes en `components/planilla/`.

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { cx } from "@/components/ui/cx";
import { Check, ChevronDown, ChevronUp, MoreHorizontal, ReceiptText, Search } from "lucide-react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import {
  TIPOS_VINCULO, TIPO_VINCULO_LABEL, hoyLima, puedeMarcarPagoPersona, puedeVerPlanilla, type TipoVinculo,
} from "@cayla-dynamic/shared";
import { Cargando } from "@/components/cargando";
import { useToast } from "@/components/toast";
import { useRolActual } from "@/lib/admin/use-rol";
import { formatSoles } from "@/lib/rangos";
import { descargarCsv, generarCsv } from "@/lib/admin/csv";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { AyudaPantalla } from "@/components/ui/ayuda-pantalla";
import { Boton } from "@/components/ui/boton";
import { BotonIcono } from "@/components/ui/boton-icono";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { ParaAtender } from "@/components/ui/para-atender";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";
import { sobretituloDeHoy } from "@/lib/admin/sobretitulo";
import { accionPrincipalDelPeriodo } from "@/lib/admin/planilla/accion-principal";
import { Insignia } from "@/components/ui/insignia";
import { usePruebasPorPersona } from "@/components/pruebas/etiqueta-prueba";
import { Modal } from "@/components/ui/modal";
import { Menu, MenuItem } from "@/components/ui/menu";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { Campo, CampoCasilla, CampoSelect } from "@/components/ui/campo";
import { Cifra } from "@/components/ui/cifra";
import { Filtro } from "@/components/ui/filtro";
import { AreaTexto } from "@/components/ui/area-texto";
import { Tabla, TablaEncabezado, Th, Fila as FilaTabla } from "@/components/ui/tabla";
import { TablaPlanilla } from "@/components/planilla/tabla-planilla";
import { PanelPersona } from "@/components/planilla/panel-persona";
import { RevisionCierre, type AnteriorPendiente } from "@/components/planilla/revision-cierre";
import { RequiereAtencion } from "@/components/planilla/requiere-atencion";
import { QueCambio } from "@/components/planilla/que-cambio";
import { PanelFeriados } from "@/components/planilla/panel-feriados";
import { MESES_LARGO, fechaCorta, fechaLargaLima, fmtHoras, sumarDias } from "@/lib/admin/planilla/formato";
import {
  agruparHallazgos, agruparPorGrupo, avanceDelPeriodo, ceseRespectoDelPeriodo, claveFila, grupoDe, hallazgosDePersona,
  lecturaDelEstado, periodoInicialSugerido, periodosAnterioresSinPagar, periodosVencidosSinPagar, sumarFilas,
  type Cese, type Hallazgo, type LecturaEstado,
} from "@/lib/admin/planilla/revision";
import { filasCsvPlanilla } from "@/lib/admin/planilla/csv-planilla";
import type {
  Desvio, EstadoPagoPersona, EventoPagoPersona, Fila, GratiCts, GrupoPago, Liquidada, PeriodoInfo, Proyeccion, Variacion,
} from "@/lib/admin/planilla/tipos";

// ── Utilidades de esta pantalla ─────────────────────────────────────────────

function nombrePeriodo(p: Pick<PeriodoInfo, "mes_etiqueta" | "anio_etiqueta">): string {
  const mes = MESES_LARGO[p.mes_etiqueta - 1];
  return `${mes.charAt(0).toUpperCase()}${mes.slice(1)} ${p.anio_etiqueta}`;
}

function etiquetaPeriodo(p: PeriodoInfo): string {
  return `${nombrePeriodo(p)} · ${fechaCorta(p.fecha_ini)} → ${fechaCorta(p.fecha_fin)}`;
}

/** El mismo día del mes siguiente (acotado al largo de ese mes): el cierre más probable del periodo que sigue. */
function mismoDiaMesSiguiente(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  const ultimo = new Date(Date.UTC(y, m + 1, 0)).getUTCDate();
  return new Date(Date.UTC(y, m, Math.min(d, ultimo))).toISOString().slice(0, 10);
}

const LECTURA: Record<LecturaEstado, { texto: string; variante: "positivo" | "advertencia" | "alerta" | "informativo" }> = {
  pagado: { texto: "Pagado", variante: "positivo" },
  pagado_en_parte: { texto: "Pagado en parte", variante: "advertencia" },
  vencido: { texto: "Vencido sin pagar", variante: "alerta" },
  abierto: { texto: "Abierto", variante: "informativo" },
};

interface Reversa {
  id: string;
  revertido_at: string;
  motivo: string;
  tipo: "reapertura" | "repago" | null;
  grupo: TipoVinculo | null;
  personas: { nombres: string; apellidos: string | null } | null;
}

/** Todo lo que se trae de un periodo de una vez; `id` dice de cuál, para descartar lo que llega tarde. */
interface DatosDelPeriodo {
  id: string;
  error: string | null;
  proy: Proyeccion | null;
  grupos: GrupoPago[] | null;
  gc: GratiCts | null;
  liquidadas: Record<string, Liquidada>;
  fechasCese: Record<string, string | null>;
  historial: Reversa[] | null;
  pagos: EstadoPagoPersona[] | null;
}

export default function PlanillaPage() {
  const pruebas = usePruebasPorPersona();
  const router = useRouter();
  const rol = useRolActual();
  const puedeVer = puedeVerPlanilla(rol);
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const { avisar } = useToast();
  const hoy = hoyLima();

  // ── Periodos ───────────────────────────────────────────────────────────────
  const [periodos, setPeriodos] = useState<PeriodoInfo[] | null>(null);
  const [errorPeriodos, setErrorPeriodos] = useState<string | null>(null);
  const [periodoSel, setPeriodoSel] = useState<string | null>(null);
  const [guardandoPeriodo, setGuardandoPeriodo] = useState(false);
  // El estado por grupo de OTROS periodos pendientes, para decir qué grupo falta en cada uno.
  const [gruposDeOtros, setGruposDeOtros] = useState<Record<string, GrupoPago[]>>({});

  // Crear periodo. Los campos de fecha nacen con el valor más probable (regla de CLAUDE.md).
  const [mostrandoNuevo, setMostrandoNuevo] = useState(false);
  const [nuevoFin, setNuevoFin] = useState(() => sumarDias(hoyLima(), 29));
  const [primerIni, setPrimerIni] = useState(() => hoyLima());
  const [primerFin, setPrimerFin] = useState(() => sumarDias(hoyLima(), 29));
  const [creandoPeriodo, setCreandoPeriodo] = useState(false);

  // ── Datos del periodo seleccionado ─────────────────────────────────────────
  const [proy, setProy] = useState<Proyeccion | null>(null);
  const [grupos, setGrupos] = useState<GrupoPago[] | null>(null);
  const [gc, setGc] = useState<GratiCts | null>(null);
  const [liquidadas, setLiquidadas] = useState<Record<string, Liquidada>>({});
  const [fechasCese, setFechasCese] = useState<Record<string, string | null>>({});
  const [historial, setHistorial] = useState<Reversa[] | null>(null);
  const [pagosPersona, setPagosPersona] = useState<EstadoPagoPersona[] | null>(null);
  const [recargando, setRecargando] = useState(false);
  // El error guarda de qué periodo es: uno viejo no puede pintarse sobre el periodo recién elegido.
  const [errorCarga, setErrorCarga] = useState<{ id: string; mensaje: string } | null>(null);
  const [desvios, setDesvios] = useState<Desvio[] | null>(null);
  const [errorDesvios, setErrorDesvios] = useState<string | null>(null);
  const [variacion, setVariacion] = useState<Variacion | null>(null);
  // El periodo VIGENTE: una respuesta que llega para otro periodo se descarta.
  const periodoSelRef = useRef<string | null>(null);
  const errorDelPeriodo = errorCarga && errorCarga.id === periodoSel ? errorCarga.mensaje : null;
  // Derivado, no un estado más: si hay periodo elegido y todavía no llegó su proyección, se está pidiendo.
  const cargando = recargando || (periodoSel !== null && proy?.periodo_id !== periodoSel && !errorDelPeriodo);

  // ── Vista ──────────────────────────────────────────────────────────────────
  // La sede YA NO se guarda entre visitas: el 15/09 la pantalla abría con «TRU»
  // de la vez anterior y mostraba «Planilla (0)» sin que nadie lo hubiera pedido.
  const [sedeFiltro, setSedeFiltro] = useState("todas");
  const [nombreFiltro, setNombreFiltro] = useState("");
  const [soloRevisar, setSoloRevisar] = useState(false);
  const [tablaTab, setTablaTab] = useState<TipoVinculo>("planilla");
  // Qué FILA está abierta en el panel — no qué persona. `claveFila` (persona_id
  // + grupo) porque alguien que cambió de tipo_vinculo a mitad de periodo
  // tiene dos filas, y persona_id solo no alcanza para saber cuál de las dos.
  const [filaAbiertaClave, setFilaAbiertaClave] = useState<string | null>(null);
  const disparadorPersona = useRef<HTMLElement | null>(null);
  const [mostrandoHistorial, setMostrandoHistorial] = useState(false);
  const [mostrandoProvisiones, setMostrandoProvisiones] = useState(false);
  const [feriadosAbierto, setFeriadosAbierto] = useState(false);
  const disparadorMenu = useRef<HTMLElement | null>(null);

  // ── Acciones con diálogo ───────────────────────────────────────────────────
  const [revisandoGrupo, setRevisandoGrupo] = useState<TipoVinculo | null>(null);
  // El detalle de «qué frena / qué revisar» arranca plegado: la franja de arriba ya dice cuántos hay y cuál frena el pago.
  const [atencionAbierta, setAtencionAbierta] = useState(false);
  const [reabrirModal, setReabrirModal] = useState<TipoVinculo | null>(null);
  const [reabrirMotivo, setReabrirMotivo] = useState("");
  const [repagoModal, setRepagoModal] = useState(false);
  const [repagoMotivo, setRepagoMotivo] = useState("");
  const [eliminarModal, setEliminarModal] = useState(false);
  const [eliminarTexto, setEliminarTexto] = useState("");
  const [confirmBulk, setConfirmBulk] = useState(false);
  // El checklist personal de pago por persona (0562) — nunca el pago oficial del grupo.
  const [confirmandoPago, setConfirmandoPago] = useState<Fila | null>(null);
  const [desmarcandoPago, setDesmarcandoPago] = useState<Fila | null>(null);
  const [desmarcarMotivo, setDesmarcarMotivo] = useState("");
  const [guardandoPago, setGuardandoPago] = useState(false);
  const [verHistorialPago, setVerHistorialPago] = useState<Fila | null>(null);
  const [historialPago, setHistorialPago] = useState<EventoPagoPersona[] | null>(null);
  const [errorHistorialPago, setErrorHistorialPago] = useState<string | null>(null);
  const [pagoFiltro, setPagoFiltro] = useState<"todas" | "pendientes" | "pagadas">("todas");
  const [guardandoBulk, setGuardandoBulk] = useState(false);

  // ── Simulador (solo lectura, nada se guarda) ───────────────────────────────
  const [mostrandoSim, setMostrandoSim] = useState(false);
  const [simIni, setSimIni] = useState(() => hoyLima());
  const [simFin, setSimFin] = useState(() => hoyLima());
  const [simTocado, setSimTocado] = useState(false);
  const [simProy, setSimProy] = useState<Proyeccion | null>(null);
  const [simCargando, setSimCargando] = useState(false);
  const [simError, setSimError] = useState<string | null>(null);
  const reqIdSim = useRef(0);

  // Si el rol no llega en ~6 s, avisar en vez de un «Cargando…» eterno.
  const [rolDemorado, setRolDemorado] = useState(false);
  // Cuando el rol llega el aviso ya no se dibuja (ver «Acceso» abajo): no hace falta apagarlo.
  useEffect(() => {
    if (rol !== null) return;
    const t = window.setTimeout(() => setRolDemorado(true), 6000);
    return () => window.clearTimeout(t);
  }, [rol]);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      if (!data.session) router.replace("/admin/login");
    });
  }, [supabase, router]);

  // ── Carga de periodos ──────────────────────────────────────────────────────
  // Se TRAE sin tocar el estado y se APLICA aparte: el efecto de arranque solo
  // escribe estado desde la respuesta, que es lo que el linter exige con razón.
  const traerPeriodos = useCallback(async () => supabase.rpc("fn_periodos"), [supabase]);

  const aplicarPeriodos = useCallback(
    ({ data, error }: { data: unknown; error: { message: string } | null }): PeriodoInfo[] | null => {
      setErrorPeriodos(error ? error.message : null);
      if (error) return null;
      const lista = (data as PeriodoInfo[] | null) ?? [];
      setPeriodos(lista);
      setPeriodoSel((prev) => {
        if (prev && lista.some((p) => p.id === prev)) return prev;
        // Si el periodo que se veía dejó de existir (eliminado desde otra pestaña), cae al más reciente.
        if (prev) return lista[0]?.id ?? null;
        // Al entrar: el sin pagar que contiene a hoy, o el más antiguo sin pagar (decisión 2026-09-12).
        return periodoInicialSugerido(lista, hoyLima())?.id ?? lista[0]?.id ?? null;
      });
      return lista;
    },
    [],
  );

  const cargarPeriodos = useCallback(async (): Promise<PeriodoInfo[] | null> => {
    if (!puedeVer) return null;
    return aplicarPeriodos(await traerPeriodos());
  }, [puedeVer, traerPeriodos, aplicarPeriodos]);

  useEffect(() => {
    if (!puedeVer) return;
    let vigente = true;
    void traerPeriodos().then((r) => { if (vigente) aplicarPeriodos(r); });
    return () => { vigente = false; };
  }, [puedeVer, traerPeriodos, aplicarPeriodos]);

  const periodoActual = useMemo(() => periodos?.find((p) => p.id === periodoSel) ?? null, [periodos, periodoSel]);
  // fn_periodos ordena por fecha_fin desc: el primero es el último periodo.
  const esUltimo = periodos !== null && periodos.length > 0 && periodoSel === periodos[0].id;

  // ── Carga del periodo seleccionado ─────────────────────────────────────────
  // Igual que los periodos: se TRAE sin tocar el estado y se APLICA aparte.
  const traerPeriodo = useCallback(async (id: string): Promise<DatosDelPeriodo> => {
    const { data, error } = await supabase.rpc("fn_proyeccion_periodo", { p_periodo_id: id });
    if (error) return { id, error: error.message, proy: null, grupos: null, gc: null, liquidadas: {}, fechasCese: {}, historial: null, pagos: null };
    const proyeccion = data as unknown as Proyeccion;
    const ids = (proyeccion.filas ?? []).map((f) => f.persona_id);

    // Todo lo de apoyo falla suave y va en paralelo.
    // · Estado por grupo (0323): sin él, todo se lee como abierto — el defecto
    //   seguro sigue pidiendo revisión en vez de dar algo por pagado.
    // · Grati/CTS: sin él, el formulario no ofrece esas opciones.
    // · Liquidaciones que se solapan (0210).
    // · La fecha de cese no viaja en la fila del cálculo: se lee de `personas`;
    //   sin ella, la insignia dice «inactiva, sin fecha» en vez de inventar una.
    // · Historial de reaperturas y repagos (reversas_pago, 0066/0323).
    // · El checklist personal de pago por persona (fn_pago_personas_estado, 0562) — sin
    //   esto, la columna «Pagado» no se dibuja; no frena nada más si falla.
    const [gruposR, gcR, liqR, cesesR, revR, pagosR] = await Promise.all([
      supabase.rpc("fn_periodo_grupos_estado", { p_periodo_id: id }),
      supabase.rpc("fn_grati_cts_periodo", { p_periodo_id: id }),
      supabase.rpc("fn_liquidaciones_del_periodo", { p_periodo_id: id }),
      ids.length > 0
        ? supabase.from("personas").select("id, fecha_cese").in("id", ids)
        : Promise.resolve({ data: [] as { id: string; fecha_cese: string | null }[], error: null }),
      supabase
        .from("reversas_pago")
        .select("id, revertido_at, motivo, tipo, grupo, personas(nombres, apellidos)")
        .eq("periodo_id", id)
        .order("revertido_at", { ascending: false }),
      supabase.rpc("fn_pago_personas_estado", { p_periodo_id: id }),
    ]);

    const g = (gcR.error ? null : gcR.data) as unknown as {
      grati_aplica: boolean; grati_concepto: string; cts_aplica: boolean; cts_concepto: string; be_concepto: string;
      personas: { persona_id: string; grati: number; cts: number; be: number }[];
    } | null;

    return {
      id,
      error: null,
      proy: proyeccion,
      grupos: gruposR.error ? null : ((gruposR.data as unknown as GrupoPago[]) ?? null),
      gc: g ? {
        gratiAplica: Boolean(g.grati_aplica), gratiConcepto: g.grati_concepto ?? "",
        ctsAplica: Boolean(g.cts_aplica), ctsConcepto: g.cts_concepto ?? "", beConcepto: g.be_concepto ?? "",
        porPersona: Object.fromEntries((g.personas ?? []).map((x) => [x.persona_id, { grati: Number(x.grati) || 0, cts: Number(x.cts) || 0, be: Number(x.be) || 0 }])),
      } : null,
      liquidadas: (liqR.error ? null : (liqR.data as unknown as Record<string, Liquidada> | null)) ?? {},
      fechasCese: Object.fromEntries(((cesesR.data ?? []) as { id: string; fecha_cese: string | null }[]).map((c) => [c.id, c.fecha_cese])),
      historial: revR.error ? null : ((revR.data as unknown as Reversa[] | null) ?? null),
      pagos: pagosR.error ? null : ((pagosR.data as unknown as EstadoPagoPersona[] | null) ?? null),
    };
  }, [supabase]);

  const aplicarPeriodo = useCallback((r: DatosDelPeriodo) => {
    if (r.id !== periodoSelRef.current) return; // llegó tarde: ya se eligió otro periodo
    setErrorCarga(r.error ? { id: r.id, mensaje: r.error } : null);
    if (r.error) return;
    setProy(r.proy);
    setGrupos(r.grupos);
    setGc(r.gc);
    setLiquidadas(r.liquidadas);
    setFechasCese(r.fechasCese);
    setHistorial(r.historial);
    setPagosPersona(r.pagos);
  }, []);

  /** Recarga el periodo que se está viendo — después de una escritura. */
  const cargarProyeccion = useCallback(async () => {
    const id = periodoSelRef.current;
    if (!puedeVer || !id) return;
    setRecargando(true);
    const r = await traerPeriodo(id);
    setRecargando(false);
    aplicarPeriodo(r);
  }, [puedeVer, traerPeriodo, aplicarPeriodo]);

  useEffect(() => {
    periodoSelRef.current = periodoSel;
    if (!puedeVer || !periodoSel) return;
    let vigente = true;
    void traerPeriodo(periodoSel).then((r) => { if (vigente) aplicarPeriodo(r); });
    return () => { vigente = false; };
  }, [periodoSel, puedeVer, traerPeriodo, aplicarPeriodo]);

  function elegirPeriodo(id: string | null) {
    // Cambiar de periodo cierra lo abierto y despinta la proyección vieja: no puede quedar visible ni editable.
    setFilaAbiertaClave(null);
    setProy(null);
    setPeriodoSel(id);
  }

  // Solo con un periodo pagado existe una foto contra la cual comparar.
  const cargarDesvios = useCallback(async (): Promise<{ desvios: Desvio[] | null; error: string | null }> => {
    if (!puedeVer || !periodoActual || periodoActual.estado !== "pagado") return { desvios: null, error: null };
    const { data, error } = await supabase.rpc("fn_planilla_foto_diferencias", { p_periodo_id: periodoActual.id });
    // Si falla no se dice «todo cuadra»: se muestra el error.
    return error ? { desvios: null, error: error.message } : { desvios: (data as unknown as Desvio[]) ?? [], error: null };
  }, [supabase, puedeVer, periodoActual]);
  const refrescarDesvios = useCallback(async () => {
    const r = await cargarDesvios();
    setDesvios(r.desvios);
    setErrorDesvios(r.error);
  }, [cargarDesvios]);
  useEffect(() => {
    let vigente = true;
    void cargarDesvios().then((r) => {
      if (!vigente) return;
      setDesvios(r.desvios);
      setErrorDesvios(r.error);
    });
    return () => { vigente = false; };
  }, [cargarDesvios]);

  const pedirVariacion = useCallback(async (): Promise<Variacion | null> => {
    if (!puedeVer || !periodoActual) return null;
    const { data, error } = await supabase.rpc("fn_planilla_variacion", { p_periodo_id: periodoActual.id });
    return error ? null : ((data as unknown as Variacion) ?? null);
  }, [supabase, puedeVer, periodoActual]);
  useEffect(() => {
    let vigente = true;
    void pedirVariacion().then((v) => { if (vigente) setVariacion(v); });
    return () => { vigente = false; };
  }, [pedirVariacion]);

  // ── Derivados: TODO sobre el periodo completo ──────────────────────────────
  const filasTodas = useMemo(() => proy?.filas ?? [], [proy]);
  const porGrupo = useMemo(() => agruparPorGrupo(filasTodas), [filasTodas]);
  const grupoDePersona = useMemo(
    () => new Map(filasTodas.map((f) => [f.persona_id, grupoDe(f)] as const)),
    [filasTodas],
  );
  const ceses = useMemo(() => {
    const m = new Map<string, Cese>();
    if (!proy) return m;
    for (const f of filasTodas) m.set(f.persona_id, ceseRespectoDelPeriodo(f.estado, fechasCese[f.persona_id], proy.fecha_ini, proy.fecha_fin));
    return m;
  }, [filasTodas, fechasCese, proy]);
  // Llave por FILA (claveFila), no por persona: alguien con dos filas en el
  // periodo (cambió de tipo_vinculo a mitad de mes) necesita sus dos listas de
  // hallazgos por separado — con `persona_id` a secas, la segunda fila procesada
  // pisaba a la primera y las dos terminaban leyendo el hallazgo de una sola.
  const hallazgos = useMemo(() => {
    const m = new Map<string, Hallazgo[]>();
    for (const f of filasTodas) {
      m.set(claveFila(f), hallazgosDePersona(f, { liquidada: liquidadas[f.persona_id] ?? null, cese: ceses.get(f.persona_id) ?? null }));
    }
    return m;
  }, [filasTodas, liquidadas, ceses]);
  const hallazgosAgrupados = useMemo(
    () => agruparHallazgos(filasTodas.map((f) => ({ fila: f, hallazgos: hallazgos.get(claveFila(f)) ?? [] }))),
    [filasTodas, hallazgos],
  );
  const totalesPeriodo = useMemo(() => sumarFilas(filasTodas), [filasTodas]);

  // Pestañas: «planilla» siempre, y toda otra que tenga gente EN EL PERIODO (no en lo filtrado).
  const tabsVisibles = useMemo(
    () => TIPOS_VINCULO.filter((g) => g === "planilla" || (porGrupo.get(g)?.length ?? 0) > 0),
    [porGrupo],
  );
  const tab = tabsVisibles.includes(tablaTab) ? tablaTab : "planilla";
  const filasGrupo = useMemo(() => porGrupo.get(tab) ?? [], [porGrupo, tab]);
  const totalesGrupo = useMemo(() => sumarFilas(filasGrupo), [filasGrupo]);
  const estadoGrupo = useMemo(() => grupos?.find((g) => g.grupo === tab) ?? null, [grupos, tab]);
  const grupoPagado = estadoGrupo?.estado === "pagado";

  // El checklist personal de pago por persona (0562): por persona_id, de TODO el periodo
  // (como hallazgos/ceses) — cada tabla busca ahí lo suyo por persona_id.
  const pagosPorPersona = useMemo(
    () => new Map((pagosPersona ?? []).map((p) => [p.persona_id, p] as const)),
    [pagosPersona],
  );
  // Solo admin, y solo mientras «tab» sigue abierto: una vez congelado el grupo, es de solo lectura.
  const puedeMarcarPago = puedeMarcarPagoPersona(rol) && !grupoPagado;
  const resumenPago = useMemo(() => {
    let marcadas = 0, monto = 0;
    for (const f of filasGrupo) {
      const e = pagosPorPersona.get(f.persona_id);
      if (e?.marcado) { marcadas++; monto += f.total; }
    }
    return { marcadas, monto };
  }, [filasGrupo, pagosPorPersona]);
  const todosPagadosDelGrupo = filasGrupo.length > 0 && resumenPago.marcadas === filasGrupo.length;

  // Filtros: SOLO la tabla.
  const sedes = useMemo(() => Array.from(new Set(filasTodas.map((f) => f.sede))).sort(), [filasTodas]);
  const nombreBuscado = nombreFiltro.trim().normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase();
  const filtrado = sedeFiltro !== "todas" || nombreBuscado !== "" || soloRevisar || pagoFiltro !== "todas";
  const filasVisibles = useMemo(
    () => filasGrupo.filter((f) =>
      (sedeFiltro === "todas" || f.sede === sedeFiltro)
      && (!nombreBuscado || f.nombre.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase().includes(nombreBuscado))
      && (!soloRevisar || (hallazgos.get(claveFila(f)) ?? []).some((h) => h.severidad !== "informa"))
      && (pagoFiltro === "todas"
          || (pagoFiltro === "pagadas") === (pagosPorPersona.get(f.persona_id)?.marcado ?? false))),
    [filasGrupo, sedeFiltro, nombreBuscado, soloRevisar, hallazgos, pagoFiltro, pagosPorPersona],
  );
  const limpiarFiltros = () => { setSedeFiltro("todas"); setNombreFiltro(""); setSoloRevisar(false); setPagoFiltro("todas"); };

  const lectura = periodoActual ? lecturaDelEstado(periodoActual, grupos, hoy) : null;
  const avance = proy ? avanceDelPeriodo(proy.fecha_ini, proy.fecha_fin, hoy) : null;
  const vencidosOtros = useMemo(
    () => (periodos ? periodosVencidosSinPagar(periodos, hoy).filter((p) => p.id !== periodoSel) : []),
    [periodos, hoy, periodoSel],
  );
  const anterioresSinPagar = useMemo(
    () => (periodos && periodoActual ? periodosAnterioresSinPagar(periodos, periodoActual) : []),
    [periodos, periodoActual],
  );

  // Qué grupo falta en cada periodo pendiente que no es este. Son pocos (uno o dos): una llamada cada uno.
  const idsPendientesOtros = useMemo(
    () => Array.from(new Set([...vencidosOtros, ...anterioresSinPagar].map((p) => p.id))).sort().join(","),
    [vencidosOtros, anterioresSinPagar],
  );
  useEffect(() => {
    if (!puedeVer || !idsPendientesOtros) return;
    let vigente = true;
    void Promise.all(idsPendientesOtros.split(",").map(async (id) => {
      const { data, error } = await supabase.rpc("fn_periodo_grupos_estado", { p_periodo_id: id });
      return [id, error ? null : (data as unknown as GrupoPago[])] as const;
    })).then((pares) => {
      if (!vigente) return;
      setGruposDeOtros(Object.fromEntries(pares.filter(([, g]) => g !== null)) as Record<string, GrupoPago[]>);
    });
    return () => { vigente = false; };
  }, [supabase, puedeVer, idsPendientesOtros]);

  const faltanEn = (id: string): TipoVinculo[] =>
    (gruposDeOtros[id] ?? []).filter((g) => g.personas > 0 && g.estado !== "pagado").map((g) => g.grupo);
  const anterioresParaCierre: AnteriorPendiente[] = anterioresSinPagar.map((p) => ({ periodo: p, faltan: faltanEn(p.id) }));

  // Desvíos de un pagado: solo los del grupo de la pestaña, porque «volver a pagar» recalcula ese grupo.
  const desviosDelGrupo = useMemo(
    () => (desvios ?? []).filter((d) => (grupoDePersona.get(d.persona_id) ?? "planilla") === tab),
    [desvios, grupoDePersona, tab],
  );

  // Los meses que un retroactivo puede corregir: PAGADOS y anteriores al que se ve (0305).
  const origenes = useMemo(() => {
    if (!periodos || !periodoActual) return [];
    return periodos
      .filter((p) => p.estado === "pagado" && p.fecha_fin < periodoActual.fecha_ini)
      .sort((a, b) => b.fecha_fin.localeCompare(a.fecha_fin))
      .map((p) => ({ id: p.id, etiqueta: nombrePeriodo(p) }));
  }, [periodos, periodoActual]);

  // Grati/CTS/bonificación pendientes (0355), del mismo dato que autocompleta cada persona.
  const pendientesGratiCts = useMemo(() => {
    if (!gc) return null;
    let personas = 0, movimientos = 0, total = 0;
    for (const v of Object.values(gc.porPersona)) {
      const suma = v.grati + v.be + v.cts;
      if (suma <= 0) continue;
      personas++;
      movimientos += (v.grati > 0 ? 1 : 0) + (v.be > 0 ? 1 : 0) + (v.cts > 0 ? 1 : 0);
      total += suma;
    }
    return personas > 0 ? { personas, movimientos, total } : null;
  }, [gc]);

  const filaAbierta = filaAbiertaClave ? filasTodas.find((f) => claveFila(f) === filaAbiertaClave) ?? null : null;
  const cesaron = (filas: Fila[]) =>
    filas.filter((f) => { const c = ceses.get(f.persona_id); return c != null && c.tipo !== "despues"; }).length;

  // `grupo` viene de quien llama (cada hallazgo ya sabe de qué fila es, ver
  // HallazgoAgrupado.personas) — no se vuelve a adivinar con grupoDePersona,
  // que tiene el mismo problema de "la última fila pisa a la anterior" que
  // tenía `hallazgos` antes de esta migración de llave.
  function abrirPersonaPorId(personaId: string, grupo: TipoVinculo) {
    setTablaTab(grupo);
    disparadorPersona.current = document.activeElement as HTMLElement | null;
    setFilaAbiertaClave(`${personaId}:${grupo}`);
  }

  async function recargarTodo() {
    await Promise.all([cargarPeriodos(), cargarProyeccion()]);
  }

  // ── Crear / eliminar periodo ───────────────────────────────────────────────
  const inicioEncadenado = periodos && periodos.length > 0 ? sumarDias(periodos[0].fecha_fin, 1) : null;

  function abrirNuevo() {
    if (inicioEncadenado && periodos) {
      const sugerido = mismoDiaMesSiguiente(periodos[0].fecha_fin);
      const min = sumarDias(inicioEncadenado, 19), max = sumarDias(inicioEncadenado, 45);
      setNuevoFin(sugerido < min ? min : sugerido > max ? max : sugerido);
    }
    setMostrandoNuevo((v) => !v);
  }

  async function crearPeriodo(fin: string, ini?: string) {
    if (!fin) { avisar("error", "Pon la fecha de cierre del periodo."); return; }
    setCreandoPeriodo(true);
    const { data, error } = await supabase.rpc("fn_crear_periodo", ini ? { p_fecha_fin: fin, p_fecha_ini: ini } : { p_fecha_fin: fin });
    setCreandoPeriodo(false);
    if (error) { avisar("error", mensajeDeError(error, "crear el periodo")); return; }
    const nuevo = data as unknown as { id: string; fecha_ini: string; fecha_fin: string };
    avisar("ok", `Periodo creado: ${fechaCorta(nuevo.fecha_ini)} → ${fechaCorta(nuevo.fecha_fin)}.`);
    setMostrandoNuevo(false);
    await cargarPeriodos();
    elegirPeriodo(nuevo.id);
  }

  const algunGrupoPagado = (grupos ?? []).some((g) => g.estado === "pagado");
  const puedeEliminar = esUltimo && periodoActual?.estado === "abierto" && !algunGrupoPagado;
  const perdidaAlEliminar = useMemo(() => {
    const movs = filasTodas.flatMap((f) => f.movimientos ?? []);
    return {
      movimientos: movs.length,
      bonos: movs.filter((m) => m.tipo === "bono").reduce((a, m) => a + m.monto, 0),
      descuentos: movs.filter((m) => m.tipo === "descuento").reduce((a, m) => a + m.monto, 0),
      yaPagados: movs.filter((m) => m.tipo === "descuento" && m.concepto.startsWith("Ya pagado el")).length,
    };
  }, [filasTodas]);
  const palabraEliminar = periodoActual ? MESES_LARGO[periodoActual.mes_etiqueta - 1] : "";

  async function confirmarEliminar() {
    if (!periodoActual) return;
    setGuardandoPeriodo(true);
    const { error } = await supabase.rpc("fn_eliminar_periodo", { p_periodo_id: periodoActual.id });
    setGuardandoPeriodo(false);
    if (error) { avisar("error", mensajeDeError(error, "eliminar el periodo")); return; }
    setEliminarModal(false);
    avisar("ok", "Periodo eliminado.");
    const lista = await cargarPeriodos();
    elegirPeriodo(lista && lista.length > 0 ? lista[0].id : null);
  }

  // ── Pagar / reabrir / volver a pagar (por grupo, 0323) ────────────────────
  async function confirmarPago() {
    if (!periodoActual || !revisandoGrupo) return;
    const grupo = revisandoGrupo;
    setGuardandoPeriodo(true);
    const { error } = await supabase.rpc("fn_periodo_pagado", { p_periodo_id: periodoActual.id, p_pagado: true, p_grupo: grupo });
    setGuardandoPeriodo(false);
    // La base puede frenar igual (un freno que la pantalla no ve): el mensaje lo nombra y no se guarda nada a medias.
    if (error) { avisar("error", mensajeDeError(error, "registrar el pago")); return; }
    setRevisandoGrupo(null);
    avisar("ok", `«${TIPO_VINCULO_LABEL[grupo]}» quedó pagado y congelado.`);
    await recargarTodo();
  }

  async function confirmarReabrir() {
    if (!periodoActual || !reabrirModal) return;
    const motivo = reabrirMotivo.trim();
    if (motivo.length < 4) { avisar("error", "El motivo de la reapertura es obligatorio (mínimo 4 caracteres)."); return; }
    const grupo = reabrirModal;
    setGuardandoPeriodo(true);
    const { error } = await supabase.rpc("fn_revertir_pago", { p_periodo_id: periodoActual.id, p_motivo: motivo, p_grupo: grupo });
    setGuardandoPeriodo(false);
    if (error) { avisar("error", mensajeDeError(error, "reabrir")); return; }
    setReabrirModal(null);
    avisar("ok", `«${TIPO_VINCULO_LABEL[grupo]}» reabierto con registro. Corrige lo necesario y vuelve a confirmar el pago.`);
    await recargarTodo();
  }

  // Volver a pagar NO reabre: los candados de los marcajes no se levantan (fn_repagar_periodo).
  async function confirmarRepago() {
    if (!periodoActual) return;
    const motivo = repagoMotivo.trim();
    if (motivo.length < 4) { avisar("error", "El motivo es obligatorio: volver a pagar cambia una cifra que ya se entregó."); return; }
    setGuardandoPeriodo(true);
    const { data, error } = await supabase.rpc("fn_repagar_periodo", { p_periodo_id: periodoActual.id, p_motivo: motivo, p_grupo: tab });
    setGuardandoPeriodo(false);
    if (error) { avisar("error", mensajeDeError(error, "volver a pagar")); return; }
    setRepagoModal(false);
    const d = Number((data as unknown as { diferencia: number } | null)?.diferencia ?? 0);
    avisar("ok", d === 0 ? "Copia nueva guardada. El total no cambió." : `Copia nueva guardada. El total ${d > 0 ? "subió" : "bajó"} ${formatSoles(Math.abs(d))}.`);
    await Promise.all([recargarTodo(), refrescarDesvios()]);
  }

  // ── El checklist personal de pago por persona (0562) ────────────────────────
  // Nunca el pago oficial del grupo: solo marca/desmarca en planilla_pago_persona_eventos.
  async function confirmarMarcarPago() {
    if (!periodoActual || !confirmandoPago) return;
    setGuardandoPago(true);
    const { data, error } = await supabase.rpc("fn_pago_persona_marcar", {
      p_periodo_id: periodoActual.id, p_persona_id: confirmandoPago.persona_id,
    });
    setGuardandoPago(false);
    if (error) { avisar("error", mensajeDeError(error, "marcar el pago")); return; }
    const fila = Array.isArray(data) ? data[0] : null;
    setConfirmandoPago(null);
    avisar("ok", `${confirmandoPago.nombre} · ${formatSoles((fila as { monto: number } | null)?.monto ?? confirmandoPago.total)} marcada como pagada.`);
    await cargarProyeccion();
  }

  function abrirDesmarcarPago(f: Fila) {
    setDesmarcarMotivo("");
    setDesmarcandoPago(f);
  }

  async function confirmarDesmarcarPago() {
    if (!periodoActual || !desmarcandoPago) return;
    const motivo = desmarcarMotivo.trim();
    if (motivo.length < 3) { avisar("error", "Escribe por qué se desmarca (al menos 3 caracteres)."); return; }
    setGuardandoPago(true);
    const { error } = await supabase.rpc("fn_pago_persona_desmarcar", {
      p_periodo_id: periodoActual.id, p_persona_id: desmarcandoPago.persona_id, p_motivo: motivo,
    });
    setGuardandoPago(false);
    if (error) { avisar("error", mensajeDeError(error, "desmarcar el pago")); return; }
    avisar("ok", `${desmarcandoPago.nombre} vuelve a quedar pendiente de pago.`);
    setDesmarcandoPago(null);
    await cargarProyeccion();
  }

  async function abrirHistorialPago(f: Fila) {
    if (!periodoActual) return;
    setVerHistorialPago(f);
    setHistorialPago(null);
    setErrorHistorialPago(null);
    const { data, error } = await supabase
      .from("planilla_pago_persona_eventos")
      .select("tipo, monto, motivo, creado_at, personas:creado_por(nombres, apellidos)")
      .eq("periodo_id", periodoActual.id)
      .eq("persona_id", f.persona_id)
      .order("secuencia", { ascending: true });
    if (error) { setErrorHistorialPago(mensajeDeError(error, "traer el historial")); return; }
    type Fila_ = { tipo: "marcado" | "desmarcado"; monto: number; motivo: string | null; creado_at: string; personas: { nombres: string; apellidos: string | null } | null };
    setHistorialPago(((data ?? []) as unknown as Fila_[]).map((e) => ({
      tipo: e.tipo, monto: e.monto, motivo: e.motivo, creado_at: e.creado_at,
      creado_por_nombre: e.personas ? [e.personas.nombres, e.personas.apellidos].filter(Boolean).join(" ") : null,
    })));
  }

  async function agregarPendientesGratiCts() {
    if (!proy?.periodo_id) return;
    setGuardandoBulk(true);
    const { data, error } = await supabase.rpc("fn_grati_cts_agregar_pendientes", { p_periodo_id: proy.periodo_id });
    setGuardandoBulk(false);
    setConfirmBulk(false);
    if (error) { avisar("error", mensajeDeError(error, "agregar los pendientes")); return; }
    const r = data as unknown as {
      agregados: { nombre: string }[];
      fallidos: { nombre: string; categoria: string; motivo: string }[];
      total_agregado: number;
    };
    if (r.agregados.length > 0) avisar("ok", `Se agregaron ${r.agregados.length} movimiento(s) por ${formatSoles(r.total_agregado)}.`);
    if (r.fallidos.length > 0) avisar("error", `${r.fallidos.length} no se pudieron agregar — ` + r.fallidos.map((f) => `${f.nombre}: ${f.motivo}`).join(" · "));
    if (r.agregados.length === 0 && r.fallidos.length === 0) avisar("ok", "No había nada pendiente por agregar.");
    await cargarProyeccion();
  }

  // ── CSV para el contador ───────────────────────────────────────────────────
  // Decisión del 2026-09-15: el CSV es la planilla, no la vista. Sale SIEMPRE
  // completo —todos los grupos, sin filtros— con la columna de grupo y todas
  // las partidas que entran al total, para que la columna `total` se pueda
  // reconstruir sumando las demás. Hasta hoy seguía el filtro y le faltaban
  // movilidad, educación, pensión y los recargos.
  function descargarCsvPlanilla() {
    if (!proy || proy.simulacion) return;
    const filas = filasCsvPlanilla(filasTodas, (id) => ceses.get(id) ?? null);
    const columnas = filas.length > 0 ? Object.keys(filas[0]) : [];
    descargarCsv(`planilla-${proy.fecha_ini}_${proy.fecha_fin}-completa.csv`, generarCsv(filas, columnas));
  }

  // ── Simulación ─────────────────────────────────────────────────────────────
  function alternarSim() {
    // Si nadie tocó las fechas, arrancan con el rango del periodo que se está viendo.
    if (!mostrandoSim && proy && !simTocado) { setSimIni(proy.fecha_ini); setSimFin(proy.fecha_fin); }
    setMostrandoSim((v) => !v);
  }
  async function simular() {
    if (!simIni || !simFin) { avisar("error", "Pon las dos fechas del rango a simular."); return; }
    const mi = ++reqIdSim.current;
    setSimCargando(true);
    setSimError(null);
    const { data, error } = await supabase.rpc("fn_simular_planilla", { p_ini: simIni, p_fin: simFin });
    if (mi !== reqIdSim.current) return;
    setSimCargando(false);
    if (error) { setSimError(error.message); setSimProy(null); return; }
    setSimProy(data as unknown as Proyeccion);
  }
  const simFilasGrupo = useMemo(() => (simProy ? agruparPorGrupo(simProy.filas).get(tab) ?? [] : []), [simProy, tab]);

  // ── Acceso ─────────────────────────────────────────────────────────────────
  if (rol === null) {
    return (
      <main className="flex-1 p-6">
        {rolDemorado
          ? <p className="max-w-md rounded-control bg-rojo/10 px-4 py-3 text-sm text-rojo-profundo">No se pudo identificar tu usuario — cierra sesión y vuelve a entrar.</p>
          : <Cargando />}
      </main>
    );
  }
  if (!puedeVer) {
    return (
      <main className="flex-1 p-6">
        <p className="max-w-md rounded-control bg-rojo/10 px-4 py-3 text-sm text-rojo-profundo">Solo Desarrollo Organizacional puede ver la planilla.</p>
      </main>
    );
  }

  // Personas DISTINTAS, no avisos: quien no marcó y además no tiene horario es una persona por resolver, no dos.
  const personasDe = (sev: (s: Hallazgo["severidad"]) => boolean) =>
    new Set(hallazgosAgrupados.filter((h) => sev(h.severidad)).flatMap((h) => h.personas.map((p) => p.persona_id))).size;
  const personasFrenan = personasDe((s) => s === "bloquea");
  const historialGrupo = (historial ?? []).filter((r) => (r.grupo ?? "planilla") === tab);
  const filasRevisando = revisandoGrupo ? porGrupo.get(revisandoGrupo) ?? [] : [];

  // La acción grande de la franja depende de cómo va el mes (ver accion-principal.ts).
  const accion = accionPrincipalDelPeriodo({ personasFrenan, grupos, grupoDeLaPestana: tab });
  const personasRevisar = personasDe((s) => s === "revisar");
  const verAtencion = () => {
    setAtencionAbierta(true);
    setTimeout(() => document.getElementById("planilla-atencion")?.scrollIntoView({ behavior: "smooth", block: "start" }), 60);
  };

  return (
    <main className="flex-1 p-4 pt-6 sm:p-6">
      <CabeceraPagina
        sobretitulo={sobretituloDeHoy("Pago")}
        titulo="Planilla"
        descripcion="El pago del periodo, por grupo: lo que falta resolver y lo que se cierra."
        ayuda={
          <AyudaPantalla
            titulo="Cómo funciona la planilla"
            intro="La planilla se calcula con lo que el sistema ya registró (marcajes, horarios, ausencias) y se paga por grupo: cerrar «Planilla» no cierra «Prueba»."
            secciones={[
              { titulo: "La franja de arriba", texto: "Dice el total del periodo, en qué estado va y cuántas personas tienen algo por resolver. Lo que FRENA el pago va siempre en rojo; el resto, «por revisar», no impide pagar pero conviene mirarlo antes." },
              { titulo: "El botón grande", texto: "Cambia según el mes: si algo frena el pago, te lleva a resolverlo; si nada frena, abre la revisión de cierre del grupo que falta; cuando todo está pagado, abre las boletas." },
              { titulo: "Cerrar un grupo", texto: "«Revisar cierre» muestra lo que se va a pagar y pide confirmación. Un grupo pagado queda como copia congelada; reabrirlo exige un motivo y queda registrado." },
              { titulo: "El periodo", texto: "Va del día siguiente al último cierre hasta la fecha de cierre que se elija (entre 20 y 46 días). Se lee de la tabla de periodos, nunca se asume el mes calendario." },
            ]}
          />
        }
      />
      <div className="space-y-6">
      {periodos && periodos.length > 0 && (
        <div className="flex flex-wrap items-center gap-2">
          {/* En celular ocupa el ancho entero: el nombre del periodo no puede leerse cortado. */}
          <div className="w-full sm:w-auto">
            <CampoSelect aria-label="Periodo" value={periodoSel ?? ""} onChange={(e) => elegirPeriodo(e.target.value)} className="sm:max-w-[19rem]">
              {periodos.map((p) => (
                <option key={p.id} value={p.id}>
                  {etiquetaPeriodo(p)}{p.estado === "pagado" ? " · pagado" : p.fecha_fin < hoy ? " · sin pagar" : ""}
                </option>
              ))}
            </CampoSelect>
          </div>
          <Boton onClick={abrirNuevo}>+ Nuevo periodo</Boton>
          {/* Las boletas oficiales (0482) siguen a un toque: cuando el periodo ya está pagado son el botón grande de la
              franja; mientras tanto, este. Es un módulo de uso mensual y estuvo tan discreto que se preguntó dónde estaba. */}
          {periodoSel && accion?.tipo !== "boletas" && (
            <Boton onClick={() => router.push(`/admin/planilla/boletas?periodo=${periodoSel}`)} className="inline-flex items-center gap-2">
              <ReceiptText size={16} aria-hidden />
              Boletas del periodo
            </Boton>
          )}
          <Menu
            trigger={({ abierto, alternar }) => (
              <Boton
                aria-label="Más acciones"
                aria-haspopup="menu"
                aria-expanded={abierto}
                onClick={(e) => { disparadorMenu.current = e.currentTarget; alternar(); }}
                className="px-2.5"
              >
                <MoreHorizontal size={16} aria-hidden />
              </Boton>
            )}
          >
            {/* El CSV vivía como botón suelto junto al periodo: es una acción de
                uso ocasional y ocupaba el sitio de lo que se usa cada mes. Al
                menú con la misma condición de siempre: sin proyección, cargando
                o sin filas no hay nada que descargar. */}
            <MenuItem onClick={descargarCsvPlanilla} disabled={!proy || cargando || filasTodas.length === 0}>
              Descargar CSV
              <span className="block text-xs text-taupe">Todos los grupos y partidas del periodo, sin filtros</span>
            </MenuItem>
            <MenuItem onClick={() => setFeriadosAbierto(true)}>Feriados del año…</MenuItem>
            {puedeEliminar && (
              <MenuItem variante="peligro" onClick={() => { setEliminarTexto(""); setEliminarModal(true); }}>
                Eliminar este periodo…
              </MenuItem>
            )}
          </Menu>
        </div>
      )}

      {errorPeriodos && (
        <BannerAviso variante="alerta">
          No se pudieron cargar los periodos: {errorPeriodos}{" "}
          <Boton variante="enlace" onClick={() => void cargarPeriodos()}>Reintentar</Boton>
        </BannerAviso>
      )}
      {periodos === null && !errorPeriodos && <Cargando />}

      {/* ── Sin periodos: arranque ─────────────────────────────────────────── */}
      {periodos !== null && periodos.length === 0 && (
        <BannerAviso variante="neutral" titulo="Crear el primer periodo">
          <p className="mb-4 text-taupe">
            La planilla se paga por periodos encadenados: eliges el día de cierre y el siguiente empieza al día siguiente,
            sin huecos ni días contados dos veces. Solo este primero necesita fecha de inicio. Cada periodo dura entre 20 y 46 días.
          </p>
          <div className="flex flex-wrap items-end gap-3">
            <Campo etiqueta="Fecha de inicio" type="date" value={primerIni} onChange={(e) => setPrimerIni(e.target.value)} />
            <Campo etiqueta="Fecha de cierre" type="date" value={primerFin} onChange={(e) => setPrimerFin(e.target.value)} />
            <Boton variante="primario" onClick={() => void crearPeriodo(primerFin, primerIni)} cargando={creandoPeriodo}>
              Crear periodo
            </Boton>
          </div>
        </BannerAviso>
      )}

      {mostrandoNuevo && inicioEncadenado && periodos && (
        <BannerAviso variante="neutral" titulo="Nuevo periodo">
          <div className="flex flex-wrap items-end gap-3">
            <Campo etiqueta="Inicio (encadenado)" type="date" value={inicioEncadenado} readOnly disabled className="opacity-60" />
            <Campo
              etiqueta="Fecha de cierre" type="date" value={nuevoFin}
              min={sumarDias(inicioEncadenado, 19)} max={sumarDias(inicioEncadenado, 45)}
              onChange={(e) => setNuevoFin(e.target.value)}
            />
            <Boton variante="primario" onClick={() => void crearPeriodo(nuevoFin)} cargando={creandoPeriodo}>Crear periodo</Boton>
            <Boton onClick={() => setMostrandoNuevo(false)}>Cancelar</Boton>
          </div>
          <p className="mt-2 text-xs text-taupe">
            El inicio siempre es el día siguiente al último cierre ({fechaCorta(periodos[0].fecha_fin)}), para que ningún día
            quede fuera ni se pague dos veces. Duración permitida: 20 a 46 días. Crear el siguiente no exige haber pagado este.
          </p>
        </BannerAviso>
      )}

      {periodos !== null && periodos.length > 0 && (
        <>
          {/* ── Periodos terminados que siguen pendientes ───────────────────── */}
          {vencidosOtros.length > 0 && (
            <BannerAviso
              variante="advertencia"
              titulo={vencidosOtros.length === 1
                ? `${nombrePeriodo(vencidosOtros[0])} sigue pendiente de pago`
                : `${vencidosOtros.length} periodos terminados siguen pendientes de pago`}
            >
              <ul className="mt-1 space-y-1.5">
                {vencidosOtros.map((p) => (
                  <li key={p.id} className="flex flex-wrap items-center gap-x-3 gap-y-1">
                    <span className="text-tinta">{etiquetaPeriodo(p)}</span>
                    {faltanEn(p.id).length > 0 && (
                      <span className="text-taupe">falta: {faltanEn(p.id).map((g) => TIPO_VINCULO_LABEL[g]).join(", ")}</span>
                    )}
                    <Boton variante="enlace" className="font-medium" onClick={() => elegirPeriodo(p.id)}>Revisar periodo →</Boton>
                  </li>
                ))}
              </ul>
            </BannerAviso>
          )}

          {errorDelPeriodo && (
            <BannerAviso variante="alerta">
              No se pudo cargar el periodo: {errorDelPeriodo}{" "}
              <Boton variante="enlace" onClick={() => void cargarProyeccion()}>Reintentar</Boton>
            </BannerAviso>
          )}

          {cargando && !proy && <Cargando />}

          {proy && periodoActual && (
            <>
              {/* ── La franja «Para cerrar»: estado, total, qué frena y qué hacer, en UNA fila ── */}
              <TarjetaInfo className="flex flex-wrap items-center gap-x-4 gap-y-3" aria-label="Resumen del periodo">
                <div>
                  <p className="text-xs text-taupe">{lectura === "pagado" ? "Total pagado del periodo" : "Total proyectado del periodo"}</p>
                  <p className="font-serif text-2xl leading-none tabular-nums text-tinta">{formatSoles(totalesPeriodo.total)}</p>
                </div>
                {lectura && (
                  <span className="flex flex-wrap items-center gap-2 text-sm text-taupe">
                    <Insignia variante={LECTURA[lectura].variante}>{LECTURA[lectura].texto}</Insignia>
                    {avance?.estado === "en_curso" && <span>en curso · día {avance.transcurridos} de {avance.dias}</span>}
                  </span>
                )}
                <ParaAtender
                  compacta
                  items={[
                    { clave: "frena", texto: `▲ ${personasFrenan} ${personasFrenan === 1 ? "frena" : "frenan"} el pago`, n: personasFrenan, tono: "rojo" },
                    { clave: "revisar", texto: `${personasRevisar} por revisar`, n: personasRevisar, tono: "ambar" },
                    { clave: "grati", texto: "Gratificación o CTS pendiente", n: pendientesGratiCts ? 1 : 0, tono: "ambar" },
                  ]}
                  activa={atencionAbierta ? (personasFrenan > 0 ? "frena" : personasRevisar > 0 ? "revisar" : pendientesGratiCts ? "grati" : null) : null}
                  alTocar={() => (atencionAbierta ? setAtencionAbierta(false) : verAtencion())}
                />
                <BotonIcono
                  etiqueta={atencionAbierta ? "Ocultar el detalle del periodo" : "Ver el detalle del periodo"}
                  icono={atencionAbierta ? <ChevronUp aria-hidden /> : <ChevronDown aria-hidden />}
                  aria-expanded={atencionAbierta}
                  aria-controls="planilla-atencion"
                  onClick={() => setAtencionAbierta((a) => !a)}
                />
                {/* La acción que toca AHORA según cómo va el mes (accion-principal.ts). Sin acción mientras carga. */}
                <span className="ml-auto">
                  {accion?.tipo === "resolver" && (
                    <Boton variante="primario" onClick={verAtencion}>Resolver lo que frena ({accion.frenan})</Boton>
                  )}
                  {accion?.tipo === "cerrar" && (
                    <Boton variante="primario" disabled={cargando} onClick={() => { setTablaTab(accion.grupo); setRevisandoGrupo(accion.grupo); }}>
                      Revisar cierre de «{TIPO_VINCULO_LABEL[accion.grupo]}» →
                    </Boton>
                  )}
                  {accion?.tipo === "boletas" && periodoSel && (
                    <Link
                      href={`/admin/planilla/boletas?periodo=${periodoSel}`}
                      className="inline-flex items-center gap-2 rounded-control bg-tinta px-4 py-2 text-sm font-medium text-crema transition-colors duration-150 hover:bg-rojo-profundo active:scale-[0.98]"
                    >
                      <ReceiptText size={16} aria-hidden />
                      Boletas del periodo
                    </Link>
                  )}
                </span>
              </TarjetaInfo>
              {/* (Aquí había una fila de pastillas «Planilla pendiente · Prueba pendiente» que hacía lo mismo que las pestañas de abajo:
                  cambiar de grupo. Se quitó el 2026-10-20: el estado de pago de cada grupo ya está en su pestaña —con la palomita
                  cuando está pagado— y, escrito completo con fecha y quién, en la barra bajo la pestaña.) */}
              {/* El contexto del periodo, en una línea gris: lo que antes eran tres cifras y una nota. */}
              <p className="text-xs text-taupe">
                {totalesPeriodo.personas} {totalesPeriodo.personas === 1 ? "persona" : "personas"}
                {cesaron(filasTodas) > 0 ? ` (${cesaron(filasTodas)} cesaron o están inactivas)` : ""}
                {" · "}{fmtHoras(totalesPeriodo.horas)}{avance?.estado === "en_curso" ? " hasta hoy" : ""}
                {" · "}sale de la cuenta {formatSoles(totalesPeriodo.sale_del_banco)}
                {" · "}
                <span title="Las horas de un periodo completo a jornada de 6.5 h diarias: con esta cifra se calcula el valor de la hora del periodo.">
                  base full-time {fmtHoras(proy.base_horas)} (6.5 h × {proy.dias} días)
                </span>
                {" · "}
                {proy.feriados.length === 0
                  ? "sin feriados en este periodo"
                  : `feriados: ${proy.feriados.map((f) => `${fechaCorta(f.fecha)} ${f.nombre}`).join(" · ")}`}
              </p>

              {/* ── El detalle: qué frena, qué revisar, qué cambió. Plegado hasta que se pide. ───────── */}
              {atencionAbierta && (
                <div id="planilla-atencion" className="grid scroll-mt-4 gap-4 xl:grid-cols-[3fr_2fr]">
                  <RequiereAtencion
                    hallazgos={hallazgosAgrupados}
                    grupoActivo={tab}
                    onAbrirPersona={abrirPersonaPorId}
                  extra={pendientesGratiCts ? (
                    <div className="mb-2 rounded-control bg-ambar/10 px-3 py-2 text-sm">
                      <div className="flex flex-wrap items-center justify-between gap-2">
                        <span className="text-ambar">
                          {[gc?.gratiAplica && "Gratificación", gc?.gratiAplica && "Bonificación 9%", gc?.ctsAplica && "CTS"].filter(Boolean).join(" · ")}{" "}
                          pendiente para {pendientesGratiCts.personas} {pendientesGratiCts.personas === 1 ? "persona" : "personas"} — {formatSoles(pendientesGratiCts.total)}
                        </span>
                        {!confirmBulk && (
                          <Boton tamano="sm" onClick={() => setConfirmBulk(true)}>Agregar todo ({pendientesGratiCts.movimientos})</Boton>
                        )}
                      </div>
                      {confirmBulk && (
                        <div className="mt-2 flex flex-wrap items-center justify-end gap-2">
                          <span className="mr-auto text-taupe">
                            Se registran {pendientesGratiCts.movimientos} movimiento(s) por {formatSoles(pendientesGratiCts.total)}. ¿Confirmas?
                          </span>
                          <Boton tamano="sm" onClick={() => setConfirmBulk(false)} disabled={guardandoBulk}>Cancelar</Boton>
                          <Boton tamano="sm" variante="primario" onClick={() => void agregarPendientesGratiCts()} cargando={guardandoBulk}>Agregar</Boton>
                        </div>
                      )}
                    </div>
                  ) : undefined}
                  />
                  {avance && <QueCambio variacion={variacion} avance={avance} fechaFin={proy.fecha_fin} />}
                </div>
              )}

              {/* ── Pestañas por grupo, con conteos del periodo completo ─── */}
              <div>
                {/* Las pastillas SON el selector de grupo (2026-10-20, decidido con Felipe): cada una dice cuántas personas tiene el grupo y
                    si ya se pagó —con la fecha— o sigue pendiente. Antes eran dos controles que hacían lo mismo: estas pastillas y unas
                    pestañas debajo. */}
                <div role="group" aria-label="Grupos del periodo" className="mb-3 flex flex-wrap gap-2">
                  {tabsVisibles.map((g) => {
                    const est = grupos?.find((x) => x.grupo === g);
                    const pagadoG = est?.estado === "pagado";
                    const activo = tab === g;
                    return (
                      <button
                        key={g}
                        type="button"
                        aria-pressed={activo}
                        onClick={() => setTablaTab(g)}
                        className={cx(
                          "inline-flex items-center gap-1.5 rounded-pildora border px-3 py-1.5 text-sm transition-colors duration-150",
                          activo ? "border-tinta bg-tinta text-crema" : "border-sand bg-papel hover:bg-sand/40",
                        )}
                      >
                        <span className={cx("font-medium", activo ? "text-crema" : "text-tinta")}>{TIPO_VINCULO_LABEL[g]} ({porGrupo.get(g)?.length ?? 0})</span>
                        {pagadoG
                          ? <span className={cx("inline-flex items-center gap-1 text-xs", activo ? "text-crema/90" : "text-verde")}><Check size={12} aria-hidden />pagado{est?.pagado_at ? ` ${fechaLargaLima(est.pagado_at)}` : ""}</span>
                          : <span className={cx("text-xs", activo ? "text-crema/80" : "text-taupe")}>pendiente</span>}
                      </button>
                    );
                  })}
                </div>

                {/* ── Barra del grupo: estado, total y la acción principal ── */}
                <div className="flex flex-wrap items-center justify-between gap-3 rounded-superficie border border-sand bg-papel px-4 py-3">
                  <div className="min-w-0 text-sm">
                    <p className="font-medium text-tinta">
                      «{TIPO_VINCULO_LABEL[tab]}» · {totalesGrupo.personas} {totalesGrupo.personas === 1 ? "persona" : "personas"} ·{" "}
                      <span className="tabular-nums">{formatSoles(totalesGrupo.total)}</span>
                    </p>
                    <p className="text-xs text-taupe">
                      {grupoPagado
                        ? `Pagado${estadoGrupo?.pagado_at ? ` el ${fechaLargaLima(estadoGrupo.pagado_at)}` : ""}${estadoGrupo?.pagado_por_nombre ? ` por ${estadoGrupo.pagado_por_nombre}` : ""} — lo que ves es la copia congelada; es la cifra que va a Costos.`
                        : "Abierto: las cifras se recalculan con las horas registradas hasta que se confirme el pago."}
                      {historialGrupo.length > 0 && (
                        <>
                          {" "}
                          <Boton variante="enlace" onClick={() => setMostrandoHistorial((v) => !v)}>
                            {mostrandoHistorial ? "Ocultar historial" : `Historial (${historialGrupo.length})`}
                          </Boton>
                        </>
                      )}
                    </p>
                  </div>
                  {grupoPagado ? (
                    <Boton onClick={() => { setReabrirMotivo(""); setReabrirModal(tab); }} disabled={guardandoPeriodo}>
                      Reabrir «{TIPO_VINCULO_LABEL[tab]}»…
                    </Boton>
                  ) : (
                    <Boton
                      variante="primario"
                      onClick={() => setRevisandoGrupo(tab)}
                      disabled={cargando || filasGrupo.length === 0}
                      title={filasGrupo.length === 0 ? "No hay personas de este grupo en el periodo." : undefined}
                    >
                      Revisar cierre de «{TIPO_VINCULO_LABEL[tab]}» →
                    </Boton>
                  )}
                </div>

                {mostrandoHistorial && historialGrupo.length > 0 && (
                  <ul className="mt-2 space-y-1 rounded-superficie border border-sand bg-papel px-4 py-3 text-sm">
                    {historialGrupo.map((r) => (
                      <li key={r.id}>
                        <span className="text-taupe">{fechaLargaLima(r.revertido_at)}</span> ·{" "}
                        {r.tipo === "repago" ? "Volvió a pagarse" : "Se reabrió"}
                        {r.personas ? ` · ${[r.personas.nombres, r.personas.apellidos].filter(Boolean).join(" ")}` : ""} — «{r.motivo}»
                      </li>
                    ))}
                  </ul>
                )}
              </div>

              {/* ── Checklist personal de pago (0562): ya marcaste a todos, falta el cierre oficial ── */}
              {puedeMarcarPago && todosPagadosDelGrupo && (
                <BannerAviso variante="positivo" titulo={`Ya marcaste a las ${filasGrupo.length} personas de «${TIPO_VINCULO_LABEL[tab]}» como pagadas`}>
                  <p className="text-xs text-taupe">Esto es tu checklist: el pago de «{TIPO_VINCULO_LABEL[tab]}» sigue abierto hasta que confirmes el cierre.</p>
                  <Boton className="mt-3" variante="primario" onClick={() => setRevisandoGrupo(tab)} disabled={cargando}>
                    Revisar cierre de «{TIPO_VINCULO_LABEL[tab]}» →
                  </Boton>
                </BannerAviso>
              )}

              {/* ── Un pagado que dejó de cuadrar: el sistema lo DICE; corregir lo decide una persona ── */}
              {grupoPagado && errorDesvios && (
                <BannerAviso variante="alerta">
                  No se pudo comprobar si este pago sigue cuadrando con los datos de hoy: {errorDesvios}{" "}
                  <Boton variante="enlace" onClick={() => void refrescarDesvios()}>Reintentar</Boton>
                </BannerAviso>
              )}
              {grupoPagado && desviosDelGrupo.length > 0 && (
                <BannerAviso variante="advertencia" titulo={`«${TIPO_VINCULO_LABEL[tab]}» ya está pagado, pero su desglose dejó de coincidir con los datos de hoy`}>
                  <p className="text-xs text-taupe">
                    Alguien corrigió algo de estas fechas después del pago. Lo transferido no cambió: cambió lo que el sistema calcularía ahora.
                  </p>
                  <ul className="mt-2 space-y-0.5 text-xs">
                    {desviosDelGrupo.slice(0, 8).map((d) => (
                      <li key={d.persona_id}>
                        <span className="font-medium">{d.nombre}</span>:{" "}
                        {d.total_foto === null ? "no estaba en la planilla pagada y ahora sí"
                          : d.total_ahora === null ? "estaba en la planilla pagada y ahora no aparece"
                          : `${formatSoles(d.total_foto)} → ${formatSoles(d.total_ahora)} (${d.diferencia > 0 ? "+" : ""}${formatSoles(d.diferencia)})`}
                      </li>
                    ))}
                    {desviosDelGrupo.length > 8 && <li>…y {desviosDelGrupo.length - 8} más.</li>}
                  </ul>
                  <Boton className="mt-3" onClick={() => { setRepagoMotivo(""); setRepagoModal(true); }} disabled={guardandoPeriodo}>
                    Recalcular y volver a pagar «{TIPO_VINCULO_LABEL[tab]}»…
                  </Boton>
                </BannerAviso>
              )}

              {/* ── El checklist personal de pago (0562): cuánto llevas marcado ── */}
              {puedeMarcarPagoPersona(rol) && filasGrupo.length > 0 && (
                <Cifra
                  tamano="sm"
                  etiqueta="Marcadas como pagadas"
                  valor={`${resumenPago.marcadas} de ${filasGrupo.length} · ${formatSoles(resumenPago.monto)}`}
                  tono={todosPagadosDelGrupo ? "positivo" : resumenPago.marcadas > 0 ? "advertencia" : undefined}
                />
              )}

              {/* ── Filtros: solo cambian la tabla ───────────────────────── */}
              <div className="space-y-2">
                <div className="flex flex-wrap items-center gap-3">
                  <div className="relative">
                    <Search size={15} strokeWidth={1.8} aria-hidden className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-taupe" />
                    <Campo value={nombreFiltro} onChange={(e) => setNombreFiltro(e.target.value)} placeholder="Buscar persona…" aria-label="Buscar persona" className="w-52 pl-8" />
                  </div>
                  <CampoSelect aria-label="Sede" value={sedeFiltro} onChange={(e) => setSedeFiltro(e.target.value)}>
                    <option value="todas">Todas las sedes</option>
                    {sedes.map((s) => <option key={s} value={s}>{s}</option>)}
                  </CampoSelect>
                  <CampoCasilla etiqueta="Solo con algo que revisar" checked={soloRevisar} onChange={(e) => setSoloRevisar(e.target.checked)} />
                  <div role="group" aria-label="Filtrar por pagado" className="flex gap-1">
                    <Filtro tamano="sm" activo={pagoFiltro === "todas"} onClick={() => setPagoFiltro("todas")}>Todas</Filtro>
                    <Filtro tamano="sm" activo={pagoFiltro === "pendientes"} onClick={() => setPagoFiltro("pendientes")}>Pendientes</Filtro>
                    <Filtro tamano="sm" activo={pagoFiltro === "pagadas"} onClick={() => setPagoFiltro("pagadas")}>Pagadas</Filtro>
                  </div>
                  {filtrado && <Boton variante="enlace" className="text-sm text-taupe" onClick={limpiarFiltros}>Limpiar filtros</Boton>}
                </div>
                <p className="text-xs text-taupe" aria-live="polite">
                  {filtrado
                    ? `Mostrando ${filasVisibles.length} de ${filasGrupo.length} personas de «${TIPO_VINCULO_LABEL[tab]}». Los filtros no cambian el total, la revisión de cierre ni el CSV.`
                    : `Mostrando las ${filasGrupo.length} personas de «${TIPO_VINCULO_LABEL[tab]}».`}
                </p>
              </div>

              <TablaPlanilla
                filas={filasVisibles}
                totalDelGrupo={filasGrupo.length}
                etiquetaGrupo={TIPO_VINCULO_LABEL[tab]}
                filtrado={filtrado}
                hallazgos={hallazgos}
                ceses={ceses}
                pagos={pagosPorPersona}
                puedeMarcarPago={puedeMarcarPago}
                onMarcarPago={(f) => setConfirmandoPago(f)}
                onDesmarcarPago={abrirDesmarcarPago}
                onVerHistorialPago={(f) => void abrirHistorialPago(f)}
                pruebas={pruebas}
                onAbrir={(f, el) => { disparadorPersona.current = el; setFilaAbiertaClave(claveFila(f)); }}
              />

              {/* ── Provisiones (secundario) ──────────────────────────────── */}
              <section>
                <button type="button" onClick={() => setMostrandoProvisiones((v) => !v)} aria-expanded={mostrandoProvisiones} className="text-sm text-taupe hover:text-tinta hover:underline">
                  {mostrandoProvisiones ? "▾" : "▸"} Provisiones de «{TIPO_VINCULO_LABEL[tab]}» (gratificación · CTS · vacaciones)
                </button>
                {mostrandoProvisiones && (
                  <div className="mt-2">
                    <Tabla className="max-w-3xl">
                      <TablaEncabezado>
                        <Th>Persona</Th>
                        <Th className="text-right">Gratificación</Th>
                        <Th className="text-right">CTS</Th>
                        <Th className="text-right">Vacaciones</Th>
                        <Th className="text-right">Total provisión</Th>
                      </TablaEncabezado>
                      <tbody>
                        {filasVisibles.length === 0 && (
                          <tr><td colSpan={5} className="px-4 py-6 text-center text-taupe">No hay personas para mostrar.</td></tr>
                        )}
                        {filasVisibles.map((f) => (
                          <FilaTabla key={f.persona_id}>
                            <td className="px-4 py-2">{f.nombre}</td>
                            <td className="px-4 py-2 text-right tabular-nums">{formatSoles(f.provision_gratificacion)}</td>
                            <td className="px-4 py-2 text-right tabular-nums">{formatSoles(f.provision_cts)}</td>
                            <td className="px-4 py-2 text-right tabular-nums">{formatSoles(f.provision_vacaciones)}</td>
                            <td className="px-4 py-2 text-right font-medium tabular-nums">{formatSoles(f.provision_total)}</td>
                          </FilaTabla>
                        ))}
                      </tbody>
                      {filasVisibles.length > 0 && (() => {
                        const t = sumarFilas(filasVisibles);
                        return (
                          <tfoot>
                            <tr className="border-t border-sand bg-sand/50">
                              <td className="px-4 py-2 font-medium">{filtrado ? `Subtotal visible (${filasVisibles.length} de ${filasGrupo.length})` : "Total"}</td>
                              <td className="px-4 py-2 text-right font-medium tabular-nums">{formatSoles(t.provision_gratificacion)}</td>
                              <td className="px-4 py-2 text-right font-medium tabular-nums">{formatSoles(t.provision_cts)}</td>
                              <td className="px-4 py-2 text-right font-medium tabular-nums">{formatSoles(t.provision_vacaciones)}</td>
                              <td className="px-4 py-2 text-right font-bold tabular-nums">{formatSoles(t.provision_total)}</td>
                            </tr>
                          </tfoot>
                        );
                      })()}
                    </Tabla>
                    <p className="mt-2 max-w-3xl text-xs text-taupe">
                      Las provisiones NO forman parte del pago del periodo: son lo que se va acumulando para pagar después. Factores MYPE
                      editables en configuración — validar con el contador.
                    </p>
                  </div>
                )}
              </section>

              {/* ── Simulación (herramienta, nunca planilla oficial) ─────── */}
              <section>
                <button type="button" onClick={alternarSim} aria-expanded={mostrandoSim} className="text-sm text-taupe hover:text-tinta hover:underline">
                  {mostrandoSim ? "▾" : "▸"} Simular otro rango de fechas
                </button>
                {mostrandoSim && (
                  <div className="mt-2 rounded-superficie border border-pizarra/30 bg-pizarra/[0.05] p-4">
                    <p className="mb-3 text-sm text-pizarra">
                      Simulación: no es la planilla oficial, no crea periodos y no guarda nada. No incluye bonos ni descuentos,
                      que viven en cada periodo.
                    </p>
                    <div className="flex flex-wrap items-end gap-3">
                      <Campo etiqueta="Desde" type="date" value={simIni} onChange={(e) => { setSimTocado(true); setSimIni(e.target.value); }} />
                      <Campo etiqueta="Hasta" type="date" value={simFin} onChange={(e) => { setSimTocado(true); setSimFin(e.target.value); }} />
                      <Boton variante="primario" onClick={() => void simular()} cargando={simCargando}>Calcular</Boton>
                    </div>
                    <p className="mt-2 text-xs text-taupe">Rango libre de hasta 62 días.</p>
                    {simError && <p className="mt-3 text-sm text-rojo-profundo">No se pudo simular: {simError}</p>}
                    {simProy && !simError && (
                      <div className="mt-3">
                        <p className="mb-2 text-xs text-taupe">
                          {fechaCorta(simProy.fecha_ini)} → {fechaCorta(simProy.fecha_fin)} · {simProy.dias} días · base {fmtHoras(simProy.base_horas)} ·
                          grupo «{TIPO_VINCULO_LABEL[tab]}» (cambia de pestaña arriba para ver otro)
                        </p>
                        <TablaPlanilla
                          filas={simFilasGrupo}
                          totalDelGrupo={simFilasGrupo.length}
                          etiquetaGrupo={`${TIPO_VINCULO_LABEL[tab]} (simulado)`}
                          filtrado={false}
                          simulacion
                        />
                      </div>
                    )}
                  </div>
                )}
              </section>
            </>
          )}
        </>
      )}

      {/* ── Paneles y diálogos ─────────────────────────────────────────────── */}
      {proy?.periodo_id && (
        <PanelPersona
          fila={filaAbierta}
          onCerrar={() => setFilaAbiertaClave(null)}
          volverElFocoA={disparadorPersona}
          periodoId={proy.periodo_id}
          pagado={filaAbierta ? grupos?.find((g) => g.grupo === grupoDe(filaAbierta))?.estado === "pagado" : false}
          liquidada={filaAbierta ? liquidadas[filaAbierta.persona_id] ?? null : null}
          cese={filaAbierta ? ceses.get(filaAbierta.persona_id) ?? null : null}
          hallazgos={filaAbierta ? hallazgos.get(claveFila(filaAbierta)) ?? [] : []}
          gc={gc}
          origenes={origenes}
          supabase={supabase}
          onCambio={cargarProyeccion}
        />
      )}

      <PanelFeriados
        abierto={feriadosAbierto}
        onCerrar={() => setFeriadosAbierto(false)}
        volverElFocoA={disparadorMenu}
        anio={proy?.anio_etiqueta ?? periodoActual?.anio_etiqueta ?? Number(hoy.slice(0, 4))}
        supabase={supabase}
        onCambio={cargarProyeccion}
      />

      {periodoActual && proy && (
        <RevisionCierre
          grupo={revisandoGrupo}
          periodo={periodoActual}
          hoy={hoy}
          totales={sumarFilas(filasRevisando)}
          cesaron={cesaron(filasRevisando)}
          hallazgos={agruparHallazgos(filasRevisando.map((f) => ({ fila: f, hallazgos: hallazgos.get(claveFila(f)) ?? [] })))}
          anteriores={anterioresParaCierre}
          guardando={guardandoPeriodo}
          onCerrar={() => setRevisandoGrupo(null)}
          onConfirmar={() => void confirmarPago()}
        />
      )}

      <Modal
        abierto={reabrirModal !== null}
        onCerrar={() => setReabrirModal(null)}
        bloqueado={guardandoPeriodo}
        titulo={reabrirModal ? `Reabrir «${TIPO_VINCULO_LABEL[reabrirModal]}»` : undefined}
        ancho="md"
      >
        {reabrirModal && (
          <div className="space-y-4 text-sm">
            <p className="text-taupe">Ya está pagado. Mientras esté abierto:</p>
            <ul className="list-disc space-y-1 pl-5 text-taupe">
              <li>se pueden volver a modificar marcajes, correcciones, ausencias, bonos y descuentos de «{TIPO_VINCULO_LABEL[reabrirModal]}» en estas fechas;</li>
              <li>la copia congelada del pago se conserva intacta;</li>
              <li>hay que volver a confirmar el pago cuando termines de corregir.</li>
            </ul>
            <p className="text-taupe">Queda registrado quién lo reabrió, cuándo y por qué.</p>
            {historialGrupo.length > 0 && (
              <p className="text-xs text-taupe">Este grupo ya se reabrió o se volvió a pagar {historialGrupo.length} {historialGrupo.length === 1 ? "vez" : "veces"} en este periodo.</p>
            )}
            <label className="flex flex-col gap-1">
              Motivo (obligatorio)
              <AreaTexto value={reabrirMotivo} onChange={(e) => setReabrirMotivo(e.target.value)} rows={2} autoFocus placeholder="ej. corregir una tardanza mal contada" />
            </label>
            <div className="flex justify-end gap-2">
              <Boton onClick={() => setReabrirModal(null)} disabled={guardandoPeriodo}>Cancelar</Boton>
              <Boton variante="primario" onClick={() => void confirmarReabrir()} cargando={guardandoPeriodo}>Reabrir</Boton>
            </div>
          </div>
        )}
      </Modal>

      <Modal abierto={repagoModal} onCerrar={() => setRepagoModal(false)} bloqueado={guardandoPeriodo} titulo={`Volver a pagar «${TIPO_VINCULO_LABEL[tab]}»`} ancho="sm">
        <p className="mb-4 text-sm text-taupe">
          Se guarda una copia nueva del desglose sin reabrir el periodo. La anterior se conserva y queda registrado quién lo hizo y por qué.
        </p>
        <label className="mb-4 flex flex-col gap-1 text-sm">
          ¿Por qué se vuelve a pagar? (obligatorio)
          <AreaTexto value={repagoMotivo} onChange={(e) => setRepagoMotivo(e.target.value)} rows={2} autoFocus placeholder="ej. se corrigió una marca del 12" />
        </label>
        <div className="flex justify-end gap-2">
          <Boton onClick={() => setRepagoModal(false)} disabled={guardandoPeriodo}>Cancelar</Boton>
          <Boton variante="primario" onClick={() => void confirmarRepago()} cargando={guardandoPeriodo}>Volver a pagar</Boton>
        </div>
      </Modal>

      <Modal abierto={eliminarModal} onCerrar={() => setEliminarModal(false)} bloqueado={guardandoPeriodo} titulo="Eliminar periodo" ancho="md">
        {periodoActual && (
          <div className="space-y-4 text-sm">
            <p>
              Vas a eliminar <strong>{etiquetaPeriodo(periodoActual)}</strong>. Solo se puede eliminar el último periodo, y solo si
              ningún grupo se pagó.
            </p>
            <div className="rounded-control border border-rojo/30 bg-rojo/[0.05] p-3">
              <p className="font-medium text-rojo-profundo">Se borra junto con el periodo:</p>
              {perdidaAlEliminar.movimientos === 0 ? (
                <p className="mt-1">Ningún bono ni descuento: no tiene movimientos registrados.</p>
              ) : (
                <ul className="mt-1 list-disc space-y-0.5 pl-5">
                  <li>{perdidaAlEliminar.movimientos} {perdidaAlEliminar.movimientos === 1 ? "movimiento" : "movimientos"}: {formatSoles(perdidaAlEliminar.bonos)} en bonos y {formatSoles(perdidaAlEliminar.descuentos)} en descuentos</li>
                  {perdidaAlEliminar.yaPagados > 0 && (
                    <li>{perdidaAlEliminar.yaPagados} «Ya le pagué aparte»: si se vuelve a crear el periodo, hay que registrarlos otra vez</li>
                  )}
                </ul>
              )}
              <p className="mt-1">y su historial de reaperturas. Las horas y los marcajes no se tocan.</p>
            </div>
            <label className="flex flex-col gap-1">
              <span>Para confirmar, escribe <strong>{palabraEliminar}</strong></span>
              <Campo value={eliminarTexto} onChange={(e) => setEliminarTexto(e.target.value)} autoFocus aria-label="Confirmación" />
            </label>
            <div className="flex justify-end gap-2">
              <Boton onClick={() => setEliminarModal(false)} disabled={guardandoPeriodo}>Cancelar</Boton>
              <Boton
                variante="peligro"
                onClick={() => void confirmarEliminar()}
                cargando={guardandoPeriodo}
                disabled={eliminarTexto.trim().toLowerCase() !== palabraEliminar}
              >
                Eliminar periodo
              </Boton>
            </div>
          </div>
        )}
      </Modal>

      {/* ── El checklist personal de pago (0562): marcar, desmarcar, historial ── */}
      <Modal abierto={confirmandoPago !== null} onCerrar={() => setConfirmandoPago(null)} bloqueado={guardandoPago} titulo="Marcar como pagada" ancho="sm">
        {confirmandoPago && (
          <div className="space-y-4 text-sm">
            <p>
              ¿Marcar a <strong>{confirmandoPago.nombre}</strong> como pagada? Se registra{" "}
              <strong className="tabular-nums">{formatSoles(confirmandoPago.total)}</strong>, a tu nombre y con la fecha de hoy.
            </p>
            <div className="flex justify-end gap-2">
              <Boton onClick={() => setConfirmandoPago(null)} disabled={guardandoPago}>Cancelar</Boton>
              <Boton variante="primario" onClick={() => void confirmarMarcarPago()} cargando={guardandoPago}>Marcar como pagada</Boton>
            </div>
          </div>
        )}
      </Modal>

      <Modal abierto={desmarcandoPago !== null} onCerrar={() => setDesmarcandoPago(null)} bloqueado={guardandoPago} titulo="Desmarcar pago" ancho="sm">
        {desmarcandoPago && (
          <div className="space-y-4 text-sm">
            <p>
              <strong>{desmarcandoPago.nombre}</strong> vuelve a quedar pendiente de pago. Escribe por qué (por ejemplo, un error al marcar).
            </p>
            <label className="flex flex-col gap-1">
              Motivo (obligatorio)
              <AreaTexto value={desmarcarMotivo} onChange={(e) => setDesmarcarMotivo(e.target.value)} rows={2} autoFocus placeholder="ej. marqué a la persona equivocada" />
            </label>
            <div className="flex justify-end gap-2">
              <Boton onClick={() => setDesmarcandoPago(null)} disabled={guardandoPago}>Cancelar</Boton>
              <Boton variante="primario" onClick={() => void confirmarDesmarcarPago()} cargando={guardandoPago} disabled={desmarcarMotivo.trim().length < 3}>
                Desmarcar
              </Boton>
            </div>
          </div>
        )}
      </Modal>

      <Modal abierto={verHistorialPago !== null} onCerrar={() => setVerHistorialPago(null)} titulo={verHistorialPago ? `Historial de pago · ${verHistorialPago.nombre}` : undefined} ancho="md">
        {errorHistorialPago ? (
          <p className="text-sm text-rojo-profundo">No se pudo traer el historial: {errorHistorialPago}</p>
        ) : historialPago === null ? (
          <Cargando />
        ) : historialPago.length === 0 ? (
          <p className="text-sm text-taupe">Sin eventos todavía.</p>
        ) : (
          <ul className="space-y-2 text-sm">
            {historialPago.map((e, i) => (
              <li key={i} className="rounded-control border border-sand bg-hueso p-3">
                <p>
                  <span className={e.tipo === "marcado" ? "font-medium text-verde" : "font-medium text-ambar"}>
                    {e.tipo === "marcado" ? "Marcada como pagada" : "Desmarcada"}
                  </span>{" "}
                  · <span className="tabular-nums">{formatSoles(e.monto)}</span>
                </p>
                <p className="mt-1 text-xs text-taupe">
                  {fechaLargaLima(e.creado_at)}{e.creado_por_nombre ? ` · ${e.creado_por_nombre}` : ""}
                </p>
                {e.motivo && <p className="mt-1 text-xs">«{e.motivo}»</p>}
              </li>
            ))}
          </ul>
        )}
      </Modal>
      </div>
    </main>
  );
}
