"use client";

import { Fragment, Suspense, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { createAdminSupabaseClient, type ClienteCayla } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { Cargando } from "@/components/cargando";
import { useToast } from "@/components/toast";
import { mensajeDeError, type ErrorBase } from "@/lib/admin/mensaje-error";
import { subirArchivoConProgreso } from "@/lib/subir-archivo";
import { abrirArchivoFirmado } from "@/lib/abrir-archivo-firmado";
import { descargarCsv, generarCsv } from "@/lib/admin/csv";
import { diffLineas, type LineaDiff } from "@/lib/admin/diff-lineas";
import { ROLES_DO, TZ_LIMA, hoyLima } from "@cayla-dynamic/shared";
import { Documento } from "@/components/documento";
import { bloquesDe } from "@/lib/admin/markdown-documento";
import { Boton } from "@/components/ui/boton";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { AreaTexto } from "@/components/ui/area-texto";
import { Insignia } from "@/components/ui/insignia";
import { Modal } from "@/components/ui/modal";
import { AyudaPantalla } from "@/components/ui/ayuda-pantalla";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { ParaAtender } from "@/components/ui/para-atender";
import { Pestanas } from "@/components/ui/pestanas";
import { sobretituloDeHoy } from "@/lib/admin/sobretitulo";
import { EstadoVacio } from "@/components/ui/estado-vacio";
import { Fila, Tabla, TablaEncabezado, Th } from "@/components/ui/tabla";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";
import { Search, X } from "lucide-react";

// ============================================================================
// Normas — rediseño (2026-09-15, decidido con Felipe tras auditoría y
// prototipo probado). Este archivo reemplaza la lista continua de antes por
// una biblioteca con tabs: Vigentes (todos), y para DO además Versiones y
// Constancias — quien no gestiona ve en su lugar Mi historial.
//
// Las funciones SQL, el parser de markdown y el visor <Documento> NO cambian:
// esta es una reescritura de interfaz sobre el mismo contrato de datos.
// ============================================================================

/** `fn_restaurar_documento` es de la migración 0460, recién escrita: el
 *  cliente tipado (`ClienteCayla`) solo deja llamar funciones que ya están en
 *  `packages/database/src/types.ts`, y ese archivo se regenera introspectando
 *  el Postgres LOCAL que comparten las ~10 sesiones de este repositorio — hoy
 *  va detrás de esta rama (le faltan tablas y columnas de migraciones ya
 *  fusionadas), así que regenerarlo ahora habría borrado tipos legítimos en
 *  vez de sumar uno nuevo. Se llama aparte, con la forma mínima de su
 *  respuesta, hasta que alguien regenere `types.ts` con la base al día. */
async function restaurarDocumento(
  supabase: ClienteCayla,
  documentoId: string,
): Promise<{ data: number | null; error: ErrorBase | null }> {
  const cliente = supabase as unknown as {
    rpc(
      fn: "fn_restaurar_documento",
      args: { p_documento_id: string },
    ): PromiseLike<{ data: number | null; error: ErrorBase | null }>;
  };
  return cliente.rpc("fn_restaurar_documento", { p_documento_id: documentoId });
}

type TabId = "vigentes" | "versiones" | "constancias" | "historial";

interface Doc {
  documento_id: string;
  tipo: string;
  tipo_nombre: string;
  version: number;
  etiqueta_version: string | null;
  titulo: string;
  documento: string;
  vigente_desde: string;
  publicado_at: string;
  requiere_acuse: boolean;
  mi_acuse_at: string | null;
  total_acuses: number;
  poblacion: number;
}

interface Tipo {
  codigo: string;
  nombre: string;
  requiere_acuse: boolean;
  orden: number;
}

interface FilaAcuse {
  persona_id: string;
  nombre: string;
  sede: string;
  tiene_cuenta: boolean;
  acusado_at: string | null;
  via: string | null;
  storage_path: string | null;
}

/** Una fila cruda de `documentos_institucionales`, para el tab Versiones —
 *  SIN el texto completo: esa columna solo se pide al abrir una versión en
 *  concreto (ver `documento`, abajo), no para listar. */
interface VersionRow {
  id: string;
  tipo: string;
  version: number;
  etiqueta_version: string | null;
  titulo: string;
  vigente_desde: string;
  publicado_at: string;
  notas: string | null;
}

/** El documento abierto en el modal — vigente (viene de `docs`, ya trae todo)
 *  o histórico (se pide aparte, con su texto). */
interface ModalDoc {
  documento_id: string;
  tipo: string;
  tipo_nombre: string;
  version: number;
  etiqueta_version: string | null;
  titulo: string;
  documento: string;
  vigente_desde: string;
  publicado_at: string;
  esVigente: boolean;
  /** Solo tienen sentido para la vigente: acusar una versión histórica no
   *  significa nada en el modelo de datos (la constancia es de LA vigente que
   *  se leyó), así que quedan en su valor neutro para una histórica y el
   *  bloque de "dejar constancia" no se muestra. */
  requiere_acuse: boolean;
  mi_acuse_at: string | null;
  total_acuses: number;
  poblacion: number;
}

interface MiConstancia {
  documento_id: string;
  titulo: string;
  tipo_nombre: string;
  etiqueta_version: string | null;
  version: number;
  acusado_at: string;
  via: string;
}

/**
 * Qué es principal y qué es anexo. No es cosmética: el artículo 47 del
 * Reglamento dice que los complementarios «tienen finalidad informativa» y
 * que «en caso de discrepancia prevalece este Reglamento». La lista vive acá
 * y no en la base a propósito: es una decisión de jerarquía normativa, no un
 * dato que DO deba poder cambiar desde una pantalla. Hoy solo `rit` — el día
 * que el RISST se declare principal, se agrega aquí.
 */
const PRINCIPALES = ["rit"];

/** Un reglamento de 61 artículos pesa cerca de 300 KB. El tope es generoso a
 *  propósito, pero existe: sin él, un archivo equivocado se sube entero antes
 *  de que nadie note que no era un documento. */
const MAX_BYTES_DOC = 2 * 1024 * 1024;

const MAX_BYTES_CARGO = 50 * 1024 * 1024;
const TIPOS_CARGO = "image/jpeg,image/png,image/heic,image/webp,application/pdf";

const SELECT =
  "rounded-control border border-sand bg-hueso px-3 py-2 text-base text-tinta transition-colors duration-150 sm:text-sm";

function selloLima(iso: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  if (isNaN(d.getTime())) return iso;
  return new Intl.DateTimeFormat("es-PE", {
    timeZone: TZ_LIMA, day: "2-digit", month: "long", year: "numeric",
    hour: "2-digit", minute: "2-digit", hour12: true,
  }).format(d);
}

// Fecha plana: se formatea en UTC para que no se corra un día por zona horaria.
function fechaCorta(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "long", year: "numeric", timeZone: "UTC" })
    .format(new Date(Date.UTC(y, m - 1, d)));
}

/**
 * Cómo se nombra una versión en pantalla. Manda la del documento (la que
 * lleva el cargo que se firma), y el correlativo baja a decir lo que de
 * verdad es: cuántas veces se ha publicado esto aquí.
 */
function comoSeLlamaLaVersion(etiqueta: string | null, version: number): string {
  const publicacion = `${version}.ª publicación en el sistema`;
  return etiqueta ? `versión ${etiqueta} · ${publicacion}` : publicacion;
}

type Categoria = "principal" | "complementario" | "formato";

function categoriaDe(tipo: string, requiereAcuse: boolean): Categoria {
  if (PRINCIPALES.includes(tipo)) return "principal";
  return requiereAcuse ? "complementario" : "formato";
}

const NOMBRE_CATEGORIA: Record<Categoria, string> = {
  principal: "Documento principal",
  complementario: "Complementario",
  formato: "Formato",
};

/** El código a partir del nombre: la tabla exige `^[a-z0-9_]{2,40}$`. */
function codigoDesde(nombre: string): string {
  const sinTildes = nombre.normalize("NFD").replace(/[̀-ͯ]/g, "");
  return sinTildes.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "").slice(0, 40);
}

/** Un encabezado ## o ### del documento, para el índice del modal. `orden` es
 *  la posición entre TODOS los encabezados (1 a 4), no solo los que entran al
 *  índice — es lo que deja encontrar el elemento exacto en el DOM sin
 *  depender de que el texto sea único. */
interface EntradaIndice {
  orden: number;
  nivel: 2 | 3;
  texto: string;
}

function indiceDe(texto: string): EntradaIndice[] {
  const bloques = bloquesDe(texto);
  const entradas: EntradaIndice[] = [];
  let orden = 0;
  for (const b of bloques) {
    if (b.tipo !== "encabezado") continue;
    if (b.nivel === 2 || b.nivel === 3) {
      entradas.push({ orden, nivel: b.nivel, texto: b.marcas.map((m) => m.texto).join("") });
    }
    orden++;
  }
  return entradas;
}

export default function NormasPage() {
  return (
    <Suspense fallback={<main className="p-6"><Cargando texto="Cargando…" /></main>}>
      <NormasPageContenido />
    </Suspense>
  );
}

function NormasPageContenido() {
  useTituloDocumento("Normas");
  const yo = usePersonaActual();
  const puedeGestionar = yo !== null && ROLES_DO.includes(yo.rol);
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const { avisar } = useToast();
  const supabase = useMemo(() => createAdminSupabaseClient(), []);

  // ── Tab activo, enlazable por `?tab=` ─────────────────────────────────────
  const [tab, setTabState] = useState<TabId>(() => {
    const t = searchParams.get("tab");
    return t === "versiones" || t === "constancias" || t === "historial" ? t : "vigentes";
  });
  const setTab = useCallback((t: TabId) => {
    setTabState(t);
    const params = new URLSearchParams(Array.from(searchParams.entries()));
    params.set("tab", t);
    router.replace(`${pathname}?${params.toString()}`, { scroll: false });
  }, [pathname, router, searchParams]);

  // Un tab que no le toca (colaboradora en Versiones, o DO en Mi historial)
  // se corrige en cuanto se sabe el rol — antes no se sabe si corregir.
  useEffect(() => {
    if (yo === null) return;
    // eslint-disable-next-line react-hooks/set-state-in-effect -- corrige el tab a uno permitido en cuanto se conoce el rol.
    if (!puedeGestionar && (tab === "versiones" || tab === "constancias")) setTab("vigentes");
    if (puedeGestionar && tab === "historial") setTab("vigentes");
    // eslint-disable-next-line react-hooks/exhaustive-deps -- solo reacciona a que se resuelva el rol, no a cada cambio de tab.
  }, [yo, puedeGestionar]);

  // ── Vigentes ───────────────────────────────────────────────────────────
  const [docs, setDocs] = useState<Doc[]>([]);
  const [cargando, setCargando] = useState(true);
  const [tipos, setTipos] = useState<Tipo[]>([]);
  const [versionesCount, setVersionesCount] = useState<number | null>(null);

  const [busqueda, setBusqueda] = useState("");
  const [filtroTipo, setFiltroTipo] = useState<Categoria | "">("");
  const [filtroConstancia, setFiltroConstancia] = useState<"" | "si" | "no">("");

  const cargar = useCallback(async () => {
    const { data, error } = await supabase.rpc("fn_documentos_vigentes");
    if (error) {
      avisar("error", mensajeDeError(error, "cargar los documentos"));
      setCargando(false);
      return;
    }
    setDocs((data as unknown as Doc[]) ?? []);
    setCargando(false);
  }, [supabase, avisar]);

  // La carga espera a que la sesión esté lista (`yo`). Al entrar directo a /admin/normas o al recargar, las
  // consultas salían ANTES de que el cliente tuviera la sesión: Postgres las veía como anónimas, rechazaba
  // `fn_documentos_vigentes` con 42501 («No tienes permiso…») y el contador de versiones quedaba en «—».
  // La función y los permisos de producción estaban bien (medido el 2026-10-24).
  // eslint-disable-next-line react-hooks/set-state-in-effect -- cargar cuando la sesión está lista, mismo patrón que el resto del panel.
  useEffect(() => { if (yo !== null) void cargar(); }, [cargar, yo]);

  useEffect(() => {
    if (yo === null) return;
    void (async () => {
      const { count } = await supabase
        .from("documentos_institucionales")
        .select("id", { count: "exact", head: true });
      setVersionesCount(count ?? null);
    })();
  }, [supabase, yo]);

  useEffect(() => {
    if (!puedeGestionar) return;
    void (async () => {
      const { data } = await supabase
        .from("documentos_tipos")
        .select("codigo, nombre, requiere_acuse, orden")
        .eq("activo", true)
        .order("orden");
      setTipos((data as Tipo[]) ?? []);
    })();
  }, [supabase, puedeGestionar]);

  const docsFiltrados = useMemo(() => {
    const q = busqueda.trim().toLowerCase();
    return docs.filter((d) => {
      if (q && !(d.titulo.toLowerCase().includes(q) || d.documento.toLowerCase().includes(q))) return false;
      if (filtroTipo && categoriaDe(d.tipo, d.requiere_acuse) !== filtroTipo) return false;
      if (filtroConstancia === "si" && !d.requiere_acuse) return false;
      if (filtroConstancia === "no" && d.requiere_acuse) return false;
      return true;
    });
  }, [docs, busqueda, filtroTipo, filtroConstancia]);

  const principales = docsFiltrados.filter((d) => categoriaDe(d.tipo, d.requiere_acuse) === "principal");
  const complementarios = docsFiltrados.filter((d) => categoriaDe(d.tipo, d.requiere_acuse) === "complementario");
  const formatos = docsFiltrados.filter((d) => categoriaDe(d.tipo, d.requiere_acuse) === "formato");

  // ── Modal de documento ────────────────────────────────────────────────
  const [modal, setModal] = useState<ModalDoc | null>(null);
  const [modalCargando, setModalCargando] = useState(false);

  function abrirModalVigente(d: Doc) {
    setModal({
      documento_id: d.documento_id, tipo: d.tipo, tipo_nombre: d.tipo_nombre,
      version: d.version, etiqueta_version: d.etiqueta_version, titulo: d.titulo,
      documento: d.documento, vigente_desde: d.vigente_desde, publicado_at: d.publicado_at,
      esVigente: true, requiere_acuse: d.requiere_acuse, mi_acuse_at: d.mi_acuse_at,
      total_acuses: d.total_acuses, poblacion: d.poblacion,
    });
  }

  const abrirModalHistorico = useCallback(async (id: string) => {
    setModalCargando(true);
    const { data, error } = await supabase
      .from("documentos_institucionales")
      .select("id, tipo, version, etiqueta_version, titulo, documento, vigente_desde, publicado_at, notas")
      .eq("id", id)
      .maybeSingle();
    setModalCargando(false);
    if (error || !data) {
      avisar("error", mensajeDeError(error ?? undefined, "abrir esa versión"));
      return;
    }
    const info = tipos.find((t) => t.codigo === data.tipo);
    setModal({
      documento_id: data.id, tipo: data.tipo, tipo_nombre: info?.nombre ?? data.tipo,
      version: data.version, etiqueta_version: data.etiqueta_version, titulo: data.titulo,
      documento: data.documento, vigente_desde: data.vigente_desde, publicado_at: data.publicado_at,
      esVigente: false, requiere_acuse: info?.requiere_acuse ?? false,
      mi_acuse_at: null, total_acuses: 0, poblacion: 0,
    });
  }, [supabase, tipos, avisar]);

  // El «#doc-<id>» con el que llega el aviso de acuses pendientes
  // (components/acuses-pendientes.tsx) y la Bandeja: abre el modal directo,
  // sin que la persona tenga que buscar el documento en la biblioteca.
  useEffect(() => {
    if (cargando || docs.length === 0) return;
    const id = window.location.hash.replace(/^#doc-/, "");
    if (!id || id === window.location.hash) return;
    const d = docs.find((x) => x.documento_id === id);
    // eslint-disable-next-line react-hooks/set-state-in-effect -- abre el modal al que apunta el enlace, una sola vez cuando `docs` llega.
    if (d) abrirModalVigente(d);
  }, [cargando, docs]);

  function irAConstanciasDesdeModal(documentoId: string) {
    setModal(null);
    setConstanciaDocId(documentoId);
    setTab("constancias");
  }

  // ── Dejar constancia propia (dentro del modal) ────────────────────────
  const [nombreDeclarado, setNombreDeclarado] = useState("");
  const [msgConstancia, setMsgConstancia] = useState<string | null>(null);
  const [ocupadoAcuse, setOcupadoAcuse] = useState(false);
  const refNombre = useRef<HTMLInputElement | null>(null);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- precarga el nombre declarado con el de la persona en cuanto se conoce.
    if (yo?.nombreCompleto) setNombreDeclarado(yo.nombreCompleto);
  }, [yo]);

  useEffect(() => {
    if (!msgConstancia) return;
    refNombre.current?.scrollIntoView({ block: "center" });
    refNombre.current?.focus({ preventScroll: true });
  }, [msgConstancia]);

  async function acusar(d: ModalDoc) {
    if (nombreDeclarado.trim().split(/\s+/).filter(Boolean).length < 2) {
      setMsgConstancia("Escribe tu nombre y tu apellido para dejar constancia.");
      return;
    }
    setOcupadoAcuse(true); setMsgConstancia(null);
    const { error } = await supabase.rpc("fn_acusar_documento", {
      p_documento_id: d.documento_id,
      p_nombre_declarado: nombreDeclarado.trim(),
    });
    setOcupadoAcuse(false);
    if (error) { setMsgConstancia(mensajeDeError(error)); return; }
    setModal((m) => (m ? { ...m, mi_acuse_at: new Date().toISOString() } : m));
    await cargar();
    avisar("ok", "Constancia registrada. No hace falta hacer nada más hasta que se publique una versión nueva.");
  }

  // ── Publicar una versión, en dos pasos ────────────────────────────────
  const [publicarAbierto, setPublicarAbierto] = useState(false);
  const [pasoPublicar, setPasoPublicar] = useState<1 | 2>(1);
  const [ocupadoPublicar, setOcupadoPublicar] = useState(false);
  const [creandoTipo, setCreandoTipo] = useState(false);
  const [tipoNuevo, setTipoNuevo] = useState({ nombre: "", acuse: true });
  const [tipoElegido, setTipoElegido] = useState("rit");
  const [archivoDoc, setArchivoDoc] = useState<{ nombre: string; texto: string } | null>(null);
  const [pegando, setPegando] = useState(false);
  const [textoPegado, setTextoPegado] = useState("");
  const [tituloDoc, setTituloDoc] = useState("");
  const [vigenteDesde, setVigenteDesde] = useState("");
  const [notasDoc, setNotasDoc] = useState("");
  const [etiquetaDoc, setEtiquetaDoc] = useState("");

  function abrirPublicar() {
    setPasoPublicar(1);
    if (!tipoElegido && tipos.length) setTipoElegido(tipos[0].codigo);
    setPublicarAbierto(true);
  }
  function cerrarPublicar() {
    setPublicarAbierto(false); setPasoPublicar(1);
    setArchivoDoc(null); setTituloDoc(""); setTextoPegado(""); setNotasDoc(""); setEtiquetaDoc("");
    setCreandoTipo(false);
  }

  async function elegirArchivo(f: File | null) {
    setArchivoDoc(null);
    if (!f) return;
    if (f.size > MAX_BYTES_DOC) {
      avisar("error", `“${f.name}” pesa ${(f.size / 1048576).toFixed(1)} MB y el máximo es 2 MB. ¿Seguro que es el documento?`);
      return;
    }
    const texto = await f.text();
    if (!texto.trim()) { avisar("error", "El archivo está vacío."); return; }
    setArchivoDoc({ nombre: f.name, texto });
    const h1 = texto.split("\n").find((l) => l.trim().startsWith("# "));
    if (h1 && !tituloDoc) setTituloDoc(h1.replace(/^#\s*/, "").trim());
  }

  function pegarTexto(t: string) {
    setTextoPegado(t);
    if (!t.trim()) { setArchivoDoc(null); return; }
    if (t.length > MAX_BYTES_DOC) {
      avisar("error", `El texto pegado es enorme (${(t.length / 1048576).toFixed(1)} MB). ¿Seguro que es el documento?`);
      setArchivoDoc(null);
      return;
    }
    setArchivoDoc({ nombre: "Texto pegado", texto: t });
    const h1 = t.split("\n").find((l) => l.trim().startsWith("# "));
    if (h1 && !tituloDoc) setTituloDoc(h1.replace(/^#\s*/, "").trim());
  }

  async function crearTipo() {
    const nombre = tipoNuevo.nombre.trim();
    const codigo = codigoDesde(nombre);
    if (codigo.length < 2) { avisar("error", "El nombre tiene que tener al menos dos letras o números."); return; }
    if (tipos.some((t) => t.codigo === codigo)) { avisar("error", `Ya existe un documento con ese nombre (${codigo}).`); return; }
    setOcupadoPublicar(true);
    const orden = 100 + tipos.length * 10;
    const { error } = await supabase.from("documentos_tipos")
      .insert({ codigo, nombre, orden, requiere_acuse: tipoNuevo.acuse });
    setOcupadoPublicar(false);
    if (error) { avisar("error", mensajeDeError(error, "crear el tipo de documento")); return; }
    const { data } = await supabase.from("documentos_tipos")
      .select("codigo, nombre, requiere_acuse, orden").eq("activo", true).order("orden");
    setTipos((data as Tipo[]) ?? []);
    setTipoElegido(codigo);
    setCreandoTipo(false); setTipoNuevo({ nombre: "", acuse: true });
    avisar("ok", `«${nombre}» ya se puede publicar${tipoNuevo.acuse ? ", y pedirá constancia a cada integrante" : ", para consulta y sin constancia"}.`);
  }

  /** El documento vigente HOY de `tipoElegido`, si lo tiene — la base del
   *  paso de confirmación: cuántas personas ya constaron esa versión y
   *  volverían a estar pendientes de la nueva. */
  const vigenteDelTipoElegido = docs.find((d) => d.tipo === tipoElegido);
  const tipoElegidoInfo = tipos.find((t) => t.codigo === tipoElegido);
  const numeroVersionNueva = (vigenteDelTipoElegido?.version ?? 0) + 1;

  function irAConfirmarPublicar() {
    if (!archivoDoc) { avisar("error", "Falta el documento: sube el archivo o pega el texto."); return; }
    if (!tituloDoc.trim()) { avisar("error", "Falta el título con el que se va a mostrar."); return; }
    setPasoPublicar(2);
  }

  async function confirmarPublicar() {
    if (!archivoDoc) return;
    setOcupadoPublicar(true);
    const { data, error } = await supabase.rpc("fn_publicar_documento", {
      p_tipo: tipoElegido,
      p_titulo: tituloDoc.trim(),
      p_documento: archivoDoc.texto,
      p_vigente_desde: vigenteDesde || null,
      p_notas: notasDoc.trim() || null,
      p_etiqueta: etiquetaDoc.trim() || null,
    });
    setOcupadoPublicar(false);
    if (error) { avisar("error", mensajeDeError(error, "publicar el documento")); return; }
    const pideAcuse = tipoElegidoInfo?.requiere_acuse ?? true;
    cerrarPublicar();
    await cargar();
    setVersiones([]); // se recarga sola la próxima vez que se mire el tab
    setVersionesCount((n) => (n === null ? null : n + 1));
    avisar("ok", pideAcuse
      ? `Publicada la versión ${String(data)}. Desde ahora cada integrante deja su constancia, y quien no tenga cuenta la deja en papel.`
      : `Publicada la versión ${String(data)}. Queda publicada para consulta: este documento no pide constancia a nadie.`);
  }

  // ── Tab Versiones (solo DO) ────────────────────────────────────────────
  const [versiones, setVersiones] = useState<VersionRow[]>([]);
  const [versionesCargando, setVersionesCargando] = useState(false);
  const [filtroEstadoVersion, setFiltroEstadoVersion] = useState<"" | "vigente" | "historica">("");
  const [filtroVigenciaDesde, setFiltroVigenciaDesde] = useState("");
  const [filtroVigenciaHasta, setFiltroVigenciaHasta] = useState("");
  const [diffAbierto, setDiffAbierto] = useState<{ id: string; lineas: LineaDiff[] } | null>(null);
  const [diffCargando, setDiffCargando] = useState<string | null>(null);
  const textosCache = useRef(new Map<string, string>());
  const [restaurando, setRestaurando] = useState<VersionRow | null>(null);
  const [ocupadoRestaurar, setOcupadoRestaurar] = useState(false);

  const cargarVersiones = useCallback(async () => {
    setVersionesCargando(true);
    const { data, error } = await supabase
      .from("documentos_institucionales")
      .select("id, tipo, version, etiqueta_version, titulo, vigente_desde, publicado_at, notas")
      .order("tipo")
      .order("version", { ascending: false });
    setVersionesCargando(false);
    if (error) { avisar("error", mensajeDeError(error, "cargar las versiones")); return; }
    setVersiones((data as VersionRow[]) ?? []);
  }, [supabase, avisar]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- carga perezosa la primera vez que se mira el tab, mismo patrón que el resto del panel.
    if (tab === "versiones" && puedeGestionar && versiones.length === 0 && !versionesCargando) void cargarVersiones();
  }, [tab, puedeGestionar, versiones.length, versionesCargando, cargarVersiones]);

  const vigentePorTipo = useMemo(() => new Map(docs.map((d) => [d.tipo, d.version])), [docs]);

  const versionesFiltradas = useMemo(() => {
    return versiones.filter((v) => {
      const esVigente = vigentePorTipo.get(v.tipo) === v.version;
      if (filtroEstadoVersion === "vigente" && !esVigente) return false;
      if (filtroEstadoVersion === "historica" && esVigente) return false;
      if (filtroVigenciaDesde && v.vigente_desde < filtroVigenciaDesde) return false;
      if (filtroVigenciaHasta && v.vigente_desde > filtroVigenciaHasta) return false;
      return true;
    });
  }, [versiones, vigentePorTipo, filtroEstadoVersion, filtroVigenciaDesde, filtroVigenciaHasta]);

  const gruposVersiones = useMemo(() => {
    const porTipo = new Map<string, VersionRow[]>();
    for (const v of versionesFiltradas) {
      const lista = porTipo.get(v.tipo) ?? [];
      lista.push(v);
      porTipo.set(v.tipo, lista);
    }
    const orden = new Map(tipos.map((t) => [t.codigo, t.orden]));
    return Array.from(porTipo.entries())
      .map(([codigo, filas]) => ({
        codigo,
        nombre: tipos.find((t) => t.codigo === codigo)?.nombre ?? filas[0]?.titulo ?? codigo,
        filas: [...filas].sort((a, b) => b.version - a.version),
      }))
      .sort((a, b) => (orden.get(a.codigo) ?? 999) - (orden.get(b.codigo) ?? 999));
  }, [versionesFiltradas, tipos]);

  function verVersion(row: VersionRow) {
    const esVigente = vigentePorTipo.get(row.tipo) === row.version;
    const doc = esVigente ? docs.find((d) => d.documento_id === row.id) : undefined;
    if (doc) abrirModalVigente(doc);
    else void abrirModalHistorico(row.id);
  }

  async function textoDe(id: string): Promise<string | null> {
    const enCache = textosCache.current.get(id);
    if (enCache !== undefined) return enCache;
    const { data, error } = await supabase
      .from("documentos_institucionales").select("documento").eq("id", id).maybeSingle();
    if (error || !data) return null;
    textosCache.current.set(id, data.documento);
    return data.documento;
  }

  async function compararConAnterior(row: VersionRow, anterior: VersionRow) {
    if (diffAbierto?.id === row.id) { setDiffAbierto(null); return; }
    setDiffCargando(row.id);
    const [textoAnterior, textoNuevo] = await Promise.all([textoDe(anterior.id), textoDe(row.id)]);
    setDiffCargando(null);
    if (textoAnterior === null || textoNuevo === null) {
      avisar("error", "No se pudo traer el texto de una de las dos versiones para compararlas.");
      return;
    }
    setDiffAbierto({ id: row.id, lineas: diffLineas(textoAnterior, textoNuevo) });
  }

  async function confirmarRestaurar() {
    if (!restaurando) return;
    setOcupadoRestaurar(true);
    const { data, error } = await restaurarDocumento(supabase, restaurando.id);
    setOcupadoRestaurar(false);
    if (error) { avisar("error", mensajeDeError(error, "restaurar esta versión")); return; }
    setRestaurando(null);
    await Promise.all([cargar(), cargarVersiones()]);
    setVersionesCount((n) => (n === null ? null : n + 1));
    avisar("ok", `Restaurada como versión ${String(data)}, ahora vigente.`);
  }

  // ── Tab Constancias (solo DO) ──────────────────────────────────────────
  const [constanciaDocId, setConstanciaDocId] = useState<string | null>(null);
  const [filasConstancia, setFilasConstancia] = useState<FilaAcuse[]>([]);
  const [constanciaCargando, setConstanciaCargando] = useState(false);
  const [buscaPersona, setBuscaPersona] = useState("");
  const [filtroSedeConstancia, setFiltroSedeConstancia] = useState("");
  const [filtroEstadoConstancia, setFiltroEstadoConstancia] = useState<"" | "registrada" | "pendiente">("");
  const [coberturaAnterior, setCoberturaAnterior] = useState<
    { version: number; etiqueta: string | null; total: number; poblacion: number } | null
  >(null);

  const docsConAcuse = docs.filter((d) => d.requiere_acuse);

  useEffect(() => {
    if (tab !== "constancias" || !puedeGestionar) return;
    if (constanciaDocId === null && docsConAcuse.length > 0) {
      const preferido = docsConAcuse.find((d) => PRINCIPALES.includes(d.tipo)) ?? docsConAcuse[0];
      setConstanciaDocId(preferido.documento_id);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps -- solo elige un valor inicial, no debe repetirse cada render.
  }, [tab, puedeGestionar, constanciaDocId, docsConAcuse.length]);

  const cargarConstancias = useCallback(async (documentoId: string) => {
    setConstanciaCargando(true);
    setCoberturaAnterior(null);
    const { data, error } = await supabase.rpc("fn_acuses_documento", { p_documento_id: documentoId });
    if (error) {
      setConstanciaCargando(false);
      avisar("error", mensajeDeError(error, "cargar las constancias"));
      return;
    }
    const filas = (data as unknown as FilaAcuse[]) ?? [];
    const { data: rutas } = await supabase
      .from("documentos_acuses").select("persona_id, storage_path").eq("documento_id", documentoId);
    const porPersona = new Map((rutas ?? []).map((r) => [r.persona_id as string, r.storage_path as string | null]));
    setFilasConstancia(filas.map((f) => ({ ...f, storage_path: porPersona.get(f.persona_id) ?? null })));
    setConstanciaCargando(false);

    // Cobertura de la versión anterior del mismo tipo, si existe.
    const doc = docs.find((d) => d.documento_id === documentoId);
    if (!doc) return;
    const { data: prevRows } = await supabase
      .from("documentos_institucionales")
      .select("id, version, etiqueta_version")
      .eq("tipo", doc.tipo)
      .lt("version", doc.version)
      .order("version", { ascending: false })
      .limit(1);
    const anterior = prevRows?.[0];
    if (!anterior) return;
    const { data: acusesAnterior } = await supabase
      .rpc("fn_acuses_documento", { p_documento_id: anterior.id as string });
    const filasAnterior = (acusesAnterior as unknown as FilaAcuse[]) ?? [];
    setCoberturaAnterior({
      version: anterior.version as number,
      etiqueta: anterior.etiqueta_version as string | null,
      total: filasAnterior.filter((f) => f.acusado_at !== null).length,
      poblacion: filasAnterior.length,
    });
  }, [supabase, avisar, docs]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- carga las constancias del documento elegido, mismo patrón que el resto del panel.
    if (tab === "constancias" && constanciaDocId) void cargarConstancias(constanciaDocId);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- recarga solo cuando cambia el tab o el documento elegido, no en cada referencia nueva de `cargarConstancias`.
  }, [tab, constanciaDocId]);

  const porSede = useMemo(() => {
    const sedes = Array.from(new Set(filasConstancia.map((f) => f.sede))).sort();
    return sedes.map((sede) => {
      const filas = filasConstancia.filter((f) => f.sede === sede);
      return { sede, completas: filas.filter((f) => f.acusado_at !== null).length, total: filas.length };
    });
  }, [filasConstancia]);

  const filasConstanciaFiltradas = useMemo(() => {
    const q = buscaPersona.trim().toLowerCase();
    return filasConstancia.filter((f) => {
      if (q && !f.nombre.toLowerCase().includes(q)) return false;
      if (filtroSedeConstancia && f.sede !== filtroSedeConstancia) return false;
      if (filtroEstadoConstancia === "registrada" && f.acusado_at === null) return false;
      if (filtroEstadoConstancia === "pendiente" && f.acusado_at !== null) return false;
      return true;
    });
  }, [filasConstancia, buscaPersona, filtroSedeConstancia, filtroEstadoConstancia]);

  function exportarCsvConstancias() {
    const doc = docs.find((d) => d.documento_id === constanciaDocId);
    const filas = filasConstanciaFiltradas.map((f) => ({
      Persona: f.nombre,
      Sede: f.sede,
      Estado: f.acusado_at !== null ? "Constancia registrada" : "Pendiente de constancia",
      Fecha: f.acusado_at ? selloLima(f.acusado_at) : "",
    }));
    const csv = generarCsv(filas, ["Persona", "Sede", "Estado", "Fecha"]);
    const nombre = doc ? `constancias_${doc.tipo}_v${doc.version}.csv` : "constancias.csv";
    descargarCsv(nombre, csv);
  }

  // El cargo en papel de quien no tiene cuenta.
  const [papelPara, setPapelPara] = useState<{ persona: string; nombre: string } | null>(null);
  const [archivo, setArchivo] = useState<File | null>(null);
  const [fechaPapel, setFechaPapel] = useState("");
  const [notaPapel, setNotaPapel] = useState("");
  const [msgPapel, setMsgPapel] = useState<string | null>(null);
  const [progreso, setProgreso] = useState<number | null>(null);
  const [ocupadoPapel, setOcupadoPapel] = useState(false);
  const refCargo = useRef<HTMLInputElement | null>(null);

  useEffect(() => {
    if (!msgPapel) return;
    refCargo.current?.scrollIntoView({ block: "center" });
    refCargo.current?.focus({ preventScroll: true });
  }, [msgPapel]);

  async function guardarPapel() {
    if (!papelPara || !constanciaDocId) return;
    if (!archivo) {
      setMsgPapel("Falta el cargo firmado escaneado. Sin el papel no hay constancia que registrar.");
      return;
    }
    if (archivo.size > MAX_BYTES_CARGO) {
      setMsgPapel(`“${archivo.name}” pesa ${(archivo.size / 1048576).toFixed(1)} MB y el máximo es 50 MB.`);
      return;
    }
    setOcupadoPapel(true); setMsgPapel(null);
    const ext = archivo.name.split(".").pop()?.toLowerCase() ?? "bin";
    const ruta = `${constanciaDocId}/${papelPara.persona}-${Date.now()}.${ext}`;
    setProgreso(0);
    const fallo = await subirArchivoConProgreso(supabase, "acuses", ruta, archivo, setProgreso);
    setProgreso(null);
    if (fallo) { setOcupadoPapel(false); setMsgPapel(`El archivo no subió (${fallo}). Vuelve a intentarlo.`); return; }
    const { error } = await supabase.rpc("fn_registrar_acuse_papel", {
      p_documento_id: constanciaDocId,
      p_persona_id: papelPara.persona,
      p_path: ruta,
      p_acusado_at: fechaPapel ? new Date(`${fechaPapel}T12:00:00-05:00`).toISOString() : null,
      p_nota: notaPapel.trim() || null,
    });
    setOcupadoPapel(false);
    if (error) { setMsgPapel(mensajeDeError(error)); return; }
    setPapelPara(null); setArchivo(null); setNotaPapel(""); setMsgPapel(null);
    await cargar();
    await cargarConstancias(constanciaDocId);
    avisar("ok", "Constancia en papel registrada, con su cargo archivado.");
  }

  async function verCargo(path: string) {
    const fallo = await abrirArchivoFirmado(supabase, "acuses", path);
    if (fallo) setMsgPapel(fallo);
  }

  // ── Tab Mi historial (quien no gestiona) ──────────────────────────────
  const [misConstancias, setMisConstancias] = useState<MiConstancia[]>([]);
  const [historialCargando, setHistorialCargando] = useState(false);

  const cargarHistorial = useCallback(async () => {
    if (!yo) return;
    setHistorialCargando(true);
    const { data, error } = await supabase
      .from("documentos_acuses")
      .select("documento_id, acusado_at, via")
      .eq("persona_id", yo.id);
    if (error || !data || data.length === 0) {
      setHistorialCargando(false);
      setMisConstancias([]);
      return;
    }
    const ids = data.map((r) => r.documento_id as string);
    const { data: docsRel } = await supabase
      .from("documentos_institucionales")
      .select("id, tipo, titulo, etiqueta_version, version")
      .in("id", ids);
    const porId = new Map((docsRel ?? []).map((d) => [d.id as string, d]));
    const tiposCod = Array.from(new Set((docsRel ?? []).map((d) => d.tipo as string)));
    const { data: tiposRel } = tiposCod.length
      ? await supabase.from("documentos_tipos").select("codigo, nombre").in("codigo", tiposCod)
      : { data: [] as { codigo: string; nombre: string }[] };
    const nombrePorTipo = new Map((tiposRel ?? []).map((t) => [t.codigo as string, t.nombre as string]));

    const armadas: MiConstancia[] = data
      .filter((r) => porId.has(r.documento_id as string))
      .map((r) => {
        const d = porId.get(r.documento_id as string)!;
        return {
          documento_id: r.documento_id as string,
          titulo: d.titulo as string,
          tipo_nombre: nombrePorTipo.get(d.tipo as string) ?? (d.tipo as string),
          etiqueta_version: d.etiqueta_version as string | null,
          version: d.version as number,
          acusado_at: r.acusado_at as string,
          via: r.via as string,
        };
      })
      .sort((a, b) => b.acusado_at.localeCompare(a.acusado_at));
    setMisConstancias(armadas);
    setHistorialCargando(false);
  }, [supabase, yo]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- carga el historial al entrar al tab, mismo patrón que el resto del panel.
    if (tab === "historial" && !puedeGestionar) void cargarHistorial();
  }, [tab, puedeGestionar, cargarHistorial]);

  // ── Resumen (arriba de la biblioteca) ─────────────────────────────────
  const constanciasPendientes = docs
    .filter((d) => d.requiere_acuse)
    .reduce((s, d) => s + (d.poblacion - d.total_acuses), 0);

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6">
        <div className="w-full">
          <CabeceraPagina
            sobretitulo={sobretituloDeHoy("Publicaciones")}
            titulo="Normas"
            descripcion="Los documentos que rigen para todo el equipo. Aquí se leen, y aquí queda la constancia de que se recibieron."
            ayuda={
              <AyudaPantalla
                titulo="Cómo funcionan las normas"
                intro="Aquí viven los documentos que rigen para todo el equipo. Se leen aquí, y aquí queda la constancia de que se recibieron."
                secciones={[
                  { titulo: "Vigentes", texto: "La versión que hoy rige de cada documento, en tres grupos: principales, complementarios y formatos. Abrir uno muestra su texto." },
                  { titulo: "Constancia de recepción", texto: "Los documentos que la requieren piden que cada persona deje constancia de haberlos recibido; lo que falta se cuenta como «constancias pendientes»." },
                  { titulo: "Versiones", texto: "Quien gestiona las normas publica una versión nueva con «+ Nueva versión»; la anterior queda en el historial." },
                  { titulo: "Mi historial", texto: "Quien no gestiona las normas ve aquí lo que ya recibió y cuándo." },
                ]}
              />
            }
            accion={puedeGestionar && (
              <Boton variante="primario" onClick={abrirPublicar}>+ Nueva versión</Boton>
            )}
          />

          {/* ── Pestañas ── */}
          <Pestanas
            etiqueta="Secciones de Normas"
            pestanas={
              puedeGestionar
                ? [{ clave: "vigentes", texto: "Vigentes" }, { clave: "versiones", texto: "Versiones" }, { clave: "constancias", texto: "Constancias", aviso: constanciasPendientes }]
                : yo !== null
                  ? [{ clave: "vigentes", texto: "Vigentes" }, { clave: "historial", texto: "Mi historial" }]
                  : [{ clave: "vigentes", texto: "Vigentes" }]
            }
            activa={tab}
            alElegir={(t) => setTab(t as typeof tab)}
          />

          {tab === "vigentes" && (
            <>
              {/* ── Resumen: lo que falta, en una línea ── */}
              {puedeGestionar && (
                <ParaAtender
                  items={[{ clave: "constancias", texto: `${constanciasPendientes} constancias pendientes`, n: constanciasPendientes, tono: "ambar" }]}
                  activa={null}
                  alTocar={() => setTab("constancias")}
                />
              )}
              <p className="-mt-2 mb-4 text-xs text-taupe">
                {docs.length} {docs.length === 1 ? "documento vigente" : "documentos vigentes"}
                {" · "}{versionesCount === null ? "—" : versionesCount} versiones publicadas
                {" · "}{docs.filter((d) => d.requiere_acuse).length} requieren recepción
              </p>

              {/* ── Buscador y filtros ── */}
              <div className="mb-5 flex flex-wrap items-center gap-2">
                <div className="relative min-w-48 flex-1">
                  <Search className="pointer-events-none absolute left-2.5 top-1/2 size-3.5 -translate-y-1/2 text-taupe" aria-hidden />
                  <Campo
                    tamano="sm" type="search" value={busqueda} onChange={(e) => setBusqueda(e.target.value)}
                    placeholder="Buscar por nombre o contenido…" aria-label="Buscar documento" className="pl-8"
                  />
                </div>
                <div className="w-full sm:w-44">
                  <CampoSelect tamano="sm" aria-label="Tipo" value={filtroTipo} onChange={(e) => setFiltroTipo(e.target.value as Categoria | "")}>
                    <option value="">Tipo · todos</option>
                    <option value="principal">Principal</option>
                    <option value="complementario">Complementario</option>
                    <option value="formato">Formato</option>
                  </CampoSelect>
                </div>
                <div className="w-full sm:w-52">
                  <CampoSelect tamano="sm" aria-label="Requiere constancia" value={filtroConstancia}
                    onChange={(e) => setFiltroConstancia(e.target.value as "" | "si" | "no")}>
                    <option value="">Constancia · todas</option>
                    <option value="si">Requiere constancia</option>
                    <option value="no">No requiere</option>
                  </CampoSelect>
                </div>
                {(busqueda || filtroTipo || filtroConstancia) && (
                  <Boton variante="sutil" tamano="sm" onClick={() => { setBusqueda(""); setFiltroTipo(""); setFiltroConstancia(""); }}>
                    Limpiar filtros
                  </Boton>
                )}
              </div>

              {cargando ? (
                <Cargando texto="Cargando los documentos…" />
              ) : docs.length === 0 ? (
                <EstadoVacio>
                  Todavía no hay ningún documento publicado.
                  {puedeGestionar && " Publica el primero con «+ Nueva versión»."}
                </EstadoVacio>
              ) : docsFiltrados.length === 0 ? (
                <EstadoVacio>Ningún documento coincide con la búsqueda o los filtros.</EstadoVacio>
              ) : (
                <div className="space-y-8">
                  <GrupoDocumentos titulo="Documentos principales" docs={principales} puedeGestionar={puedeGestionar}
                    onVer={abrirModalVigente} onVerConstancias={irAConstanciasDesdeModal} />
                  {complementarios.length > 0 && (
                    <GrupoDocumentos titulo="Documentos complementarios" docs={complementarios} puedeGestionar={puedeGestionar}
                      onVer={abrirModalVigente} onVerConstancias={irAConstanciasDesdeModal} />
                  )}
                  {formatos.length > 0 && (
                    <GrupoDocumentos titulo="Formatos y otros" docs={formatos} puedeGestionar={puedeGestionar}
                      onVer={abrirModalVigente} onVerConstancias={irAConstanciasDesdeModal} />
                  )}
                </div>
              )}
            </>
          )}

          {tab === "versiones" && puedeGestionar && (
            <div>
              <div className="mb-5 flex flex-wrap items-center gap-2">
                <select aria-label="Estado" value={filtroEstadoVersion}
                  onChange={(e) => setFiltroEstadoVersion(e.target.value as "" | "vigente" | "historica")} className={SELECT}>
                  <option value="">Estado · todas</option>
                  <option value="vigente">Vigente</option>
                  <option value="historica">Histórica</option>
                </select>
                <label className="flex items-center gap-1.5 text-xs text-taupe">
                  Vigencia desde
                  <input type="date" value={filtroVigenciaDesde} onChange={(e) => setFiltroVigenciaDesde(e.target.value)} className={`${SELECT} py-1.5`} />
                </label>
                <label className="flex items-center gap-1.5 text-xs text-taupe">
                  hasta
                  <input type="date" value={filtroVigenciaHasta} onChange={(e) => setFiltroVigenciaHasta(e.target.value)} className={`${SELECT} py-1.5`} />
                </label>
                {(filtroEstadoVersion || filtroVigenciaDesde || filtroVigenciaHasta) && (
                  <Boton variante="sutil" tamano="sm" onClick={() => { setFiltroEstadoVersion(""); setFiltroVigenciaDesde(""); setFiltroVigenciaHasta(""); }}>
                    Limpiar filtros
                  </Boton>
                )}
              </div>

              {versionesCargando ? (
                <Cargando texto="Cargando las versiones…" />
              ) : gruposVersiones.length === 0 ? (
                <EstadoVacio>Ninguna versión coincide con los filtros.</EstadoVacio>
              ) : (
                <div className="space-y-8">
                  {gruposVersiones.map((g) => (
                    <div key={g.codigo}>
                      <TituloGrupo texto={g.nombre} />
                      <TarjetaInfo className="divide-y divide-sand px-4 py-0 sm:px-4 sm:py-0">
                        {g.filas.map((row, i) => {
                          const esVigente = vigentePorTipo.get(row.tipo) === row.version;
                          const anterior = g.filas[i + 1];
                          return (
                            <div key={row.id} className="py-3">
                              <div className="flex flex-wrap items-center justify-between gap-2">
                                <div>
                                  <span className="font-serif text-base text-tinta">
                                    {comoSeLlamaLaVersion(row.etiqueta_version, row.version)}
                                  </span>
                                  <span className="ml-2 text-xs text-taupe">
                                    vigente desde {fechaCorta(row.vigente_desde)}
                                    {row.notas && <> · {row.notas}</>}
                                  </span>
                                </div>
                                <div className="flex flex-wrap items-center gap-3">
                                  {esVigente ? <Insignia variante="positivo">Vigente</Insignia> : <Insignia atenuada>Histórica</Insignia>}
                                  <button onClick={() => verVersion(row)} className="text-xs font-medium text-rojo-profundo hover:underline">Ver</button>
                                  <a href={`/admin/normas/${row.id}/imprimir`} target="_blank" rel="noopener"
                                    className="text-xs font-medium text-rojo-profundo hover:underline">Descargar</a>
                                  {anterior && (
                                    <button onClick={() => void compararConAnterior(row, anterior)} disabled={diffCargando === row.id}
                                      className="text-xs font-medium text-rojo-profundo hover:underline disabled:opacity-50">
                                      {diffCargando === row.id ? "Comparando…" : diffAbierto?.id === row.id ? "Ocultar comparación" : "Comparar con la anterior"}
                                    </button>
                                  )}
                                  {!esVigente && (
                                    <button onClick={() => setRestaurando(row)} className="text-xs font-medium text-taupe hover:text-tinta hover:underline">
                                      Restaurar esta versión
                                    </button>
                                  )}
                                </div>
                              </div>
                              {diffAbierto?.id === row.id && (
                                <PanelDiff lineas={diffAbierto.lineas} />
                              )}
                            </div>
                          );
                        })}
                      </TarjetaInfo>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}

          {tab === "constancias" && puedeGestionar && (
            <ConstanciasTab
              docsConAcuse={docsConAcuse}
              constanciaDocId={constanciaDocId}
              onElegir={setConstanciaDocId}
              cargando={constanciaCargando}
              filas={filasConstanciaFiltradas}
              totalSinFiltrar={filasConstancia.length}
              porSede={porSede}
              coberturaAnterior={coberturaAnterior}
              docActual={docs.find((d) => d.documento_id === constanciaDocId) ?? null}
              busca={buscaPersona} onBusca={setBuscaPersona}
              filtroSede={filtroSedeConstancia} onFiltroSede={setFiltroSedeConstancia}
              filtroEstado={filtroEstadoConstancia} onFiltroEstado={setFiltroEstadoConstancia}
              onExportar={exportarCsvConstancias}
              onRegistrarPapel={(persona, nombre) => {
                setPapelPara({ persona, nombre }); setArchivo(null); setFechaPapel(hoyLima()); setNotaPapel(""); setMsgPapel(null);
              }}
              onVerCargo={(p) => void verCargo(p)}
              papelPara={papelPara}
              archivo={archivo} onArchivo={setArchivo}
              fechaPapel={fechaPapel} onFechaPapel={setFechaPapel}
              notaPapel={notaPapel} onNotaPapel={setNotaPapel}
              msgPapel={msgPapel} progreso={progreso} ocupadoPapel={ocupadoPapel}
              onGuardarPapel={() => void guardarPapel()}
              onCancelarPapel={() => setPapelPara(null)}
              refCargo={refCargo}
            />
          )}

          {tab === "historial" && !puedeGestionar && (
            <div>
              {historialCargando ? (
                <Cargando texto="Reuniendo tu historial…" />
              ) : misConstancias.length === 0 ? (
                <EstadoVacio>Todavía no has dejado ninguna constancia.</EstadoVacio>
              ) : (
                <TarjetaInfo className="divide-y divide-sand px-4 py-0 sm:px-4 sm:py-0">
                  {misConstancias.map((m) => (
                    <div key={`${m.documento_id}-${m.acusado_at}`} className="flex flex-wrap items-center justify-between gap-2 py-3">
                      <div>
                        <span className="font-serif text-base text-tinta">{m.titulo}</span>
                        <span className="ml-2 text-xs text-taupe">{comoSeLlamaLaVersion(m.etiqueta_version, m.version)}</span>
                      </div>
                      <Insignia variante="positivo">Constancia registrada — {selloLima(m.acusado_at)}</Insignia>
                    </div>
                  ))}
                </TarjetaInfo>
              )}
              <p className="mt-3 text-xs text-taupe">
                Solo ves tu propio historial. La política salarial tiene su propio seguimiento, en «Política salarial».
              </p>
            </div>
          )}
        </div>
      </main>

      {/* ── Modal de documento ── */}
      <Modal abierto={modal !== null} onCerrar={() => setModal(null)} titulo={modal?.titulo} ancho="xl" bloqueado={ocupadoAcuse}>
        {modalCargando ? (
          <Cargando texto="Abriendo el documento…" />
        ) : modal && (
          <ModalDocumentoContenido
            doc={modal}
            onCerrar={() => setModal(null)}
            onVerConstancias={puedeGestionar ? () => irAConstanciasDesdeModal(modal.documento_id) : undefined}
            nombreDeclarado={nombreDeclarado} onNombreDeclarado={(v) => { setNombreDeclarado(v); setMsgConstancia(null); }}
            msgConstancia={msgConstancia} ocupadoAcuse={ocupadoAcuse}
            onAcusar={() => void acusar(modal)}
            refNombre={refNombre}
          />
        )}
      </Modal>

      {/* ── Modal de publicar (2 pasos) ── */}
      <Modal abierto={publicarAbierto} onCerrar={cerrarPublicar} ancho="lg" bloqueado={ocupadoPublicar}
        titulo={pasoPublicar === 1 ? "Publicar nueva versión — 1. Redactar" : "Publicar nueva versión — 2. Confirmar"}>
        {pasoPublicar === 1 ? (
          <div>
            <p className="mb-3 text-xs text-taupe">
              El texto puede venir de un archivo o pegarse aquí — se guarda igual, y congelado: un
              acuse de hoy seguirá apuntando dentro de cinco años a las palabras que se mostraron
              hoy. Publicar el <strong>mismo</strong> texto no crea versión nueva.
            </p>
            <div className="grid gap-3 sm:grid-cols-2">
              <label className="flex flex-col gap-1 text-xs">
                <span className="flex items-baseline justify-between gap-2">
                  Tipo de documento
                  <button type="button" onClick={() => setCreandoTipo((v) => !v)}
                    className="text-[11px] font-normal text-taupe underline underline-offset-2 hover:text-tinta">
                    {creandoTipo ? "cancelar" : "añadir uno"}
                  </button>
                </span>
                <select value={tipoElegido} onChange={(e) => setTipoElegido(e.target.value)} className={SELECT}>
                  {tipos.map((t) => (
                    <option key={t.codigo} value={t.codigo}>{t.nombre}{t.requiere_acuse ? "" : " (sin constancia)"}</option>
                  ))}
                </select>
              </label>
              <label className="flex flex-col gap-1 text-xs">
                <span className="flex items-baseline justify-between gap-2">
                  {pegando ? "Texto del documento" : "Archivo (.md o .txt)"}
                  <button type="button" onClick={() => { setPegando((v) => !v); setArchivoDoc(null); setTextoPegado(""); }}
                    className="text-[11px] font-normal text-taupe underline underline-offset-2 hover:text-tinta">
                    {pegando ? "subir un archivo" : "o pegar el texto"}
                  </button>
                </span>
                {/* `sm:text-[11px]` además de `text-[11px]`: AreaTexto trae `sm:text-sm`, y
                    una regla con media query le gana a una suelta — sin esto, desde 640 px
                    el texto pegado saldría a 14 px. */}
                {pegando ? (
                  <AreaTexto value={textoPegado} onChange={(e) => pegarTexto(e.target.value)} rows={3}
                    placeholder="Pega aquí el texto — desde Word, Canva, donde esté." className="font-mono text-[11px] sm:text-[11px]" />
                ) : (
                  <input type="file" accept=".md,.txt,text/markdown,text/plain" onChange={(e) => void elegirArchivo(e.target.files?.[0] ?? null)}
                    className="rounded-control border border-sand bg-hueso px-3 py-2 text-xs file:mr-2 file:rounded file:border-0 file:bg-sand file:px-2 file:py-0.5 file:text-xs" />
                )}
              </label>
              <Campo etiqueta="Título con el que se muestra" value={tituloDoc} onChange={(e) => setTituloDoc(e.target.value)}
                placeholder="Reglamento Interno de Trabajo" />
              <div className="flex flex-col gap-1">
                <Campo etiqueta="Rige desde" type="date" value={vigenteDesde} onChange={(e) => setVigenteDesde(e.target.value)} />
                <span className="text-xs text-taupe">Si lo dejas vacío, rige desde hoy.</span>
              </div>
              <div className="flex flex-col gap-1">
                <Campo etiqueta="Versión que dice el documento (opcional)" value={etiquetaDoc} onChange={(e) => setEtiquetaDoc(e.target.value)} placeholder="ej. 4.0" />
                <span className="text-xs text-taupe">La que aparece en el cargo que se firma.</span>
              </div>
              <div className="sm:col-span-2">
                <Campo etiqueta="Nota de la versión (opcional)" value={notasDoc} onChange={(e) => setNotasDoc(e.target.value)}
                  placeholder="ej. sustituye a la v3.0 de junio de 2026" />
              </div>
            </div>

            {creandoTipo && (
              <div className="mt-3 rounded-control border border-sand bg-crema/40 p-3">
                <p className="mb-2 text-xs text-taupe">
                  Un documento nuevo del expediente — una política, un protocolo, la presentación de la empresa.
                </p>
                <div className="grid gap-2 sm:grid-cols-2">
                  <div className="flex flex-col gap-1">
                    <Campo etiqueta="Nombre" value={tipoNuevo.nombre}
                      onChange={(e) => setTipoNuevo((t) => ({ ...t, nombre: e.target.value }))}
                      placeholder="Reglamento Interno de Seguridad y Salud" />
                    {tipoNuevo.nombre.trim() !== "" && (
                      <span className="text-[11px] text-taupe">código: {codigoDesde(tipoNuevo.nombre) || "—"}</span>
                    )}
                  </div>
                  <label className="flex items-start gap-2 text-xs sm:pt-5">
                    <input type="checkbox" checked={tipoNuevo.acuse} className="mt-0.5 size-4 accent-tinta"
                      onChange={(e) => setTipoNuevo((t) => ({ ...t, acuse: e.target.checked }))} />
                    <span>
                      Pedir constancia a cada integrante
                      <span className="block text-[11px] text-taupe">Desmárcalo si el documento no le impone nada al equipo.</span>
                    </span>
                  </label>
                </div>
                <Boton variante="primario" tamano="sm" className="mt-2" onClick={() => void crearTipo()} disabled={ocupadoPublicar || !tipoNuevo.nombre.trim()}>
                  Añadir
                </Boton>
              </div>
            )}

            {archivoDoc && (
              <div className="mt-3 rounded-control border border-sand bg-crema/40 p-3">
                <p className="text-xs text-taupe">
                  <strong>{archivoDoc.nombre}</strong> · {archivoDoc.texto.length.toLocaleString("es-PE")} caracteres
                </p>
                <div className="mt-2 max-h-40 overflow-y-auto text-[11px] leading-relaxed text-tinta">
                  <Documento texto={archivoDoc.texto.slice(0, 1200)} />
                </div>
                <p className="mt-1 text-xs text-taupe">Vista previa del principio, para comprobar que es el archivo correcto.</p>
              </div>
            )}

            <div className="mt-4 flex items-center gap-2">
              <Boton variante="primario" tamano="sm" onClick={irAConfirmarPublicar} disabled={!archivoDoc}>Continuar →</Boton>
              <Boton variante="secundario" tamano="sm" onClick={cerrarPublicar}>Cancelar</Boton>
            </div>
          </div>
        ) : (
          <div>
            <div className="mb-4 rounded-control bg-hueso px-4 py-3 text-sm leading-relaxed text-tinta">
              <p>
                Esto creará <strong>la versión {numeroVersionNueva}</strong> de{" "}
                <strong>{tipoElegidoInfo?.nombre ?? tipoElegido}</strong>.
                La versión actual queda intacta como histórica.
              </p>
              {vigenteDelTipoElegido && (tipoElegidoInfo?.requiere_acuse ?? true) && vigenteDelTipoElegido.total_acuses > 0 && (
                <p className="mt-1">
                  <strong>{vigenteDelTipoElegido.total_acuses} {vigenteDelTipoElegido.total_acuses === 1 ? "persona" : "personas"}</strong> que
                  ya {vigenteDelTipoElegido.total_acuses === 1 ? "dejó" : "dejaron"} constancia de la versión anterior volverá
                  {vigenteDelTipoElegido.total_acuses === 1 ? "" : "n"} a aparecer como pendiente
                  {vigenteDelTipoElegido.total_acuses === 1 ? "" : "s"}.
                </p>
              )}
            </div>
            <div className="flex items-center gap-2">
              <Boton variante="primario" tamano="sm" onClick={() => void confirmarPublicar()} disabled={ocupadoPublicar} cargando={ocupadoPublicar}>
                Confirmar y publicar
              </Boton>
              <Boton variante="secundario" tamano="sm" onClick={() => setPasoPublicar(1)} disabled={ocupadoPublicar}>← Volver a editar</Boton>
            </div>
          </div>
        )}
      </Modal>

      {/* ── Confirmar restaurar ── */}
      <Modal abierto={restaurando !== null} onCerrar={() => setRestaurando(null)} titulo="Restaurar esta versión" ancho="sm" bloqueado={ocupadoRestaurar}>
        {restaurando && (
          <>
            <p className="mb-4 text-sm text-tinta">
              ¿Restaurar la versión {comoSeLlamaLaVersion(restaurando.etiqueta_version, restaurando.version)} como nueva
              versión vigente? Se creará una versión nueva con este mismo texto.
            </p>
            <div className="flex justify-end gap-2">
              <Boton variante="secundario" onClick={() => setRestaurando(null)} disabled={ocupadoRestaurar}>Cancelar</Boton>
              <Boton variante="primario" onClick={() => void confirmarRestaurar()} disabled={ocupadoRestaurar} cargando={ocupadoRestaurar}>
                Restaurar
              </Boton>
            </div>
          </>
        )}
      </Modal>
    </div>
  );
}

// ============================================================================
// Piezas de presentación
// ============================================================================

function TituloGrupo({ texto }: { texto: string }) {
  return (
    <div className="mb-3 flex items-baseline gap-2">
      <span className="text-xs font-semibold uppercase tracking-[0.08em] text-taupe">{texto}</span>
      <span className="h-px flex-1 bg-sand" />
    </div>
  );
}

function GrupoDocumentos({
  titulo, docs, puedeGestionar, onVer, onVerConstancias,
}: {
  titulo: string;
  docs: Doc[];
  puedeGestionar: boolean;
  onVer: (d: Doc) => void;
  onVerConstancias: (documentoId: string) => void;
}) {
  return (
    <div>
      <TituloGrupo texto={titulo} />
      <div className="space-y-3">
        {docs.map((d) => (
          <TarjetaInfo key={d.documento_id} id={`doc-${d.documento_id}`}>
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <h3 className="font-serif text-lg text-tinta">{d.titulo}</h3>
                <p className="mt-0.5 text-xs text-taupe">
                  {comoSeLlamaLaVersion(d.etiqueta_version, d.version)} · vigente desde {fechaCorta(d.vigente_desde)}
                </p>
              </div>
              <div className="flex flex-wrap items-center gap-2">
                <Insignia variante="positivo">Vigente</Insignia>
                {d.requiere_acuse && (d.mi_acuse_at
                  ? <Insignia variante="positivo">Constancia registrada</Insignia>
                  : <Insignia variante="advertencia">Pendiente de constancia</Insignia>)}
              </div>
            </div>
            <div className="mt-3 flex flex-wrap gap-4 text-xs font-medium">
              <button onClick={() => onVer(d)} className="text-rojo-profundo hover:underline">Ver documento →</button>
              {puedeGestionar && d.requiere_acuse && (
                <button onClick={() => onVerConstancias(d.documento_id)} className="text-rojo-profundo hover:underline">Ver constancias →</button>
              )}
              <a href={`/admin/normas/${d.documento_id}/imprimir`} target="_blank" rel="noopener" className="text-rojo-profundo hover:underline">
                Descargar PDF
              </a>
            </div>
          </TarjetaInfo>
        ))}
      </div>
    </div>
  );
}

function PanelDiff({ lineas }: { lineas: LineaDiff[] }) {
  return (
    <div className="mt-3 max-h-72 overflow-y-auto rounded-control bg-hueso px-3 py-2 font-mono text-[11px] leading-relaxed">
      {lineas.map((l, i) => (
        <div key={i}
          className={
            l.tipo === "agregada" ? "bg-verde/15 px-1"
            : l.tipo === "quitada" ? "bg-rojo/15 px-1 line-through decoration-rojo/60"
            : "px-1"
          }>
          {l.texto === "" ? " " : l.texto}
        </div>
      ))}
    </div>
  );
}

function ModalDocumentoContenido({
  doc, onCerrar, onVerConstancias, nombreDeclarado, onNombreDeclarado, msgConstancia, ocupadoAcuse, onAcusar, refNombre,
}: {
  doc: ModalDoc;
  onCerrar: () => void;
  onVerConstancias?: () => void;
  nombreDeclarado: string;
  onNombreDeclarado: (v: string) => void;
  msgConstancia: string | null;
  ocupadoAcuse: boolean;
  onAcusar: () => void;
  refNombre: React.RefObject<HTMLInputElement | null>;
}) {
  const bodyRef = useRef<HTMLDivElement | null>(null);
  const indice = useMemo(() => indiceDe(doc.documento), [doc.documento]);

  function irAEncabezado(orden: number) {
    const el = bodyRef.current?.querySelectorAll("h1,h2,h3,h4")[orden];
    el?.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  return (
    <div>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs text-taupe sm:grid-cols-3">
          <div>
            <dt className="inline">Tipo: </dt>
            <dd className="inline text-tinta">{NOMBRE_CATEGORIA[categoriaDe(doc.tipo, doc.requiere_acuse)]} · {doc.tipo_nombre}</dd>
          </div>
          <div><dt className="inline">Versión: </dt><dd className="inline text-tinta">{comoSeLlamaLaVersion(doc.etiqueta_version, doc.version)}</dd></div>
          <div><dt className="inline">Vigente desde: </dt><dd className="inline text-tinta">{fechaCorta(doc.vigente_desde)}</dd></div>
          <div><dt className="inline">Publicado: </dt><dd className="inline text-tinta">{selloLima(doc.publicado_at)}</dd></div>
          <div>
            <dt className="inline">Estado: </dt>
            <dd className="inline">{doc.esVigente ? <Insignia variante="positivo">Vigente</Insignia> : <Insignia atenuada>Histórica</Insignia>}</dd>
          </div>
          {doc.requiere_acuse && (
            <div>
              <dt className="inline">Constancias: </dt>
              <dd className="inline text-tinta">{doc.total_acuses}/{doc.poblacion}</dd>
            </div>
          )}
        </dl>
        <button onClick={onCerrar} aria-label="Cerrar" className="shrink-0 rounded-pildora border border-sand bg-papel p-1.5 text-taupe hover:text-tinta">
          <X size={16} strokeWidth={1.8} aria-hidden />
        </button>
      </div>

      <div className="mt-3 flex flex-wrap gap-4 text-xs font-medium">
        <a href={`/admin/normas/${doc.documento_id}/imprimir`} target="_blank" rel="noopener" className="text-rojo-profundo hover:underline">Descargar PDF</a>
        <a href={`/admin/normas/${doc.documento_id}/imprimir`} target="_blank" rel="noopener" className="text-rojo-profundo hover:underline">Imprimir</a>
        {onVerConstancias && doc.esVigente && (
          <button onClick={onVerConstancias} className="text-rojo-profundo hover:underline">Ver constancias</button>
        )}
      </div>

      {doc.esVigente && doc.requiere_acuse && (
        <div className="mt-4 rounded-control border border-sand bg-sand/20 p-3">
          {doc.mi_acuse_at ? (
            <p className="text-xs text-taupe">
              Dejaste constancia el <strong>{selloLima(doc.mi_acuse_at)}</strong>. No hace falta hacer nada más hasta
              que se publique una versión nueva.
            </p>
          ) : (
            <>
              <p className="mb-2 text-xs text-taupe">
                Dejar constancia significa que recibiste este documento y fuiste informada de su contenido. No es
                una firma de conformidad ni renuncia a nada.
              </p>
              {msgConstancia && (
                <p role="alert" className="mb-2 rounded border border-rojo/30 bg-rojo/10 px-2 py-1.5 text-xs text-rojo">
                  {msgConstancia}
                </p>
              )}
              <div className="flex flex-wrap items-end gap-2">
                <label className="flex flex-col gap-1 text-xs">
                  Tu nombre y apellido
                  <input ref={refNombre} value={nombreDeclarado} onChange={(e) => onNombreDeclarado(e.target.value)}
                    placeholder="como lo escribirías a mano" autoComplete="name" aria-invalid={msgConstancia !== null}
                    className={`w-64 rounded-control border bg-hueso px-3 py-2 text-base text-tinta sm:text-sm ${msgConstancia ? "border-rojo" : "border-sand"}`} />
                </label>
                <Boton variante="primario" tamano="sm" onClick={onAcusar} disabled={ocupadoAcuse} cargando={ocupadoAcuse}>
                  Dejar constancia
                </Boton>
              </div>
            </>
          )}
        </div>
      )}

      {indice.length > 1 && (
        <div className="mt-4 rounded-control bg-hueso px-4 py-3 text-sm">
          <span className="mb-2 block text-xs font-medium uppercase tracking-[0.06em] text-taupe">Índice</span>
          <ol className="grid gap-x-6 gap-y-1 sm:grid-cols-2">
            {indice.map((e, i) => (
              <li key={i} className={e.nivel === 3 ? "ml-3 text-xs" : "text-sm"}>
                <button onClick={() => irAEncabezado(e.orden)} className="text-left text-tinta hover:text-rojo-profundo hover:underline">
                  {e.texto}
                </button>
              </li>
            ))}
          </ol>
        </div>
      )}

      <div ref={bodyRef} className="mt-4 max-h-[50vh] overscroll-contain overflow-y-auto rounded-control border border-sand bg-crema/40 px-4 py-3">
        <Documento texto={doc.documento} />
      </div>
    </div>
  );
}

function ConstanciasTab({
  docsConAcuse, constanciaDocId, onElegir, cargando, filas, totalSinFiltrar, porSede, coberturaAnterior, docActual,
  busca, onBusca, filtroSede, onFiltroSede, filtroEstado, onFiltroEstado, onExportar,
  onRegistrarPapel, onVerCargo, papelPara, archivo, onArchivo, fechaPapel, onFechaPapel, notaPapel, onNotaPapel,
  msgPapel, progreso, ocupadoPapel, onGuardarPapel, onCancelarPapel, refCargo,
}: {
  docsConAcuse: Doc[];
  constanciaDocId: string | null;
  onElegir: (id: string) => void;
  cargando: boolean;
  filas: FilaAcuse[];
  totalSinFiltrar: number;
  porSede: { sede: string; completas: number; total: number }[];
  coberturaAnterior: { version: number; etiqueta: string | null; total: number; poblacion: number } | null;
  docActual: Doc | null;
  busca: string; onBusca: (v: string) => void;
  filtroSede: string; onFiltroSede: (v: string) => void;
  filtroEstado: "" | "registrada" | "pendiente"; onFiltroEstado: (v: "" | "registrada" | "pendiente") => void;
  onExportar: () => void;
  onRegistrarPapel: (persona: string, nombre: string) => void;
  onVerCargo: (path: string) => void;
  papelPara: { persona: string; nombre: string } | null;
  archivo: File | null; onArchivo: (f: File | null) => void;
  fechaPapel: string; onFechaPapel: (v: string) => void;
  notaPapel: string; onNotaPapel: (v: string) => void;
  msgPapel: string | null; progreso: number | null; ocupadoPapel: boolean;
  onGuardarPapel: () => void; onCancelarPapel: () => void;
  refCargo: React.RefObject<HTMLInputElement | null>;
}) {
  if (docsConAcuse.length === 0) {
    return (
      <EstadoVacio>Ningún documento pide constancia todavía.</EstadoVacio>
    );
  }

  const total = docActual ? docActual.total_acuses : filas.filter((f) => f.acusado_at !== null).length;
  const poblacion = docActual ? docActual.poblacion : totalSinFiltrar;
  const pct = poblacion > 0 ? Math.round((total / poblacion) * 100) : 0;
  const sedesUnicas = Array.from(new Set(porSede.map((s) => s.sede)));

  return (
    <div>
      <label className="mb-4 flex max-w-md flex-col gap-1 text-xs text-taupe">
        Documento
        <select value={constanciaDocId ?? ""} onChange={(e) => onElegir(e.target.value)} className={SELECT}>
          {docsConAcuse.map((d) => (
            <option key={d.documento_id} value={d.documento_id}>{d.titulo} · {comoSeLlamaLaVersion(d.etiqueta_version, d.version)}</option>
          ))}
        </select>
      </label>

      {cargando ? <Cargando texto="Reuniendo las constancias…" /> : (
        <>
          {/* UNA línea (variante D de la maqueta, 2026-10-20): el total en grande, una barra corta y una pastilla por sede. Antes eran una barra
              de ancho completo que repetía «17 / 17» y cuatro cajas que repetían lo mismo cuando todo estaba completo. El color de cada
              sede dice si le falta gente: verde completa, ámbar si falta poco, rojo si falta mucho. */}
          <TarjetaInfo className="mb-5 flex flex-wrap items-center gap-x-4 gap-y-2 px-4 py-3 sm:px-4 sm:py-3">
            {/* receta-propia: es el número de una línea con barra y pastillas, no una casilla; <Cifra> no cabe en un renglón */}
            <span className="font-serif text-2xl leading-none tabular-nums text-tinta">{total}/{poblacion}</span>
            <span className="text-sm text-taupe">recibidas</span>
            <div className="h-1.5 min-w-32 max-w-xs flex-1 overflow-hidden rounded-pildora bg-sand" role="progressbar" aria-valuenow={total} aria-valuemin={0} aria-valuemax={poblacion} aria-label="Constancias recibidas">
              <div className="h-full bg-verde transition-[width] duration-200" style={{ width: `${pct}%` }} />
            </div>
            {porSede.length > 0 && (
              <span className="flex flex-wrap items-center gap-1.5">
                {porSede.map((s) => (
                  <Insignia key={s.sede} tamano="sm" variante={s.completas === s.total ? "positivo" : s.total > 0 && s.completas / s.total >= 0.75 ? "advertencia" : "alerta"}>
                    {s.sede} {s.completas}/{s.total}
                  </Insignia>
                ))}
              </span>
            )}
          </TarjetaInfo>

          {coberturaAnterior && docActual && (
            <div className="mb-5 flex flex-wrap gap-6">
              <BarraCobertura etiqueta={`v${docActual.etiqueta_version ?? docActual.version}`} total={total} poblacion={poblacion} />
              <BarraCobertura
                etiqueta={`v${coberturaAnterior.etiqueta ?? coberturaAnterior.version} (anterior)`}
                total={coberturaAnterior.total} poblacion={coberturaAnterior.poblacion}
              />
            </div>
          )}

          <div className="mb-3 flex flex-wrap items-center gap-2">
            <label className="flex min-w-40 flex-1 items-center gap-2 rounded-control border border-sand bg-hueso px-3">
              <Search className="size-4 shrink-0 text-taupe" aria-hidden />
              <input type="search" value={busca} onChange={(e) => onBusca(e.target.value)} placeholder="Buscar persona…"
                aria-label="Buscar persona" className="w-full bg-transparent py-2 text-sm text-tinta outline-none placeholder:text-taupe/60" />
            </label>
            <select aria-label="Sede" value={filtroSede} onChange={(e) => onFiltroSede(e.target.value)} className={SELECT}>
              <option value="">Sede · todas</option>
              {sedesUnicas.map((s) => <option key={s} value={s}>{s}</option>)}
            </select>
            <select aria-label="Estado" value={filtroEstado} onChange={(e) => onFiltroEstado(e.target.value as "" | "registrada" | "pendiente")} className={SELECT}>
              <option value="">Estado · todos</option>
              <option value="registrada">Constancia registrada</option>
              <option value="pendiente">Pendiente de constancia</option>
            </select>
            <Boton variante="secundario" tamano="sm" onClick={onExportar}>Exportar CSV</Boton>
          </div>

          <Tabla>
            <TablaEncabezado>
              <Th>Persona</Th>
              <Th>Sede</Th>
              <Th>Estado</Th>
              <Th>Fecha</Th>
              <Th />
            </TablaEncabezado>
            <tbody>
              {filas.map((f) => (
                <Fragment key={f.persona_id}>
                  <Fila className="align-top">
                    <td className="px-4 py-2">{f.nombre}{!f.tiene_cuenta && <Insignia atenuada className="ml-2">sin cuenta</Insignia>}</td>
                    <td className="px-4 py-2 text-taupe">{f.sede}</td>
                    <td className="px-4 py-2">
                      {f.acusado_at !== null
                        ? <Insignia variante="positivo">Constancia registrada</Insignia>
                        : <Insignia variante="advertencia">Pendiente de constancia</Insignia>}
                    </td>
                    <td className="px-4 py-2 text-taupe">
                      {f.acusado_at ? <>{selloLima(f.acusado_at)} · {f.via === "papel" ? "en papel" : "desde el sistema"}</> : "—"}
                    </td>
                    <td className="px-4 py-2 text-right text-xs">
                      {f.acusado_at === null ? (
                        <button onClick={() => onRegistrarPapel(f.persona_id, f.nombre)} className="text-rojo-profundo hover:underline">
                          registrar en papel
                        </button>
                      ) : f.via === "papel" && f.storage_path ? (
                        <button onClick={() => onVerCargo(f.storage_path!)} className="text-rojo-profundo hover:underline">ver cargo</button>
                      ) : null}
                    </td>
                  </Fila>
                  {papelPara?.persona === f.persona_id && (
                    <tr>
                      <td colSpan={5} className="bg-sand/20 px-3 py-3">
                        <p className="mb-2 text-xs text-taupe">
                          Constancia en papel de <strong>{papelPara.nombre}</strong>. Sin el escaneo del cargo firmado
                          no se registra: aquí la constancia es la prueba.
                        </p>
                        {msgPapel && (
                          <p role="alert" className="mb-2 rounded border border-rojo/30 bg-rojo/10 px-2 py-1.5 text-xs text-rojo">{msgPapel}</p>
                        )}
                        <div className="grid gap-2 sm:grid-cols-2">
                          <label className="flex flex-col gap-1 text-xs">
                            Cargo firmado
                            <input ref={refCargo} type="file" accept={TIPOS_CARGO} onChange={(e) => onArchivo(e.target.files?.[0] ?? null)}
                              className={`rounded-control border bg-hueso px-3 py-2 text-sm file:mr-2 file:rounded file:border-0 file:bg-sand file:px-2 file:py-0.5 file:text-xs ${msgPapel ? "border-rojo" : "border-sand"}`} />
                            {archivo && (
                              <span className="text-[11px] text-taupe">{archivo.name} · {(archivo.size / 1048576).toFixed(1)} MB</span>
                            )}
                          </label>
                          <Campo etiqueta="Fecha de recepción" type="date" value={fechaPapel} max={hoyLima()} onChange={(e) => onFechaPapel(e.target.value)} />
                          <div className="sm:col-span-2">
                            <Campo etiqueta="Nota (opcional)" value={notaPapel} onChange={(e) => onNotaPapel(e.target.value)}
                              placeholder="ej. entregado en la tienda, con su líder de equipo presente" />
                          </div>
                        </div>
                        {progreso !== null && (
                          <div className="mt-2">
                            <div className="h-1.5 w-full overflow-hidden rounded-pildora bg-sand">
                              <div className="h-full bg-tinta transition-[width] duration-200" style={{ width: `${progreso}%` }} />
                            </div>
                            <span className="text-xs text-taupe">Subiendo — {progreso}%</span>
                          </div>
                        )}
                        <div className="mt-2 flex items-center gap-2">
                          <Boton variante="primario" tamano="sm" onClick={onGuardarPapel} disabled={ocupadoPapel}>
                            {progreso !== null ? `Subiendo… ${progreso}%` : "Registrar constancia"}
                          </Boton>
                          <Boton variante="secundario" tamano="sm" onClick={onCancelarPapel}>Cancelar</Boton>
                        </div>
                      </td>
                    </tr>
                  )}
                </Fragment>
              ))}
              {filas.length === 0 && (
                <tr><td colSpan={5} className="px-3 py-6 text-center text-taupe">Nadie coincide con la búsqueda o los filtros.</td></tr>
              )}
            </tbody>
          </Tabla>
        </>
      )}
    </div>
  );
}

function BarraCobertura({ etiqueta, total, poblacion }: { etiqueta: string; total: number; poblacion: number }) {
  const pct = poblacion > 0 ? Math.round((total / poblacion) * 100) : 0;
  return (
    <div className="min-w-40 flex-1">
      <div className="mb-1 flex justify-between text-xs text-taupe">
        <span>{etiqueta}</span>
        <span>{total}/{poblacion}</span>
      </div>
      <div className="h-1.5 w-full overflow-hidden rounded-pildora bg-sand">
        <div className="h-full bg-pizarra" style={{ width: `${pct}%` }} />
      </div>
    </div>
  );
}
