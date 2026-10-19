"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { Search, ChevronRight, ChevronLeft, Calendar, ArrowUpRight, PanelLeftClose, PanelLeftOpen } from "lucide-react";
import {
  CAMPOS_DE_MARCAJE, JORNADA_ESTADO_LABELS, MINUTOS_MAXIMOS_TARDANZA_MEDIBLE, ORIGEN_MARCA_LABELS,
  ROLES_DO, TEMA_AUDITORIA_LABELS, TIPOS_MARCA, TIPO_MARCA_LABELS, TZ_LIMA, anioLima, esCampoDeMarcaje, esRolEncargada,
  fechaLima, formatoMinutos, horaLima, hoyLima, leCorrespondeHorario, puedeOperarEquipo, rangoDelDiaLima, temaDeCampo,
  type TipoMarca,
} from "@cayla-dynamic/shared";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { esperadoDelDia, esTurnoEspejoViejo, type Esperado, type HorarioTramo, type TurnoDia } from "@/lib/admin/jornada-esperada";
import { describirCambio, horaTextoLima, type Auditoria } from "@/lib/admin/historial-correcciones";
import { loQueNoSePudo } from "@/lib/admin/lo-que-no-se-pudo";
import { horaDelHorario, tipoQueFalta } from "@/lib/admin/marcaje-faltante";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { useFiltroGuardado } from "@/lib/admin/use-filtro-guardado";
import { useToast } from "@/components/toast";
import { Boton } from "@/components/ui/boton";
import { AyudaPantalla } from "@/components/ui/ayuda-pantalla";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { Filtro } from "@/components/ui/filtro";
import { ParaAtender } from "@/components/ui/para-atender";
import { Rotulo } from "@/components/ui/rotulo";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { AreaTexto } from "@/components/ui/area-texto";
import { Insignia } from "@/components/ui/insignia";
import { Modal } from "@/components/ui/modal";
import { Tabla, TablaEncabezado, Th, Fila } from "@/components/ui/tabla";


// "HH:MM" en hora Lima para el input de tipo time
function horaInput(tsISO: string) {
  return new Intl.DateTimeFormat("en-GB", { timeZone: TZ_LIMA, hour: "2-digit", minute: "2-digit", hour12: false }).format(new Date(tsISO));
}
// fecha (YYYY-MM-DD) + "HH:MM" -> ISO con offset fijo de Perú (-05:00)
function construirTs(fecha: string, horaHHMM: string) {
  return `${fecha}T${horaHHMM}:00-05:00`;
}
// Sello de auditoría: cuándo se hizo el cambio (fecha corta + hora Lima).
//
// Con la misma regla del año que `diaTextoLima`, y por el mismo motivo: la fila
// enfrenta dos fechas —el día del marcaje corregido y el día en que alguien lo
// corrigió— y dejar el año en una sola vuelve ambigua justamente a la que dice
// cuándo se tocó la planilla.
function selloLima(iso: string): string {
  const d = new Date(iso);
  if (isNaN(d.getTime())) return iso;
  const formato: Intl.DateTimeFormatOptions = {
    timeZone: TZ_LIMA, day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit", hour12: true,
  };
  if (Number(fechaLima(d).slice(0, 4)) !== anioLima()) formato.year = "numeric";
  return new Intl.DateTimeFormat("es-PE", formato).format(d);
}

// CAMBIO · esta pantalla calculaba "qué le tocaba ese día" con su propia
// copia (`calcularEsperado`), y la copia tenía un bug real: la rama legacy
// devolvía la hora de entrada mirando solo `horario.hora_entrada`, sin
// comprobar `dias_laborables` — porque la consulta de abajo nunca pedía esa
// columna. A alguien con un horario del formato viejo se le podía medir
// tardanza un día que no le tocaba trabajar. Ahora se usa la misma función
// que ya usan /mio y /admin/horas (jornada-esperada.ts), que sí lo hace bien.
//
// Solo cambia CÓMO se calcula `entrada`/`trabaja`; el texto que ve la
// encargada es el mismo — este mapa reconstruye las frases que ya existían,
// porque `Esperado.origen` da un código corto ("turno"/"horario"/"legacy"),
// no la frase para pantalla.
function textoOrigen(e: Esperado): string {
  // Ojo con `sin_horario`: NO es un descanso. Un descanso dice "no le tocaba
  // trabajar"; `sin_horario` dice "no sabemos qué le tocaba, porque esa persona
  // no tiene horario cargado para esa fecha". `jornada-esperada.ts` las
  // distingue (devuelve un estado propio, línea 242) y esta pantalla las fundía
  // en "descanso (sin horario vigente)" — una frase que afirma lo que no sabe.
  // Se lee como normalidad, y lo que hay detrás es un día con horas marcadas
  // que nadie está midiendo. Por eso el caso tiene su propio texto abajo, y
  // aquí no se le pone "descanso" delante.
  const base = e.origen === "turno" ? "turno del día"
    : e.origen === "sin_horario" ? "sin horario vigente"
    : "horario base";
  if (e.origen === "sin_horario") return base;
  return e.trabaja ? base : `descanso (${base})`;
}

interface Persona {
  id: string; nombres: string; apellidos: string; rol: string; sede_base_id: string;
  // Para saber si a esta persona le CORRESPONDE llevar horario. Sin esto, el
  // aviso de "no tiene horario vigente" le salta a quien lo tiene así a
  // propósito — una locadora de servicios o el personal de dirección — y se
  // convierte en ruido diario por algo correcto. Espeja las exclusiones de
  // fn_personas_sin_horario_vigente (mig. 0385): la verdad se dice una vez.
  tipo_vinculo: string; personal_direccion: boolean;
  estado: string;
}
/** ¿A esta persona le toca tener horario? La regla vive en
 *  `leCorrespondeHorario` (packages/shared/vinculo.ts), compartida con
 *  Horarios base. */
function leTocaHorario(p: Persona | undefined): boolean {
  if (!p) return true;
  return leCorrespondeHorario(p.tipo_vinculo, p.personal_direccion);
}
interface Sede { id: string; nombre: string }
/** Cuántos días por revisar se piden. Si llegan tantos, puede haber más atrás. */
const LIMITE_DIAS_POR_REVISAR = 50;
interface Marcaje {
  id: string; tipo: TipoMarca; motivo_otro: string | null; timestamp_marca: string;
  origen: string; estado_revision: string;
  // Anulada (mig. 0081): la marca sigue aquí, tachada, pero no cuenta para la jornada.
  anulada_at: string | null; anulada_por: string | null; anulada_motivo: string | null;
}

// A qué familia pertenece cada tipo. Espeja fn_familia_marca (mig. 0081): una
// salida solo puede pasar a ser otra salida, y un retorno a otro retorno. Nunca
// una entrada en salida — dejaría el día con dos salidas y sin entrada.
function familiaDe(tipo: TipoMarca): "entrada" | "salida" | "retorno" {
  if (tipo === "entrada") return "entrada";
  return tipo.startsWith("retorno") ? "retorno" : "salida";
}
const TIPOS_DE_LA_FAMILIA = (tipo: TipoMarca): TipoMarca[] =>
  (Object.keys(TIPO_MARCA_LABELS) as TipoMarca[]).filter((t) => familiaDe(t) === familiaDe(tipo));
/** Un día con marcas sin revisar. `motivo` (mig. 0384) dice POR QUÉ está en la
 *  lista, porque `estado_revision = 'pendiente_revision'` la escriben tres cosas
 *  distintas y hasta la 0384 esta pantalla las anunciaba todas como si fueran la
 *  primera — un día con el auto-cierre sin confirmar salía titulado "secuencia
 *  imposible" aunque su secuencia fuera perfectamente posible. */
type MotivoRevision = "secuencia_imposible" | "auto_cierre_sin_confirmar" | "sello_sin_levantar";
interface DiaPorRevisar {
  persona_id: string; nombre: string; sede: string; fecha: string; marcas: number;
  periodo_pagado: boolean;
  // Puede llegar null si la base todavía no tiene la 0384: se trata como el caso
  // grave, que es el que no se puede dejar de avisar.
  motivo: MotivoRevision | null;
}

/** Una marca que la persona hizo y el terminal no pudo enviar. No es un marcaje:
 *  lo será si alguien la repone desde acá, con su hora original. */
interface MarcaApartada {
  id: string;
  client_uuid: string;
  persona_id: string;
  persona: string;
  sede: string;
  tipo: string;
  timestamp_cliente: string;
  fecha: string;
  ultimo_error: string | null;
  reportada_at: string;
}
interface HorarioAplicado {
  fuente: "turnos" | "horarios_asignados"; horario_id: string | null;
  entrada: string | null; salida: string | null; refrigerio_min: number; es_descanso: boolean;
}
interface Jornada {
  estado: string; horas_trabajadas: number | null; minutos_tarde: number | null;
  // 0446 — la foto de con qué horario se calculó ESTA jornada. `null` en
  // jornadas de antes de esa migración, hasta su próximo recálculo.
  horario_aplicado: HorarioAplicado | null;
}
// Tipos que un admin puede agregar manualmente (los pares salida/retorno y entrada/salida final)
const TIPOS_AGREGABLES = TIPOS_MARCA;

type Accion =
  | { modo: "editar"; marcaje: Marcaje; nuevaHora: string; nuevoTipo: TipoMarca; posteriores: Marcaje[] }
  | { modo: "anular"; marcaje: Marcaje }
  | { modo: "reactivar"; marcaje: Marcaje }
  | { modo: "confirmar"; marcaje: Marcaje }
  | { modo: "agregar"; tipo: TipoMarca; hora: string; motivoOtro: string };

/** Tarjeta de resumen del día (Estado, Horas, Tardanza, Entrada esperada). Un
 *  solo componente para las cuatro en vez de repetir el marco: así, si un día
 *  hace falta una quinta, no hay que copiar la envoltura otra vez. */
function TarjetaResumen({ etiqueta, children }: { etiqueta: string; children: React.ReactNode }) {
  return (
    <TarjetaInfo>
      <Rotulo className="mb-1.5">{etiqueta}</Rotulo>
      {/* break-words: jornada.estado llega crudo de la base ("auto_cerrada_pendiente",
          sin espacios) y desbordaba el ancho fijo de la tarjeta en vez de
          envolver — un `<strong>` suelto en el layout de antes no tenía este
          problema porque fluía en un párrafo, no en una tarjeta angosta. */}
      <div className="break-words text-base font-medium text-tinta">{children}</div>
    </TarjetaInfo>
  );
}

export default function CorreccionesPage() {
  const router = useRouter();
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [sedes, setSedes] = useState<Sede[]>([]);
  const [personaId, setPersonaId] = useState("");
  const [fecha, setFecha] = useState(hoyLima());
  // Filtro de la lista de la izquierda — no de qué persona está abierta.
  const [sedeFiltro, setSedeFiltro] = useState("");
  const [busqueda, setBusqueda] = useState("");
  // Si el panel de colaboradores está oculto para darle todo el ancho al día
  // abierto. Misma preferencia de vista, mismo hook, que en Datos personales
  // — se acuerda por navegador y no depende de qué persona esté abierta.
  const [equipoColapsado, setEquipoColapsado] = useFiltroGuardado("correcciones.equipo-colapsado", false);
  const [marcajes, setMarcajes] = useState<Marcaje[]>([]);
  const [jornada, setJornada] = useState<Jornada | null>(null);
  const [auditoria, setAuditoria] = useState<Auditoria[]>([]); // últimas correcciones de esta persona
  const [auditoriaError, setAuditoriaError] = useState(false); // para no confundir "sin correcciones" con "no cargó"
  // Por defecto el historial muestra solo lo que esta pantalla corrige (marcajes).
  // El resto —horario, contrato, educación…— comparte tabla pero responde otras
  // preguntas; se cuenta aparte (`auditoriaOtros`) y se ve con «Todo». No se
  // esconde: un cambio de horario explica por qué cambió la hora esperada.
  const [auditoriaVista, setAuditoriaVista] = useState<"marcajes" | "todo">("marcajes");
  const [auditoriaOtros, setAuditoriaOtros] = useState(0);
  // Cuántas filas se piden, POR PERSONA: al cambiar de persona vuelve a 30 sin
  // necesitar un efecto que lo resetee.
  const [auditoriaMas, setAuditoriaMas] = useState<Record<string, number>>({});
  // Lo que no se pudo traer al abrir la pantalla (lista del equipo, días por
  // revisar, marcas apartadas). Vacío = todo bien. Un vacío por ERROR se lee
  // igual que «no hay nada que revisar» — por eso se nombra.
  const [baseFalla, setBaseFalla] = useState<string[]>([]);
  // Del día abierto: `diaError` = no cargó lo esencial (marcajes o jornada);
  // `diaFallas` = cargó, pero una consulta de contexto no contestó.
  const [diaError, setDiaError] = useState<string | null>(null);
  const [diaFallas, setDiaFallas] = useState({ esperado: false, levantamiento: false, secuencia: false });
  // Contra qué hora se mide la tardanza ese día y de dónde sale (turno del día vs
  // horario base) — para que "N min tarde" nunca sea un número sin contexto.
  const [esperado, setEsperado] = useState<Esperado | null>(null);
  // TODOS los tramos de horario de la persona (no solo el vigente) — para
  // detectar un turno "espejo viejo" (caso Diana, set-2026): un turno puntual
  // que coincide con un horario que esta persona ya no tiene, y que por eso
  // sigue mandando en silencio sobre una tardanza real. Se pide solo al
  // cambiar de persona, no en cada fecha: no cambia mientras se navega el
  // calendario de la misma persona.
  const [tramosHistoricos, setTramosHistoricos] = useState<HorarioTramo[]>([]);
  // El turno puntual crudo del día (no solo lo que `esperadoDelDia` ya
  // resolvió) — `esTurnoEspejoViejo` necesita compararlo tramo por tramo, no
  // el resultado final.
  const [turnoDelDia, setTurnoDelDia] = useState<TurnoDia | null>(null);
  // Levantamiento de tardanza de ese día (perdón por fuerza mayor): si existe, la
  // tardanza se muestra tachada y no cuenta. La hora real NO se toca.
  const [levTardanza, setLevTardanza] = useState<{ motivo: string; observacion: string | null } | null>(null);
  const [levModal, setLevModal] = useState(false);
  const [levMotivo, setLevMotivo] = useState("fuerza_mayor");
  const [levObs, setLevObs] = useState("");
  const [levGuardando, setLevGuardando] = useState(false);
  const [cargado, setCargado] = useState(false);
  const [cargando, setCargando] = useState(false);
  const { avisar } = useToast();
  // Días sellados por el sistema (secuencia imposible). Sin esta lista el sello
  // sería inútil: nadie va a revisar persona por persona adivinando cuál quedó mal.
  const [porRevisar, setPorRevisar] = useState<DiaPorRevisar[]>([]);
  const [atencionElegida, setAtencionElegida] = useState<string | undefined>(undefined);
  // Marcas que el terminal no logró enviar y apartó (0304). Hasta esa migración
  // vivían en el IndexedDB de una Mac mini y nadie podía verlas desde acá.
  const [apartadas, setApartadas] = useState<MarcaApartada[]>([]);
  const [resolviendo, setResolviendo] = useState<string | null>(null);
  // Reemplaza el window.prompt() que pedía el motivo de resolver una marca
  // apartada: un motivo obligatorio se pregunta en un Modal con textarea, no
  // en un diálogo nativo del navegador (Felipe aprobó migrar todos, ver
  // CLAUDE.md). `apartadaAccion` guarda CUÁL marca y CUÁL resolución mientras
  // el modal está abierto; el motivo se escribe en `apartadaMotivo`.
  const [apartadaAccion, setApartadaAccion] = useState<{ marca: MarcaApartada; resolucion: "repuesta" | "improcedente" } | null>(null);
  const [apartadaMotivo, setApartadaMotivo] = useState("");
  // Reponer TODAS las apartadas de una vez: una caída del vínculo del terminal
  // deja decenas, y resolverlas una a una cuesta lo mismo que el error original.
  const [masivaAbierta, setMasivaAbierta] = useState(false);
  // ¿La secuencia de ESTE día sigue siendo imposible? Se pregunta en vivo a la
  // base en cada carga, no se deduce del sello guardado en las marcas: el sello
  // dice que el día estuvo roto alguna vez, no que lo siga estando.
  const [diaIncoherente, setDiaIncoherente] = useState(false);

  // edición local de horas por marcaje
  const [horasEditadas, setHorasEditadas] = useState<Record<string, string>>({});
  const [tiposEditados, setTiposEditados] = useState<Record<string, TipoMarca>>({});
  // acción pendiente de confirmar con motivo
  const [accion, setAccion] = useState<Accion | null>(null);
  const [motivo, setMotivo] = useState("");
  const [procesando, setProcesando] = useState(false);
  // Al convertir una marca en "salida final", lo que quedó después casi siempre
  // sobra (el caso real: un regreso que nunca ocurrió y el auto-cierre). El
  // sistema las propone marcadas, pero no las anula sin que se vean primero.
  const [anularPosteriores, setAnularPosteriores] = useState<Record<string, boolean>>({});
  // formulario "agregar marcaje". Tipo y hora arrancan en lo que le falta al día
  // y en la hora de su horario (marcaje-faltante.ts); aquí solo se guarda lo que
  // la persona del panel ELIGIÓ encima. Va atado a persona y fecha (`clave`): al
  // cambiar de día vuelve a la sugerencia sin un efecto que lo resetee.
  const [agregarElegido, setAgregarElegido] = useState<{ clave: string; tipo?: TipoMarca; hora?: string }>({ clave: "" });
  const [agregarMotivoOtro, setAgregarMotivoOtro] = useState("");

  // Todo lo que se pide al abrir la pantalla. Es una función y no el cuerpo de
  // un efecto para poder reintentar sin recargar la página.
  //
  // Antes las cinco consultas tiraban su `error`. Una lista de personas vacía por
  // fallo decía «Nadie coincide con este filtro»; unas marcas apartadas que no
  // llegaron desaparecían del aviso que existe justo para que ese día no se pague
  // como falta. Ahora un fallo se nombra y las listas que ya había se conservan.
  const cargarBase = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data } = await supabase.auth.getSession();
    if (!data.session) { router.replace("/admin/login"); return; }
    // Sin filtro de estado en la base, a propósito: la lista de la izquierda
    // solo muestra a quien sigue activo (`personasCorregibles`), pero el panel del
    // día y los nombres del historial se resuelven contra TODAS las personas — un
    // día que se abre desde una banda o desde un enlace puede ser de alguien que
    // ya cesó, y sin su fila quedaría sin nombre.
    const [p, s, dr, ap] = await Promise.all([
      supabase
        .from("personas").select("id, nombres, apellidos, rol, sede_base_id, tipo_vinculo, personal_direccion, estado")
        .eq("cuenta_de_servicio", false).order("nombres"),
      supabase.from("sedes").select("id, nombre").order("nombre"),
      supabase.rpc("fn_dias_por_revisar", { p_limite: LIMITE_DIAS_POR_REVISAR }),
      supabase.rpc("fn_marcas_apartadas"),
    ]);
    // DURAS (afirman algo sobre una persona o un pago): el equipo, los días por
    // revisar y las marcas apartadas. BLANDAS (solo comodidad): sedes, que es
    // un filtro.
    setBaseFalla(loQueNoSePudo([
      { error: p.error, que: "la lista del equipo" },
      { error: dr.error, que: "los días por revisar" },
      { error: ap.error, que: "las marcas que el terminal no pudo registrar" },
    ]));
    if (!p.error) setPersonas((p.data as Persona[]) ?? []);
    if (!s.error) setSedes((s.data as Sede[]) ?? []);
    if (!dr.error) setPorRevisar((dr.data as unknown as DiaPorRevisar[]) ?? []);
    if (!ap.error) setApartadas((ap.data as unknown as MarcaApartada[]) ?? []);
  }, [router]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- abrir la pantalla pide sus datos; el estado se pone después del await.
    void cargarBase();
  }, [cargarBase]);

  function abrirApartada(m: MarcaApartada, resolucion: "repuesta" | "improcedente") {
    setApartadaAccion({ marca: m, resolucion });
    setApartadaMotivo("");
  }

  async function resolverApartada() {
    if (!apartadaAccion) return;
    const { marca: m, resolucion } = apartadaAccion;
    if (apartadaMotivo.trim().length < 3) {
      avisar("error", "Escribe el motivo: esto decide si un día de trabajo queda registrado o no.");
      return;
    }

    setResolviendo(m.id);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_marca_apartada_resolver", {
      p_id: m.id, p_resolucion: resolucion, p_motivo: apartadaMotivo.trim(),
    });
    setResolviendo(null);

    if (error) {
      // El error de fn_registrar_marcaje sube tal cual: si el día está en un
      // periodo pagado, por ejemplo, hay que reabrirlo antes — y eso es lo que
      // dice el mensaje. La marca NO queda como resuelta, y el modal se queda
      // abierto con el motivo ya escrito para no perderlo.
      avisar("error", mensajeDeError(error, "resolver la marca apartada"));
      return;
    }

    setApartadaAccion(null);
    setApartadaMotivo("");
    const { data: ap } = await supabase.rpc("fn_marcas_apartadas");
    setApartadas((ap as unknown as MarcaApartada[]) ?? []);
    avisar(
      "ok",
      resolucion === "repuesta"
        ? `Marca registrada con su hora original. El aviso del terminal bajará solo en unos minutos.`
        : `Declarada improcedente. No se registró ningún marcaje, y queda el motivo en el historial.`,
    );
    if (m.persona_id === personaId) void refrescar();
  }

  // Una por una y en orden de hora: la máquina de estados del marcaje exige
  // entrada antes que salida, y repuestas al revés se rechazarían entre sí. Cada
  // una pasa por la misma `fn_marca_apartada_resolver` que el botón individual,
  // con sus mismas validaciones; la que la base rechace se queda en la lista y
  // se informa, no se oculta.
  async function resolverTodasApartadas() {
    if (apartadaMotivo.trim().length < 3) {
      avisar("error", "Escribe el motivo: esto decide si un día de trabajo queda registrado o no.");
      return;
    }
    setResolviendo("todas");
    const supabase = createAdminSupabaseClient();
    const orden = [...apartadas].sort((a, b) => a.timestamp_cliente.localeCompare(b.timestamp_cliente));
    let repuestas = 0;
    const fallos: string[] = [];
    for (const m of orden) {
      const { error } = await supabase.rpc("fn_marca_apartada_resolver", {
        p_id: m.id, p_resolucion: "repuesta", p_motivo: apartadaMotivo.trim(),
      });
      if (error) fallos.push(`${m.persona} ${m.fecha} ${horaTextoLima(m.timestamp_cliente)}: ${mensajeDeError(error, "resolver la marca apartada")}`);
      else repuestas++;
    }
    setResolviendo(null);
    setMasivaAbierta(false);
    setApartadaMotivo("");
    const { data: ap } = await supabase.rpc("fn_marcas_apartadas");
    setApartadas((ap as unknown as MarcaApartada[]) ?? []);
    if (fallos.length === 0) avisar("ok", `${repuestas} marcas registradas con su hora original.`);
    else avisar("error", `${repuestas} registradas, ${fallos.length} no se pudieron: ${fallos.slice(0, 3).join(" · ")}${fallos.length > 3 ? " …" : ""} Revísalas una a una.`);
    void refrescar();
  }

  const auditoriaLimite = auditoriaMas[personaId] ?? 30;

  // Historial de correcciones de la persona. Columnas planas (sin embeds: el
  // schema cache está trabado). Vive aparte del día para poder cambiar de vista
  // o pedir más filas sin volver a traer marcajes, jornada y turno.
  // Si no llega, se marca el error para NO mostrar «sin correcciones» en falso.
  const cargarAuditoria = useCallback(async () => {
    if (!personaId) return;
    const supabase = createAdminSupabaseClient();
    const lista = `(${CAMPOS_DE_MARCAJE.join(",")})`;
    let consulta = supabase.from("correcciones_auditoria")
      .select("id, campo_modificado, valor_anterior, valor_nuevo, corregido_at, motivo, corregido_por")
      .eq("persona_id", personaId);
    if (auditoriaVista === "marcajes") consulta = consulta.in("campo_modificado", [...CAMPOS_DE_MARCAJE]);
    const [{ data, error }, otros] = await Promise.all([
      consulta.order("corregido_at", { ascending: false }).limit(auditoriaLimite),
      // Cuántos cambios de OTROS temas hay, para avisarlo sin traerlos.
      supabase.from("correcciones_auditoria").select("id", { count: "exact", head: true })
        .eq("persona_id", personaId).not("campo_modificado", "in", lista),
    ]);
    setAuditoriaError(Boolean(error));
    setAuditoria(error ? [] : ((data as Auditoria[]) ?? []));
    setAuditoriaOtros(otros.error ? 0 : (otros.count ?? 0));
  }, [personaId, auditoriaVista, auditoriaLimite]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- cambiar de persona, de vista o de límite pide el historial; el estado se pone después del await.
    void cargarAuditoria();
  }, [cargarAuditoria]);

  const cargarDia = useCallback(async () => {
    if (!personaId) return;
    setCargando(true);
    setDiaError(null);
    const supabase = createAdminSupabaseClient();
    const { inicio, fin } = rangoDelDiaLima(fecha);
    const [{ data: incoh, error: errInc }, { data: mk, error: errMk }, { data: jor, error: errJor }, { data: turno, error: errTurno }, { data: horario, error: errHorario }, { data: levT, error: errLev }, { data: dr, error: errDr }] = await Promise.all([
      supabase.rpc("fn_dia_incoherente", { p_persona_id: personaId, p_fecha: fecha }),
      supabase.from("marcajes")
        .select("id, tipo, motivo_otro, timestamp_marca, origen, estado_revision, anulada_at, anulada_por, anulada_motivo")
        .eq("persona_id", personaId).gte("timestamp_marca", inicio).lte("timestamp_marca", fin)
        .order("timestamp_marca"),
      supabase.from("jornadas")
        .select("estado, horas_trabajadas, minutos_tarde, horario_aplicado")
        .eq("persona_id", personaId).eq("fecha", fecha).maybeSingle(),
      // Contra qué se mide la tardanza ese día: el turno puntual manda sobre el
      // horario base (misma prioridad que fn_recalcular_jornada, espejada en
      // jornada-esperada.ts).
      //
      // CAMBIO · `horarios_asignados` no traía `dias_laborables`: la rama
      // legacy de esperadoDelDia necesita esa columna para saber si el día
      // era laborable, no solo si hay una hora de entrada declarada.
      supabase.from("turnos").select("hora_entrada, hora_salida, es_descanso").eq("persona_id", personaId).eq("fecha", fecha).maybeSingle(),
      supabase.from("horarios_asignados")
        .select("persona_id, vigente_desde, vigente_hasta, hora_entrada, hora_salida, dias_laborables, horario_por_dia, almuerzo_min_minutos")
        .eq("persona_id", personaId).lte("vigente_desde", fecha).or(`vigente_hasta.is.null,vigente_hasta.gte.${fecha}`)
        .order("vigente_desde", { ascending: false }).limit(1).maybeSingle(),
      // ¿La tardanza de ese día fue levantada (perdonada por fuerza mayor)?
      supabase.from("tardanzas_justificadas").select("motivo, observacion").eq("persona_id", personaId).eq("fecha", fecha).maybeSingle(),
      // La lista de arriba se vuelve a pedir AQUÍ y no en cada acción, porque
      // todas las acciones de esta pantalla terminan llamando a `cargarDia`.
      // Antes se pedía una sola vez al montar: confirmabas el auto-cierre, el día
      // salía de la lista en la base, y la banda seguía anunciándolo — parecía
      // que la corrección no había hecho nada.
      supabase.rpc("fn_dias_por_revisar", { p_limite: LIMITE_DIAS_POR_REVISAR }),
    ]);
    if (errMk || errJor) {
      // Sin marcajes ni jornada no hay día que mostrar: se dice, y se puede
      // reintentar. Antes quedaba un «—» sin explicación, con el aviso ya
      // desaparecido. No pisa `marcajes`/`jornada` con datos parciales.
      setCargando(false);
      setDiaError(`No se pudo cargar el día: ${(errMk ?? errJor)!.message}`);
      return;
    }
    setMarcajes((mk as Marcaje[]) ?? []);
    // Si alguna de las tres consultas de contexto no contestó, NO se afirma lo
    // contrario: «sin horario vigente» a alguien que sí lo tiene, o «sin
    // levantar» a una tardanza que sí se perdonó, son afirmaciones falsas. Se
    // marca y las tarjetas dicen «no se pudo consultar».
    setDiaFallas({ esperado: Boolean(errTurno || errHorario), levantamiento: Boolean(errLev), secuencia: Boolean(errInc) });
    setDiaIncoherente(!errInc && incoh === true);
    setJornada((jor as Jornada) ?? null);
    setTurnoDelDia((turno as TurnoDia) ?? null);
    setEsperado(errTurno || errHorario ? null : esperadoDelDia(fecha, (turno as TurnoDia) ?? null, (horario as HorarioTramo) ?? null));
    setLevTardanza((levT as { motivo: string; observacion: string | null } | null) ?? null);
    // Falla suave: si no llega, se deja la lista que ya había en vez de vaciarla
    // — una lista vacía por error se lee igual que "no hay nada que revisar".
    if (!errDr && dr) setPorRevisar(dr as unknown as DiaPorRevisar[]);
    setHorasEditadas(Object.fromEntries(((mk as Marcaje[]) ?? []).map((m) => [m.id, horaInput(m.timestamp_marca)])));
    setCargado(true);
    setCargando(false);
  }, [personaId, fecha]);

  // Recarga el día Y el historial: toda acción de esta pantalla escribe una fila
  // en la auditoría, y el historial tiene que mostrarla.
  const refrescar = useCallback(async () => {
    await Promise.all([cargarDia(), cargarAuditoria()]);
  }, [cargarDia, cargarAuditoria]);

  // Historial completo de horarios de la persona seleccionada, SIN filtrar por
  // `vigente_hasta` — a diferencia de la consulta de `cargarDia`, que solo trae
  // el tramo vigente de esa fecha. Solo depende de `personaId`: cambiar de
  // fecha no debe repetir esta consulta.
  useEffect(() => {
    // El estado se pone SIEMPRE desde un `.then` (nunca en el cuerpo del
    // efecto): sin persona seleccionada no hay consulta que hacer, pero el
    // reset a `[]` tiene que llegar por la misma vía asíncrona que el dato
    // real, o el lint de la casa lo marca como setState síncrono en un efecto.
    const supabase = createAdminSupabaseClient();
    const tramos: Promise<HorarioTramo[]> = personaId
      ? Promise.resolve(
          supabase.from("horarios_asignados")
            .select("persona_id, vigente_desde, vigente_hasta, hora_entrada, hora_salida, dias_laborables, horario_por_dia, almuerzo_min_minutos")
            .eq("persona_id", personaId)
            .then(({ data }) => (data as HorarioTramo[]) ?? [])
        )
      : Promise.resolve([]);
    tramos.then(setTramosHistoricos);
  }, [personaId]);

  // Deep-link: al llegar con ?persona=<id>&fecha=<YYYY-MM-DD> (desde un incidente del
  // dashboard), precarga esa persona y fecha.
  useEffect(() => {
    if (personas.length === 0) return;
    const sp = new URLSearchParams(window.location.search);
    const pid = sp.get("persona");
    const f = sp.get("fecha");
    if (pid) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- leer la URL al montar, mismo patrón aceptado en admin/bandeja/page.tsx.
      setPersonaId(pid);
      if (f) setFecha(f);
    }
  }, [personas]);

  // La lista de la izquierda ya no necesita un botón "Ver el día": elegir a
  // alguien (o cambiar la fecha del panel de la derecha) carga el día solo.
  // `cargarDia` ya vuelve de inmediato si no hay persona elegida.
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- elegir persona o fecha carga el día; el estado se pone después del await.
    void cargarDia();
  }, [cargarDia]);

  const MOTIVOS_TARD = [
    { valor: "fuerza_mayor", label: "Fuerza mayor" },
    { valor: "salud", label: "Salud" },
    { valor: "transporte", label: "Transporte" },
    { valor: "otro", label: "Otro" },
  ];
  const motivoTardLabel = (m: string | null | undefined) => MOTIVOS_TARD.find((x) => x.valor === m)?.label ?? m ?? "";

  async function levantarTardanza() {
    if (!personaId) return;
    if (levMotivo === "otro" && levObs.trim().length < 3) { avisar("error", "Para 'Otro' la observación es obligatoria."); return; }
    setLevGuardando(true);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_levantar_tardanza", {
      p_persona_id: personaId, p_fecha: fecha, p_motivo: levMotivo, p_observacion: levObs.trim() || null,
    });
    setLevGuardando(false);
    if (error) { avisar("error", error.message); return; }
    setLevModal(false); setLevObs(""); setLevMotivo("fuerza_mayor");
    await cargarDia();
    avisar("ok", "Tardanza levantada. La hora real no se tocó.");
  }
  async function quitarLevantamiento() {
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_quitar_levantamiento", { p_persona_id: personaId, p_fecha: fecha });
    if (error) { avisar("error", error.message); return; }
    await cargarDia();
  }

  async function ejecutar() {
    if (!accion) return;
    if (motivo.trim().length < 3) { avisar("error", "Escribe un motivo (mínimo 3 caracteres)."); return; }
    setProcesando(true);
    const supabase = createAdminSupabaseClient();
    let error = null;
    if (accion.modo === "editar") {
      // Tipo y hora en una sola corrección (mig. 0081). Se manda solo lo que cambió.
      const cambiaTipo = accion.nuevoTipo !== accion.marcaje.tipo;
      const cambiaHora = accion.nuevaHora !== horaInput(accion.marcaje.timestamp_marca);
      ({ error } = await supabase.rpc("fn_corregir_marca", {
        p_marcaje_id: accion.marcaje.id,
        p_nuevo_tipo: cambiaTipo ? accion.nuevoTipo : undefined,
        p_nuevo_ts: cambiaHora ? construirTs(fecha, accion.nuevaHora) : undefined,
        p_motivo: motivo.trim(),
      }));
    } else if (accion.modo === "anular") {
      // Anular, no borrar: la marca se queda en el historial (mig. 0081).
      ({ error } = await supabase.rpc("fn_anular_marcaje", {
        p_marcaje_id: accion.marcaje.id, p_motivo: motivo.trim(),
      }));
    } else if (accion.modo === "reactivar") {
      ({ error } = await supabase.rpc("fn_reactivar_marcaje", {
        p_marcaje_id: accion.marcaje.id, p_motivo: motivo.trim(),
      }));
    } else if (accion.modo === "confirmar") {
      ({ error } = await supabase.rpc("fn_confirmar_auto_cierre", {
        p_marcaje_id: accion.marcaje.id, p_motivo: motivo.trim(),
      }));
    } else {
      ({ error } = await supabase.rpc("fn_agregar_marcaje", {
        p_persona_id: personaId,
        p_tipo: accion.tipo,
        p_ts: construirTs(fecha, accion.hora),
        p_motivo: motivo.trim(),
        p_motivo_otro: accion.tipo === "salida_otro" ? (accion.motivoOtro || undefined) : undefined,
      }));
    }
    // Las marcas que quedaron después de una salida final, si se dejaron marcadas.
    // Van después de la corrección: si esta falla, no se anula nada.
    let anuladas = 0;
    if (!error && accion.modo === "editar") {
      for (const post of accion.posteriores) {
        if (!anularPosteriores[post.id]) continue;
        const { error: eAnu } = await supabase.rpc("fn_anular_marcaje", {
          p_marcaje_id: post.id,
          p_motivo: `${motivo.trim()} — queda después de la salida final`,
        });
        if (eAnu) { error = eAnu; break; }
        anuladas += 1;
      }
    }
    setProcesando(false);
    if (error) {
      avisar("error", anuladas > 0
        ? `La corrección se guardó y se anularon ${anuladas}, pero luego falló: ${error.message}`
        : error.message);
      await refrescar();
      return;
    }
    setAccion(null);
    setMotivo("");
    setAnularPosteriores({});
    // Agregado el marcaje, el formulario vuelve a proponer lo que falte ahora.
    if (accion.modo === "agregar") setAgregarElegido({ clave: "" });
    await refrescar();
    avisar("ok", anuladas > 0
      ? `Corrección guardada y ${anuladas} ${anuladas === 1 ? "marca anulada" : "marcas anuladas"}. Todo queda en la auditoría.`
      : "Corrección guardada y registrada en la auditoría.");
  }

  const personaSel = useMemo(() => personas.find((p) => p.id === personaId), [personas, personaId]);
  // ¿El turno puntual de este día es un espejo de un horario que esta persona
  // YA NO TIENE vigente? (caso Diana, set-2026). Solo tiene sentido preguntarlo
  // cuando el turno es lo que de verdad manda ese día (`esperado.origen ===
  // "turno"`) — si no hay turno puntual, no hay nada que comparar.
  const esEspejoViejo = useMemo(() => {
    if (esperado?.origen !== "turno" || !turnoDelDia) return false;
    return esTurnoEspejoViejo(fecha, turnoDelDia, tramosHistoricos);
  }, [esperado, turnoDelDia, tramosHistoricos, fecha]);
  // Con qué arranca «Agregar un marcaje faltante». Lo que se muestra y lo que se
  // manda es este mismo valor derivado, nunca dos estados que puedan separarse
  // (la lección del campo de fecha de Safari, CLAUDE.md, 2026-08-26). Sin
  // sugerencia, el mismo arranque de siempre: «Entrada» a las 08:00.
  const agregarClave = `${personaId}|${fecha}`;
  const agregarYaElegido = agregarElegido.clave === agregarClave ? agregarElegido : { clave: agregarClave };
  const momentoAgregar = { fecha, hoy: hoyLima(), ahora: horaLima() };
  const agregarTipo = agregarYaElegido.tipo
    ?? tipoQueFalta(
      marcajes.filter((m) => m.anulada_at === null).map((m) => ({ tipo: m.tipo, timestamp: m.timestamp_marca })),
      esperado, momentoAgregar,
    )
    ?? "entrada";
  const agregarHoraDelHorario = horaDelHorario(agregarTipo, esperado, momentoAgregar);
  const agregarHora = agregarYaElegido.hora ?? agregarHoraDelHorario ?? "08:00";
  // Nombre de quién hizo cada corrección, resuelto desde la lista ya cargada
  // (evita depender de un embed de PostgREST que el schema cache puede no exponer).
  const nombrePorId = useMemo(() => new Map(personas.map((p) => [p.id, `${p.nombres} ${p.apellidos}`])), [personas]);
  const sedeNombrePorId = useMemo(() => new Map(sedes.map((s) => [s.id, s.nombre])), [sedes]);
  const puedeCorregir = puedeOperarEquipo(rol);
  const esSupervisor = esRolEncargada(rol);

  // Solo quien sigue activo entra a la lista: a quien ya cesó no se le ofrece
  // aquí (decisión de Felipe, 2026-09-30 — estorbaba la vista, y lo dijo dos
  // veces). Su día NO desaparece de la pantalla: sigue abriéndose desde las
  // bandas de arriba (`fn_dias_por_revisar`, que por la 0422 aún incluye al
  // cesado sin liquidar) y desde un enlace `?persona=…`. Y una encargada no
  // puede corregir su propia asistencia ni la de un admin.
  const personasCorregibles = useMemo(() => {
    const activas = personas.filter((p) => p.estado === "activo");
    if (!esSupervisor || !yo) return activas;
    return activas.filter((p) => p.id !== yo.id && !ROLES_DO.includes(p.rol));
  }, [personas, esSupervisor, yo]);

  // Cuántos días por revisar tiene cada persona, en TODO el equipo — no solo el
  // día que está abierto ahora mismo. Es lo que deja elegir a quién atender sin
  // tener que probar persona por persona; reusa fn_dias_por_revisar, que ya se
  // pedía para las tres bandas de arriba, en vez de una consulta nueva.
  const pendientesPorPersona = useMemo(() => {
    const mapa = new Map<string, number>();
    for (const d of porRevisar) {
      if (d.periodo_pagado) continue; // sin acción posible: no cuenta como pendiente
      mapa.set(d.persona_id, (mapa.get(d.persona_id) ?? 0) + 1);
    }
    return mapa;
  }, [porRevisar]);

  // La lista de la izquierda: sede + texto, sobre las mismas personas que ya
  // puede corregir quien mira la pantalla.
  const personasListadas = useMemo(() => {
    const texto = busqueda.trim().toLowerCase();
    return personasCorregibles.filter((p) => {
      if (sedeFiltro && p.sede_base_id !== sedeFiltro) return false;
      if (!texto) return true;
      return `${p.nombres} ${p.apellidos}`.toLowerCase().includes(texto);
    });
  }, [personasCorregibles, sedeFiltro, busqueda]);

  if (rol !== null && !puedeCorregir) {
    return (
      <div className="flex flex-1 flex-col">
        <main className="flex flex-1 items-center justify-center p-6">
          <p className="max-w-md text-center text-taupe">
            No tienes permiso para corregir marcajes. Si necesitas un cambio, pídeselo a Felipe o Carlos.
          </p>
        </main>
      </div>
    );
  }

  // Tres bandas, no una — y esta es la razón (mig. 0384).
  //
  // Hasta hoy había una sola, titulada "quedó con una secuencia
  // imposible", y se pintaba para CUALQUIER día que la base devolviera.
  // Pero `fn_dias_por_revisar` devuelve todo día con una marca en
  // 'pendiente_revision', y a esa columna la escriben tres cosas que no
  // se parecen en nada. La consecuencia real, vista en producción el
  // 2026-09-06: un día cuya única pendiente era confirmar la hora del
  // auto-cierre se anunciaba como secuencia imposible, y al abrirlo la
  // MISMA pantalla decía lo contrario dos centímetros más abajo.
  //
  // Y como el auto-cierre corre todas las noches, esa banda se llenaba
  // sola de días sanos bajo un titular de alarma. El daño no es el
  // texto: es que el día que una marca llegue de verdad fuera de orden
  // va a estar enterrada entre ellos y se leerá como más de lo mismo.
  //
  // Un día de un periodo ya pagado no tiene acción posible
  // (fn_anular_marcaje lo rechaza), así que no entra a ninguna banda:
  // Felipe pidió que dejara de estorbar la vista. Sigue existiendo en
  // fn_dias_por_revisar por si algún día hace falta un historial.
  const accionables = porRevisar.filter((d) => !d.periodo_pagado);
  // `motivo` null = base sin la 0384 todavía. Se trata como el caso
  // grave, que es el único que no se puede dejar de avisar.
  const rotos    = accionables.filter((d) => d.motivo === "secuencia_imposible" || d.motivo == null);
  const cerrados = accionables.filter((d) => d.motivo === "auto_cierre_sin_confirmar");
  const sellados = accionables.filter((d) => d.motivo === "sello_sin_levantar");

  // Abre el día de verdad. El efecto de arriba se encarga de cargarlo.
  const abrir = (d: DiaPorRevisar) => {
    setPersonaId(d.persona_id);
    setFecha(d.fecha);
    setCargado(false);
  };
  const lista = (dias: DiaPorRevisar[], hover: string) => (
    <ul className="flex flex-col">
      {dias.map((d) => (
        <li key={`${d.persona_id}-${d.fecha}`}>
          <button
            onClick={() => abrir(d)}
            className={`w-full rounded-lg px-3 py-2 text-left text-sm transition-colors ${hover}`}
          >
            <span className="font-medium text-tinta">{d.nombre}</span>
            <span className="text-taupe"> · {d.sede} · {d.fecha}</span>
          </button>
        </li>
      ))}
    </ul>
  );


  // Qué lista está abierta bajo «Para atender». `undefined` = nadie eligió todavía: se abre la más
  // grave que tenga algo. `""` = quien usa la pantalla la cerró a propósito.
  const primeraConAlgo = apartadas.length > 0 ? "apartadas" : rotos.length > 0 ? "rotos" : cerrados.length > 0 ? "cerrados" : sellados.length > 0 ? "sellados" : "";
  const atencion = atencionElegida ?? primeraConAlgo;

  return (
    <div className="flex flex-1 flex-col">
      <div className="px-4 pt-5 md:px-6">
        <CabeceraPagina
          titulo="Corregir marcajes"
          descripcion="Corrige una hora, agrega una marca olvidada o anula un duplicado. Cada cambio pide un motivo."
          ayuda={
            <AyudaPantalla
              titulo="Cómo funciona Corregir marcajes"
              intro="Aquí se arregla lo que el terminal no pudo resolver solo. Nada se borra: toda corrección queda con quién, qué y cuándo."
              secciones={[
                { titulo: "Elegir el día", texto: "Busca a la persona en la lista de la izquierda y abre el día. Si llegaste desde Incidencias o Desempeño, el día ya viene abierto." },
                { titulo: "Qué puedes hacer", texto: "Cambiar la hora o el tipo de una marca, agregar una marca olvidada, anular una que sobra (se puede deshacer) y confirmar la salida que puso el sistema." },
                { titulo: "Para atender", texto: "Las pastillas de arriba son lo que pide una decisión: marcas que el terminal apartó sin registrar, días con la secuencia desordenada y salidas puestas por el cierre nocturno que nadie confirmó. Toca una para ver su lista." },
                { titulo: "Marcas sin registrar", texto: "La persona sí marcó pero la marca no llegó. Mientras no se repone, ese día se paga como si no hubiera venido: es lo primero que conviene mirar." },
                { titulo: "Periodo pagado", texto: "Un día de un periodo ya pagado no se puede corregir sin reabrirlo primero." },
              ]}
            />
          }
        />
      </div>

      <div className="px-4 md:px-6">
        {/* Lo que no se pudo traer al abrir. Va primero: si la lista de marcas
            apartadas no llegó, «no hay nada que revisar» sería falso. */}
        {baseFalla.length > 0 && (
          <BannerAviso role="alert" variante="alerta" titulo={<>No se pudo traer: {baseFalla.join(", ")}.</>} className="mb-6 max-w-3xl">
            <p className="mb-3 text-taupe">
              Lo que ves abajo puede estar incompleto: que una lista salga vacía no quiere decir que no haya nada pendiente.
            </p>
            <Boton variante="secundario" tamano="sm" className="min-h-11 md:min-h-0" onClick={() => void cargarBase()}>Reintentar</Boton>
          </BannerAviso>
        )}

        {/* «Para atender» (como Educación): lo que pide una decisión, en una línea. Tocar una pastilla abre
            su lista debajo. Si hay algo, se abre solo el más grave: nadie debería tener que adivinar que
            hay marcas que no llegaron a registrarse. */}
        <ParaAtender
          items={[
            { clave: "apartadas", texto: `${apartadas.length} marca${apartadas.length === 1 ? "" : "s"} sin registrar`, n: apartadas.length, tono: "rojo" },
            { clave: "rotos", texto: `${rotos.length} día${rotos.length === 1 ? "" : "s"} desordenado${rotos.length === 1 ? "" : "s"}`, n: rotos.length, tono: "ambar" },
            { clave: "cerrados", texto: `${cerrados.length} salida${cerrados.length === 1 ? "" : "s"} por confirmar`, n: cerrados.length, tono: "pizarra" },
            { clave: "sellados", texto: `${sellados.length} ya cuadra${sellados.length === 1 ? "" : "n"}`, n: sellados.length, tono: "neutro" },
          ]}
          activa={atencion || null}
          alTocar={(clave) => setAtencionElegida(atencion === clave ? "" : clave)}
        />

        {/* Va ARRIBA de los días por revisar: aquellos son días que existen y
            están desordenados; estas son marcas que NO existen todavía. Si nadie
            las repone, ese día se paga como si la persona no hubiera venido. */}
        {atencion === "apartadas" && apartadas.length > 0 && (
          <BannerAviso
            variante="alerta"
            className="mb-6 max-w-3xl"
            titulo={apartadas.length === 1
              ? "1 marca no llegó a registrarse"
              : `${apartadas.length} marcas no llegaron a registrarse`}
          >
            <p className="mb-3 text-taupe">
              El terminal las intentó seis veces y las apartó para no perderlas. La persona sí marcó:
              mientras no se repongan, ese día se paga como si no hubiera venido.
            </p>
            {apartadas.length > 1 && (
              <div className="mb-3">
                <Boton variante="primario" tamano="sm" onClick={() => { setApartadaMotivo(""); setMasivaAbierta(true); }} disabled={resolviendo !== null}>
                  Registrar todas con su hora ({apartadas.length})
                </Boton>
              </div>
            )}
            <ul className="flex flex-col gap-2">
              {apartadas.map((m) => (
                <li key={m.id} className="rounded-lg bg-papel px-3 py-2 text-sm">
                  <div>
                    <span className="font-medium text-tinta">{m.persona}</span>
                    <span className="text-taupe">
                      {" "}· {m.sede} · {m.tipo} del {m.fecha} a las {horaTextoLima(m.timestamp_cliente)}
                    </span>
                  </div>
                  {m.ultimo_error && (
                    <div className="mt-0.5 text-xs text-taupe">el terminal decía: {m.ultimo_error}</div>
                  )}
                  <div className="mt-2 flex flex-wrap gap-2">
                    <Boton
                      variante="secundario"
                      tamano="sm"
                      onClick={() => abrirApartada(m, "repuesta")}
                      disabled={resolviendo !== null}
                    >
                      Registrarla con su hora
                    </Boton>
                    <Boton
                      variante="peligro"
                      tamano="sm"
                      onClick={() => abrirApartada(m, "improcedente")}
                      disabled={resolviendo !== null}
                    >
                      No corresponde
                    </Boton>
                  </div>
                </li>
              ))}
            </ul>
          </BannerAviso>
        )}

        {porRevisar.length >= LIMITE_DIAS_POR_REVISAR && atencion !== "apartadas" && (
          <p className="mb-4 max-w-3xl text-xs text-taupe">
            Se muestran los {LIMITE_DIAS_POR_REVISAR} días más recientes: puede haber más atrás. Al resolver estos, aparecen los siguientes.
          </p>
        )}
        
        {/* 1 · El día está roto de verdad. Es el único que pide trabajo. */}
        {atencion === "rotos" && rotos.length > 0 && (
          <BannerAviso
            variante="advertencia"
            className="mb-6 max-w-3xl"
            titulo={rotos.length === 1
              ? "1 día quedó con una secuencia imposible"
              : `${rotos.length} días quedaron con una secuencia imposible`}
          >
            <p className="mb-3 text-taupe">
              Por ejemplo, dos salidas seguidas sin retorno entre medio. Ocurre cuando la
              terminal pierde señal y una marca llega tarde. No se perdió nada: solo hay que
              ordenar el día. Toca uno para abrirlo.
            </p>
            {lista(rotos, "hover:bg-ambar/10")}
          </BannerAviso>
        )}

        {/* 2 · El día cuadra; falta decir si la hora que inventó el robot vale. */}
        {atencion === "cerrados" && cerrados.length > 0 && (
          <BannerAviso
            variante="informativo"
            className="mb-6 max-w-3xl"
            titulo={cerrados.length === 1
              ? "1 día espera que confirmes la hora de salida"
              : `${cerrados.length} días esperan que confirmes la hora de salida`}
          >
            <p className="mb-3 text-taupe">
              Nadie marcó la salida y el auto-cierre nocturno puso una hora. La secuencia de
              esos días está bien; lo único pendiente es decir si esa hora es la buena.
              Mientras siga sin confirmar, el día no mide salida anticipada ni tiempo
              adicional. Toca uno para abrirlo.
            </p>
            {lista(cerrados, "hover:bg-pizarra/10")}
          </BannerAviso>
        )}

        {/* 3 · Ya no hay nada que hacer, y aun así siguen marcados. */}
        {atencion === "sellados" && sellados.length > 0 && (
          <BannerAviso
            variante="neutral"
            className="mb-6 max-w-3xl"
            titulo={sellados.length === 1
              ? "1 día quedó marcado y ya cuadra"
              : `${sellados.length} días quedaron marcados y ya cuadran`}
          >
            <p className="mb-3 text-taupe">
              No hay nada que corregir: su secuencia es correcta. La marca quedó señalada
              cuando el día estuvo roto, y la marca que llegó después a arreglarlo no levantó
              esa señal. Sale de la lista en cuanto se corrija cualquier cosa de ese día.
            </p>
            {lista(sellados, "hover:bg-sand/40")}
          </BannerAviso>
        )}
      </div>

      {/* Split view: filtro + lista de personas a la izquierda, el día abierto a
          la derecha. Reemplaza el selector único de arriba — con ~30 personas
          en 4 sedes, elegir a alguien pedía abrir un <select> larguísimo; acá
          se filtra por sede y se busca por nombre, y el número junto a cada
          fila dice de entrada quién tiene algo por revisar. */}
      <div className="flex min-h-0 flex-1">
        {/* Igual que en Datos personales: se oculta del todo (no solo
            visualmente) para que el día abierto —a la derecha, `flex-1`—
            recupere el ancho de verdad. Acá no hace falta tocar ninguna
            columna de grid: al ser `flex`, con el `<aside>` fuera del árbol
            el hermano `flex-1` ya ocupa lo que queda. */}
        {/* En celular la pantalla es de UNA columna: la lista, y al elegir a
            alguien el día (con «‹ Equipo» para volver). Con las dos a la vez,
            a 375 px el día quedaba en ~27 px de ancho. Desde `md` es el split de
            siempre, y «ocultar el equipo» solo aplica ahí. */}
        <aside className={`${personaId ? "hidden" : "flex"} ${equipoColapsado ? "md:hidden" : "md:flex"} w-full flex-col border-r border-sand bg-papel md:max-w-[300px] md:shrink-0`}>
          <div className="space-y-3 border-b border-sand p-4">
            <div className="hidden items-center justify-end md:flex">
              <button
                onClick={() => setEquipoColapsado(true)}
                className="rounded-control p-1 text-taupe transition-colors hover:bg-sand hover:text-tinta"
                title="Ocultar el equipo y darle todo el ancho al día"
                aria-label="Ocultar el equipo"
              >
                <PanelLeftClose size={15} strokeWidth={1.8} aria-hidden />
              </button>
            </div>
            <CampoSelect
              etiqueta="Sede"
              value={sedeFiltro}
              onChange={(e) => setSedeFiltro(e.target.value)}
            >
              <option value="">Todas las sedes</option>
              {sedes.map((s) => <option key={s.id} value={s.id}>{s.nombre}</option>)}
            </CampoSelect>
            <label className="relative block">
              <span className="sr-only">Buscar por nombre</span>
              <Search size={14} strokeWidth={1.8} className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-taupe" aria-hidden />
              <input
                type="text"
                placeholder="Buscar por nombre…"
                value={busqueda}
                onChange={(e) => setBusqueda(e.target.value)}
                className="w-full rounded-control border border-borde-control bg-hueso py-1.5 pl-8 pr-3 text-sm text-tinta placeholder:text-taupe focus:outline-none focus-visible:outline-2 focus-visible:outline-rojo"
              />
            </label>
          </div>

          <div className="flex-1 overflow-y-auto p-2">
            <Rotulo className="px-2 py-1.5">
              {personasListadas.length} {personasListadas.length === 1 ? "colaborador" : "colaboradores"}
            </Rotulo>
            {personasListadas.length === 0 ? (
              <p className="px-2 py-6 text-center text-sm text-taupe">
                {personas.length === 0 && baseFalla.length > 0 ? "No se pudo traer la lista del equipo." : "Nadie coincide con este filtro."}
              </p>
            ) : (
              <ul className="flex flex-col gap-1">
                {personasListadas.map((p) => {
                  const seleccionada = p.id === personaId;
                  const pendientes = pendientesPorPersona.get(p.id) ?? 0;
                  const iniciales = `${p.nombres[0] ?? ""}${p.apellidos[0] ?? ""}`.toUpperCase();
                  return (
                    <li key={p.id}>
                      <button
                        onClick={() => { setPersonaId(p.id); setCargado(false); }}
                        className={`flex w-full items-center gap-2.5 rounded-lg px-2.5 py-2 text-left transition-colors ${
                          seleccionada ? "bg-crema ring-1 ring-inset ring-rojo/30" : "hover:bg-crema/70"
                        }`}
                      >
                        <span className="flex size-8 shrink-0 items-center justify-center rounded-full bg-rojo/10 font-serif text-sm text-rojo">
                          {iniciales}
                        </span>
                        <span className="min-w-0 flex-1">
                          <span className={`block truncate text-sm font-medium ${seleccionada ? "text-rojo" : "text-tinta"}`}>
                            {p.nombres} {p.apellidos}
                          </span>
                          <span className="block truncate text-xs text-taupe">
                            {sedeNombrePorId.get(p.sede_base_id) ?? "—"}
                          </span>
                        </span>
                        {pendientes > 0 && (
                          <span title={`${pendientes} ${pendientes === 1 ? "día" : "días"} por revisar`}>
                            <Insignia variante="contador" tamano="sm">{pendientes}</Insignia>
                          </span>
                        )}
                        <ChevronRight size={16} strokeWidth={1.8} className={seleccionada ? "text-rojo" : "text-taupe/60"} aria-hidden />
                      </button>
                    </li>
                  );
                })}
              </ul>
            )}
          </div>
        </aside>

        <div className={`${personaId ? "block" : "hidden md:block"} min-w-0 flex-1 overflow-y-auto p-4 md:p-6`}>
          <button
            onClick={() => { setPersonaId(""); setCargado(false); }}
            className="mb-4 inline-flex min-h-11 items-center gap-1 rounded-pildora px-2 text-sm font-medium text-rojo md:hidden"
          >
            <ChevronLeft size={16} strokeWidth={1.8} aria-hidden /> Equipo
          </button>
          {equipoColapsado && (
            <button
              onClick={() => setEquipoColapsado(false)}
              className="mb-4 hidden items-center gap-1.5 md:inline-flex rounded-pildora bg-tinta px-3 py-1.5 text-xs font-medium text-crema transition-colors hover:bg-rojo-profundo"
            >
              <PanelLeftOpen size={14} strokeWidth={1.8} aria-hidden /> Equipo · {personasListadas.length}
            </button>
          )}
          {!personaId || !personaSel ? (
            <div className="flex h-full flex-col items-center justify-center px-6 text-center">
              <p className="text-sm text-taupe">Elige a alguien de la lista para ver y corregir sus marcajes.</p>
            </div>
          ) : (
            <div className="max-w-3xl">
              <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
                <h2 className="font-serif text-xl text-tinta">
                  {personaSel.nombres} {personaSel.apellidos}
                </h2>
                <label className="flex items-center gap-2 rounded-control border border-borde-control bg-papel px-3 py-1.5">
                  <Calendar size={15} strokeWidth={1.8} className="text-rojo" aria-hidden />
                  <input
                    type="date"
                    value={fecha}
                    onChange={(e) => { setFecha(e.target.value); setCargado(false); }}
                    className="bg-transparent text-sm font-medium text-tinta focus:outline-none"
                  />
                </label>
              </div>

              {!cargado ? (
                diaError ? (
                  <BannerAviso role="alert" variante="alerta" enLinea>
                    <p className="text-tinta">{diaError}</p>
                    <Boton variante="secundario" tamano="sm" className="mt-2 min-h-11 md:min-h-0" onClick={() => void cargarDia()}>Reintentar</Boton>
                  </BannerAviso>
                ) : (
                  <p className="text-sm text-taupe">{cargando ? "Cargando…" : "—"}</p>
                )
              ) : (
                <>
                  {(diaFallas.esperado || diaFallas.levantamiento || diaFallas.secuencia) && (
                    <BannerAviso role="alert" enLinea titulo="No se pudo consultar todo." className="mb-4 leading-relaxed">
                      <span className="text-taupe">
                        Falta: {[
                          diaFallas.esperado && "el horario que le tocaba ese día",
                          diaFallas.levantamiento && "si la tardanza fue levantada",
                          diaFallas.secuencia && "si la secuencia de marcas es posible",
                        ].filter(Boolean).join(", ")}. Lo que no aparece no quiere decir que no exista.{" "}
                      </span>
                      <Boton variante="enlace" className="font-medium" onClick={() => void cargarDia()}>Reintentar</Boton>
                    </BannerAviso>
                  )}
                  {/* Dos avisos distintos, no uno.
                      Antes había uno solo, que se mostraba cuando CUALQUIER marca del día
                      seguía en 'pendiente_revision'. Eso daba dos fallos: (a) un día ya
                      arreglado seguía en rojo, porque el sello es un estado guardado de
                      cuando estuvo roto y no una pregunta sobre si sigue roto — y las
                      marcas anuladas también contaban; (b) el texto hablaba siempre de
                      "secuencia imposible" aunque el motivo real fuera un auto-cierre,
                      que es otra cosa. Ahora se pregunta en vivo y cada caso dice lo suyo. */}
                  {diaIncoherente && (
                    <BannerAviso enLinea titulo="La secuencia de marcas de este día no es posible." className="mb-4 leading-relaxed">
                      <span className="text-taupe">
                        Por ejemplo, dos salidas seguidas sin retorno entre medio. Suele pasar cuando una
                        marca llega tarde tras un corte de señal. Corrige el tipo o la hora de lo que esté
                        mal, o anula lo que sobre — el aviso desaparece solo en cuanto el día cuadre.
                      </span>
                    </BannerAviso>
                  )}
                  {marcajes.some((m) => m.anulada_at === null && m.origen === "auto_cierre" && m.estado_revision === "pendiente_revision") && (
                    <BannerAviso enLinea titulo="Este día lo cerró el sistema." className="mb-4 leading-relaxed">
                      <span className="text-taupe">
                        Nadie marcó la salida, así que el auto-cierre nocturno puso una hora. Mientras
                        siga sin revisar, ese día no mide salida anticipada ni tiempo adicional. Pulsa
                        <em> Confirmar</em> si esa hora es la buena, o corrígela.
                      </span>
                    </BannerAviso>
                  )}

                  {/* Caso Diana (set-2026): el turno del día manda sobre el horario
                      base, así que un turno puntual viejo que quedó como "espejo" de
                      un horario ya reemplazado sigue mandando en silencio sobre una
                      tardanza real. No reemplaza el aviso de la tarjeta "Entrada
                      esperada", se suma — aquella dice DE DÓNDE sale la hora
                      esperada, este dice que esa fuente puede estar desactualizada.
                      Solo señala: la corrección sigue siendo manual, en Turnos. */}
                  {esperado?.origen === "turno" && esEspejoViejo && (
                    <BannerAviso enLinea titulo="Ojo: este turno coincide con un horario que esta persona ya no tiene." className="mb-4 leading-relaxed">
                      <span className="text-taupe">
                        Puede ser un espejo viejo que quedó desactualizado cuando cambió su horario base. Revísalo en Turnos.
                      </span>
                    </BannerAviso>
                  )}

                  {/* Cuatro tarjetas de resumen — Estado, Horas, Tardanza (con su
                      levantar/quitar intacto) y Entrada esperada (con su enlace a
                      Turnos, aprobado en la auditoría del 2026-09-14). */}
                  <div className="mb-5 grid grid-cols-2 gap-3 lg:grid-cols-4">
                    <TarjetaResumen etiqueta="Estado">
                      {jornada ? (JORNADA_ESTADO_LABELS[jornada.estado] ?? jornada.estado) : "Sin jornada"}
                    </TarjetaResumen>
                    <TarjetaResumen etiqueta="Horas">
                      {jornada?.horas_trabajadas != null ? (
                        formatoMinutos(Math.round(jornada.horas_trabajadas * 60))
                      ) : (
                        <span className="flex flex-col gap-0.5">
                          <span>—</span>
                          <span className="text-xs font-normal text-taupe">
                            {jornada ? "aún sin salida" : "sin marcajes"}
                          </span>
                        </span>
                      )}
                    </TarjetaResumen>
                    <TarjetaResumen etiqueta="Tardanza">
                      {/* «—» decía cuatro cosas distintas: puntual, sin jornada, sin
                          horario contra qué medir y aún sin entrada. Ahora cada una
                          se dice, y lo que no se pudo comprobar no se afirma. */}
                      {!jornada ? (
                        <span className="text-sm font-normal text-taupe">sin jornada ese día</span>
                      ) : jornada.minutos_tarde == null ? (
                        <span className="text-sm font-normal text-taupe">
                          {esperado?.origen === "sin_horario" ? "no se mide: sin horario ese día" : "no medible todavía"}
                        </span>
                      ) : jornada.minutos_tarde === 0 ? (
                        // «Puntual» solo si había una hora contra qué medir.
                        esperado?.entrada ? "Puntual" : (
                          <span className="text-sm font-normal text-taupe">
                            {diaFallas.esperado ? "no se pudo comprobar" : "sin hora contra qué medir"}
                          </span>
                        )
                      ) : jornada.minutos_tarde > MINUTOS_MAXIMOS_TARDANZA_MEDIBLE ? (
                        // RIT 17.5: más de 3 h no es una medición confiable; el día no
                        // computa ni se emite documento hasta verificar el horario.
                        <span className="flex flex-col gap-1">
                          <span className="text-taupe">{formatoMinutos(jornada.minutos_tarde)}</span>
                          <span className="text-xs font-normal text-taupe">
                            Más de 3 h: no cuenta como tardanza hasta verificar que el horario era el correcto.
                          </span>
                        </span>
                      ) : levTardanza ? (
                        <span className="flex flex-wrap items-center gap-1.5 text-sm">
                          <s className="text-taupe">{formatoMinutos(jornada.minutos_tarde)}</s>
                          <Insignia variante="positivo" tamano="sm">levantada · {motivoTardLabel(levTardanza.motivo)}</Insignia>
                          <Boton variante="enlace" className="text-xs" onClick={() => void quitarLevantamiento()}>quitar</Boton>
                        </span>
                      ) : diaFallas.levantamiento ? (
                        <span className="flex flex-col gap-1">
                          <span className="text-rojo">{formatoMinutos(jornada.minutos_tarde)}</span>
                          <span className="text-xs font-normal text-taupe">No se pudo comprobar si fue levantada.</span>
                        </span>
                      ) : (
                        <span className="flex flex-wrap items-center gap-1.5">
                          <span className="text-rojo">{formatoMinutos(jornada.minutos_tarde)}</span>
                          <Boton variante="sutil" tamano="sm" className="min-h-11 md:min-h-0"
                            onClick={() => { setLevModal(true); setLevMotivo("fuerza_mayor"); setLevObs(""); }}>
                            Levantar
                          </Boton>
                        </span>
                      )}
                    </TarjetaResumen>
                    <TarjetaResumen etiqueta="Entrada esperada">
                      {esperado?.entrada ? (
                        <span className="flex flex-col gap-1">
                          <span className="flex flex-wrap items-center gap-1.5">
                            <span>{esperado.entrada}</span>
                            <Insignia
                              variante={esperado.origen === "turno" ? "advertencia" : "neutral"}
                              atenuada={esperado.origen !== "turno"}
                              tamano="sm"
                            >
                              {textoOrigen(esperado)}
                            </Insignia>
                          </span>
                          {esperado.origen === "turno" && (
                            <a
                              href={`/admin/turnos?fecha=${fecha}`}
                              className="inline-flex w-fit items-center gap-1 text-xs text-rojo underline decoration-rojo/40 underline-offset-2 hover:decoration-rojo"
                            >
                              Ver en Turnos <ArrowUpRight size={12} strokeWidth={2} aria-hidden />
                            </a>
                          )}
                        </span>
                      ) : diaFallas.esperado ? (
                        <span className="text-sm font-normal text-taupe">no se pudo consultar</span>
                      ) : esperado?.origen === "sin_horario" && !leTocaHorario(personaSel) ? (
                        // A esta persona no le toca horario, y eso es correcto.
                        <span className="text-sm font-normal text-taupe">
                          {personaSel.personal_direccion ? "personal de dirección" : "sin jornada por su vínculo"}
                        </span>
                      ) : esperado?.origen === "sin_horario" ? (
                        <span className="text-sm font-normal text-rojo">sin horario vigente</span>
                      ) : (
                        "—"
                      )}
                    </TarjetaResumen>
                  </div>

                  {/* 0446 — con qué horario se calculó ESTA jornada, tal cual quedó
                      guardado en su momento. Distinto de `esperado` (arriba), que
                      relee `horarios_asignados` EN VIVO para esta fecha: si alguien
                      corrigió el horario retroactivamente después de que esta
                      jornada se calculó, los dos pueden decir cosas distintas — y
                      eso es justo lo que hay que poder ver acá, no adivinar. */}
                  {jornada?.horario_aplicado && (
                    <div className="mb-5 rounded-lg border border-sand bg-hueso px-4 py-2 text-xs text-taupe">
                      Calculado con{" "}
                      {jornada.horario_aplicado.es_descanso ? (
                        <strong className="text-tinta">descanso ese día</strong>
                      ) : jornada.horario_aplicado.entrada ? (
                        <strong className="text-tinta">
                          entrada {jornada.horario_aplicado.entrada.slice(0, 5)}
                          {jornada.horario_aplicado.salida ? `–${jornada.horario_aplicado.salida.slice(0, 5)}` : ""}
                        </strong>
                      ) : (
                        <strong className="text-tinta">sin horario</strong>
                      )}
                      {" "}({jornada.horario_aplicado.fuente === "turnos" ? "turno de ese día" : "horario base"})
                      {/* .slice(0,5): horario_aplicado sale de Postgres con segundos
                          ("08:30:00"), esperado.entrada ya viene truncado a "08:30"
                          — comparar sin normalizar los dos formatos siempre daba
                          "distinto" aunque la hora fuera la misma. */}
                      {esperado && (jornada.horario_aplicado.entrada?.slice(0, 5) ?? null) !== esperado.entrada && (
                        <span className="ml-1.5 text-ambar">
                          — hoy, para esta fecha, {esperado.entrada ? `horarios_asignados dice ${esperado.entrada}` : "ya no hay horario"}: alguien lo cambió después de que esta jornada se calculara.
                        </span>
                      )}
                    </div>
                  )}

                  {/* El texto largo del hueco real (sin horario vigente, y a esta
                      persona SÍ le toca tener uno) se mantiene aparte: es la única
                      de las cuatro tarjetas que necesita una explicación completa,
                      y meterla dentro de la tarjeta la habría desbordado. */}
                  {esperado?.origen === "sin_horario" && leTocaHorario(personaSel) && (
                    <BannerAviso enLinea titulo="Esta persona no tiene horario vigente para esa fecha." className="mb-5 text-taupe">
                      Sin horario no hay contra qué medir: ese día no cuenta tardanza, ni salida
                      anticipada, ni tiempo adicional, aunque tenga horas marcadas. Se carga en Horarios.
                    </BannerAviso>
                  )}

                  <TarjetaInfo className="overflow-hidden p-0 sm:p-0">
                    <h3 className="border-b border-sand px-4 py-2.5 text-sm font-medium">Marcajes del día</h3>
                    {marcajes.length === 0 ? (
                      <p className="px-4 py-4 text-sm text-taupe">No hay marcajes ese día. Puedes agregar uno abajo.</p>
                    ) : (
                      <Tabla className="rounded-none border-none">
                        <TablaEncabezado>
                          <Th>Tipo</Th>
                          <Th>Hora</Th>
                          <Th className="hidden sm:table-cell">Origen</Th>
                          <Th>Acciones</Th>
                        </TablaEncabezado>
                        <tbody>
                          {marcajes.map((m) => {
                            const anulada = m.anulada_at !== null;
                            const horaLocal = horasEditadas[m.id] ?? horaInput(m.timestamp_marca);
                            const tipoLocal = tiposEditados[m.id] ?? m.tipo;
                            const cambiada = horaLocal !== horaInput(m.timestamp_marca) || tipoLocal !== m.tipo;
                            const esAutoCierrePendiente = m.origen === "auto_cierre" && m.estado_revision === "pendiente_revision";
                            const opciones = TIPOS_DE_LA_FAMILIA(m.tipo);
                            return (
                              <Fila key={m.id} className={anulada ? "opacity-55" : undefined}>
                                <td className="px-4 py-2">
                                  {anulada || opciones.length === 1 ? (
                                    <span className={anulada ? "line-through" : undefined}>{TIPO_MARCA_LABELS[m.tipo]}</span>
                                  ) : (
                                    // Solo tipos de su misma familia: una entrada no puede volverse salida.
                                    // Select compacto DENTRO de la tabla: se deja a mano a propósito —
                                    // CampoSelect fuerza w-full y un padding pensado para un formulario
                                    // suelto (px-3 py-2 + flecha), no para una celda angosta; usarlo acá
                                    // habría ensanchado cada fila de esta tabla, la más usada del panel.
                                    <select value={tipoLocal}
                                      onChange={(e) => setTiposEditados({ ...tiposEditados, [m.id]: e.target.value as TipoMarca })}
                                      className="rounded-control border border-sand bg-hueso px-2 py-1 text-sm text-tinta">
                                      {opciones.map((t) => <option key={t} value={t}>{TIPO_MARCA_LABELS[t]}</option>)}
                                    </select>
                                  )}
                                  <p className="mt-0.5 text-xs text-taupe sm:hidden">{ORIGEN_MARCA_LABELS[m.origen] ?? m.origen}</p>
                                  {m.origen === "auto_cierre" && <Insignia variante="alerta" tamano="sm" className="ml-2">auto-cierre</Insignia>}
                                  {m.origen === "admin_correccion" && <Insignia variante="neutral" atenuada tamano="sm" className="ml-2">manual</Insignia>}
                                  {m.origen === "auto_cierre" && m.estado_revision === "revisada" && !anulada && (
                                    <Insignia variante="positivo" tamano="sm" className="ml-2">confirmada</Insignia>
                                  )}
                                  {anulada && (
                                    <p className="mt-1 text-xs text-taupe">Anulada · {m.anulada_motivo}</p>
                                  )}
                                </td>
                                <td className="px-4 py-2">
                                  {anulada ? (
                                    <span className="line-through text-taupe">{horaTextoLima(m.timestamp_marca)}</span>
                                  ) : (
                                    // Mismo motivo que el select de arriba: se deja como input a mano.
                                    <input type="time" value={horaLocal}
                                      onChange={(e) => setHorasEditadas({ ...horasEditadas, [m.id]: e.target.value })}
                                      className="rounded-control border border-sand bg-hueso px-2 py-1 text-sm text-tinta" />
                                  )}
                                </td>
                                <td className="hidden px-4 py-2 text-taupe sm:table-cell">{ORIGEN_MARCA_LABELS[m.origen] ?? m.origen}</td>
                                <td className="px-4 py-2">
                                  <div className="flex flex-wrap gap-2">
                                    {anulada ? (
                                      <Boton
                                        variante="secundario" tamano="sm" className="min-h-11 md:min-h-0"
                                        onClick={() => { setAccion({ modo: "reactivar", marcaje: m }); setMotivo(""); }}
                                        title="Devolver esta marca al cálculo del día">
                                        Reactivar
                                      </Boton>
                                    ) : (
                                      <>
                                        <Boton
                                          variante="secundario" tamano="sm" className="min-h-11 md:min-h-0"
                                          disabled={!cambiada}
                                          onClick={() => {
                                            const nuevoTs = construirTs(fecha, horaLocal);
                                            const posteriores = tipoLocal === "salida_final"
                                              ? marcajes.filter((x) => x.id !== m.id && x.anulada_at === null
                                                  && new Date(x.timestamp_marca) > new Date(nuevoTs))
                                              : [];
                                            setAccion({ modo: "editar", marcaje: m, nuevaHora: horaLocal, nuevoTipo: tipoLocal, posteriores });
                                            setAnularPosteriores(Object.fromEntries(posteriores.map((x) => [x.id, true])));
                                            setMotivo("");
                                          }}>
                                          Guardar
                                        </Boton>
                                        {esAutoCierrePendiente && (
                                          <Boton
                                            variante="secundario" tamano="sm" className="min-h-11 md:min-h-0"
                                            onClick={() => { setAccion({ modo: "confirmar", marcaje: m }); setMotivo(""); }}
                                            title="Esa es su salida final: el día deja de estar pendiente y pasa a medirse entero">
                                            Confirmar
                                          </Boton>
                                        )}
                                        <Boton
                                          variante="peligro" tamano="sm" className="min-h-11 md:min-h-0"
                                          onClick={() => { setAccion({ modo: "anular", marcaje: m }); setMotivo(""); }}
                                          title="La marca deja de contar, pero se queda en el historial con su motivo">
                                          Anular
                                        </Boton>
                                      </>
                                    )}
                                  </div>
                                </td>
                              </Fila>
                            );
                          })}
                        </tbody>
                      </Tabla>
                    )}
                  </TarjetaInfo>

                  {/* Agregar marcaje faltante */}
                  <TarjetaInfo className="mt-4" titulo="Agregar un marcaje faltante">
                    <div className="flex flex-wrap items-end gap-3">
                      <CampoSelect
                        etiqueta="Tipo" value={agregarTipo}
                        onChange={(e) => setAgregarElegido({ ...agregarYaElegido, tipo: e.target.value as TipoMarca })}>
                        {TIPOS_AGREGABLES.map((t) => <option key={t} value={t}>{TIPO_MARCA_LABELS[t]}</option>)}
                      </CampoSelect>
                      {/* La etiqueta dice de dónde salió la hora mientras nadie la
                          haya tocado: un valor que llega solo tiene que decirlo. */}
                      <Campo
                        etiqueta={agregarYaElegido.hora === undefined && agregarHoraDelHorario ? "Hora · según su horario" : "Hora"}
                        type="time" value={agregarHora}
                        onChange={(e) => setAgregarElegido({ ...agregarYaElegido, hora: e.target.value })} />
                      {agregarTipo === "salida_otro" && (
                        <Campo
                          etiqueta="Motivo de la salida"
                          value={agregarMotivoOtro}
                          onChange={(e) => setAgregarMotivoOtro(e.target.value)}
                          placeholder="ej. trámite banco"
                        />
                      )}
                      <Boton
                        variante="primario"
                        onClick={() => { setAccion({ modo: "agregar", tipo: agregarTipo, hora: agregarHora, motivoOtro: agregarMotivoOtro }); setMotivo(""); }}>
                        Agregar
                      </Boton>
                    </div>
                  </TarjetaInfo>

                  {/* Historial de correcciones: el motivo de cada cambio, quién y cuándo.
                      Es donde se LEE la auditoría que cada corrección va guardando.
                      Lo que NO viene de una RPC de esta pantalla (hoy, cambios de
                      turno hechos desde Turnos) lleva su propia insignia "otro
                      sistema": responde "qué le tocaba trabajar", no "qué marcó" —
                      aprobado en la segunda ronda de la auditoría, 2026-09-14. */}
                  <TarjetaInfo className="mt-4 overflow-hidden p-0 sm:p-0">
                    <div className="flex flex-wrap items-center justify-between gap-2 border-b border-sand px-4 py-2.5">
                      <h3 className="text-sm font-medium">
                        Historial de correcciones · {personaSel.nombres} {personaSel.apellidos}
                      </h3>
                      <div className="flex gap-1" role="group" aria-label="Qué cambios ver">
                        {([["marcajes", "Marcajes"], ["todo", "Todo"]] as const).map(([v, etiqueta]) => (
                          <Filtro
                            key={v} tamano="sm" className="min-h-11 md:min-h-0"
                            activo={auditoriaVista === v}
                            onClick={() => setAuditoriaVista(v)}
                          >
                            {etiqueta}
                          </Filtro>
                        ))}
                      </div>
                    </div>
                    {auditoriaVista === "marcajes" && auditoriaOtros > 0 && !auditoriaError && (
                      <p className="border-b border-sand bg-hueso px-4 py-2 text-xs text-taupe">
                        Además hay {auditoriaOtros} {auditoriaOtros === 1 ? "cambio" : "cambios"} de otros temas (horario, contrato, educación…) que no son de marcajes.{" "}
                        <Boton variante="enlace" className="text-xs font-medium" onClick={() => setAuditoriaVista("todo")}>Verlos</Boton>
                      </p>
                    )}
                    {auditoriaError ? (
                      <p className="px-4 py-4 text-sm text-rojo">
                        No se pudo cargar el historial de correcciones. <Boton variante="enlace" className="font-medium" onClick={() => void cargarAuditoria()}>Reintentar</Boton>
                      </p>
                    ) : auditoria.length === 0 ? (
                      <p className="px-4 py-4 text-sm text-taupe">
                        {auditoriaVista === "marcajes" ? "Esta persona no tiene correcciones de marcajes registradas." : "Esta persona no tiene cambios registrados."}
                      </p>
                    ) : (
                      <ul className="divide-y divide-sand">
                        {auditoria.map((row) => {
                          const { accion, cuando, detalle } = describirCambio(row);
                          const esDeMarcaje = esCampoDeMarcaje(row.campo_modificado);
                          return (
                            <li key={row.id} className="px-4 py-3 text-sm">
                              <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-0.5">
                                {/* Izquierda: el día del MARCAJE que se tocó. Derecha: cuándo se
                                    hizo la corrección — de ahí el «corregido», que antes faltaba y
                                    dejaba las dos fechas pareciendo la misma. */}
                                <span className="font-medium">
                                  {!esDeMarcaje && <Insignia variante="informativo" tamano="sm" className="mr-1.5">{TEMA_AUDITORIA_LABELS[temaDeCampo(row.campo_modificado)]}</Insignia>}
                                  {accion}
                                  {cuando && <span className="font-normal text-taupe"> · del {cuando}</span>}
                                  <span className="font-normal text-taupe"> · {detalle}</span>
                                </span>
                                <span className="text-xs text-taupe">
                                  corregido {selloLima(row.corregido_at)} · por {nombrePorId.get(row.corregido_por) ?? "alguien fuera de tu lista"}
                                </span>
                              </div>
                              <p className="mt-1 text-taupe">“{row.motivo}”</p>
                            </li>
                          );
                        })}
                      </ul>
                    )}
                    {/* Si llegaron tantas filas como se pidieron, probablemente hay más
                        atrás: no hay conteo total, así que es una pista, no una certeza. */}
                    {!auditoriaError && auditoria.length >= auditoriaLimite && (
                      <div className="border-t border-sand px-4 py-2.5 text-center">
                        <Boton
                          variante="enlace" className="min-h-11 text-xs font-medium md:min-h-0"
                          onClick={() => setAuditoriaMas((m) => ({ ...m, [personaId]: auditoriaLimite + 30 }))}
                        >
                          Cargar 30 más
                        </Boton>
                      </div>
                    )}
                  </TarjetaInfo>
                </>
              )}
            </div>
          )}
        </div>
      </div>

      {/* Modal: levantar tardanza (no cambia la hora). Antes era una
          reimplementación a mano (z-20, propia entre los 4 pisos distintos
          del panel) — ahora usa <Modal>, que fija un solo piso (z-40) y un
          solo velo para todos los diálogos del sistema. */}
      <Modal abierto={levModal} onCerrar={() => setLevModal(false)} bloqueado={levGuardando} titulo="Levantar tardanza" ancho="sm">
        <p className="mb-4 text-sm text-taupe">
          Se perdona la tardanza: deja de contar para la escalera disciplinaria y para el umbral del mes.
          <strong> La hora real no se toca</strong> — queda tachada con su motivo.
        </p>
        <div className="mb-3">
          <CampoSelect etiqueta="Motivo" value={levMotivo} onChange={(e) => setLevMotivo(e.target.value)}>
            {MOTIVOS_TARD.map((m) => <option key={m.valor} value={m.valor}>{m.label}</option>)}
          </CampoSelect>
        </div>
        <label className="mb-4 flex flex-col gap-1 text-sm">
          Observación {levMotivo === "otro" ? <span className="text-rojo">(obligatoria)</span> : <span className="text-taupe">(opcional)</span>}
          <AreaTexto value={levObs} onChange={(e) => setLevObs(e.target.value)} rows={2} placeholder="ej. paro de transporte" />
        </label>
        <div className="flex justify-end gap-2">
          <Boton onClick={() => setLevModal(false)} disabled={levGuardando}>Cancelar</Boton>
          <Boton variante="primario" onClick={() => void levantarTardanza()} cargando={levGuardando}>Levantar</Boton>
        </div>
      </Modal>

      {/* Modal: motivo de la corrección. Era el otro piso suelto (z-10, el
          más bajo del sistema) para la acción que decide si un marcaje se
          edita o se anula — ahora también hereda z-40 + max-h-[90vh] del
          primitivo, así que la lista de marcas posteriores nunca se corta
          arriba y abajo a la vez en una pantalla chica. */}
      <Modal
        abierto={accion !== null}
        onCerrar={() => setAccion(null)}
        bloqueado={procesando}
        titulo={accion ? (
          accion.modo === "editar" ? "Confirmar la corrección"
            : accion.modo === "anular" ? "Anular esta marca"
            : accion.modo === "reactivar" ? "Devolver esta marca al día"
            : accion.modo === "confirmar" ? "Confirmar la salida del auto-cierre"
            : "Agregar marcaje"
        ) : undefined}
      >
        {accion && (
          <>
            <p className="mb-4 text-sm text-taupe">
              {accion.modo === "editar" && [
                accion.nuevoTipo !== accion.marcaje.tipo
                  ? `${TIPO_MARCA_LABELS[accion.marcaje.tipo]} → ${TIPO_MARCA_LABELS[accion.nuevoTipo]}`
                  : TIPO_MARCA_LABELS[accion.marcaje.tipo],
                accion.nuevaHora !== horaInput(accion.marcaje.timestamp_marca)
                  ? `hora: ${horaInput(accion.marcaje.timestamp_marca)} → ${accion.nuevaHora}`
                  : null,
              ].filter(Boolean).join(" · ")}
              {accion.modo === "anular" && `${TIPO_MARCA_LABELS[accion.marcaje.tipo]} de las ${horaInput(accion.marcaje.timestamp_marca)}. Dejará de contar para el día, pero se queda en el historial y puedes deshacerlo.`}
              {accion.modo === "reactivar" && `${TIPO_MARCA_LABELS[accion.marcaje.tipo]} de las ${horaInput(accion.marcaje.timestamp_marca)}. Volverá a contar para el cálculo del día.`}
              {accion.modo === "confirmar" && `Das por buena la salida de las ${horaInput(accion.marcaje.timestamp_marca)} que puso el sistema. El día deja de estar pendiente y pasa a medirse entero, incluida la salida anticipada y el tiempo adicional.`}
              {accion.modo === "agregar" && `${TIPO_MARCA_LABELS[accion.tipo]} a las ${accion.hora}, para ${personaSel?.nombres} ${personaSel?.apellidos}.`}
            </p>
            {accion.modo === "editar" && accion.posteriores.length > 0 && (
              <BannerAviso enLinea className="mb-4">
                <p className="mb-2 text-taupe">
                  Después de esa salida final quedan {accion.posteriores.length}{" "}
                  {accion.posteriores.length === 1 ? "marca" : "marcas"}. Se anularán con el mismo
                  motivo; desmarca la que quieras conservar.
                </p>
                {/* Casilla suelta: no hay CampoCasilla todavía en components/ui/campo.tsx
                    (Fase A no la agregó pese a lo anunciado) — se deja con las clases que
                    ese primitivo va a necesitar (accent-tinta, size-4) para que migrar sea
                    trivial en cuanto exista. Ver 'pendientes'. */}
                {accion.posteriores.map((post) => (
                  <label key={post.id} className="flex items-center gap-2 py-0.5">
                    <input type="checkbox"
                      checked={anularPosteriores[post.id] ?? false}
                      onChange={(e) => setAnularPosteriores({ ...anularPosteriores, [post.id]: e.target.checked })}
                      className="size-4 rounded border-sand accent-tinta" />
                    <span>
                      {TIPO_MARCA_LABELS[post.tipo]} de las {horaInput(post.timestamp_marca)}
                      {post.origen === "auto_cierre" && " (auto-cierre)"}
                    </span>
                  </label>
                ))}
              </BannerAviso>
            )}
            <label className="mb-4 flex flex-col gap-1 text-sm">
              Motivo (obligatorio)
              <AreaTexto value={motivo} onChange={(e) => setMotivo(e.target.value)} rows={2} autoFocus placeholder="ej. el reloj del terminal estaba adelantado" />
            </label>
            <div className="flex justify-end gap-3">
              <Boton onClick={() => setAccion(null)} disabled={procesando}>Cancelar</Boton>
              <Boton variante="primario" onClick={ejecutar} cargando={procesando}>Confirmar</Boton>
            </div>
          </>
        )}
      </Modal>

      <Modal
        abierto={masivaAbierta}
        onCerrar={() => setMasivaAbierta(false)}
        bloqueado={resolviendo !== null}
        titulo="Registrar todas las marcas apartadas"
        ancho="sm"
      >
        <p className="mb-4 text-sm text-taupe">
          Vas a registrar <strong className="text-tinta">{apartadas.length} marcas</strong> con su hora original, en orden.
          Si alguna no corresponde (por ejemplo, ya se corrigió a mano), la base la rechaza y queda en la lista.
        </p>
        <label className="mb-4 flex flex-col gap-1 text-sm">
          Motivo (obligatorio, queda en el historial)
          <AreaTexto value={apartadaMotivo} onChange={(e) => setApartadaMotivo(e.target.value)} rows={2} autoFocus placeholder="ej. el terminal estaba mal vinculado" />
        </label>
        <div className="flex justify-end gap-3">
          <Boton onClick={() => setMasivaAbierta(false)} disabled={resolviendo !== null}>Cancelar</Boton>
          <Boton variante="primario" onClick={() => void resolverTodasApartadas()} cargando={resolviendo !== null}>Registrar todas</Boton>
        </div>
      </Modal>

      {/* Modal: motivo para resolver una marca apartada. Reemplaza el
          window.prompt() que pedía este mismo motivo en un diálogo nativo
          del navegador — Felipe aprobó migrar todos los diálogos nativos
          del panel a este primitivo (ver CLAUDE.md). */}
      <Modal
        abierto={apartadaAccion !== null}
        onCerrar={() => setApartadaAccion(null)}
        bloqueado={resolviendo !== null}
        titulo={apartadaAccion?.resolucion === "repuesta" ? "Registrar la marca con su hora" : "Declarar improcedente"}
        ancho="sm"
      >
        {apartadaAccion && (
          <>
            <p className="mb-4 text-sm text-taupe">
              {apartadaAccion.resolucion === "repuesta" ? (
                <>Vas a registrar la marca de <strong className="text-tinta">{apartadaAccion.marca.persona}</strong>{" "}
                  con su hora original: {horaTextoLima(apartadaAccion.marca.timestamp_cliente)} del {apartadaAccion.marca.fecha}.</>
              ) : (
                <>Vas a declarar <strong className="text-rojo">IMPROCEDENTE</strong> la marca de{" "}
                  {apartadaAccion.marca.persona} del {apartadaAccion.marca.fecha} a las{" "}
                  {horaTextoLima(apartadaAccion.marca.timestamp_cliente)}. No se va a registrar ningún marcaje.</>
              )}
            </p>
            <label className="mb-4 flex flex-col gap-1 text-sm">
              Motivo (obligatorio, queda en el historial)
              <AreaTexto value={apartadaMotivo} onChange={(e) => setApartadaMotivo(e.target.value)} rows={2} autoFocus placeholder="ej. el terminal se quedó sin señal" />
            </label>
            <div className="flex justify-end gap-3">
              <Boton onClick={() => setApartadaAccion(null)} disabled={resolviendo !== null}>Cancelar</Boton>
              <Boton
                variante={apartadaAccion.resolucion === "repuesta" ? "primario" : "peligro"}
                onClick={() => void resolverApartada()}
                cargando={resolviendo !== null}
              >
                {apartadaAccion.resolucion === "repuesta" ? "Registrar" : "Declarar improcedente"}
              </Boton>
            </div>
          </>
        )}
      </Modal>
    </div>
  );
}
