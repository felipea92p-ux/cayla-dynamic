"use client";

import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Colibri } from "@/components/marca";
import { AcusesPendientes } from "@/components/acuses-pendientes";
import { AnunciosWidget } from "@/components/anuncios-widget";
import { SelectorTema } from "@/components/selector-tema";
import { Boton } from "@/components/ui/boton";
import { Insignia } from "@/components/ui/insignia";
import { Campo } from "@/components/ui/campo";
import { AreaTexto } from "@/components/ui/area-texto";
import { Tabla, TablaEncabezado, Th, Fila } from "@/components/ui/tabla";
import { useToast } from "@/components/toast";
import { FirmaEditor } from "@/app/(admin)/admin/personas/[id]/FirmaEditor";
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
import { loQueNoSePudo } from "@/lib/admin/lo-que-no-se-pudo";

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
  /** El nombre tal como aparece en el DNI (`datos_personales.nombre_dni`),
   *  con reserva a `nombre` si todavía no cargó su ficha. Es el que se usa
   *  para firmar documentos — nunca `nombre` a secas, que es de uso diario
   *  y puede no coincidir con el oficial (ver FirmaEditor). */
  nombreOficial: string;
  nombres: string;
  apellidos: string;
  fechaIngreso: string | null;
  /** Para saber si esta persona tiene panel al que volver. Nada más: lo que se
   *  muestra en esta pantalla es igual para todo el mundo. */
  rol: string | null;
  /** Ruta en el bucket público «fotos-perfil» (0381), o null si nunca subió una. */
  fotoUrl: string | null;
  /** Su puesto, tal como se llama en la casa. Se muestra el CARGO y nunca el
   *  `rol` del sistema: el rol dice qué pantallas alcanza, no a qué se dedica —
   *  y ponerlo en un perfil obligaría además a traducir `supervisor_sede` a
   *  «encargada» aquí, fuera de donde vive esa traducción. */
  cargo: string | null;
  /** Nombre de su sede BASE —la que la contrata—, no la física en la que está
   *  cubriendo hoy. Se lee de `sedes` nombrando la llave foránea
   *  (`personas_sede_base_id_fkey`) porque hay DOS caminos de `personas` a
   *  `sedes` y PostgREST no adivina cuál: sin nombrarla, la consulta entera
   *  falla. Y se lee de la tabla, nunca de una lista escrita a mano: esa lista
   *  ya se volvió falsa una vez, cuando abrió Central. */
  sede: string | null;
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

/** Las seis pestañas del detalle. Ver el comentario de `tab`. */
type Tab = "dias" | "turnos" | "ausencias" | "contrato" | "firma" | "objetivos" | "historial";

/**
 * Lo mínimo para saber si tiene contrato y a dónde llevarla a verlo. El texto
 * completo (`documento_html`) NO se pide acá — vive en `/mio/contrato`, su
 * propia pantalla, con el mismo criterio que la boleta: es un documento que
 * se imprime, y esta pestaña solo dice que existe.
 */
interface MiContrato {
  tipo: string;
  fecha_inicio: string;
  fecha_fin: string | null;
  fecha_firma: string | null;
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
  marca_apartada: "Un marcaje tuyo que no llegó a registrarse",
};
function etiquetaCampo(campo: string): string {
  return ETIQUETA_CAMPO[campo] ?? campo.replaceAll("_", " ");
}

/**
 * ⚠ EL ERROR TÉCNICO NO SE LE ENSEÑA A LA PERSONA.
 *
 * `fn_marca_apartada_resolver` (0304) guarda en `valor_anterior` la marca Y el
 * error de Postgres que la apartó, separados por « · ». Eso está bien: DO
 * necesita ese texto para saber por qué el terminal no pudo registrarla.
 *
 * Pero esta pantalla la abre la persona desde su celular, y ahí ese texto salía
 * crudo — media pantalla de «Could not choose the best candidate function
 * between: public.fn_registrar_marcaje(p_persona_id => uuid, …)» en el sitio
 * donde esperaba leer qué pasó con su marcaje del jueves. No es una fuga: es
 * ruido que hace ilegible lo único que sí le importa. Se recorta acá, en la
 * presentación, y no en la base: el dato completo sigue donde tiene que estar.
 */
function limpiaErrorTecnico(campo: string, valor: string | null): string | null {
  if (campo !== "marca_apartada" || valor === null) return valor;
  return valor.split(" · ")[0];
}

/** «repuesta» / «improcedente» dicho como se lo diría una persona a otra. */
const RESOLUCION_APARTADA: Record<string, string> = {
  repuesta: "se registró después, con su hora original",
  improcedente: "se revisó y no correspondía registrarla",
};
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

/** «2025-08-14» → «agosto de 2025». Para el «desde cuándo» del perfil. */
function mesYAnio(iso: string): string {
  const [a, m] = iso.split("-");
  return `${MESES[Number(m) - 1]} de ${a}`;
}

/**
 * Cuánto lleva en CAYLA, dicho en años y meses. No es adorno: la antigüedad es
 * lo que decide cuántos días de vacaciones le tocan y qué escalón de la
 * escalera disciplinaria le aplica, y hoy solo la sabe quien abre su ficha en
 * el panel. Se cuenta en meses completos —«1 año y 2 meses»— y nunca en días,
 * que es como lo diría ella.
 */
function antiguedad(ingreso: string): string {
  const [ai, mi, di] = ingreso.split("-").map(Number);
  const [ah, mh, dh] = hoyLima().split("-").map(Number);
  let meses = (ah - ai) * 12 + (mh - mi);
  if (dh < di) meses--;
  if (meses < 0) return "recién ingresada";
  if (meses < 1) return "menos de un mes";
  if (meses < 12) return `${meses} ${meses === 1 ? "mes" : "meses"}`;
  const anios = Math.floor(meses / 12);
  const resto = meses % 12;
  const parteAnios = `${anios} ${anios === 1 ? "año" : "años"}`;
  return resto === 0 ? parteAnios : `${parteAnios} y ${resto} ${resto === 1 ? "mes" : "meses"}`;
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
  const { avisar } = useToast();
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
  // Qué de lo que alimenta las tarjetas y «Tu mes» no se pudo traer. Vacío es
  // lo normal — ver lib/admin/lo-que-no-se-pudo.ts. Solo mira `jornadas`,
  // `horarios_asignados` y `turnos`: el resto de esta pantalla puede seguir
  // degradándose en silencio como hoy.
  const [noSePudo, setNoSePudo] = useState<string[]>([]);

  /**
   * QUÉ PESTAÑA ESTÁ ABIERTA.
   *
   * POR QUÉ HAY PESTAÑAS, QUE ES LA DECISIÓN DE FORMA DE ESTA PANTALLA
   *
   * Antes esto eran quince secciones apiladas en un solo scroll. Ordenarlas de
   * más a menos importante mejora las tres primeras y no arregla el fondo: la
   * doceava sigue estando a ocho arrastres del pulgar en un celular, que es
   * donde se abre esta pantalla. Un perfil de Workday, BambooHR o Gusto no
   * ordena un scroll infinito: corta el detalle en pestañas y deja fuera de
   * ellas lo que siempre importa.
   *
   * De ahí sale la regla de esta pantalla, y es la que hay que respetar al
   * agregarle algo mañana:
   *
   *   · ARRIBA, SIN PESTAÑA — quién eres, lo que te exige actuar hoy, y tus
   *     cuatro cifras. Se ve completo sin tocar nada.
   *   · DENTRO DE UNA PESTAÑA — solo lo que se viene a MIRAR.
   *
   * Una acción no se esconde nunca detrás de una pestaña. Si alguien no
   * encuentra dónde pedir sus vacaciones, el error es del diseño y no de la
   * persona: por eso «Pedir vacaciones» tiene su botón arriba, aunque el
   * formulario viva en su pestaña.
   */
  const [tab, setTab] = useState<Tab>("dias");

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
        .select("id, nombres, apellidos, fecha_ingreso, rol, foto_url, cargo, sedes!personas_sede_base_id_fkey(nombre)")
        .eq("auth_user_id", uid)
        .maybeSingle();

      if (!p) {
        setAviso("Tu cuenta todavía no está enlazada con tu ficha. Avisa a Desarrollo Organizacional.");
        return;
      }
      const nombre = `${p.nombres as string} ${p.apellidos as string}`;
      // Mismo criterio que /mio/contrato: el nombre que firma es el del DNI,
      // no el de uso diario — con reserva por si todavía no cargó su ficha.
      const { data: ficha } = await supabase
        .from("datos_personales").select("nombre_dni").eq("persona_id", p.id as string).maybeSingle();
      setYo({
        id: p.id as string,
        nombre,
        nombreOficial: (ficha?.nombre_dni as string | null) || nombre,
        nombres: p.nombres as string,
        apellidos: p.apellidos as string,
        fechaIngreso: (p.fecha_ingreso as string | null) ?? null,
        rol: (p.rol as string | null) ?? null,
        fotoUrl: (p.foto_url as string | null) ?? null,
        cargo: (p.cargo as string | null) ?? null,
        // PostgREST embebe la sede como objeto; si la fila no cargó, el perfil
        // se dibuja igual sin esa línea en vez de romperse.
        sede: ((p.sedes as { nombre: string } | null) ?? null)?.nombre ?? null,
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
      { data: js, error: errJornadas }, { data: perd }, { data: hs, error: errHs }, { data: ts, error: errTs },
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

    // Estas tres alimentan las tarjetas y la cuadrícula de «Tu mes». Si alguna
    // falla no se pintan números: un cero acá diría «no trabajaste», y sería
    // mentira — el mismo defecto que ya se corrigió en la Hoja de sede.
    setNoSePudo(
      loQueNoSePudo([
        { error: errJornadas, que: "tus días trabajados" },
        { error: errHs, que: "tu horario asignado" },
        { error: errTs, que: "tus turnos" },
      ]),
    );

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

  // Su contrato, si tiene uno. `contratos_lectura` (0272) ya deja a cada
  // persona leer sus propias filas de `contratos_generados` — no hace falta
  // una función nueva. El desempate copia el de `fn_contrato_firmado_vigente_de`
  // (0312): mismo criterio que ya usa el resto del sistema para decidir «cuál
  // es el vigente» entre varios contratos de la misma persona.
  const [contrato, setContrato] = useState<MiContrato | null>(null);
  const [contratoCargado, setContratoCargado] = useState(false);
  useEffect(() => {
    if (!yo?.id) return;
    let vivo = true;
    void supabase
      .from("contratos_generados")
      .select("tipo, fecha_inicio, fecha_fin, fecha_firma")
      .eq("persona_id", yo.id)
      .is("anulado_at", null)
      .order("generado_at", { ascending: false })
      .order("fecha_inicio", { ascending: false })
      .order("fecha_fin", { ascending: false })
      .order("id", { ascending: false })
      .limit(1)
      .maybeSingle()
      .then(({ data }) => {
        if (!vivo) return;
        setContrato((data as MiContrato | null) ?? null);
        setContratoCargado(true);
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

  /** Sube al detalle después de cambiar de pestaña: sin esto, tocar un aviso de
   *  arriba cambia una pestaña que está fuera de la vista y no pasa nada
   *  visible — que es como se aprende que los avisos no hacen nada. */
  function irArriba() {
    requestAnimationFrame(() => {
      document.getElementById("detalle")?.scrollIntoView({ behavior: "smooth", block: "start" });
    });
  }

  /** Desde un aviso de arriba hasta el día concreto del que habla. */
  function abrirDia(fecha: string) {
    setTab("dias");
    setDiaAbierto(fecha);
    setComentario("");
    setAvisoRevision(null);
    irArriba();
  }

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

  /**
   * Todo lo que hoy le pide algo a ella, en una sola lista y en un solo sitio.
   *
   * Antes esto vivía repartido en tres secciones a tres alturas distintas del
   * scroll —los días por revisar arriba, la respuesta de su encargada con
   * ellos, y el vencimiento de vacaciones diez secciones más abajo—, así que
   * «¿tengo algo pendiente?» no se contestaba mirando: se contestaba
   * arrastrando hasta el final. Juntarlas no es orden: es que la respuesta
   * quepa en la primera pantalla.
   */
  const pendientes = useMemo(() => {
    const out: { clave: string; texto: string; detalle?: string; ir?: () => void }[] = [];
    if (resumen.porRevisar.length > 0) {
      const n = resumen.porRevisar.length;
      out.push({
        clave: "revisar",
        texto: `${n} día${n === 1 ? "" : "s"} con el marcaje incompleto`,
        detalle: `${resumen.porRevisar.map((d) => diaYMes(d.fecha)).join(", ")}. Falta la salida o la puso el sistema, así que las horas de ese día no son las que trabajaste.`,
        ir: () => abrirDia(resumen.porRevisar[0].fecha),
      });
    }
    if (resumen.faltas.length > 0) {
      const n = resumen.faltas.length;
      out.push({
        clave: "faltas",
        texto: `${n} día${n === 1 ? "" : "s"} figuran sin marcaje`,
        detalle: `${resumen.faltas.map((d) => diaYMes(d.fecha)).join(", ")}. Si trabajaste o tenías permiso, se corrige con el motivo anotado.`,
        ir: () => abrirDia(resumen.faltas[0].fecha),
      });
    }
    if (respondidas.length > 0) {
      out.push({
        clave: "respondidas",
        texto: respondidas.length === 1
          ? "Te respondieron el día que pediste revisar"
          : `Te respondieron los ${respondidas.length} días que pediste revisar`,
        detalle: respondidas.map((r) => `${diaYMes(r.fecha)}: ${r.respuesta}`).join(" · "),
        ir: () => abrirDia(respondidas[0].fecha),
      });
    }
    // Un récord de vacaciones que vence deja de poder tomarse como descanso:
    // avisa solo cuando queda poco, para que el aviso siga significando algo.
    if (vacas && vacas.records_sin_gozar > 0 && vacas.vence_el && (vacas.dias_para_vencer ?? 999) <= 60) {
      out.push({
        clave: "vacaciones",
        texto: `Tus vacaciones más antiguas vencen el ${diaYMes(vacas.vence_el)}`,
        detalle: `Te quedan ${vacas.dias_pendientes} días sin tomar. Después de esa fecha esos días ya no se pueden tomar como descanso.`,
        ir: () => { setTab("ausencias"); irArriba(); },
      });
    }
    return out;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [resumen, respondidas, vacas]);

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
            <h1 className="font-serif text-3xl leading-none">Mi perfil</h1>
            <p className="etiqueta mt-2 text-taupe">Tus días y tus horas · CAYLA</p>
          </div>
        </div>
        <form onSubmit={entrar} className="flex w-full max-w-xs flex-col gap-3">
          <Campo type="email" placeholder="correo" value={email} onChange={(e) => setEmail(e.target.value)} required />
          <Campo type="password" placeholder="contraseña" value={clave} onChange={(e) => setClave(e.target.value)} required />
          {errorLogin && <p className="text-sm text-rojo">{errorLogin}</p>}
          <Boton type="submit" variante="primario" tamano="lg" cargando={entrando}>
            Entrar
          </Boton>
          <a href="/admin/olvide-clave" className="text-center text-sm text-taupe underline-offset-2 hover:underline">
            ¿Olvidaste tu clave?
          </a>
        </form>
      </main>
    );
  }

  return (
    <main className="mx-auto min-h-screen w-full max-w-3xl bg-crema px-5 py-8 text-tinta">
      {/* ══ 1 · QUIÉN ERES ══════════════════════════════════════════════════
          Lo primero de un perfil es la persona, y hasta hoy acá lo primero era
          una barrita de 14 píxeles con la foto encogida al lado del nombre.
          Un perfil de Workday, de BambooHR o de Gusto abre con la identidad
          completa —foto grande, nombre, puesto, sede, desde cuándo— porque es
          lo único de la pantalla que responde «¿esto es mío?», y esa pregunta
          se contesta antes que ninguna otra.

          La antigüedad va acá y no escondida: es lo que decide cuántos días de
          vacaciones le tocan, y hasta hoy solo la sabía quien abría su ficha
          en el panel — o sea, todo el mundo menos ella. */}
      <header className="mb-6 overflow-hidden rounded-2xl border border-sand bg-papel">
        <div className="flex flex-wrap items-start justify-between gap-4 p-5 sm:p-6">
          <div className="flex items-center gap-4">
            {yo ? (
              <FotoDePerfil supabase={supabase} yo={yo} subiendo={subiendoFoto} error={errorFoto} onSubir={subirMiFoto} />
            ) : (
              <Colibri tono="rojo" className="w-12" />
            )}
            <div className="min-w-0">
              <p className="etiqueta text-taupe">Mi perfil</p>
              <h1 className="mt-0.5 font-serif text-3xl leading-tight">{yo?.nombre ?? "Mi perfil"}</h1>
              {/* El CARGO, nunca el rol del sistema: «supervisor_sede» no es a
                  lo que se dedica nadie, y en pantalla siempre es «encargada». */}
              <p className="mt-1 text-sm text-taupe">
                {[yo?.cargo, yo?.sede].filter(Boolean).join(" · ") || "CAYLA"}
              </p>
              {yo?.fechaIngreso && (
                <p className="mt-0.5 text-xs text-taupe">
                  En CAYLA desde {mesYAnio(yo.fechaIngreso)} · {antiguedad(yo.fechaIngreso)}
                </p>
              )}
            </div>
          </div>

          {/* ── La salida ──────────────────────────────────────────────────
              Esta pantalla vive FUERA de `(admin)`, así que no hereda el menú:
              sin estos enlaces es un callejón sin salida. Quien tiene panel
              entró desde «Mi perfil» del menú y necesita volver; quien no lo
              tiene, no ve un enlace que le daría error.

              Y «Salir» manda a /admin/login en vez de dejar el formulario de
              esta misma pantalla: ese formulario vuelve siempre a /mio, así que
              cerrar sesión y entrar de nuevo devolvía aquí para siempre. El
              login del panel sí reparte por rol. */}
          <div className="flex items-center gap-3">
            {yo && ROLES_CON_PANEL.includes(yo.rol as never) && (
              <Link href="/admin/dashboard"
                className="rounded-lg border border-sand px-3 py-1.5 text-xs text-tinta transition-colors hover:bg-hueso">
                Volver al panel
              </Link>
            )}
            {yo && (
              <Link href="/mio/editar"
                className="rounded-lg border border-sand px-3 py-1.5 text-xs text-tinta transition-colors hover:bg-hueso">
                Editar datos
              </Link>
            )}
            <Boton variante="sutil" tamano="sm"
              onClick={() => void supabase.auth.signOut().then(() => router.replace("/admin/login"))}>
              Salir
            </Boton>
            <SelectorTema />
          </div>
        </div>
      </header>

      {/* ══ 2 · LO QUE TE PIDE ALGO HOY ═════════════════════════════════════
          Todo lo que exige que ella haga algo, junto y arriba. Si no hay nada,
          no se dibuja nada: un bloque vacío enseña a saltarse el bloque.

          ⚠ EL ACUSE VA PRIMERO Y ES LO PRIMERO. Este aviso llevaba desde que
          se escribió pintándose SOLO dentro de `AdminNav`, y el login manda a
          /mio a quien no tiene panel: o sea que la integrante —para quien se
          escribió— nunca lo veía. La Ley 30709 obliga a informar la política
          salarial y a PODER PROBARLO, y el reglamento interno igual. Un acuse
          que no le llega a su destinataria no prueba nada. */}
      <AcusesPendientes />

      <AnunciosWidget />

      {aviso && <div className="mb-6 rounded-2xl border border-ambar/30 bg-ambar/[0.06] p-4 text-sm">{aviso}</div>}

      {/* Si esto no se pudo traer, las tarjetas y «Tu mes» de abajo NO pintan
          números: un cero ahí no es la ausencia de un dato, es la afirmación de
          que no trabajaste ese día. Ver lib/admin/lo-que-no-se-pudo.ts. */}
      {noSePudo.length > 0 && (
        <div className="mb-6 rounded-2xl border border-rojo/30 bg-rojo/[0.06] p-4 text-sm">
          <div className="font-medium text-rojo">No se pudo traer tu mes completo</div>
          <p className="mt-1 text-tinta">
            No se pudo traer {noSePudo.join(", ")}. Vuelve a cargar la página; si sigue igual, avisa a
            Desarrollo Organizacional.
          </p>
        </div>
      )}

      {pendientes.length > 0 && (
        <section className="mb-6 rounded-2xl border border-ambar/40 bg-ambar/[0.07] p-5">
          <h2 className="mb-1 font-serif text-lg">Necesita que hagas algo</h2>
          <p className="mb-3 text-sm text-taupe">
            Un marcaje se arregla mientras el periodo sigue abierto; al final del mes ya no.
          </p>
          <ul className="space-y-3 text-sm">
            {pendientes.map((x) => (
              <li key={x.clave} className="border-t border-ambar/25 pt-3 first:border-t-0 first:pt-0">
                <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
                  <strong>{x.texto}</strong>
                  {x.ir && (
                    <button onClick={x.ir} className="shrink-0 text-xs text-tinta underline underline-offset-2">
                      Verlo →
                    </button>
                  )}
                </div>
                {x.detalle && <p className="mt-0.5 text-taupe">{x.detalle}</p>}
              </li>
            ))}
          </ul>
        </section>
      )}

      {/* ══ 3 · TUS CUATRO CIFRAS, Y LO QUE SE HACE CON ELLAS ═══════════════
          Las cuatro preguntas que traen a alguien a esta pantalla: cuándo me
          pagan, cuántas vacaciones tengo, cuándo me toca entrar y cómo voy con
          lo mío. Cada una con su acción al lado.

          Y las ACCIONES viven acá, fuera de las pestañas, a propósito: quien
          entra a pedir vacaciones no debería tener que adivinar detrás de qué
          pestaña están. La pestaña guarda lo que se viene a mirar; nunca lo
          que se viene a hacer. */}
      <div className="mb-6 grid gap-3 sm:grid-cols-2">
        {/* El periodo de pago. Sin montos: la boleta vive en su propia pantalla
            porque es un documento que se imprime, y el print de esta imprimiría
            las quince secciones de arriba con él. */}
        {periodo && estadoDelPeriodo ? (
          <TarjetaClave
            titulo="Tu periodo de pago"
            valor={estadoDelPeriodo.cierra > 0
              ? `Cierra en ${estadoDelPeriodo.cierra} día${estadoDelPeriodo.cierra === 1 ? "" : "s"}`
              : "Cierra hoy"}
            pie={`Del ${diaYMes(periodo.fecha_ini)} al ${diaYMes(periodo.fecha_fin)}. ${
              !estadoDelPeriodo.cubre
                ? "Estás mirando otro rango de fechas: toca «Periodo de pago» abajo para revisar el que se te va a pagar."
                : estadoDelPeriodo.pendientes > 0
                  ? `Tienes ${estadoDelPeriodo.pendientes} día${estadoDelPeriodo.pendientes === 1 ? "" : "s"} por revisar dentro de este periodo.`
                  : "Todos tus días de este periodo están completos."}`}
            alerta={estadoDelPeriodo.cubre && estadoDelPeriodo.pendientes > 0}
            accion={<Link href="/mio/boleta" className="text-tinta underline underline-offset-2 hover:text-rojo-profundo">Ver mi boleta →</Link>}
          />
        ) : (
          <TarjetaClave titulo="Tu periodo de pago" valor="—" pie="No hay un periodo de pago abierto para hoy." />
        )}

        {/* Nadie pide vacaciones que no sabe que tiene. */}
        {vacas && (
          <TarjetaClave
            titulo="Tus vacaciones"
            valor={`${vacas.dias_pendientes} días`}
            pie={vacas.vence_el
              ? `Sin tomar. El récord más antiguo vence el ${diaYMes(vacas.vence_el)}${
                  typeof vacas.dias_para_vencer === "number" && vacas.dias_para_vencer >= 0
                    ? ` — faltan ${vacas.dias_para_vencer} días.` : "."}`
              : "Días pendientes de tomar."}
            alerta={(vacas.dias_para_vencer ?? 999) <= 60 && vacas.records_sin_gozar > 0}
            accion={
              <button onClick={() => { setTab("ausencias"); irArriba(); }}
                className="text-tinta underline underline-offset-2 hover:text-rojo-profundo">
                Pedir vacaciones →
              </button>
            }
          />
        )}

        {/* «¿Cuándo me toca?» es la pregunta que más veces abre esta pantalla, y
            hasta hoy se respondía por WhatsApp. */}
        <TarjetaClave
          titulo="Tu próximo turno"
          valor={proximos.length > 0
            ? `${proximos[0].esperado.entrada}${proximos[0].esperado.salida ? `–${proximos[0].esperado.salida}` : ""}`
            : "—"}
          pie={proximos.length > 0
            ? `Te toca ${cuando(proximos[0].fecha)}.${feriados.length > 0 ? ` Próximo feriado: ${diaYMes(feriados[0].fecha)}, ${feriados[0].nombre}.` : ""}`
            : "No hay turnos ni horario cargados para los próximos días. Si eso no es lo que esperabas, avísale a tu encargada."}
          accion={
            <button onClick={() => { setTab("turnos"); irArriba(); }}
              className="text-tinta underline underline-offset-2 hover:text-rojo-profundo">
              Ver mis próximos días →
            </button>
          }
        />

        {/* Sin lenguaje de premio: desde la 0171 los objetivos NO pagan. */}
        <TarjetaClave
          titulo={`Tus objetivos de ${mesLabel}`}
          valor={objetivos.length > 0 ? `${objCumplidos} de ${objetivos.length}` : "—"}
          pie={objetivos.length > 0
            ? "Los marca tu encargada cuando los conversan."
            : `Todavía no tienes objetivos cargados para ${mesLabel}. Los acuerda contigo tu encargada.`}
          accion={objetivos.length > 0 ? (
            <button onClick={() => { setTab("objetivos"); irArriba(); }}
              className="text-tinta underline underline-offset-2 hover:text-rojo-profundo">
              Verlos →
            </button>
          ) : undefined}
        />
      </div>

      {/* ══ 4 · EL DETALLE ══════════════════════════════════════════════════
          Mismo patrón de pestañas que la ficha de una persona en el panel
          (admin/personas/[id]): que las dos pantallas con pestañas del sistema
          se vean iguales no es cosmético, es que quien aprendió una ya sabe
          usar la otra.

          Con 7 pestañas (antes 6, "Firma" es la que se agregó) ya no entran
          todas en una pantalla angosta, así que este `overflow-x-auto` pasa de
          decorativo a necesario — y ahí aparece la barra de scroll horizontal
          que se veía pesada bajo el texto. Sigue desplazándose igual con el
          dedo o el trackpad; solo se oculta la barra en sí, no la función.
          `scrollbar-width:none` cubre Firefox y el Chrome/Edge actuales;
          `::-webkit-scrollbar` es el remanente para Safari, que todavía no
          soporta la propiedad estándar (mismo motivo de las dos vías que ya
          explica el bloque de scrollbars globales en globals.css). */}
      <div
        id="detalle"
        className="mb-5 flex gap-1 overflow-x-auto border-b border-sand [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
      >
        <TabBtn valor="dias" activa={tab} onSel={setTab}>Mis días</TabBtn>
        <TabBtn valor="turnos" activa={tab} onSel={setTab}>Mis turnos</TabBtn>
        <TabBtn valor="ausencias" activa={tab} onSel={setTab}>Vacaciones y permisos</TabBtn>
        <TabBtn valor="contrato" activa={tab} onSel={setTab}>Contrato</TabBtn>
        <TabBtn valor="firma" activa={tab} onSel={setTab}>Firma</TabBtn>
        <TabBtn valor="objetivos" activa={tab} onSel={setTab}>Objetivos</TabBtn>
        <TabBtn valor="historial" activa={tab} onSel={setTab}>Historial</TabBtn>
      </div>

      {/* ── MIS DÍAS ─────────────────────────────────────────────────────── */}
      {tab === "dias" && (
        <>
          {/* El filtro. Abre en los últimos 30 días. El botón del periodo de pago
              está porque es el tramo con el que se le paga —del 29 al 28, leído
              de la base y nunca calculado— y es contra el que va a querer cuadrar
              su boleta. */}
          <section className="mb-5 flex flex-wrap items-end gap-3 rounded-2xl border border-sand px-4 py-3">
            <Campo etiqueta="Desde" type="date" value={desde} max={hasta} onChange={(e) => setDesde(e.target.value)} />
            <Campo etiqueta="Hasta" type="date" value={hasta} min={desde} max={hoyLima()} onChange={(e) => setHasta(e.target.value)} />
            <div className="flex flex-wrap gap-2">
              <Boton variante="secundario" tamano="sm" onClick={() => { setDesde(haceDias(30)); setHasta(hoyLima()); }}>
                Últimos 30 días
              </Boton>
              <Boton variante="secundario" tamano="sm" onClick={() => void irAlPeriodoDePago()}>
                Periodo de pago
              </Boton>
            </div>
          </section>

          {/* Cada número con su «de cuánto». Sin eso, «6h 54m de promedio» no dice
              si va bien o mal, y ella no tiene a quién preguntarle. Y si `jornadas`,
              `horarios_asignados` o `turnos` no se pudieron traer, no se pinta nada
              de esto: un cero acá diría «no trabajaste», y sería mentira. */}
          {noSePudo.length > 0 ? (
            <div className="mb-5 rounded-2xl border border-rojo/30 bg-rojo/[0.06] p-4 text-sm text-rojo">
              No se pudieron calcular tus días y horas de este rango — ver el aviso de arriba.
            </div>
          ) : (
            <div className="mb-5 grid grid-cols-2 gap-3 sm:grid-cols-4">
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
          )}

          {/* ── El mes de un vistazo ─────────────────────────────────────────
              Un cuadrito por día, con los MISMOS colores que ve su encargada. Que
              las dos vean el mismo día del mismo color es lo que les deja hablar
              de él sin traducirse la una a la otra. */}
          <section className="mb-5 rounded-2xl border border-sand p-5">
            <h2 className="mb-3 font-serif text-lg">Tu mes</h2>
            {cargando ? <p className="text-sm text-taupe">Cargando…</p>
              : noSePudo.length > 0 ? (
                <p className="text-sm text-rojo">
                  No se pudo traer tu mes — ver el aviso de arriba. Lo que se vería acá no es de fiar todavía.
                </p>
              )
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
                          <Boton variante="enlace" className="text-xs text-taupe" onClick={() => setDiaAbierto(null)}>cerrar</Boton>
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
                                <Boton variante="enlace" className="text-xs text-rojo" disabled={enviando}
                                  onClick={() => void quitarRevision(d.fecha)}>
                                  retirar
                                </Boton>
                              </div>
                            )}
                          </div>
                        ) : puedePedirRevision ? (
                          <div className="mt-3">
                            <label className="flex flex-col gap-1 text-xs text-taupe">
                              ¿Algo de este día no cuadra? Cuéntalo y le llega a tu encargada.
                              <AreaTexto value={comentario} onChange={(e) => setComentario(e.target.value)} rows={2}
                                placeholder="Ese día sí vine, marqué la entrada y la salida no me tomó." />
                            </label>
                            <Boton variante="primario" className="mt-2" cargando={enviando}
                              onClick={() => void pedirRevision(d.fecha)}>
                              Pedir que se revise
                            </Boton>
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

          {/* ── El desglose ──────────────────────────────────────────────────
              Solo los días con marcaje. Un día de descanso o un feriado no tienen
              por qué ocupar una fila vacía en una pantalla que se mira en el
              teléfono. */}
          <section className="rounded-2xl border border-sand p-5">
            <h2 className="mb-4 font-serif text-lg">Día por día</h2>
            {jornadas.length === 0 ? (
              <p className="text-sm text-taupe">No hay días marcados en este rango.</p>
            ) : (
              <Tabla>
                <TablaEncabezado>
                  <Th>Día</Th>
                  <Th>Entrada</Th>
                  <Th>Salida</Th>
                  <Th>Te tocaba</Th>
                  <Th>Tardanza</Th>
                  <Th className="text-right">Horas</Th>
                </TablaEncabezado>
                <tbody>
                  {[...dias].reverse().filter((d) => d.jornada !== null).map((d) => {
                    const j = d.jornada!;
                    const tarde = (j.minutos_tarde ?? 0) > 0;
                    const laPusoElSistema = j.estado === "auto_cerrada_pendiente";
                    return (
                      <Fila key={d.fecha}>
                        <td className="px-4 py-2">{diaYMes(d.fecha)}</td>
                        <td className="px-4 py-2">{hora(j.entrada_ts)}</td>
                        <td className="px-4 py-2">
                          {hora(j.salida_final_ts)}
                          {/* Esa hora NO la marcó ella: la inventó el auto-cierre porque
                              olvidó marcar. Es justo la que conviene que revise, así que
                              se dice en vez de dejarla pasar por buena. */}
                          {laPusoElSistema && (
                            <Insignia tamano="sm" variante="advertencia" className="ml-2">la puso el sistema</Insignia>
                          )}
                        </td>
                        {/* Contra qué se midió su tardanza ese día. Sin esto, un
                            número de minutos es una afirmación sin origen. */}
                        <td className="px-4 py-2 text-taupe">
                          {d.esperado.trabaja
                            ? <>{d.esperado.entrada}{d.esperado.salida ? `–${d.esperado.salida}` : ""}</>
                            : "—"}
                        </td>
                        <td className="px-4 py-2">
                          {!tarde ? <span className="text-taupe">—</span>
                            : d.perdonada ? <span className="text-taupe line-through">{j.minutos_tarde} min</span>
                            : <span className="text-ambar">{j.minutos_tarde} min</span>}
                        </td>
                        <td className="px-4 py-2 text-right">{comoReloj(j.horas_trabajadas ?? 0)}</td>
                      </Fila>
                    );
                  })}
                </tbody>
              </Tabla>
            )}
          </section>
        </>
      )}

      {/* ── MIS TURNOS ───────────────────────────────────────────────────── */}
      {tab === "turnos" && (
        <section className="rounded-2xl border border-sand p-5">
          <h2 className="mb-1 font-serif text-lg">Cuándo te toca</h2>
          <p className="mb-3 text-sm text-taupe">Tus próximos días de trabajo, de hoy en adelante.</p>
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
            <ul className="mt-4 space-y-1 border-t border-sand pt-3 text-sm">
              {feriados.map((f) => (
                <li key={f.fecha} className="text-taupe">
                  Feriado: <strong className="text-tinta">{diaYMes(f.fecha)}</strong>, {f.nombre}.
                </li>
              ))}
            </ul>
          )}
        </section>
      )}

      {/* ── VACACIONES Y PERMISOS ────────────────────────────────────────── */}
      {tab === "ausencias" && (
        <>
          {/* ── Pedir vacaciones ─────────────────────────────────────────────
              Solo si le aplican (`vacas` viene null cuando no aplica o no hay
              sesión resuelta todavía). No dice si el saldo alcanza para el rango
              elegido: eso lo decide `fn_solicitar_vacaciones` con el mismo cálculo
              que ya se le mostró arriba, y su respuesta es la que se ve abajo.

              Un récord que se cierra tiene un año para gozarse. Pasado ese año la
              empresa debe una indemnización (art. 23 del D. Leg. 713) y la persona
              se quedó sin su descanso — que es lo que de verdad importa acá. */}
          {vacas ? (
            <section className="mb-5 rounded-2xl border border-sand p-5 text-sm">
              <h2 className="mb-3 font-serif text-lg">Pedir vacaciones</h2>
              <p className="mb-3 text-taupe">
                Tienes <strong className="text-tinta">{vacas.dias_pendientes} días</strong> pendientes. Elige el rango y avisa —tu
                encargada no la aprueba, la aprueba Desarrollo Organizacional.
              </p>
              <form onSubmit={(e) => void pedirVacaciones(e)} className="flex flex-wrap items-end gap-3">
                <label className="flex flex-col gap-1 text-xs text-taupe">Desde
                  <input type="date" value={desdeSolicitud} min={hoyLima()} max={hastaSolicitud}
                    onChange={(e) => setDesdeSolicitud(e.target.value)}
                    className="rounded-lg border border-sand bg-hueso px-3 py-1.5 text-sm text-tinta" required />
                </label>
                <label className="flex flex-col gap-1 text-xs text-taupe">Hasta
                  <input type="date" value={hastaSolicitud} min={desdeSolicitud}
                    onChange={(e) => setHastaSolicitud(e.target.value)}
                    className="rounded-lg border border-sand bg-hueso px-3 py-1.5 text-sm text-tinta" required />
                </label>
                <label className="flex min-w-48 flex-1 flex-col gap-1 text-xs text-taupe">Comentario (opcional)
                  <input type="text" value={comentarioSolicitud} onChange={(e) => setComentarioSolicitud(e.target.value)}
                    placeholder="Lo que quieras que sepa Desarrollo Organizacional"
                    className="rounded-lg border border-sand bg-hueso px-3 py-1.5 text-sm text-tinta" />
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
                <ul className="mt-4 space-y-2 border-t border-sand pt-3 text-xs">
                  {solicitudesVacas.map((s) => (
                    <li key={s.id} className="flex flex-wrap items-center justify-between gap-2">
                      <span>
                        {diaYMes(s.fecha_inicio)}{s.fecha_fin !== s.fecha_inicio ? ` – ${diaYMes(s.fecha_fin)}` : ""}
                        {" · "}
                        <span className={
                          s.estado === "aprobada" ? "text-verde"
                          : s.estado === "rechazada" ? "text-rojo"
                          : s.estado === "cancelada" ? "text-taupe"
                          : "text-pizarra"
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
          ) : (
            <section className="mb-5 rounded-2xl border border-sand p-5 text-sm text-taupe">
              Todavía no te corresponden vacaciones. Se acumulan por año trabajado; si crees que ya te tocan,
              avísale a Desarrollo Organizacional.
            </section>
          )}

          {/* ── Sus ausencias ────────────────────────────────────────────────
              «El descanso médico que presenté, ¿quedó registrado?» es una pregunta
              que hoy se responde preguntando. Y el aviso del documento que falta la
              protege a ella: sin documento, ese permiso no cuenta igual. */}
          <section className="rounded-2xl border border-sand p-5">
            {/* Incluye las vacaciones: la vista `vacaciones` no es otra tabla,
                es un SELECT sobre `ausencias` con tipo='vacaciones'. Consultarla
                aparte traería las mismas filas dos veces. */}
            <h2 className="mb-3 font-serif text-lg">Tus permisos, descansos y vacaciones</h2>
            {ausencias.length === 0 ? (
              <p className="text-sm text-taupe">No tienes ausencias registradas en este rango de fechas.</p>
            ) : (
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
                      {noPaga(a.tipo) && <Insignia tamano="sm" atenuada>no remunerado</Insignia>}
                      {faltaDoc && <Insignia tamano="sm" variante="advertencia">falta el documento</Insignia>}
                    </li>
                  );
                })}
              </ul>
            )}
            <p className="mt-3 text-xs text-taupe">
              Si presentaste algo que no aparece acá, todavía se puede registrar — avísale a tu encargada.
              {hayCumpleanos && " Y recuerda que tienes permiso por tu cumpleaños: se pide, no se descuenta solo."}
            </p>
          </section>
        </>
      )}

      {/* ── CONTRATO ─────────────────────────────────────────────────────────
          Solo dice si tiene uno y lleva a verlo. El documento en sí —que se
          imprime— vive en /mio/contrato, mismo criterio que la boleta. */}
      {tab === "contrato" && (
        <section className="rounded-2xl border border-sand p-5 text-sm">
          <h2 className="mb-1 font-serif text-lg">Tu contrato</h2>
          {!contratoCargado ? (
            <p className="text-taupe">Cargando…</p>
          ) : !contrato ? (
            <p className="text-taupe">
              Todavía no tienes un contrato registrado en el sistema. Si crees que deberías tener uno, avisa
              a Desarrollo Organizacional.
            </p>
          ) : (
            <div>
              <p className="text-taupe">
                {!contrato.fecha_fin
                  ? `Desde el ${diaYMes(contrato.fecha_inicio)}, sin fecha de término.`
                  : `Del ${diaYMes(contrato.fecha_inicio)} al ${diaYMes(contrato.fecha_fin)}.`}{" "}
                {contrato.fecha_firma
                  ? `Firmado el ${diaYMes(contrato.fecha_firma)}.`
                  : "Pendiente de firma."}
              </p>
              <Link
                href="/mio/contrato"
                className="mt-3 inline-block text-tinta underline underline-offset-2 hover:text-rojo-profundo"
              >
                Ver mi contrato →
              </Link>
            </div>
          )}
        </section>
      )}

      {/* ── FIRMA ────────────────────────────────────────────────────────────
          Mismo componente que usa Felipe en su ficha de Equipo (FirmaEditor:
          subir imagen, dibujar o escribir con el nombre oficial bloqueado) —
          desde la 0398 cualquier persona puede generar y guardar la suya, no
          solo admin/líder. Antes esto solo aparecía dentro de /mio/contrato,
          y solo si ya había un contrato cargado: quien todavía no tenía uno
          no encontraba dónde configurarla. Acá se puede configurar con
          anticipación — en cuanto DO genere el contrato, la firma ya está
          lista sin que haga falta volver a hacer nada. */}
      {tab === "firma" && (
        <section className="rounded-2xl border border-sand p-5">
          <h2 className="mb-1 font-serif text-lg">Mi firma</h2>
          <p className="mb-3 text-sm text-taupe">
            Aparecerá en tu contrato de trabajo, en tu propio apartado. Si además firmas documentos por la
            empresa (memos, política salarial), es la misma firma la que se usa ahí.
          </p>
          {yo ? (
            <FirmaEditor supabase={supabase} nombreOficial={yo.nombreOficial} avisar={avisar} />
          ) : (
            <p className="text-sm text-taupe">Cargando…</p>
          )}
        </section>
      )}

      {/* ── OBJETIVOS ────────────────────────────────────────────────────────
          De solo lectura: marcarlos cumplidos es de su encargada, y esa es la
          razón por la que valen. Sin lenguaje de premio — desde la 0171 los
          objetivos NO pagan, así que nada de «plus» ni de verde de recompensa. */}
      {tab === "objetivos" && (
        <section className="rounded-2xl border border-sand p-5">
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
      )}

      {/* ── HISTORIAL ────────────────────────────────────────────────────────
          Las correcciones que alguien le aplicó a sus marcajes. Ya se pueden leer
          desde la 0003 (auditoria_select_propia); nadie lo mostraba. Sin esto,
          alguien corrige un marcaje suyo y ella no tiene cómo enterarse de qué
          cambió ni por qué — se entera si pregunta.

          Va en la ÚLTIMA pestaña y no arriba: es lo que ya pasó y está resuelto.
          Estaba de tercera sección de la pantalla, ocupándole media vista a algo
          que se consulta una vez al mes. */}
      {tab === "historial" && (
        <section className="rounded-2xl border border-sand p-5 text-sm">
          <h2 className="mb-1 font-serif text-lg">Correcciones a tus marcajes</h2>
          <p className="mb-3 text-taupe">
            Cuando alguien corrige uno de tus marcajes queda anotado acá, con el motivo. Son las 20 más recientes.
          </p>
          {correcciones.length === 0 ? (
            <p className="text-taupe">Nadie ha corregido ningún marcaje tuyo.</p>
          ) : (
            <ul className="space-y-3">
              {correcciones.map((c) => {
                const antes = limpiaErrorTecnico(c.campo_modificado, c.valor_anterior);
                const despues = c.campo_modificado === "marca_apartada"
                  ? RESOLUCION_APARTADA[c.valor_nuevo ?? ""] ?? c.valor_nuevo
                  : null;
                return (
                  <li key={c.id} className="border-t border-sand pt-3 first:border-t-0 first:pt-0">
                    <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-0.5">
                      <span className="font-medium">{etiquetaCampo(c.campo_modificado)}</span>
                      <span className="text-xs text-taupe">{fechaYHora(c.corregido_at)}</span>
                    </div>
                    <p className="text-taupe">
                      {despues !== null
                        ? <>{valorLegible(c.campo_modificado, antes)} · {despues}</>
                        : <>{valorLegible(c.campo_modificado, antes)} → {valorLegible(c.campo_modificado, c.valor_nuevo)}</>}
                      {c.marcajes && <> · marcaje del {diaYMes(fechaLimaDeMarca(c.marcajes.timestamp_marca))}</>}
                    </p>
                    <p className="mt-0.5 italic">«{c.motivo}»</p>
                  </li>
                );
              })}
            </ul>
          )}
        </section>
      )}

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
        className="h-20 w-20 overflow-hidden rounded-full border border-sand disabled:opacity-60"
      >
        {url ? (
          // eslint-disable-next-line @next/next/no-img-element -- foto de un bucket externo, no un asset local
          <img src={url} alt="" className="h-full w-full object-cover" />
        ) : (
          <span className="flex h-full w-full items-center justify-center bg-sand font-serif text-2xl text-taupe">
            {inicialesDe(yo.nombres, yo.apellidos)}
          </span>
        )}
      </button>
      <Boton
        variante="enlace"
        onClick={() => inputRef.current?.click()}
        disabled={subiendo}
        className="text-[11px] text-taupe"
      >
        {subiendo ? "Subiendo…" : "Cambiar foto"}
      </Boton>
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

/**
 * Una de las cuatro cifras de arriba, con su acción.
 *
 * `alerta` la pinta en ámbar, y se usa con cuidado: si las cuatro pueden
 * ponerse en ámbar a la vez, el ámbar deja de querer decir «mira esto». Hoy
 * solo lo hacen dos —el periodo con días por revisar y las vacaciones a punto
 * de vencer—, que son las dos que le pueden costar algo a ella.
 */
function TarjetaClave({
  titulo, valor, pie, accion, alerta = false,
}: {
  titulo: string;
  valor: string;
  pie?: string;
  accion?: React.ReactNode;
  alerta?: boolean;
}) {
  return (
    <div className={`flex flex-col rounded-2xl border p-4 ${
      alerta ? "border-ambar/40 bg-ambar/[0.07]" : "border-sand bg-papel"}`}>
      <div className="etiqueta text-taupe">{titulo}</div>
      <div className="mt-1 font-serif text-2xl leading-tight">{valor}</div>
      {pie && <p className="mt-1 flex-1 text-xs leading-relaxed text-taupe">{pie}</p>}
      {accion && <div className="mt-3 text-sm font-medium">{accion}</div>}
    </div>
  );
}

/**
 * Una pestaña del detalle. Mismo aspecto que las de la ficha de una persona en
 * el panel (`admin/personas/[id]`) a propósito: dos pantallas con pestañas que
 * se vean distintas obligan a aprenderlas dos veces.
 */
function TabBtn({
  valor, activa, onSel, children,
}: {
  valor: Tab;
  activa: Tab;
  onSel: (t: Tab) => void;
  children: React.ReactNode;
}) {
  return (
    <button
      onClick={() => onSel(valor)}
      aria-current={activa === valor ? "page" : undefined}
      className={`-mb-px shrink-0 border-b-2 px-3 py-2 text-sm transition-colors sm:px-4 ${
        activa === valor ? "border-rojo font-medium text-tinta" : "border-transparent text-taupe hover:text-tinta"}`}
    >
      {children}
    </button>
  );
}
