"use client";

// ============================================================================
// Bandeja — todo lo que requiere atención del equipo, en un solo lugar.
// ----------------------------------------------------------------------------
// QUÉ PROMETE. Diez módulos ya saben, cada uno, cuándo algo suyo necesita a una
// persona. Esta pantalla no inventa un criterio nuevo de "pendiente": pide las
// mismas fuentes que usa cada módulo, a través de `lib/admin/bandeja-fuentes.ts`
// —la MISMA lista de la que salen el número del menú y el de Equipo— y las
// junta. Si un pendiente se arregla en su módulo, a la próxima carga ya no está.
//
// QUÉ NO HACE. No resuelve nada que ya tenga su propio formulario: enlaza a la
// persona en su módulo. Seis tipos sí se resuelven aquí mismo porque son una
// sola RPC con un texto o una fecha: las tres revisiones pedidas («marcar
// atendida»), las solicitudes de vacaciones, las de cambio de perfil y el bono
// de cumpleaños que alguien pidió («Ya se lo transferí», 0478).
//
// A quién se le muestra. Lo decide la base: la encargada recibe solo lo de su
// sede. Aquí `puede*` decide qué se PIDE y qué categorías se pintan.
//
// ── Rediseño 2 (2026-09-15, decidido con Felipe sobre una maqueta) ──────────
// Con los datos de un día normal la Bandeja solo mostraba Educación, y no se
// distinguía «Contratos está al día» de «Contratos no se revisa aquí». Ahora:
//
//   · Arriba, una tarjeta por cada módulo que esta persona puede ver, TAMBIÉN
//     las que están en cero («Al día»). Un clic filtra. Si la consulta de un
//     módulo falló, su tarjeta lo dice: no se pinta «Al día» sobre un hueco.
//   · Se suman Contratos, Correcciones (días y marcas por revisar), Disciplina,
//     Documentación (ruta y bono) y Feriados. Ver ADR 0003.
//   · La lista sigue ordenada por urgencia (Vencido / Hoy / Próximos / Sin
//     plazo). Se quitan las pestañas «Resolver aquí / En otra pantalla»: cada
//     fila ya dice si se resuelve aquí.
// ============================================================================

import { useCallback, useEffect, useMemo, useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import {
  CalendarCheck, Clock, FileSignature, Gavel, GraduationCap, HandCoins, Hourglass, IdCard, Inbox, MessagesSquare, PencilLine, ScrollText, Search,
  ShieldCheck, TreePalm, type LucideIcon,
} from "lucide-react";
import { Cargando } from "@/components/cargando";
import { Boton } from "@/components/ui/boton";
import { AyudaPantalla } from "@/components/ui/ayuda-pantalla";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { sobretituloDeHoy } from "@/lib/admin/sobretitulo";
import { cx } from "@/components/ui/cx";
import { useToast } from "@/components/toast";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { BUCKET_SOLICITUDES_PERFIL } from "@/lib/foto-dni";
import { diaYMes } from "@/lib/bandeja-mia";
import { sinTildes } from "@/lib/sin-tildes";
import {
  avisarCambioEnBandeja, GRUPOS_URGENCIA, type GrupoUrgencia, type Urgencia,
} from "@/lib/admin/bandeja-urgencia";
import {
  alertasConProblema, armarPendientes, diaLima, ETIQUETA_MODULO, FUENTES_VACIAS, modulosDeLaBandeja,
  resumenValorPerfil, traerFuentesBandeja, type FuentesBandeja, type ModuloBandeja, type Pendiente, type TipoItemVisto,
} from "@/lib/admin/bandeja-fuentes";
import { hoyLima, puedeOperarEquipo, puedeVerIdentidad, puedeVerPlanilla, puedeVerSaludDeAlertas, puedeVerTodasLasSedes } from "@cayla-dynamic/shared";
import { TarjetaSistema } from "@/components/bandeja/tarjeta-sistema";
import { PanelPrueba } from "@/components/pruebas/panel-prueba";
import { textoDeHoras } from "@/lib/admin/pruebas";
import { resumenNormasPendientes, type ResumenNormas } from "@/lib/admin/bandeja-equipo";

const CLAVE_SEDE_FILTRO = "bandeja_sede_filtro";

interface Sede { codigo: string; nombre: string; activa: boolean }

/** El ícono de cada módulo es el MISMO del menú (nav-items.ts). */
const ICONO_MODULO: Record<ModuloBandeja, LucideIcon> = {
  contratos: ScrollText,
  correcciones: PencilLine,
  disciplina: Gavel,
  documentacion: FileSignature,
  feriados: CalendarCheck,
  educacion: GraduationCap,
  ausencias: TreePalm,
  horarios: Clock,
  datos_personales: IdCard,
  liquidaciones: HandCoins,
  seguros: ShieldCheck,
  casos: MessagesSquare,
  pruebas: Hourglass,
};

// Columnas de la fila en ancho completo. Literal, no armado: Tailwind solo ve
// clases que aparecen enteras en el código.
const COLUMNAS = "@3xl:grid-cols-[minmax(9rem,1.1fr)_minmax(14rem,2.4fr)_9.5rem_11rem_minmax(8rem,auto)]";

/** El grupo también se dice con FORMA, no solo con color: cuadro lleno, medio círculo, anillo, raya. */
function MarcaGrupo({ grupo }: { grupo: GrupoUrgencia }) {
  const forma: Record<GrupoUrgencia, string> = {
    vencido: "size-2 rounded-[2px] bg-rojo",
    hoy: "size-2 rounded-full border-[1.5px] border-ambar bg-[linear-gradient(90deg,var(--color-ambar)_50%,transparent_50%)]",
    proximo: "size-2 rounded-full border-[1.5px] border-pizarra",
    sin_plazo: "h-0.5 w-2.5 bg-taupe",
  };
  return <span aria-hidden className={cx("inline-block shrink-0", forma[grupo])} />;
}

function InsigniaPlazo({ urgencia }: { urgencia: Urgencia }) {
  const tono: Record<GrupoUrgencia, string> = {
    vencido: "bg-rojo/10 text-rojo-profundo",
    hoy: "bg-ambar/15 text-ambar",
    proximo: "bg-pizarra/15 text-pizarra",
    sin_plazo: "bg-sand text-tinta",
  };
  return (
    <span className={cx("inline-flex items-center gap-1.5 whitespace-nowrap rounded-full px-2 py-0.5 text-xs font-medium", tono[urgencia.grupo])}>
      <MarcaGrupo grupo={urgencia.grupo} />
      {urgencia.plazo}
    </span>
  );
}

/** Insignia "Nuevo desde tu última visita" (bandeja_vistos, 0436). */
function InsigniaNuevo() {
  return <span className="rounded-full bg-rojo/15 px-2 py-0.5 text-xs font-medium text-rojo">Nuevo</span>;
}

/** Una tarjeta de categoría: un módulo (o «Todo»), su conteo y qué tan urgente está. */
function TarjetaCategoria({
  id, etiqueta, Icon, n, vencidos, hoy, fallo, activa, onClick,
}: {
  id: string; etiqueta: string; Icon: LucideIcon; n: number; vencidos: number; hoy: number;
  fallo: boolean; activa: boolean; onClick: () => void;
}) {
  const alDia = n === 0 && !fallo;
  const sub = fallo ? "No se pudo cargar"
    : alDia ? "Al día"
    : vencidos > 0 ? `${vencidos} vencido${vencidos === 1 ? "" : "s"}`
    : hoy > 0 ? `${hoy} para hoy`
    : "sin urgencia";
  return (
    <button
      id={id}
      type="button"
      aria-pressed={activa}
      title={alDia ? `${etiqueta}: nada pendiente` : activa ? "Ver todo" : `Ver solo ${etiqueta}`}
      onClick={onClick}
      className={cx(
        "flex items-center gap-2 rounded-control border px-3 py-1.5 text-left transition-colors duration-150",
        activa ? "border-tinta bg-papel ring-1 ring-tinta"
          : alDia ? "border-dashed border-sand hover:border-taupe/60"
          : "border-sand bg-papel hover:border-taupe/60",
      )}
    >
      <Icon className="size-4 shrink-0 text-taupe" aria-hidden />
      <span className="text-sm font-medium text-tinta">{etiqueta}</span>
      <span className={cx("text-base font-medium tabular-nums", alDia ? "text-taupe" : "text-tinta")}>{fallo ? "—" : n}</span>
      <span className={cx("text-xs",
        fallo ? "font-medium text-rojo-profundo"
          : alDia ? "text-verde"
          : vencidos > 0 ? "font-medium text-rojo-profundo"
          : "text-taupe")}
      >
        {sub}
      </span>
    </button>
  );
}

export default function BandejaPage() {
  const router = useRouter();
  const persona = usePersonaActual();
  const rol = persona?.rol ?? null;
  const { avisar } = useToast();

  const puedeEntrar = puedeVerPlanilla(rol) || puedeOperarEquipo(rol);
  // ALCANCE, no permiso: la encargada ya recibe solo su sede, así que no se le
  // ofrece un filtro que no tiene nada que filtrar.
  const puedeTodasLasSedes = puedeVerTodasLasSedes(rol);
  const modulos = useMemo(() => modulosDeLaBandeja(rol), [rol]);

  const [cargando, setCargando] = useState(true);
  const [fuentes, setFuentes] = useState<FuentesBandeja>(FUENTES_VACIAS);
  const [sedes, setSedes] = useState<Sede[]>([]);
  const [ceses, setCeses] = useState<Map<string, string>>(new Map());
  const [vistosIniciales, setVistosIniciales] = useState<Set<string>>(new Set());
  // El enlace compacto de Normas (0460): no es un ítem de esta cola —no se
  // "resuelve" desde acá, se resuelve dejando constancia en Normas— así que
  // se carga aparte de `cargar()` y se pinta como una línea, no como una
  // sección con tabla. Ver `lib/admin/bandeja-equipo.ts`.
  const [normas, setNormas] = useState<ResumenNormas | null>(null);

  // Lo que se escribe en el desplegable de cada fila, por clave de pendiente.
  const [textos, setTextos] = useState<Record<string, string>>({});
  // La fecha de cada transferencia por confirmar. Nace en HOY y no en "": es lo
  // más probable, y un campo de fecha vacío que bloquea el envío es la regla
  // quinta de CLAUDE.md. Lo que se ve y lo que se manda es la MISMA expresión.
  const [fechas, setFechas] = useState<Record<string, string>>({});
  const [errores, setErrores] = useState<Record<string, string>>({});
  const [ocupado, setOcupado] = useState<string | null>(null);
  const [abierta, setAbierta] = useState<string | null>(null);
  const [saliendo, setSaliendo] = useState<Set<string>>(new Set());

  const [busca, setBusca] = useState("");
  const [sedeFiltro, setSedeFiltro] = useState<string | null>(null);
  const [moduloFiltro, setModuloFiltro] = useState<ModuloBandeja | null>(null);
  const [grupoFiltro, setGrupoFiltro] = useState<GrupoUrgencia | null>(null);

  useEffect(() => {
    try {
      const guardado = window.localStorage.getItem(CLAVE_SEDE_FILTRO);
      // eslint-disable-next-line react-hooks/set-state-in-effect -- leer localStorage al montar, mismo patrón ya aceptado en `cargar` más abajo.
      if (guardado) setSedeFiltro(guardado);
    } catch { /* localStorage puede fallar en modo privado — se sigue sin filtro. */ }
  }, []);

  function elegirSedeFiltro(s: string | null) {
    setSedeFiltro(s);
    try {
      if (s) window.localStorage.setItem(CLAVE_SEDE_FILTRO, s);
      else window.localStorage.removeItem(CLAVE_SEDE_FILTRO);
    } catch { /* preferencia de UI, no un dato de negocio: si no se guarda, no pasa nada. */ }
  }

  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    if (!rol) return;

    const [f] = await Promise.all([
      traerFuentesBandeja(supabase, rol, (que, error) =>
        avisar("error", mensajeDeError(error as Parameters<typeof mensajeDeError>[0], `cargar ${que}`))),
      // bandeja_vistos (0436). Falla suave — sin ella, todo se ve sin «Nuevo».
      supabase.from("bandeja_vistos").select("tipo_item,item_id").then(({ data }) => {
        setVistosIniciales(new Set<string>((data ?? []).map((v) => `${v.tipo_item}:${v.item_id}`)));
      }),
      // Quién ya cesó, para «Cesó el …». Falla suave: sin ella nadie se marca
      // como cesado, que es el lado seguro (nada baja de urgencia por error).
      supabase.rpc("fn_personas_funciones").then(({ data }) => {
        const filas = (data as { persona_id: string; fecha_cese: string | null }[] | null) ?? [];
        setCeses(new Map(filas.filter((x) => x.fecha_cese).map((x) => [x.persona_id, x.fecha_cese as string] as const)));
      }),
      // Las opciones del filtro salen de la tabla (regla #3 de este repo),
      // no de lo que trajo la carga: una sede sin pendientes también existe.
      puedeTodasLasSedes
        ? supabase.from("sedes").select("codigo, nombre, activa").order("codigo").then(({ data }) => {
            setSedes((data as Sede[] | null) ?? []);
          })
        : Promise.resolve(),
    ]);
    setFuentes(f);
    setCargando(false);
  }, [router, rol, puedeTodasLasSedes, avisar]);

  // eslint-disable-next-line react-hooks/set-state-in-effect -- cargar al montar, mismo patrón que el resto del panel.
  useEffect(() => { void cargar(); }, [cargar]);

  // El enlace compacto de Normas (0460) se carga aparte de `cargar()`: no es
  // una fuente de `traerFuentesBandeja` (no encaja en la forma `Pendiente`),
  // así que no tiene sentido bloquear la carga principal por él.
  useEffect(() => {
    if (!rol) return;
    void (async () => {
      const supabase = createAdminSupabaseClient();
      const r = await resumenNormasPendientes(supabase, rol);
      setNormas(r);
    })();
  }, [rol]);

  // Marcar visto lo que lleva «Nuevo», una vez que terminó de cargar — la
  // insignia de esta visita ya se calculó con vistosIniciales.
  useEffect(() => {
    if (cargando) return;
    const supabase = createAdminSupabaseClient();
    const items: Array<[TipoItemVisto, string]> = [
      ...fuentes.revisiones.map((r): [TipoItemVisto, string] => ["revision", r.id]),
      ...fuentes.revisionesMovilidad.map((r): [TipoItemVisto, string] => ["revision_movilidad", r.id]),
      ...fuentes.revisionesContrato.map((r): [TipoItemVisto, string] => ["revision_contrato", r.id]),
      ...fuentes.solicitudesVacaciones.map((s): [TipoItemVisto, string] => ["solicitud_vacacion", s.id]),
      ...fuentes.solicitudesPerfil.map((s): [TipoItemVisto, string] => ["solicitud_perfil", s.id]),
      ...fuentes.entregasEducacion.map((e): [TipoItemVisto, string] => ["entrega_educacion", e.id]),
      ...fuentes.avisosFinEducacion.map((a): [TipoItemVisto, string] => ["aviso_fin_educacion", a.id]),
    ];
    for (const [tipo, id] of items) {
      if (!vistosIniciales.has(`${tipo}:${id}`)) {
        // `supabase.rpc(...)` sola NO dispara nada: postgrest-js solo hace el
        // fetch dentro de `.then()` (PostgrestBuilder#then). Sin ese `.then()`
        // —o un `await`— esto arma la petición y la descarta en silencio: ni
        // error, ni red, ni consola. Medido el 2026-09-16: esta línea llevaba
        // así desde la 0436 y nunca marcó un solo «visto» en producción.
        void supabase.rpc("fn_bandeja_marcar_visto", { p_tipo_item: tipo, p_item_id: id })
          .then(() => {}, () => {});
      }
    }
    // Solo cuando termina de cargar: una vez por visita.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cargando]);

  const hoy = hoyLima();
  const pendientes = useMemo(
    () => armarPendientes(fuentes, { hoy, ceses, vistos: vistosIniciales }),
    [fuentes, hoy, ceses, vistosIniciales],
  );

  // ── Filtros ───────────────────────────────────────────────────────────────
  // El filtro guardado de sede no aplica a quien solo ve la suya.
  const sedeEfectiva = puedeTodasLasSedes ? sedeFiltro : null;
  const q = sinTildes(busca.trim());
  const coincideTexto = (p: Pendiente) => q === "" || sinTildes(p.persona).includes(q) || sinTildes(p.titulo).includes(q);
  // Lo que cuentan las tarjetas: todos los filtros MENOS el de módulo, que es
  // justo lo que las tarjetas eligen.
  const paraTarjetas = pendientes.filter((p) =>
    coincideTexto(p) && (!sedeEfectiva || p.sede === sedeEfectiva) && (!grupoFiltro || p.urgencia.grupo === grupoFiltro));
  const filtrados = paraTarjetas.filter((p) => !moduloFiltro || p.modulo === moduloFiltro);
  const hayFiltros = q !== "" || !!sedeEfectiva || moduloFiltro !== null || grupoFiltro !== null;
  const porSedeSinSede = pendientes.filter((p) => coincideTexto(p) && (!moduloFiltro || p.modulo === moduloFiltro) && (!grupoFiltro || p.urgencia.grupo === grupoFiltro));

  // Las sedes activas de la tabla, más cualquier sede con pendientes aunque ya
  // no esté activa (quien sigue asignada a una sede cerrada no desaparece).
  const opcionesSede = useMemo(() => {
    const codigos = new Set(sedes.filter((s) => s.activa).map((s) => s.codigo));
    for (const p of pendientes) if (p.sede && p.sede !== "—" && p.sede !== "?") codigos.add(p.sede);
    if (sedeFiltro) codigos.add(sedeFiltro);
    return Array.from(codigos).sort().map((codigo) => ({
      codigo,
      nombre: sedes.find((s) => s.codigo === codigo)?.nombre ?? null,
    }));
  }, [sedes, pendientes, sedeFiltro]);

  function limpiarFiltros() {
    setBusca("");
    elegirSedeFiltro(null);
    setModuloFiltro(null);
    setGrupoFiltro(null);
  }

  const problemasCorreo = alertasConProblema(fuentes.resumenAlertas);
  const resumenAlertas = fuentes.resumenAlertas;
  const alDia = modulos.filter((m) => !fuentes.fallidas.includes(m) && !paraTarjetas.some((p) => p.modulo === m)).length;

  // ── Resolver ──────────────────────────────────────────────────────────────
  /** La fila se desvanece, sale de la lista y el menú vuelve a contar. */
  function retirar(p: Pendiente, mensaje: string) {
    setSaliendo((s) => new Set(s).add(p.clave));
    setAbierta(null);
    const quedaEnModulo = pendientes.some((x) => x.modulo === p.modulo && x.clave !== p.clave);
    avisar("ok", quedaEnModulo ? mensaje : `${mensaje} ${ETIQUETA_MODULO[p.modulo]} quedó al día.`);
    avisarCambioEnBandeja();
    window.setTimeout(() => {
      setFuentes((f) => {
        const fuera = <T extends { id: string }>(xs: T[]) => xs.filter((x) => x.id !== p.itemId);
        switch (p.tipo) {
          case "revision": return { ...f, revisiones: fuera(f.revisiones) };
          case "revision_movilidad": return { ...f, revisionesMovilidad: fuera(f.revisionesMovilidad) };
          case "revision_contrato": return { ...f, revisionesContrato: fuera(f.revisionesContrato) };
          case "solicitud_vacacion": return { ...f, solicitudesVacaciones: fuera(f.solicitudesVacaciones) };
          case "solicitud_perfil": return { ...f, solicitudesPerfil: fuera(f.solicitudesPerfil) };
          case "bono_por_transferir":
            return { ...f, bonosPorTransferir: f.bonosPorTransferir.filter((x) => x.documento_id !== p.itemId) };
          default: return f;
        }
      });
      setSaliendo((s) => { const n = new Set(s); n.delete(p.clave); return n; });
    }, 220);
  }

  async function atender(p: Pendiente) {
    const supabase = createAdminSupabaseClient();
    const respuesta = (textos[p.clave] ?? "").trim() || null;
    setOcupado(p.clave);
    const { error } = p.tipo === "revision"
      ? await supabase.rpc("fn_atender_revision", { p_id: p.itemId, p_respuesta: respuesta })
      : p.tipo === "revision_movilidad"
        ? await supabase.rpc("fn_atender_revision_movilidad", { p_id: p.itemId, p_respuesta: respuesta })
        : await supabase.rpc("fn_atender_revision_contrato", { p_id: p.itemId, p_respuesta: respuesta });
    setOcupado(null);
    if (error) { avisar("error", mensajeDeError(error, "marcar la revisión como atendida")); return; }
    retirar(p, `Revisión atendida — ${p.persona} verá tu respuesta.`);
  }

  async function resolver(p: Pendiente, aprobar: boolean) {
    const motivo = (textos[p.clave] ?? "").trim();
    // La base también lo exige; decirlo antes evita un error después del clic.
    if (!aprobar && motivo === "") {
      setErrores((e) => ({ ...e, [p.clave]: "Escribe el motivo del rechazo: lo va a leer la persona." }));
      return;
    }
    setErrores((e) => { const n = { ...e }; delete n[p.clave]; return n; });
    const supabase = createAdminSupabaseClient();
    setOcupado(p.clave);
    const { error } = p.tipo === "solicitud_vacacion"
      ? await supabase.rpc("fn_resolver_solicitud_vacaciones", { p_id: p.itemId, p_aprobar: aprobar, p_respuesta: motivo || null })
      : await supabase.rpc("fn_resolver_solicitud_perfil", { p_id: p.itemId, p_aprobar: aprobar, p_motivo: motivo || undefined });
    setOcupado(null);
    if (error) { avisar("error", mensajeDeError(error, aprobar ? "aprobar la solicitud" : "rechazar la solicitud")); return; }
    const que = p.tipo === "solicitud_vacacion" ? (aprobar ? "Vacaciones aprobadas" : "Solicitud rechazada") : (aprobar ? "Cambio aprobado" : "Solicitud rechazada");
    retirar(p, `${que} — ${p.persona}.`);
  }

  async function confirmarTransferencia(p: Pendiente, fecha: string) {
    if (!fecha) {
      setErrores((e) => ({ ...e, [p.clave]: "Elige la fecha en que salió la transferencia." }));
      return;
    }
    setErrores((e) => { const n = { ...e }; delete n[p.clave]; return n; });
    const supabase = createAdminSupabaseClient();
    setOcupado(p.clave);
    const { error } = await supabase.rpc("fn_confirmar_entrega_bono", { p_documento_id: p.itemId, p_fecha: fecha });
    setOcupado(null);
    if (error) { avisar("error", mensajeDeError(error, "confirmar la transferencia")); return; }
    retirar(p, `Transferencia confirmada — ${p.persona} lo verá en su Info.`);
  }

  /** El bucket es privado: cada documento se abre con una URL firmada, pedida
   *  al momento de mirar — nunca se firman todos de golpe. */
  async function verDocumentoPerfil(ruta: string) {
    const supabase = createAdminSupabaseClient();
    const { data, error } = await supabase.storage.from(BUCKET_SOLICITUDES_PERFIL).createSignedUrl(ruta, 300);
    if (error || !data) { avisar("error", "No se pudo abrir el documento."); return; }
    window.open(data.signedUrl, "_blank", "noopener,noreferrer");
  }

  // ── Piezas ────────────────────────────────────────────────────────────────
  function desplegable(p: Pendiente): ReactNode {
    const texto = textos[p.clave] ?? "";
    const escribir = (v: string) => setTextos((t) => ({ ...t, [p.clave]: v }));
    const contexto = p.contexto && (
      <Link href={p.contexto.href} className="text-sm text-rojo hover:underline">{p.contexto.texto} →</Link>
    );

    // La prueba de tres días (0536): el MISMO panel que usa Contratos, para que la líder de
    // equipo —que no abre Contratos— pueda decidir sobre su gente desde aquí.
    if (p.tipo === "prueba") {
      const prueba = fuentes.pruebas.find((x) => x.persona_id === p.itemId);
      if (!prueba) return null;
      return (
        <PanelPrueba
          fila={prueba} supabase={createAdminSupabaseClient()} rol={rol}
          alCambiar={() => { setAbierta(null); void cargar(); }}
        />
      );
    }
    if (p.tipo === "prueba_cierre") {
      const cierre = fuentes.cierresPruebas.find((x) => x.prueba_id === p.itemId);
      if (!cierre) return null;
      return (
        <div className="flex flex-col gap-1 text-sm">
          <p>
            «{cierre.motivo}» · {cierre.decidida_por ? `decidió ${cierre.decidida_por}` : "decidió una persona que ya no figura"}
            {" "}el {diaLima(cierre.cerrada_at)}
          </p>
          <p className="text-taupe">
            Último día trabajado: {diaYMes(cierre.cerrada_fecha)} · {cierre.dias_trabajados} {cierre.dias_trabajados === 1 ? "día" : "días"} ·
            {" "}{textoDeHoras(cierre.horas_marcadas)} marcadas{cierre.resultado === "retirado" ? ", que no se pagan" : ", que se pagan"}.
          </p>
          <p className="text-xs text-taupe">
            Si fue un error, se corrige reactivando a la persona desde Equipo: queda rastro de quién y cuándo.
          </p>
        </div>
      );
    }

    if (p.tipo === "revision" || p.tipo === "revision_movilidad" || p.tipo === "revision_contrato") {
      return (
        <div className="flex flex-col gap-2">
          {p.detalle && <p className="text-sm">{p.detalle}</p>}
          <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
            <div className="flex-1">
              <Campo id={`respuesta-${p.clave}`} value={texto} onChange={(e) => escribir(e.target.value)}
                placeholder="En qué quedó (lo va a leer la persona)" aria-label="Respuesta para la persona" />
            </div>
            <Boton variante="primario" onClick={() => void atender(p)} cargando={ocupado === p.clave} className="w-full sm:w-auto">
              Marcar atendida
            </Boton>
          </div>
          {contexto}
        </div>
      );
    }

    if (p.tipo === "bono_por_transferir") {
      const fecha = fechas[p.clave] ?? hoy;
      return (
        <div className="flex flex-col gap-2">
          <p className="text-sm">
            Ya firmó su constancia al pedirlo. Cuando la transferencia salga del banco, confírmala aquí
            con su fecha: hasta entonces este aviso no se va, y {p.persona} lo ve como pedido en su Info.
          </p>
          <div className="flex flex-col gap-2 sm:flex-row sm:items-end">
            <Campo
              id={`fecha-${p.clave}`} etiqueta="Fecha de la transferencia" type="date"
              value={fecha} max={hoy} error={errores[p.clave]} className="sm:w-44"
              onChange={(e) => setFechas((f) => ({ ...f, [p.clave]: e.target.value }))}
            />
            <Boton variante="primario" onClick={() => void confirmarTransferencia(p, fecha)} cargando={ocupado === p.clave}
              className="w-full sm:w-auto">
              Ya se lo transferí
            </Boton>
          </div>
          {contexto}
        </div>
      );
    }

    const solicitudPerfil = p.tipo === "solicitud_perfil" ? fuentes.solicitudesPerfil.find((s) => s.id === p.itemId) : undefined;
    return (
      <div className="flex flex-col gap-2">
        {p.tipo === "solicitud_vacacion" && p.detalle?.startsWith("«") && <p className="text-sm">{p.detalle}</p>}
        {solicitudPerfil && (
          <div className="text-sm">
            <p className="text-taupe">de: {resumenValorPerfil(solicitudPerfil.valor_anterior)}</p>
            <p>a: {resumenValorPerfil(solicitudPerfil.valor_propuesto)}</p>
            {solicitudPerfil.rutas_adjuntas.length > 0 && (
              <div className="mt-1 flex flex-wrap gap-3">
                {solicitudPerfil.rutas_adjuntas.map((ruta, i) => (
                  <button key={ruta} type="button" onClick={() => void verDocumentoPerfil(ruta)} className="text-sm text-rojo hover:underline">
                    Ver documento{solicitudPerfil.rutas_adjuntas.length > 1 ? ` ${i + 1}` : ""} →
                  </button>
                ))}
              </div>
            )}
          </div>
        )}
        {/* Se muestra igual a la encargada —si no, su equipo esperaría algo que
            ella no ve— pero sin botones cuando el campo es de DO (0405). */}
        {solicitudPerfil?.solo_do && !puedeVerIdentidad(rol) ? (
          <p className="rounded-control border border-pizarra/30 bg-pizarra/10 px-3 py-2 text-sm text-pizarra">
            Esta solicitud cambia el número de documento: la resuelve Desarrollo Organizacional. Avísales para que la revisen.
          </p>
        ) : (
          <div className="flex flex-col gap-2 sm:flex-row sm:items-start">
            <div className="flex-1">
              <Campo id={`motivo-${p.clave}`} value={texto} error={errores[p.clave]}
                onChange={(e) => { escribir(e.target.value); if (errores[p.clave]) setErrores((x) => { const n = { ...x }; delete n[p.clave]; return n; }); }}
                placeholder="Motivo si rechazas (lo va a leer la persona)" aria-label="Motivo del rechazo" />
            </div>
            <div className="flex gap-2">
              <Boton variante="primario" onClick={() => void resolver(p, true)} cargando={ocupado === p.clave} className="flex-1 sm:flex-none">
                Aprobar
              </Boton>
              <Boton variante="peligro" onClick={() => void resolver(p, false)} disabled={ocupado === p.clave} className="flex-1 sm:flex-none">
                Rechazar
              </Boton>
            </div>
          </div>
        )}
        {contexto}
      </div>
    );
  }

  function fila(p: Pendiente) {
    const Icon = ICONO_MODULO[p.modulo];
    const estaAbierta = abierta === p.clave;
    const soloVer = p.tipo === "solicitud_perfil"
      && !!fuentes.solicitudesPerfil.find((s) => s.id === p.itemId)?.solo_do && !puedeVerIdentidad(rol);
    const verbo = soloVer ? "Ver"
      : p.tipo === "solicitud_vacacion" || p.tipo === "solicitud_perfil" ? "Resolver"
      : p.tipo === "bono_por_transferir" ? "Confirmar"
      : p.tipo === "prueba" ? "Decidir"
      : p.tipo === "prueba_cierre" ? "Ver"
      : "Atender";
    return (
      <li
        key={p.clave}
        className={cx(
          "rounded-control border border-sand bg-papel transition-[opacity,transform,border-color,box-shadow] duration-200 motion-reduce:transition-none",
          p.urgencia.grupo === "vencido" && "border-l-[3px] border-l-rojo",
          estaAbierta && "border-taupe/60 shadow-sm",
          !estaAbierta && "hover:border-taupe/40",
          saliendo.has(p.clave) && "translate-x-3 opacity-0",
        )}
      >
        <div className={cx("grid grid-cols-[1fr_auto] items-center gap-x-4 gap-y-1.5 px-4 py-3", COLUMNAS)}>
          {/* Quién */}
          <div className="min-w-0">
            <div className="flex flex-wrap items-center gap-1.5">
              <span className="font-medium text-tinta">{p.persona}</span>
              {p.nuevo && <InsigniaNuevo />}
              {p.cesoEl && (
                <span className="rounded-full bg-sand px-2 py-0.5 text-xs text-tinta">Cesó el {diaYMes(p.cesoEl)}</span>
              )}
            </div>
            <div className="text-xs text-taupe">{p.sede}</div>
          </div>
          {/* Qué */}
          <div className="col-span-2 min-w-0 @3xl:col-span-1">
            <div className="text-sm text-tinta">{p.titulo}</div>
            <div className="line-clamp-2 text-xs text-taupe">
              {p.detalle}
              {p.resolucion === "aqui" && (
                <>{p.detalle ? " · " : ""}<span className="rounded-full border border-sand px-1.5 text-[11px]">se resuelve aquí</span></>
              )}
            </div>
          </div>
          {/* De qué módulo */}
          <div className="flex items-center gap-1.5 text-xs text-taupe">
            <Icon className="size-3.5 shrink-0" aria-hidden />
            {ETIQUETA_MODULO[p.modulo]}
          </div>
          {/* Cuándo — en teléfono sube a la primera línea, junto al nombre */}
          <div className="col-start-2 row-start-1 flex flex-col items-end gap-0.5 @3xl:col-start-auto @3xl:row-start-auto @3xl:items-start">
            <InsigniaPlazo urgencia={p.urgencia} />
            {p.urgencia.nota && <span className="text-[11px] text-taupe">{p.urgencia.nota}</span>}
          </div>
          {/* Qué hago ahora */}
          <div className="flex justify-end">
            {p.resolucion === "aqui" ? (
              <Boton
                variante={estaAbierta ? "secundario" : "primario"}
                tamano="sm"
                aria-expanded={estaAbierta}
                aria-controls={`desplegable-${p.clave}`}
                onClick={() => setAbierta(estaAbierta ? null : p.clave)}
              >
                {estaAbierta ? "Cerrar" : verbo}
              </Boton>
            ) : p.ir ? (
              <Link href={p.ir.href} className="whitespace-nowrap rounded-control px-1 text-sm font-medium text-rojo hover:underline">
                {p.ir.texto} →
              </Link>
            ) : null}
          </div>
        </div>
        {estaAbierta && (
          <div id={`desplegable-${p.clave}`} className="border-t border-dashed border-sand px-4 pb-4 pt-3">
            {desplegable(p)}
          </div>
        )}
      </li>
    );
  }

  const vencidosTotal = paraTarjetas.filter((p) => p.urgencia.grupo === "vencido").length;
  const moduloActivo = moduloFiltro ? ETIQUETA_MODULO[moduloFiltro] : null;

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6">
        <CabeceraPagina
          sobretitulo={sobretituloDeHoy("Pendientes")}
          titulo="Bandeja"
          descripcion="Todo lo que requiere tu atención, en un solo lugar."
          ayuda={
            <AyudaPantalla
              titulo="Cómo funciona la Bandeja"
              intro="Junta lo que cada módulo ya sabe que necesita a una persona. No inventa un criterio nuevo de «pendiente»: si algo se arregla en su módulo, a la próxima carga ya no está."
              secciones={[
                { titulo: "Las casillas de arriba", texto: "Una por módulo, también las que están en cero («Al día»): así se distingue «Contratos está al día» de «Contratos no se revisa aquí». Tocar una filtra la lista." },
                { titulo: "Si un módulo no cargó", texto: "Su casilla dice «No se pudo cargar» en rojo. No se pinta «Al día» sobre un hueco: que no se pudiera mirar no significa que no haya nada." },
                { titulo: "La lista", texto: "Va por urgencia: Vencido (ya pasó el plazo o el riesgo corre), Hoy, Próximos y Sin plazo. Cada fila dice si se resuelve aquí mismo o en su módulo." },
                { titulo: "Qué ves", texto: "Los líderes de equipo ven solo lo de su sede; Desarrollo Organizacional y dirección, todas." },
                { titulo: "El número del menú", texto: "Suma las filas de la lista (la casilla «Todo»), más 1 si hay correos de aviso que no salieron (la tarjeta «Sistema») y 1 si hay constancias de Normas por recoger (el enlace de arriba). Por eso puede ser 2 más que «Todo»: la tarjeta y el enlace cuentan una vez cada uno, aunque dentro haya decenas de avisos." },
              ]}
            />
          }
        />

        {/* Enlace compacto, no una sección: esto no se resuelve aquí —se
            resuelve dejando constancia en Normas—, así que no le corresponde
            un grupo de urgencia ni una fila por persona en esta cola. */}
        {normas && (
          <Link href={normas.href}
            className="mb-6 flex items-center justify-between gap-2 rounded-control bg-hueso px-4 py-2.5 text-sm text-tinta hover:bg-sand/50">
            <span>{normas.texto}</span>
            <span className="shrink-0 font-medium text-rojo-profundo">Ver en Normas →</span>
          </Link>
        )}

        {cargando ? (
          <Cargando />
        ) : !puedeEntrar ? (
          <div className="max-w-2xl rounded-control bg-ambar/15 px-4 py-3 text-sm text-ambar">
            Esta pantalla es para quien opera el equipo — líderes de equipo y Desarrollo Organizacional.
          </div>
        ) : (
          <>
            {/* ── Qué revisa la Bandeja: una tarjeta por módulo, también en cero ── */}
            <div className="flex flex-wrap items-baseline justify-between gap-2">
              <h2 className="text-[11px] font-semibold uppercase tracking-wider text-taupe">Lo que revisa la Bandeja</h2>
              <span className="text-xs text-taupe">
                {modulos.length} módulo{modulos.length === 1 ? "" : "s"} · {alDia} al día
              </span>
            </div>
            <div className="mt-2 flex flex-wrap gap-2">
              <TarjetaCategoria
                id="categoria-todo" etiqueta="Todo" Icon={Inbox}
                n={paraTarjetas.length} vencidos={vencidosTotal}
                hoy={paraTarjetas.filter((p) => p.urgencia.grupo === "hoy").length}
                fallo={false} activa={moduloFiltro === null}
                onClick={() => { setModuloFiltro(null); setAbierta(null); }}
              />
              {modulos.map((m) => {
                const delModulo = paraTarjetas.filter((p) => p.modulo === m);
                return (
                  <TarjetaCategoria
                    key={m} id={`categoria-${m}`} etiqueta={ETIQUETA_MODULO[m]} Icon={ICONO_MODULO[m]}
                    n={delModulo.length}
                    vencidos={delModulo.filter((p) => p.urgencia.grupo === "vencido").length}
                    hoy={delModulo.filter((p) => p.urgencia.grupo === "hoy").length}
                    fallo={fuentes.fallidas.includes(m)}
                    activa={moduloFiltro === m}
                    onClick={() => { setModuloFiltro(moduloFiltro === m ? null : m); setAbierta(null); }}
                  />
                );
              })}
            </div>

            {/* ── Buscar y filtrar ─────────────────────────────────────── */}
            <div className="mt-4 flex flex-wrap items-center gap-2 border-b border-sand pb-3">
              <div className="relative min-w-48 flex-1">
                <Search className="pointer-events-none absolute left-2.5 top-1/2 size-3.5 -translate-y-1/2 text-taupe" aria-hidden />
                <Campo
                  id="bandeja-buscar"
                  tamano="sm"
                  type="search"
                  value={busca}
                  onChange={(e) => setBusca(e.target.value)}
                  placeholder="Buscar persona o pendiente…"
                  aria-label="Buscar persona o pendiente"
                  className="pl-8"
                />
              </div>
              {puedeTodasLasSedes && (
                <div className="w-full sm:w-56">
                  <CampoSelect
                    id="bandeja-sede"
                    tamano="sm"
                    aria-label="Sede"
                    value={sedeEfectiva ?? ""}
                    onChange={(e) => elegirSedeFiltro(e.target.value || null)}
                  >
                    <option value="">Todas las sedes · {porSedeSinSede.length}</option>
                    {opcionesSede.map((s) => (
                      <option key={s.codigo} value={s.codigo}>
                        {s.codigo}{s.nombre ? ` — ${s.nombre}` : ""} · {porSedeSinSede.filter((p) => p.sede === s.codigo).length}
                      </option>
                    ))}
                  </CampoSelect>
                </div>
              )}
              <div className="w-full sm:w-44">
                <CampoSelect
                  id="bandeja-urgencia"
                  tamano="sm"
                  aria-label="Urgencia"
                  value={grupoFiltro ?? ""}
                  onChange={(e) => setGrupoFiltro((e.target.value || null) as GrupoUrgencia | null)}
                >
                  <option value="">Toda urgencia</option>
                  {GRUPOS_URGENCIA.map((g) => <option key={g.clave} value={g.clave}>{g.etiqueta}</option>)}
                </CampoSelect>
              </div>
              {!puedeTodasLasSedes && <span className="text-xs text-taupe">Ves solo lo de tu sede.</span>}
              {hayFiltros && <Boton variante="enlace" onClick={limpiarFiltros} className="text-sm text-rojo">Limpiar filtros</Boton>}
            </div>

            {/* ── Sistema: salud del despacho de correos, no una tarea ─── */}
            {resumenAlertas && problemasCorreo > 0 && (
              <TarjetaSistema
                resumen={resumenAlertas}
                total={problemasCorreo}
                puedeResolver={puedeVerSaludDeAlertas(rol)}
                onResuelto={async () => {
                  // Recargar la lista no basta: el número del menú se calcula aparte y solo
                  // vuelve a contar al oír este aviso (el mismo que da `retirar`).
                  await cargar();
                  avisarCambioEnBandeja();
                }}
              />
            )}

            {/* ── La lista, por urgencia ───────────────────────────────── */}
            <div id="bandeja-lista" className="@container mt-2">
              {filtrados.length === 0 ? (
                <div className="mt-4 flex flex-col items-center gap-3 rounded-control border border-dashed border-sand py-10 text-center">
                  {pendientes.length === 0 ? (
                    <>
                      <p className="font-serif text-lg text-tinta">Todo al día.</p>
                      <p className="max-w-md text-sm text-taupe">
                        {fuentes.fallidas.length > 0
                          ? "No hay pendientes en lo que se pudo cargar. Los módulos marcados «No se pudo cargar» hay que revisarlos de nuevo."
                          : "No tienes pendientes que requieran atención. Cuando algo lo necesite, va a aparecer aquí."}
                      </p>
                    </>
                  ) : moduloActivo && q === "" && !sedeEfectiva && !grupoFiltro ? (
                    <>
                      <p className="font-serif text-lg text-tinta">
                        {fuentes.fallidas.includes(moduloFiltro!) ? `No se pudo cargar ${moduloActivo}.` : `${moduloActivo} está al día.`}
                      </p>
                      <p className="text-sm text-taupe">
                        {fuentes.fallidas.includes(moduloFiltro!) ? "Vuelve a abrir la Bandeja en un momento." : "La Bandeja lo revisa y hoy no tiene nada pendiente."}
                      </p>
                      <Boton variante="secundario" tamano="sm" onClick={() => setModuloFiltro(null)}>Ver todo</Boton>
                    </>
                  ) : (
                    <>
                      <p className="font-serif text-lg text-tinta">No encontramos pendientes con estos filtros.</p>
                      <Boton variante="secundario" tamano="sm" onClick={limpiarFiltros}>Limpiar filtros</Boton>
                    </>
                  )}
                </div>
              ) : (
                <>
                  <div className={cx("sticky top-0 z-10 hidden gap-x-4 border-b border-sand bg-crema px-4 py-2 text-[11px] font-semibold uppercase tracking-wider text-taupe @3xl:grid", COLUMNAS)}>
                    <span>Persona</span><span>Pendiente</span><span>Origen</span><span>Plazo</span><span className="text-right">Acción</span>
                  </div>
                  {GRUPOS_URGENCIA.map((g) => {
                    const delGrupo = filtrados.filter((p) => p.urgencia.grupo === g.clave);
                    if (delGrupo.length === 0) return null;
                    return (
                      <section key={g.clave} aria-labelledby={`grupo-${g.clave}`} className="mt-3">
                        <h3 id={`grupo-${g.clave}`} className="flex flex-wrap items-center gap-2 px-1 pb-2 pt-1 text-[11px] font-semibold uppercase tracking-wider text-tinta">
                          <MarcaGrupo grupo={g.clave} />
                          {g.etiqueta}
                          <span className="font-normal tabular-nums text-taupe">· {delGrupo.length}</span>
                          <span className="font-normal normal-case tracking-normal text-taupe">— {g.descripcion}</span>
                        </h3>
                        <ul className="flex flex-col gap-1.5">{delGrupo.map(fila)}</ul>
                      </section>
                    );
                  })}
                </>
              )}
            </div>
          </>
        )}
      </main>
    </div>
  );
}
