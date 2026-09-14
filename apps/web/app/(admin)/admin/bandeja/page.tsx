"use client";

// ============================================================================
// Bandeja — lo que hoy solo se ve como un número en el menú, en un solo lugar.
// ----------------------------------------------------------------------------
// QUÉ PROMETE. Educación, Ausencias e Incidencias ya avisan, cada una con su
// número en el menú, cuando algo suyo necesita atención. Esta pantalla no
// inventa un criterio nuevo de "pendiente": pide las MISMAS RPC que ya corren
// para esos contadores —o la lista completa detrás del mismo número, cuando
// la RPC del contador solo da un total— y las junta.
//
// QUÉ NO HACE. No resuelve nada que ya tenga su propio formulario. Educación
// (adjuntar un comprobante, cerrar una asignación) y Ausencias (registrar el
// descanso) siguen viviendo en sus pantallas; acá solo se enlaza. Dos
// excepciones, y por la misma razón: Revisiones ("marcar atendida") y
// Solicitudes de vacaciones (aprobar/rechazar) son cada una una sola RPC con
// un texto opcional, así que resolverlas acá mismo —sin salir de la
// bandeja— no duplica ningún formulario, solo evita un clic.
//
// A quién se le muestra. Ausencias/Revisiones a quien puede operar el equipo
// (encargada y DO); Educación y Solicitudes de vacaciones solo a DO —esta
// última con la misma regla que ya rige fn_aprobar_ausencia: aprobar
// convierte días en plata, y eso no lo decide quien opera el día a día de la
// sede. Si alguien sin ninguno de los dos permisos entra por la URL, ninguna
// RPC le devuelve nada —RLS decide, no esta pantalla— y ve la bandeja vacía.
//
// ── Rediseño (ADR 0002, 2026-09-13) ─────────────────────────────────────────
// Dos zonas, no una lista plana: "Por aprobar" (exige un clic tuyo) y "Para
// saber" (informa y enlaza a otra pantalla) — antes las 9 secciones se veían
// idénticas aunque solo 5 tuvieran botón. "Avisos por correo" no es ninguna
// de las dos: es salud del cron, no una tarea de una persona, así que lleva
// su propia franja con los tokens de "informativo" del sistema de diseño.
//
// "Nuevo desde tu última visita" (bandeja_vistos, migración 0436) solo cubre
// la zona "Por aprobar": es la única zona que se resuelve acá, así que es la
// única donde "ya lo vi" cambia algo. Simplificación a propósito: se marca
// visto TODO lo que la RPC trajo, no solo lo que el filtro de sede deja ver
// en pantalla — si alguien filtra por su sede y nunca mira las demás, un
// ítem ajeno puede perder el aviso de "nuevo" una visita antes de tiempo.
// Aceptable: sigue siendo visible al cambiar el filtro, solo sin la marca.
// ============================================================================

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Cargando, SinDatos } from "@/components/cargando";
import { Boton } from "@/components/ui/boton";
import { Campo } from "@/components/ui/campo";
import { useToast } from "@/components/toast";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { BUCKET_SOLICITUDES_PERFIL } from "@/lib/foto-dni";
import {
  fechaLima, puedeGestionarCatalogos, puedeGestionarContratos, puedeOperarEquipo, puedeVerIdentidad,
  puedeVerPlanilla, puedeVerSaludDeAlertas,
} from "@cayla-dynamic/shared";

type TipoItemBandeja =
  | "revision" | "revision_movilidad" | "revision_contrato"
  | "solicitud_vacacion" | "solicitud_perfil";

const CLAVE_SEDE_FILTRO = "bandeja_sede_filtro";

interface ItemEducacion {
  id: string;
  persona: string;
  sede: string;
  rango: string;
  dias_para_vencer: number;
  meses_sin_papel: number;
  semaforo: "sin_comprobante" | "vencida" | "por_vencer" | "vigente";
}

/** Alguien que trabajó días que su horario no cubre (mig. 0385). La función ya
 *  excluye a quien no le toca llevar horario (RxH y personal de dirección), así
 *  que todo lo que llega aquí es un hueco de verdad. */
interface ItemSinHorario {
  persona_id: string; nombre: string; sede: string;
  dias: number; primer_dia: string; ultimo_dia: string;
  nunca_tuvo_horario: boolean;
}
function detalleSinHorario(h: ItemSinHorario): string {
  const dias = `${h.dias} día${h.dias === 1 ? "" : "s"}`;
  return h.nunca_tuvo_horario
    ? `${dias} · nunca se le cargó un horario`
    : `${dias} sin cubrir · ${h.primer_dia} a ${h.ultimo_dia}`;
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
  id: string;
  persona_id: string;
  nombre: string;
  sede: string;
  fecha: string;
  comentario: string;
  pedida_at: string;
}

/** Un pedido de revisión de una declaración de ruta (0425). Mismo molde que
 *  ItemRevision, sobre movilidad_revisiones_pedidas en vez de revisiones_pedidas —
 *  no lleva `fecha` porque no hay "el día que se revisa", solo un motivo. */
interface ItemRevisionMovilidad {
  id: string;
  persona_id: string;
  nombre: string;
  sede: string;
  motivo: string;
  pedida_at: string;
}

/** Un pedido de revisión de un contrato ya generado (0427). Mismo molde que
 *  ItemRevisionMovilidad, sobre contrato_revisiones_pedidas. */
interface ItemRevisionContrato {
  id: string;
  persona_id: string;
  nombre: string;
  sede: string;
  motivo: string;
  pedida_at: string;
}

interface ItemSolicitudVacacion {
  id: string;
  persona_id: string;
  nombre: string;
  sede: string;
  fecha_inicio: string;
  fecha_fin: string;
  dias: number;
  comentario: string | null;
  pedida_at: string;
}

/** Una propuesta de cambio de perfil por resolver (migración 0399). */
interface ItemSolicitudPerfil {
  id: string;
  persona_id: string;
  nombre: string;
  sede: string;
  campo: string;
  etiqueta: string;
  valor_anterior: Record<string, unknown>;
  valor_propuesto: Record<string, unknown>;
  rutas_adjuntas: string[];
  creada_at: string;
  /** Este campo solo lo aprueba DO, aunque la encargada vea la solicitud (0405).
   *  Lo dice el catálogo, no esta pantalla: `catalogo_campos_perfil.solo_do`. */
  solo_do: boolean;
}

/** «celular: 987654321, direccion: Av. Uno 123» — genérico a propósito: son
 *  campos con formas distintas, y esto solo es para que quien aprueba vea
 *  de un vistazo qué cambia, no para imprimir un documento.
 *
 *  Con una excepción, desde la 0401: cuando el valor ES un archivo (la foto del
 *  DNI), su valor es una ruta del almacén —`solicitud/<uuid>/dni-anverso-….jpg`,
 *  sesenta caracteres que no dicen nada y empujan el resto de la fila fuera de
 *  la pantalla—. Ahí se anuncia la cara y ya está: lo que hay que mirar es la
 *  imagen, y para eso están los botones de adjuntos de abajo. */
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

// "2026-07-13" → "13/07/2026" — la misma aritmética de string que ya usa el
// resto del panel, sin pasar por Date ni arriesgar un desfase de zona horaria.
function fmtFecha(iso: string): string {
  const [y, m, d] = iso.split("-");
  return `${d}/${m}/${y}`;
}

// Un timestamptz de la base ("2026-09-03T12:00:14.1+00:00") → "03/09/2026", en
// el día de Lima. Solo hace falta el día: la hora exacta del último correo no
// le dice nada a quien mira la tarjeta; que sea de hace una semana, sí.
function fmtDiaLima(ts: string): string {
  return fmtFecha(fechaLima(ts));
}

// A diferencia de fmtDiaLima, acá SÍ importa cuánto tiempo pasó, no solo el
// día calendario — por eso es aritmética de milisegundos y no de fecha Lima:
// "hace 3 días" no cambia por el huso horario de quien mira la pantalla.
function diasDesde(iso: string): number {
  return Math.max(0, Math.floor((Date.now() - new Date(iso).getTime()) / 86_400_000));
}

// Alarma desde el día 8: el mismo plazo que ya exige el reglamento de
// disciplina de este sistema para pedir reiteración (ver docs/disciplina-*).
function antiguedad(iso: string): { texto: string; alarma: boolean } {
  const dias = diasDesde(iso);
  const texto = dias === 0 ? "pedido hoy" : dias === 1 ? "hace 1 día" : `hace ${dias} días`;
  return { texto, alarma: dias >= 8 };
}

function detalleEducacion(f: ItemEducacion): string {
  if (f.semaforo === "sin_comprobante") return "sin comprobante";
  if (f.semaforo === "vencida") return "vencida";
  if (f.semaforo === "por_vencer") return `vence en ${f.dias_para_vencer} día${f.dias_para_vencer === 1 ? "" : "s"}`;
  return `${f.meses_sin_papel} mes${f.meses_sin_papel === 1 ? "" : "es"} sin papel`;
}

function detalleVacacion(v: ItemVacacion): string {
  if (v.records_vencidos > 0) return `${v.records_vencidos} récord${v.records_vencidos === 1 ? "" : "s"} ya vencido${v.records_vencidos === 1 ? "" : "s"}`;
  return `vence el ${fmtFecha(v.vence_el)} · en ${v.dias_para_vencer} día${v.dias_para_vencer === 1 ? "" : "s"}`;
}

function rangoSolicitud(s: ItemSolicitudVacacion): string {
  const rango = s.fecha_inicio === s.fecha_fin ? fmtFecha(s.fecha_inicio) : `${fmtFecha(s.fecha_inicio)} – ${fmtFecha(s.fecha_fin)}`;
  return `${rango} · ${s.dias} día${s.dias === 1 ? "" : "s"}`;
}

/** Insignia "Nuevo desde tu última visita" — solo aparece si el ítem no
 *  estaba en bandeja_vistos cuando esta visita empezó a cargar. */
function InsigniaNuevo() {
  return (
    <span className="rounded-full bg-rojo/15 px-2 py-0.5 text-xs font-medium text-rojo">
      Nuevo
    </span>
  );
}

/** "hace N días", en rojo y negrita desde el día 8. */
function Antiguedad({ pedidaAt }: { pedidaAt: string }) {
  const { texto, alarma } = antiguedad(pedidaAt);
  return (
    <span className={alarma ? "font-medium text-rojo" : "text-taupe"}>
      {texto}{alarma ? " — más de una semana esperando" : ""}
    </span>
  );
}

export default function BandejaPage() {
  const router = useRouter();
  const persona = usePersonaActual();
  const rol = persona?.rol ?? null;
  const { avisar } = useToast();

  const puedeEducacion = puedeVerPlanilla(rol);
  const puedeEquipo = puedeOperarEquipo(rol);
  // Resolver una solicitud de vacaciones crea plata (o la corta): misma regla
  // que fn_resolver_solicitud_vacaciones ya exige en el servidor, y la misma
  // que ya usa fn_aprobar_ausencia — es DO, nunca la encargada de la sede.
  const puedeResolverVacaciones = puedeVerPlanilla(rol);
  const puedeSaludAlertas = puedeVerSaludDeAlertas(rol);
  // CAMBIO 0403 — Antes era DO en exclusiva (ADR 0001, DECIDÍ #9). Se revirtió
  // al día siguiente de confirmarse, al construir /mio/editar: la encargada de
  // sede también resuelve, pero solo lo de su propio equipo — el guard vive en
  // fn_resolver_solicitud_perfil/fn_solicitudes_perfil_pendientes, esto solo
  // decide si se le muestra la sección. Ver la "Corrección tras implementar
  // (2026-09-08)" al final del ADR.
  const puedeResolverPerfil = puedeOperarEquipo(rol);
  // Mismo alcance que `fn_movilidad_revisiones_pedidas` (0425): admin/líder,
  // sin la encargada de sede — a diferencia de las revisiones de marcaje, que
  // sí le llegan a ella. La declaración de ruta es papeleo legal/tributario,
  // no operación del día a día de una sede.
  const puedeMovilidad = puedeGestionarCatalogos(rol);
  // El contrato es papeleo legal/laboral igual que la declaración de ruta,
  // pero con su propio permiso (`puedeGestionarContratos`) porque es el que
  // ya usa admin/contratos para decidir quién entra ahí — no se inventa un
  // criterio nuevo solo para la Bandeja.
  const puedeContratos = puedeGestionarContratos(rol);

  const [cargando, setCargando] = useState(true);
  const [resumenAlertas, setResumenAlertas] = useState<ResumenAlertas | null>(null);
  const [educacion, setEducacion] = useState<ItemEducacion[]>([]);
  const [vacaciones, setVacaciones] = useState<ItemVacacion[]>([]);
  const [sinHorario, setSinHorario] = useState<ItemSinHorario[]>([]);
  const [revisiones, setRevisiones] = useState<ItemRevision[]>([]);
  const [revisionesMovilidad, setRevisionesMovilidad] = useState<ItemRevisionMovilidad[]>([]);
  const [revisionesContrato, setRevisionesContrato] = useState<ItemRevisionContrato[]>([]);
  const [solicitudesVacaciones, setSolicitudesVacaciones] = useState<ItemSolicitudVacacion[]>([]);
  const [solicitudesPerfil, setSolicitudesPerfil] = useState<ItemSolicitudPerfil[]>([]);
  const [vistosIniciales, setVistosIniciales] = useState<Set<string>>(new Set());
  const [respuestas, setRespuestas] = useState<Record<string, string>>({});
  const [respuestasMovilidad, setRespuestasMovilidad] = useState<Record<string, string>>({});
  const [respuestasContrato, setRespuestasContrato] = useState<Record<string, string>>({});
  const [motivosRechazo, setMotivosRechazo] = useState<Record<string, string>>({});
  const [motivosPerfil, setMotivosPerfil] = useState<Record<string, string>>({});
  const [atendiendo, setAtendiendo] = useState<string | null>(null);
  const [atendiendoMovilidad, setAtendiendoMovilidad] = useState<string | null>(null);
  const [atendiendoContrato, setAtendiendoContrato] = useState<string | null>(null);
  const [resolviendo, setResolviendo] = useState<string | null>(null);
  const [resolviendoPerfil, setResolviendoPerfil] = useState<string | null>(null);
  const [sedeFiltro, setSedeFiltro] = useState<string | null>(null);

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
      tareas.push(
        supabase.rpc("fn_educacion_listar").then(({ data, error }) => {
          if (error) { avisar("error", mensajeDeError(error, "cargar educación")); return; }
          // Mismo criterio que fn_educacion_por_atender (0290): el comentario
          // de la propia pantalla de Educación explica por qué — ver ahí antes
          // de tocar esto, para no separar los dos criterios.
          const filas = ((data as unknown as ItemEducacion[]) ?? []).filter(
            (f) => f.semaforo === "sin_comprobante" || f.semaforo === "por_vencer" || f.meses_sin_papel > 0,
          );
          setEducacion(filas);
        }),
      );
    } else {
      setEducacion([]);
    }

    if (puedeEquipo) {
      tareas.push(
        supabase.rpc("fn_vacaciones_por_vencer", { p_dias: 60, p_as_of: null }).then(({ data, error }) => {
          if (error) { avisar("error", mensajeDeError(error, "cargar vacaciones por vencer")); return; }
          setVacaciones((data as unknown as ItemVacacion[]) ?? []);
        }),
      );
      tareas.push(
        // Falla suave a propósito: si la base todavía no tiene la 0385, la
        // bandeja sigue funcionando igual, solo sin esta sección.
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
        // bandeja_vistos (0436): qué ítems de "Por aprobar" ya vio ESTA
        // persona. Falla suave — sin ella, todo se ve simplemente sin
        // insignia de "Nuevo", nunca al revés.
        supabase.from("bandeja_vistos").select("tipo_item,item_id").then(({ data }) => {
          const set = new Set<string>((data ?? []).map((v) => `${v.tipo_item}:${v.item_id}`));
          setVistosIniciales(set);
        }),
      );
    } else {
      setVacaciones([]);
      setRevisiones([]);
      setSinHorario([]);
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
          // Un fallo acá se ignora a propósito, sin toast: esta tarjeta es un
          // chequeo de salud, no una tarea pendiente, y entre fusionar este
          // cambio y pegar la 0362 en producción la RPC no existe todavía —
          // un aviso rojo en cada visita a la Bandeja por eso sería ruido.
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
      puedeResolverPerfil, puedeSaludAlertas, avisar]);

  // Cargar al montar es el mismo patrón que usa cada pantalla del panel que
  // trae datos de la base (Equipo, Ausencias, Disciplina...); el aviso de acá
  // es el mismo que ya tienen todas ellas sin corregir.
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void cargar(); }, [cargar]);

  // Marcar visto TODO lo que "Por aprobar" trajo, una vez que terminó de
  // cargar — así la insignia de "Nuevo" de esta visita se calculó ANTES
  // (con vistosIniciales, congelado al momento de cargar) y la próxima
  // visita ya no la va a mostrar para lo mismo. Fire-and-forget: si una
  // marca falla, la próxima visita simplemente la vuelve a ofrecer como
  // "Nuevo" — no es una pérdida de datos, es como si nunca se hubiera visto.
  useEffect(() => {
    if (cargando) return;
    const supabase = createAdminSupabaseClient();
    const items: Array<[TipoItemBandeja, string]> = [
      ...revisiones.map((r): [TipoItemBandeja, string] => ["revision", r.id]),
      ...revisionesMovilidad.map((r): [TipoItemBandeja, string] => ["revision_movilidad", r.id]),
      ...revisionesContrato.map((r): [TipoItemBandeja, string] => ["revision_contrato", r.id]),
      ...solicitudesVacaciones.map((s): [TipoItemBandeja, string] => ["solicitud_vacacion", s.id]),
      ...solicitudesPerfil.map((s): [TipoItemBandeja, string] => ["solicitud_perfil", s.id]),
    ];
    for (const [tipo, id] of items) {
      if (!vistosIniciales.has(`${tipo}:${id}`)) {
        void supabase.rpc("fn_bandeja_marcar_visto", { p_tipo_item: tipo, p_item_id: id });
      }
    }
    // Solo cuando termina de cargar: no queremos volver a marcar en cada
    // render, solo una vez por visita.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cargando]);

  async function marcarAtendida(id: string) {
    setAtendiendo(id);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_atender_revision", {
      p_id: id, p_respuesta: (respuestas[id] ?? "").trim() || null,
    });
    setAtendiendo(null);
    if (error) { avisar("error", mensajeDeError(error, "marcar la revisión como atendida")); return; }
    setRevisiones((r) => r.filter((x) => x.id !== id));
    avisar("ok", "Revisión marcada como atendida.");
  }

  async function marcarAtendidaMovilidad(id: string) {
    setAtendiendoMovilidad(id);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_atender_revision_movilidad", {
      p_id: id, p_respuesta: (respuestasMovilidad[id] ?? "").trim() || null,
    });
    setAtendiendoMovilidad(null);
    if (error) { avisar("error", mensajeDeError(error, "marcar la revisión de movilidad como atendida")); return; }
    setRevisionesMovilidad((r) => r.filter((x) => x.id !== id));
    avisar("ok", "Revisión de movilidad marcada como atendida.");
  }

  async function marcarAtendidaContrato(id: string) {
    setAtendiendoContrato(id);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_atender_revision_contrato", {
      p_id: id, p_respuesta: (respuestasContrato[id] ?? "").trim() || null,
    });
    setAtendiendoContrato(null);
    if (error) { avisar("error", mensajeDeError(error, "marcar la revisión de contrato como atendida")); return; }
    setRevisionesContrato((r) => r.filter((x) => x.id !== id));
    avisar("ok", "Revisión de contrato marcada como atendida.");
  }

  async function resolverSolicitud(id: string, aprobar: boolean) {
    setResolviendo(id);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_resolver_solicitud_vacaciones", {
      p_id: id, p_aprobar: aprobar, p_respuesta: (motivosRechazo[id] ?? "").trim() || null,
    });
    setResolviendo(null);
    if (error) { avisar("error", mensajeDeError(error, aprobar ? "aprobar la solicitud" : "rechazar la solicitud")); return; }
    setSolicitudesVacaciones((s) => s.filter((x) => x.id !== id));
    avisar("ok", aprobar ? "Vacaciones aprobadas." : "Solicitud rechazada.");
  }

  async function resolverSolicitudPerfil(id: string, aprobar: boolean) {
    setResolviendoPerfil(id);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_resolver_solicitud_perfil", {
      p_id: id, p_aprobar: aprobar, p_motivo: (motivosPerfil[id] ?? "").trim() || undefined,
    });
    setResolviendoPerfil(null);
    if (error) { avisar("error", mensajeDeError(error, aprobar ? "aprobar la solicitud" : "rechazar la solicitud")); return; }
    setSolicitudesPerfil((s) => s.filter((x) => x.id !== id));
    avisar("ok", aprobar ? "Cambio aprobado." : "Solicitud rechazada.");
  }

  /** El bucket es privado: cada documento se abre con una URL firmada, pedida
   *  al momento de mirar — nunca se firman todos de golpe. */
  async function verDocumentoPerfil(ruta: string) {
    const supabase = createAdminSupabaseClient();
    const { data, error } = await supabase.storage.from(BUCKET_SOLICITUDES_PERFIL).createSignedUrl(ruta, 300);
    if (error || !data) { avisar("error", "No se pudo abrir el documento."); return; }
    window.open(data.signedUrl, "_blank", "noopener,noreferrer");
  }

  // La tarjeta de avisos por correo solo aparece cuando hay algo que una
  // persona tiene que mirar: lo que se va a reintentar solo no se muestra.
  const alertasConProblema = resumenAlertas
    ? resumenAlertas.atascadas + resumenAlertas.fallidas_definitivas + resumenAlertas.caducadas
    : 0;

  const total = educacion.length + vacaciones.length + revisiones.length + revisionesMovilidad.length
    + revisionesContrato.length + solicitudesVacaciones.length + solicitudesPerfil.length
    + alertasConProblema + sinHorario.length;

  // Nunca una lista escrita a mano de sedes (regla #3 de este repo): las
  // opciones del filtro salen de lo que de verdad trajeron las RPC hoy, no
  // de un enum. Si mañana abre una quinta sede, aparece sola.
  const sedesDisponibles = useMemo(() => {
    const todas = [
      ...educacion, ...vacaciones, ...sinHorario, ...revisiones, ...revisionesMovilidad,
      ...revisionesContrato, ...solicitudesVacaciones, ...solicitudesPerfil,
    ].map((x) => x.sede);
    return Array.from(new Set(todas)).sort();
  }, [educacion, vacaciones, sinHorario, revisiones, revisionesMovilidad, revisionesContrato,
      solicitudesVacaciones, solicitudesPerfil]);

  function filtradas<T extends { sede: string }>(items: T[]): T[] {
    return sedeFiltro ? items.filter((x) => x.sede === sedeFiltro) : items;
  }

  const revisionesF = filtradas(revisiones);
  const revisionesMovilidadF = filtradas(revisionesMovilidad);
  const revisionesContratoF = filtradas(revisionesContrato);
  const solicitudesVacacionesF = filtradas(solicitudesVacaciones);
  const solicitudesPerfilF = filtradas(solicitudesPerfil);
  const sinHorarioF = filtradas(sinHorario);
  const vacacionesF = filtradas(vacaciones);
  const educacionF = filtradas(educacion);

  const totalPorAprobar = revisionesF.length + revisionesMovilidadF.length + revisionesContratoF.length
    + solicitudesVacacionesF.length + solicitudesPerfilF.length;
  const totalParaSaber = sinHorarioF.length + vacacionesF.length + educacionF.length;

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6">
        <h1 className="mb-1 font-serif text-2xl">Bandeja</h1>
        <p className="mb-4 max-w-2xl text-sm text-taupe">
          Lo que hoy solo se ve como un número en el menú, junto en un solo lugar.
        </p>

        {!cargando && sedesDisponibles.length > 1 && (
          <div className="mb-6 flex flex-wrap gap-2">
            <button
              onClick={() => elegirSedeFiltro(null)}
              className={`rounded-full px-3 py-1 text-xs font-medium ${
                sedeFiltro === null ? "bg-tinta text-crema" : "bg-sand text-taupe hover:bg-sand/70"
              }`}
            >
              Todas las sedes
            </button>
            {sedesDisponibles.map((s) => (
              <button
                key={s}
                onClick={() => elegirSedeFiltro(s)}
                className={`rounded-full px-3 py-1 text-xs font-medium ${
                  sedeFiltro === s ? "bg-tinta text-crema" : "bg-sand text-taupe hover:bg-sand/70"
                }`}
              >
                {s}
              </button>
            ))}
          </div>
        )}

        {cargando ? (
          <Cargando />
        ) : !puedeEducacion && !puedeEquipo ? (
          <div className="max-w-2xl rounded-lg bg-ambar/15 px-4 py-3 text-sm text-ambar">
            Esta pantalla es para quien opera el equipo — encargadas y Desarrollo Organizacional.
          </div>
        ) : total === 0 ? (
          <SinDatos texto="No hay nada pendiente." pista="Cuando algo necesite atención, va a aparecer aquí." />
        ) : sedeFiltro && totalPorAprobar + totalParaSaber === 0 && !(resumenAlertas && alertasConProblema > 0) ? (
          <SinDatos
            texto={`Nada pendiente en ${sedeFiltro}.`}
            pista="Hay pendientes en otras sedes — quita el filtro de arriba para verlos."
          />
        ) : (
          <div className="grid items-start gap-6 xl:grid-cols-2">
            {resumenAlertas && alertasConProblema > 0 && (
              <section className="rounded-2xl border border-sand bg-papel p-5">
                <h2 className="mb-1 flex items-center gap-2 font-serif text-lg text-pizarra">
                  <span className="rounded bg-pizarra/15 px-2 py-0.5 text-xs font-medium uppercase tracking-wide">
                    Sistema
                  </span>
                  Avisos por correo
                </h2>
                <p className="mb-3 text-sm text-taupe">
                  El despacho diario de avisos (auto-cierres, contratos y vacaciones por vencer) dejó
                  {" "}{alertasConProblema} aviso{alertasConProblema === 1 ? "" : "s"} que no va{alertasConProblema === 1 ? "" : "n"} a salir solo{alertasConProblema === 1 ? "" : "s"}.
                  Esto no es tarea de una persona: es el cron avisando que algo suyo se rompió.
                </p>
                <ul className="space-y-2 text-sm">
                  {resumenAlertas.fallidas_definitivas > 0 && (
                    <li className="rounded-xl border border-pizarra/30 bg-pizarra/5 p-3">
                      <strong className="text-rojo">
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
                    <li className="rounded-xl border border-pizarra/30 bg-pizarra/5 p-3">
                      <strong className="text-ambar">
                        {resumenAlertas.atascadas} qued{resumenAlertas.atascadas === 1 ? "ó" : "aron"} a medio despachar
                      </strong>
                      <span className="text-taupe"> hace más de una hora — la ejecución se cortó. </span>
                      Se reintentan solos en el próximo despacho (hasta tres veces); si vuelve a pasar, revisa en Sentry por qué se corta.
                    </li>
                  )}
                  {resumenAlertas.caducadas > 0 && (
                    <li className="rounded-xl border border-pizarra/30 bg-pizarra/5 p-3">
                      <strong className="text-ambar">
                        {resumenAlertas.caducadas} caduc{resumenAlertas.caducadas === 1 ? "ó" : "aron"} sin salir
                      </strong>
                      <span className="text-taupe"> — más de siete días sin despacho. </span>
                      Ya no se van a mandar: si el aviso todavía importa, hay que darlo a mano.
                    </li>
                  )}
                </ul>
                <p className="mt-2 text-sm text-taupe">
                  {resumenAlertas.despachables} esperando el próximo despacho ·{" "}
                  {resumenAlertas.ultimo_envio_at
                    ? `último correo enviado el ${fmtDiaLima(resumenAlertas.ultimo_envio_at)}`
                    : "todavía no salió ningún correo"}
                  {" "}— si esa fecha se aleja, el cron dejó de correr.
                </p>
              </section>
            )}

            {totalPorAprobar > 0 && (
              <div className="flex flex-col gap-8 rounded-2xl border border-sand bg-papel p-5">
                <h2 className="-mb-2 text-xs font-semibold uppercase tracking-wide text-taupe">
                  Por aprobar · {totalPorAprobar}
                </h2>

                {revisionesF.length > 0 && (
                  <section>
                    <h3 className="mb-1 font-serif text-lg">
                      Tu equipo pidió revisar {revisionesF.length} día{revisionesF.length === 1 ? "" : "s"}
                    </h3>
                    <p className="mb-3 text-sm text-taupe">
                      Lo escribieron desde «Lo mío». Corrige el día en Correcciones si hace falta y cierra acá
                      diciendo en qué quedó — esa respuesta la va a leer la persona.
                    </p>
                    <ul className="space-y-3">
                      {revisionesF.map((r) => (
                        <li key={r.id} className="rounded-xl border border-sand p-3 text-sm">
                          <div className="flex flex-wrap items-baseline justify-between gap-2">
                            <span className="flex flex-wrap items-baseline gap-2">
                              {!vistosIniciales.has(`revision:${r.id}`) && <InsigniaNuevo />}
                              <strong>{r.nombre}</strong>
                              <span className="text-taupe">· {r.sede} · {fmtFecha(r.fecha)} · <Antiguedad pedidaAt={r.pedida_at} /></span>
                            </span>
                            <Link href={`/admin/correcciones?persona=${r.persona_id}&fecha=${r.fecha}`}
                              className="text-rojo hover:underline">Abrir ese día en Correcciones →</Link>
                          </div>
                          <p className="mt-1.5">«{r.comentario}»</p>
                          <div className="mt-2 flex flex-col gap-2 sm:flex-row sm:items-center">
                            <div className="flex-1 sm:min-w-56">
                              <Campo
                                value={respuestas[r.id] ?? ""}
                                onChange={(e) => setRespuestas((x) => ({ ...x, [r.id]: e.target.value }))}
                                placeholder="En qué quedó (lo va a leer la persona)"
                              />
                            </div>
                            <Boton
                              variante="primario"
                              onClick={() => void marcarAtendida(r.id)}
                              cargando={atendiendo === r.id}
                              className="w-full sm:w-auto"
                            >
                              Marcar atendida
                            </Boton>
                          </div>
                        </li>
                      ))}
                    </ul>
                  </section>
                )}

                {/* Pedidos de revisión de una declaración de ruta ya firmada (0425).
                    No hay un "Abrir en Correcciones" análogo: si el pedido amerita
                    una declaración nueva, se registra desde admin/documentacion,
                    con el flujo de "Subir firmada" de siempre. Acá solo se cierra
                    la conversación con una respuesta. */}
                {revisionesMovilidadF.length > 0 && (
                  <section>
                    <h3 className="mb-1 font-serif text-lg">
                      {revisionesMovilidadF.length === 1
                        ? "Pidieron revisar una declaración de ruta"
                        : `Pidieron revisar ${revisionesMovilidadF.length} declaraciones de ruta`}
                    </h3>
                    <p className="mb-3 text-sm text-taupe">
                      Lo escribieron desde «Movilidad», en Lo mío. Si hace falta una declaración nueva, regístrala
                      en Documentación y cierra acá diciendo en qué quedó.
                    </p>
                    <ul className="space-y-3">
                      {revisionesMovilidadF.map((r) => (
                        <li key={r.id} className="rounded-xl border border-sand p-3 text-sm">
                          <div className="flex flex-wrap items-baseline justify-between gap-2">
                            <span className="flex flex-wrap items-baseline gap-2">
                              {!vistosIniciales.has(`revision_movilidad:${r.id}`) && <InsigniaNuevo />}
                              <strong>{r.nombre}</strong>
                              <span className="text-taupe">· {r.sede} · <Antiguedad pedidaAt={r.pedida_at} /></span>
                            </span>
                            <Link href={`/admin/documentacion?persona=${r.persona_id}`}
                              className="text-rojo hover:underline">Abrir en Documentación →</Link>
                          </div>
                          <p className="mt-1.5">«{r.motivo}»</p>
                          <div className="mt-2 flex flex-col gap-2 sm:flex-row sm:items-center">
                            <div className="flex-1 sm:min-w-56">
                              <Campo
                                value={respuestasMovilidad[r.id] ?? ""}
                                onChange={(e) => setRespuestasMovilidad((x) => ({ ...x, [r.id]: e.target.value }))}
                                placeholder="En qué quedó (lo va a leer la persona)"
                              />
                            </div>
                            <Boton
                              variante="primario"
                              onClick={() => void marcarAtendidaMovilidad(r.id)}
                              cargando={atendiendoMovilidad === r.id}
                              className="w-full sm:w-auto"
                            >
                              Marcar atendida
                            </Boton>
                          </div>
                        </li>
                      ))}
                    </ul>
                  </section>
                )}

                {/* Pedidos de revisión de un contrato ya generado (0427). Mismo
                    molde que la sección de movilidad de arriba: no hay un "Abrir
                    en Contratos" que filtre por persona (admin/contratos no lee
                    query params), así que enlaza a la pantalla a secas. */}
                {revisionesContratoF.length > 0 && (
                  <section>
                    <h3 className="mb-1 font-serif text-lg">
                      {revisionesContratoF.length === 1
                        ? "Pidieron revisar un contrato"
                        : `Pidieron revisar ${revisionesContratoF.length} contratos`}
                    </h3>
                    <p className="mb-3 text-sm text-taupe">
                      Lo escribieron desde «Contrato», en Lo mío. Si hace falta corregirlo, hazlo en Contratos y
                      cierra acá diciendo en qué quedó.
                    </p>
                    <ul className="space-y-3">
                      {revisionesContratoF.map((r) => (
                        <li key={r.id} className="rounded-xl border border-sand p-3 text-sm">
                          <div className="flex flex-wrap items-baseline justify-between gap-2">
                            <span className="flex flex-wrap items-baseline gap-2">
                              {!vistosIniciales.has(`revision_contrato:${r.id}`) && <InsigniaNuevo />}
                              <strong>{r.nombre}</strong>
                              <span className="text-taupe">· {r.sede} · <Antiguedad pedidaAt={r.pedida_at} /></span>
                            </span>
                            <Link href="/admin/contratos" className="text-rojo hover:underline">Abrir en Contratos →</Link>
                          </div>
                          <p className="mt-1.5">«{r.motivo}»</p>
                          <div className="mt-2 flex flex-col gap-2 sm:flex-row sm:items-center">
                            <div className="flex-1 sm:min-w-56">
                              <Campo
                                value={respuestasContrato[r.id] ?? ""}
                                onChange={(e) => setRespuestasContrato((x) => ({ ...x, [r.id]: e.target.value }))}
                                placeholder="En qué quedó (lo va a leer la persona)"
                              />
                            </div>
                            <Boton
                              variante="primario"
                              onClick={() => void marcarAtendidaContrato(r.id)}
                              cargando={atendiendoContrato === r.id}
                              className="w-full sm:w-auto"
                            >
                              Marcar atendida
                            </Boton>
                          </div>
                        </li>
                      ))}
                    </ul>
                  </section>
                )}

                {solicitudesVacacionesF.length > 0 && (
                  <section>
                    <h3 className="mb-1 font-serif text-lg">
                      {solicitudesVacacionesF.length} solicitud{solicitudesVacacionesF.length === 1 ? "" : "es"} de vacaciones por resolver
                    </h3>
                    <p className="mb-3 text-sm text-taupe">
                      Lo pidieron desde «Lo mío». Aprobar crea la ausencia real de una vez; rechazar exige decir por qué —esa respuesta la va a leer la persona.
                    </p>
                    <ul className="space-y-3">
                      {solicitudesVacacionesF.map((s) => (
                        <li key={s.id} className="rounded-xl border border-sand p-3 text-sm">
                          <div className="flex flex-wrap items-baseline justify-between gap-2">
                            <span className="flex flex-wrap items-baseline gap-2">
                              {!vistosIniciales.has(`solicitud_vacacion:${s.id}`) && <InsigniaNuevo />}
                              <strong>{s.nombre}</strong>
                              <span className="text-taupe">· {s.sede} · {rangoSolicitud(s)} · <Antiguedad pedidaAt={s.pedida_at} /></span>
                            </span>
                          </div>
                          {s.comentario && <p className="mt-1.5">«{s.comentario}»</p>}
                          <div className="mt-2 flex flex-col gap-2 sm:flex-row sm:items-center">
                            <div className="flex-1 sm:min-w-64">
                              <Campo
                                value={motivosRechazo[s.id] ?? ""}
                                onChange={(e) => setMotivosRechazo((x) => ({ ...x, [s.id]: e.target.value }))}
                                placeholder="Motivo si rechazas (obligatorio solo para rechazar)"
                              />
                            </div>
                            <div className="flex gap-2">
                              <Boton
                                variante="primario"
                                onClick={() => void resolverSolicitud(s.id, true)}
                                cargando={resolviendo === s.id}
                                className="flex-1 sm:flex-none"
                              >
                                Aprobar
                              </Boton>
                              <Boton
                                variante="peligro"
                                onClick={() => void resolverSolicitud(s.id, false)}
                                disabled={resolviendo === s.id}
                                className="flex-1 sm:flex-none"
                              >
                                Rechazar
                              </Boton>
                            </div>
                          </div>
                        </li>
                      ))}
                    </ul>
                  </section>
                )}

                {solicitudesPerfilF.length > 0 && (
                  <section>
                    <h3 className="mb-1 font-serif text-lg">
                      {solicitudesPerfilF.length} solicitud{solicitudesPerfilF.length === 1 ? "" : "es"} de cambio de perfil
                    </h3>
                    <p className="mb-3 text-sm text-taupe">
                      Lo pidieron desde «Lo mío». Aprobar aplica el cambio real de una vez; rechazar exige decir por qué —esa respuesta la va a leer la persona.
                    </p>
                    <ul className="space-y-3">
                      {solicitudesPerfilF.map((s) => (
                        <li key={s.id} className="rounded-xl border border-sand p-3 text-sm">
                          <div className="flex flex-wrap items-baseline justify-between gap-2">
                            <span className="flex flex-wrap items-baseline gap-2">
                              {!vistosIniciales.has(`solicitud_perfil:${s.id}`) && <InsigniaNuevo />}
                              <strong>{s.nombre}</strong>
                              <span className="text-taupe">· {s.sede} · {s.etiqueta} · <Antiguedad pedidaAt={s.creada_at} /></span>
                            </span>
                          </div>
                          <p className="mt-1.5 text-xs text-taupe">
                            de: {resumenValorPerfil(s.valor_anterior)}
                          </p>
                          <p className="text-xs">
                            a: {resumenValorPerfil(s.valor_propuesto)}
                          </p>
                          {s.rutas_adjuntas.length > 0 && (
                            <div className="mt-1.5 flex flex-wrap gap-2">
                              {s.rutas_adjuntas.map((ruta, i) => (
                                <button key={ruta} onClick={() => void verDocumentoPerfil(ruta)}
                                  className="text-xs text-rojo hover:underline">
                                  Ver documento {s.rutas_adjuntas.length > 1 ? i + 1 : ""} →
                                </button>
                              ))}
                            </div>
                          )}
                          {/* La solicitud se muestra igual a la encargada —si no,
                              su equipo estaría esperando algo que ella no ve— pero
                              sin los botones cuando el campo es de DO (0405). Antes
                              los botones estaban y reventaban al pulsarlos, con un
                              mensaje que hablaba de un permiso que la pantalla
                              acababa de decirle que tenía. */}
                          {s.solo_do && !puedeVerIdentidad(rol) ? (
                            <p className="mt-2 rounded-lg border border-pizarra/30 bg-pizarra/10 px-3 py-2 text-xs text-pizarra">
                              Esta solicitud cambia el número de documento: la resuelve Desarrollo Organizacional.
                              Avísales para que la revisen.
                            </p>
                          ) : (
                          <div className="mt-2 flex flex-col gap-2 sm:flex-row sm:items-center">
                            <div className="flex-1 sm:min-w-64">
                              <Campo
                                value={motivosPerfil[s.id] ?? ""}
                                onChange={(e) => setMotivosPerfil((x) => ({ ...x, [s.id]: e.target.value }))}
                                placeholder="Motivo si rechazas (obligatorio solo para rechazar)"
                              />
                            </div>
                            <div className="flex gap-2">
                              <Boton
                                variante="primario"
                                onClick={() => void resolverSolicitudPerfil(s.id, true)}
                                cargando={resolviendoPerfil === s.id}
                                className="flex-1 sm:flex-none"
                              >
                                Aprobar
                              </Boton>
                              <Boton
                                variante="peligro"
                                onClick={() => void resolverSolicitudPerfil(s.id, false)}
                                disabled={resolviendoPerfil === s.id}
                                className="flex-1 sm:flex-none"
                              >
                                Rechazar
                              </Boton>
                            </div>
                          </div>
                          )}
                        </li>
                      ))}
                    </ul>
                  </section>
                )}
              </div>
            )}

            {totalParaSaber > 0 && (
              <div className="flex flex-col gap-8 rounded-2xl border border-sand bg-papel p-5">
                <h2 className="-mb-2 text-xs font-semibold uppercase tracking-wide text-taupe">
                  Para saber · {totalParaSaber}
                </h2>

                {sinHorarioF.length > 0 && (
                  <section>
                    <h3 className="mb-1 font-serif text-lg">
                      {sinHorarioF.length} persona{sinHorarioF.length === 1 ? "" : "s"} trabajó sin horario vigente
                    </h3>
                    <p className="mb-3 max-w-2xl text-xs leading-relaxed text-taupe">
                      Marcaron días que ningún horario suyo cubre. Esos días no miden tardanza, ni
                      salida anticipada, ni tiempo adicional — y si a alguien le cae un descanso médico
                      o una licencia dentro del hueco, se le paga en cero, sin que nada falle. Suele
                      ocurrir cuando se cambia el horario de una tienda y el tramo nuevo empieza unos
                      días después de que terminó el anterior. Quien no lleva horario por su vínculo no
                      aparece acá.
                    </p>
                    <ul className="space-y-2">
                      {sinHorarioF.map((h) => (
                        <li key={h.persona_id} className="rounded-xl border border-sand p-3 text-sm">
                          <div className="flex flex-wrap items-center justify-between gap-2">
                            <span><strong>{h.nombre}</strong> <span className="text-taupe">· {h.sede}</span></span>
                            <span className={h.nunca_tuvo_horario ? "text-rojo" : "text-ambar"}>{detalleSinHorario(h)}</span>
                          </div>
                        </li>
                      ))}
                    </ul>
                    <Link href="/admin/horarios" className="mt-2 inline-block text-sm text-taupe hover:text-rojo">
                      Ir a Horarios →
                    </Link>
                  </section>
                )}

                {vacacionesF.length > 0 && (
                  <section>
                    <h3 className="mb-3 font-serif text-lg">
                      {vacacionesF.length} récord{vacacionesF.length === 1 ? "" : "s"} de vacaciones vencen pronto
                    </h3>
                    <ul className="space-y-2">
                      {vacacionesF.map((v) => (
                        <li key={v.persona_id} className="rounded-xl border border-sand p-3 text-sm">
                          <div className="flex flex-wrap items-center justify-between gap-2">
                            <span><strong>{v.persona}</strong> <span className="text-taupe">· {v.sede}</span></span>
                            <span className={v.records_vencidos > 0 ? "text-rojo" : "text-ambar"}>{detalleVacacion(v)}</span>
                          </div>
                        </li>
                      ))}
                    </ul>
                    <Link href="/admin/ausencias" className="mt-2 inline-block text-sm text-taupe hover:text-rojo">
                      Ir a Ausencias →
                    </Link>
                  </section>
                )}

                {educacionF.length > 0 && (
                  <section>
                    <h3 className="mb-3 font-serif text-lg">
                      {educacionF.length} asignación{educacionF.length === 1 ? "" : "es"} de educación por atender
                    </h3>
                    <ul className="space-y-2">
                      {educacionF.map((f) => (
                        <li key={f.id} className="rounded-xl border border-sand p-3 text-sm">
                          <div className="flex flex-wrap items-center justify-between gap-2">
                            <span><strong>{f.persona}</strong> <span className="text-taupe">· {f.sede} · {f.rango}</span></span>
                            <span className={f.semaforo === "vencida" || f.semaforo === "sin_comprobante" ? "text-rojo" : "text-ambar"}>
                              {detalleEducacion(f)}
                            </span>
                          </div>
                        </li>
                      ))}
                    </ul>
                    <Link href="/admin/educacion" className="mt-2 inline-block text-sm text-taupe hover:text-rojo">
                      Ir a Educación →
                    </Link>
                  </section>
                )}
              </div>
            )}
          </div>
        )}
      </main>
    </div>
  );
}
