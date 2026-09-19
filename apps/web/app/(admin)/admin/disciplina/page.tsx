"use client";

// ─────────────────────────────────────────────────────────────────────────────
// DISCIPLINA — rediseño del 2026-09-15 (lote 1: solo pantalla)
//
// Qué cambió y por qué, en una línea cada cosa (auditoría y decisiones del
// 2026-09-15):
//   · Pestañas por etapa real —Requieren revisión · Borradores · Por entregar ·
//     Historial— en vez de cuatro cajas que competían y dejaban contenedores
//     vacíos.
//   · Revisar primero: «Generar borrador» vive dentro del caso, al lado de la
//     evidencia. Antes estaba en la fila y se ofrecía también a quien le
//     faltaba una tardanza, donde la base lo rechazaba siempre.
//   · «Cerca del umbral» se separa de «Requieren revisión»: se sigue, no se
//     documenta.
//   · Entregado no es cerrado: lo que aún pide el cargo o una decisión se
//     queda en «Por entregar».
//   · Una acción principal por fila y el resto en «⋯», según el estado.
//   · Persona cesada: solo lo que todavía tiene sentido (cerrar sin entrega, o
//     registrar una entrega anterior al cese).
//   · Borrador desactualizado: si la asistencia cambió después de generarlo,
//     se dice y se bloquean «Comunicar cargos» y «Firmar».
//
// Lo que NO cambió: ninguna regla. Umbrales, escalones, generación, firma y
// entrega siguen decidiéndose en la base; ninguna llamada a una RPC cambió de
// forma. Los frenos de la base (desfase, persona cesada, motivos) y el
// historial con autor son los lotes 2 y 3.
// ─────────────────────────────────────────────────────────────────────────────

import { useCallback, useEffect, useMemo, useState, type MouseEvent, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { Cargando } from "@/components/cargando";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { useToast } from "@/components/toast";
import { instanteEntrega } from "@/lib/admin/instante-entrega";
import { subirArchivoConProgreso } from "@/lib/subir-archivo";
import { abrirArchivoFirmado } from "@/lib/abrir-archivo-firmado";
import { Boton } from "@/components/ui/boton";
import { Insignia } from "@/components/ui/insignia";
import { Modal } from "@/components/ui/modal";
import { AreaTexto } from "@/components/ui/area-texto";
import { Campo } from "@/components/ui/campo";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { Menu, MenuItem } from "@/components/ui/menu";
import { cx } from "@/components/ui/cx";
import { FormularioCargo, MAX_BYTES_CARGO, TITULO_PAPEL } from "@/components/disciplina/formulario-cargo";
import { Celda, FilaCaso, ListaCasos, type Encabezado } from "@/components/disciplina/lista-casos";
import {
  CAUSAL_LABEL, ESTADO_DOCUMENTO, ETIQUETA_PAPEL, MEDIO_ENTREGA, PanelCaso,
  type CasoAbierto, type PersonaInfo,
} from "@/components/disciplina/panel-caso";
import { addDias, fechaCorta, selloLima } from "@/components/disciplina/formato";
import { evidenciaDeDocumento, type Evidencia } from "@/lib/admin/disciplina-evidencia";
import {
  ETAPAS, ETAPA_LABEL, admiteEntregaAnteriorAlCese, esGradual, etapaDelBorrador, eventosDeObservacion,
  normalizarBusqueda, pendientesDeEntregado, pestanaDelDocumento, situacionFalta, situacionTardanza, ultimoDiaDeEntrega,
  type Adjunto, type DocDisciplina, type FaltaRow, type Pestana, type SituacionDeteccion, type TardanzaRow, type TipoPapel,
} from "@/lib/admin/disciplina";
import {
  NIVEL_DISCIPLINARIO_CORTO, NIVEL_DISCIPLINARIO_LABELS, fechaLima, hoyLima, mesesRecientesLima, nombreDelMesLima,
  nombreDelMesLimaTitulo, primeroDeMesLima, puedeAnularDocumentoDisciplinario, puedeOperarEquipo,
  puedeVerTodasLasSedes, rangoDelDiaLima, rangoDelMesLima,
} from "@cayla-dynamic/shared";

// ── Constantes ───────────────────────────────────────────────────────────────

const NIVEL_LABEL: Record<string, string> = NIVEL_DISCIPLINARIO_LABELS;
const nivelCorto = (n: string) => NIVEL_DISCIPLINARIO_CORTO[n as keyof typeof NIVEL_DISCIPLINARIO_CORTO] ?? n;

/** Las cuatro salidas de la valoración: las mismas que acepta fn_expediente_valorar_descargo. */
const ETIQUETA_DESCARGO: Record<string, string> = {
  sin_descargo: "No presentó descargo",
  total: "Se acoge",
  parcial: "Se acoge en parte",
  no: "No se acoge",
};

const NOMBRE_ARCHIVO: Record<TipoPapel, string> = { cargo_firmado: "cargo", acta_negativa: "acta", descargo: "descargo" };
const FALTA_PAPEL: Record<TipoPapel, string> = {
  cargo_firmado: "Falta el cargo firmado.",
  acta_negativa: "Falta el acta de la negativa. Sin el papel con el testigo no queda constancia de que se ofreció.",
  descargo: "Falta el descargo. Es el papel que prueba que la persona pudo defenderse dentro del plazo del art. 31.",
};

const COLUMNAS_DOC = "id, persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta, hechos, suspension_dias, suspension_desde, suspension_hasta, suspension_fechas, fecha_cese, resuelto_at, resuelto_por, resuelto_resultado, resuelto_motivo, correlativo, creado_at, creado_por, firmante_id, firmado_at, entregado_at, entregado_por, medio_entrega, entrega_testigo_nombre, cargos_comunicados_at, descargo_vence_at, descargo_acogido, descargo_valoracion, observacion";

// Seis columnas, la segunda (sede) secundaria: en tablet se esconde y la
// plantilla de `md` tiene cinco. Literal a propósito (ver lista-casos.tsx).
const PLANTILLA = "md:grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)_minmax(0,1fr)_minmax(0,1.3fr)_auto] lg:grid-cols-[minmax(0,1.4fr)_3.5rem_minmax(0,1fr)_minmax(0,1fr)_minmax(0,1.3fr)_auto]";

const TXT_DESFASE = "La asistencia cambió después de generar el borrador: algún día ya no se sostiene. Ábrelo para ver cuál.";

/** Quién puede suscribir un documento concreto (fn_expediente_firmantes, mig. 0074). */
interface Firmante { persona_id: string; nombre: string; cargo: string; tiene_firma: boolean }

interface Accion {
  etiqueta: string;
  alPulsar: (e?: MouseEvent<HTMLElement>) => void;
  variante?: "primario" | "secundario" | "peligro";
  disabled?: boolean;
  title?: string;
}
interface Acciones { principal: Accion | null; estado: string | null; menu: Array<Accion | "separador"> }

interface FilaDeteccion {
  clave: string; tipo: "tardanza" | "falta"; personaId: string; nombre: string; sede: string;
  situacion: SituacionDeteccion; progreso: ReactNode; motivo: string;
}

// ── Piezas chicas de la vista ────────────────────────────────────────────────

function Progreso({ n, de, alcanzado }: { n: number; de: number; alcanzado: boolean }) {
  const casillas = Math.min(Math.max(de, n), 6);
  return (
    <span className="inline-flex items-center gap-2 tabular-nums">
      <span className="inline-flex gap-0.5" aria-hidden>
        {Array.from({ length: casillas }, (_, i) => (
          <span key={i} className={cx("size-2 rounded-[2px]", i < n ? (alcanzado ? "bg-rojo" : "bg-tinta") : "bg-sand")} />
        ))}
      </span>
      {n} / {de}
    </span>
  );
}

function PasosBorrador({ etapa }: { etapa: (typeof ETAPAS)[number] }) {
  const actual = ETAPAS.indexOf(etapa);
  return (
    <span className="inline-flex flex-wrap items-center gap-2">
      <span className="inline-flex gap-0.5" aria-hidden>
        {ETAPAS.map((e, i) => (
          <span key={e} className={cx("h-1 w-4 rounded-full", i < actual ? "bg-verde" : i === actual ? "bg-pizarra" : "bg-sand")} />
        ))}
      </span>
      <span className="text-xs">{ETAPA_LABEL[etapa]}</span>
    </span>
  );
}

function TabBtn({ valor, tab, setTab, cuenta, urgente, children }: {
  valor: Pestana; tab: Pestana; setTab: (t: Pestana) => void; cuenta: number; urgente?: boolean; children: ReactNode;
}) {
  return (
    <button type="button" role="tab" id={`tab-${valor}`} aria-selected={tab === valor} aria-controls={`panel-${valor}`}
      onClick={() => setTab(valor)}
      className={cx("-mb-px inline-flex items-center gap-2 whitespace-nowrap border-b-2 px-3 py-2 text-sm transition-colors",
        tab === valor ? "border-rojo font-medium text-tinta" : "border-transparent text-taupe hover:text-tinta")}>
      {children}
      <Insignia variante={urgente && cuenta > 0 ? "contador" : "neutral"} tamano="sm" punto={false} className="tabular-nums">{cuenta}</Insignia>
    </button>
  );
}

function Grupo({ titulo, detalle, children }: { titulo: string; detalle?: string; children: ReactNode }) {
  return (
    <section className="mb-7">
      <div className="mb-2 flex flex-wrap items-baseline justify-between gap-x-4 gap-y-0.5">
        <h2 className="text-xs font-medium uppercase tracking-[0.08em] text-tinta">{titulo}</h2>
        {detalle && <span className="text-xs text-taupe">{detalle}</span>}
      </div>
      {children}
    </section>
  );
}

function Vacio({ children }: { children: ReactNode }) {
  return <p className="border-t border-dashed border-sand py-2 text-sm text-taupe">{children}</p>;
}

function FalloLectura({ que }: { que: string }) {
  return (
    <p className="mb-3 rounded-control bg-rojo/10 px-3 py-2 text-sm text-rojo-profundo">
      No se pudo leer {que}. <strong>Esto NO significa que no haya nadie</strong> — significa que no se pudo mirar.
      Vuelve a cargar la página; si sigue igual, avisa antes de dar el periodo por revisado.
    </p>
  );
}

// ─────────────────────────────────────────────────────────────────────────────

export default function DisciplinaPage() {
  const router = useRouter();
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;
  const puede = puedeOperarEquipo(rol);
  const puedeAnular = puedeAnularDocumentoDisciplinario(rol);
  const { avisar } = useToast();
  const supabase = useMemo(() => createAdminSupabaseClient(), []);

  // ── Datos ──────────────────────────────────────────────────────────────
  const [tardanzas, setTardanzas] = useState<TardanzaRow[]>([]);
  const [faltas, setFaltas] = useState<FaltaRow[]>([]);
  // «No hay nadie» y «no pude mirar» son cosas distintas. En esta pantalla esa
  // confusión es la peor que puede haber: da por revisado lo que no se revisó.
  const [falloTard, setFalloTard] = useState(false);
  const [falloFaltas, setFalloFaltas] = useState(false);
  const [falloDocs, setFalloDocs] = useState(false);
  const [docs, setDocs] = useState<DocDisciplina[]>([]);
  const [personas, setPersonas] = useState<Map<string, PersonaInfo>>(new Map());
  const [sedes, setSedes] = useState<string[]>([]);
  const [nombresAusencia, setNombresAusencia] = useState<Map<string, string>>(new Map());
  const [adjuntos, setAdjuntos] = useState<Map<string, Adjunto[]>>(new Map());
  // Quién puede suscribir CADA borrador: depende del nivel y de la sede (0074).
  // Desde la 0214 sale vacía a propósito para una carta de despido vista por DO.
  const [firmantes, setFirmantes] = useState<Record<string, Firmante[]>>({});
  // Quién no tiene constancia del Reglamento vigente (numeral 60.5, mig. 0228).
  const [sinConstancia, setSinConstancia] = useState<Map<string, string>>(new Map());
  /** Si la empresa exige el descargo previo (0268). Arranca en `true`: una lectura
   *  fallida no puede hacer aparecer un «Firmar» que la base va a rechazar. */
  const [exigeDescargo, setExigeDescargo] = useState(true);
  /** Lo que dice hoy la asistencia de los días que cita cada borrador y firmado. */
  const [evidencias, setEvidencias] = useState<Map<string, Evidencia>>(new Map());
  const [cargando, setCargando] = useState(true);

  // ── Vista ──────────────────────────────────────────────────────────────
  const [tab, setTab] = useState<Pestana>("revision");
  /** El mes de tardanzas, como `2026-08-01`. Se elige porque el numeral 19.4
   *  permite documentar un mes ya concluido. */
  const [mesTard, setMesTard] = useState<string>(primeroDeMesLima());
  const [busqueda, setBusqueda] = useState("");
  const [sedeFiltro, setSedeFiltro] = useState("");
  const [caso, setCaso] = useState<CasoAbierto | null>(null);
  // A quién devolverle el foco al cerrar el caso. En estado y no en un
  // `useRef`: el botón que abre vive dentro de las filas, y React Compiler no
  // deja tocar una ref desde funciones que se arman durante el render. El
  // Drawer solo necesita algo con forma de ref, y lo lee en su efecto.
  const [disparadorEl, setDisparadorEl] = useState<HTMLElement | null>(null);
  const disparador = useMemo(() => ({ current: disparadorEl }), [disparadorEl]);
  const [resaltado, setResaltado] = useState<string | null>(null);
  const [verReglas, setVerReglas] = useState(false);
  const [ocupado, setOcupado] = useState<string | null>(null);

  // ── Trámites: cada uno abre un Modal; la RPC vive en su «confirmar…» ────
  const [subiendoCargo, setSubiendoCargo] = useState<{ id: string; tipo: TipoPapel; fechaMax?: string } | null>(null);
  const [archivoCargo, setArchivoCargo] = useState<File | null>(null);
  const [fechaEntrega, setFechaEntrega] = useState(hoyLima());
  const [notaCargo, setNotaCargo] = useState("");
  const [testigoCargo, setTestigoCargo] = useState("");
  const [progresoCargo, setProgresoCargo] = useState<number | null>(null);
  const [entregandoSinPapel, setEntregandoSinPapel] = useState<DocDisciplina | null>(null);
  const [medio, setMedio] = useState("fisico");
  const [confirmandoCargos, setConfirmandoCargos] = useState<DocDisciplina | null>(null);
  // `fechaCargos` NACE EN HOY y no en "": un campo de fecha cuyo vacío bloquea
  // el envío no puede arrancar vacío (quinta regla de CLAUDE.md).
  const [declarando, setDeclarando] = useState<DocDisciplina | null>(null);
  const [fechaCargos, setFechaCargos] = useState(hoyLima());
  const [constanciaTexto, setConstanciaTexto] = useState("");
  const [valorando, setValorando] = useState<{ d: DocDisciplina; acogido: string } | null>(null);
  const [valoracionTexto, setValoracionTexto] = useState("");
  const [firmando, setFirmando] = useState<string | null>(null);
  const [firmanteElegido, setFirmanteElegido] = useState<Record<string, string>>({});
  const [resolviendo, setResolviendo] = useState<{ d: DocDisciplina; resultado: "" | "archivado" | "despido" } | null>(null);
  const [motivoResolucion, setMotivoResolucion] = useState("");
  const [reabriendo, setReabriendo] = useState<string | null>(null);
  const [anulando, setAnulando] = useState<{ id: string; entregado: boolean } | null>(null);
  const [motivoAnular, setMotivoAnular] = useState("");
  const [cerrandoSinEntrega, setCerrandoSinEntrega] = useState<string | null>(null);
  const [motivoCierre, setMotivoCierre] = useState("");

  const modalAbierto = verReglas || subiendoCargo !== null || entregandoSinPapel !== null || confirmandoCargos !== null
    || declarando !== null || valorando !== null || firmando !== null || resolviendo !== null || reabriendo !== null
    || anulando !== null || cerrandoSinEntrega !== null;

  // ── Carga ──────────────────────────────────────────────────────────────
  const cargar = useCallback(async (): Promise<DocDisciplina[]> => {
    setCargando(true);
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return []; }
    const [
      { data: t, error: eT }, { data: f, error: eF }, { data: d, error: eD },
      { data: p }, { data: s }, { data: ta },
    ] = await Promise.all([
      // Mes en curso: sin argumentos. Uno cerrado: `p_as_of` en su último día (0067).
      supabase.rpc("fn_tardanzas_resumen",
        mesTard === primeroDeMesLima() ? {} : { p_as_of: rangoDelMesLima(mesTard).fin }),
      supabase.rpc("fn_faltas_resumen", {}),
      // Todos los estados: anulados y cerrados sin entrega desaparecían de la
      // pantalla y no había dónde consultarlos.
      supabase.from("expediente_disciplinario").select(COLUMNAS_DOC).order("creado_at", { ascending: false }),
      supabase.from("personas").select("id, nombres, apellidos, estado, sede_base_id, fecha_cese"),
      supabase.from("sedes").select("id, codigo").order("codigo"),
      supabase.from("tipos_ausencia").select("codigo, nombre"),
    ]);
    // Los TRES errores, cada uno nombrando su sección: un «error al cargar»
    // genérico deja igual de ciego que el silencio.
    const fallos = [
      eT ? mensajeDeError(eT, "cargar la cuenta de tardanzas") : null,
      eF ? mensajeDeError(eF, "cargar la cuenta de faltas") : null,
      eD ? mensajeDeError(eD, "cargar el legajo") : null,
    ].filter(Boolean);
    if (fallos.length) avisar("error", fallos.join(" · "));
    setFalloTard(!!eT);
    setFalloFaltas(!!eF);
    setFalloDocs(!!eD);

    // Doble casteo: `types.ts` es generado y no describe `sin_medir` (ver 0184).
    setTardanzas(Array.isArray(t) ? (t as unknown as TardanzaRow[]) : []);
    setFaltas(Array.isArray(f) ? (f as unknown as FaltaRow[]) : []);
    const lista = Array.isArray(d) ? (d as unknown as DocDisciplina[]) : [];
    setDocs(lista);

    const codigoDeSede = new Map(((s ?? []) as { id: string; codigo: string }[]).map((x) => [x.id, x.codigo]));
    setSedes([...new Set(codigoDeSede.values())]);
    const personasList = (p ?? []) as Array<{ id: string; nombres: string; apellidos: string; estado: string; sede_base_id: string | null; fecha_cese: string | null }>;
    setPersonas(new Map(personasList.map((x) => [x.id, {
      nombre: `${x.nombres} ${x.apellidos}`,
      sede: (x.sede_base_id && codigoDeSede.get(x.sede_base_id)) || "",
      estado: x.estado,
      fechaCese: x.fecha_cese,
    }])));
    const tipos = new Map(((ta ?? []) as { codigo: string; nombre: string }[]).map((x) => [x.codigo, x.nombre]));
    setNombresAusencia(tipos);

    // Consulta aparte y tolerante: sin adjuntos la pantalla sigue funcionando.
    const { data: adj } = await supabase
      .from("expediente_adjuntos")
      .select("id, documento_id, storage_path, tipo, nota, subido_at")
      .order("subido_at", { ascending: false });
    const porDoc = new Map<string, Adjunto[]>();
    for (const a of (adj as Adjunto[]) ?? []) porDoc.set(a.documento_id, [...(porDoc.get(a.documento_id) ?? []), a]);
    setAdjuntos(porDoc);

    const borradores = lista.filter((x) => x.estado === "borrador");
    const [pares, evs, { data: cfg }, { data: sc }] = await Promise.all([
      Promise.all(borradores.map(async (x) => {
        const { data: fs } = await supabase.rpc("fn_expediente_firmantes", { p_id: x.id });
        return [x.id, Array.isArray(fs) ? (fs as Firmante[]) : []] as const;
      })),
      // Borradores y firmados: es donde un día que dejó de valer todavía se
      // puede frenar. Los demás se leen al abrir el caso.
      Promise.all(lista.filter((x) => x.estado === "borrador" || x.estado === "firmado").map(async (x) =>
        [x.id, await evidenciaDeDocumento(supabase, x, lista, tipos)] as const)),
      supabase.from("configuracion").select("valor").eq("clave", "disciplina_descargo_previo").maybeSingle(),
      supabase.rpc("fn_sin_constancia_del_reglamento"),
    ]);
    setFirmantes(Object.fromEntries(pares));
    setEvidencias(new Map(evs));
    // Misma forma que la base: solo `false` exacto releva del trámite.
    setExigeDescargo((cfg as { valor: unknown } | null)?.valor !== false);
    setSinConstancia(new Map(((sc as { persona_id: string; motivo: string }[]) ?? []).map((x) => [x.persona_id, x.motivo])));
    setCargando(false);
    return lista;
  }, [supabase, router, mesTard, avisar]);

  // La carga al entrar, con la misma forma que el resto del panel (mio/,
  // boleta, editar): `cargar` marca «cargando» antes de su primera espera.
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void cargar(); }, [cargar]);

  // Atajos desde el Dashboard: `#tard-ID` y `#falta-ID` bajan hasta la fila en
  // «Requieren revisión»; `#entregados` («N memos sin el cargo archivado»)
  // abre «Por entregar», que es donde viven ahora. Aterrizar y no ver nada es
  // igual a no haber avisado.
  useEffect(() => {
    if (cargando) return;
    const hash = typeof window !== "undefined" ? window.location.hash.slice(1) : "";
    if (!hash) return;
    const t0 = setTimeout(() => {
      if (hash === "entregados") { setTab("entregar"); return; }
      if (!hash.startsWith("tard-") && !hash.startsWith("falta-")) return;
      setTab("revision");
      setResaltado(hash);
      requestAnimationFrame(() => {
        const reduce = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
        document.getElementById(hash)?.scrollIntoView({ behavior: reduce ? "auto" : "smooth", block: "center" });
      });
    }, 0);
    const t1 = setTimeout(() => setResaltado(null), 2800);
    return () => { clearTimeout(t0); clearTimeout(t1); };
  }, [cargando]);

  function abrirCaso(c: CasoAbierto, e?: MouseEvent<HTMLElement>) {
    if (e) setDisparadorEl(e.currentTarget);
    setCaso(c);
  }

  // ── Generar ────────────────────────────────────────────────────────────
  async function generar(tipo: "tardanza" | "falta", personaId: string) {
    setOcupado(personaId);
    // El generador de tardanzas recibe el mes; el de faltas no, porque su
    // escala no se cuenta por mes calendario.
    const { error } = tipo === "tardanza"
      ? await supabase.rpc("fn_expediente_generar_tardanza", { p_persona_id: personaId, p_mes: mesTard })
      : await supabase.rpc("fn_expediente_generar_falta", { p_persona_id: personaId });
    setOcupado(null);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    const lista = await cargar();
    const nuevo = lista.find((x) => x.estado === "borrador" && x.persona_id === personaId && x.tipo_causal === tipo);
    setTab("borradores");
    setCaso(nuevo ? { tipo: "documento", id: nuevo.id } : null);
    avisar("ok", "Borrador generado. Revisa la evidencia y sigue el paso que indica.");
  }

  // ── Comunicar cargos (art. 55.2): abre el plazo, que NO se reabre ───────
  async function confirmarComunicarCargos(d: DocDisciplina) {
    setOcupado(d.id);
    const { data, error } = await supabase.rpc("fn_expediente_comunicar_cargos", { p_id: d.id, p_dias: 2, p_nota: null });
    setOcupado(null);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    setConfirmandoCargos(null);
    await cargar();
    avisar("ok", `Cargos comunicados · su plazo de descargo vence el ${selloLima(String(data))}`);
  }

  /**
   * Registrar una comunicación de cargos que YA OCURRIÓ, con su fecha (0266).
   * No adelanta nada: la base sigue exigiendo que el plazo de ESA fecha venza.
   * El día se elige en un calendario, no se teclea (hallazgo 34, 2026-09-03).
   */
  function abrirDeclaracion(d: DocDisciplina) {
    setFechaCargos(hoyLima());
    setConstanciaTexto("");
    setDeclarando(d);
  }

  async function confirmarDeclararCargos(d: DocDisciplina) {
    const dia = fechaCargos;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dia)) {
      avisar("error", "Elige en el calendario el día en que se le comunicaron los cargos.");
      return;
    }
    if (dia > hoyLima()) {
      avisar("error", "Ese día todavía no llega: los cargos no pudieron comunicarse en el futuro.");
      return;
    }
    const constancia = constanciaTexto.trim();
    if (constancia.length < 15) {
      avisar("error", "Falta decir cómo consta, y con detalle: va a ser la única prueba de que esa comunicación existió.");
      return;
    }
    setOcupado(d.id);
    // Dentro del `try` va SOLO la llamada: un fallo al refrescar no puede decir
    // «no se pudo registrar» si ya se registró.
    let vence: string;
    try {
      const { data, error } = await supabase.rpc("fn_expediente_declarar_cargos_comunicados", {
        p_id: d.id, p_fecha: instanteEntrega(dia, null), p_constancia: constancia, p_dias: 2,
      });
      if (error) { avisar("error", mensajeDeError(error, "registrar la comunicación")); return; }
      vence = String(data);
    } catch {
      avisar("error", "No se pudo registrar la comunicación. Vuelve a elegir el día en el calendario y repítelo; si sigue igual, avisa a Felipe.");
      return;
    } finally {
      setOcupado(null);
    }
    setDeclarando(null);
    const plazo = `Comunicación registrada · su plazo de descargo venció o vence el ${selloLima(vence)}`;
    try {
      await cargar();
      avisar("ok", plazo);
    } catch {
      avisar("ok", `${plazo}. La lista no se pudo actualizar: recarga la página para verla al día.`);
    }
  }

  // ── Valorar el descargo (19.3): se deja por escrito aunque no haya ─────
  async function confirmarValorarDescargo() {
    if (!valorando) return;
    const { d, acogido } = valorando;
    if (!acogido) { avisar("error", "Elige cómo se valora el descargo."); return; }
    const pideTexto = acogido === "parcial" || acogido === "no";
    if (pideTexto && valoracionTexto.trim().length < 10) {
      avisar("error", "Hace falta el motivo, y con algo de detalle: es lo que se lee si alguien discute la sanción.");
      return;
    }
    setOcupado(d.id);
    const { error } = await supabase.rpc("fn_expediente_valorar_descargo", {
      p_id: d.id, p_acogido: acogido, p_valoracion: pideTexto ? valoracionTexto.trim() : null,
    });
    setOcupado(null);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    setValorando(null);
    await cargar();
    avisar("ok", acogido === "total"
      ? "Descargo acogido. Si ya no corresponde sancionar, anula el borrador."
      : "Valoración guardada. Ya se puede firmar.");
  }

  // ── Firmar ─────────────────────────────────────────────────────────────
  /** El firmante que MUESTRA el desplegable es el que viaja: antes se mostraba
   *  el primero de la lista y, si nadie lo tocaba, se mandaba null. */
  function firmanteDe(id: string): string {
    const lista = firmantes[id] ?? [];
    return firmanteElegido[id] ?? lista.find((f) => f.persona_id === yo?.id)?.persona_id ?? lista[0]?.persona_id ?? "";
  }

  async function confirmarFirmar(id: string) {
    const elegido = firmanteDe(id);
    setOcupado(id);
    const { data, error } = await supabase.rpc("fn_expediente_firmar", { p_id: id, p_firmante_id: elegido || null });
    setOcupado(null);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    setFirmando(null);
    await cargar();
    setTab("entregar");
    avisar("ok", `Firmado — documento ${data ?? ""}. Ya puedes entregarlo.`);
  }

  // ── Papeles: cargo, acta de negativa, descargo ─────────────────────────
  function abrirCargo(id: string, tipo: TipoPapel, fechaMax?: string) {
    setArchivoCargo(null);
    setFechaEntrega(fechaMax ?? hoyLima());
    setNotaCargo("");
    setTestigoCargo("");
    setSubiendoCargo({ id, tipo, fechaMax });
  }

  async function guardarCargo() {
    if (!subiendoCargo) return;
    const doc = docs.find((x) => x.id === subiendoCargo.id) ?? null;
    // El acta de negativa ENTREGA (num. 55.4): produce los mismos efectos que
    // el cargo firmado. Hasta la 0303 solo se archivaba y la negativa salía gratis.
    const actaEntrega = subiendoCargo.tipo === "acta_negativa" && doc?.estado === "firmado";
    const pideFecha = (subiendoCargo.tipo === "cargo_firmado" && doc?.estado === "firmado") || actaEntrega;
    if (!archivoCargo) { avisar("error", FALTA_PAPEL[subiendoCargo.tipo]); return; }
    if (archivoCargo.size > MAX_BYTES_CARGO) {
      avisar("error", `“${archivoCargo.name}” pesa ${(archivoCargo.size / 1048576).toFixed(1)} MB y el máximo es 50 MB.`);
      return;
    }
    if (pideFecha && !fechaEntrega) {
      avisar("error", "Indica la fecha de entrega: desde ahí corren los plazos de descargo.");
      return;
    }
    if (subiendoCargo.fechaMax && fechaEntrega > subiendoCargo.fechaMax) {
      avisar("error", `La entrega tiene que ser de un día en que la persona todavía trabajaba: hasta el ${fechaCorta(subiendoCargo.fechaMax)}.`);
      return;
    }
    if (actaEntrega && !testigoCargo.trim()) {
      avisar("error", "Escribe el nombre del testigo: el acta la suscriben quien entrega y un testigo (num. 55.4 del RIT). Sin testigo no hay acta, y sin acta no hay entrega.");
      return;
    }
    // Decisión del 2026-09-15: la negativa pide qué pasó. Viaja en la nota del
    // adjunto, que es donde la base ya la guarda.
    if (subiendoCargo.tipo === "acta_negativa" && notaCargo.trim().length < 10) {
      avisar("error", "Cuenta qué pasó, con algo de detalle: es lo que sostiene la negativa si alguien la discute.");
      return;
    }

    setOcupado(subiendoCargo.id);
    // "<id del documento>/…" es lo que valida fn_expediente_puede_adjuntar: no
    // hay forma de colgar el archivo del memo equivocado.
    const ext = archivoCargo.name.split(".").pop()?.toLowerCase() ?? "bin";
    const ruta = `${subiendoCargo.id}/${NOMBRE_ARCHIVO[subiendoCargo.tipo]}-${Date.now()}.${ext}`;
    setProgresoCargo(0);
    const fallo = await subirArchivoConProgreso(supabase, "expedientes", ruta, archivoCargo, setProgresoCargo);
    setProgresoCargo(null);
    if (fallo) {
      setOcupado(null);
      avisar("error", `El archivo no subió (${fallo}). Vuelve a intentarlo.`);
      return;
    }
    const { error } = await supabase.rpc("fn_expediente_adjuntar", {
      p_documento_id: subiendoCargo.id,
      p_path: ruta,
      p_tipo: subiendoCargo.tipo,
      // Solo el cargo firmado entrega por esta vía (marca 'fisico'). El acta se
      // entrega abajo, con su medio y su testigo.
      p_fecha_entrega: pideFecha && !actaEntrega ? instanteEntrega(fechaEntrega, doc?.firmado_at ?? null) : null,
      p_nota: notaCargo.trim() || null,
    });
    if (error) { setOcupado(null); avisar("error", mensajeDeError(error)); return; }

    // En este orden a propósito: si esto falla, el acta ya está archivada y el
    // documento sigue «firmado», del que se sale reintentando.
    if (actaEntrega) {
      const { error: falloEntrega } = await supabase.rpc("fn_expediente_entregar", {
        p_id: subiendoCargo.id,
        p_medio: "acta_negativa",
        p_fecha: instanteEntrega(fechaEntrega, doc?.firmado_at ?? null),
        p_testigo_nombre: testigoCargo.trim(),
      });
      if (falloEntrega) {
        setOcupado(null);
        setSubiendoCargo(null);
        await cargar();
        avisar("error", `El acta quedó archivada, pero el documento NO se marcó entregado (${mensajeDeError(falloEntrega)}). Vuelve a intentarlo desde «Entregar sin papel».`);
        return;
      }
    }
    setOcupado(null);
    const tipo = subiendoCargo.tipo;
    setSubiendoCargo(null);
    await cargar();
    avisar("ok", tipo === "acta_negativa"
      ? actaEntrega
        ? "Acta archivada y documento ENTREGADO. La negativa produce los mismos efectos que la firma (num. 55.4): desde hoy corren los plazos."
        : "Acta de negativa archivada contra el documento."
      : tipo === "descargo"
        ? "Descargo archivado en el legajo. Es la pieza que prueba que se respetó el plazo del art. 31."
        : pideFecha
          ? "Cargo archivado y documento marcado como entregado."
          : "Cargo archivado contra el documento. La fecha de entrega registrada no cambió.");
  }

  async function verAdjunto(path: string) {
    // URL firmada de vida corta: el bucket es privado.
    const fallo = await abrirArchivoFirmado(supabase, "expedientes", path);
    if (fallo) avisar("error", fallo);
  }

  // ── Entregar sin papel: una entrega por correo certificado es válida y su
  //    cargo llega días después. Sigue existiendo, pero no es el atajo. ────
  async function confirmarEntregar() {
    if (!entregandoSinPapel) return;
    const id = entregandoSinPapel.id;
    setOcupado(id);
    const { error } = await supabase.rpc("fn_expediente_entregar", { p_id: id, p_medio: medio });
    setOcupado(null);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    setEntregandoSinPapel(null);
    await cargar();
    avisar("ok", "Marcado como entregado. Sube el cargo firmado cuando llegue.");
  }

  // ── Resolver una imputación (art. 31): NO es anular ─────────────────────
  async function confirmarResolver() {
    if (!resolviendo) return;
    const { d, resultado } = resolviendo;
    if (!resultado) { avisar("error", "Elige qué se resolvió."); return; }
    if (motivoResolucion.trim().length < 10) {
      avisar("error", "Explica la decisión con al menos 10 caracteres: es lo que sostiene el expediente si alguien lo revisa.");
      return;
    }
    setOcupado(d.id);
    const { error } = await supabase.rpc("fn_expediente_resolver", {
      p_id: d.id, p_resultado: resultado, p_motivo: motivoResolucion.trim(),
    });
    setOcupado(null);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    setResolviendo(null);
    await cargar();
    avisar("ok", resultado === "archivado"
      ? "Procedimiento archivado. El sistema deja de pedir una decisión ya tomada."
      : "Anotado que se resolvió con despido. La carta se emite aparte.");
  }

  /**
   * Fijar los días de una suspensión. Son días LABORABLES DE ESA PERSONA (0075):
   * el 25/07/2026 contar días de calendario convirtió una suspensión de tres
   * días en una de uno. El cálculo vive en la base. El camino viejo queda solo
   * como red por si esta base no tiene `fn_expediente_set_suspension`.
   */
  async function guardarDias(d: DocDisciplina, dias: number, desdeElegido?: string) {
    if (dias < 1) return;
    const desde = desdeElegido ?? d.suspension_desde ?? addDias(hoyLima(), 1);
    setOcupado(d.id);
    const { data, error } = await supabase.rpc("fn_expediente_set_suspension", { p_id: d.id, p_dias: dias, p_desde: desde });
    // PGRST202 = PostgREST no encuentra la función.
    if (error && error.code !== "PGRST202") { setOcupado(null); avisar("error", mensajeDeError(error)); return; }
    if (!error) {
      setOcupado(null);
      const fechas = (data as Array<{ fecha: string }> | null)?.map((x) => x.fecha) ?? [];
      const salta = fechas.length > 1 && addDias(fechas[0], fechas.length - 1) !== fechas[fechas.length - 1];
      await cargar();
      if (fechas.length) {
        avisar("ok", salta
          ? `Suspensión fijada en ${fechas.map(fechaCorta).join(", ")} — se saltan sus días de descanso, que no cuentan como sanción.`
          : `Suspensión fijada en ${fechas.map(fechaCorta).join(", ")}`);
      }
      return;
    }
    const { error: eViejo } = await supabase.rpc("fn_expediente_editar_borrador", {
      p_id: d.id, p_suspension_dias: dias, p_suspension_desde: desde, p_suspension_hasta: addDias(desde, dias - 1),
    });
    setOcupado(null);
    if (eViejo) { avisar("error", mensajeDeError(eViejo)); return; }
    await cargar();
    avisar("error", "Días fijados por CALENDARIO: falta aplicar la migración 0075 en esta base. "
      + "Comprueba a mano que ninguno caiga en su día de descanso — si cae, la suspensión no se cumple ese día y el memo diría algo falso.");
  }

  /** La fecha de cese que declarará la carta de despido (art. 32 LPCL, 0205). */
  async function guardarFechaCese(d: DocDisciplina, fecha: string) {
    if (!fecha || fecha === d.fecha_cese) return;
    setOcupado(d.id);
    const { error } = await supabase.rpc("fn_expediente_editar_borrador", { p_id: d.id, p_fecha_cese: fecha });
    setOcupado(null);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    await cargar();
    avisar("ok", `Fecha de cese fijada en ${fechaCorta(fecha)}. Es la que imprimirá la carta.`);
  }

  // ── Cambiar firmante: vuelve a borrador (0131). Solo mientras no se entregue.
  async function confirmarReabrir(id: string) {
    setOcupado(id);
    const { error } = await supabase.rpc("fn_expediente_reabrir", { p_id: id });
    setOcupado(null);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    setReabriendo(null);
    await cargar();
    setTab("borradores");
    avisar("ok", "Vuelto a borrador. Elige el firmante correcto y fírmalo de nuevo.");
  }

  /**
   * Anular. Distinto de archivar: anular devuelve el escalón al peldaño que
   * tocaba; archivar lo deja donde está. Anular algo ENTREGADO retira un papel
   * que la persona ya tiene, y hay que decírselo por escrito.
   */
  function abrirAnular(id: string, entregado: boolean) {
    setMotivoAnular("");
    setAnulando({ id, entregado });
  }

  async function confirmarAnular() {
    if (!anulando) return;
    const { id, entregado } = anulando;
    if (motivoAnular.trim().length < 3) {
      avisar("error", "Escribe el motivo de la anulación: queda registrado en el documento.");
      return;
    }
    setOcupado(id);
    const { error } = await supabase.rpc("fn_expediente_anular", { p_id: id, p_motivo: motivoAnular.trim() });
    setOcupado(null);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    setAnulando(null);
    await cargar();
    avisar("ok", entregado
      ? "Documento anulado. Queda el rastro con tu motivo — ahora comunícaselo a la persona por escrito."
      : "Documento anulado.");
  }

  /**
   * Cerrar sin entrega (0412): la persona cesó antes de que se le pudiera
   * entregar. No es anular: el documento sí era válido. Desde el 2026-09-15 el
   * motivo es obligatorio en la pantalla; la base lo guarda en `observacion`.
   */
  async function confirmarCerrarSinEntrega() {
    if (!cerrandoSinEntrega) return;
    const id = cerrandoSinEntrega;
    if (motivoCierre.trim().length < 10) {
      avisar("error", "Explica por qué no se le entregó, con algo de detalle: es lo único que queda de este documento.");
      return;
    }
    setOcupado(id);
    const { error } = await supabase.rpc("fn_expediente_cerrar_sin_entrega", { p_id: id, p_motivo: motivoCierre.trim() });
    setOcupado(null);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    setCerrandoSinEntrega(null);
    await cargar();
    avisar("ok", "Cerrado sin entrega. Queda en el historial con tu motivo.");
  }

  /**
   * El rango de días que el Reglamento admite para ESTA suspensión: techo de
   * tres (54.5); la primera por tardanzas de uno a dos (19.2 c), la segunda
   * mayor que la primera (19.2 d). La misma cuenta que hace la base (0294),
   * para que el campo OFREZCA lo que se puede pedir. La referencia es el cierre
   * del periodo que el documento cubre (19.1 c), no «hoy».
   */
  function rangoSuspension(d: DocDisciplina): { min: number; max: number; previa: number | null } {
    const ref = Date.parse(rangoDelDiaLima(d.periodo_hasta ?? hoyLima()).fin);
    const doceMeses = ref - 365 * 24 * 60 * 60 * 1000;
    const dias = docs
      .filter((x) => x.persona_id === d.persona_id && x.tipo_causal === d.tipo_causal
        && x.nivel === "suspension" && x.estado === "entregado" && x.id !== d.id
        && x.entregado_at !== null && Date.parse(x.entregado_at) >= doceMeses && Date.parse(x.entregado_at) <= ref)
      .map((x) => x.suspension_dias ?? 0);
    const previa = dias.length ? Math.max(...dias) : null;
    if (d.tipo_causal !== "tardanza") return { min: 1, max: 3, previa };
    if (previa === null) return { min: 1, max: 2, previa };
    return { min: Math.min(previa + 1, 3), max: 3, previa };
  }

  if (rol !== null && !puede) {
    return (
      <div className="flex flex-1 flex-col">
        <main className="flex flex-1 items-center justify-center p-6">
          <p className="max-w-md text-center text-taupe">No tienes permiso para el módulo disciplinario.</p>
        </main>
      </div>
    );
  }

  // ── Qué se ve ──────────────────────────────────────────────────────────
  const q = normalizarBusqueda(busqueda);
  const pasa = (nombre: string, sede: string) =>
    (!q || normalizarBusqueda(nombre).includes(q)) && (!sedeFiltro || sede === sedeFiltro);
  const infoDe = (id: string) => personas.get(id);
  const nombreDe = (id: string) => infoDe(id)?.nombre ?? "—";
  const nombreMes = nombreDelMesLima(mesTard);
  const pendientePorCausal = new Set(docs.filter((d) => d.estado === "borrador").map((d) => `${d.persona_id}:${d.tipo_causal}`));

  const detecciones: FilaDeteccion[] = [
    ...tardanzas.filter((t) => pasa(t.nombre, t.sede)).map((t): FilaDeteccion => {
      const s = situacionTardanza(t, nombreMes, pendientePorCausal.has(`${t.persona_id}:tardanza`));
      return {
        clave: `tard-${t.persona_id}`, tipo: "tardanza", personaId: t.persona_id, nombre: t.nombre, sede: t.sede, situacion: s,
        motivo: `Tardanzas · ${nombreMes}`,
        progreso: t.minimo !== null
          ? <Progreso n={t.tardanzas_mes} de={t.minimo} alcanzado={s.grupo === "alcanzo"} />
          : <span className="tabular-nums">{t.tardanzas_mes}</span>,
      };
    }),
    ...faltas.filter((f) => pasa(f.nombre, f.sede)).map((f): FilaDeteccion => ({
      clave: `falta-${f.persona_id}`, tipo: "falta", personaId: f.persona_id, nombre: f.nombre, sede: f.sede,
      situacion: situacionFalta(f, pendientePorCausal.has(`${f.persona_id}:falta`)),
      motivo: "Faltas · 180 días",
      progreso: <span className="tabular-nums text-xs">{f.consecutivas} seguidas · {f.en_30} en 30 d · {f.en_180} en 180 d</span>,
    })),
  ];
  const alcanzaron = detecciones.filter((x) => x.situacion.grupo === "alcanzo");
  const seguimiento = detecciones.filter((x) => x.situacion.grupo === "seguimiento");

  const docsVisibles = docs.filter((d) => pasa(nombreDe(d.persona_id), infoDe(d.persona_id)?.sede ?? ""));
  const porPestana = (p: Pestana) => docsVisibles.filter((d) => pestanaDelDocumento(d, adjuntos.get(d.id) ?? []) === p);
  const borradores = porPestana("borradores");
  const porEntregar = porPestana("entregar");
  const firmados = porEntregar.filter((d) => d.estado === "firmado");
  const entregadosPendientes = porEntregar.filter((d) => d.estado === "entregado");
  const historial = porPestana("historial").sort((a, b) =>
    Date.parse(b.entregado_at ?? b.firmado_at ?? b.creado_at) - Date.parse(a.entregado_at ?? a.firmado_at ?? a.creado_at));
  const hayFiltro = q !== "" || sedeFiltro !== "";

  // ── Acciones de cada documento, según su estado ────────────────────────
  // Las mismas en la fila y en el panel: dos listas para el mismo documento
  // terminan ofreciendo cosas distintas.
  function accionesDeDocumento(d: DocDisciplina): Acciones {
    const papeles = adjuntos.get(d.id) ?? [];
    const info = infoDe(d.persona_id);
    const ocup = ocupado === d.id;
    const memo: Accion = { etiqueta: "Ver memo", alPulsar: () => router.push(`/admin/disciplina/memo/${d.id}`) };
    const verPapeles: Accion[] = papeles.map((a) => ({ etiqueta: ETIQUETA_PAPEL[a.tipo] ?? "Ver papel", alPulsar: () => void verAdjunto(a.storage_path) }));
    const anular: Accion[] = puedeAnular
      ? [{ etiqueta: d.estado === "borrador" ? "Anular borrador" : "Anular documento", alPulsar: () => abrirAnular(d.id, d.estado === "entregado"), variante: "peligro", disabled: ocup }]
      : [];

    if (d.estado === "borrador") {
      const etapa = etapaDelBorrador(d, exigeDescargo);
      const desfase = (evidencias.get(d.id)?.noCuentan ?? 0) > 0;
      const menu: Acciones["menu"] = [memo];
      let principal: Accion | null = null;
      let estado: string | null = null;
      if (etapa === "comunicar") {
        principal = { etiqueta: "Comunicar cargos", alPulsar: () => setConfirmandoCargos(d), variante: "primario", disabled: ocup || desfase, title: desfase ? TXT_DESFASE : undefined };
        // Para lo que ya ocurrió: el camino normal es comunicar hoy.
        menu.push({ etiqueta: "Ya se lo comuniqué", alPulsar: () => abrirDeclaracion(d), disabled: ocup || desfase });
      } else if (etapa === "esperando") {
        estado = `Descargo hasta ${d.descargo_vence_at ? selloLima(d.descargo_vence_at) : "—"}`;
      } else if (etapa === "valorar") {
        principal = { etiqueta: "Valorar descargo", alPulsar: () => { setValoracionTexto(""); setValorando({ d, acogido: "" }); }, variante: "primario", disabled: ocup };
      } else {
        // `=== 0` y no `?? []`: la clave ausente es «todavía no se preguntó», y
        // ahí se deja pasar para que decida la base (art. 54.4 c).
        const sinFirmante = firmantes[d.id]?.length === 0;
        principal = {
          etiqueta: "Firmar", alPulsar: () => setFirmando(d.id), variante: "primario", disabled: ocup || sinFirmante || desfase,
          title: desfase ? TXT_DESFASE : sinFirmante ? `Un documento de nivel ${(NIVEL_LABEL[d.nivel] ?? d.nivel).toLowerCase()} no lo puedes suscribir tú (art. 54.4 del Reglamento).` : undefined,
        };
      }
      if (anular.length) menu.push("separador", ...anular);
      return { principal, estado, menu };
    }

    if (d.estado === "firmado") {
      // Persona cesada: lo que asume que sigue ahí para recibirlo no se ofrece.
      if (info?.estado === "inactivo") {
        const menu: Acciones["menu"] = [memo];
        if (admiteEntregaAnteriorAlCese(d, info.fechaCese)) {
          menu.push({ etiqueta: "Registrar entrega anterior al cese", alPulsar: () => abrirCargo(d.id, "cargo_firmado", ultimoDiaDeEntrega(info.fechaCese!)), disabled: ocup });
        }
        return {
          principal: { etiqueta: "Cerrar sin entrega", alPulsar: () => { setMotivoCierre(""); setCerrandoSinEntrega(d.id); }, variante: "primario", disabled: ocup },
          estado: null, menu,
        };
      }
      return {
        principal: { etiqueta: "Subir cargo firmado", alPulsar: () => abrirCargo(d.id, "cargo_firmado"), variante: "primario", disabled: ocup },
        estado: null,
        menu: [
          memo,
          { etiqueta: "Registrar negativa a firmar", alPulsar: () => abrirCargo(d.id, "acta_negativa"), disabled: ocup },
          { etiqueta: "Entregar sin papel", alPulsar: () => { setMedio("fisico"); setEntregandoSinPapel(d); }, disabled: ocup },
          "separador",
          { etiqueta: "Cambiar firmante", alPulsar: () => setReabriendo(d.id), disabled: ocup },
        ],
      };
    }

    if (d.estado === "entregado") {
      const pend = pendientesDeEntregado(d, papeles);
      const menu: Acciones["menu"] = [...verPapeles];
      let principal: Accion | null = null;
      if (pend.includes("cargo")) principal = { etiqueta: "Subir cargo", alPulsar: () => abrirCargo(d.id, "cargo_firmado"), variante: "primario", disabled: ocup };
      // Solo la imputación abre un plazo de descargo, así que solo ella lo pide.
      if (d.nivel === "imputacion" && !papeles.some((a) => a.tipo === "descargo")) {
        menu.push({ etiqueta: "Subir su descargo", alPulsar: () => abrirCargo(d.id, "descargo"), disabled: ocup });
      }
      if (pend.includes("resolver")) {
        const resolver: Accion = { etiqueta: "Registrar la decisión", alPulsar: () => { setMotivoResolucion(""); setResolviendo({ d, resultado: "" }); }, disabled: ocup };
        if (principal) menu.push(resolver); else principal = { ...resolver, variante: "primario" };
      }
      if (principal) menu.unshift(memo); else principal = { ...memo, variante: "secundario" };
      if (anular.length) menu.push("separador", ...anular);
      return { principal, estado: null, menu };
    }

    // Anulado o cerrado sin entrega: solo consulta.
    return { principal: { ...memo, variante: "secundario" }, estado: null, menu: [] };
  }

  function pintarAcciones(a: Acciones, verCaso?: () => void): ReactNode {
    const menu = a.menu.filter((m) => m === "separador" || !m.disabled);
    // Sin separadores sueltos al principio o al final.
    while (menu[0] === "separador") menu.shift();
    while (menu[menu.length - 1] === "separador") menu.pop();
    return (
      <>
        {a.estado && <span className="text-xs text-taupe">{a.estado}</span>}
        {a.principal && (
          <Boton variante={a.principal.variante ?? "secundario"} tamano="sm" onClick={(e) => a.principal!.alPulsar(e)}
            disabled={a.principal.disabled} title={a.principal.title}>
            {a.principal.etiqueta}
          </Boton>
        )}
        {(menu.length > 0 || verCaso) && (
          <Menu trigger={({ abierto, alternar }) => (
            <Boton variante="sutil" tamano="sm" aria-label="Más acciones" aria-haspopup="menu" aria-expanded={abierto} onClick={alternar}>
              <span aria-hidden>⋯</span>
            </Boton>
          )}>
            {verCaso && <MenuItem onClick={verCaso}>Ver el caso completo</MenuItem>}
            {menu.map((m, i) => m === "separador"
              ? <div key={i} role="separator" className="my-1 border-t border-sand" />
              : <MenuItem key={i} onClick={() => m.alPulsar()} variante={m.variante === "peligro" ? "peligro" : "normal"}>{m.etiqueta}</MenuItem>)}
          </Menu>
        )}
      </>
    );
  }

  const encabezados = (a: string, b: string, c: string, d: string): Encabezado[] => [
    { texto: "Persona" }, { texto: "Sede", secundaria: true }, { texto: a }, { texto: b }, { texto: c }, { texto: d, derecha: true },
  ];

  // Una función que devuelve celdas, no un componente: un componente definido
  // dentro de la página se volvería a montar entero en cada render.
  function celdaPersona(id: string, nombre: string, sede: string, alAbrir: (e: MouseEvent<HTMLElement>) => void, cesada = false) {
    return (
      <>
        <Celda>
          <button type="button" onClick={alAbrir} data-persona={id}
            className="text-left font-medium text-tinta underline decoration-sand decoration-2 underline-offset-4 hover:decoration-taupe">
            {nombre}
          </button>
          {cesada && <Insignia variante="advertencia" tamano="sm" className="ml-2">cesó</Insignia>}
          {sede && <span className="text-xs text-taupe lg:hidden"> · {sede}</span>}
        </Celda>
        <Celda secundaria><span className="hidden text-taupe lg:inline">{sede || "—"}</span></Celda>
      </>
    );
  }

  // ── El caso abierto ────────────────────────────────────────────────────
  const docAbierto = caso?.tipo === "documento" ? docs.find((d) => d.id === caso.id) ?? null : null;
  const tardAbierta = caso?.tipo === "tardanza" ? tardanzas.find((t) => t.persona_id === caso.personaId) ?? null : null;
  const faltaAbierta = caso?.tipo === "falta" ? faltas.find((f) => f.persona_id === caso.personaId) ?? null : null;
  const deteccionAbierta = caso && caso.tipo !== "documento" ? detecciones.find((x) => x.clave === `${caso.tipo === "tardanza" ? "tard" : "falta"}-${caso.personaId}`) ?? null : null;
  const personaAbierta = docAbierto?.persona_id ?? (caso && caso.tipo !== "documento" ? caso.personaId : null);

  let accionesPanel: ReactNode = null;
  if (docAbierto) {
    accionesPanel = <div className="flex flex-wrap items-center gap-2">{pintarAcciones(accionesDeDocumento(docAbierto))}</div>;
  } else if (caso && caso.tipo !== "documento") {
    const s = deteccionAbierta?.situacion;
    const tipo = caso.tipo;
    const pid = caso.personaId;
    accionesPanel = (
      <div className="flex flex-wrap items-center gap-3">
        <Boton variante="primario" onClick={() => void generar(tipo, pid)} disabled={!s?.generable} cargando={ocupado === pid}>
          Generar borrador
        </Boton>
        <p className="min-w-0 flex-1 basis-60 text-xs text-taupe">
          {s?.generable
            ? "Crea un borrador sin número con estas pruebas. No comunica ni firma nada todavía."
            : s?.porQueNo ?? "Esta persona ya no aparece en la cuenta."}
        </p>
      </div>
    );
  }

  let editoresPanel: ReactNode = null;
  if (docAbierto?.estado === "borrador" && docAbierto.nivel === "despido") {
    const d = docAbierto;
    editoresPanel = (
      // El art. 32 de la LPCL exige que la carta diga la causa Y la fecha de
      // cese. Se fija en el borrador: después de firmar ya no se edita.
      <label className="flex flex-wrap items-center gap-2 text-taupe">
        Fecha de cese (art. 32):
        <input key={`cese-${d.id}-${d.fecha_cese}`} type="date" defaultValue={d.fecha_cese ?? ""}
          onBlur={(e) => void guardarFechaCese(d, e.target.value)}
          className="rounded-control border border-sand bg-hueso px-2 py-1 text-tinta" />
        {!d.fecha_cese && <span className="text-rojo-profundo">sin fecha, la carta saldría incompleta</span>}
      </label>
    );
  } else if (docAbierto?.estado === "borrador" && docAbierto.nivel === "suspension") {
    const d = docAbierto;
    const r = rangoSuspension(d);
    const fuera = d.suspension_dias !== null && (d.suspension_dias < r.min || d.suspension_dias > r.max);
    editoresPanel = (
      <div className="grid gap-2 rounded-control border border-sand p-3 text-taupe">
        <label className="flex flex-wrap items-center gap-2">
          Días de suspensión:
          {/* Un `max` de HTML no impide nada: el candado está en la base (0294).
              `onWheel` con blur porque la rueda del mouse cambia el número al
              hacer scroll — una forma de mover días de sueldo sin querer. */}
          <input key={`dias-${d.id}-${d.suspension_dias}`} type="number" min={r.min} max={r.max} defaultValue={d.suspension_dias ?? r.min}
            onWheel={(e) => e.currentTarget.blur()}
            onBlur={(e) => void guardarDias(d, Number(e.target.value))}
            className={cx("w-16 rounded-control border bg-hueso px-2 py-1 text-tinta", fuera ? "border-rojo text-rojo-profundo" : "border-sand")} />
          <span className={fuera ? "text-rojo-profundo" : undefined}>
            {r.min === r.max ? `solo ${r.min}` : `de ${r.min} a ${r.max}`}
            {r.previa !== null
              ? ` · su anterior fue de ${r.previa}, y el numeral 19.2 d) pide que esta sea mayor`
              : d.tipo_causal === "tardanza" ? " · es la primera, y el numeral 19.2 c) la topa en dos" : " · numeral 54.5"}
          </span>
        </label>
        {fuera && <span className="text-rojo-profundo">Los {d.suspension_dias} de ahora quedan fuera de ese rango: corrígelo antes de firmar.</span>}
        <label className="flex flex-wrap items-center gap-2">
          Desde:
          <input key={`desde-${d.id}-${d.suspension_desde}`} type="date" defaultValue={d.suspension_desde ?? ""} min={hoyLima()}
            onBlur={(e) => e.target.value && e.target.value !== d.suspension_desde && void guardarDias(d, d.suspension_dias ?? 1, e.target.value)}
            className="rounded-control border border-sand bg-hueso px-2 py-1 text-tinta" />
          {/* Las fechas una por una cuando se saltan un descanso. */}
          {d.suspension_fechas?.length
            ? <span className="tabular-nums">{d.suspension_fechas.map(fechaCorta).join(", ")}</span>
            : d.suspension_desde && <span>del {fechaCorta(d.suspension_desde)}{d.suspension_hasta ? ` al ${fechaCorta(d.suspension_hasta)}` : ""}</span>}
        </label>
        {(d.suspension_fechas?.[0] ?? d.suspension_desde ?? "9999-12-31") <= hoyLima() && (
          <span className="text-rojo-profundo">Esos días ya empezaron: si firmas hoy, la sanción no tendría efecto real.</span>
        )}
      </div>
    );
  }

  const conteo = {
    revision: alcanzaron.length,
    borradores: borradores.length,
    entregar: porEntregar.length,
    historial: historial.length,
  };

  // ── Render ─────────────────────────────────────────────────────────────
  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6">
        <CabeceraPagina
          titulo="Disciplina"
          descripcion={
            <>
              Revisa incidencias que alcanzan umbrales y gestiona su trazabilidad.
              <span className="mt-1 flex flex-wrap items-baseline gap-x-3 gap-y-0.5">
                <span><span aria-hidden>ⓘ </span>El sistema detecta condiciones y prepara borradores; la decisión la toma una persona.</span>
                <Boton variante="enlace" className="text-sm text-tinta" onClick={() => setVerReglas(true)}>Ver reglas y umbrales</Boton>
              </span>
            </>
          }
        />

        {/* Filtros */}
        <div className="-mt-4 mb-5 flex flex-wrap items-end gap-3">
          <label htmlFor="f-mes" className="grid gap-1 text-xs text-taupe">
            Mes de tardanzas
            <select id="f-mes" value={mesTard} onChange={(e) => setMesTard(e.target.value)}
              className="rounded-control border border-sand bg-hueso px-2.5 py-1.5 text-sm text-tinta">
              {mesesRecientesLima().map((m) => (
                <option key={m} value={m}>
                  {nombreDelMesLimaTitulo(m)} {m.slice(0, 4)}{m === primeroDeMesLima() ? " · en curso" : ""}
                </option>
              ))}
            </select>
          </label>
          <label htmlFor="f-persona" className="grid min-w-0 flex-1 basis-56 gap-1 text-xs text-taupe">
            Persona
            <input id="f-persona" type="search" value={busqueda} onChange={(e) => setBusqueda(e.target.value)}
              placeholder="Buscar por nombre"
              className="rounded-control border border-sand bg-hueso px-2.5 py-1.5 text-sm text-tinta placeholder:text-taupe" />
          </label>
          {puedeVerTodasLasSedes(rol) && sedes.length > 1 && (
            <label htmlFor="f-sede" className="grid gap-1 text-xs text-taupe">
              Sede
              <select id="f-sede" value={sedeFiltro} onChange={(e) => setSedeFiltro(e.target.value)}
                className="rounded-control border border-sand bg-hueso px-2.5 py-1.5 text-sm text-tinta">
                <option value="">Todas</option>
                {sedes.map((s) => <option key={s} value={s}>{s}</option>)}
              </select>
            </label>
          )}
        </div>

        {/* Pestañas */}
        {/* En el celular las cuatro van en 2 × 2 y no en una franja que se
            desliza: «Por entregar» y «Historial» quedaban fuera de la pantalla,
            y una pestaña con contador que no se ve es un aviso que no llega. */}
        <div role="tablist" aria-label="Etapas de Disciplina" className="mb-5 grid grid-cols-2 gap-x-1 border-b border-sand sm:flex sm:gap-1">
          <TabBtn valor="revision" tab={tab} setTab={setTab} cuenta={conteo.revision} urgente>Requieren revisión</TabBtn>
          <TabBtn valor="borradores" tab={tab} setTab={setTab} cuenta={conteo.borradores}>Borradores</TabBtn>
          <TabBtn valor="entregar" tab={tab} setTab={setTab} cuenta={conteo.entregar} urgente>Por entregar</TabBtn>
          <TabBtn valor="historial" tab={tab} setTab={setTab} cuenta={conteo.historial}>Historial</TabBtn>
        </div>

        {cargando && docs.length === 0 && tardanzas.length === 0 ? (
          <Cargando />
        ) : (
          <div role="tabpanel" id={`panel-${tab}`} aria-labelledby={`tab-${tab}`}>
            {/* ── Requieren revisión ─────────────────────────────────── */}
            {tab === "revision" && (
              <>
                {falloTard && <FalloLectura que="la cuenta de tardanzas" />}
                {falloFaltas && <FalloLectura que="la cuenta de faltas" />}
                <Grupo titulo="Alcanzaron un umbral" detalle="Revisar el caso no genera nada: el borrador se prepara desde ahí.">
                  {alcanzaron.length === 0 ? (
                    <Vacio>
                      {hayFiltro
                        ? "Nadie con estos filtros."
                        : `Nadie alcanza su umbral de tardanzas en ${nombreMes} ni tiene faltas por revisar.`}
                    </Vacio>
                  ) : (
                    <ListaCasos etiqueta="Alcanzaron un umbral" plantilla={PLANTILLA} encabezados={encabezados("Motivo", "Progreso", "Situación", "")}>
                      {alcanzaron.map((x) => {
                        const abrir = (e?: MouseEvent<HTMLElement>) => abrirCaso({ tipo: x.tipo, personaId: x.personaId }, e);
                        return (
                          <FilaCaso key={x.clave} id={x.clave} plantilla={PLANTILLA} resaltada={resaltado === x.clave}>
                            {celdaPersona(x.personaId, x.nombre, x.sede, abrir)}
                            <Celda etiqueta="Motivo">{x.motivo}</Celda>
                            <Celda etiqueta="Progreso">{x.progreso}</Celda>
                            <Celda etiqueta="Situación"><Insignia variante={x.situacion.variante}>{x.situacion.etiqueta}</Insignia></Celda>
                            <Celda acciones>
                              <Boton variante={x.situacion.generable ? "primario" : "secundario"} tamano="sm" onClick={abrir}>Revisar caso</Boton>
                            </Celda>
                          </FilaCaso>
                        );
                      })}
                    </ListaCasos>
                  )}
                </Grupo>
                {(seguimiento.length > 0 || !hayFiltro) && (
                  <Grupo titulo="En seguimiento" detalle="Cerca del umbral o a la espera de otra decisión. No admiten documento.">
                    {seguimiento.length === 0 ? (
                      <Vacio>Nadie cerca de su umbral en {nombreMes}.</Vacio>
                    ) : (
                      <ListaCasos etiqueta="En seguimiento" plantilla={PLANTILLA} encabezados={encabezados("Motivo", "Progreso", "Situación", "")}>
                        {seguimiento.map((x) => {
                          const abrir = (e?: MouseEvent<HTMLElement>) => abrirCaso({ tipo: x.tipo, personaId: x.personaId }, e);
                          return (
                            <FilaCaso key={x.clave} id={x.clave} plantilla={PLANTILLA} resaltada={resaltado === x.clave} atenuada>
                              {celdaPersona(x.personaId, x.nombre, x.sede, abrir)}
                              <Celda etiqueta="Motivo">{x.motivo}</Celda>
                              <Celda etiqueta="Progreso">{x.progreso}</Celda>
                              <Celda etiqueta="Situación"><Insignia variante={x.situacion.variante}>{x.situacion.etiqueta}</Insignia></Celda>
                              <Celda acciones><Boton variante="sutil" tamano="sm" onClick={abrir}>Ver detalle</Boton></Celda>
                            </FilaCaso>
                          );
                        })}
                      </ListaCasos>
                    )}
                  </Grupo>
                )}
              </>
            )}

            {/* ── Borradores ─────────────────────────────────────────── */}
            {tab === "borradores" && (
              <>
                {falloDocs && <FalloLectura que="el legajo" />}
                {borradores.length === 0 ? (
                  <Vacio>{hayFiltro ? "No hay borradores con estos filtros." : "No hay borradores pendientes."}</Vacio>
                ) : (
                  <ListaCasos etiqueta="Borradores" plantilla={PLANTILLA} encabezados={encabezados("Documento", "Paso", "Situación", "")}>
                    {borradores.map((d) => {
                      const info = infoDe(d.persona_id);
                      const etapa = etapaDelBorrador(d, exigeDescargo);
                      const ev = evidencias.get(d.id);
                      const abrir = (e?: MouseEvent<HTMLElement>) => abrirCaso({ tipo: "documento", id: d.id }, e);
                      return (
                        <FilaCaso key={d.id} plantilla={PLANTILLA}>
                          {celdaPersona(d.persona_id, nombreDe(d.persona_id), info?.sede ?? "", abrir, info?.estado === "inactivo")}
                          <Celda etiqueta="Documento">{CAUSAL_LABEL[d.tipo_causal] ?? d.tipo_causal} · {nivelCorto(d.nivel)}</Celda>
                          <Celda etiqueta="Paso">
                            {exigeDescargo && esGradual(d.nivel) ? <PasosBorrador etapa={etapa} /> : <span className="text-xs">{ETAPA_LABEL.firmar}</span>}
                          </Celda>
                          <Celda etiqueta="Situación">
                            {ev && ev.noCuentan > 0
                              ? <Insignia variante="alerta">{ev.noCuentan} día{ev.noCuentan === 1 ? "" : "s"} ya no cuenta{ev.noCuentan === 1 ? "" : "n"}</Insignia>
                              : sinConstancia.has(d.persona_id) && d.nivel !== "imputacion" && d.nivel !== "despido"
                                ? <Insignia variante="alerta">Sin constancia del RIT</Insignia>
                                : <span className="text-xs text-taupe">Generado el {fechaCorta(fechaLima(d.creado_at))}</span>}
                          </Celda>
                          <Celda acciones>{pintarAcciones(accionesDeDocumento(d), () => abrirCaso({ tipo: "documento", id: d.id }))}</Celda>
                        </FilaCaso>
                      );
                    })}
                  </ListaCasos>
                )}
              </>
            )}

            {/* ── Por entregar ───────────────────────────────────────── */}
            {tab === "entregar" && (
              <>
                {falloDocs && <FalloLectura que="el legajo" />}
                <Grupo titulo="Firmados sin entregar" detalle="Un documento firmado y no entregado todavía no produce efecto (56.2).">
                  {firmados.length === 0 ? (
                    <Vacio>{hayFiltro ? "Ninguno con estos filtros." : "No hay documentos firmados pendientes de entrega."}</Vacio>
                  ) : (
                    <ListaCasos etiqueta="Firmados sin entregar" plantilla={PLANTILLA} encabezados={encabezados("Documento", "Firmado", "Situación", "")}>
                      {firmados.map((d) => {
                        const info = infoDe(d.persona_id);
                        const cesada = info?.estado === "inactivo";
                        const ev = evidencias.get(d.id);
                        const abrir = (e?: MouseEvent<HTMLElement>) => abrirCaso({ tipo: "documento", id: d.id }, e);
                        return (
                          <FilaCaso key={d.id} plantilla={PLANTILLA}>
                            {celdaPersona(d.persona_id, nombreDe(d.persona_id), info?.sede ?? "", abrir)}
                            <Celda etiqueta="Documento"><span className="tabular-nums">{d.correlativo}</span> · {nivelCorto(d.nivel)}</Celda>
                            <Celda etiqueta="Firmado"><span className="text-xs tabular-nums">{d.firmado_at ? selloLima(d.firmado_at) : "—"}</span></Celda>
                            <Celda etiqueta="Situación">
                              {cesada
                                ? <Insignia variante="advertencia">Cesó{info?.fechaCese ? ` el ${fechaCorta(info.fechaCese)}` : ""}</Insignia>
                                : ev && ev.noCuentan > 0
                                  ? <Insignia variante="alerta">Cita días que ya no cuentan</Insignia>
                                  : <Insignia variante="informativo">Por entregar</Insignia>}
                            </Celda>
                            <Celda acciones>{pintarAcciones(accionesDeDocumento(d), () => abrirCaso({ tipo: "documento", id: d.id }))}</Celda>
                          </FilaCaso>
                        );
                      })}
                    </ListaCasos>
                  )}
                </Grupo>
                {entregadosPendientes.length > 0 && (
                  <Grupo titulo="Entregados que aún piden algo" detalle="Pasan al historial cuando tengan el cargo archivado y, si es imputación, la decisión.">
                    <ListaCasos etiqueta="Entregados que aún piden algo" plantilla={PLANTILLA} encabezados={encabezados("Documento", "Entregado", "Falta", "")}>
                      {entregadosPendientes.map((d) => {
                        const info = infoDe(d.persona_id);
                        const pend = pendientesDeEntregado(d, adjuntos.get(d.id) ?? []);
                        const abrir = (e?: MouseEvent<HTMLElement>) => abrirCaso({ tipo: "documento", id: d.id }, e);
                        return (
                          <FilaCaso key={d.id} plantilla={PLANTILLA}>
                            {celdaPersona(d.persona_id, nombreDe(d.persona_id), info?.sede ?? "", abrir, info?.estado === "inactivo")}
                            <Celda etiqueta="Documento"><span className="tabular-nums">{d.correlativo}</span> · {nivelCorto(d.nivel)}</Celda>
                            <Celda etiqueta="Entregado">
                              <span className="text-xs tabular-nums">
                                {d.entregado_at ? selloLima(d.entregado_at) : "—"}
                                {d.medio_entrega && ` · ${MEDIO_ENTREGA[d.medio_entrega] ?? d.medio_entrega}`}
                              </span>
                            </Celda>
                            <Celda etiqueta="Falta">
                              <span className="inline-flex flex-wrap gap-1.5">
                                {pend.includes("cargo") && <Insignia variante="advertencia">El cargo firmado</Insignia>}
                                {pend.includes("resolver") && <Insignia variante="alerta">Registrar la decisión</Insignia>}
                              </span>
                            </Celda>
                            <Celda acciones>{pintarAcciones(accionesDeDocumento(d), () => abrirCaso({ tipo: "documento", id: d.id }))}</Celda>
                          </FilaCaso>
                        );
                      })}
                    </ListaCasos>
                  </Grupo>
                )}
              </>
            )}

            {/* ── Historial ──────────────────────────────────────────── */}
            {tab === "historial" && (
              <>
                {falloDocs && <FalloLectura que="el legajo" />}
                {historial.length === 0 ? (
                  <Vacio>{hayFiltro ? "Nada en el historial con estos filtros." : "Todavía no hay documentos cerrados."}</Vacio>
                ) : (
                  <ListaCasos etiqueta="Historial" plantilla={PLANTILLA} encabezados={encabezados("Documento", "Desenlace", "Estado", "")}>
                    {historial.map((d) => {
                      const info = infoDe(d.persona_id);
                      const cierre = eventosDeObservacion(d.observacion).filter((e) => e.tipo === "anulado" || e.tipo === "cerrado_sin_entrega").pop();
                      const abrir = (e?: MouseEvent<HTMLElement>) => abrirCaso({ tipo: "documento", id: d.id }, e);
                      return (
                        <FilaCaso key={d.id} plantilla={PLANTILLA}>
                          {celdaPersona(d.persona_id, nombreDe(d.persona_id), info?.sede ?? "", abrir)}
                          <Celda etiqueta="Documento">
                            <span className="tabular-nums">{d.correlativo ?? "sin número"}</span> · {CAUSAL_LABEL[d.tipo_causal] ?? d.tipo_causal} · {nivelCorto(d.nivel)}
                          </Celda>
                          <Celda etiqueta="Desenlace">
                            <span className="text-xs text-taupe">
                              {d.estado === "entregado"
                                ? `Entregado ${d.entregado_at ? fechaCorta(fechaLima(d.entregado_at)) : ""}${d.resuelto_at ? ` · ${d.resuelto_resultado === "despido" ? "resuelto con despido" : "archivado sin sancionar"}` : ""}`
                                : cierre
                                  ? `${cierre.fecha ? fechaCorta(cierre.fecha) : ""} · ${cierre.texto}`
                                  : "—"}
                            </span>
                          </Celda>
                          <Celda etiqueta="Estado">
                            <Insignia variante={ESTADO_DOCUMENTO[d.estado]?.variante ?? "neutral"} atenuada={d.estado !== "entregado"}>
                              {ESTADO_DOCUMENTO[d.estado]?.texto ?? d.estado}
                            </Insignia>
                          </Celda>
                          <Celda acciones>{pintarAcciones(accionesDeDocumento(d), () => abrirCaso({ tipo: "documento", id: d.id }))}</Celda>
                        </FilaCaso>
                      );
                    })}
                  </ListaCasos>
                )}
              </>
            )}
          </div>
        )}

        <PanelCaso
          caso={caso}
          onCerrar={() => setCaso(null)}
          volverElFocoA={disparador}
          bloqueado={modalAbierto}
          supabase={supabase}
          docs={docs}
          adjuntos={adjuntos}
          personas={personas}
          tardanza={tardAbierta}
          falta={faltaAbierta}
          situacion={deteccionAbierta?.situacion ?? null}
          mesTard={mesTard}
          nombresAusencia={nombresAusencia}
          evidenciaPrevia={docAbierto ? evidencias.get(docAbierto.id) : undefined}
          sinConstancia={personaAbierta ? sinConstancia.get(personaAbierta) ?? null : null}
          exigeDescargo={exigeDescargo}
          puedeAnular={puedeAnular}
          acciones={accionesPanel}
          editores={editoresPanel}
          onVerPapel={(path) => void verAdjunto(path)}
        />

        {/* ── Diálogos ───────────────────────────────────────────────────
            Cada uno solo pide confirmación o un texto; la llamada de verdad
            vive en su «confirmar…», nunca en el botón que abre el Modal. */}

        <Modal abierto={verReglas} onCerrar={() => setVerReglas(false)} titulo="Reglas y umbrales" ancho="lg">
          <div className="grid gap-4 text-sm">
            <p className="text-taupe">Lo que el sistema mira para detectar. Detectar no es sancionar: cada documento lo revisa y firma una persona.</p>
            <dl className="grid gap-3">
              {[
                ["Tardanzas", "En un mismo mes calendario: 3 sin antecedente vigente → amonestación escrita · 2 con una amonestación vigente → primera suspensión · 1 con una suspensión vigente → segunda suspensión, mayor que la primera · 1 tardanza nueva tras la segunda suspensión → imputación de cargos. Cada fila dice el paso que le toca a esa persona.", "RIT 19.2"],
                ["Sin medir", "Un día con más de tres horas de diferencia no suma: casi siempre es un turno mal cargado. Se revisa a mano con la persona y con su líder de equipo.", "RIT 17.5"],
                ["Mes cerrado", "Se puede documentar un mes concluido, pero una demora injustificada equivale a condonación. Del mes más viejo al más nuevo.", "RIT 19.4 · 52 · 56.6"],
                ["Faltas", "Día programado sin marca ni justificación. Umbral grave: 4 seguidas · 6 en 30 días · 16 en 180 días.", "LPCL 25 h)"],
                ["Antecedente", "Solo cuenta lo entregado en los doce meses previos. Firmado y no entregado no agrava.", "RIT 56.1 · 56.2"],
                ["Antes de firmar", "Amonestación y suspensión: comunicar los cargos por escrito y esperar dos días hábiles de descargo; después, valorarlo.", "RIT 55.2 · 19.3"],
                ["Suspensión", "Tope de tres días laborables. La primera por tardanzas, de uno a dos días; la segunda, de dos a tres y siempre mayor que la primera.", "RIT 54.5 · 19.2 c) d)"],
                ["Incidencias", "Cuenta tardanzas sobre 30 días corridos, así que puede mostrar un número mayor que acá. El que gobierna el documento es el del mes calendario.", ""],
              ].map(([t, x, ref]) => (
                <div key={t} className="grid gap-0.5 border-t border-sand pt-2 sm:grid-cols-[8rem_1fr] sm:gap-4">
                  <dt className="font-medium text-tinta">{t}</dt>
                  <dd className="text-taupe">{x}{ref && <span className="block text-xs">{ref}</span>}</dd>
                </div>
              ))}
            </dl>
            <div className="flex justify-end">
              <Boton variante="primario" onClick={() => setVerReglas(false)}>Entendido</Boton>
            </div>
          </div>
        </Modal>

        <Modal abierto={confirmandoCargos !== null} onCerrar={() => setConfirmandoCargos(null)}
          titulo="Comunicar los cargos" bloqueado={ocupado === confirmandoCargos?.id}>
          {confirmandoCargos && (
            <>
              <p className="mb-2 text-sm text-taupe">
                ¿Comunicar los cargos a <strong className="text-tinta">{nombreDe(confirmandoCargos.persona_id)}</strong>?
              </p>
              <p className="mb-2 text-sm text-taupe">
                Se abre el plazo de dos días hábiles para su descargo, y hasta que venza no se podrá firmar.{" "}
                <strong className="text-tinta">El plazo no se reabre.</strong>
              </p>
              <p className="mb-4 text-sm text-taupe">
                Antes de continuar: entrégale por escrito los hechos con sus fechas, la norma que se le imputa y el
                detalle de la medición. El sistema guarda la fecha; el documento lo entregas tú.
              </p>
              <div className="flex justify-end gap-3">
                <Boton variante="secundario" onClick={() => setConfirmandoCargos(null)} disabled={ocupado === confirmandoCargos.id}>Cancelar</Boton>
                <Boton variante="primario" onClick={() => void confirmarComunicarCargos(confirmandoCargos)} cargando={ocupado === confirmandoCargos.id}>
                  Comunicar cargos
                </Boton>
              </div>
            </>
          )}
        </Modal>

        <Modal abierto={declarando !== null} onCerrar={() => setDeclarando(null)}
          titulo="Registrar una comunicación que ya ocurrió" bloqueado={ocupado === declarando?.id}>
          {declarando && (
            <div className="grid gap-3">
              <p className="text-sm text-taupe">
                Desde ese día corren los dos días hábiles de descargo; si todavía no han pasado, el documento seguirá sin
                poder firmarse. Queda escrito con tu nombre y la fecha de hoy.
              </p>
              <div className="w-44">
                <Campo etiqueta="Día de la comunicación" type="date" value={fechaCargos} max={hoyLima()}
                  onChange={(e) => setFechaCargos(e.target.value)} />
              </div>
              <label htmlFor="constancia" className="grid gap-1 text-sm">
                Cómo consta (obligatorio)
                <AreaTexto id="constancia" value={constanciaTexto} onChange={(e) => setConstanciaTexto(e.target.value)} rows={3}
                  placeholder="ej. se lo comuniqué en persona en la oficina de la sede, delante de su líder de equipo" />
              </label>
              <p className="text-xs text-taupe">Quién se la hizo, dónde y quién más estaba. Si fue verbal, dilo: es más débil que un cargo firmado.</p>
              <div className="flex justify-end gap-3">
                <Boton variante="secundario" onClick={() => setDeclarando(null)} disabled={ocupado === declarando.id}>Cancelar</Boton>
                <Boton variante="primario" onClick={() => void confirmarDeclararCargos(declarando)} cargando={ocupado === declarando.id}>Registrar</Boton>
              </div>
            </div>
          )}
        </Modal>

        <Modal abierto={valorando !== null} onCerrar={() => setValorando(null)} titulo="Valorar el descargo" bloqueado={ocupado === valorando?.d.id}>
          {valorando && (
            <div className="grid gap-3">
              <p className="text-sm text-taupe">Queda escrito en el documento (art. 19.3 del RIT), también si no presentó ninguno.</p>
              <fieldset className="grid gap-1.5">
                <legend className="sr-only">Cómo se valora</legend>
                {Object.entries(ETIQUETA_DESCARGO).map(([valor, etiqueta]) => (
                  <label key={valor} htmlFor={`valora-${valor}`} className="flex items-center gap-2 text-sm">
                    <input id={`valora-${valor}`} type="radio" name="valoracion" value={valor} checked={valorando.acogido === valor}
                      onChange={() => setValorando({ ...valorando, acogido: valor })} />
                    {etiqueta}
                  </label>
                ))}
              </fieldset>
              {(valorando.acogido === "parcial" || valorando.acogido === "no") && (
                <label htmlFor="valoracion-texto" className="grid gap-1 text-sm">
                  {valorando.acogido === "no" ? "Por qué no se acoge (obligatorio)" : "Qué parte se acoge y qué parte no (obligatorio)"}
                  <AreaTexto id="valoracion-texto" value={valoracionTexto} onChange={(e) => setValoracionTexto(e.target.value)} rows={3} />
                </label>
              )}
              {valorando.acogido === "total" && (
                <p className="text-xs text-taupe">Si se acoge por completo, lo normal es que ya no corresponda sancionar: después, anula el borrador.</p>
              )}
              <div className="flex justify-end gap-3">
                <Boton variante="secundario" onClick={() => setValorando(null)} disabled={ocupado === valorando.d.id}>Cancelar</Boton>
                <Boton variante="primario" onClick={() => void confirmarValorarDescargo()} cargando={ocupado === valorando.d.id}>Guardar valoración</Boton>
              </div>
            </div>
          )}
        </Modal>

        <Modal abierto={firmando !== null} onCerrar={() => setFirmando(null)} titulo="Firmar este documento" bloqueado={ocupado === firmando}>
          {firmando && (() => {
            const lista = firmantes[firmando] ?? [];
            const elegido = lista.find((x) => x.persona_id === firmanteDe(firmando)) ?? null;
            return (
              <div className="grid gap-3">
                {lista.length > 0 && (
                  <label htmlFor="firmante" className="grid gap-1 text-sm">
                    Quién firma
                    <select id="firmante" value={firmanteDe(firmando)}
                      onChange={(e) => setFirmanteElegido((m) => ({ ...m, [firmando]: e.target.value }))}
                      className="rounded-control border border-sand bg-hueso px-2.5 py-1.5 text-sm text-tinta">
                      {lista.map((f) => (
                        <option key={f.persona_id} value={f.persona_id}>
                          {f.nombre} · {f.cargo}{f.tiene_firma ? "" : " (sin firma escaneada)"}
                        </option>
                      ))}
                    </select>
                  </label>
                )}
                {/* El cargo va en el aviso: es lo que se imprime en el documento. */}
                <p className="text-sm text-taupe">
                  {elegido
                    ? <>Se firmará como <strong className="text-tinta">{elegido.nombre}</strong> ({elegido.cargo}). </>
                    : null}
                  Le asigna su número oficial y deja de ser un borrador. Después podrás entregarlo o, si hizo falta, anularlo.
                </p>
                <div className="flex justify-end gap-3">
                  <Boton variante="secundario" onClick={() => setFirmando(null)} disabled={ocupado === firmando}>Cancelar</Boton>
                  <Boton variante="primario" onClick={() => void confirmarFirmar(firmando)} cargando={ocupado === firmando}>Firmar</Boton>
                </div>
              </div>
            );
          })()}
        </Modal>

        <Modal abierto={subiendoCargo !== null} onCerrar={() => setSubiendoCargo(null)}
          titulo={subiendoCargo ? (subiendoCargo.fechaMax ? "Registrar una entrega anterior al cese" : TITULO_PAPEL[subiendoCargo.tipo]) : ""}
          bloqueado={ocupado === subiendoCargo?.id}>
          {subiendoCargo && (() => {
            const doc = docs.find((x) => x.id === subiendoCargo.id);
            const pideFecha = doc?.estado === "firmado" && (subiendoCargo.tipo === "cargo_firmado" || subiendoCargo.tipo === "acta_negativa");
            return (
              <div className="grid gap-4">
                {subiendoCargo.fechaMax && (
                  <p className="rounded-control bg-ambar/15 px-3 py-2 text-sm text-ambar">
                    Solo si se le entregó antes de que cesara. Con esta fecha el documento cuenta como antecedente si la persona vuelve.
                  </p>
                )}
                <FormularioCargo
                  tipo={subiendoCargo.tipo}
                  pideFecha={pideFecha}
                  entregadoEl={doc?.entregado_at ? selloLima(doc.entregado_at) : null}
                  fecha={fechaEntrega} fechaMax={subiendoCargo.fechaMax}
                  nota={notaCargo} testigo={testigoCargo} progreso={progresoCargo}
                  alElegirArchivo={setArchivoCargo} alCambiarFecha={setFechaEntrega}
                  alCambiarNota={setNotaCargo} alCambiarTestigo={setTestigoCargo}
                />
                <div className="flex justify-end gap-3">
                  <Boton variante="secundario" onClick={() => setSubiendoCargo(null)} disabled={ocupado === subiendoCargo.id}>Cancelar</Boton>
                  <Boton variante="primario" onClick={() => void guardarCargo()} cargando={ocupado === subiendoCargo.id}>
                    {progresoCargo !== null ? `Subiendo… ${progresoCargo}%` : "Guardar"}
                  </Boton>
                </div>
              </div>
            );
          })()}
        </Modal>

        <Modal abierto={entregandoSinPapel !== null} onCerrar={() => setEntregandoSinPapel(null)}
          titulo="Entregar sin papel" bloqueado={ocupado === entregandoSinPapel?.id}>
          {entregandoSinPapel && (
            <div className="grid gap-3">
              <p className="text-sm text-taupe">
                Para una entrega por correo certificado o notarial cuyo cargo llega después. El documento queda entregado
                con la fecha de hoy y desde ahí corren los plazos. El cargo se sube después y no pisa esta fecha.
              </p>
              <label htmlFor="medio-entrega" className="grid gap-1 text-sm">
                Medio
                <select id="medio-entrega" value={medio} onChange={(e) => setMedio(e.target.value)}
                  className="rounded-control border border-sand bg-hueso px-2.5 py-1.5 text-sm text-tinta">
                  <option value="fisico">En mano</option>
                  {/* Nivel 4 no admite correo (0303): no se ofrece. */}
                  {entregandoSinPapel.nivel !== "imputacion" && entregandoSinPapel.nivel !== "despido" && <option value="correo">Por correo</option>}
                  <option value="notarial">Notarial</option>
                </select>
              </label>
              <div className="flex justify-end gap-3">
                <Boton variante="secundario" onClick={() => setEntregandoSinPapel(null)} disabled={ocupado === entregandoSinPapel.id}>Cancelar</Boton>
                <Boton variante="primario" onClick={() => void confirmarEntregar()} cargando={ocupado === entregandoSinPapel.id}>Marcar entregado</Boton>
              </div>
            </div>
          )}
        </Modal>

        <Modal abierto={resolviendo !== null} onCerrar={() => setResolviendo(null)} titulo="Registrar la decisión" bloqueado={ocupado === resolviendo?.d.id}>
          {resolviendo && (
            <div className="grid gap-3">
              <p className="text-sm text-taupe">Tras evaluar sus descargos. Esto solo ANOTA la decisión: no es anular.</p>
              <fieldset className="grid gap-1.5">
                <legend className="sr-only">Qué se resolvió</legend>
                {([["archivado", "Archivar sin sancionar"], ["despido", "Se resolvió con despido"]] as const).map(([v, t]) => (
                  <label key={v} htmlFor={`resuelve-${v}`} className="flex items-center gap-2 text-sm">
                    <input id={`resuelve-${v}`} type="radio" name="resolucion" value={v} checked={resolviendo.resultado === v}
                      onChange={() => setResolviendo({ ...resolviendo, resultado: v })} />
                    {t}
                  </label>
                ))}
              </fieldset>
              {resolviendo.resultado && (
                <p className="rounded-control bg-hueso px-3 py-2 text-sm text-taupe">
                  {resolviendo.resultado === "despido"
                    ? "La carta de despido se redacta, se firma y se entrega aparte."
                    : "El documento sigue entregado y sigue contando como antecedente doce meses."}
                </p>
              )}
              <label htmlFor="motivo-resolucion" className="grid gap-1 text-sm">
                Por qué (obligatorio)
                <AreaTexto id="motivo-resolucion" value={motivoResolucion} onChange={(e) => setMotivoResolucion(e.target.value)} rows={3} />
              </label>
              <div className="flex justify-end gap-3">
                <Boton variante="secundario" onClick={() => setResolviendo(null)} disabled={ocupado === resolviendo.d.id}>Cancelar</Boton>
                <Boton variante={resolviendo.resultado === "despido" ? "peligro" : "primario"} onClick={() => void confirmarResolver()} cargando={ocupado === resolviendo.d.id}>
                  Guardar decisión
                </Boton>
              </div>
            </div>
          )}
        </Modal>

        <Modal abierto={reabriendo !== null} onCerrar={() => setReabriendo(null)} titulo="Cambiar firmante" bloqueado={ocupado === reabriendo}>
          {reabriendo && (
            <>
              <p className="mb-4 text-sm text-taupe">
                El documento vuelve a borrador y <strong className="text-tinta">pierde su número oficial</strong>; al firmarlo
                de nuevo recibe uno nuevo. Solo se puede mientras no se haya entregado.
              </p>
              <div className="flex justify-end gap-3">
                <Boton variante="secundario" onClick={() => setReabriendo(null)} disabled={ocupado === reabriendo}>Cancelar</Boton>
                <Boton variante="primario" onClick={() => void confirmarReabrir(reabriendo)} cargando={ocupado === reabriendo}>Volver a borrador</Boton>
              </div>
            </>
          )}
        </Modal>

        <Modal abierto={anulando !== null} onCerrar={() => setAnulando(null)} titulo="Anular este documento" bloqueado={ocupado === anulando?.id}>
          {anulando && (
            <div className="grid gap-3">
              {anulando.entregado && (
                <p className="rounded-control border border-rojo/30 bg-rojo/[0.06] px-3 py-2 text-sm text-rojo-profundo">
                  Este documento YA SE ENTREGÓ y la persona lo tiene. Anularlo lo deja sin efecto y queda el rastro con tu
                  motivo, pero el sistema no puede avisarle: tendrás que comunicárselo tú por escrito.
                </p>
              )}
              <label htmlFor="motivo-anular" className="grid gap-1 text-sm">
                {anulando.entregado
                  ? "Por qué se anula — si fue un defecto del documento o una decisión de la empresa (obligatorio)"
                  : "Motivo de la anulación (obligatorio)"}
                <AreaTexto id="motivo-anular" value={motivoAnular} onChange={(e) => setMotivoAnular(e.target.value)} rows={3} />
              </label>
              <p className="text-xs text-taupe">Anular no es archivar: devuelve la escala al paso que de verdad tocaba.</p>
              <div className="flex justify-end gap-3">
                <Boton variante="secundario" onClick={() => setAnulando(null)} disabled={ocupado === anulando.id}>Cancelar</Boton>
                <Boton variante="peligro" onClick={() => void confirmarAnular()} cargando={ocupado === anulando.id}>Anular</Boton>
              </div>
            </div>
          )}
        </Modal>

        <Modal abierto={cerrandoSinEntrega !== null} onCerrar={() => setCerrandoSinEntrega(null)} titulo="Cerrar sin entrega" bloqueado={ocupado === cerrandoSinEntrega}>
          {cerrandoSinEntrega && (
            <div className="grid gap-3">
              <p className="rounded-control bg-hueso px-3 py-2 text-sm text-taupe">
                El documento pasa al historial como <strong className="text-tinta">cerrado sin entrega</strong>. No es anular:
                el documento sí era válido, solo que ya no tiene a quién notificarse. No cuenta como antecedente y ya no
                se podrá entregar.
              </p>
              <label htmlFor="motivo-cierre" className="grid gap-1 text-sm">
                Por qué no se le entregó (obligatorio)
                <AreaTexto id="motivo-cierre" value={motivoCierre} onChange={(e) => setMotivoCierre(e.target.value)} rows={3}
                  placeholder="ej. cesó antes de poder citarla; no se le entregó en su último día" />
              </label>
              <div className="flex justify-end gap-3">
                <Boton variante="secundario" onClick={() => setCerrandoSinEntrega(null)} disabled={ocupado === cerrandoSinEntrega}>Cancelar</Boton>
                <Boton variante="primario" onClick={() => void confirmarCerrarSinEntrega()} cargando={ocupado === cerrandoSinEntrega}>Cerrar sin entrega</Boton>
              </div>
            </div>
          )}
        </Modal>
      </main>
    </div>
  );
}
