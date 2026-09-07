"use client";

import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Colibri } from "@/components/marca";
import { AcusesPendientes } from "@/components/acuses-pendientes";
import { AnunciosWidget } from "@/components/anuncios-widget";
import { SelectorTema } from "@/components/selector-tema";
import { subirArchivoConProgreso } from "@/lib/subir-archivo";
import {
  BUCKET_FOTOS_PERFIL, comprimirFotoPerfil, inicialesDe, rutaNuevaFotoPerfil, urlPublicaFotoPerfil,
} from "@/lib/foto-perfil";
import { ROLES_CON_PANEL, TZ_LIMA, hoyLima } from "@cayla-dynamic/shared";
import { MESES as MESES_LARGOS, type ObjetivoItem } from "@/lib/objetivos";
import {
  esperadoDelDia, horarioVigente, fechasDelRango, dowDe, estadoDelDia,
  type Esperado, type EstadoDia, type HorarioTramo, type TurnoDia,
} from "@/lib/admin/jornada-esperada";

/**
 * «Lo mío» — lo que cada persona ve de sí misma.
 *
 * POR QUÉ ESTÁ FUERA DE /admin
 *
 * El layout de `(admin)` no comprueba ningún rol: es un `<div>`. Cada pantalla se
 * defiende sola pidiendo sesión, pero ninguna pregunta QUIÉN eres. Meter aquí a
 * alguien con rol `integrante` dejaría alcanzables las 35 pantallas del panel, y
 * confiar en que las capas de abajo aguanten es la suposición que este
 * repositorio ha aprendido a medir en vez de dar por buena.
 *
 * ⚠ EL ERROR QUE ESTA PANTALLA YA COMETIÓ, Y QUE NO SE PUEDE REPETIR
 *
 * La primera versión (2026-08-12) no filtraba por persona: pedía `personas` con
 * `.limit(1)` y las jornadas sin `persona_id`, dando por hecho que la RLS
 * devolvería «lo suyo». Eso es cierto para una integrante y FALSO para todas las
 * demás: a una encargada, `personas_select_supervisor` le devuelve su sede
 * entera, y a DO, `personas_select_admin_lider` le devuelve a todo el mundo.
 *
 * Resultado medido en producción: Danitza —encargada— entró y la pantalla le
 * mostró el nombre de Dayana y 148 días, 1098 horas y 9 de 150 tardanzas, que
 * son la suma de medio equipo. No fue una fuga —esos datos ya los ve en el
 * panel, es su trabajo— pero la pantalla mintió sobre DE QUIÉN eran, en la
 * pantalla que se llama «lo mío».
 *
 * La regla que sale de ahí: SE FILTRA SIEMPRE POR `persona_id`, explícitamente,
 * en cada consulta. La RLS es la red de abajo, nunca el mecanismo. Una consulta
 * que depende de la RLS para acertar devuelve cosas distintas según quién
 * pregunte, y eso no se ve hasta que alguien con más permisos la abre.
 *
 * QUÉ VE, Y QUÉ NO
 *
 * Sus días, sus horas, sus tardanzas, lo que le tocaba, sus próximos turnos, sus
 * objetivos del mes y sus ausencias registradas.
 *
 * Y DESDE LA 0339, su boleta — pero solo la del periodo actual, nunca una
 * pasada. Hasta el 2026-08-11 esta pantalla no mostraba NADA de dinero
 * (decisión de Felipe, esa fecha); el 2026-08-31 la reabrió él mismo, con una
 * condición explícita: los periodos ya cerrados tuvieron errores de cálculo
 * reales, ya corregidos en el código, y su foto congelada puede no reflejarlo
 * — así que el autoservicio empieza en el periodo de hoy, nunca antes.
 * `fn_planilla_calcular_persona` hace cumplir ese corte del lado del
 * servidor (no aquí): ver supabase/migrations/0339_*.sql. Sigue sin mostrarse
 * el sobretiempo como «tiempo adicional» del panel: son horas por encima del
 * horario programado y NO es sobretiempo pagable (desde la 0185 se mide
 * contra 48 h SEMANALES por ciclo), así que enseñarlo invita a leerlo como
 * «me deben estas horas» — eso no cambió.
 *
 * Y tampoco el expediente disciplinario, aunque `exp_select_propia` se lo
 * permita: esa policy no filtra por estado, así que incluiría los BORRADORES —
 * documentos que nadie decidió entregar todavía. Avisarle a alguien de una
 * sanción que aún no existe es peor que no avisarle de nada.
 *
 * POR QUÉ LOS NÚMEROS LLEVAN «DE CUÁNTO»
 *
 * «Promedio 6h 54m» no dice si va bien o mal. Una encargada puede preguntar; ella
 * no tiene a quién. Lo que le tocaba sale de su propio horario y sus turnos
 * (lib/admin/jornada-esperada.ts), la misma cascada que usa el panel — para que
 * las dos pantallas no puedan contar cosas distintas de la misma persona.
 */

interface Yo {
  id: string;
  nombre: string;
  nombres: string;
  apellidos: string;
  fechaIngreso: string | null;
  /** Para saber si esta persona tiene panel al que volver. Nada más: lo que se
   *  muestra en esta pantalla es igual para todo el mundo. */
  rol: string | null;
  /** Ruta en el bucket público «fotos-perfil» (0381), o null si nunca subió una. */
  fotoUrl: string | null;
}

interface Jornada {
  fecha: string;
  entrada_ts: string | null;
  salida_final_ts: string | null;
  horas_trabajadas: number | null;
  minutos_tarde: number | null;
  estado: string;
}

interface Dia {
  fecha: string;
  estado: EstadoDia;
  esperado: Esperado;
  jornada: Jornada | null;
  perdonada: boolean;
  motivoFalta: string | null;
}

interface Ausencia {
  tipo: string;
  fecha_inicio: string;
  fecha_fin: string;
  doc_profesional: string | null;
  aprobada_at: string | null;
}

interface TipoAusencia { codigo: string; nombre: string; requiere_documento: boolean; paga: boolean }

/** Una petición suya de que se revise un día. La escribe `fn_pedir_revision`. */
interface Revision {
  fecha: string;
  comentario: string;
  atendida_at: string | null;
  respuesta: string | null;
}

/**
 * Una corrección que alguien le aplicó a uno de sus marcajes. Vive en
 * `correcciones_auditoria` desde la 0001; `auditoria_select_propia` ya le deja
 * leer sus propias filas desde la 0003 — nadie lo mostraba, no porque faltara
 * permiso, sino porque ninguna pantalla lo pedía.
 */
interface Correccion {
  id: string;
  campo_modificado: string;
  valor_anterior: string | null;
  valor_nuevo: string | null;
  motivo: string;
  corregido_at: string;
  // Puede no haber marcaje asociado (ej. un ajuste de contrato): entonces
  // PostgREST lo embebe como null, no como error.
  marcajes: { tipo: string; timestamp_marca: string } | null;
}

/** Una petición suya de vacaciones. La escribe `fn_solicitar_vacaciones`. */
interface SolicitudVacacion {
  id: string;
  fecha_inicio: string;
  fecha_fin: string;
  comentario: string | null;
  estado: "pendiente" | "aprobada" | "rechazada" | "cancelada";
  pedida_at: string;
  respuesta: string | null;
}

const MESES = [
  "enero", "febrero", "marzo", "abril", "mayo", "junio",
  "julio", "agosto", "setiembre", "octubre", "noviembre", "diciembre",
];
const LETRA_DIA = ["D", "L", "M", "M", "J", "V", "S"];

/** «2026-07-29» → «29 de julio». */
function diaYMes(iso: string): string {
  const [, m, d] = iso.split("-");
  return `${Number(d)} de ${MESES[Number(m) - 1]}`;
}

/** 7.53 → «7h 32m». La gente cuenta en horas y minutos, no en decimales. */
function comoReloj(horas: number): string {
  const total = Math.round(horas * 60);
  return `${Math.floor(total / 60)}h ${String(total % 60).padStart(2, "0")}m`;
}

function comoMinutos(min: number): string {
  if (min < 60) return `${min} min`;
  return `${Math.floor(min / 60)}h ${String(min % 60).padStart(2, "0")}m`;
}

/** La hora de un marcaje, en Lima. Nunca `toLocaleTimeString` a secas: el huso
 *  del navegador no es el que decide a qué día pertenece una marca. */
function hora(iso: string | null): string {
  if (!iso) return "—";
  return new Intl.DateTimeFormat("es-PE", {
    timeZone: TZ_LIMA, hour: "2-digit", minute: "2-digit", hour12: true,
  }).format(new Date(iso));
}

/** Fecha y hora de un timestamp, en Lima: «20 ago, 1:15 p. m.». */
function fechaYHora(iso: string): string {
  return new Intl.DateTimeFormat("es-PE", {
    timeZone: TZ_LIMA, day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit", hour12: true,
  }).format(new Date(iso));
}

/** El día de Lima (YYYY-MM-DD) al que pertenece un timestamp — nunca el UTC
 *  crudo, que puede caer un día antes o después cerca de medianoche. */
function fechaLimaDeMarca(iso: string): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: TZ_LIMA }).format(new Date(iso));
}

// Qué dice `campo_modificado` en `correcciones_auditoria` — vocabulario real,
// tomado de los `insert` de las migraciones 0009/0010/0081/0084, no inventado.
// Un campo nuevo que aparezca mañana no rompe nada: cae al fallback de abajo.
const ETIQUETA_CAMPO: Record<string, string> = {
  timestamp_marca: "Hora del marcaje",
  tipo: "Tipo de marcaje",
  marcaje_agregado: "Marcaje agregado",
  marcaje_eliminado: "Marcaje eliminado",
  marcaje_anulado: "Marcaje anulado",
  marcaje_reactivado: "Marcaje reactivado",
  auto_cierre_confirmado: "Cierre automático confirmado",
};
function etiquetaCampo(campo: string): string {
  return ETIQUETA_CAMPO[campo] ?? campo.replaceAll("_", " ");
}
// Dos formas reales de valor_anterior/valor_nuevo, tomadas de los mismos
// insert: un timestamp a secas (`timestamp_marca`), o "tipo @ timestamp"
// (marcaje_agregado/eliminado/anulado). Las dos traen la hora en su offset
// crudo (+00), no en hora de Lima — reformatear es lo mismo que hace `hora()`
// para cualquier otro timestamp de esta pantalla, no un caso aparte.
function valorLegible(campo: string, valor: string | null): string {
  if (valor === null) return "—";
  if (campo === "timestamp_marca") {
    const d = new Date(valor);
    return Number.isNaN(d.getTime()) ? valor : fechaYHora(valor);
  }
  const conMarca = valor.match(/^(.+) @ (.+)$/);
  if (conMarca) {
    const d = new Date(conMarca[2]);
    if (!Number.isNaN(d.getTime())) return `${conMarca[1]} · ${fechaYHora(conMarca[2])}`;
  }
  return valor; // "anulada", "revisada", un tipo de marcaje a secas, etc.
}

/** Hoy más/menos N días, en fecha de Lima. */
function corrimiento(n: number): string {
  const [a, m, d] = hoyLima().split("-").map(Number);
  const x = new Date(Date.UTC(a, m - 1, d));
  x.setUTCDate(x.getUTCDate() + n);
  return x.toISOString().slice(0, 10);
}
const haceDias = (n: number) => corrimiento(-n);

/** «mañana», «el martes», «el 3 de setiembre» — cómo lo diría una persona. */
function cuando(fecha: string): string {
  if (fecha === hoyLima()) return "hoy";
  if (fecha === corrimiento(1)) return "mañana";
  const dow = dowDe(fecha);
  const nombres = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"];
  if (fecha <= corrimiento(6)) return `el ${nombres[dow]}`;
  return `el ${diaYMes(fecha)}`;
}

// Los mismos colores que el panel, con el mismo significado. Que la persona y su
// encargada vean el mismo día del mismo color no es cosmético: es lo que hace
// que puedan hablar de él sin traducirse una a la otra.
function colorDia(d: Dia): string {
  switch (d.estado) {
    case "falta": return "bg-rojo";
    case "revisar": return "border border-dashed border-taupe bg-crema";
    case "tarde": {
      const m = d.jornada?.minutos_tarde ?? 0;
      if (m >= 60) return "bg-ambar brightness-75";
      if (m >= 15) return "bg-ambar";
      return "bg-ambar/45";
    }
    case "justificada": return "bg-rojo/20";
    case "ok": return "bg-verde";
    case "extra": return "bg-verde/45 ring-1 ring-inset ring-verde";
    case "sin_marca": return "bg-taupe/25";
    case "descanso": return "bg-sand";
    case "sin_horario": return "bg-sand/40";
    case "futuro": return "border border-sand";
  }
}

function explicaDia(d: Dia): string {
  const p: string[] = [diaYMes(d.fecha)];
  if (d.esperado.trabaja) p.push(`te tocaba ${d.esperado.entrada}${d.esperado.salida ? `–${d.esperado.salida}` : ""}`);
  else if (d.estado !== "sin_horario") p.push("descanso");
  if (d.jornada?.entrada_ts) p.push(`entraste ${hora(d.jornada.entrada_ts)}`);
  if (d.jornada?.horas_trabajadas != null) p.push(comoReloj(d.jornada.horas_trabajadas));
  if ((d.jornada?.minutos_tarde ?? 0) > 0) {
    p.push(d.perdonada ? "tardanza levantada" : `${comoMinutos(d.jornada!.minutos_tarde!)} tarde`);
  }
  if (d.estado === "falta") p.push("no hay marcaje");
  if (d.estado === "revisar") p.push("marcaje incompleto");
  return p.join(" · ");
}

export default function MioPage() {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const router = useRouter();
  const [sesion, setSesion] = useState<boolean | null>(null);
  const [yo, setYo] = useState<Yo | null>(null);
  const [subiendoFoto, setSubiendoFoto] = useState(false);
  const [errorFoto, setErrorFoto] = useState<string | null>(null);

  /**
   * Sube y enlaza la foto de perfil (0381). Comprime en el navegador antes de
   * subir —ver `comprimirFotoPerfil`— para que la grilla del terminal, que
   * pinta 10-30 de estas a la vez, no cargue fotos de varios MB tal como
   * salen del celular.
   */
  async function subirMiFoto(archivo: File) {
    if (!yo) return;
    setSubiendoFoto(true);
    setErrorFoto(null);
    try {
      const comprimida = await comprimirFotoPerfil(archivo);
      const ruta = rutaNuevaFotoPerfil(yo.id);
      const archivoAEnviar = new File([comprimida], "foto.jpg", { type: "image/jpeg" });
      const fallo = await subirArchivoConProgreso(supabase, BUCKET_FOTOS_PERFIL, ruta, archivoAEnviar, () => {});
      if (fallo) { setErrorFoto(`No se pudo subir tu foto: ${fallo}`); return; }

      const { error } = await supabase.rpc("fn_actualizar_foto_perfil", {
        p_persona_id: yo.id,
        p_foto_url: ruta,
      });
      if (error) { setErrorFoto(`La foto se subió, pero no se pudo enlazar: ${error.message}`); return; }

      setYo((prev) => (prev ? { ...prev, fotoUrl: ruta } : prev));
    } catch {
      setErrorFoto("Esta imagen no se pudo procesar. Prueba con otra foto.");
    } finally {
      setSubiendoFoto(false);
    }
  }
  // Su saldo de vacaciones y hasta cuándo puede tomarlo. Sin plata: en esta
  // pantalla no hay dinero, y la función tampoco devuelve ninguno — por eso se
  // le puede preguntar a cada persona por lo suyo.
  const [vacas, setVacas] = useState<{
    dias_pendientes: number; records_sin_gozar: number; records_vencidos: number;
    vence_el: string | null; dias_para_vencer: number | null;
  } | null>(null);
  const [solicitudesVacas, setSolicitudesVacas] = useState<SolicitudVacacion[]>([]);
  // El rango del formulario de pedir vacaciones. Arranca en mañana y en un
  // solo día — nunca en "": un campo de fecha que arranca vacío y bloquea el
  // envío es justo el error que ya costó caro acá (ver CLAUDE.md, 2026-08-26).
  const [desdeSolicitud, setDesdeSolicitud] = useState(corrimiento(1));
  const [hastaSolicitud, setHastaSolicitud] = useState(corrimiento(1));
  const [comentarioSolicitud, setComentarioSolicitud] = useState("");
  const [enviandoSolicitud, setEnviandoSolicitud] = useState(false);
  const [avisoSolicitud, setAvisoSolicitud] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);
  const [jornadas, setJornadas] = useState<Jornada[]>([]);
  const [perdonadas, setPerdonadas] = useState<Set<string>>(new Set());
  const [tramos, setTramos] = useState<HorarioTramo[]>([]);
  const [turnos, setTurnos] = useState<Map<string, TurnoDia>>(new Map());
  const [faltas, setFaltas] = useState<Map<string, { justificada: boolean; motivo: string | null }>>(new Map());
  const [objetivos, setObjetivos] = useState<ObjetivoItem[]>([]);
  const [ausencias, setAusencias] = useState<Ausencia[]>([]);
  const [tiposAusencia, setTiposAusencia] = useState<TipoAusencia[]>([]);
  const [periodo, setPeriodo] = useState<{ fecha_ini: string; fecha_fin: string } | null>(null);
  const [feriados, setFeriados] = useState<{ fecha: string; nombre: string }[]>([]);
  const [revisiones, setRevisiones] = useState<Map<string, Revision>>(new Map());
  const [correcciones, setCorrecciones] = useState<Correccion[]>([]);
  // ¿Existe ya la tabla de la 0257? Mientras la migración no esté pegada,
  // PostgREST responde con error y pedir una revisión fallaría con un mensaje
  // que no significa nada para quien lo lee. Sin la tabla, ese trozo no sale.
  const [puedePedirRevision, setPuedePedirRevision] = useState(false);
  const [cargando, setCargando] = useState(false);
  const [aviso, setAviso] = useState<string | null>(null);

  // El día abierto desde la cuadrícula. En un teléfono no hay `hover`, así que
  // sin esto los cuadritos de colores son decoración: se ve que el 12 está en
  // ámbar y no hay forma de saber por qué.
  const [diaAbierto, setDiaAbierto] = useState<string | null>(null);
  const [comentario, setComentario] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [avisoRevision, setAvisoRevision] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);

  // El rango. Por defecto los últimos 30 días: es lo que se entiende por «el
  // último mes» dicho en voz alta, y siempre incluye lo de esta semana — que es
  // lo primero que alguien mira. El periodo de pago está a un botón.
  const [desde, setDesde] = useState(haceDias(30));
  const [hasta, setHasta] = useState(hoyLima());

  const [email, setEmail] = useState("");
  const [clave, setClave] = useState("");
  const [entrando, setEntrando] = useState(false);
  const [errorLogin, setErrorLogin] = useState<string | null>(null);

  useEffect(() => {
    void supabase.auth.getSession().then(({ data }) => setSesion(Boolean(data.session)));
  }, [supabase]);

  async function entrar(e: FormEvent) {
    e.preventDefault();
    setEntrando(true);
    setErrorLogin(null);
    const { error } = await supabase.auth.signInWithPassword({ email, password: clave });
    setEntrando(false);
    if (error) { setErrorLogin("Correo o contraseña incorrectos."); return; }
    setSesion(true);
  }

  // ── Quién soy ─────────────────────────────────────────────────────────────
  // POR auth_user_id, no por «la primera fila que la RLS me deje ver». Ver el
  // comentario de arriba: esa suposición fue el error de la primera versión.
  useEffect(() => {
    if (!sesion) return;
    void (async () => {
      const { data: sesionAuth } = await supabase.auth.getUser();
      const uid = sesionAuth.user?.id;
      if (!uid) { setAviso("No se pudo leer tu sesión. Vuelve a entrar."); return; }

      const { data: p } = await supabase
        .from("personas")
        .select("id, nombres, apellidos, fecha_ingreso, rol, foto_url")
        .eq("auth_user_id", uid)
        .maybeSingle();

      if (!p) {
        setAviso("Tu cuenta todavía no está enlazada con tu ficha. Avisa a Desarrollo Organizacional.");
        return;
      }
      setYo({
        id: p.id as string,
        nombre: `${p.nombres as string} ${p.apellidos as string}`,
        nombres: p.nombres as string,
        apellidos: p.apellidos as string,
        fechaIngreso: (p.fecha_ingreso as string | null) ?? null,
        rol: (p.rol as string | null) ?? null,
        fotoUrl: (p.foto_url as string | null) ?? null,
      });
    })();
  }, [supabase, sesion]);

  // ── Lo suyo ───────────────────────────────────────────────────────────────
  const cargar = useCallback(async () => {
    if (!yo) return;
    setCargando(true);
    // Los turnos se piden hasta 14 días adelante aunque el rango termine hoy:
    // «cuándo me toca» es la pregunta que más veces se abre esta pantalla.
    const turnosHasta = hasta > corrimiento(14) ? hasta : corrimiento(14);

    const [
      { data: js }, { data: perd }, { data: hs }, { data: ts },
      { data: fl }, { data: objs }, { data: aus }, { data: tipos },
      { data: per }, { data: fer }, { data: revs, error: errRevs },
      { data: corrs },
    ] = await Promise.all([
      supabase.from("jornadas")
        .select("fecha, entrada_ts, salida_final_ts, horas_trabajadas, minutos_tarde, estado")
        .eq("persona_id", yo.id)          // ← explícito. La RLS es la red, no el filtro.
        .gte("fecha", desde).lte("fecha", hasta)
        .order("fecha"),
      supabase.from("tardanzas_justificadas")
        .select("fecha").eq("persona_id", yo.id)
        .gte("fecha", desde).lte("fecha", hasta),
      supabase.from("horarios_asignados")
        .select("persona_id, vigente_desde, vigente_hasta, hora_entrada, hora_salida, dias_laborables, horario_por_dia, almuerzo_min_minutos")
        .eq("persona_id", yo.id)
        .lte("vigente_desde", turnosHasta).or(`vigente_hasta.is.null,vigente_hasta.gte.${desde}`),
      supabase.from("turnos")
        .select("fecha, hora_entrada, hora_salida, es_descanso")
        .eq("persona_id", yo.id)
        .gte("fecha", desde).lte("fecha", turnosHasta),
      // Sus faltas. Hasta la 0256, `fn_faltas` no tiene rama para «soy yo» y le
      // devuelve vacío a una integrante: entonces sus días sin marcaje salen en
      // gris («te tocaba, sin marcaje») en vez de en rojo. Se degrada diciendo
      // menos, nunca diciendo algo falso.
      supabase.rpc("fn_faltas", { p_desde: desde, p_hasta: hasta }),
      supabase.rpc("fn_objetivos_checklist", {
        p_anio: Number(hasta.slice(0, 4)), p_mes: Number(hasta.slice(5, 7)), p_persona_id: yo.id,
      }),
      // `is("anulada_at", null)` no es opcional: una ausencia anulada existe
      // en la tabla y NO cuenta. Sin ese filtro la pantalla le diría que su
      // permiso está registrado cuando alguien ya lo dio de baja — y es justo
      // en lo que se fiaría para no volver a presentarlo. La vista
      // `vacaciones` lleva ese mismo filtro dentro desde siempre.
      supabase.from("ausencias")
        .select("tipo, fecha_inicio, fecha_fin, doc_profesional, aprobada_at")
        .eq("persona_id", yo.id)
        .is("anulada_at", null)
        .lte("fecha_inicio", hasta).gte("fecha_fin", desde)
        .order("fecha_inicio", { ascending: false }),
      supabase.from("tipos_ausencia").select("codigo, nombre, requiere_documento, paga"),
      // El periodo de pago en curso. Es el tramo con el que se le paga —del 29
      // al 28, LEÍDO y nunca calculado— y contra el que va a querer cuadrar.
      supabase.from("periodos_planilla").select("fecha_ini, fecha_fin")
        .lte("fecha_ini", hoyLima()).gte("fecha_fin", hoyLima()).maybeSingle(),
      supabase.from("feriados").select("fecha, nombre")
        .gte("fecha", hoyLima()).order("fecha").limit(3),
      // SIN filtro de fechas, a propósito. Antes se recortaba al rango que la
      // persona está mirando, y entonces la RESPUESTA de su encargada se volvía
      // invisible en cuanto el día caía fuera de la ventana por defecto: pidió
      // que le revisaran un día, se lo revisaron, y no se enteraba. Traerlas
      // todas no pesa —hay como mucho UNA por día y por persona, por el unique
      // de la 0257— y es lo que permite avisar abajo de las ya respondidas.
      supabase.from("revisiones_pedidas")
        .select("fecha, comentario, atendida_at, respuesta")
        .eq("persona_id", yo.id),         // ← explícito, como todo lo de acá
      // Igual que revisiones_pedidas: SIN filtro de fechas y con un límite fijo
      // en vez de uno por rango. Una corrección de hace dos meses sigue siendo
      // algo que le pasó a su marcaje; recortarla al mes que mira hoy la
      // esconde justo del único lugar donde puede enterarse de que existió.
      supabase.from("correcciones_auditoria")
        .select("id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_at, marcajes(tipo, timestamp_marca)")
        .eq("persona_id", yo.id)          // ← explícito, como todo lo de acá
        .order("corregido_at", { ascending: false })
        .limit(20),
    ]);

    setJornadas((js as Jornada[]) ?? []);
    setPerdonadas(new Set(((perd as { fecha: string }[]) ?? []).map((t) => t.fecha)));
    setTramos((hs as unknown as HorarioTramo[]) ?? []);
    setTurnos(new Map(((ts as unknown as (TurnoDia & { fecha: string })[]) ?? []).map((t) => [t.fecha, t])));
    setFaltas(new Map(
      ((fl as { persona_id: string; fecha: string; justificada: boolean; motivo: string | null }[] | null) ?? [])
        .filter((f) => f.persona_id === yo.id)   // explícito, igual que todo lo demás de acá
        .map((f) => [f.fecha, { justificada: f.justificada, motivo: f.motivo }]),
    ));
    setObjetivos(((objs as unknown as ObjetivoItem[] | null) ?? []).filter((o) => o.persona_id === yo.id));
    setAusencias((aus as Ausencia[]) ?? []);
    setTiposAusencia((tipos as TipoAusencia[]) ?? []);
    setPeriodo((per as { fecha_ini: string; fecha_fin: string } | null) ?? null);
    setFeriados((fer as { fecha: string; nombre: string }[]) ?? []);
    // La tabla es de la 0257. Mientras no esté pegada, PostgREST responde con
    // error y `revs` viene null: la pantalla se queda sin el botón de pedir
    // revisión y todo lo demás sigue igual. Se degrada, no se cae.
    setRevisiones(new Map(((revs as Revision[] | null) ?? []).map((r) => [r.fecha, r])));
    setPuedePedirRevision(!errRevs);
    setCorrecciones((corrs as unknown as Correccion[] | null) ?? []);
    setCargando(false);
  }, [supabase, yo, desde, hasta]);

  useEffect(() => { void cargar(); }, [cargar]);

  // Se pide aparte y no dentro del bloque grande: es una sola pregunta, depende
  // solo de quién es, y si falla no debe llevarse por delante el resto de la
  // pantalla.
  useEffect(() => {
    if (!yo?.id) { setVacas(null); return; }
    let vivo = true;
    void supabase
      .rpc("fn_vacaciones_saldo", { p_persona_id: yo.id, p_as_of: null })
      .then(({ data }) => {
        if (!vivo) return;
        const r = data as { aplica?: boolean } | null;
        setVacas(r && r.aplica ? (r as never) : null);
      });
    return () => { vivo = false; };
  }, [supabase, yo?.id]);

  // Sus propias solicitudes de vacaciones. Aparte del bloque grande de arriba
  // por la misma razón que `vacas`: depende solo de quién es, no del rango de
  // fechas que esté mirando en la cuadrícula del mes.
  const cargarSolicitudesVacas = useCallback(async () => {
    if (!yo?.id) { setSolicitudesVacas([]); return; }
    const { data } = await supabase
      .from("solicitudes_vacaciones")
      .select("id, fecha_inicio, fecha_fin, comentario, estado, pedida_at, respuesta")
      .eq("persona_id", yo.id)          // ← explícito, como todo lo de acá
      .order("pedida_at", { ascending: false });
    setSolicitudesVacas((data as SolicitudVacacion[]) ?? []);
  }, [supabase, yo]);

  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void cargarSolicitudesVacas(); }, [cargarSolicitudesVacas]);

  /** Pedir un rango de vacaciones. No dice si alcanza el saldo: eso lo decide
   *  el servidor con el mismo cálculo que ya se le muestra arriba. */
  async function pedirVacaciones(e: FormEvent) {
    e.preventDefault();
    setAvisoSolicitud(null);
    setEnviandoSolicitud(true);
    const { error } = await supabase.rpc("fn_solicitar_vacaciones", {
      p_fecha_inicio: desdeSolicitud,
      p_fecha_fin: hastaSolicitud,
      p_comentario: comentarioSolicitud.trim() || null,
    });
    setEnviandoSolicitud(false);
    if (error) { setAvisoSolicitud({ tipo: "error", texto: error.message }); return; }
    setAvisoSolicitud({ tipo: "ok", texto: "Pedido. Te avisamos cuando Desarrollo Organizacional responda." });
    setComentarioSolicitud("");
    await cargarSolicitudesVacas();
  }

  /** Retirar una solicitud propia mientras siga pendiente. */
  async function retirarSolicitudVacas(id: string) {
    setEnviandoSolicitud(true);
    const { error } = await supabase.rpc("fn_cancelar_solicitud_vacaciones", { p_id: id });
    setEnviandoSolicitud(false);
    if (error) { setAvisoSolicitud({ tipo: "error", texto: error.message }); return; }
    await cargarSolicitudesVacas();
  }

  /** El periodo de pago en curso, para el botón. Del 29 al 28 — leído, no calculado. */
  async function irAlPeriodoDePago() {
    const hoy = hoyLima();
    const { data } = await supabase
      .from("periodos_planilla")
      .select("fecha_ini, fecha_fin")
      .lte("fecha_ini", hoy).gte("fecha_fin", hoy)
      .maybeSingle();
    if (!data) { setAviso("No hay un periodo de pago abierto para hoy."); return; }
    setAviso(null);
    setDesde(data.fecha_ini as string);
    setHasta(data.fecha_fin as string);
  }

  /** Pedir que se revise un día. No corrige nada: deja constancia y le llega a
   *  su encargada. Reabrir borra la respuesta anterior — eso lo hace la RPC. */
  async function pedirRevision(fecha: string) {
    if (comentario.trim().length < 5) {
      setAvisoRevision({ tipo: "error", texto: "Cuéntanos qué pasó ese día, aunque sea en una línea." });
      return;
    }
    setEnviando(true);
    const { error } = await supabase.rpc("fn_pedir_revision", { p_fecha: fecha, p_comentario: comentario.trim() });
    setEnviando(false);
    if (error) { setAvisoRevision({ tipo: "error", texto: error.message }); return; }
    setAvisoRevision({ tipo: "ok", texto: "Listo. Tu encargada lo va a ver." });
    setComentario("");
    await cargar();
  }

  async function quitarRevision(fecha: string) {
    setEnviando(true);
    const { error } = await supabase.rpc("fn_quitar_revision", { p_fecha: fecha });
    setEnviando(false);
    if (error) { setAvisoRevision({ tipo: "error", texto: error.message }); return; }
    setAvisoRevision({ tipo: "ok", texto: "Retirado." });
    await cargar();
  }

  // ── Cada día del rango, con lo que le tocaba al lado ───────────────────────
  const dias = useMemo<Dia[]>(() => {
    if (!yo || desde > hasta) return [];
    const hoy = hoyLima();
    const porFecha = new Map(jornadas.map((j) => [j.fecha, j]));
    return fechasDelRango(desde, hasta).map((fecha) => {
      const j = porFecha.get(fecha) ?? null;
      const esperado = esperadoDelDia(fecha, turnos.get(fecha) ?? null, horarioVigente(tramos, fecha));
      const horas = j?.horas_trabajadas ?? null;
      const agregado = (horas ?? 0) > 24;
      const falta = faltas.get(fecha) ?? null;
      return {
        fecha, esperado, jornada: j,
        perdonada: perdonadas.has(fecha),
        motivoFalta: falta?.motivo ?? null,
        estado: estadoDelDia({
          fecha, hoy, esperado, agregado, falta,
          jornada: j ? { horas, minutosTarde: j.minutos_tarde, estado: j.estado } : null,
          tardanzaJustificada: perdonadas.has(fecha),
        }),
      };
    });
  }, [yo, desde, hasta, jornadas, turnos, tramos, faltas, perdonadas]);

  // Las que YA te respondieron, hayas mirado ese día o no. Es la vuelta del
  // circuito de la 0257: pediste que revisaran un día y alguien contestó. Sin
  // esto, la respuesta solo se veía si navegabas justo a esa fecha.
  const respondidas = useMemo(
    () => [...revisiones.values()]
      .filter((r) => r.atendida_at && r.respuesta)
      .sort((a, b) => (b.atendida_at ?? "").localeCompare(a.atendida_at ?? "")),
    [revisiones],
  );

  const resumen = useMemo(() => {
    const hoy = hoyLima();
    // Un día de más de 24 h es un AGREGADO del histórico de 2025 —un mes entero
    // cargado en una fecha—, no una jornada. Suma al total pero no al promedio ni
    // al gráfico, que si no daría una barra imposible y un promedio absurdo.
    const reales = jornadas.filter((d) => (d.horas_trabajadas ?? 0) <= 24);
    const trabajados = reales.filter((d) => (d.horas_trabajadas ?? 0) > 0);
    const horasReales = reales.reduce((s, d) => s + (d.horas_trabajadas ?? 0), 0);
    // Lo que le tocaba: solo hasta hoy —sumar los días que aún no llegaron la
    // pintaría en deuda a principio de mes— y sin los días con motivo, que no
    // se deben. Nadie debe las horas de sus propias vacaciones.
    let diasEsperados = 0, horasEsperadas = 0;
    for (const d of dias) {
      if (!d.esperado.trabaja || d.fecha > hoy) continue;
      if (d.estado === "justificada") continue;
      diasEsperados++; horasEsperadas += d.esperado.horas;
    }
    return {
      total: jornadas.reduce((s, d) => s + (d.horas_trabajadas ?? 0), 0),
      horasReales,
      trabajados: trabajados.length,
      promedio: trabajados.length ? horasReales / trabajados.length : 0,
      diasEsperados, horasEsperadas,
      jornadaDiaria: diasEsperados > 0 ? horasEsperadas / diasEsperados : 0,
      // Una tardanza perdonada NO cuenta: si la encargada se la levantó, no tiene
      // por qué seguir viéndola en su marcador.
      tardanzas: jornadas.filter((d) => (d.minutos_tarde ?? 0) > 0 && !perdonadas.has(d.fecha)).length,
      medidos: jornadas.filter((d) => d.minutos_tarde !== null).length,
      porRevisar: dias.filter((d) => d.estado === "revisar"),
      faltas: dias.filter((d) => d.estado === "falta"),
    };
  }, [jornadas, perdonadas, dias]);

  // Los próximos turnos, de hoy en adelante. Solo los días que se trabajan: una
  // lista de descansos no es lo que se viene a consultar.
  const proximos = useMemo(() => {
    if (!yo) return [];
    const hoy = hoyLima();
    return fechasDelRango(hoy, corrimiento(14))
      .map((fecha) => ({ fecha, esperado: esperadoDelDia(fecha, turnos.get(fecha) ?? null, horarioVigente(tramos, fecha)) }))
      .filter((x) => x.esperado.trabaja)
      .slice(0, 7);
  }, [yo, turnos, tramos]);

  // Cuatro filas de «Permiso personal» seguidas son cuatro días que ella vivió
  // como un episodio. Se juntan los consecutivos del mismo tipo.
  const ausenciasAgrupadas = useMemo(() => {
    const orden = [...ausencias].sort((a, b) => a.fecha_inicio.localeCompare(b.fecha_inicio));
    const out: (Ausencia & { hasta: string })[] = [];
    for (const a of orden) {
      const ult = out[out.length - 1];
      const siguienteAlAnterior =
        ult && ult.tipo === a.tipo &&
        fechasDelRango(ult.hasta, a.fecha_inicio).length === 2;   // un día de diferencia
      if (siguienteAlAnterior) ult.hasta = a.fecha_fin > ult.hasta ? a.fecha_fin : ult.hasta;
      else out.push({ ...a, hasta: a.fecha_fin });
    }
    return out.reverse();
  }, [ausencias]);

  // Cuántos días le faltan al periodo de pago para cerrar, y si lo suyo está
  // completo. Es la traducción de «¿voy a cobrar bien?» a algo que el sistema
  // puede afirmar sin decir una cifra.
  const estadoDelPeriodo = useMemo(() => {
    if (!periodo) return null;
    const cierra = fechasDelRango(hoyLima(), periodo.fecha_fin).length - 1;
    const mios = dias.filter((d) => d.fecha >= periodo.fecha_ini && d.fecha <= periodo.fecha_fin);
    const pendientes = mios.filter((d) => d.estado === "revisar" || d.estado === "falta").length;
    // `cubre` dice si el rango que está mirando abarca el periodo entero: si no,
    // el «todo completo» sería una afirmación sobre días que no se consultaron.
    const cubre = desde <= periodo.fecha_ini && hasta >= hoyLima();
    return { cierra, pendientes, cubre };
  }, [periodo, dias, desde, hasta]);

  const objCumplidos = objetivos.filter((o) => o.cumplido).length;
  const mesLabel = `${MESES_LARGOS[Number(hasta.slice(5, 7)) - 1].toLowerCase()} ${hasta.slice(0, 4)}`;
  const nombreTipo = (c: string) => tiposAusencia.find((t) => t.codigo === c)?.nombre ?? c;
  const exigeDoc = (c: string) => tiposAusencia.find((t) => t.codigo === c)?.requiere_documento === true;
  const noPaga = (c: string) => tiposAusencia.find((t) => t.codigo === c)?.paga === false;
  const hayCumpleanos = tiposAusencia.some((t) => t.codigo === "cumpleanos");

  if (sesion === null) {
    return <main className="flex min-h-screen items-center justify-center bg-crema text-taupe">Un momento…</main>;
  }

  if (!sesion) {
    return (
      <main className="flex min-h-screen flex-col items-center justify-center gap-8 bg-crema p-8 text-tinta">
        <div className="flex flex-col items-center gap-4">
          <Colibri tono="rojo" className="w-12" />
          <div className="text-center">
            <h1 className="font-serif text-3xl leading-none">Lo mío</h1>
            <p className="etiqueta mt-2 text-taupe">Tus días y tus horas · CAYLA</p>
          </div>
        </div>
        <form onSubmit={entrar} className="flex w-full max-w-xs flex-col gap-3">
          <input type="email" placeholder="correo" value={email} onChange={(e) => setEmail(e.target.value)}
            className="rounded-lg border border-sand bg-crema px-4 py-3 outline-none placeholder:text-taupe/60 focus:border-taupe" required />
          <input type="password" placeholder="contraseña" value={clave} onChange={(e) => setClave(e.target.value)}
            className="rounded-lg border border-sand bg-crema px-4 py-3 outline-none placeholder:text-taupe/60 focus:border-taupe" required />
          {errorLogin && <p className="text-sm text-rojo">{errorLogin}</p>}
          <button type="submit" disabled={entrando}
            className="rounded-lg bg-tinta px-4 py-3 font-medium text-crema transition-colors hover:bg-rojo-profundo disabled:opacity-50">
            {entrando ? "Entrando…" : "Entrar"}
          </button>
          <a href="/admin/olvide-clave" className="text-center text-sm text-taupe underline-offset-2 hover:underline">
            ¿Olvidaste tu clave?
          </a>
        </form>
      </main>
    );
  }

  return (
    <main className="mx-auto min-h-screen w-full max-w-3xl bg-crema px-5 py-8 text-tinta">
      <header className="mb-6 flex items-center justify-between gap-4">
        <div className="flex items-center gap-3">
          {yo ? (
            <FotoDePerfil supabase={supabase} yo={yo} subiendo={subiendoFoto} error={errorFoto} onSubir={subirMiFoto} />
          ) : (
            <Colibri tono="rojo" className="w-8" />
          )}
          <div>
            <h1 className="font-serif text-2xl leading-tight">{yo?.nombre ?? "Lo mío"}</h1>
            <p className="etiqueta text-taupe">Tus días, tus turnos y tus objetivos</p>
          </div>
        </div>
        {/* ── La salida ────────────────────────────────────────────────────────
            Esta pantalla vive FUERA de `(admin)`, así que no hereda el menú: sin
            estos dos enlaces es un callejón sin salida. Quien tiene panel entró
            desde «Lo mío» del menú y necesita volver; quien no lo tiene, no ve
            un enlace que le daría error.

            Y «Salir» manda a /admin/login en vez de dejar el formulario de esta
            misma pantalla: ese formulario vuelve siempre a /mio, así que cerrar
            sesión y entrar de nuevo devolvía aquí para siempre. El login del
            panel sí reparte por rol. */}
        <div className="flex items-center gap-4">
          {yo && ROLES_CON_PANEL.includes(yo.rol as never) && (
            <Link href="/admin/dashboard" className="text-xs text-taupe underline">
              Volver al panel
            </Link>
          )}
          <button onClick={() => void supabase.auth.signOut().then(() => router.replace("/admin/login"))}
            className="text-xs text-taupe underline">Salir</button>
          <SelectorTema />
        </div>
      </header>

      {/* ⚠ VA AQUÍ Y ES LO PRIMERO. Este aviso llevaba desde que se escribió
          pintándose SOLO dentro de `AdminNav`, y el login manda a /mio a quien no
          tiene panel: o sea que la integrante —para quien se escribió— nunca lo
          veía. La Ley 30709 obliga a informar la política salarial y a PODER
          PROBARLO, y el reglamento interno igual. Un acuse que no le llega a su
          destinataria no prueba nada. */}
      <AcusesPendientes />

      <AnunciosWidget />

      {aviso && <div className="mb-6 rounded-2xl border border-ambar/30 bg-ambar/[0.06] p-4 text-sm">{aviso}</div>}

      {/* ── El periodo de pago ───────────────────────────────────────────────
          La pregunta que de verdad se hace al abrir esto es «¿voy a cobrar
          bien?». Esto responde la parte de «¿están todos mis días bien
          registrados antes de que cierre?» — sin montos, porque eso no
          depende del periodo que se esté mirando en el filtro de abajo, sino
          de "el periodo actual" siempre. El enlace a la boleta (0339) vive
          aparte, en su propia pantalla `/mio/boleta`, por la misma razón que
          en admin: es un documento que se imprime, y el print de esta
          pantalla imprimiría las quince secciones de arriba con él. */}
      {periodo && estadoDelPeriodo && (
        <section className={`mb-6 rounded-2xl border p-4 text-sm ${
          estadoDelPeriodo.pendientes > 0 ? "border-ambar/40 bg-ambar/[0.07]" : "border-sand"}`}>
          <p>
            Tu periodo de pago va del <strong>{diaYMes(periodo.fecha_ini)}</strong> al{" "}
            <strong>{diaYMes(periodo.fecha_fin)}</strong>
            {estadoDelPeriodo.cierra > 0
              ? <> · cierra en {estadoDelPeriodo.cierra} día{estadoDelPeriodo.cierra === 1 ? "" : "s"}</>
              : <> · cierra hoy</>}.
          </p>
          <p className="mt-1 text-taupe">
            {!estadoDelPeriodo.cubre
              ? "Estás mirando otro rango de fechas: toca «Periodo de pago» para revisar el que se te va a pagar."
              : estadoDelPeriodo.pendientes > 0
                ? `Tienes ${estadoDelPeriodo.pendientes} día${estadoDelPeriodo.pendientes === 1 ? "" : "s"} por revisar dentro de este periodo. Míralos abajo antes de que cierre.`
                : "Todos tus días de este periodo están completos."}
          </p>
          <Link
            href="/mio/boleta"
            className="mt-2 inline-block text-sm font-medium text-tinta underline hover:text-rojo-profundo"
          >
            🧾 Ver mi boleta de este periodo
          </Link>
        </section>
      )}

      {/* ── Lo que necesita su atención ──────────────────────────────────────
          Arriba y con un verbo, no como una etiqueta pequeña dentro de la tabla.
          Estos son los días que le pueden costar plata a ella, y es la única que
          sabe qué pasó de verdad ese día. */}
      {(resumen.porRevisar.length > 0 || resumen.faltas.length > 0 || respondidas.length > 0) && (
        <section className="mb-6 rounded-2xl border border-ambar/40 bg-ambar/[0.07] p-4 text-sm">
          <h2 className="mb-2 font-serif text-lg">Revisa esto</h2>
          {resumen.porRevisar.length > 0 && (
            <p className="mb-1">
              <strong>{resumen.porRevisar.length} día{resumen.porRevisar.length === 1 ? "" : "s"} con el marcaje incompleto</strong>{" "}
              ({resumen.porRevisar.map((d) => diaYMes(d.fecha)).join(", ")}). Falta la salida o la puso el sistema,
              así que las horas de ese día no son las que trabajaste.
            </p>
          )}
          {resumen.faltas.length > 0 && (
            <p className="mb-1">
              <strong>{resumen.faltas.length} día{resumen.faltas.length === 1 ? "" : "s"} figuran sin marcaje</strong>{" "}
              ({resumen.faltas.map((d) => diaYMes(d.fecha)).join(", ")}). Si trabajaste o tenías permiso, se corrige
              con el motivo anotado.
            </p>
          )}
          {respondidas.length > 0 && (
            <div className="mb-1">
              <strong>
                Te respondieron {respondidas.length === 1 ? "el día que pediste revisar" : `los ${respondidas.length} días que pediste revisar`}.
              </strong>
              <ul className="mt-0.5 space-y-0.5">
                {respondidas.map((r) => (
                  <li key={r.fecha}>
                    <span className="text-taupe">{diaYMes(r.fecha)}:</span> {r.respuesta}
                  </li>
                ))}
              </ul>
            </div>
          )}
          <p className="text-taupe">Avísale a tu encargada. Un marcaje se arregla; al final del mes ya no.</p>
        </section>
      )}

      {/* ── Correcciones a sus marcajes ──────────────────────────────────────
          Ya se puede leer desde la 0003 (auditoria_select_propia); nadie lo
          mostraba. Sin esto, alguien corrige un marcaje suyo y ella no tiene
          cómo enterarse de qué cambió ni por qué — se entera si pregunta. */}
      {correcciones.length > 0 && (
        <section className="mb-6 rounded-2xl border border-sand p-5 text-sm">
          <h2 className="mb-1 font-serif text-lg">Correcciones a tus marcajes</h2>
          <p className="mb-3 text-taupe">
            Cuando alguien corrige uno de tus marcajes queda anotado acá, con el motivo.
          </p>
          <ul className="space-y-3">
            {correcciones.map((c) => (
              <li key={c.id} className="border-t border-sand pt-3 first:border-t-0 first:pt-0">
                <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-0.5">
                  <span className="font-medium">{etiquetaCampo(c.campo_modificado)}</span>
                  <span className="text-xs text-taupe">{fechaYHora(c.corregido_at)}</span>
                </div>
                <p className="text-taupe">
                  {valorLegible(c.campo_modificado, c.valor_anterior)} → {valorLegible(c.campo_modificado, c.valor_nuevo)}
                  {c.marcajes && <> · marcaje del {diaYMes(fechaLimaDeMarca(c.marcajes.timestamp_marca))}</>}
                </p>
                <p className="mt-0.5 italic">«{c.motivo}»</p>
              </li>
            ))}
          </ul>
        </section>
      )}

      {/* ── Cuándo te toca ───────────────────────────────────────────────────
          De hoy en adelante. Es la pregunta que más veces abre esta pantalla, y
          hasta hoy se respondía por WhatsApp. */}
      <section className="mb-6 rounded-2xl border border-sand p-5">
        <h2 className="mb-3 font-serif text-lg">Cuándo te toca</h2>
        {proximos.length === 0 ? (
          <p className="text-sm text-taupe">
            No hay turnos ni horario cargados para los próximos días. Si eso no es lo que esperabas, avísale a tu encargada.
          </p>
        ) : (
          <ul className="flex flex-wrap gap-2">
            {proximos.map(({ fecha, esperado }) => (
              <li key={fecha}
                className={`rounded-xl border px-3 py-2 ${fecha === hoyLima() ? "border-tinta bg-papel" : "border-sand"}`}>
                <div className="text-xs capitalize text-taupe">{cuando(fecha)}</div>
                <div className="font-medium">{esperado.entrada}{esperado.salida ? `–${esperado.salida}` : ""}</div>
                {esperado.origen === "turno" && <div className="text-[10px] text-taupe">turno del día</div>}
              </li>
            ))}
          </ul>
        )}
        {feriados.length > 0 && (
          <p className="mt-3 text-xs text-taupe">
            Próximo feriado: <strong>{diaYMes(feriados[0].fecha)}</strong>, {feriados[0].nombre}.
          </p>
        )}
      </section>

      {/* ── El filtro ────────────────────────────────────────────────────────
          Abre en los últimos 30 días. El botón del periodo de pago está porque es
          el tramo con el que se le paga —del 29 al 28, leído de la base y nunca
          calculado— y es contra el que va a querer cuadrar su boleta. */}
      <section className="mb-6 flex flex-wrap items-end gap-3 rounded-2xl border border-sand px-4 py-3">
        <label className="flex flex-col gap-1 text-xs text-taupe">Desde
          <input type="date" value={desde} max={hasta} onChange={(e) => setDesde(e.target.value)}
            className="rounded-lg border border-sand bg-crema px-3 py-1.5 text-sm text-tinta" />
        </label>
        <label className="flex flex-col gap-1 text-xs text-taupe">Hasta
          <input type="date" value={hasta} min={desde} max={hoyLima()} onChange={(e) => setHasta(e.target.value)}
            className="rounded-lg border border-sand bg-crema px-3 py-1.5 text-sm text-tinta" />
        </label>
        <div className="flex flex-wrap gap-2">
          <button onClick={() => { setDesde(haceDias(30)); setHasta(hoyLima()); }}
            className="rounded-lg border border-sand px-3 py-1.5 text-xs">Últimos 30 días</button>
          <button onClick={() => void irAlPeriodoDePago()}
            className="rounded-lg border border-sand px-3 py-1.5 text-xs">Periodo de pago</button>
        </div>
      </section>

      {/* Cada número con su «de cuánto». Sin eso, «6h 54m de promedio» no dice si
          va bien o mal, y ella no tiene a quién preguntarle. */}
      <div className="mb-6 grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Tarjeta titulo="Días trabajados" valor={String(resumen.trabajados)}
          pie={resumen.diasEsperados > 0 ? `de ${resumen.diasEsperados} que te tocaban` : "sin horario cargado"} />
        <Tarjeta titulo="Total de horas" valor={comoReloj(resumen.total)}
          pie={resumen.horasEsperadas > 0 ? `de ${comoReloj(resumen.horasEsperadas)}` : undefined} />
        <Tarjeta titulo="Promedio por día" valor={comoReloj(resumen.promedio)}
          pie={resumen.jornadaDiaria > 0 ? `tu jornada son ${comoReloj(resumen.jornadaDiaria)}` : undefined} />
        {/* «de N medidos» y no un número suelto: un cero puede significar
            «llegaste puntual» o «no había horario que comparar». */}
        <Tarjeta titulo="Tardanzas" valor={String(resumen.tardanzas)} pie={`de ${resumen.medidos} días con horario que comparar`} />
      </div>

      {/* ── El mes de un vistazo ─────────────────────────────────────────────
          Un cuadrito por día, con los MISMOS colores que ve su encargada. Que las
          dos vean el mismo día del mismo color es lo que les deja hablar de él
          sin traducirse la una a la otra. */}
      <section className="mb-6 rounded-2xl border border-sand p-5">
        <h2 className="mb-3 font-serif text-lg">Tu mes</h2>
        {cargando ? <p className="text-sm text-taupe">Cargando…</p>
          : dias.length === 0 ? <p className="text-sm text-taupe">No hay días en este rango.</p>
          : (
            <>
              <div className="overflow-x-auto pb-1">
                <div className="flex">
                  {dias.map((d) => (
                    <div key={d.fecha} className="w-[22px] shrink-0 px-[1px] text-center">
                      <div className={`text-[9px] leading-tight ${dowDe(d.fecha) === 0 ? "text-rojo/60" : "text-taupe"}`}>
                        {LETRA_DIA[dowDe(d.fecha)]}
                      </div>
                      {/* Un <button> y no un <div> con `title`: en un teléfono no
                          existe el hover, así que el tooltip nunca aparece y la
                          fila de colores se vuelve decoración. Se toca y se abre. */}
                      <button
                        onClick={() => { setDiaAbierto((f) => (f === d.fecha ? null : d.fecha)); setComentario(""); setAvisoRevision(null); }}
                        title={explicaDia(d)}
                        aria-label={explicaDia(d)}
                        className={`h-7 w-full rounded-[3px] ${colorDia(d)} ${
                          diaAbierto === d.fecha ? "ring-2 ring-tinta ring-offset-1" : ""} ${
                          revisiones.has(d.fecha) ? "outline outline-1 outline-offset-1 outline-tinta/40" : ""}`}
                      />
                      <div className="text-[9px] leading-tight text-taupe">{Number(d.fecha.slice(8, 10))}</div>
                    </div>
                  ))}
                </div>
              </div>
              {/* ── El día que tocó ─────────────────────────────────────────
                  Va DEBAJO de la cuadrícula y no en un panel que tape la
                  pantalla: en un teléfono un modal a pantalla completa hace
                  perder de vista dónde estabas. */}
              {diaAbierto && (() => {
                const d = dias.find((x) => x.fecha === diaAbierto);
                if (!d) return null;
                const rev = revisiones.get(d.fecha);
                return (
                  <div className="mt-4 rounded-2xl border border-tinta/20 bg-papel p-4 text-sm">
                    <div className="mb-2 flex items-start justify-between gap-3">
                      <h3 className="font-serif text-lg capitalize">{diaYMes(d.fecha)}</h3>
                      <button onClick={() => setDiaAbierto(null)} className="text-xs text-taupe underline">cerrar</button>
                    </div>
                    <dl className="space-y-1">
                      <div className="flex justify-between gap-4">
                        <dt className="text-taupe">Te tocaba</dt>
                        <dd className="text-right">
                          {d.esperado.trabaja
                            ? <>{d.esperado.entrada}{d.esperado.salida ? `–${d.esperado.salida}` : ""}</>
                            : d.estado === "sin_horario" ? "no hay horario cargado" : "descansar"}
                        </dd>
                      </div>
                      <div className="flex justify-between gap-4">
                        <dt className="text-taupe">Entraste</dt>
                        <dd className={(d.jornada?.minutos_tarde ?? 0) > 0 && !d.perdonada ? "text-ambar" : ""}>
                          {hora(d.jornada?.entrada_ts ?? null)}
                        </dd>
                      </div>
                      <div className="flex justify-between gap-4">
                        <dt className="text-taupe">Saliste</dt>
                        <dd>{d.jornada?.salida_final_ts ? hora(d.jornada.salida_final_ts) : <span className="text-ambar">no quedó marcada</span>}</dd>
                      </div>
                      {d.jornada?.horas_trabajadas != null && (
                        <div className="flex justify-between gap-4">
                          <dt className="text-taupe">Trabajaste</dt>
                          <dd>{comoReloj(d.jornada.horas_trabajadas)}</dd>
                        </div>
                      )}
                      {(d.jornada?.minutos_tarde ?? 0) > 0 && (
                        <div className="flex justify-between gap-4">
                          <dt className="text-taupe">Llegaste tarde</dt>
                          <dd className={d.perdonada ? "text-taupe" : "text-ambar"}>
                            {comoMinutos(d.jornada!.minutos_tarde!)}{d.perdonada && " · justificada"}
                          </dd>
                        </div>
                      )}
                    </dl>

                    {d.estado === "falta" && (
                      <p className="mt-3 rounded-lg bg-rojo/10 px-3 py-2 text-rojo">
                        Te tocaba trabajar y no hay ningún marcaje tuyo de ese día.
                      </p>
                    )}
                    {d.estado === "justificada" && (
                      <p className="mt-3 rounded-lg bg-sand/60 px-3 py-2">No marcaste, y está justificado.</p>
                    )}

                    {/* ── Decir que algo no cuadra ──────────────────────────
                        Lo que convierte esta pantalla de informativa en útil.
                        Antes todo terminaba en «avísale a tu encargada», que en
                        un teléfono es un callejón: lo ve, cierra el navegador y
                        se acuerda cuando llega la boleta. */}
                    {rev ? (
                      <div className="mt-3 rounded-lg border border-tinta/20 px-3 py-2">
                        <p className="text-taupe">Pediste que se revise este día:</p>
                        <p className="mt-1">«{rev.comentario}»</p>
                        {rev.atendida_at ? (
                          <p className="mt-2 rounded bg-verde/10 px-2 py-1.5 text-verde">
                            Respondido: {rev.respuesta ?? "sin comentario"}
                          </p>
                        ) : (
                          <div className="mt-2 flex items-center gap-3">
                            <span className="text-taupe">Todavía sin responder.</span>
                            <button onClick={() => void quitarRevision(d.fecha)} disabled={enviando}
                              className="text-xs text-rojo underline disabled:opacity-50">retirar</button>
                          </div>
                        )}
                      </div>
                    ) : puedePedirRevision ? (
                      <div className="mt-3">
                        <label className="flex flex-col gap-1 text-xs text-taupe">
                          ¿Algo de este día no cuadra? Cuéntalo y le llega a tu encargada.
                          <textarea value={comentario} onChange={(e) => setComentario(e.target.value)} rows={2}
                            placeholder="Ese día sí vine, marqué la entrada y la salida no me tomó."
                            className="rounded-lg border border-sand bg-crema px-3 py-2 text-sm text-tinta" />
                        </label>
                        <button onClick={() => void pedirRevision(d.fecha)} disabled={enviando}
                          className="mt-2 rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema disabled:opacity-50">
                          {enviando ? "Enviando…" : "Pedir que se revise"}
                        </button>
                      </div>
                    ) : null}
                    {avisoRevision && (
                      <p className={`mt-2 text-xs ${avisoRevision.tipo === "ok" ? "text-verde" : "text-rojo"}`}>
                        {avisoRevision.texto}
                      </p>
                    )}
                  </div>
                );
              })()}

              <div className="mt-3 flex flex-wrap gap-x-4 gap-y-1 text-[11px] text-taupe">
                <span className="flex items-center gap-1.5"><i className="inline-block size-3 rounded-[3px] bg-verde" /> trabajaste</span>
                <span className="flex items-center gap-1.5"><i className="inline-block size-3 rounded-[3px] bg-ambar" /> llegaste tarde</span>
                <span className="flex items-center gap-1.5"><i className="inline-block size-3 rounded-[3px] bg-rojo" /> no marcaste</span>
                <span className="flex items-center gap-1.5"><i className="inline-block size-3 rounded-[3px] bg-rojo/20" /> con motivo</span>
                <span className="flex items-center gap-1.5"><i className="inline-block size-3 rounded-[3px] border border-dashed border-taupe bg-crema" /> falta una marca</span>
                <span className="flex items-center gap-1.5"><i className="inline-block size-3 rounded-[3px] bg-sand" /> descanso</span>
              </div>
              <p className="mt-3 text-xs text-taupe">
                Si tu encargada justificó una tardanza, deja de contar acá.
              </p>
            </>
          )}
      </section>

      {/* ── Sus objetivos ────────────────────────────────────────────────────
          De solo lectura: marcarlos cumplidos es de su encargada, y esa es la
          razón por la que valen. Sin lenguaje de premio — desde la 0171 los
          objetivos NO pagan, así que nada de «plus» ni de verde de recompensa. */}
      <section className="mb-6 rounded-2xl border border-sand p-5">
        <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
          <h2 className="font-serif text-lg">Tus objetivos de {mesLabel}</h2>
          {objetivos.length > 0 && (
            <span className="text-sm text-taupe">{objCumplidos} de {objetivos.length}</span>
          )}
        </div>
        {objetivos.length === 0 ? (
          <p className="text-sm text-taupe">
            Todavía no tienes objetivos cargados para {mesLabel}. Los acuerda contigo tu encargada.
          </p>
        ) : (
          <>
            <div className="mb-3 h-2 overflow-hidden rounded-full bg-sand">
              <div className="h-full rounded-full bg-verde"
                style={{ width: `${Math.round((objCumplidos / objetivos.length) * 100)}%` }} />
            </div>
            <ul className="space-y-1.5 text-sm">
              {objetivos.map((o) => (
                <li key={o.id} className="flex items-start gap-2">
                  <span className={o.cumplido ? "text-verde" : "text-taupe/50"}>{o.cumplido ? "✓" : "○"}</span>
                  <div>
                    <span className={o.cumplido ? "text-taupe line-through" : ""}>{o.descripcion}</span>
                    {o.indicaciones && (
                      <p className="mt-0.5 whitespace-pre-wrap text-xs text-taupe">{o.indicaciones}</p>
                    )}
                  </div>
                </li>
              ))}
            </ul>
            <p className="mt-3 text-xs text-taupe">
              Los marca tu encargada cuando los conversan. Si crees que alguno ya está, díselo.
            </p>
          </>
        )}
      </section>

      {/* ── Sus vacaciones, y hasta cuándo puede tomarlas ───────────────────
          Un récord que se cierra tiene un año para gozarse. Pasado ese año la
          empresa debe una indemnización (art. 23 del D. Leg. 713) y la persona
          se quedó sin su descanso — que es lo que de verdad importa acá. Nadie
          pide vacaciones que no sabe que tiene. */}
      {vacas && vacas.records_sin_gozar > 0 && vacas.vence_el && (
        <section className={`mb-6 rounded-2xl border p-5 text-sm ${
          (vacas.dias_para_vencer ?? 999) <= 60 ? "border-ambar/40 bg-ambar/[0.07]" : "border-sand"}`}>
          <h2 className="mb-2 font-serif text-lg">Tus vacaciones</h2>
          <p>
            Te quedan <strong>{vacas.dias_pendientes} días</strong> sin tomar, y el récord más
            antiguo <strong>vence el {diaYMes(vacas.vence_el)}</strong>
            {typeof vacas.dias_para_vencer === "number" && vacas.dias_para_vencer >= 0
              ? ` — faltan ${vacas.dias_para_vencer} días.`
              : "."}
          </p>
          <p className="mt-2 text-xs text-taupe">
            Después de esa fecha esos días ya no se pueden tomar como descanso. Pídelas abajo
            antes de que llegue esa fecha.
          </p>
        </section>
      )}

      {/* ── Pedir vacaciones ─────────────────────────────────────────────────
          Solo si le aplican (`vacas` viene null cuando no aplica o no hay
          sesión resuelta todavía). No dice si el saldo alcanza para el rango
          elegido: eso lo decide `fn_solicitar_vacaciones` con el mismo cálculo
          que ya se le mostró arriba, y su respuesta es la que se ve abajo. */}
      {vacas && (
        <section className="mb-6 rounded-2xl border border-sand p-5 text-sm">
          <h2 className="mb-3 font-serif text-lg">Pedir vacaciones</h2>
          <p className="mb-3 text-taupe">
            Tienes <strong>{vacas.dias_pendientes} días</strong> pendientes. Elige el rango y avisa —tu
            encargada no la aprueba, la aprueba Desarrollo Organizacional.
          </p>
          <form onSubmit={(e) => void pedirVacaciones(e)} className="flex flex-wrap items-end gap-3">
            <label className="flex flex-col gap-1 text-xs text-taupe">Desde
              <input type="date" value={desdeSolicitud} min={hoyLima()} max={hastaSolicitud}
                onChange={(e) => setDesdeSolicitud(e.target.value)}
                className="rounded-lg border border-sand bg-crema px-3 py-1.5 text-sm text-tinta" required />
            </label>
            <label className="flex flex-col gap-1 text-xs text-taupe">Hasta
              <input type="date" value={hastaSolicitud} min={desdeSolicitud}
                onChange={(e) => setHastaSolicitud(e.target.value)}
                className="rounded-lg border border-sand bg-crema px-3 py-1.5 text-sm text-tinta" required />
            </label>
            <label className="flex min-w-48 flex-1 flex-col gap-1 text-xs text-taupe">Comentario (opcional)
              <input type="text" value={comentarioSolicitud} onChange={(e) => setComentarioSolicitud(e.target.value)}
                placeholder="Lo que quieras que sepa Desarrollo Organizacional"
                className="rounded-lg border border-sand bg-crema px-3 py-1.5 text-sm text-tinta" />
            </label>
            <button type="submit" disabled={enviandoSolicitud}
              className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema disabled:opacity-50">
              {enviandoSolicitud ? "Enviando…" : "Pedir"}
            </button>
          </form>
          {avisoSolicitud && (
            <p className={`mt-2 text-xs ${avisoSolicitud.tipo === "ok" ? "text-verde" : "text-rojo"}`}>
              {avisoSolicitud.texto}
            </p>
          )}

          {solicitudesVacas.length > 0 && (
            <ul className="mt-4 space-y-2 border-t border-sand pt-3">
              {solicitudesVacas.map((s) => (
                <li key={s.id} className="flex flex-wrap items-center justify-between gap-2 text-xs">
                  <span>
                    {diaYMes(s.fecha_inicio)}{s.fecha_fin !== s.fecha_inicio ? ` – ${diaYMes(s.fecha_fin)}` : ""}
                    {" · "}
                    <span className={
                      s.estado === "aprobada" ? "text-verde"
                      : s.estado === "rechazada" ? "text-rojo"
                      : s.estado === "cancelada" ? "text-taupe"
                      : "text-ambar"
                    }>
                      {s.estado === "pendiente" ? "por resolver" : s.estado}
                    </span>
                    {s.respuesta && <span className="text-taupe"> — «{s.respuesta}»</span>}
                  </span>
                  {s.estado === "pendiente" && (
                    <button onClick={() => void retirarSolicitudVacas(s.id)} disabled={enviandoSolicitud}
                      className="text-taupe underline disabled:opacity-50">retirar</button>
                  )}
                </li>
              ))}
            </ul>
          )}
        </section>
      )}

      {/* ── Sus ausencias ────────────────────────────────────────────────────
          «El descanso médico que presenté, ¿quedó registrado?» es una pregunta
          que hoy se responde preguntando. Y el aviso del documento que falta la
          protege a ella: sin documento, ese permiso no cuenta igual. */}
      {ausencias.length > 0 && (
        <section className="mb-6 rounded-2xl border border-sand p-5">
          {/* Incluye las vacaciones: la vista `vacaciones` no es otra tabla,
              es un SELECT sobre `ausencias` con tipo='vacaciones'. Consultarla
              aparte traería las mismas filas dos veces. */}
          <h2 className="mb-3 font-serif text-lg">Tus permisos, descansos y vacaciones</h2>
          <ul className="space-y-2 text-sm">
            {ausenciasAgrupadas.map((a) => {
              const faltaDoc = exigeDoc(a.tipo) && !a.doc_profesional;
              return (
                <li key={`${a.tipo}-${a.fecha_inicio}`} className="flex flex-wrap items-baseline gap-x-2">
                  <span className="font-medium">{nombreTipo(a.tipo)}</span>
                  <span className="text-taupe">
                    {a.fecha_inicio === a.hasta ? diaYMes(a.fecha_inicio) : `del ${diaYMes(a.fecha_inicio)} al ${diaYMes(a.hasta)}`}
                  </span>
                  {/* La condición, no la cifra. Que un permiso no se pague es
                      algo que debería haber sabido al pedirlo, y callarlo deja
                      la sorpresa para el día de la boleta. Ningún monto: en esta
                      pantalla no hay dinero. */}
                  {noPaga(a.tipo) && (
                    <span className="rounded-full bg-sand px-2 py-0.5 text-[11px] text-taupe">no remunerado</span>
                  )}
                  {faltaDoc && (
                    <span className="rounded-full bg-ambar/15 px-2 py-0.5 text-[11px] text-ambar">
                      falta el documento
                    </span>
                  )}
                </li>
              );
            })}
          </ul>
          <p className="mt-3 text-xs text-taupe">
            Si presentaste algo que no aparece acá, todavía se puede registrar — avísale a tu encargada.
            {hayCumpleanos && " Y recuerda que tienes permiso por tu cumpleaños: se pide, no se descuenta solo."}
          </p>
        </section>
      )}

      {/* ── El desglose ──────────────────────────────────────────────────────
          Solo los días con marcaje. Un día de descanso o un feriado no tienen por
          qué ocupar una fila vacía en una pantalla que se mira en el teléfono. */}
      <section className="rounded-2xl border border-sand p-5">
        <h2 className="mb-4 font-serif text-lg">Día por día</h2>
        {jornadas.length === 0 ? (
          <p className="text-sm text-taupe">No hay días marcados en este rango.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-sand text-left">
                  <th className="etiqueta pb-2 font-normal text-taupe">Día</th>
                  <th className="etiqueta pb-2 font-normal text-taupe">Entrada</th>
                  <th className="etiqueta pb-2 font-normal text-taupe">Salida</th>
                  <th className="etiqueta pb-2 font-normal text-taupe">Te tocaba</th>
                  <th className="etiqueta pb-2 font-normal text-taupe">Tardanza</th>
                  <th className="etiqueta pb-2 text-right font-normal text-taupe">Horas</th>
                </tr>
              </thead>
              <tbody>
                {[...dias].reverse().filter((d) => d.jornada !== null).map((d) => {
                  const j = d.jornada!;
                  const tarde = (j.minutos_tarde ?? 0) > 0;
                  const laPusoElSistema = j.estado === "auto_cerrada_pendiente";
                  return (
                    <tr key={d.fecha} className="border-b border-sand/60">
                      <td className="py-2">{diaYMes(d.fecha)}</td>
                      <td className="py-2">{hora(j.entrada_ts)}</td>
                      <td className="py-2">
                        {hora(j.salida_final_ts)}
                        {/* Esa hora NO la marcó ella: la inventó el auto-cierre porque
                            olvidó marcar. Es justo la que conviene que revise, así que
                            se dice en vez de dejarla pasar por buena. */}
                        {laPusoElSistema && (
                          <span className="ml-2 rounded-full bg-ambar/15 px-2 py-0.5 text-[10px] text-ambar">
                            la puso el sistema
                          </span>
                        )}
                      </td>
                      {/* Contra qué se midió su tardanza ese día. Sin esto, un
                          número de minutos es una afirmación sin origen. */}
                      <td className="py-2 text-taupe">
                        {d.esperado.trabaja
                          ? <>{d.esperado.entrada}{d.esperado.salida ? `–${d.esperado.salida}` : ""}</>
                          : "—"}
                      </td>
                      <td className="py-2">
                        {!tarde ? <span className="text-taupe">—</span>
                          : d.perdonada ? <span className="text-taupe line-through">{j.minutos_tarde} min</span>
                          : <span className="text-ambar">{j.minutos_tarde} min</span>}
                      </td>
                      <td className="py-2 text-right">{comoReloj(j.horas_trabajadas ?? 0)}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <p className="mt-6 text-xs text-taupe">
        Si algo no cuadra, no lo dejes pasar: avisa a tu encargada y se corrige con el motivo anotado. Lo que
        ves sale de tus marcajes, y un marcaje mal registrado se arregla, no se discute al final del mes.
      </p>
    </main>
  );
}

/**
 * La foto que aparece junto a su nombre en el terminal de marcaje (0381). Se
 * comprime en el navegador antes de subir — ver `comprimirFotoPerfil`.
 *
 * El botón de texto va SIEMPRE visible, no solo al pasar el mouse: esta
 * pantalla la abre cada quien desde su propio celular, donde no hay hover.
 */
function FotoDePerfil({
  supabase, yo, subiendo, error, onSubir,
}: {
  supabase: ReturnType<typeof createAdminSupabaseClient>;
  yo: Yo;
  subiendo: boolean;
  error: string | null;
  onSubir: (archivo: File) => void;
}) {
  const inputRef = useRef<HTMLInputElement>(null);
  const url = urlPublicaFotoPerfil(supabase, yo.fotoUrl);

  return (
    <div className="flex flex-col items-center gap-1">
      <button
        type="button"
        onClick={() => inputRef.current?.click()}
        disabled={subiendo}
        className="h-14 w-14 overflow-hidden rounded-full border border-sand disabled:opacity-60"
      >
        {url ? (
          // eslint-disable-next-line @next/next/no-img-element -- foto de un bucket externo, no un asset local
          <img src={url} alt="" className="h-full w-full object-cover" />
        ) : (
          <span className="flex h-full w-full items-center justify-center bg-sand text-lg text-taupe">
            {inicialesDe(yo.nombres, yo.apellidos)}
          </span>
        )}
      </button>
      <button
        type="button"
        onClick={() => inputRef.current?.click()}
        disabled={subiendo}
        className="text-[11px] text-taupe underline disabled:opacity-60"
      >
        {subiendo ? "Subiendo…" : "Cambiar foto"}
      </button>
      <input
        ref={inputRef}
        type="file"
        accept="image/*"
        className="hidden"
        onChange={(e) => {
          const archivo = e.target.files?.[0];
          e.target.value = "";
          if (archivo) onSubir(archivo);
        }}
      />
      {error && <p className="max-w-[9rem] text-center text-[11px] text-rojo">{error}</p>}
    </div>
  );
}

function Tarjeta({ titulo, valor, pie }: { titulo: string; valor: string; pie?: string }) {
  return (
    <div className="rounded-2xl border border-sand px-4 py-3">
      <div className="etiqueta text-taupe">{titulo}</div>
      <div className="mt-1 font-serif text-2xl leading-none">{valor}</div>
      {pie && <div className="mt-1 text-[11px] text-taupe">{pie}</div>}
    </div>
  );
}
