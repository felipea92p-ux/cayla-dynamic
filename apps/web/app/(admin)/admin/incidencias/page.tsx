"use client";

// ============================================================================
// Incidencias — la bandeja de revisión de asistencia (rediseño 2026-09-15)
// ============================================================================
// Dynamic detecta y avisa; la decisión es de una persona. Esta pantalla existe
// para que en menos de diez segundos se sepa cuántos casos piden revisión,
// quiénes, qué pasó, cuándo, dónde y qué corresponde hacer.
//
// Decisiones de Felipe (auditoría del 2026-09-15), que explican la forma:
//   · Bloques por sede plegables (opción B de la demo).
//   · Orden: la severidad que ya existía y, dentro, lo más reciente.
//   · Pulsar un caso abre un panel lateral con el contexto, no Correcciones.
//   · El visto bueno dice qué afirma: «Dar por válida», «Trabajó de corrido»,
//     «Marcar revisada».
//   · Quitar una justificación pide confirmación y motivo, y solo se hace acá
//     si la ausencia es de UN día (quitar una de cinco días anulaba los cinco).
//   · «Detalle» deja de ser pestaña: las reglas viven en «Cómo se detectan» y
//     en el panel de cada caso, con las mismas palabras (presentacion.tsx).
//   · Un visto bueno guarda el número que aceptó y deshacerlo anula con motivo
//     en vez de borrar (0452).
//   · Lote solo para lo que únicamente pide constancia, y por selección.
//   · «Por revisar» suma todo menos lo ya resuelto.
//
// La detección (qué es una incidencia) vive en lib/admin/incidencias.ts, con
// pruebas. Acá solo se trae de la base, se filtra y se muestra.
// ============================================================================

import { Suspense, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import Link from "next/link";
import { ChevronDown } from "lucide-react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { esRolEncargada, hoyLima, puedeVerTodasLasSedes } from "@cayla-dynamic/shared";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { Cargando, EsqueletoSecciones } from "@/components/cargando";
import { Boton } from "@/components/ui/boton";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { Insignia } from "@/components/ui/insignia";
import { TablaEncabezado, Th } from "@/components/ui/tabla";
import { cx } from "@/components/ui/cx";
import { traerTodo } from "@/lib/admin/traer-todo";
import { sinTildes } from "@/lib/sin-tildes";
import type { HorarioTramo } from "@/lib/admin/jornada-esperada";
import {
  addDias, compararIncidencias, detectarIncidencias, estadoDe, lunesDeLaSemana, TIPOS_EN_LOTE, ventanasDeConsulta,
  type Categoria, type DatosDeteccion, type Incidencia, type TipoIncidencia,
} from "@/lib/admin/incidencias";
import {
  IconoIncidencia, NOMBRE_TIPO, REGLA, REGLAS_EN_ORDEN, SIGUE_EL_PERIODO, accionDe, fechaCorta, fechaHoraLima, horaLima,
} from "@/components/incidencias/presentacion";
import { EstadoInsignia, PanelIncidencia } from "@/components/incidencias/panel-incidencia";

const HOY = hoyLima();

// ── Periodo ────────────────────────────────────────────────────────────────
type Periodo = "semana" | "mes" | "30" | "libre";
const PERIODOS: { clave: Exclude<Periodo, "libre">; etiqueta: string }[] = [
  { clave: "semana", etiqueta: "Esta semana" },
  { clave: "mes", etiqueta: "Este mes" },
  { clave: "30", etiqueta: "Últimos 30 días" },
];
function rangoDe(p: Exclude<Periodo, "libre">): [string, string] {
  if (p === "semana") return [lunesDeLaSemana(HOY), HOY];
  if (p === "mes") return [`${HOY.slice(0, 8)}01`, HOY];
  return [addDias(HOY, -30), HOY];
}

// ── Resumen ────────────────────────────────────────────────────────────────
const CATEGORIAS: { clave: Categoria; etiqueta: string }[] = [
  { clave: "faltas", etiqueta: "Faltas injustificadas" },
  { clave: "marcaciones", etiqueta: "Marcaciones" },
  { clave: "patrones", etiqueta: "Patrones" },
  { clave: "otros", etiqueta: "Otros" },
];
type FiltroEstado = "por_revisar" | "resueltas" | "todas";

// Motivos que devuelve fn_faltas y que NO son filas de tipos_ausencia: la
// suspensión (0079) y el descanso sustitutorio (0070). Todo lo demás se nombra
// desde la tabla.
const MOTIVOS_FUERA_DE_AUSENCIAS: Record<string, string> = {
  suspension: "Suspensión",
  descanso_sustitutorio: "Descanso sustitutorio",
};

interface RevisionPedida {
  id: string; persona_id: string; nombre: string; sede: string;
  fecha: string; comentario: string; pedida_at: string;
}
interface PracticanteSobreTope {
  persona_id: string; persona: string; sede: string; estado: string; dias_restantes: number | null;
}
interface Sede { id: string; codigo: string; nombre: string; activa: boolean }
interface AceptadaRow {
  persona_id: string; fecha: string; tipo: string; nota: string | null;
  aceptado_por: string; aceptado_at: string; valor: number | null;
  anulada_at: string | null; anulada_por: string | null; anulada_motivo: string | null;
  personas: { nombres: string; apellidos: string; sedes: { codigo: string } | null } | null;
}

function IncidenciasContenido() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const personaFiltro = searchParams.get("persona");
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;

  const [periodo, setPeriodo] = useState<Periodo>("30");
  const [desde, setDesde] = useState(addDias(HOY, -30));
  const [hasta, setHasta] = useState(HOY);

  const [incidencias, setIncidencias] = useState<Incidencia[]>([]);
  const [sedes, setSedes] = useState<Sede[]>([]);
  const [historial, setHistorial] = useState<AceptadaRow[]>([]);
  const [nombrePorId, setNombrePorId] = useState<Map<string, string>>(new Map());
  const [nombreTipoAusencia, setNombreTipoAusencia] = useState<Map<string, string>>(new Map());
  const [revisiones, setRevisiones] = useState<RevisionPedida[]>([]);
  const [respuestas, setRespuestas] = useState<Record<string, string>>({});
  const [atendiendo, setAtendiendo] = useState<string | null>(null);
  const [practicantesSobreTope, setPracticantesSobreTope] = useState<PracticanteSobreTope[]>([]);

  const [cargando, setCargando] = useState(true);
  // Dos errores distintos: uno de CARGA (arriba, con Reintentar) y uno de ACCIÓN
  // (lo que falló al actuar). Mezclarlos anunciaba un rechazo al guardar como
  // si no hubiera cargado la pantalla.
  const [error, setError] = useState<string | null>(null);
  const [errorAccion, setErrorAccion] = useState<string | null>(null);
  const [avisoLevantadas, setAvisoLevantadas] = useState<string | null>(null);

  const [busca, setBusca] = useState("");
  const [sedeFiltro, setSedeFiltro] = useState("");
  const [tipoFiltro, setTipoFiltro] = useState<TipoIncidencia | "">("");
  const [estadoFiltro, setEstadoFiltro] = useState<FiltroEstado>("por_revisar");
  const [categoria, setCategoria] = useState<Categoria | "">("");
  const [plegadas, setPlegadas] = useState<Set<string>>(new Set());
  const [mostrarReglas, setMostrarReglas] = useState(false);
  const [mostrarHistorial, setMostrarHistorial] = useState(false);

  const [seleccion, setSeleccion] = useState<Set<string>>(new Set());
  const [loteando, setLoteando] = useState(false);

  const [abierta, setAbierta] = useState<string | null>(null);
  const volverFoco = useRef<HTMLElement | null>(null);

  const etiquetaMotivo = useCallback((m: string | null) => {
    if (!m) return "Sin motivo";
    // `permiso_concedido` es el nombre viejo; en tipos_ausencia es `permiso_personal` (0101).
    const codigo = m === "permiso_concedido" ? "permiso_personal" : m;
    return nombreTipoAusencia.get(codigo) ?? MOTIVOS_FUERA_DE_AUSENCIAS[m] ?? m.replaceAll("_", " ");
  }, [nombreTipoAusencia]);

  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    setCargando(true);

    // Qué rango pide cada consulta: vive junto a la detección para que no se separen.
    const v = ventanasDeConsulta(HOY, desde, hasta);

    const [
      { data, error: errData },
      { data: extraData },
      { data: tardias, error: errTardias },
      { data: sedesData, error: errSedes },
      { data: encargadasData, error: errEnc },
      { data: metasData, error: errMetas },
      { data: horariosData, error: errHorarios },
      { data: turnosData, error: errTurnos },
      { data: aceptadasData },
      { data: personasData },
      { data: faltasData },
      { data: revisionesData },
      { data: levTardData, error: errLevTard },
      { data: horasSemanaData },
      { data: diasRachaData },
      { data: contratosData },
      { data: tiposData },
    ] = await Promise.all([
      // Por lotes: PostgREST cortaba en 1000 filas sin avisar.
      traerTodo<unknown>((ini, fin) =>
        supabase
          .from("jornadas")
          .select("persona_id, fecha, estado, entrada_ts, salida_final_ts, tiene_salida_no_retornada, personas:persona_id(nombres, apellidos, sedes:sede_base_id(codigo))")
          .gte("fecha", desde).lte("fecha", hasta)
          .order("fecha", { ascending: false })
          .order("persona_id")
          .range(ini, fin),
      ),
      supabase.rpc("fn_jornadas_extra", { p_desde: desde, p_hasta: hasta }),
      traerTodo<unknown>((ini, fin) =>
        supabase
          .from("jornadas")
          // `en_planilla` viaja para que el patrón se quede exclusivo de quien está en planilla (0413).
          .select("persona_id, fecha, entrada_ts, personas:persona_id(nombres, apellidos, en_planilla, sedes:sede_base_id(codigo))")
          .gte("fecha", v.desdePatron).lte("fecha", HOY)
          .gt("minutos_tarde", 0)
          .order("fecha", { ascending: false })
          .order("persona_id")
          .range(ini, fin),
      ),
      supabase.from("sedes").select("id, codigo, nombre, activa").order("codigo"),
      supabase.from("personas").select("id, sede_base_id").eq("rol", "supervisor_sede").eq("estado", "activo"),
      supabase.from("metas_cobertura").select("sede_id, dia_semana, meta_encargadas").gt("meta_encargadas", 0),
      supabase.from("horarios_asignados").select("persona_id, hora_entrada, hora_salida, dias_laborables, horario_por_dia, almuerzo_min_minutos, vigente_desde, vigente_hasta").lte("vigente_desde", v.domingoSiguiente).or(`vigente_hasta.is.null,vigente_hasta.gte.${v.lunesActual}`),
      supabase.from("turnos").select("persona_id, fecha, hora_entrada, hora_salida, es_descanso").gte("fecha", v.lunesActual).lte("fecha", v.domingoSiguiente),
      // Vistos buenos, también los deshechos: la detección usa los vigentes y el
      // historial muestra todos (0452). Desde lo más atrás que haga falta.
      supabase.from("incidencias_aceptadas")
        .select("persona_id, fecha, tipo, nota, aceptado_por, aceptado_at, valor, anulada_at, anulada_por, anulada_motivo, personas:persona_id(nombres, apellidos, sedes:sede_base_id(codigo))")
        .gte("fecha", v.desdeAceptadas)
        .lte("fecha", v.hastaAceptadas)
        .order("aceptado_at", { ascending: false }),
      supabase.from("personas").select("id, nombres, apellidos"),
      supabase.rpc("fn_faltas", { p_desde: desde, p_hasta: hasta }),
      supabase.rpc("fn_revisiones_pedidas", { p_solo_pendientes: true }),
      // Falla DURA para el patrón (se apaga entero), suave para el resto.
      supabase.from("tardanzas_justificadas").select("persona_id, fecha").gte("fecha", v.desdePatron).lte("fecha", HOY),
      traerTodo<unknown>((ini, fin) =>
        supabase
          .from("jornadas")
          .select("persona_id, fecha, horas_trabajadas, estado, personas:persona_id(nombres, apellidos, tipo_vinculo, practicante_modalidad, sedes:sede_base_id(codigo))")
          .gte("fecha", v.desdeHoras).lte("fecha", HOY)
          .gt("horas_trabajadas", 0)
          .order("persona_id")
          .range(ini, fin),
      ),
      traerTodo<unknown>((ini, fin) =>
        supabase
          .from("jornadas")
          .select("persona_id, fecha, personas:persona_id(nombres, apellidos, sedes:sede_base_id(codigo))")
          .gte("fecha", v.desdeRacha).lte("fecha", HOY)
          .gt("horas_trabajadas", 0)
          .order("persona_id")
          .range(ini, fin),
      ),
      supabase.rpc("fn_contratos_tablero"),
      supabase.from("tipos_ausencia").select("codigo, nombre"),
    ]);

    if (errData || errTardias || errSedes || errEnc || errMetas || errHorarios || errTurnos) {
      setError((errData ?? errTardias ?? errSedes ?? errEnc ?? errMetas ?? errHorarios ?? errTurnos)!.message);
      setCargando(false);
      return; // no pisa la lista con datos parciales
    }
    setError(null);
    setAvisoLevantadas(
      errLevTard
        ? `No se pudo comprobar qué tardanzas ya fueron levantadas (${errLevTard.message}). ` +
          "El aviso de «patrón de tardanzas» se ocultó mientras tanto, para no volver a acusar una tardanza ya perdonada."
        : null,
    );

    const aceptadasRows = (aceptadasData as unknown as AceptadaRow[] | null) ?? [];
    const tipos = new Map(((tiposData as { codigo: string; nombre: string }[] | null) ?? []).map((t) => [t.codigo, t.nombre]));
    const etiqueta = (m: string | null) => {
      if (!m) return "Sin motivo";
      const codigo = m === "permiso_concedido" ? "permiso_personal" : m;
      return tipos.get(codigo) ?? MOTIVOS_FUERA_DE_AUSENCIAS[m] ?? m.replaceAll("_", " ");
    };
    const sedesRows = (sedesData as Sede[] | null) ?? [];

    setIncidencias(detectarIncidencias({
      hoy: HOY,
      jornadasRango: (data as DatosDeteccion["jornadasRango"] | null) ?? [],
      salidaTemprana: (extraData as unknown as DatosDeteccion["salidaTemprana"] | null) ?? [],
      tardanzas: (tardias as DatosDeteccion["tardanzas"] | null) ?? [],
      tardanzasLevantadas: errLevTard ? null : ((levTardData as { persona_id: string; fecha: string }[] | null) ?? []),
      horasVentana: (horasSemanaData as DatosDeteccion["horasVentana"] | null) ?? [],
      diasRacha: (diasRachaData as DatosDeteccion["diasRacha"] | null) ?? [],
      aceptadas: aceptadasRows.filter((a) => a.anulada_at === null),
      sedes: sedesRows,
      encargadas: (encargadasData as { id: string; sede_base_id: string }[] | null) ?? [],
      metas: (metasData as { sede_id: string; dia_semana: number; meta_encargadas: number }[] | null) ?? [],
      horarios: (horariosData as HorarioTramo[] | null) ?? [],
      turnos: (turnosData as DatosDeteccion["turnos"] | null) ?? [],
      faltas: (faltasData as unknown as DatosDeteccion["faltas"] | null) ?? [],
      etiquetaMotivo: etiqueta,
    }));
    setSedes(sedesRows);
    setHistorial(aceptadasRows);
    setNombreTipoAusencia(tipos);
    setNombrePorId(new Map(
      ((personasData as { id: string; nombres: string; apellidos: string }[] | null) ?? [])
        .map((p) => [p.id, `${p.nombres} ${p.apellidos}`.trim()]),
    ));
    setRevisiones((revisionesData as unknown as RevisionPedida[] | null) ?? []);
    // Tope de 12 meses del convenio (Ley 28518 art. 30, 0336): aviso aparte,
    // porque el riesgo existe aunque la practicante venga con normalidad.
    setPracticantesSobreTope(
      ((contratosData as { persona_id: string; persona: string; sede: string; tipo: string; estado: string; dias_restantes: number | null }[] | null) ?? [])
        .filter((c) => c.tipo === "convenio_practicas" && (c.estado === "vencido" || c.estado === "por_vencer"))
        .map((c) => ({ persona_id: c.persona_id, persona: c.persona, sede: c.sede, estado: c.estado, dias_restantes: c.dias_restantes })),
    );
    setSeleccion(new Set());
    setCargando(false);
  }, [router, desde, hasta]);

  // eslint-disable-next-line react-hooks/set-state-in-effect -- cargar al montar y al mover el periodo, mismo patrón que el resto del panel.
  useEffect(() => { void cargar(); }, [cargar]);

  // ── Alcance: lo que esta persona puede ver ─────────────────────────────
  const codigoDeMiSede = sedes.find((s) => s.id === yo?.sedeBaseId)?.codigo ?? null;
  const veTodas = puedeVerTodasLasSedes(rol);
  const alcance = useMemo(() => incidencias.filter((i) =>
    // La base ya limita a la encargada (RLS y fn_faltas); esto es la salvaguarda visual.
    (veTodas || !esRolEncargada(rol) || i.sede === codigoDeMiSede)
    && (!personaFiltro || i.personaId === personaFiltro),
  ), [incidencias, veTodas, rol, codigoDeMiSede, personaFiltro]);

  const q = sinTildes(busca.trim());
  const sinEstadoNiCategoria = useMemo(() => alcance.filter((i) =>
    (q === "" || sinTildes(i.nombre).includes(q))
    && (!sedeFiltro || i.sede === sedeFiltro)
    && (!tipoFiltro || i.tipo === tipoFiltro),
  ), [alcance, q, sedeFiltro, tipoFiltro]);

  const porRevisar = sinEstadoNiCategoria.filter((i) => estadoDe(i) !== "resuelta");
  const resueltas = sinEstadoNiCategoria.length - porRevisar.length;

  const visibles = useMemo(() => sinEstadoNiCategoria
    .filter((i) => {
      const e = estadoDe(i);
      if (estadoFiltro === "por_revisar" && e === "resuelta") return false;
      if (estadoFiltro === "resueltas" && e !== "resuelta") return false;
      return !categoria || i.categoria === categoria;
    })
    .sort(compararIncidencias), [sinEstadoNiCategoria, estadoFiltro, categoria]);

  // Sedes del filtro: las activas de la tabla, más cualquiera con casos aunque
  // ya no esté activa (un aviso de una sede cerrada sigue siendo un aviso).
  const sedesDelFiltro = useMemo(() => {
    const codigos = new Set(sedes.filter((s) => s.activa).map((s) => s.codigo));
    for (const i of alcance) codigos.add(i.sede);
    return [...codigos].sort();
  }, [sedes, alcance]);
  const tiposPresentes = useMemo(
    () => [...new Set(alcance.map((i) => i.tipo))].sort((a, b) => NOMBRE_TIPO[a].localeCompare(NOMBRE_TIPO[b], "es")),
    [alcance],
  );
  const sedesDeLaVista = [...new Set(visibles.map((i) => i.sede))].sort();
  const nombreSede = (codigo: string) => sedes.find((s) => s.codigo === codigo)?.nombre ?? null;

  const hayFiltros = busca !== "" || sedeFiltro !== "" || tipoFiltro !== "" || categoria !== "" || estadoFiltro !== "por_revisar";
  function limpiarFiltros() {
    setBusca(""); setSedeFiltro(""); setTipoFiltro(""); setCategoria(""); setEstadoFiltro("por_revisar");
  }

  // ── Permiso sobre un caso ──────────────────────────────────────────────
  // El servidor decide (fn_verificar_corrector); esto evita ofrecer un botón
  // que va a ser rechazado.
  function motivoNoPuede(i: Incidencia): string | null {
    if (!i.personaId) return "Es un aviso de la sede: se resuelve en Turnos.";
    if (esRolEncargada(rol) && i.personaId === yo?.id) {
      return "No puedes revisar tu propia asistencia. Pídeselo a Desarrollo Organizacional.";
    }
    return null;
  }
  const loteable = (i: Incidencia) =>
    !!i.aceptable && TIPOS_EN_LOTE.has(i.aceptable) && estadoDe(i) !== "resuelta" && motivoNoPuede(i) === null;

  async function marcarRevisadas(objetivo: Incidencia[]) {
    setLoteando(true);
    setErrorAccion(null);
    const supabase = createAdminSupabaseClient();
    let hechas = 0;
    for (const i of objetivo) {
      const { error: e } = await supabase.rpc("fn_aceptar_incidencia", {
        p_persona_id: i.personaId!, p_fecha: i.fecha, p_tipo: i.aceptable!, p_valor: i.valor,
      });
      if (e) {
        setErrorAccion(`Se marcaron ${hechas} de ${objetivo.length}. Se detuvo en ${i.nombre} (${fechaCorta(i.fecha)}): ${e.message}`);
        break;
      }
      hechas++;
    }
    setLoteando(false);
    await cargar();
  }

  async function atenderRevision(id: string) {
    setAtendiendo(id);
    const supabase = createAdminSupabaseClient();
    const { error: e } = await supabase.rpc("fn_atender_revision", {
      p_id: id, p_respuesta: (respuestas[id] ?? "").trim() || null,
    });
    setAtendiendo(null);
    if (e) { setErrorAccion(e.message); return; }
    setErrorAccion(null);
    setRespuestas((r) => ({ ...r, [id]: "" }));
    await cargar();
  }

  function abrir(i: Incidencia, desdeElemento: HTMLElement) {
    volverFoco.current = desdeElemento;
    setAbierta(i.clave);
  }
  const incidenciaAbierta = abierta ? incidencias.find((i) => i.clave === abierta) ?? null : null;

  function elegirPeriodo(p: Exclude<Periodo, "libre">) {
    const [d, h] = rangoDe(p);
    setPeriodo(p); setDesde(d); setHasta(h);
  }

  const nombreFiltro = personaFiltro ? alcance.find((i) => i.personaId === personaFiltro)?.nombre ?? null : null;

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex flex-1 flex-col gap-6 p-6">
        <CabeceraPagina
          titulo="Incidencias"
          descripcion="Revisa anomalías de asistencia y corrige únicamente lo que corresponda. Dynamic detecta y avisa; la decisión es tuya."
          accion={
            <Boton variante="enlace" className="text-sm text-taupe" aria-expanded={mostrarReglas} onClick={() => setMostrarReglas((x) => !x)}>
              ⓘ Cómo se detectan
            </Boton>
          }
        />

        {mostrarReglas && (
          <section className="-mt-4 rounded-superficie border border-sand bg-papel p-5">
            <dl className="grid gap-x-8 gap-y-4 text-sm md:grid-cols-2">
              {REGLAS_EN_ORDEN.map((r) => (
                <div key={r.titulo} className="flex flex-col gap-1">
                  <dt className="font-medium text-tinta">{r.titulo}</dt>
                  {r.tipos.map((t) => <dd key={t} className="leading-relaxed text-taupe">{REGLA[t]}</dd>)}
                </div>
              ))}
            </dl>
            <p className="mt-4 border-t border-sand pt-3 text-xs text-taupe">
              <strong className="font-medium text-tinta">Sobre el periodo:</strong> Desde y Hasta filtran las faltas y los
              cierres del día. Patrones, excesos de jornada, días sin descanso y déficit de encargadas se miden sobre
              ventanas fijas desde hoy, porque describen la situación actual de la persona, no un rango histórico.
            </p>
          </section>
        )}

        {/* ── Lo que tu equipo pidió revisar ────────────────────────────
            Primero, y no por orden alfabético: es la única lista que no generó
            el sistema, sino una persona que estuvo ahí ese día. */}
        {revisiones.length > 0 && (
          <section className="rounded-superficie border border-tinta/25 bg-papel p-5">
            <h2 className="mb-1 font-serif text-lg">Tu equipo pidió revisar {revisiones.length} día{revisiones.length === 1 ? "" : "s"}</h2>
            <p className="mb-4 text-sm text-taupe">
              Lo escribieron desde «Lo mío». Corrige el día en Correcciones si hace falta y cierra acá diciendo en qué
              quedó: esa respuesta la va a leer la persona.
            </p>
            <ul className="flex flex-col gap-3">
              {revisiones.map((r) => (
                <li key={r.id} className="rounded-control border border-sand p-3 text-sm">
                  <div className="flex flex-wrap items-baseline justify-between gap-2">
                    <span><strong>{r.nombre}</strong> <span className="text-taupe">· {r.sede} · {fechaCorta(r.fecha)}</span></span>
                    <Link href={`/admin/correcciones?persona=${r.persona_id}&fecha=${r.fecha}`} className="text-tinta underline underline-offset-2">
                      Abrir ese día en Correcciones →
                    </Link>
                  </div>
                  <p className="mt-1.5">«{r.comentario}»</p>
                  <div className="mt-2 flex flex-wrap items-end gap-2">
                    <div className="min-w-0 flex-1 basis-56">
                      <Campo
                        id={`revision-respuesta-${r.id}`}
                        aria-label="En qué quedó"
                        value={respuestas[r.id] ?? ""}
                        onChange={(e) => setRespuestas((x) => ({ ...x, [r.id]: e.target.value }))}
                        placeholder="En qué quedó (lo va a leer la persona)"
                      />
                    </div>
                    <Boton variante="primario" onClick={() => void atenderRevision(r.id)} cargando={atendiendo === r.id}>
                      Marcar atendida
                    </Boton>
                  </div>
                </li>
              ))}
            </ul>
          </section>
        )}

        {/* Tope de 12 meses del convenio de prácticas: se revisa en Contratos. */}
        {practicantesSobreTope.length > 0 && (
          <section className="rounded-superficie border border-ambar/40 bg-ambar/5 p-5">
            <h2 className="mb-1 font-serif text-lg">
              {practicantesSobreTope.length} convenio{practicantesSobreTope.length === 1 ? "" : "s"} de prácticas en el tope de 12 meses
            </h2>
            <p className="mb-3 text-sm text-taupe">
              Ley 28518, art. 30: pasado el tope, la relación arriesga considerarse desnaturalizada, aunque siga
              viniendo con normalidad. Se revisa en Contratos, no acá.
            </p>
            <ul className="flex flex-col gap-1.5 text-sm">
              {practicantesSobreTope.map((p) => (
                <li key={p.persona_id} className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
                  <span>
                    <strong>{p.persona}</strong> <span className="text-taupe">· {p.sede}</span>{" — "}
                    {p.estado === "vencido"
                      ? "superó el tope de 12 meses"
                      : `se acerca al tope de 12 meses${p.dias_restantes !== null ? ` · ${p.dias_restantes} días` : ""}`}
                  </span>
                  <Link href="/admin/contratos" className="shrink-0 text-taupe underline underline-offset-2 hover:text-tinta">Ver en Contratos →</Link>
                </li>
              ))}
            </ul>
          </section>
        )}

        {/* ── Resumen: cuántos y de qué ──────────────────────────────────── */}
        <div className="grid grid-cols-2 overflow-hidden rounded-superficie border border-sand bg-papel md:grid-cols-5">
          <button
            type="button"
            aria-pressed={categoria === "" && estadoFiltro === "por_revisar"}
            onClick={() => { setCategoria(""); setEstadoFiltro("por_revisar"); }}
            className={cx(
              "col-span-2 flex flex-col items-start gap-1 border-b border-sand px-5 py-4 text-left transition-colors md:col-span-1 md:border-b-0",
              categoria === "" && estadoFiltro === "por_revisar" ? "bg-hueso" : "hover:bg-crema/60",
            )}
          >
            <span className="font-serif text-4xl leading-none tabular-nums text-tinta">{cargando ? "—" : porRevisar.length}</span>
            <span className="text-sm text-taupe">
              por revisar{!cargando && resueltas > 0 && <> · {resueltas} ya resuelta{resueltas === 1 ? "" : "s"}</>}
            </span>
          </button>
          {CATEGORIAS.map((c, idx) => {
            const n = porRevisar.filter((i) => i.categoria === c.clave).length;
            const activa = categoria === c.clave;
            return (
              <button
                key={c.clave}
                type="button"
                aria-pressed={activa}
                onClick={() => { setCategoria(activa ? "" : c.clave); if (!activa) setEstadoFiltro("por_revisar"); }}
                className={cx(
                  "flex flex-col items-start gap-1 border-sand px-5 py-4 text-left transition-colors md:border-l",
                  idx % 2 === 1 && "border-l",
                  idx < 2 && "border-b md:border-b-0",
                  activa ? "bg-hueso" : "hover:bg-crema/60",
                )}
              >
                <span className="font-serif text-3xl leading-none tabular-nums text-tinta">{cargando ? "—" : n}</span>
                <span className="text-sm text-taupe">{c.etiqueta}</span>
              </button>
            );
          })}
        </div>

        {/* ── Filtros ───────────────────────────────────────────────────── */}
        <div className="flex flex-col gap-3">
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-[minmax(0,2fr)_repeat(3,minmax(0,1fr))]">
            <Campo
              id="incidencias-buscar"
              type="search"
              aria-label="Buscar persona"
              placeholder="Buscar persona…"
              value={busca}
              onChange={(e) => setBusca(e.target.value)}
            />
            {veTodas && (
              <CampoSelect id="incidencias-sede" aria-label="Sede" value={sedeFiltro} onChange={(e) => setSedeFiltro(e.target.value)}>
                <option value="">Todas las sedes</option>
                {sedesDelFiltro.map((s) => (
                  <option key={s} value={s}>{s}{nombreSede(s) ? ` · ${nombreSede(s)}` : ""}</option>
                ))}
              </CampoSelect>
            )}
            <CampoSelect id="incidencias-tipo" aria-label="Tipo de incidencia" value={tipoFiltro} onChange={(e) => setTipoFiltro(e.target.value as TipoIncidencia | "")}>
              <option value="">Todos los tipos</option>
              {tiposPresentes.map((t) => <option key={t} value={t}>{NOMBRE_TIPO[t]}</option>)}
            </CampoSelect>
            <CampoSelect id="incidencias-estado" aria-label="Estado" value={estadoFiltro} onChange={(e) => setEstadoFiltro(e.target.value as FiltroEstado)}>
              <option value="por_revisar">Por revisar</option>
              <option value="resueltas">Ya resueltas</option>
              <option value="todas">Todas</option>
            </CampoSelect>
          </div>

          <div className="flex flex-wrap items-end gap-x-4 gap-y-3">
            <div role="group" aria-label="Periodo" className="flex flex-wrap gap-1.5">
              {PERIODOS.map((p) => (
                <button
                  key={p.clave}
                  type="button"
                  aria-pressed={periodo === p.clave}
                  onClick={() => elegirPeriodo(p.clave)}
                  className={cx(
                    "rounded-pildora border px-3 py-1.5 text-sm transition-colors",
                    periodo === p.clave ? "border-tinta bg-tinta text-crema" : "border-sand text-taupe hover:text-tinta",
                  )}
                >
                  {p.etiqueta}
                </button>
              ))}
            </div>
            <div className="flex items-end gap-2">
              {/* Nunca vacíos: sin fecha no hay consulta. Un borrado se ignora. */}
              <Campo id="incidencias-desde" etiqueta="Desde" type="date" value={desde} max={hasta}
                onChange={(e) => { if (e.target.value) { setDesde(e.target.value); setPeriodo("libre"); } }} />
              <Campo id="incidencias-hasta" etiqueta="Hasta" type="date" value={hasta} min={desde}
                onChange={(e) => { if (e.target.value) { setHasta(e.target.value); setPeriodo("libre"); } }} />
            </div>
            {hayFiltros && (
              <Boton variante="enlace" className="pb-2 text-sm text-taupe" onClick={limpiarFiltros}>Limpiar filtros</Boton>
            )}
          </div>
        </div>

        {personaFiltro && (
          <div className="flex flex-wrap items-center justify-between gap-2 rounded-control border border-sand bg-papel px-4 py-2.5 text-sm">
            <span>
              {nombreFiltro
                ? <>Mostrando solo las incidencias de <strong>{nombreFiltro}</strong>.</>
                : "La persona seleccionada no tiene incidencias en este periodo."}
            </span>
            <Boton variante="enlace" className="shrink-0" onClick={() => router.push("/admin/incidencias")}>Ver todas →</Boton>
          </div>
        )}

        {error && (
          <div className="rounded-control bg-rojo/10 px-4 py-3 text-sm text-rojo-profundo">
            No se pudieron cargar las incidencias: {error}{" "}
            <Boton variante="enlace" onClick={() => void cargar()}>Reintentar</Boton>
          </div>
        )}
        {avisoLevantadas && (
          <div className="rounded-control border border-ambar/30 bg-ambar/10 px-4 py-3 text-sm">
            {avisoLevantadas}{" "}
            <Boton variante="enlace" onClick={() => void cargar()}>Reintentar</Boton>
          </div>
        )}
        {errorAccion && (
          <div className="flex items-start gap-3 rounded-control bg-rojo/10 px-4 py-3 text-sm text-rojo-profundo">
            <span className="flex-1">{errorAccion}</span>
            <Boton variante="enlace" className="shrink-0" onClick={() => setErrorAccion(null)}>Entendido</Boton>
          </div>
        )}

        {cargando && incidencias.length === 0 && <EsqueletoSecciones anchos={["w-32", "w-24", "w-40", "w-12", "w-12", "w-20"]} />}

        {!cargando && !error && visibles.length === 0 && (
          <div className="flex flex-col items-center gap-2 rounded-superficie border border-sand bg-papel px-6 py-10 text-center">
            <p className="font-serif text-xl text-tinta">
              {hayFiltros ? "No hay incidencias con estos filtros." : "Todo revisado en este periodo."}
            </p>
            {hayFiltros
              ? <Boton variante="enlace" className="text-sm text-taupe" onClick={limpiarFiltros}>Limpiar filtros</Boton>
              : resueltas > 0 && <p className="text-sm text-taupe">Hay {resueltas} ya resuelta{resueltas === 1 ? "" : "s"}: elige «Ya resueltas» en Estado para verlas.</p>}
          </div>
        )}

        {/* ── Casos, por sede ────────────────────────────────────────────── */}
        <div className="flex flex-col gap-4">
          {sedesDeLaVista.map((sede) => {
            const casos = visibles.filter((i) => i.sede === sede);
            const abiertaSede = !plegadas.has(sede);
            const altas = casos.filter((i) => i.severidad === "alta" && estadoDe(i) !== "resuelta").length;
            const loteables = casos.filter(loteable);
            const elegidos = loteables.filter((i) => seleccion.has(i.clave));
            const idBloque = `incidencias-sede-${sede}`;
            return (
              <section key={sede} className="overflow-clip rounded-superficie border border-sand bg-papel">
                <h2>
                  <button
                    type="button"
                    aria-expanded={abiertaSede}
                    aria-controls={idBloque}
                    onClick={() => setPlegadas((p) => { const n = new Set(p); if (n.has(sede)) n.delete(sede); else n.add(sede); return n; })}
                    className="flex w-full flex-wrap items-baseline gap-x-3 gap-y-1 px-5 py-3.5 text-left transition-colors hover:bg-crema/60"
                  >
                    <span className="font-serif text-xl text-tinta">{sede}</span>
                    {nombreSede(sede) && <span className="text-sm text-taupe">{nombreSede(sede)}</span>}
                    <span className="text-sm text-taupe">· {casos.length} caso{casos.length === 1 ? "" : "s"}</span>
                    {altas > 0 && <Insignia variante="alerta" tamano="sm">{altas} alta{altas === 1 ? "" : "s"}</Insignia>}
                    <ChevronDown aria-hidden className={cx("ml-auto size-4 self-center text-taupe transition-transform", !abiertaSede && "-rotate-90")} />
                  </button>
                </h2>

                {abiertaSede && (
                  <div id={idBloque} className="border-t border-sand">
                    {loteables.length > 0 && (
                      <div className="flex flex-wrap items-center justify-between gap-2 border-b border-sand bg-crema/40 px-5 py-2.5 text-sm">
                        <label className="flex items-center gap-2 text-taupe">
                          <input
                            id={`incidencias-lote-${sede}`}
                            type="checkbox"
                            className="size-4 accent-tinta"
                            checked={elegidos.length === loteables.length}
                            onChange={(e) => setSeleccion((s) => {
                              const n = new Set(s);
                              for (const i of loteables) { if (e.target.checked) n.add(i.clave); else n.delete(i.clave); }
                              return n;
                            })}
                          />
                          Seleccionar las {loteables.length} que solo piden constancia (rachas y excesos que ya ocurrieron)
                        </label>
                        <Boton
                          variante="sutil"
                          tamano="sm"
                          disabled={elegidos.length === 0 || loteando}
                          cargando={loteando}
                          onClick={() => void marcarRevisadas(elegidos)}
                        >
                          Marcar {elegidos.length || ""} como revisada{elegidos.length === 1 ? "" : "s"}
                        </Boton>
                      </div>
                    )}

                    {/* Escritorio y tableta: tabla con encabezado fijo dentro del bloque. */}
                    <div className="hidden max-h-[70vh] overflow-auto md:block">
                      <table className="w-full text-sm">
                        <TablaEncabezado>
                          {loteables.length > 0 && <Th className="w-10"><span className="sr-only">Seleccionar</span></Th>}
                          <Th>Persona</Th>
                          <Th>Fecha</Th>
                          <Th>Incidencia</Th>
                          <Th className="hidden lg:table-cell">Entrada</Th>
                          <Th className="hidden lg:table-cell">Salida</Th>
                          <Th>Estado</Th>
                          <Th><span className="sr-only">Acción</span></Th>
                        </TablaEncabezado>
                        <tbody>
                          {casos.map((i) => {
                            const accion = accionDe(i);
                            return (
                              <tr
                                key={i.clave}
                                tabIndex={0}
                                aria-label={`${i.nombre}, ${i.titulo}, ${fechaCorta(i.fecha)}`}
                                onClick={(e) => abrir(i, e.currentTarget)}
                                onKeyDown={(e) => { if (e.key === "Enter" && e.target === e.currentTarget) abrir(i, e.currentTarget); }}
                                className="cursor-pointer border-t border-sand transition-colors duration-150 hover:bg-crema/60 focus-visible:bg-crema/60"
                              >
                                {loteables.length > 0 && (
                                  <td className="px-4 py-3" onClick={(e) => e.stopPropagation()}>
                                    {loteable(i) && (
                                      <input
                                        id={`incidencias-elegir-${i.clave}`}
                                        type="checkbox"
                                        aria-label={`Seleccionar ${i.nombre}, ${i.titulo}`}
                                        className="size-4 accent-tinta"
                                        checked={seleccion.has(i.clave)}
                                        onChange={(e) => setSeleccion((s) => { const n = new Set(s); if (e.target.checked) n.add(i.clave); else n.delete(i.clave); return n; })}
                                      />
                                    )}
                                  </td>
                                )}
                                <td className="px-4 py-3 font-medium text-tinta">{i.nombre}</td>
                                <td className="whitespace-nowrap px-4 py-3 capitalize tabular-nums text-tinta">{fechaCorta(i.fecha)}</td>
                                <td className="px-4 py-3">
                                  <div className="flex items-center gap-2.5">
                                    <IconoIncidencia incidencia={i} />
                                    <span>
                                      <span className="text-tinta">{i.titulo}</span>
                                      {i.detalle && <span className="text-taupe"> · {i.detalle}</span>}
                                    </span>
                                  </div>
                                </td>
                                <td className="hidden px-4 py-3 tabular-nums text-taupe lg:table-cell">{horaLima(i.entrada)}</td>
                                <td className="hidden px-4 py-3 tabular-nums text-taupe lg:table-cell">{horaLima(i.salida)}</td>
                                <td className="px-4 py-3"><EstadoInsignia incidencia={i} /></td>
                                <td className="whitespace-nowrap px-4 py-3 text-right" onClick={(e) => e.stopPropagation()}>
                                  {accion.tipo === "enlace" ? (
                                    <Link href={accion.href} className="font-medium text-tinta underline decoration-taupe/40 underline-offset-4 hover:decoration-tinta">
                                      {accion.etiqueta} →
                                    </Link>
                                  ) : (
                                    <Boton
                                      variante={estadoDe(i) === "resuelta" ? "sutil" : "secundario"}
                                      tamano="sm"
                                      onClick={(e) => abrir(i, e.currentTarget)}
                                    >
                                      {accion.etiqueta}
                                    </Boton>
                                  )}
                                </td>
                              </tr>
                            );
                          })}
                        </tbody>
                      </table>
                    </div>

                    {/* Celular: tarjetas. Toda la tarjeta abre el caso. */}
                    <ul className="divide-y divide-sand md:hidden">
                      {casos.map((i) => (
                        <li key={i.clave}>
                          <button type="button" onClick={(e) => abrir(i, e.currentTarget)} className="flex w-full flex-col gap-2 px-4 py-3.5 text-left">
                            <span className="flex items-start justify-between gap-2">
                              <span className="flex flex-col">
                                <span className="font-medium text-tinta">{i.nombre}</span>
                                <span className="text-xs capitalize text-taupe">{fechaCorta(i.fecha)}</span>
                              </span>
                              <EstadoInsignia incidencia={i} />
                            </span>
                            <span className="flex items-center gap-2.5 text-sm">
                              <IconoIncidencia incidencia={i} />
                              <span>
                                <span className="text-tinta">{i.titulo}</span>
                                {i.detalle && <span className="block text-taupe">{i.detalle}</span>}
                              </span>
                            </span>
                            <span className="flex items-center justify-between text-sm">
                              <span className="tabular-nums text-taupe">
                                {i.entrada ? `${horaLima(i.entrada)} → ${i.salida ? horaLima(i.salida) : "sin salida"}` : ""}
                              </span>
                              <span className="font-medium text-tinta">{accionDe(i).etiqueta} →</span>
                            </span>
                          </button>
                        </li>
                      ))}
                    </ul>
                  </div>
                )}
              </section>
            );
          })}
        </div>

        {tipoFiltro && !SIGUE_EL_PERIODO.has(tipoFiltro) && (
          <p className="text-xs text-taupe">«{NOMBRE_TIPO[tipoFiltro]}» se mide sobre una ventana fija desde hoy: el periodo no la filtra.</p>
        )}

        {/* ── Historial de vistos buenos ─────────────────────────────────── */}
        {historial.length > 0 && (
          <section className="flex flex-col gap-3">
            <Boton variante="enlace" className="self-start text-sm text-taupe" aria-expanded={mostrarHistorial} onClick={() => setMostrarHistorial((x) => !x)}>
              {mostrarHistorial ? "Ocultar historial de vistos buenos" : `Ver historial de vistos buenos (${historial.length})`}
            </Boton>
            {mostrarHistorial && (
              <div className="overflow-x-auto rounded-superficie border border-sand bg-papel">
                <table className="w-full text-sm">
                  <TablaEncabezado>
                    <Th>Persona</Th>
                    <Th>Fecha</Th>
                    <Th>Incidencia</Th>
                    <Th>Visto bueno</Th>
                    <Th>Estado</Th>
                  </TablaEncabezado>
                  <tbody>
                    {historial.map((h, idx) => (
                      <tr key={`${h.persona_id}-${h.fecha}-${h.tipo}-${h.aceptado_at}-${idx}`} className="border-t border-sand">
                        <td className="px-4 py-2.5">
                          {`${h.personas?.nombres ?? ""} ${h.personas?.apellidos ?? ""}`.trim()}
                          <span className="text-taupe"> · {h.personas?.sedes?.codigo ?? "?"}</span>
                        </td>
                        <td className="whitespace-nowrap px-4 py-2.5 capitalize tabular-nums">{fechaCorta(h.fecha)}</td>
                        <td className="px-4 py-2.5">
                          {NOMBRE_TIPO[h.tipo as TipoIncidencia] ?? h.tipo.replaceAll("_", " ")}
                          {h.valor !== null && <span className="text-taupe"> · sobre {h.valor}</span>}
                        </td>
                        <td className="px-4 py-2.5 text-taupe">
                          {nombrePorId.get(h.aceptado_por) ?? "otra persona"} · {fechaHoraLima(h.aceptado_at)}
                          {h.nota && <span className="block">«{h.nota}»</span>}
                        </td>
                        <td className="px-4 py-2.5">
                          {h.anulada_at ? (
                            <span className="text-taupe">
                              Deshecho por {nombrePorId.get(h.anulada_por ?? "") ?? "otra persona"}
                              <span className="block">«{h.anulada_motivo}»</span>
                            </span>
                          ) : (
                            <Insignia variante="positivo">Vigente</Insignia>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </section>
        )}

        <PanelIncidencia
          incidencia={incidenciaAbierta}
          onCerrar={() => setAbierta(null)}
          volverElFocoA={volverFoco}
          motivoNoPuedeActuar={incidenciaAbierta ? motivoNoPuede(incidenciaAbierta) : null}
          etiquetaMotivo={etiquetaMotivo}
          nombrePorId={nombrePorId}
          onCambio={async (claveNueva) => {
            await cargar();
            if (claveNueva) setAbierta(claveNueva);
          }}
        />
      </main>
    </div>
  );
}

export default function IncidenciasPage() {
  return (
    <Suspense fallback={<main className="p-6"><Cargando /></main>}>
      <IncidenciasContenido />
    </Suspense>
  );
}
