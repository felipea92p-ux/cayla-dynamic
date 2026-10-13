"use client";

import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Inbox } from "lucide-react";
import { ResumenEducacionMia } from "./educacion/resumen";
import { BoletasMias } from "./boletas/boletas-mias";
import { ReportesMios } from "./reportes/reportes-mios";
import { CambiosMios } from "./cambios-mios";
import { DisciplinaMia } from "./disciplina-mia";
import { SaludoCumpleanos } from "./saludo-cumpleanos";
import { cuantosPiden, porLeer, type CuentaMia, type DocMio } from "@/lib/mio-disciplina";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Colibri } from "@/components/marca";
import { AcusesPendientes } from "@/components/acuses-pendientes";
import { AnunciosWidget } from "@/components/anuncios-widget";
import { NovedadesWidget } from "@/components/novedades-widget";
import { SelectorTema } from "@/components/selector-tema";
import { MenuDetalle } from "@/components/nav/menu-detalle";
import { GRUPOS_MIO, TABS, type Tab } from "@/lib/mio-secciones";
import { Boton } from "@/components/ui/boton";
import { Insignia } from "@/components/ui/insignia";
import { Campo } from "@/components/ui/campo";
import { AreaTexto } from "@/components/ui/area-texto";
import { Tabla, TablaEncabezado, Th, Fila } from "@/components/ui/tabla";
import { Modal } from "@/components/ui/modal";
import { useToast } from "@/components/toast";
import { FirmaEditor } from "@/app/(admin)/admin/personas/[id]/FirmaEditor";
import { subirArchivoConProgreso } from "@/lib/subir-archivo";
import {
  BUCKET_FOTOS_PERFIL, comprimirFotoPerfil, inicialesDe, rutaNuevaFotoPerfil, urlPublicaFotoPerfil,
} from "@/lib/foto-perfil";
import {
  BUCKET_SOLICITUDES_PERFIL, CARAS_DNI, comprimirFotoDni, rutaNuevaCaraDni,
  urlFirmadaSolicitudPerfil, type CaraDni,
} from "@/lib/foto-dni";
import {
  EMPRESA, ROLES_CON_PANEL, TZ_LIMA, hoyLima, formatoMinutos,
  ESTADO_CIVIL_LABELS, GENERO_LABELS, GRADO_INSTRUCCION_LABELS, VINCULO_DERECHOHABIENTE_LABELS,
  TIPO_VINCULO_LABEL,
} from "@cayla-dynamic/shared";
import { MESES as MESES_LARGOS, type ObjetivoItem } from "@/lib/objetivos";
import {
  esperadoDelDia, horarioVigente, fechasDelRango, dowDe, estadoDelDia,
  type Esperado, type EstadoDia, type HorarioTramo, type TurnoDia,
} from "@/lib/admin/jornada-esperada";
import { loQueNoSePudo } from "@/lib/admin/lo-que-no-se-pudo";
import { cicloVigente, type DiaTrabajado } from "@/lib/admin/ciclo-sobretiempo";
import { traerBandeja } from "@/lib/bandeja-mia";
import { mostrarBonoEnInfo, puedePedirBono, traerMiBono, type MiBono } from "@/lib/mi-bono";
import { esMesDeCumpleanos } from "@/lib/saludos-cumpleanos";
import { esBoletaNueva } from "@/lib/boletas";
import { contarBoletasNuevas, nombreDelPeriodo, traerMisBoletas, type FilaMiBoleta } from "@/lib/mis-boletas";
import { contarSinLeer, traerMisReportes, type FilaMiReporte } from "@/lib/reportes";
import { formatSoles } from "@/lib/rangos";
import { direccionDeSeccion, seccionAlLlegar, seccionDeLaDireccion } from "@/lib/seccion-en-la-direccion";
import { useRecorridoGuiado, type PasoRecorrido } from "@/lib/use-recorrido-guiado";

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

/** Una propuesta suya de foto del DNI (0401). Solo lo que hace falta para
 *  contarle en qué va: el valor propuesto son rutas del almacén y no se
 *  muestran — se mira la imagen, no su ruta. */
interface SolicitudDni {
  estado: "pendiente" | "aprobado" | "rechazado" | "reemplazada";
  creada_at: string;
  resuelta_at: string | null;
  motivo: string | null;
}

/** Su ficha completa, de solo lectura — corregir un dato sigue yendo por
 *  Desarrollo Organizacional, no desde acá. Junta lo que ya vive repartido en
 *  `personas` (identidad y laboral) y en `datos_personales` (contacto, banco,
 *  salud): las dos filas de la misma persona, nunca mezcladas con la de nadie
 *  más — ver la cabecera del archivo sobre por qué se filtra siempre por
 *  `persona_id` explícito. */
interface MisDatos {
  documento: string | null;
  tipoVinculo: string;
  conHijos: boolean;
  email: string | null;
  funcion: string;
  fechaNacimiento: string | null;
  estadoCivil: string | null;
  genero: string | null;
  gradoInstruccion: string | null;
  celular: string | null;
  direccion: string | null;
  entidadBancaria: string | null;
  numeroCuenta: string | null;
  discapacidad: boolean | null;
  discapacidadConadis: string | null;
  emergenciaNombre: string | null;
  emergenciaTelefono: string | null;
  emergenciaVinculo: string | null;
}

/** Una fila de `derechohabientes` — a quién cubre su Seguro de Vida Ley y/o su
 *  EsSalud. La registra Desarrollo Organizacional; acá solo se ve. */
interface Derechohabiente {
  id: string;
  nombres: string;
  apellidos: string;
  vinculo: string;
  documento: string | null;
  fechaNacimiento: string | null;
  essalud: boolean;
  vidaLey: boolean;
}

// Las secciones de la pantalla —cuáles son, en qué grupo va cada una, con qué
// ícono y con qué palabras se buscan— viven en `lib/mio-secciones.ts`.

/**
 * Si «Lo mío» ya apareció alguna vez desde que se cargó este documento. Vive
 * fuera del componente a propósito: tiene que sobrevivir a que la pantalla se
 * desmonte al abrir un reporte y se vuelva a montar al volver «atrás», y
 * volver a `false` solo con una carga de página entera. Es lo que distingue
 * una recarga de un «atrás» que cae en la misma dirección (ver
 * `esRecargaDeEstaDireccion`).
 */
let mioYaAparecio = false;

/**
 * El recorrido de primera vez de «Resumen» — Fase 1 (ver CLAUDE.md). Solo esta
 * pestaña: las otras ocho quedan para cuando se sepa si el patrón funciona.
 *
 * En el mismo orden en que las tarjetas aparecen en pantalla. Tres de los
 * siete pasos (`mio-resumen-pago`, `-semana`, `-vacaciones`) apuntan a
 * tarjetas que no siempre existen —piden sus propios datos, o dependen de que
 * haya vacaciones pendientes—: `useRecorridoGuiado` los salta solos si no
 * aparecen a tiempo, no hace falta condicionarlos acá.
 *
 * Dos cosas decididas a propósito el 2026-09-12, después de verlo saltar del
 * paso 3 al 6 en una cuenta con menos de un mes (sin ciclo de semana cerrado
 * ni vacaciones que le apliquen todavía) — para que una sesión futura no lo
 * lea como un bug y lo "arregle":
 * - El contador "Paso X de Y" no se recalcula para ocultar el salto. Hacerlo
 *   bien exigiría esperar a que las tarjetas lentas carguen ANTES de arrancar
 *   el recorrido, retrasando el inicio para todo el mundo, no solo para quien
 *   tiene menos tarjetas. El salto es cosmético, no un error.
 * - "Tu semana" y "Tus vacaciones" no se sacan del recorrido ni se explican
 *   por adelantado con una tarjeta que no existe: no le sirven a quien
 *   todavía no las tiene, y explicarlas antes de tiempo confunde más de lo
 *   que ayuda. Si la persona no marca "no volver a mostrar", el recorrido se
 *   las muestra solo el día que le aparezcan de verdad.
 */
const PASOS_TOUR_RESUMEN: readonly PasoRecorrido[] = [
  { selector: '[data-tour="mio-resumen-header"]', titulo: "Tu información",
    texto: "Tu nombre, tu cargo y tu sede. Si algo está mal, corrígelo desde «Editar datos»." },
  { selector: '[data-tour="mio-resumen-periodo"]', titulo: "Tu periodo de pago",
    texto: "Cuándo cierra tu periodo actual y si te falta algún día por revisar." },
  { selector: '[data-tour="mio-resumen-pago"]', titulo: "Cómo va tu pago",
    texto: "Un estimado en vivo, con lo marcado hasta hoy. No es tu boleta final hasta que cierre el periodo." },
  { selector: '[data-tour="mio-resumen-semana"]', titulo: "Tu semana",
    texto: "Cuántas horas llevas trabajadas en tu semana actual." },
  { selector: '[data-tour="mio-resumen-vacaciones"]', titulo: "Tus vacaciones",
    texto: "Tus días pendientes, y si alguno está por vencer." },
  { selector: '[data-tour="mio-resumen-turno"]', titulo: "Tu próximo turno",
    texto: "Tu horario y el próximo feriado que le toca a tu sede." },
  { selector: '[data-tour="mio-resumen-objetivos"]', titulo: "Tus objetivos",
    texto: "Los conversa contigo tu líder de equipo. Aquí solo ves el avance." },
];

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
  // Desde la 0430, confirmar tu firma en /mio/contrato ya fija esta columna
  // (como Movilidad) — no hace falta mirar `firma_persona_confirmada_at`
  // aparte para saber si el contrato está firmado.
  fecha_firma: string | null;
}


const MESES = [
  "enero", "febrero", "marzo", "abril", "mayo", "junio",
  "julio", "agosto", "setiembre", "octubre", "noviembre", "diciembre",
];
const LETRA_DIA = ["D", "L", "M", "M", "J", "V", "S"];

/**
 * Lo que se acepta al mandar las fotos del DNI (Ley N.° 29733, 0404).
 *
 * Va aquí, palabra por palabra, y no en la base: es texto legal que se lee en
 * pantalla y se guarda tal cual en `consentimientos_datos_personales.texto` al
 * aceptarlo, para que cada constancia diga QUÉ aceptó esa persona ese día
 * aunque esta redacción cambie después. La razón social y el RUC salen de
 * `EMPRESA` —una sola respuesta a «cómo se identifica la empresa», ver
 * packages/shared/src/empresa.ts—, nunca escritos a mano acá.
 */
const TEXTO_CONSENTIMIENTO_DNI =
  `Declaro que el Documento Nacional de Identidad (DNI) que adjunto corresponde a mi persona y autorizo a ` +
  `${EMPRESA.nombre} (RUC ${EMPRESA.ruc}) a tratar este documento y mis demás datos personales con la finalidad ` +
  `de verificar mi identidad y dejar constancia de mi aceptación de los términos del contrato. Estos datos se ` +
  `incorporarán al banco de datos personales de ${EMPRESA.nombre}. Su entrega es necesaria para continuar el ` +
  `proceso; de no autorizarlo, no será posible continuar con la firma del contrato. Puedo ejercer mis derechos ` +
  `de acceso, rectificación, cancelación y oposición escribiendo a info@cayla.pe.`;

/** «2026-07-29» → «29 de julio». */
function diaYMes(iso: string): string {
  const [, m, d] = iso.split("-");
  return `${Number(d)} de ${MESES[Number(m) - 1]}`;
}

/** «2026-07-29» → «29 de julio de 2026». Para fechas donde el año sí importa
 *  (nacimiento, vigencia) — a diferencia de `diaYMes`, pensada para marcas del
 *  mismo periodo, donde repetir el año de hoy sería ruido. */
function diaMesYAnio(iso: string): string {
  const [a, m, d] = iso.split("-");
  return `${Number(d)} de ${MESES[Number(m) - 1]} de ${a}`;
}

/** Una etiqueta legible, o el valor crudo si no está en el catálogo — nunca
 *  «undefined» en pantalla por un valor que el catálogo todavía no conoce. */
function etiquetaDe(valor: string | null, mapa: Record<string, string>): string {
  if (!valor) return "— no registrado —";
  return mapa[valor] ?? valor;
}

/** 7.53 → «7h 32m». La gente cuenta en horas y minutos, no en decimales. */
function comoReloj(horas: number): string {
  const total = Math.round(horas * 60);
  return `${Math.floor(total / 60)}h ${String(total % 60).padStart(2, "0")}m`;
}

/** La hora de un marcaje, en Lima. Nunca `toLocaleTimeString` a secas: el huso
 *  del navegador no es el que decide a qué día pertenece una marca. */
function hora(iso: string | null): string {
  if (!iso) return "—";
  return new Intl.DateTimeFormat("es-PE", {
    timeZone: TZ_LIMA, hour: "2-digit", minute: "2-digit", hour12: true,
  }).format(new Date(iso));
}

/** El día de Lima (YYYY-MM-DD) al que pertenece un timestamp — nunca el UTC
 *  crudo, que puede caer un día antes o después cerca de medianoche. */
function fechaLimaDeMarca(iso: string): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: TZ_LIMA }).format(new Date(iso));
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

/**
 * ¿Este día es su jornada de HOY, todavía abierta?
 *
 * `estadoDelDia` la devuelve como "revisar" —marcó y el día no está cerrado—, y
 * para un día PASADO eso es exactamente lo que hay que decir: falta la salida,
 * así que las horas de ese día no son las que trabajó. Pero para HOY, con la
 * jornada `abierta` o `en_pausa`, no falta nada: está trabajando en este
 * momento. Llamarlo «marcaje incompleto» acusa de un problema a quien está
 * cumpliendo su turno, y encima de uno que no puede arreglar hasta salir.
 *
 * Se distingue ACÁ, en la pantalla, y NO en `estadoDelDia`: esa función la
 * comparten el panel y esta pantalla, y el color del día tiene que seguir
 * significando lo mismo para la integrante y para su encargada.
 *
 * El corte por fecha es lo que hace segura la excepción: una jornada que quedó
 * `abierta` de AYER sí es un marcaje roto —se fue sin marcar la salida— y
 * sigue avisando como siempre. Queda un borde conocido y a propósito: un turno
 * que cruza la medianoche (raro, pero existe — ver `lib/terminal/jornada-en-curso.ts`
 * y la migración 0240) cuelga de la fecha de AYER, así que entre las 00:00 y su
 * salida vuelve a leerse como incompleto. Cerrarlo pediría reconstruir acá la
 * ventana de horas del terminal, y esa regla ya vive en un solo sitio.
 */
function enJornadaAbierta(d: Dia, hoy: string): boolean {
  return d.fecha === hoy && (d.jornada?.estado === "abierta" || d.jornada?.estado === "en_pausa");
}

function explicaDia(d: Dia): string {
  const p: string[] = [diaYMes(d.fecha)];
  if (d.esperado.trabaja) p.push(`te tocaba ${d.esperado.entrada}${d.esperado.salida ? `–${d.esperado.salida}` : ""}`);
  else if (d.estado !== "sin_horario") p.push("descanso");
  if (d.jornada?.entrada_ts) p.push(`entraste ${hora(d.jornada.entrada_ts)}`);
  if (d.jornada?.horas_trabajadas != null) p.push(comoReloj(d.jornada.horas_trabajadas));
  if ((d.jornada?.minutos_tarde ?? 0) > 0) {
    p.push(d.perdonada ? "tardanza levantada" : `${formatoMinutos(d.jornada!.minutos_tarde!)} tarde`);
  }
  if (d.estado === "falta") p.push("no hay marcaje");
  if (d.estado === "revisar") {
    p.push(enJornadaAbierta(d, hoyLima()) ? "en jornada, todavía sin marcar la salida" : "marcaje incompleto");
  }
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

  // ── La foto del DNI (0401) ─────────────────────────────────────────────────
  //
  // Vive en su propia pestaña y no en /mio/editar, con el resto de los cambios
  // de ficha, porque no se parece a los demás campos: no es un valor que se
  // escribe, son dos imágenes que hay que VER antes y después. Por debajo es el
  // mismo mecanismo —una solicitud del campo `foto_dni` que DO resuelve desde
  // /admin/bandeja—, así que sigue habiendo una sola puerta.
  //
  // Tres cosas distintas que conviene no mezclar: lo que YA está aprobado en la
  // ficha (`dniVigente`, rutas), lo que se puede mostrar de eso ahora mismo
  // (`dniUrls`, firmadas y caducan) y lo que acaba de elegir en el navegador y
  // todavía no mandó (`dniElegido`).
  const [dniVigente, setDniVigente] = useState<Record<CaraDni, string | null>>({ anverso: null, reverso: null });
  const [dniUrls, setDniUrls] = useState<Record<CaraDni, string | null>>({ anverso: null, reverso: null });
  const [dniElegido, setDniElegido] = useState<Record<CaraDni, { archivo: File; vista: string } | null>>(
    { anverso: null, reverso: null });
  const [solicitudDni, setSolicitudDni] = useState<SolicitudDni | null>(null);
  const [enviandoDni, setEnviandoDni] = useState(false);
  /** La casilla de consentimiento (0404). Arranca desmarcada SIEMPRE y vuelve a
   *  desmarcarse tras cada envío: la ley pide el consentimiento en el momento
   *  de recolectar el dato, así que un envío nuevo es un acto nuevo — no lo
   *  cubre el de la vez anterior. */
  const [aceptoDatos, setAceptoDatos] = useState(false);
  /** ¿Existe ya el campo de la 0401 en el catálogo? Mientras esa migración no
   *  esté pegada no hay dónde guardar la solicitud, así que la pestaña no sale.
   *  Vale más que no esté a que esté y falle recién al enviar, con las dos fotos
   *  ya subidas — mismo criterio que `puedePedirRevision` con la 0257. */
  const [hayCampoDni, setHayCampoDni] = useState(false);
  /** La cara que se está mirando en grande, o null. Solo la vista, nunca la ruta. */
  const [dniAmpliado, setDniAmpliado] = useState<{ url: string; titulo: string } | null>(null);

  /** Las rutas aprobadas de su ficha, y en qué va su última propuesta. Con
   *  `persona_id` explícito, como todo lo de esta pantalla: la RLS es la red de
   *  abajo, nunca el mecanismo (ver la cabecera del archivo). */
  const cargarDni = useCallback(async () => {
    if (!yo?.id) { setDniVigente({ anverso: null, reverso: null }); setSolicitudDni(null); return; }
    const [ficha, solicitud, campo] = await Promise.all([
      supabase.from("datos_personales")
        .select("foto_dni_anverso_ruta, foto_dni_reverso_ruta")
        .eq("persona_id", yo.id).maybeSingle(),
      supabase.from("solicitudes_cambio_perfil")
        .select("estado, creada_at, resuelta_at, motivo")
        .eq("persona_id", yo.id).eq("campo", "foto_dni")
        .order("creada_at", { ascending: false }).limit(1).maybeSingle(),
      supabase.from("catalogo_campos_perfil").select("campo").eq("campo", "foto_dni").maybeSingle(),
    ]);
    setDniVigente({
      anverso: ficha.data?.foto_dni_anverso_ruta ?? null,
      reverso: ficha.data?.foto_dni_reverso_ruta ?? null,
    });
    setSolicitudDni((solicitud.data as SolicitudDni | null) ?? null);
    setHayCampoDni(campo.data !== null);
  }, [supabase, yo]);

  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void cargarDni(); }, [cargarDni]);

  const [misDatos, setMisDatos] = useState<MisDatos | null>(null);
  const [derechohabientes, setDerechohabientes] = useState<Derechohabiente[]>([]);

  /** Su ficha completa, de solo lectura. Con `persona_id`/`id` explícito, como
   *  todo lo de esta pantalla — la RLS (`personas_select_propia`,
   *  `dp_select_propia`, `dh_select_propia`) es la red de abajo, nunca el
   *  mecanismo (ver la cabecera del archivo). Nunca `select("*")`: aunque la
   *  RLS dejara leer la fila entera, `personas` lleva columnas que esta
   *  pantalla no tiene por qué pedir (`pin_hash` entre ellas). */
  const cargarMisDatos = useCallback(async () => {
    if (!yo?.id) { setMisDatos(null); setDerechohabientes([]); return; }
    const [persona, ficha, familia] = await Promise.all([
      supabase.from("personas")
        .select("documento, tipo_vinculo, con_hijos, email, funcion")
        .eq("id", yo.id).maybeSingle(),
      supabase.from("datos_personales")
        .select("fecha_nacimiento, estado_civil, genero, grado_instruccion, celular, direccion, entidad_bancaria, numero_cuenta, discapacidad, discapacidad_conadis, emergencia_nombre, emergencia_telefono, emergencia_vinculo")
        .eq("persona_id", yo.id).maybeSingle(),
      supabase.from("derechohabientes")
        .select("id, nombres, apellidos, vinculo, documento, fecha_nacimiento, essalud, vida_ley")
        .eq("persona_id", yo.id).order("created_at", { ascending: true }),
    ]);
    setMisDatos({
      documento: persona.data?.documento ?? null,
      tipoVinculo: persona.data?.tipo_vinculo ?? "",
      conHijos: persona.data?.con_hijos ?? false,
      email: persona.data?.email ?? null,
      funcion: persona.data?.funcion ?? "",
      fechaNacimiento: ficha.data?.fecha_nacimiento ?? null,
      estadoCivil: ficha.data?.estado_civil ?? null,
      genero: ficha.data?.genero ?? null,
      gradoInstruccion: ficha.data?.grado_instruccion ?? null,
      celular: ficha.data?.celular ?? null,
      direccion: ficha.data?.direccion ?? null,
      entidadBancaria: ficha.data?.entidad_bancaria ?? null,
      numeroCuenta: ficha.data?.numero_cuenta ?? null,
      discapacidad: ficha.data?.discapacidad ?? null,
      discapacidadConadis: ficha.data?.discapacidad_conadis ?? null,
      emergenciaNombre: ficha.data?.emergencia_nombre ?? null,
      emergenciaTelefono: ficha.data?.emergencia_telefono ?? null,
      emergenciaVinculo: ficha.data?.emergencia_vinculo ?? null,
    });
    setDerechohabientes(
      (familia.data ?? []).map((d) => ({
        id: d.id,
        nombres: d.nombres,
        apellidos: d.apellidos,
        vinculo: d.vinculo,
        documento: d.documento,
        fechaNacimiento: d.fecha_nacimiento,
        essalud: d.essalud,
        vidaLey: d.vida_ley,
      })),
    );
  }, [supabase, yo]);

  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void cargarMisDatos(); }, [cargarMisDatos]);

  /** El bucket es privado —un DNI no se sirve por URL pública, a diferencia del
   *  retrato del terminal—, así que para pintarlas hace falta firmarlas. Se
   *  piden cuando cambian las rutas, no en cada render: cada firma es una
   *  llamada de red y caduca a los cinco minutos. */
  useEffect(() => {
    let vivo = true;
    void (async () => {
      const [anverso, reverso] = await Promise.all([
        dniVigente.anverso ? urlFirmadaSolicitudPerfil(supabase, dniVigente.anverso) : Promise.resolve(null),
        dniVigente.reverso ? urlFirmadaSolicitudPerfil(supabase, dniVigente.reverso) : Promise.resolve(null),
      ]);
      if (vivo) setDniUrls({ anverso, reverso });
    })();
    return () => { vivo = false; };
  }, [supabase, dniVigente]);

  /** Elegir una cara. La vista previa es un object URL y el anterior se libera
   *  acá mismo: se crea FUERA del actualizador de estado a propósito, porque
   *  React puede invocarlo dos veces y quedaría una vista que nadie libera. */
  function elegirCaraDni(cara: CaraDni, archivo: File | null) {
    const anterior = dniElegido[cara];
    if (anterior) URL.revokeObjectURL(anterior.vista);
    const nuevo = archivo ? { archivo, vista: URL.createObjectURL(archivo) } : null;
    setDniElegido((prev) => ({ ...prev, [cara]: nuevo }));
  }

  /**
   * Manda las dos caras a revisión.
   *
   * Sube los archivos PRIMERO y crea la solicitud después: es el orden que
   * espera `fn_crear_solicitud_perfil`, que recibe rutas ya subidas y las valida
   * (todavía no existe un id de solicitud que meter en la ruta — ver la 0399).
   * Y las dos rutas van dos veces, como valor propuesto y como adjuntos: lo
   * segundo es lo que las hace visibles en /admin/bandeja para quien va a
   * aprobarlas, y la base lo exige (0401).
   */
  async function enviarDni(e: FormEvent) {
    e.preventDefault();
    if (!yo?.id) return;
    if (!dniElegido.anverso || !dniElegido.reverso) {
      avisar("error", "Faltan las dos caras: hay que subir el anverso y el reverso.");
      return;
    }
    if (!aceptoDatos) {
      avisar("error", "Falta marcar la autorización para tratar tus datos personales.");
      return;
    }
    setEnviandoDni(true);
    try {
      /** Sube una cara y devuelve su ruta, o null si falló (ya avisó por qué). */
      const subirCara = async (
        cara: (typeof CARAS_DNI)[number],
        elegido: { archivo: File; vista: string },
      ): Promise<string | null> => {
        // Comprimido a JPEG en el navegador: alivia la conexión de la tienda y,
        // sobre todo, convierte el HEIC del iPhone en un formato que el bucket
        // acepta — sin esto rebotaría con 415 y nadie sabría por qué.
        const comprimida = await comprimirFotoDni(elegido.archivo);
        const ruta = rutaNuevaCaraDni(yo.id, cara.clave);
        const aEnviar = new File([comprimida], `dni-${cara.clave}.jpg`, { type: "image/jpeg" });
        const fallo = await subirArchivoConProgreso(supabase, BUCKET_SOLICITUDES_PERFIL, ruta, aEnviar, () => {});
        if (fallo) {
          avisar("error", `No se pudo subir el ${cara.etiqueta.toLowerCase()}: ${fallo}`);
          return null;
        }
        return ruta;
      };

      // Una por una y con su ruta en una variable propia: si fueran un objeto
      // parcial, TypeScript dejaría mandar la solicitud con una ruta sin definir
      // y la base la rechazaría con «Falta el dato», que no explica nada.
      const [caraAnverso, caraReverso] = CARAS_DNI;
      const rutaAnverso = await subirCara(caraAnverso, dniElegido.anverso);
      if (rutaAnverso === null) return;
      const rutaReverso = await subirCara(caraReverso, dniElegido.reverso);
      if (rutaReverso === null) return;

      // La constancia ANTES de la solicitud, y no al revés: si algo falla en
      // medio, es preferible una constancia de una aceptación que no llegó a
      // mandar fotos —inofensiva: dice lo que dice, con su fecha— que unas
      // fotos recolectadas sin constancia de haberlo autorizado, que es
      // justamente lo que la Ley N.° 29733 no admite.
      const { error: eConsentimiento } = await supabase.rpc("fn_registrar_mi_consentimiento", {
        p_finalidad: "foto_dni",
        p_texto: TEXTO_CONSENTIMIENTO_DNI,
      });
      if (eConsentimiento) { avisar("error", eConsentimiento.message); return; }

      const { error } = await supabase.rpc("fn_crear_solicitud_perfil", {
        p_campo: "foto_dni",
        p_valor_propuesto: {
          foto_dni_anverso_ruta: rutaAnverso,
          foto_dni_reverso_ruta: rutaReverso,
        },
        p_rutas_adjuntas: [rutaAnverso, rutaReverso],
      });
      if (error) { avisar("error", error.message); return; }

      for (const cara of CARAS_DNI) {
        const elegido = dniElegido[cara.clave];
        if (elegido) URL.revokeObjectURL(elegido.vista);
      }
      setDniElegido({ anverso: null, reverso: null });
      setAceptoDatos(false);
      avisar("ok", "Enviado. Desarrollo Organizacional lo revisa y te avisamos.");
      await cargarDni();
    } catch {
      avisar("error", "Alguna de las imágenes no se pudo procesar. Prueba tomando la foto otra vez.");
    } finally {
      setEnviandoDni(false);
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
  /** Cuántos avisos le esperan en /mio/bandeja. Ver `cargarAvisosDeBandeja`. */
  const [avisosEnBandeja, setAvisosEnBandeja] = useState(0);
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
   *   · SIEMPRE A LA VISTA, FUERA DE TODA SECCIÓN — quién eres, cómo salir de
   *     aquí, y lo que te exige actuar hoy: los acuses de ley, los anuncios,
   *     «necesita que hagas algo» y tu jornada abierta. Nada de eso se
   *     esconde detrás de un renglón del menú, porque son cosas con fecha.
   *   · DENTRO DE UNA SECCIÓN — solo lo que se viene a MIRAR, y SOLO lo de
   *     esa sección. Elegir «Mis turnos» no debe dejar en pantalla cifras que
   *     hablan de otra cosa (2026-09-10).
   *
   * Las cuatro cifras —periodo de pago, vacaciones, próximo turno, objetivos—
   * viven por eso en «Resumen», que es la sección con la que ABRE la pantalla.
   * Las novedades del sistema también (2026-10-06): no piden nada, así que no
   * son «lo que te exige actuar hoy» y no tienen por qué seguirte.
   * Ese detalle es lo que sostiene la otra mitad de la regla: una acción no se
   * esconde nunca detrás de un renglón del menú, y «Pedir vacaciones» sigue
   * siendo de lo primero que se ve al entrar, sin tocar nada. Lo que cambió es
   * que ya no TE SIGUE a las otras ocho.
   *
   * Si algún día «Resumen» deja de ser la sección inicial, esa acción queda
   * escondida y hay que sacarla de ahí antes.
   */
  const [tab, mostrarSeccion] = useState<Tab>("resumen");

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

  // La sección vive en la dirección (`?tab=`), y de ahí salen tres cosas que
  // se pidieron el 2026-10-06 y tiran en direcciones opuestas: un enlace con
  // ?tab=<sección> —la Bandeja, «← Tus reportes»— abre esa sección; «atrás»
  // (en el teléfono, el gesto) devuelve a la sección en la que estabas; y
  // recargar abre SIEMPRE Resumen. La regla y sus dos trampas viven en
  // `lib/seccion-en-la-direccion.ts`, con sus pruebas.
  //
  // Recargar abre Resumen porque es lo único que esta pantalla esconde detrás
  // de una sección y no debe esconder: las novedades y «Pedir vacaciones» (ver
  // el comentario de `tab`). Antes la recarga volvía a la última sección
  // enlazada, y quien llegaba desde un aviso de la Bandeja no las veía más.
  useEffect(() => {
    void (() => {
      const carga = performance.getEntriesByType("navigation")[0] as PerformanceNavigationTiming | undefined;
      const { seccion, reemplazarPor } = seccionAlLlegar({
        direccion: window.location.href,
        carga: carga ? { tipo: carga.type, direccion: carga.name } : null,
        primeraVez: !mioYaAparecio,
      }, TABS, "resumen");
      mioYaAparecio = true;
      mostrarSeccion(seccion);
      // `null` y no `window.history.state`: Next.js solo se entera del cambio
      // de dirección si el estado que recibe NO trae ya el suyo.
      if (reemplazarPor) window.history.replaceState(null, "", reemplazarPor);
    })();
    // «Atrás» y «adelante» entre secciones no vuelven a montar la pantalla:
    // solo cambian la dirección. Hay que leerla de nuevo.
    const alMoverseEnElHistorial = () =>
      mostrarSeccion(seccionDeLaDireccion(window.location.href, TABS, "resumen"));
    window.addEventListener("popstate", alMoverseEnElHistorial);
    return () => window.removeEventListener("popstate", alMoverseEnElHistorial);
  }, []);

  /**
   * Toda forma de cambiar de sección pasa por aquí —el menú, los botones de
   * Resumen, los avisos de «necesita que hagas algo»—, y cada cambio es un paso
   * del «atrás». Por eso NO se llama a `mostrarSeccion` directo desde un botón:
   * la dirección dejaría de decir dónde estás y «atrás» te llevaría a otra parte.
   */
  function cambiarSeccion(valor: Tab) {
    mostrarSeccion(valor);
    const destino = direccionDeSeccion(window.location.href, valor, "resumen");
    if (destino !== window.location.href) window.history.pushState(null, "", destino);
  }

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

  // Su propia declaración de ruta (0423). Aparte del bloque grande por la
  // misma razón que `contrato`: depende solo de quién es. `p_solo_mi_fila =>
  // true` es obligatorio acá, no cosmético — sin él, como esta persona podría
  // ser admin o líder mirando SU PROPIA pantalla, `fn_documentos_tablero`
  // le devolvería la fila de cualquier compañera, no la suya (ver el
  // comentario CAMBIO 0423 en la migración).
  const [miMovilidad, setMiMovilidad] = useState<{
    estado: "sin_ruta" | "se_nego" | "ok"; ruta_firmada_el: string | null; ruta_desfasada: boolean;
    ruta_por_renovar?: "incompleta" | "vencida" | null;   // 0492
  } | null>(null);
  const [miMovilidadCargada, setMiMovilidadCargada] = useState(false);
  useEffect(() => {
    if (!yo?.id) return;
    let vivo = true;
    void supabase.rpc("fn_documentos_tablero", { p_solo_mi_fila: true }).then(({ data }) => {
      if (!vivo) return;
      type Fila = {
        estado: "sin_ruta" | "se_nego" | "ok"; ruta_firmada_el: string | null; ruta_desfasada: boolean;
        ruta_por_renovar?: "incompleta" | "vencida" | null;
      };
      setMiMovilidad(((data as Fila[] | null) ?? [])[0] ?? null);
      setMiMovilidadCargada(true);
    });
    return () => { vivo = false; };
  }, [supabase, yo?.id]);

  // Su bono de cumpleaños (0478). Aparte del bloque grande por la misma razón
  // que la ruta: depende solo de quién es. Qué le toca lo contesta la base
  // —la misma función que es la puerta del pedido—, así que el botón de acá
  // no puede ofrecer algo que el servidor después rechace.
  const [miBono, setMiBono] = useState<MiBono | null>(null);
  useEffect(() => {
    if (!yo?.id) return;
    let vivo = true;
    void traerMiBono(supabase).then(({ bono }) => { if (vivo) setMiBono(bono); });
    return () => { vivo = false; };
  }, [supabase, yo?.id]);

  // Sus boletas OFICIALES, las que entrega el contador (0482). Se traen acá y no
  // dentro de la pestaña porque el globito del menú y el aviso del Resumen tienen
  // que verse ANTES de que alguien abra «Boletas»; la pestaña pinta esta misma
  // lectura, así que el número y la lista no pueden discrepar. `fn_mis_boletas`
  // contesta solo por quien pregunta, incluso si es de DO.
  //
  // Si falla, NO se inventa un «0 nuevas»: el globito calla y la pestaña dice que
  // no pudo leerlas. Recargar tras abrir/confirmar corre por `onRecargar`.
  const [misBoletas, setMisBoletas] = useState<FilaMiBoleta[] | null>(null);
  const [misBoletasError, setMisBoletasError] = useState<string | null>(null);
  const cargarMisBoletas = useCallback(async () => {
    const r = await traerMisBoletas(supabase);
    if (r.error) { setMisBoletasError(r.error); return; }
    setMisBoletasError(null);
    setMisBoletas(r.filas);
  }, [supabase]);
  // La carga solo pone estado cuando la base contesta (después de un `await`),
  // no de forma síncrona; el linter no lo distingue. Mismo permiso que
  // `cargarAvisosDeBandeja`, más abajo.
  useEffect(() => {
    if (!yo?.id) return;
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void cargarMisBoletas();
  }, [cargarMisBoletas, yo?.id]);
  const boletasNuevas = useMemo(() => (misBoletas ? contarBoletasNuevas(misBoletas) : 0), [misBoletas]);

  // Sus reportes (0488): igual que las boletas, se leen aquí y no en la
  // pestaña, para que el globito del menú se vea antes de abrirla.
  const [misReportes, setMisReportes] = useState<FilaMiReporte[] | null>(null);
  const [misReportesError, setMisReportesError] = useState<string | null>(null);
  const cargarMisReportes = useCallback(async () => {
    const r = await traerMisReportes(supabase);
    if (r.error) { setMisReportesError(r.error); return; }
    setMisReportesError(null);
    setMisReportes(r.filas);
  }, [supabase]);
  useEffect(() => {
    if (!yo?.id) return;
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void cargarMisReportes();
  }, [cargarMisReportes, yo?.id]);
  const reportesSinLeer = useMemo(() => (misReportes ? contarSinLeer(misReportes) : 0), [misReportes]);

  // Su disciplina: lo entregado, lo enviado a su Info que todavía no recibió, y cómo va
  // este mes con sus tardanzas (0516, 0517). UNA sola lectura para la sección, el contador
  // del menú y las tarjetas del Resumen: escrita tres veces, un día el número y la lista
  // dirían distinto. La base filtra del lado del servidor —nunca un borrador ni uno firmado
  // y sin enviar—, que es justo lo que `exp_select_propia` por sí sola no evita (ver el
  // comentario de cabecera de este archivo).
  //
  // Las dos son tolerantes por separado: si «cómo vas» falla, la lista se ve igual; si falla
  // la lista, se dice, y no se pinta «no tienes nada» sobre algo que no se pudo mirar.
  const [miDisciplina, setMiDisciplina] = useState<DocMio[] | null>(null);
  const [miDisciplinaError, setMiDisciplinaError] = useState(false);
  const [miCuenta, setMiCuenta] = useState<CuentaMia | null>(null);
  const cargarMiDisciplina = useCallback(async () => {
    if (!yo?.id) { setMiDisciplina(null); setMiCuenta(null); return; }
    const [{ data, error }, { data: cuenta }] = await Promise.all([
      supabase.rpc("fn_mi_disciplina"),
      supabase.rpc("fn_mi_cuenta_de_tardanzas", {}),
    ]);
    setMiCuenta((cuenta as unknown as CuentaMia | null) ?? null);
    if (error) { setMiDisciplinaError(true); return; }
    setMiDisciplinaError(false);
    setMiDisciplina(((data as unknown as { documentos?: DocMio[] } | null)?.documentos) ?? []);
  }, [supabase, yo?.id]);
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void cargarMiDisciplina(); }, [cargarMiDisciplina]);

  // Lo que le pide algo: recibir lo enviado a su Info, o leer lo entregado en papel.
  const memosPorRecibir = useMemo(() => (miDisciplina ?? []).filter((d) => d.estado === "por_recibir"), [miDisciplina]);
  const memosPorLeer = useMemo(() => (miDisciplina ?? []).filter(porLeer), [miDisciplina]);
  const disciplinaPide = useMemo(() => cuantosPiden(miDisciplina ?? []), [miDisciplina]);

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

  // Cuántos avisos le esperan en la Bandeja: lo que le falta hacer (su contrato
  // sin firmar, un documento por firmar, una constancia de ley, sus días con el
  // marcaje incompleto) más lo que le respondieron estos días.
  //
  // Sale de `traerBandeja`, la MISMA función que arma la lista de /mio/bandeja,
  // aunque esta pantalla ya tenga a mano varias de las fuentes. Contar acá con
  // lo que ya está cargado sería más barato y crearía justo el defecto que la
  // Bandeja vino a evitar: dos sitios respondiendo «cuántos» por su cuenta,
  // listos para separarse el día que alguien cambie uno de los dos.
  //
  // Falla en silencio a propósito: si no se pudo contar, el botón sale sin
  // número. Un aviso rojo en la portada por un contador es ruido — la propia
  // Bandeja sí dice lo que no pudo traer, que es donde importa.
  const cargarAvisosDeBandeja = useCallback(async () => {
    if (!yo?.id) { setAvisosEnBandeja(0); return; }
    const { bandeja } = await traerBandeja(supabase, yo.id);
    setAvisosEnBandeja(bandeja.avisos);
  }, [supabase, yo]);

  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void cargarAvisosDeBandeja(); }, [cargarAvisosDeBandeja]);

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
    setAvisoRevision({ tipo: "ok", texto: "Listo. Tu líder de equipo lo va a ver." });
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

  // Las que pediste y todavía nadie contestó. Antes solo se veían reabriendo
  // cada día en «Mis días»; sin esta lista, pedir una revisión y olvidarte de
  // cuáles quedaron pendientes era el mismo callejón que la 0257 quiso evitar.
  const pendientesRevision = useMemo(
    () => [...revisiones.values()]
      .filter((r) => !r.atendida_at)
      .sort((a, b) => b.fecha.localeCompare(a.fecha)),
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

  /**
   * Cambiar de sección desde el menú lateral.
   *
   * Sube al detalle SOLO si el detalle ya quedó por encima de la pantalla.
   * Las dos mitades importan: estando arriba, elegir una sección no debe
   * empujar la vista hacia abajo —eso no pasaba con la tira de pestañas y no
   * hay razón para que empiece—; y estando abajo (o saliendo del cajón del
   * teléfono, que tapa la pantalla entera) quedarse donde estabas te deja a
   * media altura de una sección que ya no es la que estás mirando.
   */
  function elegirSeccion(valor: Tab) {
    cambiarSeccion(valor);
    requestAnimationFrame(() => {
      const el = document.getElementById("detalle");
      if (el && el.getBoundingClientRect().top < 0) {
        el.scrollIntoView({ behavior: "smooth", block: "start" });
      }
    });
  }

  // «Mi DNI» solo existe si la base tiene dónde guardarlo: mientras la
  // migración no esté pegada, esa sección no se ofrece (mismo criterio que ya
  // usaba la pestaña).
  //
  // «Boletas» lleva el globito con las publicadas que aún no abrió: sale de la
  // misma lectura que pinta la pestaña (`misBoletas`), no de una cuenta aparte.
  const grupos = useMemo(
    () => GRUPOS_MIO.map((g) => ({
      ...g,
      secciones: g.secciones
        .filter((s) => s.valor !== "dni" || hayCampoDni)
        .map((s) => (s.valor === "boletas" && boletasNuevas > 0 ? { ...s, contador: boletasNuevas } : s))
        .map((s) => (s.valor === "reportes" && reportesSinLeer > 0 ? { ...s, contador: reportesSinLeer } : s))
        .map((s) => (s.valor === "disciplina" && disciplinaPide > 0 ? { ...s, contador: disciplinaPide } : s)),
    })),
    [hayCampoDni, boletasNuevas, reportesSinLeer, disciplinaPide],
  );

  // Recorrido guiado de "Resumen", primera vez. `Boolean(yo)` y no solo `yo`:
  // el hook solo necesita saber SI ya hay una persona cargada, no memorizar el
  // objeto entero — comparado por referencia, `yo` cambia en cada refetch
  // aunque los datos sean los mismos, y reiniciaría el efecto sin motivo.
  useRecorridoGuiado("mio-resumen", PASOS_TOUR_RESUMEN, tab === "resumen" && Boolean(yo));

  /** Desde un aviso de arriba hasta el día concreto del que habla. */
  function abrirDia(fecha: string) {
    cambiarSeccion("dias");
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
      // Su jornada de hoy todavía abierta NO es un día por revisar: está
      // trabajando. Sale de la cuenta y se cuenta aparte (ver `enJornadaAbierta`).
      porRevisar: dias.filter((d) => d.estado === "revisar" && !enJornadaAbierta(d, hoy)),
      enJornadaAhora: dias.some((d) => enJornadaAbierta(d, hoy)),
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
    const hoy = hoyLima();
    const cierra = fechasDelRango(hoy, periodo.fecha_fin).length - 1;
    const mios = dias.filter((d) => d.fecha >= periodo.fecha_ini && d.fecha <= periodo.fecha_fin);
    // Misma exclusión que en `resumen`: su turno de hoy en curso no es un día
    // pendiente, y sin esto la tarjeta seguía diciendo «tienes 1 día por
    // revisar» —en alerta— justo debajo del aviso que se acaba de calmar.
    const pendientes = mios.filter(
      (d) => (d.estado === "revisar" && !enJornadaAbierta(d, hoy)) || d.estado === "falta",
    ).length;
    // `cubre` dice si el rango que está mirando abarca el periodo entero: si no,
    // el «todo completo» sería una afirmación sobre días que no se consultaron.
    const cubre = desde <= periodo.fecha_ini && hasta >= hoy;
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
    if (pendientesRevision.length > 0) {
      const n = pendientesRevision.length;
      out.push({
        clave: "revision-pendiente",
        texto: n === 1
          ? "Pediste que se revise un día y todavía no te responden"
          : `Pediste que se revisen ${n} días y todavía no te responden`,
        detalle: pendientesRevision.map((r) => `${diaYMes(r.fecha)}: «${r.comentario}»`).join(" · "),
        ir: () => abrirDia(pendientesRevision[0].fecha),
      });
    }
    // Un récord de vacaciones que vence deja de poder tomarse como descanso:
    // avisa solo cuando queda poco, para que el aviso siga significando algo.
    if (vacas && vacas.records_sin_gozar > 0 && vacas.vence_el && (vacas.dias_para_vencer ?? 999) <= 60) {
      out.push({
        clave: "vacaciones",
        texto: `Tus vacaciones más antiguas vencen el ${diaYMes(vacas.vence_el)}`,
        detalle: `Te quedan ${vacas.dias_pendientes} días sin tomar. Después de esa fecha esos días ya no se pueden tomar como descanso.`,
        ir: () => { cambiarSeccion("ausencias"); irArriba(); },
      });
    }
    // El bono de cumpleaños: solo cuando pedirlo es posible. Un «ya lo pediste»
    // no va en este recuadro — no le pide nada a ella; vive en su tarjeta.
    if (puedePedirBono(miBono)) {
      out.push({
        clave: "bono",
        texto: "Pide tu bono de cumpleaños",
        detalle: `${miBono?.monto != null ? `${formatSoles(miBono.monto)}. ` : ""}${
          miBono?.estado === "vencido"
            ? "Ya pasó tu cumpleaños y todavía no lo pides: aún estás a tiempo."
            : "Es el mes de tu cumpleaños: pídelo firmando tu constancia."}`,
        ir: () => router.push("/mio/cumpleanos"),
      });
    }
    // Genérica a propósito: ni el nivel ni el motivo de la sanción van acá.
    // Esta tarjeta puede verla de reojo cualquiera que pase cerca de la
    // pantalla — el detalle recién se ve al abrir el documento, en Disciplina.
    if (memosPorLeer.length > 0) {
      const n = memosPorLeer.length;
      out.push({
        clave: "memos",
        texto: `Tienes ${n} documento${n === 1 ? "" : "s"} por leer`,
        ir: () => { cambiarSeccion("disciplina"); irArriba(); },
      });
    }
    // Uno por documento, y no «tienes N»: cada uno se abre por su cuenta y lo
    // que se confirma es ESE documento. Genérico igual que el de arriba.
    for (const m of memosPorRecibir) {
      out.push({
        clave: `memo-recibir:${m.id}`,
        texto: "Tienes un documento por recibir",
        detalle: "Ábrelo, léelo y confirma que lo recibiste. Recibirlo no es aceptar lo que dice: puedes firmarlo o recibirlo sin firmar.",
        ir: () => router.push(`/mio/memo/${m.id}`),
      });
    }
    return out;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [resumen, respondidas, pendientesRevision, vacas, memosPorLeer, memosPorRecibir, miBono]);

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
            <h1 className="font-serif text-3xl leading-none">Info</h1>
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
    // El marco de esta pantalla, con la misma forma que el del panel
    // (`(admin)/layout.tsx`): el menú pegado al borde izquierdo y el contenido
    // ocupando el resto. En teléfono se apila, y ahí el menú es la barra
    // pegajosa de arriba que abre el cajón.
    <div className="flex min-h-screen flex-col bg-crema text-tinta md:flex-row">
      <MenuDetalle
        grupos={grupos}
        // Su propia memoria de grupos cerrados, no la del panel: los dos
        // menús tienen un «Pago» y una «Asistencia» con cosas distintas.
        memoriaGrupos="cayla-mio-grupos-cerrados"
        activo={tab}
        onSel={elegirSeccion}
        etiqueta="Secciones de tu perfil"
        // «Volver al panel» en la esquina de la barra de teléfono, y no solo
        // en la tarjeta de abajo: en 375px la tarjeta queda bajo el pliegue y
        // quien entró desde el panel se quedaba sin salida a la vista (se
        // probó con gente el 2026-09-11). En `rojo` relleno —el acento cálido
        // de la casa, no un color de Tailwind— para que sea lo primero que se
        // ve: crema sobre rojo da 4.83:1 en claro y 4.70:1 en oscuro, medido
        // como se pinta. El mismo enlace vive en la tarjeta para escritorio,
        // donde esta barra no existe.
        accion={yo && ROLES_CON_PANEL.includes(yo.rol as never) && (
          <Link
            href="/admin/dashboard"
            className="whitespace-nowrap rounded-control bg-rojo px-3 py-2 text-xs font-medium text-crema transition-colors duration-150 hover:bg-rojo-profundo active:scale-[0.97]"
          >
            Volver al panel
          </Link>
        )}
        // El tema estaba a la izquierda de «Volver al panel», en la barra. Desde
        // el 2026-10-06 va en la cabecera del cajón: se cambia una vez, y en la
        // barra le quitaba al nombre de la sección el espacio para quedar al
        // centro. En escritorio sigue en la tarjeta, como siempre.
        accionCajon={<SelectorTema />}
        // «Salir» vive al pie del menú —cajón en teléfono, columna en
        // escritorio— y no en la tarjeta: es donde el panel tiene «Cerrar
        // sesión». Manda a /admin/login en vez de dejar el formulario de esta
        // misma pantalla: ese formulario vuelve siempre a /mio, así que cerrar
        // sesión y entrar de nuevo devolvía aquí para siempre. El login del
        // panel sí reparte por rol.
        onSalir={() => void supabase.auth.signOut().then(() => router.replace("/admin/login"))}
        sesion={yo?.nombre}
      />

    {/* `w-full` no es adorno. En teléfono el marco es `flex-col`, y un hijo
        con `mx-auto` en una columna flex deja de estirarse al ancho del
        contenedor: pasa a medir «lo que su contenido necesite». Bastaba una
        sola cosa con ancho intrínseco grande —la tira de 30 días de «Mis
        días», la tabla «Día por día», el `input type="file"` del DNI— para
        que `main` entero, tarjeta incluida, se fuera a 764px en un viewport de
        375 y la pantalla se desplazara de lado (medido el 2026-09-11, visto
        en producción desde un teléfono). Con un ancho definido, lo ancho
        vuelve a desplazarse dentro de su propia caja (`overflow-x-auto`) y la
        página solo se mueve hacia abajo. En escritorio no cambia nada:
        `flex-1` fija la base en 0 y el ancho se reparte igual que antes. */}
    <main className="mx-auto w-full min-w-0 max-w-5xl flex-1 px-5 py-8">
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
      <header data-tour="mio-resumen-header" className="mb-6 overflow-hidden rounded-2xl border border-sand bg-papel">
        <div className="flex flex-wrap items-start justify-between gap-4 p-5 sm:p-6">
          <div className="flex items-center gap-4">
            {yo ? (
              <FotoDePerfil supabase={supabase} yo={yo} subiendo={subiendoFoto} error={errorFoto} onSubir={subirMiFoto} />
            ) : (
              <Colibri tono="rojo" className="w-12" />
            )}
            <div className="min-w-0">
              <p className="etiqueta text-taupe">Info</p>
              <h1 className="mt-0.5 font-serif text-3xl leading-tight">{yo?.nombre ?? "Info"}</h1>
              {/* El CARGO, nunca el rol del sistema: «supervisor_sede» no es a
                  lo que se dedica nadie, y en pantalla siempre es «líder de equipo». */}
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
              entró desde «Info» del menú y necesita volver; quien no lo
              tiene, no ve un enlace que le daría error.

              «Salir» ya no está acá: vive al pie del menú (ver `onSalir` de
              MenuDetalle, arriba), que es donde el panel tiene «Cerrar sesión».

              En teléfono quedan dos botones —Bandeja y Editar datos— en una
              GRILLA de dos columnas iguales, y no en una fila que envuelve:
              cada botón medía lo que medía su texto, así que al achicar o
              agrandar la ventana cambiaban de tamaño y de sitio (visto en la
              preview el 2026-09-11). Con la grilla miden siempre la mitad.
              De 640px para arriba vuelven a ser una fila, con «Volver al
              panel» y el tema, que en teléfono viven en la barra de arriba. */}
          <div className="grid w-full grid-cols-2 gap-2 sm:flex sm:w-auto sm:flex-wrap sm:items-center sm:gap-3">
            {/* Escondido hasta 768px: ahí ya está en la barra de arriba (ver
                `accion` de MenuDetalle), y dos veces el mismo botón en la
                misma pantalla es uno de más. Mismo rojo que allá, para que sea
                el mismo botón se mire donde se mire. */}
            {yo && ROLES_CON_PANEL.includes(yo.rol as never) && (
              <Link href="/admin/dashboard"
                className="hidden items-center justify-center whitespace-nowrap rounded-control bg-rojo px-3 py-2 text-sm font-medium text-crema transition-colors duration-150 hover:bg-rojo-profundo active:scale-[0.97] md:inline-flex">
                Volver al panel
              </Link>
            )}
            {/* La Bandeja va ANTES de «Editar datos» a propósito: es donde
                aterriza el resultado de lo que se pide ahí al lado. El número
                sale de la misma función que arma la lista (lib/bandeja-mia.ts),
                nunca de una cuenta propia de esta pantalla.
                Cuenta dos cosas distintas y por eso no se apaga igual: lo que
                le falta HACER sigue contando hasta que lo firme o lo arregle;
                lo que le RESPONDIERON caduca solo a los DIAS_NOVEDAD. */}
            {yo && (
              <Link href="/mio/bandeja"
                title={avisosEnBandeja > 0
                  ? `${avisosEnBandeja} cosa${avisosEnBandeja === 1 ? "" : "s"} en tu bandeja: lo que te falta hacer y lo que te respondieron`
                  : "Lo que te falta hacer y lo que respondieron a lo que pediste"}
                className="relative flex items-center justify-center gap-1.5 whitespace-nowrap rounded-control border border-sand px-3 py-2 text-sm text-tinta transition-colors hover:bg-hueso">
                {/* El mismo ícono que el panel usa para su Bandeja
                    (admin/nav-items.ts), no uno nuevo: es la misma idea en las
                    dos superficies, y quien tiene panel la reconoce sin leer. */}
                <Inbox size={16} strokeWidth={1.8} className="shrink-0" aria-hidden />
                Bandeja
                {avisosEnBandeja > 0 && (
                  <>
                    {/* El número montado en la esquina, con los tokens del
                        contador del panel (`bg-rojo` sobre `text-crema`): un
                        dígito sale círculo y dos salen píldora corta, sin
                        deformar el botón. Va `aria-hidden` porque un número
                        suelto no dice nada a quien no lo ve — el dato entero
                        viaja en el `sr-only` de abajo y en el `title`. */}
                    <span aria-hidden
                      className="absolute -right-1.5 -top-1.5 min-w-[1.125rem] rounded-pildora bg-rojo px-1 text-center text-[10px] font-medium leading-[1.125rem] text-crema">
                      {avisosEnBandeja}
                    </span>
                    <span className="sr-only">
                      {avisosEnBandeja} cosa{avisosEnBandeja === 1 ? "" : "s"} en tu bandeja
                    </span>
                  </>
                )}
              </Link>
            )}
            {yo && (
              <Link href="/mio/editar"
                className="flex items-center justify-center whitespace-nowrap rounded-control border border-sand px-3 py-2 text-sm text-tinta transition-colors hover:bg-hueso">
                Editar datos
              </Link>
            )}
            {/* El tema, solo de 768px para arriba: en teléfono está en la barra. */}
            <SelectorTema className="hidden md:inline-flex" />
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

      {/* El mes de su cumpleaños, del día 1 al último y en cualquier sección,
          para TODO el mundo — también para quien la base le contestaba
          `no_aplica` al bono, que es el caso que se quedaba en silencio
          (Daniel Ruiz, oct-2026). Arriba y no dentro de «Resumen»: ahí quedaba
          debajo de las novedades y de «Necesita que hagas algo», fuera de la
          primera vista. Solo el acuse va antes, por la razón escrita arriba. */}
      {yo && miBono && esMesDeCumpleanos(miBono, hoyLima()) && (
        <SaludoCumpleanos nombre={yo.nombres.split(" ")[0]} bono={miBono} hoy={hoyLima()} />
      )}

      <AnunciosWidget />

      {/* Lo que mejoró en el sistema. No pide nada: se entiende y desaparece.
          Por eso vive SOLO en «Resumen» (2026-10-06) y no arriba de todas las
          secciones como los acuses y los anuncios: no tiene fecha ni exige
          actuar, así que cae en la otra mitad de la regla de `tab` — quien
          elige «Mis turnos» pide ver sus turnos, no cuatro tarjetas sobre el
          terminal. Una pendiente sigue esperando en «Resumen», que es la
          sección con la que abre la pantalla. */}
      {tab === "resumen" && <NovedadesWidget />}

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

      {/* Su jornada de hoy sigue abierta. No es un pendiente —no hay nada roto
          que arreglar— así que va FUERA del recuadro ámbar «Necesita que hagas
          algo»: en `pizarra`, el tono informativo/«en proceso», con el mismo
          criterio que ya usa la banda de Equipo. Lo único que aporta es el
          recordatorio de marcar al salir, que es lo único que ella puede hacer. */}
      {resumen.enJornadaAhora && (
        <div className="mb-6 rounded-2xl border border-pizarra/40 bg-pizarra/[0.07] px-5 py-4 text-sm">
          Te encuentras en jornada laboral, no te olvides de marcar al salir.
        </div>
      )}

      {/* ══ 3 · RESUMEN — TUS CUATRO CIFRAS, Y LO QUE SE HACE CON ELLAS ═══
          Las cuatro preguntas que traen a alguien a esta pantalla: cuándo me
          pagan, cuántas vacaciones tengo, cuándo me toca entrar y cómo voy con
          lo mío. Cada una con su acción al lado.

          Hasta el 2026-09-10 se pintaban SIEMPRE, por encima de la sección que
          estuvieras mirando. Con el menú lateral eso dejó de tener sentido:
          quien elige «Mis turnos» pide ver sus turnos, y cuatro cifras que
          hablan de otra cosa compiten con lo que acaba de pedir.

          Ahora son su propia sección, «Resumen», Y ES LA SECCIÓN CON LA QUE LA
          PANTALLA ABRE. Eso no es un detalle de arranque: es lo que mantiene en
          pie la regla de que una acción no se esconde detrás de un renglón del
          menú. «Pedir vacaciones» y «Ver mi boleta» siguen viéndose al entrar,
          sin tocar nada — lo que cambió es que ya no siguen a quien se fue a
          mirar otra cosa. Ver el comentario de `tab`. */}
      {tab === "resumen" && (
        // `entra-seccion` a mano: las otras ocho entran animadas por vivir
        // DESPUÉS del ancla `#detalle` (regla de hermandad en globals.css), y
        // esta vive antes.
        <div className="entra-seccion mb-6 grid gap-3 sm:grid-cols-2">
          {/* Una boleta oficial publicada y sin abrir. Solo aparece mientras haya
              una: en cuanto se abre, `vista_at` queda escrito y esto se va. Lleva
              a «Boletas», no a `/mio/boleta` (esa es la boleta en vivo). */}
          {boletasNuevas > 0 && misBoletas && (
            <div className="flex flex-wrap items-center justify-between gap-x-4 gap-y-2 rounded-2xl border border-ambar/40 bg-ambar/[0.07] p-4 text-sm sm:col-span-2">
              <p className="text-tinta">
                {boletasNuevas === 1
                  ? `Tu boleta de ${nombreDelPeriodo(misBoletas.find(esBoletaNueva)!.fecha_fin, { minuscula: true })} ya está disponible.`
                  : `Tienes ${boletasNuevas} boletas nuevas.`}
              </p>
              <button onClick={() => elegirSeccion("boletas")}
                className="min-h-11 text-tinta underline underline-offset-2 hover:text-rojo-profundo">
                Ir a Boletas →
              </button>
            </div>
          )}
          {/* El periodo de pago. Sin montos: la boleta vive en su propia pantalla
              porque es un documento que se imprime, y el print de esta imprimiría
              las quince secciones de arriba con él. */}
          {periodo && estadoDelPeriodo ? (
            <TarjetaClave
              dataTour="mio-resumen-periodo"
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
            <TarjetaClave dataTour="mio-resumen-periodo" titulo="Tu periodo de pago" valor="—" pie="No hay un periodo de pago abierto para hoy." />
          )}

          {yo && <AdelantoDePago personaId={yo.id} />}
          {yo && <HorasDeLaSemana personaId={yo.id} />}

          {/* Nadie pide vacaciones que no sabe que tiene. */}
          {vacas && (
            <TarjetaClave
              dataTour="mio-resumen-vacaciones"
              titulo="Tus vacaciones"
              valor={`${vacas.dias_pendientes} días`}
              pie={vacas.vence_el
                ? `Sin tomar. El récord más antiguo vence el ${diaYMes(vacas.vence_el)}${
                    typeof vacas.dias_para_vencer === "number" && vacas.dias_para_vencer >= 0
                      ? ` — faltan ${vacas.dias_para_vencer} días.` : "."}`
                : "Días pendientes de tomar."}
              alerta={(vacas.dias_para_vencer ?? 999) <= 60 && vacas.records_sin_gozar > 0}
              accion={
                <button onClick={() => { cambiarSeccion("ausencias"); irArriba(); }}
                  className="text-tinta underline underline-offset-2 hover:text-rojo-profundo">
                  Pedir vacaciones →
                </button>
              }
            />
          )}

          {/* El bono de cumpleaños (0478). Solo aparece cuando hay algo que
              hacer o que esperar, y en su mes: ver `mostrarBonoEnInfo`. */}
          {miBono && mostrarBonoEnInfo(miBono, hoyLima()) && (
            <TarjetaClave
              titulo="Tu bono de cumpleaños"
              valor={miBono.estado === "pedido" ? "Pedido"
                : miBono.estado === "en_boleta" ? "En tu boleta"
                : miBono.estado === "entregado" ? (miBono.via === "boleta" ? "Pagado" : "Entregado")
                : miBono.monto != null ? formatSoles(miBono.monto) : "Te toca"}
              pie={miBono.estado === "pedido"
                ? `Lo pediste el ${diaYMes(miBono.pedido_el!)}. Desarrollo Organizacional te lo transfiere y aquí verás la fecha.`
                : miBono.estado === "en_boleta"
                  ? `Ya está en tu boleta${miBono.periodo_fin ? ` del periodo que cierra el ${diaYMes(miBono.periodo_fin)}` : ""} y se paga junto con tu planilla.`
                  : miBono.estado === "entregado"
                    // Por la boleta no hay «día en que se transfirió»: la
                    // planilla no lo guarda por persona, solo el periodo.
                    ? miBono.via === "boleta"
                      ? `Pagado con tu planilla${miBono.periodo_fin ? ` del periodo que cerró el ${diaYMes(miBono.periodo_fin)}` : ""}${
                          miBono.monto != null ? `: ${formatSoles(miBono.monto)}` : ""}. ¡Feliz cumpleaños!`
                      : `${miBono.pedido_el ? "Transferido" : "Recibido"} el ${miBono.entregado_el ? diaYMes(miBono.entregado_el) : "—"}${
                          miBono.monto != null ? `: ${formatSoles(miBono.monto)}` : ""}. ¡Feliz cumpleaños!`
                    : miBono.estado === "vencido"
                      ? "Ya pasó tu cumpleaños y todavía no lo pides: aún estás a tiempo."
                      : "Es el mes de tu cumpleaños. Pídelo firmando tu constancia."}
              alerta={puedePedirBono(miBono)}
              accion={
                <Link href="/mio/cumpleanos" className="text-tinta underline underline-offset-2 hover:text-rojo-profundo">
                  {puedePedirBono(miBono) ? "Pedir mi bono →" : "Ver mi constancia →"}
                </Link>
              }
            />
          )}

          {/* «¿Cuándo me toca?» es la pregunta que más veces abre esta pantalla, y
              hasta hoy se respondía por WhatsApp. */}
          <TarjetaClave
            dataTour="mio-resumen-turno"
            titulo="Tu próximo turno"
            valor={proximos.length > 0
              ? `${proximos[0].esperado.entrada}${proximos[0].esperado.salida ? `–${proximos[0].esperado.salida}` : ""}`
              : "—"}
            pie={proximos.length > 0
              ? `Te toca ${cuando(proximos[0].fecha)}.${feriados.length > 0 ? ` Próximo feriado: ${diaYMes(feriados[0].fecha)}, ${feriados[0].nombre}.` : ""}`
              : "No hay turnos ni horario cargados para los próximos días. Si eso no es lo que esperabas, avísale a tu líder de equipo."}
            accion={
              <button onClick={() => { cambiarSeccion("turnos"); irArriba(); }}
                className="text-tinta underline underline-offset-2 hover:text-rojo-profundo">
                Ver mis próximos días →
              </button>
            }
          />

          {/* Sin lenguaje de premio: desde la 0171 los objetivos NO pagan. */}
          <TarjetaClave
            dataTour="mio-resumen-objetivos"
            titulo={`Tus objetivos de ${mesLabel}`}
            valor={objetivos.length > 0 ? `${objCumplidos} de ${objetivos.length}` : "—"}
            pie={objetivos.length > 0
              ? "Los marca tu líder de equipo cuando los conversan."
              : `Todavía no tienes objetivos cargados para ${mesLabel}. Los acuerda contigo tu líder de equipo.`}
            accion={objetivos.length > 0 ? (
              <button onClick={() => { cambiarSeccion("objetivos"); irArriba(); }}
                className="text-tinta underline underline-offset-2 hover:text-rojo-profundo">
                Verlos →
              </button>
            ) : undefined}
          />
        </div>
      )}

      {/* ══ 4 · EL DETALLE ══════════════════════════════════════════════════
          Las ocho secciones que se MIRAN, gobernadas por el menú de la
          izquierda y no por una tira de pestañas. La novena, «Resumen», es la de
          arriba: se pinta igual que estas y con la misma condición.

          La tira estaba en `overflow-x-auto` con la barra de scroll escondida,
          así que en cualquier pantalla que no fuera ancha había secciones
          enteras —Contrato, Firma, Objetivos, Historial— fuera de la vista y
          sin nada que anunciara que estaban ahí. Es el mismo problema que el
          panel resolvió el 2026-09-07 cambiando su barra horizontal por un
          sidebar, y ya se había intentado arreglar con scroll horizontal
          (688e8e5) y revertido el mismo día (21591a7) por esconder ítems.

          Lo de arriba NO se movió, y esa sigue siendo la regla de la pantalla
          (ver el comentario de `tab`): quién eres, lo que te exige actuar hoy y
          tus cuatro cifras se ven completos sin tocar nada. El menú solo decide
          qué se MIRA aquí abajo.

          El ancla de abajo es un div vacío y no un contenedor de las ocho
          secciones: el menú vive en el marco, así que envolverlas no serviría
          para nada salvo correr 760 líneas de sangría — y hay una docena de
          ramas sin fusionar tocando este archivo. A esto suben `irArriba` y
          `elegirSeccion`, y de esto cuelga también la entrada animada de las
          secciones: `#detalle ~ *` en globals.css anima lo que se monte
          después del ancla, sin envolver nada. */}
      <div id="detalle" aria-hidden />

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
                                {formatoMinutos(d.jornada!.minutos_tarde!)}{d.perdonada && " · justificada"}
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
                              ¿Algo de este día no cuadra? Cuéntalo y le llega a tu líder de equipo.
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
                    Si tu líder de equipo justificó una tardanza, deja de contar acá.
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
              No hay turnos ni horario cargados para los próximos días. Si eso no es lo que esperabas, avísale a tu líder de equipo.
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

      {/* ── MI DNI (0401) ─────────────────────────────────────────────────────
          Dos caras, y ninguna entra a la ficha hasta que Desarrollo
          Organizacional la aprueba.

          Lo de arriba de cada recuadro es lo que ESTÁ GUARDADO; lo que se elige
          abajo es una propuesta. Que se distingan no es un detalle de forma: si
          al elegir una foto se reemplazara la de arriba, la pantalla estaría
          diciendo que ya quedó guardada —justo lo contrario de lo que esta
          pestaña promete—, y nadie entendería por qué su encargada sigue viendo
          la anterior. */}
      {tab === "dni" && hayCampoDni && (
        <section className="rounded-2xl border border-sand p-5">
          <h2 className="mb-1 font-serif text-lg">Tu DNI</h2>
          {/* Quién las ve NO es una frase de relleno: es una promesa sobre un
              documento de identidad, y tiene que decir la verdad. Decía «solo
              Administración — no tu encargada» hasta que la 0403 le dio a la
              encargada de sede permiso para ver y resolver las solicitudes de
              su equipo. Al componerse con esta pantalla, eso incluye el DNI.
              Si algún día se decide devolverlo a DO (ver la enmienda del ADR
              0001), esta frase cambia con ello — no antes. */}
          <p className="mb-4 text-sm text-taupe">
            Sube una foto de cada cara. Se revisan antes de que queden guardadas: hasta entonces
            tu ficha sigue con lo que ya tenía. Las ven Administración y tu líder de equipo;
            nadie más del equipo.
          </p>

          {solicitudDni?.estado === "pendiente" && (
            <p className="mb-4 rounded-xl border border-pizarra/30 bg-pizarra/10 px-3 py-2 text-sm text-pizarra">
              Ya mandaste tus fotos y están en revisión desde el {diaYMes(fechaLimaDeMarca(solicitudDni.creada_at))}.
              Si subes otras, reemplazan a esas.
            </p>
          )}
          {solicitudDni?.estado === "rechazado" && (
            <p className="mb-4 rounded-xl border border-rojo/30 bg-rojo/10 px-3 py-2 text-sm text-rojo">
              Tus últimas fotos no se aprobaron{solicitudDni.motivo ? `: «${solicitudDni.motivo}»` : ""}. Puedes volver a subirlas.
            </p>
          )}
          {solicitudDni?.estado === "aprobado" && solicitudDni.resuelta_at && (
            <p className="mb-4 text-xs text-verde">
              Aprobadas el {diaYMes(fechaLimaDeMarca(solicitudDni.resuelta_at))}.
            </p>
          )}

          <form onSubmit={(e) => void enviarDni(e)}>
            <div className="grid gap-3 sm:grid-cols-2">
              {CARAS_DNI.map((cara) => {
                const elegido = dniElegido[cara.clave];
                const urlGuardada = dniUrls[cara.clave];
                const hayGuardada = dniVigente[cara.clave] !== null;
                // La elegida manda sobre la guardada: es lo que está mirando
                // ahora. La etiqueta de abajo dice cuál de las dos es.
                const aMostrar = elegido?.vista ?? urlGuardada;
                return (
                  <div key={cara.clave} className="flex flex-col gap-2 rounded-xl border border-sand p-3">
                    <div>
                      <div className="text-sm font-medium">{cara.etiqueta}</div>
                      <div className="text-xs text-taupe">{cara.ayuda}</div>
                    </div>

                    {aMostrar ? (
                      // Un <button> y no un <div> con hover: en un teléfono el
                      // hover no existe, y esta pantalla se abre sobre todo ahí.
                      <button type="button"
                        onClick={() => setDniAmpliado({ url: aMostrar, titulo: `${cara.etiqueta} de tu DNI` })}
                        className="overflow-hidden rounded-lg border border-sand bg-hueso">
                        {/* eslint-disable-next-line @next/next/no-img-element -- imagen de un bucket privado, no un asset local */}
                        <img src={aMostrar} alt={`${cara.etiqueta} de tu DNI`}
                          className="h-40 w-full object-contain" />
                      </button>
                    ) : (
                      <div className="flex h-40 items-center justify-center rounded-lg border border-dashed border-sand bg-hueso px-3 text-center text-xs text-taupe">
                        {hayGuardada ? "Cargando…" : "Todavía no hay ninguna foto"}
                      </div>
                    )}

                    <p className="text-[11px] text-taupe">
                      {elegido ? "Foto nueva, todavía sin enviar."
                        : hayGuardada ? "Es la que está guardada en tu ficha."
                        : "Falta subirla."}
                    </p>

                    <label className="flex flex-col gap-1 text-xs text-taupe">
                      {elegido ? "Elegir otra" : "Elegir foto"}
                      {/* Solo imágenes: el PDF que el bucket acepta no se puede
                          comprimir en el navegador, y todo el mundo fotografía
                          su DNI con el celular. Sin `capture`, para que se pueda
                          elegir una que ya está en la galería. */}
                      <input type="file" accept="image/*" disabled={enviandoDni}
                        onChange={(e) => elegirCaraDni(cara.clave, e.target.files?.[0] ?? null)}
                        // `w-full min-w-0`: un input de archivo mide por defecto lo
                        // que mide su texto («Elegir archivo · Ningún archivo
                        // seleccionado», ~350px en Android en español), más que la
                        // tarjeta en un teléfono. Con ancho definido se recorta por
                        // dentro en vez de sacar la tarjeta de la pantalla.
                        className="w-full min-w-0 rounded-lg border border-sand bg-hueso px-3 py-1.5 text-sm text-tinta disabled:opacity-50" />
                    </label>
                  </div>
                );
              })}
            </div>

            {/* El consentimiento (0404) va AQUÍ, pegado a las fotos y antes del
                botón, y no dentro del contrato que se firma después: la Ley
                N.° 29733 lo pide en el momento de recolectar el dato. Lo que
                se lee acá es lo que se guarda como constancia, palabra por
                palabra — por eso el texto es una constante y no se arma en el
                JSX. */}
            <label className="mt-4 flex items-start gap-2 rounded-xl border border-sand bg-hueso p-3 text-xs leading-relaxed text-tinta">
              <input
                type="checkbox"
                checked={aceptoDatos}
                onChange={(e) => setAceptoDatos(e.target.checked)}
                disabled={enviandoDni}
                className="mt-0.5 shrink-0"
              />
              <span>
                {TEXTO_CONSENTIMIENTO_DNI}
                <span className="mt-1 block font-medium">Acepto y autorizo.</span>
              </span>
            </label>

            <div className="mt-4 flex flex-wrap items-center gap-3">
              <Boton type="submit" variante="primario" cargando={enviandoDni}
                disabled={!dniElegido.anverso || !dniElegido.reverso || !aceptoDatos}>
                Enviar para aprobación
              </Boton>
              {(!dniElegido.anverso || !dniElegido.reverso) && (
                <span className="text-xs text-taupe">Hacen falta las dos caras para poder enviar.</span>
              )}
              {dniElegido.anverso && dniElegido.reverso && !aceptoDatos && (
                <span className="text-xs text-taupe">Falta marcar la autorización para poder enviar.</span>
              )}
            </div>
          </form>

          {/* El mismo modal que el resto del sistema (components/ui/modal):
              un solo scrim y un solo z-index, y cierra con Escape. */}
          <Modal abierto={dniAmpliado !== null} onCerrar={() => setDniAmpliado(null)}
            titulo={dniAmpliado?.titulo} ancho="xl">
            {dniAmpliado && (
              // eslint-disable-next-line @next/next/no-img-element -- imagen de un bucket privado, no un asset local
              <img src={dniAmpliado.url} alt={dniAmpliado.titulo}
                className="mx-auto w-auto max-w-full rounded-lg" />
            )}
          </Modal>
        </section>
      )}

      {/* ── TUS DATOS ────────────────────────────────────────────────────────
          De solo lectura: corregir un dato sigue yendo por Desarrollo
          Organizacional, igual que en el panel. No hay ningún formulario acá
          a propósito — desde la 0399 la propia persona ya NO puede escribir
          su ficha directo (`fn_set_datos_personales` le quitó la rama
          `persona_id = fn_persona_actual_id()`): el camino de autoedición es
          `fn_crear_solicitud_perfil` + aprobación de DO, con su propia
          pantalla (docs/adr/0001-solicitudes-cambio-perfil-colaborador.md).
          Esta nota corrige la del PR #331, escrita antes de conocer la
          0399 — no se construye el formulario de propuesta acá sin que
          Felipe lo pida. */}
      {tab === "datos" && (
        <section className="rounded-2xl border border-sand p-5 text-sm">
          <h2 className="mb-1 font-serif text-lg">Tus datos</h2>
          <p className="mb-4 text-taupe">
            Lo que Desarrollo Organizacional tiene registrado de ti. Si algo está mal o falta, avísales — esta
            pantalla no tiene botón de editar.
          </p>
          {!misDatos ? (
            <p className="text-taupe">Cargando…</p>
          ) : (
            <div className="space-y-5">
              <div>
                <h3 className="mb-2 text-xs font-medium tracking-wide text-taupe uppercase">Identidad</h3>
                <dl className="grid gap-x-4 gap-y-2 sm:grid-cols-3">
                  <div><dt className="text-xs text-taupe">DNI</dt><dd>{misDatos.documento ?? "— no registrado —"}</dd></div>
                  <div>
                    <dt className="text-xs text-taupe">Fecha de nacimiento</dt>
                    <dd>{misDatos.fechaNacimiento ? diaMesYAnio(misDatos.fechaNacimiento) : "— no registrado —"}</dd>
                  </div>
                  <div><dt className="text-xs text-taupe">Género</dt><dd>{etiquetaDe(misDatos.genero, GENERO_LABELS)}</dd></div>
                  <div>
                    <dt className="text-xs text-taupe">Estado civil</dt>
                    <dd>{etiquetaDe(misDatos.estadoCivil, ESTADO_CIVIL_LABELS)}</dd>
                  </div>
                  <div>
                    <dt className="text-xs text-taupe">Grado de instrucción</dt>
                    <dd>{etiquetaDe(misDatos.gradoInstruccion, GRADO_INSTRUCCION_LABELS)}</dd>
                  </div>
                </dl>
              </div>

              <div>
                <h3 className="mb-2 text-xs font-medium tracking-wide text-taupe uppercase">Laboral</h3>
                <dl className="grid gap-x-4 gap-y-2 sm:grid-cols-3">
                  <div><dt className="text-xs text-taupe">Cargo</dt><dd>{yo?.cargo ?? "— no registrado —"}</dd></div>
                  <div><dt className="text-xs text-taupe">Sede</dt><dd>{yo?.sede ?? "— no registrado —"}</dd></div>
                  <div><dt className="text-xs text-taupe">Función</dt><dd>{misDatos.funcion || "— no registrado —"}</dd></div>
                  <div>
                    <dt className="text-xs text-taupe">Tipo de vínculo</dt>
                    <dd>{etiquetaDe(misDatos.tipoVinculo, TIPO_VINCULO_LABEL)}</dd>
                  </div>
                  <div>
                    <dt className="text-xs text-taupe">Fecha de ingreso</dt>
                    <dd>{yo?.fechaIngreso ? diaMesYAnio(yo.fechaIngreso) : "— no registrado —"}</dd>
                  </div>
                  <div><dt className="text-xs text-taupe">¿Con hijos?</dt><dd>{misDatos.conHijos ? "Sí" : "No"}</dd></div>
                </dl>
              </div>

              <div>
                <h3 className="mb-2 text-xs font-medium tracking-wide text-taupe uppercase">Contacto</h3>
                <dl className="grid gap-x-4 gap-y-2 sm:grid-cols-3">
                  <div><dt className="text-xs text-taupe">Celular</dt><dd>{misDatos.celular ?? "— no registrado —"}</dd></div>
                  <div><dt className="text-xs text-taupe">Correo</dt><dd>{misDatos.email ?? "— no registrado —"}</dd></div>
                  <div className="sm:col-span-3">
                    <dt className="text-xs text-taupe">Dirección</dt>
                    <dd>{misDatos.direccion ?? "— no registrado —"}</dd>
                  </div>
                </dl>
              </div>

              <div>
                <h3 className="mb-2 text-xs font-medium tracking-wide text-taupe uppercase">Banco</h3>
                <dl className="grid gap-x-4 gap-y-2 sm:grid-cols-3">
                  <div><dt className="text-xs text-taupe">Entidad</dt><dd>{misDatos.entidadBancaria ?? "— no registrado —"}</dd></div>
                  <div><dt className="text-xs text-taupe">Cuenta</dt><dd>{misDatos.numeroCuenta ?? "— no registrado —"}</dd></div>
                </dl>
              </div>

              <div>
                <h3 className="mb-2 text-xs font-medium tracking-wide text-taupe uppercase">Contacto de emergencia</h3>
                <dl className="grid gap-x-4 gap-y-2 sm:grid-cols-3">
                  <div><dt className="text-xs text-taupe">Nombre</dt><dd>{misDatos.emergenciaNombre ?? "— no registrado —"}</dd></div>
                  <div><dt className="text-xs text-taupe">Teléfono</dt><dd>{misDatos.emergenciaTelefono ?? "— no registrado —"}</dd></div>
                  <div><dt className="text-xs text-taupe">Vínculo</dt><dd>{misDatos.emergenciaVinculo ?? "— no registrado —"}</dd></div>
                </dl>
              </div>

              {/* Solo si hay algo que decir: silencio es distinto de «No». Es la
                  única diferencia con las secciones de arriba, porque acá SÍ hay
                  un motivo legítimo y frecuente para no marcarlo (no aplica). */}
              {misDatos.discapacidad !== null && (
                <div>
                  <h3 className="mb-2 text-xs font-medium tracking-wide text-taupe uppercase">Discapacidad</h3>
                  <dl className="grid gap-x-4 gap-y-2 sm:grid-cols-3">
                    <div><dt className="text-xs text-taupe">Registrada</dt><dd>{misDatos.discapacidad ? "Sí" : "No"}</dd></div>
                    {misDatos.discapacidad && (
                      <div>
                        <dt className="text-xs text-taupe">CONADIS</dt>
                        <dd>{misDatos.discapacidadConadis ?? "— no registrado —"}</dd>
                      </div>
                    )}
                  </dl>
                </div>
              )}

              <div>
                <h3 className="mb-2 text-xs font-medium tracking-wide text-taupe uppercase">
                  Familiares registrados (Seguro de Vida Ley / EsSalud)
                </h3>
                {derechohabientes.length === 0 ? (
                  <p className="text-xs text-taupe">Ninguno registrado.</p>
                ) : (
                  <ul className="space-y-1.5">
                    {derechohabientes.map((d) => (
                      <li key={d.id} className="rounded-lg border border-sand p-2 text-xs">
                        <span className="font-medium text-tinta">{d.nombres} {d.apellidos}</span>
                        {" — "}{etiquetaDe(d.vinculo, VINCULO_DERECHOHABIENTE_LABELS)}
                        {d.fechaNacimiento && ` · nacido el ${diaMesYAnio(d.fechaNacimiento)}`}
                        {" · "}
                        {[d.essalud && "EsSalud", d.vidaLey && "Vida Ley"].filter(Boolean).join(" y ") || "sin cobertura marcada"}
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            </div>
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
                líder de equipo no la aprueba, la aprueba Desarrollo Organizacional.
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
              Si presentaste algo que no aparece acá, todavía se puede registrar — avísale a tu líder de equipo.
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
              {/* CAMBIO (0430): antes esto decía «Pendiente de firma.» aunque
                  ya hubieras confirmado tu firma digital en /mio/contrato,
                  porque `fecha_firma` solo la ponía Desarrollo Organizacional
                  al registrar un escaneo físico. Desde la 0430 confirmar tu
                  firma ahí YA fija `fecha_firma` (como Movilidad), así que
                  este texto vuelve a ser el único que hace falta. */}
              <p className={contrato.fecha_firma ? "text-verde" : "text-taupe"}>
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

      {/* ── BOLETAS (0482) ───────────────────────────────────────────────────
          Las boletas oficiales del contador, por periodo pagado. NO es
          `/mio/boleta` (el cálculo del periodo en curso). El componente vive
          aparte, como Educación, y pinta la lectura de `fn_mis_boletas` que esta
          pantalla ya trajo para el globito del menú. */}
      {tab === "boletas" && (
        <BoletasMias filas={misBoletas} error={misBoletasError} onRecargar={cargarMisBoletas} />
      )}

      {tab === "reportes" && <ReportesMios filas={misReportes} error={misReportesError} />}

      {/* ── MOVILIDAD ────────────────────────────────────────────────────────
          Solo dice si le falta o si quedó desactualizada, y lleva a firmarla.
          El formulario en sí vive en /mio/movilidad, mismo criterio que el
          contrato de arriba. */}
      {tab === "movilidad" && (
        <section className="rounded-2xl border border-sand p-5 text-sm">
          <h2 className="mb-1 font-serif text-lg">Tu declaración de ruta</h2>
          {!miMovilidadCargada ? (
            <p className="text-taupe">Cargando…</p>
          ) : !miMovilidad ? (
            <p className="text-taupe">Esto no te corresponde por ahora.</p>
          ) : (
            <div>
              <p className={
                miMovilidad.estado === "ok" && !miMovilidad.ruta_desfasada
                  ? (miMovilidad.ruta_por_renovar ? "text-ambar" : "text-verde")
                  : "text-rojo"}>
                {miMovilidad.estado === "ok" && !miMovilidad.ruta_desfasada && miMovilidad.ruta_por_renovar === "incompleta"
                  ? `Firmada el ${diaYMes(miMovilidad.ruta_firmada_el!)}, con la versión corta. Toca renovarla.`
                  : miMovilidad.estado === "ok" && !miMovilidad.ruta_desfasada && miMovilidad.ruta_por_renovar === "vencida"
                  ? `Firmada el ${diaYMes(miMovilidad.ruta_firmada_el!)}: ya pasó un año. Toca renovarla.`
                  : miMovilidad.estado === "ok" && !miMovilidad.ruta_desfasada
                  ? `Firmada el ${diaYMes(miMovilidad.ruta_firmada_el!)}.`
                  : miMovilidad.estado === "ok"
                    ? "Firmada, pero con una tarifa que ya no es la vigente."
                    : miMovilidad.estado === "se_nego"
                      ? "Quedó registrado que no la firmaste."
                      : "Todavía te falta firmarla."}
              </p>
              <Link
                href="/mio/movilidad"
                className="mt-3 inline-block text-tinta underline underline-offset-2 hover:text-rojo-profundo"
              >
                Ir a mi declaración de ruta →
              </Link>
            </div>
          )}
        </section>
      )}

      {/* ── EDUCACIÓN (0450) ─────────────────────────────────────────────────
          Solo dice en qué está su constancia y lleva a subirla. El flujo en
          sí vive en /mio/educacion, mismo criterio que contrato y movilidad. */}
      {tab === "educacion" && <ResumenEducacionMia />}

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
              Todavía no tienes objetivos cargados para {mesLabel}. Los acuerda contigo tu líder de equipo.
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
                Los marca tu líder de equipo cuando los conversan. Si crees que alguno ya está, díselo.
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
          que se consulta una vez al mes.

          Desde el 2026-10-06 vive en `cambios-mios.tsx`: plegado, de a 10 por
          página y traducido con el mismo `describirCambio` del panel. Antes
          tenía su propio traductor, que no conocía el horario y lo pintaba
          como JSON crudo, y un tope de 20 que escondía la 21. */}
      {/* ── DISCIPLINA ───────────────────────────────────────────────────────
          Sus memos, el mensaje cuando no hay nada, la constancia de lectura y
          cómo va este mes (entrega 4, 2026-10-06). Antes los memos vivían al
          principio de «Historial», que no decía que ahí estaba la disciplina.
          Todo vive en `disciplina-mia.tsx` y recibe los datos hechos: el menú y
          el Resumen cuentan lo mismo que esta sección. */}
      {tab === "disciplina" && yo && (
        <DisciplinaMia
          supabase={supabase} personaId={yo.id}
          docs={miDisciplina} error={miDisciplinaError} cuenta={miCuenta}
          onCambio={() => void cargarMiDisciplina()}
        />
      )}

      {tab === "historial" && (
        <>
        {yo && <CambiosMios supabase={supabase} personaId={yo.id} />}

        {yo && <TusUltimosPeriodos personaId={yo.id} />}
        </>
      )}

      <p className="mt-6 text-xs text-taupe">
        Si algo no cuadra, no lo dejes pasar: avisa a tu líder de equipo y se corrige con el motivo anotado. Lo que
        ves sale de tus marcajes, y un marcaje mal registrado se arregla, no se discute al final del mes.
      </p>
    </main>
    </div>
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

/**
 * Cuántas horas lleva trabajadas en su semana (ciclo de 7 días) en curso.
 *
 * A PROPÓSITO no dice nada del tope de 48h ni usa la palabra «sobretiempo»:
 * la cabecera de este archivo documenta que la pantalla decidió (2026-08-31)
 * no mostrar el sobretiempo como horas por cobrar, porque invita a leerlo
 * como «me deben esto» antes de que se cruce el tope legal. Esta tarjeta es
 * un dato neutro — cuántas horas ya trabajó esta semana — y nada más.
 *
 * Fetch propio, independiente del filtro Desde/Hasta de «Mis días»: si
 * alguien lo angosta para mirar un mes viejo, este dato de "ahora mismo" no
 * debe romperse.
 */
function HorasDeLaSemana({ personaId }: { personaId: string }) {
  const [dias, setDias] = useState<DiaTrabajado[] | null>(null);

  useEffect(() => {
    let vivo = true;
    const supabase = createAdminSupabaseClient();
    const hoy = hoyLima();
    const [a, m, d] = hoy.split("-").map(Number);
    const desde = new Date(Date.UTC(a, m - 1, d - 9)).toISOString().slice(0, 10);
    void supabase
      .from("jornadas")
      .select("fecha, horas_trabajadas")
      .eq("persona_id", personaId)          // ← explícito, como todo lo de esta pantalla
      .gte("fecha", desde).lte("fecha", hoy)
      .then(({ data }) => {
        if (!vivo) return;
        setDias(
          ((data as { fecha: string; horas_trabajadas: number | null }[]) ?? [])
            .map((j) => ({ fecha: j.fecha, horas: j.horas_trabajadas ?? 0 }))
            .filter((j) => j.horas <= 24),   // un agregado histórico no es una jornada real
        );
      });
    return () => { vivo = false; };
  }, [personaId]);

  const ciclo = useMemo(() => (dias ? cicloVigente(dias, hoyLima()) : null), [dias]);
  if (!ciclo) return null;

  return (
    <TarjetaClave dataTour="mio-resumen-semana" titulo="Tu semana" valor={comoReloj(ciclo.horas)}
      pie={`Trabajadas desde el ${diaYMes(ciclo.desde)}.`} />
  );
}

/**
 * Un adelanto de «cómo va tu pago» del periodo actual, antes de entrar a la
 * boleta completa. MISMA REGLA que ya rige toda esta pantalla (ver cabecera
 * del archivo): SOLO el periodo actual, nunca uno cerrado —
 * `fn_planilla_calcular_persona` lo hace cumplir del lado del servidor.
 */
function AdelantoDePago({ personaId }: { personaId: string }) {
  const [fila, setFila] = useState<{ total: number; horas_mes: number; sin_datos?: boolean } | null>(null);

  useEffect(() => {
    let vivo = true;
    const supabase = createAdminSupabaseClient();
    void (async () => {
      const hoy = hoyLima();
      const { data: per } = await supabase
        .from("periodos_planilla")
        .select("id")
        .lte("fecha_ini", hoy).gte("fecha_fin", hoy)
        .maybeSingle();
      if (!vivo || !per) return;
      const { data: f } = await supabase.rpc("fn_planilla_calcular_persona", {
        p_persona_id: personaId,
        p_periodo_id: (per as { id: string }).id,
      });
      if (!vivo) return;
      setFila((f ?? null) as { total: number; horas_mes: number; sin_datos?: boolean } | null);
    })();
    return () => { vivo = false; };
  }, [personaId]);

  if (!fila || fila.sin_datos) return null;

  return (
    <TarjetaClave
      dataTour="mio-resumen-pago"
      titulo="Cómo va tu pago"
      valor={`S/ ${fila.total.toFixed(2)}`}
      pie={`Horas trabajadas: ${comoReloj(fila.horas_mes)}. En vivo, con lo marcado hasta hoy — todavía puede cambiar antes de que cierre el periodo.`}
      accion={<Link href="/mio/boleta" className="text-tinta underline underline-offset-2 hover:text-rojo-profundo">Ver el desglose completo →</Link>}
    />
  );
}

interface PeriodoTendencia {
  id: string;
  fecha_ini: string;
  fecha_fin: string;
  dias: number;           // largo del periodo — no son todos iguales (20 a 46 días)
  horas: number;
  diasTrabajados: number;
  tardanzas: number;
}

/**
 * Cómo vienen tus últimos periodos, uno al lado del otro.
 *
 * A PROPÓSITO no muestra ningún monto, ni siquiera del periodo actual (eso ya
 * lo hace `AdelantoDePago`): un periodo CERRADO puede tener su foto de pago
 * (`planilla_pagada_detalle`) desactualizada frente a errores de cálculo ya
 * corregidos en el código — mezclar esa foto con una comparación de
 * tendencia enseñaría un número que puede estar mal, sin ninguna de las
 * advertencias que sí tiene `/mio/boleta`. Horas y tardanzas no tienen ese
 * problema: salen de `jornadas`, la fuente de verdad siempre vigente.
 *
 * Cada fila muestra los días del periodo al lado de las horas — los periodos
 * no duran lo mismo (20 a 46 días, CHECK de la 0025), así que comparar solo
 * horas totales compararía peras con manzanas.
 */
function TusUltimosPeriodos({ personaId }: { personaId: string }) {
  const [periodos, setPeriodos] = useState<PeriodoTendencia[] | null>(null);

  useEffect(() => {
    let vivo = true;
    const supabase = createAdminSupabaseClient();
    void (async () => {
      const { data: pers } = await supabase
        .from("periodos_planilla")
        .select("id, fecha_ini, fecha_fin, estado")
        .order("fecha_fin", { ascending: false })
        .limit(6);
      if (!vivo || !pers || pers.length === 0) { setPeriodos([]); return; }

      const lista = pers as { id: string; fecha_ini: string; fecha_fin: string; estado: string }[];
      const cerrados = lista.filter((p) => p.estado === "pagado");
      const abiertos = lista.filter((p) => p.estado !== "pagado");

      // Dos grupos, no un array de tamaño variable: mezclar la respuesta de
      // Supabase (`{data, error}`) con la de la RPC por-abierto en un solo
      // `Promise.all` de longitud dinámica le quita a TypeScript la forma de
      // saber qué trae cada posición — con dos promesas fijas sí la sabe.
      const [{ data: fotos }, calculosAbiertos] = await Promise.all([
        cerrados.length > 0
          ? supabase.from("v_planilla_pagada")
              .select("periodo_id, horas_mes, dias_trabajados")
              .eq("persona_id", personaId)
              .in("periodo_id", cerrados.map((p) => p.id))
          : Promise.resolve({ data: [] as { periodo_id: string; horas_mes: number; dias_trabajados: number }[] }),
        Promise.all(
          abiertos.map((p) =>
            supabase.rpc("fn_planilla_calcular_persona", { p_persona_id: personaId, p_periodo_id: p.id })
              .then(({ data }) => ({ periodo_id: p.id, fila: data as { horas_mes?: number; dias_trabajados?: number } | null })),
          ),
        ),
      ]);
      if (!vivo) return;

      const horasPorPeriodo = new Map<string, { horas: number; dias: number }>();
      for (const f of (fotos as { periodo_id: string; horas_mes: number; dias_trabajados: number }[] | null) ?? []) {
        horasPorPeriodo.set(f.periodo_id, { horas: f.horas_mes, dias: f.dias_trabajados });
      }
      for (const c of calculosAbiertos) {
        horasPorPeriodo.set(c.periodo_id, { horas: c.fila?.horas_mes ?? 0, dias: c.fila?.dias_trabajados ?? 0 });
      }

      // Tardanzas: un solo fetch sobre el rango completo de los periodos
      // pedidos, en vez de uno por periodo.
      const desde = lista.reduce((m, p) => (p.fecha_ini < m ? p.fecha_ini : m), lista[0].fecha_ini);
      const hasta = lista.reduce((m, p) => (p.fecha_fin > m ? p.fecha_fin : m), lista[0].fecha_fin);
      const [{ data: js }, { data: perd }] = await Promise.all([
        supabase.from("jornadas").select("fecha, minutos_tarde")
          .eq("persona_id", personaId).gte("fecha", desde).lte("fecha", hasta),
        supabase.from("tardanzas_justificadas").select("fecha")
          .eq("persona_id", personaId).gte("fecha", desde).lte("fecha", hasta),
      ]);
      if (!vivo) return;
      const perdonadas = new Set(((perd as { fecha: string }[]) ?? []).map((t) => t.fecha));
      const tardes = ((js as { fecha: string; minutos_tarde: number | null }[]) ?? [])
        .filter((j) => (j.minutos_tarde ?? 0) > 0 && !perdonadas.has(j.fecha))
        .map((j) => j.fecha);

      setPeriodos(
        [...lista].reverse().map((p) => ({
          id: p.id,
          fecha_ini: p.fecha_ini,
          fecha_fin: p.fecha_fin,
          dias: fechasDelRango(p.fecha_ini, p.fecha_fin).length,
          horas: horasPorPeriodo.get(p.id)?.horas ?? 0,
          diasTrabajados: horasPorPeriodo.get(p.id)?.dias ?? 0,
          tardanzas: tardes.filter((f) => f >= p.fecha_ini && f <= p.fecha_fin).length,
        })),
      );
    })();
    return () => { vivo = false; };
  }, [personaId]);

  if (!periodos || periodos.length < 2) return null;   // una tendencia necesita al menos dos puntos

  return (
    <section className="mt-5 rounded-2xl border border-sand p-5 text-sm">
      <h2 className="mb-1 font-serif text-lg">Tus últimos periodos</h2>
      <p className="mb-3 text-taupe">
        Sin montos: un periodo ya cerrado puede tener su foto de pago desactualizada — para eso está tu boleta.
      </p>
      <Tabla>
        <TablaEncabezado>
          <Th>Periodo</Th>
          <Th>Días trabajados</Th>
          <Th>Horas</Th>
          <Th className="text-right">Tardanzas</Th>
        </TablaEncabezado>
        <tbody>
          {periodos.map((p) => (
            <Fila key={p.id}>
              <td className="px-4 py-2">{diaYMes(p.fecha_ini)} – {diaYMes(p.fecha_fin)}</td>
              <td className="px-4 py-2 text-taupe">{p.diasTrabajados} de {p.dias}</td>
              <td className="px-4 py-2">{comoReloj(p.horas)}</td>
              <td className="px-4 py-2 text-right">{p.tardanzas}</td>
            </Fila>
          ))}
        </tbody>
      </Tabla>
    </section>
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
  titulo, valor, pie, accion, alerta = false, dataTour,
}: {
  titulo: string;
  valor: string;
  pie?: string;
  accion?: React.ReactNode;
  alerta?: boolean;
  /** Ancla del recorrido guiado (ver use-recorrido-guiado.ts). Opcional: la
   *  inmensa mayoría de los usos de esta tarjeta no son parte de ningún tour. */
  dataTour?: string;
}) {
  return (
    <div data-tour={dataTour} className={`flex flex-col rounded-2xl border p-4 ${
      alerta ? "border-ambar/40 bg-ambar/[0.07]" : "border-sand bg-papel"}`}>
      <div className="etiqueta text-taupe">{titulo}</div>
      <div className="mt-1 font-serif text-2xl leading-tight">{valor}</div>
      {pie && <p className="mt-1 flex-1 text-xs leading-relaxed text-taupe">{pie}</p>}
      {accion && <div className="mt-3 text-sm font-medium">{accion}</div>}
    </div>
  );
}
