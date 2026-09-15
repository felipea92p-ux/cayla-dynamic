"use client";

// ============================================================================
// Bandeja — todo lo que requiere atención del equipo, en un solo lugar.
// ----------------------------------------------------------------------------
// QUÉ PROMETE. Educación, Ausencias, Incidencias, Horarios, Datos personales,
// Documentación y Contratos ya saben, cada uno, cuándo algo suyo necesita a una
// persona. Esta pantalla no inventa un criterio nuevo de "pendiente": pide las
// MISMAS RPC que ya corren para el número del menú (lib/admin/bandeja-equipo.ts)
// y las junta. Si un pendiente se arregla en su módulo, a la próxima carga ya
// no está: no hay nada guardado aquí que pueda quedar viejo.
//
// QUÉ NO HACE. No resuelve nada que ya tenga su propio formulario. Educación
// (adjuntar un comprobante), Ausencias (programar un récord) y Horarios
// (asignar uno) siguen en sus pantallas; acá solo se enlaza, a la persona
// cuando el módulo lo permite. Cinco tipos sí se resuelven acá mismo porque
// son una sola RPC con un texto opcional: las tres revisiones pedidas
// («marcar atendida»), las solicitudes de vacaciones y las de cambio de perfil
// (aprobar/rechazar). Resolverlas sin salir no duplica ningún formulario.
//
// A quién se le muestra. Lo decide la base, no esta pantalla: la encargada
// recibe de cada RPC solo lo de su sede, y DO todo. Aquí `puede*` solo decide
// qué se PIDE, para no pedir lo que igual volvería vacío.
//
// ── Rediseño (2026-09-15, decidido con Felipe) ──────────────────────────────
// Reemplaza las zonas «Por aprobar / Para saber» del ADR 0002. «Para saber» no
// era informativo: una asignación sin papel también exige que alguien haga
// algo, solo que en otra pantalla. Ahora:
//
//   · Dos pestañas por DÓNDE se resuelve — «Resolver aquí» y «En otra
//     pantalla» —, cada una con su conteo de vencidos a la vista: lo vencido
//     de la pestaña que no se está mirando no puede quedar escondido.
//   · Dentro, grupos por URGENCIA (lib/admin/bandeja-urgencia.ts): Vencido,
//     Hoy, Próximos, Sin plazo.
//   · Las sedes del filtro salen de la tabla `sedes` (activas, más cualquier
//     sede que tenga pendientes aunque ya no esté activa), no de lo que trajo
//     la carga: antes una sede sin pendientes desaparecía y parecía un olvido.
//   · Quien ya cesó sigue apareciendo, con «Cesó el …», en Sin plazo.
//   · Resolver algo avisa al menú para que su número baje sin navegar.
//
// "Nuevo desde tu última visita" (bandeja_vistos, 0436) sigue igual: solo los
// cinco tipos que se resuelven acá, y se marca visto todo lo que trajo la RPC,
// no solo lo que el filtro deja ver.
// ============================================================================

import { useCallback, useEffect, useMemo, useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import {
  Clock, FileSignature, GraduationCap, IdCard, PencilLine, ScrollText, Search, TreePalm, type LucideIcon,
} from "lucide-react";
import { Cargando, SinDatos } from "@/components/cargando";
import { Boton } from "@/components/ui/boton";
import { Campo } from "@/components/ui/campo";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { cx } from "@/components/ui/cx";
import { useToast } from "@/components/toast";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { BUCKET_SOLICITUDES_PERFIL } from "@/lib/foto-dni";
import { diaYMes } from "@/lib/bandeja-mia";
import { sinTildes } from "@/lib/sin-tildes";
import {
  avisarCambioEnBandeja, compararPendientes, conCese, documentoEducacion, GRUPOS_URGENCIA, urgenciaEducacion,
  urgenciaEspera, urgenciaInicio, urgenciaRecordVacaciones, urgenciaSinHorario,
  type GrupoUrgencia, type Urgencia,
} from "@/lib/admin/bandeja-urgencia";
import {
  fechaLima, hoyLima, puedeGestionarCatalogos, puedeGestionarContratos, puedeOperarEquipo, puedeVerIdentidad,
  puedeVerPlanilla, puedeVerSaludDeAlertas, puedeVerTodasLasSedes,
} from "@cayla-dynamic/shared";
import { esEducacionParaSaber, type FilaEducacionBandeja } from "@/lib/admin/bandeja-equipo";

// Los dos de educación (0450) no se resuelven aquí —la constancia se mira con sus
// archivos, en Educación—, pero llevan «Nuevo» igual: son una cola de revisión, y
// una constancia que acaba de llegar es justo lo que hay que distinguir.
type TipoItemBandeja =
  | "revision" | "revision_movilidad" | "revision_contrato"
  | "solicitud_vacacion" | "solicitud_perfil"
  | "entrega_educacion" | "aviso_fin_educacion";

const CLAVE_SEDE_FILTRO = "bandeja_sede_filtro";

/** Un estudio para tener presente (0450): constancia vencida, sin calendario, o pago cercano. */
type ItemEducacion = FilaEducacionBandeja;

/** Una constancia de estudios esperando revisión (0450). UNA entrega = UN pendiente, tenga las páginas que tenga. */
interface ItemEntregaEducacion {
  id: string; familia_id: string; persona_id: string; persona: string; sede: string;
  institucion: string; fecha_pago: string; enviada_at: string; archivos: number; es_reenvio: boolean;
}

/** Una integrante avisó que ya no va a pagar su estudio (0450). */
interface ItemAvisoFinEducacion {
  id: string; familia_id: string; persona_id: string; persona: string; sede: string;
  institucion: string; motivo: string; creado_at: string;
}

/** Alguien que trabajó días que su horario no cubre (mig. 0385). La función ya
 *  excluye a quien no le toca llevar horario (RxH y personal de dirección), así
 *  que todo lo que llega aquí es un hueco de verdad. */
interface ItemSinHorario {
  persona_id: string; nombre: string; sede: string;
  dias: number; primer_dia: string; ultimo_dia: string;
  nunca_tuvo_horario: boolean;
}

interface ItemVacacion {
  persona_id: string;
  persona: string;
  sede: string;
  records_vencidos: number;
  vence_el: string;
  dias_para_vencer: number;
}

interface ItemRevision {
  id: string; persona_id: string; nombre: string; sede: string;
  fecha: string; comentario: string; pedida_at: string;
}

/** Un pedido de revisión de una declaración de ruta (0425). `sede` puede venir
 *  null: la RPC hace left join. */
interface ItemRevisionMovilidad {
  id: string; persona_id: string; nombre: string; sede: string | null;
  motivo: string; pedida_at: string;
}

/** Un pedido de revisión de un contrato ya generado (0427). Mismo molde. */
interface ItemRevisionContrato {
  id: string; persona_id: string; nombre: string; sede: string | null;
  motivo: string; pedida_at: string;
}

interface ItemSolicitudVacacion {
  id: string; persona_id: string; nombre: string; sede: string;
  fecha_inicio: string; fecha_fin: string; dias: number;
  comentario: string | null; pedida_at: string;
}

/** Una propuesta de cambio de perfil por resolver (migración 0399). */
interface ItemSolicitudPerfil {
  id: string; persona_id: string; nombre: string; sede: string;
  campo: string; etiqueta: string;
  valor_anterior: Record<string, unknown>;
  valor_propuesto: Record<string, unknown>;
  rutas_adjuntas: string[];
  creada_at: string;
  /** Este campo solo lo aprueba DO, aunque la encargada vea la solicitud (0405).
   *  Lo dice el catálogo, no esta pantalla: `catalogo_campos_perfil.solo_do`. */
  solo_do: boolean;
}

// Lo que devuelve fn_alertas_despacho_resumen (0362): lo que el despacho
// diario de avisos por correo NO va a resolver solo.
interface ResumenAlertas {
  despachables: number;
  atascadas: number;
  fallidas_definitivas: number;
  caducadas: number;
  ultimo_envio_at: string | null;
  /** Notas distintas del último fallo de las definitivas: el POR QUÉ, que no siempre está en Sentry. */
  motivos_definitivos: string[];
}

interface Sede { codigo: string; nombre: string; activa: boolean }

type TipoPendiente = TipoItemBandeja | "educacion" | "vacaciones_por_vencer" | "sin_horario";

/** De qué módulo viene cada pendiente. El ícono es el MISMO del menú (nav-items.ts). */
type Modulo = "educacion" | "ausencias" | "correcciones" | "horarios" | "datos_personales" | "contratos" | "documentacion";
const MODULOS: Record<Modulo, { etiqueta: string; Icon: LucideIcon }> = {
  educacion: { etiqueta: "Educación", Icon: GraduationCap },
  ausencias: { etiqueta: "Ausencias", Icon: TreePalm },
  correcciones: { etiqueta: "Correcciones", Icon: PencilLine },
  horarios: { etiqueta: "Horarios", Icon: Clock },
  datos_personales: { etiqueta: "Datos personales", Icon: IdCard },
  contratos: { etiqueta: "Contratos", Icon: ScrollText },
  documentacion: { etiqueta: "Documentación", Icon: FileSignature },
};

/**
 * Un pendiente, sea del tipo que sea, en la forma en que se pinta. Quién, qué,
 * dónde, de qué módulo, cuándo y qué hacer ahora: las seis preguntas de una
 * fila de la Bandeja.
 */
interface Pendiente {
  clave: string;
  tipo: TipoPendiente;
  itemId: string;
  personaId: string | null;
  persona: string;
  sede: string;
  modulo: Modulo;
  titulo: string;
  detalle: string | null;
  urgencia: Urgencia;
  /** «aqui» se resuelve desplegando la fila; «afuera» lleva a su módulo. */
  resolucion: "aqui" | "afuera";
  /** Para «afuera»: el verbo y a dónde. */
  ir: { texto: string; href: string } | null;
  /** Para «aqui»: un enlace de contexto dentro del desplegable. */
  contexto: { texto: string; href: string } | null;
  nuevo: boolean;
  /** Fecha de cese ya cumplida, o null. */
  cesoEl: string | null;
}

/** «celular: 987654321, direccion: Av. Uno 123» — genérico a propósito: son
 *  campos con formas distintas, y esto solo es para que quien aprueba vea
 *  de un vistazo qué cambia, no para imprimir un documento.
 *
 *  Con una excepción, desde la 0401: cuando el valor ES un archivo (la foto del
 *  DNI), su valor es una ruta del almacén —sesenta caracteres que no dicen
 *  nada—. Ahí se anuncia la cara y ya está: lo que hay que mirar es la imagen,
 *  y para eso están los botones de adjuntos. */
function resumenValorPerfil(v: Record<string, unknown>): string {
  const entradas = Object.entries(v).filter(([, val]) => val !== null && val !== undefined && val !== "");
  if (entradas.length === 0) return "—";
  return entradas.map(([k, val]) => {
    if (typeof val === "string" && val.startsWith("solicitud/")) {
      return `${k.replace(/^foto_dni_|_ruta$/g, "")}: imagen adjunta`;
    }
    return `${k}: ${typeof val === "boolean" ? (val ? "Sí" : "No") : String(val)}`;
  }).join(" · ");
}

// Un timestamptz → "3 de setiembre", en el día de Lima.
function diaLima(ts: string): string {
  return diaYMes(fechaLima(ts));
}

function rangoVacaciones(s: ItemSolicitudVacacion): string {
  const rango = s.fecha_inicio === s.fecha_fin
    ? `el ${diaYMes(s.fecha_inicio)}`
    : `del ${diaYMes(s.fecha_inicio)} al ${diaYMes(s.fecha_fin)}`;
  return `Vacaciones ${rango} · ${s.dias} día${s.dias === 1 ? "" : "s"}`;
}

// Columnas de la fila en ancho completo. Literal, no armado: Tailwind solo ve
// clases que aparecen enteras en el código.
const COLUMNAS = "@3xl:grid-cols-[minmax(9rem,1.1fr)_minmax(14rem,2.4fr)_9.5rem_11rem_minmax(8rem,auto)]";
const SELECT = "rounded-control border border-sand bg-hueso px-3 py-2 text-base text-tinta sm:text-sm";

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

export default function BandejaPage() {
  const router = useRouter();
  const persona = usePersonaActual();
  const rol = persona?.rol ?? null;
  const { avisar } = useToast();

  const puedeEducacion = puedeVerPlanilla(rol);
  const puedeEquipo = puedeOperarEquipo(rol);
  // Resolver una solicitud de vacaciones crea plata (o la corta): misma regla
  // que fn_resolver_solicitud_vacaciones ya exige en el servidor — es DO,
  // nunca la encargada de la sede.
  const puedeResolverVacaciones = puedeVerPlanilla(rol);
  const puedeSaludAlertas = puedeVerSaludDeAlertas(rol);
  // CAMBIO 0403 — la encargada también resuelve perfiles, pero solo de su
  // equipo: el guard vive en fn_resolver_solicitud_perfil.
  const puedeResolverPerfil = puedeOperarEquipo(rol);
  // Mismo alcance que `fn_movilidad_revisiones_pedidas` (0425): sin la encargada.
  const puedeMovilidad = puedeGestionarCatalogos(rol);
  const puedeContratos = puedeGestionarContratos(rol);
  // ALCANCE, no permiso: la encargada ya recibe solo su sede, así que no se le
  // ofrece un filtro que no tiene nada que filtrar.
  const puedeTodasLasSedes = puedeVerTodasLasSedes(rol);

  const [cargando, setCargando] = useState(true);
  const [resumenAlertas, setResumenAlertas] = useState<ResumenAlertas | null>(null);
  const [educacion, setEducacion] = useState<ItemEducacion[]>([]);
  const [entregasEducacion, setEntregasEducacion] = useState<ItemEntregaEducacion[]>([]);
  const [avisosFinEducacion, setAvisosFinEducacion] = useState<ItemAvisoFinEducacion[]>([]);
  const [vacaciones, setVacaciones] = useState<ItemVacacion[]>([]);
  const [sinHorario, setSinHorario] = useState<ItemSinHorario[]>([]);
  const [revisiones, setRevisiones] = useState<ItemRevision[]>([]);
  const [revisionesMovilidad, setRevisionesMovilidad] = useState<ItemRevisionMovilidad[]>([]);
  const [revisionesContrato, setRevisionesContrato] = useState<ItemRevisionContrato[]>([]);
  const [solicitudesVacaciones, setSolicitudesVacaciones] = useState<ItemSolicitudVacacion[]>([]);
  const [solicitudesPerfil, setSolicitudesPerfil] = useState<ItemSolicitudPerfil[]>([]);
  const [sedes, setSedes] = useState<Sede[]>([]);
  const [ceses, setCeses] = useState<Map<string, string>>(new Map());
  const [vistosIniciales, setVistosIniciales] = useState<Set<string>>(new Set());

  // Lo que se escribe en el desplegable de cada fila, por clave de pendiente.
  const [textos, setTextos] = useState<Record<string, string>>({});
  const [errores, setErrores] = useState<Record<string, string>>({});
  const [ocupado, setOcupado] = useState<string | null>(null);
  const [abierta, setAbierta] = useState<string | null>(null);
  const [saliendo, setSaliendo] = useState<Set<string>>(new Set());

  const [busca, setBusca] = useState("");
  const [sedeFiltro, setSedeFiltro] = useState<string | null>(null);
  const [moduloFiltro, setModuloFiltro] = useState<Modulo | "">("");
  const [grupoFiltro, setGrupoFiltro] = useState<GrupoUrgencia | null>(null);
  // null = todavía no eligió: se abre en la que tenga algo (ver `pestanaActiva`).
  const [pestana, setPestana] = useState<"aqui" | "afuera" | null>(null);

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

    const tareas: PromiseLike<void>[] = [];

    if (puedeEducacion) {
      // ⇩ CAMBIO 0450 ⇩ Tres fuentes, el mismo criterio que cuenta el menú
      // (lib/admin/bandeja-equipo.ts): cada constancia por revisar, cada aviso de
      // «ya no voy a pagar», y los estudios para tener presentes. El contador de
      // Educación (fn_educacion_por_atender) cuenta lo mismo salvo los pagos
      // cercanos, que avisan pero no piden nada todavía — la decisión 8 del
      // ADR 0003 quedó cerrada por la 0450.
      tareas.push(
        supabase.rpc("fn_educacion_entregas_pendientes").then(({ data, error }) => {
          if (error) { avisar("error", mensajeDeError(error, "cargar las constancias de educación")); return; }
          setEntregasEducacion((data as unknown as ItemEntregaEducacion[]) ?? []);
        }),
      );
      tareas.push(
        supabase.rpc("fn_educacion_avisos_fin_pendientes").then(({ data, error }) => {
          if (error) { avisar("error", mensajeDeError(error, "cargar los avisos de educación")); return; }
          setAvisosFinEducacion((data as unknown as ItemAvisoFinEducacion[]) ?? []);
        }),
      );
      tareas.push(
        supabase.rpc("fn_educacion_situacion").then(({ data, error }) => {
          if (error) { avisar("error", mensajeDeError(error, "cargar educación")); return; }
          setEducacion(((data as unknown as ItemEducacion[]) ?? []).filter(esEducacionParaSaber));
        }),
      );
    } else {
      setEducacion([]);
      setEntregasEducacion([]);
      setAvisosFinEducacion([]);
    }

    if (puedeEquipo) {
      tareas.push(
        supabase.rpc("fn_vacaciones_por_vencer", { p_dias: 60, p_as_of: null }).then(({ data, error }) => {
          if (error) { avisar("error", mensajeDeError(error, "cargar vacaciones por vencer")); return; }
          setVacaciones((data as unknown as ItemVacacion[]) ?? []);
        }),
      );
      tareas.push(
        // Falla suave a propósito: sin la 0385 la bandeja sigue, solo sin esto.
        supabase.rpc("fn_personas_sin_horario_vigente", { p_dias: 60 }).then(({ data }) => {
          setSinHorario((data as unknown as ItemSinHorario[]) ?? []);
        }),
      );
      tareas.push(
        supabase.rpc("fn_revisiones_pedidas", { p_solo_pendientes: true }).then(({ data, error }) => {
          if (error) { avisar("error", mensajeDeError(error, "cargar revisiones pedidas")); return; }
          setRevisiones((data as unknown as ItemRevision[]) ?? []);
        }),
      );
      tareas.push(
        // bandeja_vistos (0436). Falla suave — sin ella, todo se ve sin «Nuevo».
        supabase.from("bandeja_vistos").select("tipo_item,item_id").then(({ data }) => {
          setVistosIniciales(new Set<string>((data ?? []).map((v) => `${v.tipo_item}:${v.item_id}`)));
        }),
      );
      tareas.push(
        // Quién ya cesó, para la insignia «Cesó el …». La misma función que usa
        // Educación para su filtro de liquidados; ya acota a la sede de la
        // encargada. Falla suave: sin ella nadie se marca como cesado, que es
        // el lado seguro (nada se baja de urgencia por error).
        supabase.rpc("fn_personas_funciones").then(({ data }) => {
          const filas = (data as { persona_id: string; fecha_cese: string | null }[] | null) ?? [];
          setCeses(new Map(filas.filter((f) => f.fecha_cese).map((f) => [f.persona_id, f.fecha_cese as string] as const)));
        }),
      );
    } else {
      setVacaciones([]);
      setRevisiones([]);
      setSinHorario([]);
    }

    if (puedeTodasLasSedes) {
      tareas.push(
        // Las opciones del filtro salen de la tabla (regla #3 de este repo),
        // no de lo que trajo la carga: una sede sin pendientes también existe.
        supabase.from("sedes").select("codigo, nombre, activa").order("codigo").then(({ data }) => {
          setSedes((data as Sede[] | null) ?? []);
        }),
      );
    }

    if (puedeMovilidad) {
      tareas.push(
        supabase.rpc("fn_movilidad_revisiones_pedidas", { p_solo_pendientes: true }).then(({ data, error }) => {
          if (error) { avisar("error", mensajeDeError(error, "cargar revisiones de movilidad pedidas")); return; }
          setRevisionesMovilidad((data as unknown as ItemRevisionMovilidad[]) ?? []);
        }),
      );
    } else {
      setRevisionesMovilidad([]);
    }

    if (puedeContratos) {
      tareas.push(
        supabase.rpc("fn_contrato_revisiones_pedidas", { p_solo_pendientes: true }).then(({ data, error }) => {
          if (error) { avisar("error", mensajeDeError(error, "cargar revisiones de contrato pedidas")); return; }
          setRevisionesContrato((data as unknown as ItemRevisionContrato[]) ?? []);
        }),
      );
    } else {
      setRevisionesContrato([]);
    }

    if (puedeResolverVacaciones) {
      tareas.push(
        supabase.rpc("fn_solicitudes_vacaciones", { p_solo_pendientes: true }).then(({ data, error }) => {
          if (error) { avisar("error", mensajeDeError(error, "cargar solicitudes de vacaciones")); return; }
          setSolicitudesVacaciones((data as unknown as ItemSolicitudVacacion[]) ?? []);
        }),
      );
    } else {
      setSolicitudesVacaciones([]);
    }

    if (puedeResolverPerfil) {
      tareas.push(
        supabase.rpc("fn_solicitudes_perfil_pendientes").then(({ data, error }) => {
          if (error) { avisar("error", mensajeDeError(error, "cargar solicitudes de perfil")); return; }
          setSolicitudesPerfil((data as unknown as ItemSolicitudPerfil[]) ?? []);
        }),
      );
    } else {
      setSolicitudesPerfil([]);
    }

    if (puedeSaludAlertas) {
      tareas.push(
        supabase.rpc("fn_alertas_despacho_resumen").then(({ data, error }) => {
          // Sin toast a propósito: es un chequeo de salud, no una tarea.
          if (error || !data) { setResumenAlertas(null); return; }
          setResumenAlertas(data as unknown as ResumenAlertas);
        }),
      );
    } else {
      setResumenAlertas(null);
    }

    await Promise.all(tareas);
    setCargando(false);
  }, [router, puedeEducacion, puedeEquipo, puedeMovilidad, puedeContratos, puedeResolverVacaciones,
      puedeResolverPerfil, puedeSaludAlertas, puedeTodasLasSedes, avisar]);

  // eslint-disable-next-line react-hooks/set-state-in-effect -- cargar al montar, mismo patrón que el resto del panel.
  useEffect(() => { void cargar(); }, [cargar]);

  // Marcar visto TODO lo que se resuelve acá, una vez que terminó de cargar —
  // la insignia de «Nuevo» de esta visita ya se calculó con vistosIniciales.
  useEffect(() => {
    if (cargando) return;
    const supabase = createAdminSupabaseClient();
    const items: Array<[TipoItemBandeja, string]> = [
      ...revisiones.map((r): [TipoItemBandeja, string] => ["revision", r.id]),
      ...revisionesMovilidad.map((r): [TipoItemBandeja, string] => ["revision_movilidad", r.id]),
      ...revisionesContrato.map((r): [TipoItemBandeja, string] => ["revision_contrato", r.id]),
      ...solicitudesVacaciones.map((s): [TipoItemBandeja, string] => ["solicitud_vacacion", s.id]),
      ...solicitudesPerfil.map((s): [TipoItemBandeja, string] => ["solicitud_perfil", s.id]),
      ...entregasEducacion.map((e): [TipoItemBandeja, string] => ["entrega_educacion", e.id]),
      ...avisosFinEducacion.map((a): [TipoItemBandeja, string] => ["aviso_fin_educacion", a.id]),
    ];
    for (const [tipo, id] of items) {
      if (!vistosIniciales.has(`${tipo}:${id}`)) {
        void supabase.rpc("fn_bandeja_marcar_visto", { p_tipo_item: tipo, p_item_id: id });
      }
    }
    // Solo cuando termina de cargar: una vez por visita.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cargando]);

  const hoy = hoyLima();

  // ── Todo en una sola forma ────────────────────────────────────────────────
  const pendientes = useMemo<Pendiente[]>(() => {
    const lista: Pendiente[] = [];
    const agregar = (p: Omit<Pendiente, "cesoEl">) => {
      const cese = p.personaId ? ceses.get(p.personaId) : undefined;
      const cesoEl = cese && cese <= hoy ? cese : null;
      lista.push({ ...p, cesoEl, urgencia: cesoEl ? conCese(p.urgencia) : p.urgencia });
    };

    for (const r of revisiones) {
      agregar({
        clave: `revision:${r.id}`, tipo: "revision", itemId: r.id, personaId: r.persona_id,
        persona: r.nombre, sede: r.sede, modulo: "correcciones",
        titulo: `Pidió revisar su ${diaYMes(r.fecha)}`, detalle: `«${r.comentario}»`,
        urgencia: urgenciaEspera(r.pedida_at, hoy), resolucion: "aqui", ir: null,
        contexto: { texto: "Abrir ese día en Correcciones", href: `/admin/correcciones?persona=${r.persona_id}&fecha=${r.fecha}` },
        nuevo: !vistosIniciales.has(`revision:${r.id}`),
      });
    }
    for (const r of revisionesMovilidad) {
      agregar({
        clave: `revision_movilidad:${r.id}`, tipo: "revision_movilidad", itemId: r.id, personaId: r.persona_id,
        persona: r.nombre, sede: r.sede ?? "—", modulo: "documentacion",
        titulo: "Pidió revisar su declaración de ruta", detalle: `«${r.motivo}»`,
        urgencia: urgenciaEspera(r.pedida_at, hoy), resolucion: "aqui", ir: null,
        contexto: { texto: "Abrir su ruta en Documentación", href: `/admin/documentacion?persona=${r.persona_id}` },
        nuevo: !vistosIniciales.has(`revision_movilidad:${r.id}`),
      });
    }
    for (const r of revisionesContrato) {
      agregar({
        clave: `revision_contrato:${r.id}`, tipo: "revision_contrato", itemId: r.id, personaId: r.persona_id,
        persona: r.nombre, sede: r.sede ?? "—", modulo: "contratos",
        titulo: "Pidió revisar su contrato", detalle: `«${r.motivo}»`,
        urgencia: urgenciaEspera(r.pedida_at, hoy), resolucion: "aqui", ir: null,
        contexto: { texto: "Abrir su contrato en Contratos", href: `/admin/contratos?persona=${r.persona_id}` },
        nuevo: !vistosIniciales.has(`revision_contrato:${r.id}`),
      });
    }
    for (const s of solicitudesVacaciones) {
      agregar({
        clave: `solicitud_vacacion:${s.id}`, tipo: "solicitud_vacacion", itemId: s.id, personaId: s.persona_id,
        persona: s.nombre, sede: s.sede, modulo: "ausencias",
        titulo: rangoVacaciones(s), detalle: s.comentario ? `«${s.comentario}» · pedidas el ${diaLima(s.pedida_at)}` : `Pedidas el ${diaLima(s.pedida_at)}`,
        urgencia: urgenciaInicio(s.fecha_inicio, hoy), resolucion: "aqui", ir: null, contexto: null,
        nuevo: !vistosIniciales.has(`solicitud_vacacion:${s.id}`),
      });
    }
    for (const s of solicitudesPerfil) {
      agregar({
        clave: `solicitud_perfil:${s.id}`, tipo: "solicitud_perfil", itemId: s.id, personaId: s.persona_id,
        persona: s.nombre, sede: s.sede, modulo: "datos_personales",
        titulo: `Cambio de ${s.etiqueta.toLowerCase()}`,
        detalle: s.rutas_adjuntas.length > 0
          ? `Con ${s.rutas_adjuntas.length} documento${s.rutas_adjuntas.length === 1 ? "" : "s"} adjunto${s.rutas_adjuntas.length === 1 ? "" : "s"}`
          : resumenValorPerfil(s.valor_propuesto),
        urgencia: urgenciaEspera(s.creada_at, hoy), resolucion: "aqui", ir: null,
        contexto: { texto: "Ver su ficha", href: `/admin/personas/${s.persona_id}` },
        nuevo: !vistosIniciales.has(`solicitud_perfil:${s.id}`),
      });
    }
    // ⇩ CAMBIO 0450 ⇩ UNA entrega = UN pendiente, tenga los archivos que tenga, y
    // su botón abre ESA entrega, no la portada de Educación. Se mide por lo que
    // lleva esperando, igual que las demás respuestas pendientes.
    for (const e of entregasEducacion) {
      agregar({
        clave: `entrega_educacion:${e.id}`, tipo: "entrega_educacion", itemId: e.id, personaId: e.persona_id,
        persona: e.persona, sede: e.sede, modulo: "educacion",
        titulo: e.es_reenvio ? "Constancia educativa corregida, pendiente de revisión" : "Constancia educativa pendiente de revisión",
        detalle: `${e.institucion} · pago del ${diaYMes(e.fecha_pago)} · ${e.archivos} archivo${e.archivos === 1 ? "" : "s"} · enviada el ${diaLima(e.enviada_at)}`,
        urgencia: urgenciaEspera(e.enviada_at, hoy), resolucion: "afuera",
        ir: { texto: "Revisar", href: `/admin/educacion?entrega=${e.id}` },
        contexto: null, nuevo: !vistosIniciales.has(`entrega_educacion:${e.id}`),
      });
    }
    for (const a of avisosFinEducacion) {
      agregar({
        clave: `aviso_fin_educacion:${a.id}`, tipo: "aviso_fin_educacion", itemId: a.id, personaId: a.persona_id,
        persona: a.persona, sede: a.sede, modulo: "educacion",
        titulo: "Avisó que ya no va a pagar su estudio", detalle: `${a.institucion} · «${a.motivo}»`,
        urgencia: urgenciaEspera(a.creado_at, hoy), resolucion: "afuera",
        ir: { texto: "Decidir el cierre", href: `/admin/educacion?familia=${a.familia_id}` },
        contexto: null, nuevo: !vistosIniciales.has(`aviso_fin_educacion:${a.id}`),
      });
    }
    for (const f of educacion) {
      const doc = documentoEducacion(f);
      agregar({
        clave: `educacion:${f.familia_id}`, tipo: "educacion", itemId: f.familia_id, personaId: f.persona_id,
        persona: f.persona, sede: f.sede, modulo: "educacion",
        titulo: doc.titulo, detalle: f.institucion,
        urgencia: urgenciaEducacion(f, hoy), resolucion: "afuera",
        ir: { texto: doc.accion, href: `/admin/educacion?familia=${f.familia_id}` },
        contexto: null, nuevo: false,
      });
    }
    for (const v of vacaciones) {
      agregar({
        clave: `vacaciones_por_vencer:${v.persona_id}`, tipo: "vacaciones_por_vencer", itemId: v.persona_id,
        personaId: v.persona_id, persona: v.persona, sede: v.sede, modulo: "ausencias",
        titulo: v.records_vencidos > 0 ? "Récord de vacaciones vencido sin gozar" : "Récord de vacaciones por vencer",
        detalle: `Vence el ${diaYMes(v.vence_el)} · hay que programarle sus días`,
        urgencia: urgenciaRecordVacaciones(v), resolucion: "afuera",
        ir: { texto: "Programar vacaciones", href: "/admin/ausencias" }, contexto: null, nuevo: false,
      });
    }
    for (const h of sinHorario) {
      const dias = `${h.dias} día${h.dias === 1 ? "" : "s"}`;
      agregar({
        clave: `sin_horario:${h.persona_id}`, tipo: "sin_horario", itemId: h.persona_id, personaId: h.persona_id,
        persona: h.nombre, sede: h.sede, modulo: "horarios",
        titulo: h.nunca_tuvo_horario ? `Trabajó ${dias} y nunca se le cargó horario` : `Trabajó ${dias} sin horario`,
        detalle: `${h.nunca_tuvo_horario ? "" : `Del ${diaYMes(h.primer_dia)} al ${diaYMes(h.ultimo_dia)}. `}Esos días no miden tardanza, y una licencia que caiga ahí se paga en cero.`,
        urgencia: urgenciaSinHorario(h), resolucion: "afuera",
        ir: { texto: "Asignar horario", href: "/admin/horarios" }, contexto: null, nuevo: false,
      });
    }
    return lista.sort(compararPendientes);
  }, [revisiones, revisionesMovilidad, revisionesContrato, solicitudesVacaciones, solicitudesPerfil, educacion,
      entregasEducacion, avisosFinEducacion, vacaciones, sinHorario, ceses, vistosIniciales, hoy]);

  // ── Filtros ───────────────────────────────────────────────────────────────
  // El filtro guardado de sede no aplica a quien solo ve la suya.
  const sedeEfectiva = puedeTodasLasSedes ? sedeFiltro : null;
  const q = sinTildes(busca.trim());
  const porTextoYModulo = pendientes.filter((p) =>
    (q === "" || sinTildes(p.persona).includes(q) || sinTildes(p.titulo).includes(q))
    && (moduloFiltro === "" || p.modulo === moduloFiltro));
  const porSede = porTextoYModulo.filter((p) => !sedeEfectiva || p.sede === sedeEfectiva);
  const filtrados = porSede.filter((p) => !grupoFiltro || p.urgencia.grupo === grupoFiltro);
  const aqui = filtrados.filter((p) => p.resolucion === "aqui");
  const afuera = filtrados.filter((p) => p.resolucion === "afuera");
  const hayFiltros = q !== "" || !!sedeEfectiva || moduloFiltro !== "" || grupoFiltro !== null;

  const pestanaActiva: "aqui" | "afuera" = pestana
    ?? (pendientes.some((p) => p.resolucion === "aqui") || !pendientes.some((p) => p.resolucion === "afuera") ? "aqui" : "afuera");
  const listaActiva = pestanaActiva === "aqui" ? aqui : afuera;
  const listaOtra = pestanaActiva === "aqui" ? afuera : aqui;

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

  const modulosPresentes = (Object.keys(MODULOS) as Modulo[]).filter((m) => pendientes.some((p) => p.modulo === m));

  function limpiarFiltros() {
    setBusca("");
    elegirSedeFiltro(null);
    setModuloFiltro("");
    setGrupoFiltro(null);
  }

  // La franja de avisos por correo solo aparece cuando hay algo que una
  // persona tiene que mirar: lo que se va a reintentar solo no se muestra.
  const alertasConProblema = resumenAlertas
    ? resumenAlertas.atascadas + resumenAlertas.fallidas_definitivas + resumenAlertas.caducadas
    : 0;

  // ── Resolver ──────────────────────────────────────────────────────────────
  /** La fila se desvanece, sale de la lista y el menú vuelve a contar. */
  function retirar(p: Pendiente, mensaje: string) {
    setSaliendo((s) => new Set(s).add(p.clave));
    setAbierta(null);
    avisar("ok", mensaje);
    avisarCambioEnBandeja();
    window.setTimeout(() => {
      const fuera = <T extends { id: string }>(xs: T[]) => xs.filter((x) => x.id !== p.itemId);
      if (p.tipo === "revision") setRevisiones(fuera);
      if (p.tipo === "revision_movilidad") setRevisionesMovilidad(fuera);
      if (p.tipo === "revision_contrato") setRevisionesContrato(fuera);
      if (p.tipo === "solicitud_vacacion") setSolicitudesVacaciones(fuera);
      if (p.tipo === "solicitud_perfil") setSolicitudesPerfil(fuera);
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

    const solicitudPerfil = p.tipo === "solicitud_perfil" ? solicitudesPerfil.find((s) => s.id === p.itemId) : undefined;
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
    const { etiqueta, Icon } = MODULOS[p.modulo];
    const estaAbierta = abierta === p.clave;
    const soloVer = p.tipo === "solicitud_perfil"
      && !!solicitudesPerfil.find((s) => s.id === p.itemId)?.solo_do && !puedeVerIdentidad(rol);
    const verbo = soloVer ? "Ver" : p.tipo === "solicitud_vacacion" || p.tipo === "solicitud_perfil" ? "Resolver" : "Atender";
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
            {p.detalle && <div className="line-clamp-2 text-xs text-taupe">{p.detalle}</div>}
          </div>
          {/* De qué módulo */}
          <div className="flex items-center gap-1.5 text-xs text-taupe">
            <Icon className="size-3.5 shrink-0" aria-hidden />
            {etiqueta}
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

  const nombrePestana = { aqui: "Resolver aquí", afuera: "En otra pantalla" } as const;

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6">
        <CabeceraPagina titulo="Bandeja" descripcion="Todo lo que requiere tu atención, en un solo lugar." />

        {cargando ? (
          <Cargando />
        ) : !puedeEducacion && !puedeEquipo ? (
          <div className="max-w-2xl rounded-control bg-ambar/15 px-4 py-3 text-sm text-ambar">
            Esta pantalla es para quien opera el equipo — encargadas y Desarrollo Organizacional.
          </div>
        ) : pendientes.length === 0 && alertasConProblema === 0 ? (
          <SinDatos texto="Todo al día." pista="No tienes pendientes que requieran atención. Cuando algo lo necesite, va a aparecer aquí." />
        ) : (
          <>
            {/* ── Resumen: también son filtros ─────────────────────────── */}
            <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
              {GRUPOS_URGENCIA.map((g) => {
                const n = porSede.filter((p) => p.urgencia.grupo === g.clave).length;
                const activo = grupoFiltro === g.clave;
                return (
                  <button
                    key={g.clave}
                    id={`resumen-${g.clave}`}
                    type="button"
                    aria-pressed={activo}
                    title={activo ? "Quitar este filtro" : `Ver solo: ${g.etiqueta.toLowerCase()}`}
                    onClick={() => setGrupoFiltro(activo ? null : g.clave)}
                    className={cx(
                      "flex flex-col items-start gap-0.5 rounded-control border bg-papel px-3 py-2.5 text-left transition-colors duration-150",
                      activo ? "border-tinta ring-1 ring-tinta" : "border-sand hover:border-taupe/60",
                    )}
                  >
                    <span className="flex items-center gap-1.5 text-xs text-taupe"><MarcaGrupo grupo={g.clave} />{g.etiqueta}</span>
                    <span className={cx("text-2xl font-medium tabular-nums",
                      g.clave === "vencido" && n > 0 ? "text-rojo-profundo" : "text-tinta")}>{n}</span>
                  </button>
                );
              })}
            </div>

            {/* ── Buscar y filtrar ─────────────────────────────────────── */}
            <div className="mt-4 flex flex-wrap items-center gap-2">
              <label className="flex min-w-48 flex-1 items-center gap-2 rounded-control border border-sand bg-hueso px-3 focus-within:border-taupe focus-within:ring-2 focus-within:ring-rojo/30">
                <Search className="size-4 shrink-0 text-taupe" aria-hidden />
                <input
                  id="bandeja-buscar"
                  type="search"
                  value={busca}
                  onChange={(e) => setBusca(e.target.value)}
                  placeholder="Buscar persona o pendiente…"
                  aria-label="Buscar persona o pendiente"
                  className="w-full bg-transparent py-2 text-base text-tinta outline-none placeholder:text-taupe/60 sm:text-sm"
                />
              </label>
              {puedeTodasLasSedes && (
                <select
                  id="bandeja-sede"
                  aria-label="Sede"
                  value={sedeEfectiva ?? ""}
                  onChange={(e) => elegirSedeFiltro(e.target.value || null)}
                  className={SELECT}
                >
                  <option value="">Todas las sedes · {porTextoYModulo.length}</option>
                  {opcionesSede.map((s) => (
                    <option key={s.codigo} value={s.codigo}>
                      {s.codigo}{s.nombre ? ` — ${s.nombre}` : ""} · {porTextoYModulo.filter((p) => p.sede === s.codigo).length}
                    </option>
                  ))}
                </select>
              )}
              {modulosPresentes.length > 1 && (
                <select
                  id="bandeja-modulo"
                  aria-label="Módulo"
                  value={moduloFiltro}
                  onChange={(e) => setModuloFiltro(e.target.value as Modulo | "")}
                  className={SELECT}
                >
                  <option value="">Todos los módulos</option>
                  {modulosPresentes.map((m) => <option key={m} value={m}>{MODULOS[m].etiqueta}</option>)}
                </select>
              )}
              {hayFiltros && <Boton variante="enlace" onClick={limpiarFiltros} className="text-sm text-rojo">Limpiar filtros</Boton>}
            </div>
            {!puedeTodasLasSedes && <p className="mt-1.5 text-xs text-taupe">Ves solo lo de tu sede.</p>}

            {/* ── Sistema: salud del despacho de correos, no una tarea ─── */}
            {resumenAlertas && alertasConProblema > 0 && (
              <details className="group mt-4 rounded-control border border-pizarra/30 bg-pizarra/5 px-4 py-2.5 text-sm">
                <summary className="flex cursor-pointer list-none flex-wrap items-center gap-2">
                  <span className="rounded bg-pizarra/15 px-2 py-0.5 text-[11px] font-medium uppercase tracking-wide text-pizarra">Sistema</span>
                  <span>
                    <strong>{alertasConProblema} aviso{alertasConProblema === 1 ? "" : "s"} por correo</strong>{" "}
                    no va{alertasConProblema === 1 ? "" : "n"} a salir solo{alertasConProblema === 1 ? "" : "s"}.
                  </span>
                  <span className="text-rojo group-open:hidden">Ver qué pasó →</span>
                </summary>
                <ul className="mt-2 space-y-2">
                  {resumenAlertas.fallidas_definitivas > 0 && (
                    <li className="rounded-control border border-pizarra/30 bg-papel p-3">
                      <strong className="text-rojo-profundo">
                        {resumenAlertas.fallidas_definitivas} fall{resumenAlertas.fallidas_definitivas === 1 ? "ó" : "aron"} tres veces
                      </strong>
                      <span className="text-taupe"> — ya no se reintentan. </span>
                      {resumenAlertas.motivos_definitivos.length > 0 ? (
                        <>
                          Motivo del último intento:
                          <ul className="mt-1 list-disc pl-5 text-taupe">
                            {resumenAlertas.motivos_definitivos.map((m) => <li key={m}>{m}</li>)}
                          </ul>
                          <span className="mt-1 block">
                            Si dice «sin encargada con correo», se arregla en Equipo dándole correo a la encargada de esa sede;
                            si es de Resend, revisa la clave <code>RESEND_API_KEY</code> y el dominio verificado.
                          </span>
                        </>
                      ) : (
                        <>Sin nota del motivo: revisa en Sentry el último despacho y la cuenta de Resend (clave <code>RESEND_API_KEY</code> y dominio verificado).</>
                      )}
                    </li>
                  )}
                  {resumenAlertas.atascadas > 0 && (
                    <li className="rounded-control border border-pizarra/30 bg-papel p-3">
                      <strong className="text-ambar">
                        {resumenAlertas.atascadas} qued{resumenAlertas.atascadas === 1 ? "ó" : "aron"} a medio despachar
                      </strong>
                      <span className="text-taupe"> hace más de una hora. </span>
                      Se reintentan solos en el próximo despacho (hasta tres veces); si vuelve a pasar, revisa en Sentry por qué se corta.
                    </li>
                  )}
                  {resumenAlertas.caducadas > 0 && (
                    <li className="rounded-control border border-pizarra/30 bg-papel p-3">
                      <strong className="text-ambar">
                        {resumenAlertas.caducadas} caduc{resumenAlertas.caducadas === 1 ? "ó" : "aron"} sin salir
                      </strong>
                      <span className="text-taupe"> — más de siete días sin despacho. </span>
                      Ya no se van a mandar: si el aviso todavía importa, hay que darlo a mano.
                    </li>
                  )}
                </ul>
                <p className="mt-2 text-taupe">
                  {resumenAlertas.despachables} esperando el próximo despacho ·{" "}
                  {resumenAlertas.ultimo_envio_at
                    ? `último correo enviado el ${diaLima(resumenAlertas.ultimo_envio_at)}`
                    : "todavía no salió ningún correo"}
                  {" "}— si esa fecha se aleja, el cron dejó de correr.
                </p>
              </details>
            )}

            {/* ── Pestañas por dónde se resuelve ───────────────────────── */}
            <div role="tablist" aria-label="Dónde se resuelve" className="mt-5 flex gap-6 border-b border-sand">
              {(["aqui", "afuera"] as const).map((t) => {
                const lista = t === "aqui" ? aqui : afuera;
                const vencidos = lista.filter((p) => p.urgencia.grupo === "vencido").length;
                const seleccionada = pestanaActiva === t;
                return (
                  <button
                    key={t}
                    id={`pestana-${t}`}
                    type="button"
                    role="tab"
                    aria-selected={seleccionada}
                    aria-controls="bandeja-lista"
                    onClick={() => { setPestana(t); setAbierta(null); }}
                    className={cx(
                      "-mb-px flex flex-wrap items-center gap-2 border-b-2 py-2 text-sm transition-colors duration-150",
                      seleccionada ? "border-rojo font-medium text-tinta" : "border-transparent text-taupe hover:text-tinta",
                    )}
                  >
                    {nombrePestana[t]} <span className="tabular-nums">{lista.length}</span>
                    {vencidos > 0 && (
                      <span className="rounded-full bg-rojo/10 px-2 py-0.5 text-xs font-medium text-rojo-profundo">
                        {vencidos} vencido{vencidos === 1 ? "" : "s"}
                      </span>
                    )}
                  </button>
                );
              })}
            </div>
            <p className="mt-2 text-xs text-taupe">
              {pestanaActiva === "aqui"
                ? "Se aprueban o se atienden sin salir de la Bandeja."
                : "Cada uno se arregla en su módulo: el botón te lleva ahí."}
            </p>

            {/* ── La lista ─────────────────────────────────────────────── */}
            <div id="bandeja-lista" role="tabpanel" aria-labelledby={`pestana-${pestanaActiva}`} className="@container mt-2">
              {listaActiva.length === 0 ? (
                <div className="mt-4 flex flex-col items-center gap-3 rounded-control border border-dashed border-sand py-10 text-center">
                  {hayFiltros && filtrados.length === 0 ? (
                    <>
                      <p className="font-serif text-lg text-tinta">No encontramos pendientes con estos filtros.</p>
                      <Boton variante="secundario" tamano="sm" onClick={limpiarFiltros}>Limpiar filtros</Boton>
                    </>
                  ) : (
                    <>
                      <p className="font-serif text-lg text-tinta">
                        {pestanaActiva === "aqui" ? "Nada por resolver aquí." : "Nada pendiente en otras pantallas."}
                      </p>
                      {listaOtra.length > 0 && (
                        <Boton variante="secundario" tamano="sm" onClick={() => setPestana(pestanaActiva === "aqui" ? "afuera" : "aqui")}>
                          Ver «{nombrePestana[pestanaActiva === "aqui" ? "afuera" : "aqui"]}» · {listaOtra.length}
                        </Boton>
                      )}
                    </>
                  )}
                </div>
              ) : (
                <>
                  <div className={cx("sticky top-0 z-10 hidden gap-x-4 border-b border-sand bg-crema px-4 py-2 text-[11px] font-semibold uppercase tracking-wider text-taupe @3xl:grid", COLUMNAS)}>
                    <span>Persona</span><span>Pendiente</span><span>Origen</span><span>Plazo</span><span className="text-right">Acción</span>
                  </div>
                  {GRUPOS_URGENCIA.map((g) => {
                    const delGrupo = listaActiva.filter((p) => p.urgencia.grupo === g.clave);
                    if (delGrupo.length === 0) return null;
                    return (
                      <section key={g.clave} aria-labelledby={`grupo-${g.clave}`} className="mt-3">
                        <h2 id={`grupo-${g.clave}`} className="flex flex-wrap items-center gap-2 px-1 pb-2 pt-1 text-[11px] font-semibold uppercase tracking-wider text-tinta">
                          <MarcaGrupo grupo={g.clave} />
                          {g.etiqueta}
                          <span className="font-normal tabular-nums text-taupe">· {delGrupo.length}</span>
                          <span className="font-normal normal-case tracking-normal text-taupe">— {g.descripcion}</span>
                        </h2>
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
