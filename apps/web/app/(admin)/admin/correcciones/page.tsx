"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { ROLES_DO, TIPOS_MARCA, TIPO_MARCA_LABELS, TZ_LIMA, puedeOperarEquipo, type TipoMarca } from "@cayla-dynamic/shared";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { esperadoDelDia, type Esperado, type HorarioTramo, type TurnoDia } from "@/lib/admin/jornada-esperada";
import { AdminNav } from "../nav";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { useToast } from "@/components/toast";


function fechaHoyLima() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: TZ_LIMA }).format(new Date());
}
// "HH:MM" en hora Lima para el input de tipo time
function horaInput(tsISO: string) {
  return new Intl.DateTimeFormat("en-GB", { timeZone: TZ_LIMA, hour: "2-digit", minute: "2-digit", hour12: false }).format(new Date(tsISO));
}
// fecha (YYYY-MM-DD) + "HH:MM" -> ISO con offset fijo de Perú (-05:00)
function construirTs(fecha: string, horaHHMM: string) {
  return `${fecha}T${horaHHMM}:00-05:00`;
}
// Un timestamptz guardado como texto crudo en la auditoría (ej. "2026-07-18
// 19:15:00+00") o un ISO -> hora Lima "hh:mm a.m.". Tolera el espacio en vez de
// T y offsets cortos como "-05"; si aun así no parsea, muestra el texto crudo.
function horaTextoLima(s: string | null): string {
  if (!s) return "—";
  const t = s.trim().replace(" ", "T").replace(/([+-]\d{2})$/, "$1:00");
  const d = new Date(t);
  if (isNaN(d.getTime())) return s;
  return new Intl.DateTimeFormat("es-PE", { timeZone: TZ_LIMA, hour: "2-digit", minute: "2-digit", hour12: true }).format(d);
}
// Sello de auditoría: cuándo se hizo el cambio (fecha corta + hora Lima).
function selloLima(iso: string): string {
  const d = new Date(iso);
  if (isNaN(d.getTime())) return iso;
  return new Intl.DateTimeFormat("es-PE", { timeZone: TZ_LIMA, day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit", hour12: true }).format(d);
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
  const base = e.origen === "turno" ? "turno del día"
    : e.origen === "sin_horario" ? "sin horario vigente"
    : "horario base";
  return e.trabaja ? base : `descanso (${base})`;
}

interface Persona { id: string; nombres: string; apellidos: string; rol: string; sede_base_id: string; }
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
/** Día que el sistema selló solo, por haber quedado con una secuencia imposible (mig. 0068). */
interface DiaPorRevisar { persona_id: string; nombre: string; sede: string; fecha: string; marcas: number; periodo_pagado: boolean; }

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
interface Jornada { estado: string; horas_trabajadas: number | null; minutos_tarde: number | null; }
// Fila de correcciones_auditoria (el registro de quién cambió qué, cuándo y por qué).
// Sin embeds de PostgREST a propósito: en este repo el schema cache está trabado
// para varias relaciones, así que el nombre de quién corrigió se resuelve aparte
// desde la lista de personas ya cargada (ver `nombrePorId`).
interface Auditoria {
  id: string;
  campo_modificado: string;
  valor_anterior: string | null;
  valor_nuevo: string | null;
  corregido_at: string;
  motivo: string;
  corregido_por: string; // id de quien hizo el cambio
}
// Traduce una fila de auditoría a lenguaje llano: qué acción fue y su detalle.
// El tipo de marcaje ya viene embebido en el valor de agregado/eliminado
// ("entrada @ ts"); para una hora corregida solo cambian las horas.
function describirCambio(row: Auditoria): { accion: string; detalle: string } {
  const lblTipo = (t?: string | null) => (t && TIPO_MARCA_LABELS[t as TipoMarca]) || t || "marcaje";
  if (row.campo_modificado === "timestamp_marca") {
    return { accion: "Hora corregida", detalle: `${horaTextoLima(row.valor_anterior)} → ${horaTextoLima(row.valor_nuevo)}` };
  }
  if (row.campo_modificado === "marcaje_agregado") {
    const [tipo, ts] = (row.valor_nuevo ?? "").split(" @ ");
    return { accion: "Marcaje agregado", detalle: `${lblTipo(tipo)} a las ${horaTextoLima(ts)}` };
  }
  if (row.campo_modificado === "marcaje_eliminado") {
    const [tipo, ts] = (row.valor_anterior ?? "").split(" @ ");
    return { accion: "Marcaje eliminado", detalle: `${lblTipo(tipo)} de las ${horaTextoLima(ts)}` };
  }
  return { accion: row.campo_modificado, detalle: `${row.valor_anterior ?? ""} → ${row.valor_nuevo ?? ""}` };
}

// Tipos que un admin puede agregar manualmente (los pares salida/retorno y entrada/salida final)
const TIPOS_AGREGABLES = TIPOS_MARCA;

type Accion =
  | { modo: "editar"; marcaje: Marcaje; nuevaHora: string; nuevoTipo: TipoMarca; posteriores: Marcaje[] }
  | { modo: "anular"; marcaje: Marcaje }
  | { modo: "reactivar"; marcaje: Marcaje }
  | { modo: "confirmar"; marcaje: Marcaje }
  | { modo: "agregar"; tipo: TipoMarca; hora: string; motivoOtro: string };

export default function CorreccionesPage() {
  const router = useRouter();
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [personaId, setPersonaId] = useState("");
  const [fecha, setFecha] = useState(fechaHoyLima());
  const [marcajes, setMarcajes] = useState<Marcaje[]>([]);
  const [jornada, setJornada] = useState<Jornada | null>(null);
  const [auditoria, setAuditoria] = useState<Auditoria[]>([]); // últimas correcciones de esta persona
  const [auditoriaError, setAuditoriaError] = useState(false); // para no confundir "sin correcciones" con "no cargó"
  // Contra qué hora se mide la tardanza ese día y de dónde sale (turno del día vs
  // horario base) — para que "N min tarde" nunca sea un número sin contexto.
  const [esperado, setEsperado] = useState<Esperado | null>(null);
  // Levantamiento de tardanza de ese día (perdón por fuerza mayor): si existe, la
  // tardanza se muestra tachada y no cuenta. La hora real NO se toca.
  const [levTardanza, setLevTardanza] = useState<{ motivo: string; observacion: string | null } | null>(null);
  const [levModal, setLevModal] = useState(false);
  const [levMotivo, setLevMotivo] = useState("fuerza_mayor");
  const [levObs, setLevObs] = useState("");
  const [levGuardando, setLevGuardando] = useState(false);
  const [cargado, setCargado] = useState(false);
  const [cargando, setCargando] = useState(false);
  const [autoCargar, setAutoCargar] = useState(false); // deep-link: cargar solo al llegar con ?persona=&fecha=
  const { avisar } = useToast();
  // Días sellados por el sistema (secuencia imposible). Sin esta lista el sello
  // sería inútil: nadie va a revisar persona por persona adivinando cuál quedó mal.
  const [porRevisar, setPorRevisar] = useState<DiaPorRevisar[]>([]);
  // Marcas que el terminal no logró enviar y apartó (0304). Hasta esa migración
  // vivían en el IndexedDB de una Mac mini y nadie podía verlas desde acá.
  const [apartadas, setApartadas] = useState<MarcaApartada[]>([]);
  const [resolviendo, setResolviendo] = useState<string | null>(null);
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
  // formulario "agregar marcaje"
  const [agregarTipo, setAgregarTipo] = useState<TipoMarca>("entrada");
  const [agregarHora, setAgregarHora] = useState("08:00");
  const [agregarMotivoOtro, setAgregarMotivoOtro] = useState("");

  useEffect(() => {
    const supabase = createAdminSupabaseClient();
    supabase.auth.getSession().then(async ({ data }) => {
      if (!data.session) { router.replace("/admin/login"); return; }
      const { data: p } = await supabase
        .from("personas").select("id, nombres, apellidos, rol, sede_base_id").eq("estado", "activo").order("nombres");
      setPersonas((p as Persona[]) ?? []);
      // Días sellados por el sistema. Falla suave a propósito: si la base todavía
      // no tiene la migración 0068, la pantalla sigue funcionando igual (sin lista).
      const { data: dr } = await supabase.rpc("fn_dias_por_revisar", { p_limite: 50 });
      setPorRevisar((dr as DiaPorRevisar[]) ?? []);
      // Falla suave igual que la de arriba: sin la 0304 la pantalla funciona
      // igual, solo que sin esta lista.
      const { data: ap } = await supabase.rpc("fn_marcas_apartadas");
      setApartadas((ap as unknown as MarcaApartada[]) ?? []);
    });
  }, [router]);

  async function resolverApartada(m: MarcaApartada, resolucion: "repuesta" | "improcedente") {
    const pregunta = resolucion === "repuesta"
      ? `Vas a registrar la marca de ${m.persona} con su hora original: ${horaTextoLima(m.timestamp_cliente)} del ${m.fecha}.\n\n¿Por qué? (queda en el historial)`
      : `Vas a declarar IMPROCEDENTE la marca de ${m.persona} del ${m.fecha} a las ${horaTextoLima(m.timestamp_cliente)}.\n\nNo se va a registrar ningún marcaje. ¿Por qué?`;
    const motivo = window.prompt(pregunta, "");
    if (motivo === null) return;
    if (motivo.trim().length < 3) {
      avisar("error", "Escribe el motivo: esto decide si un día de trabajo queda registrado o no.");
      return;
    }

    setResolviendo(m.id);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_marca_apartada_resolver", {
      p_id: m.id, p_resolucion: resolucion, p_motivo: motivo.trim(),
    });
    setResolviendo(null);

    if (error) {
      // El error de fn_registrar_marcaje sube tal cual: si el día está en un
      // periodo pagado, por ejemplo, hay que reabrirlo antes — y eso es lo que
      // dice el mensaje. La marca NO queda como resuelta.
      avisar("error", mensajeDeError(error, "resolver la marca apartada"));
      return;
    }

    const { data: ap } = await supabase.rpc("fn_marcas_apartadas");
    setApartadas((ap as unknown as MarcaApartada[]) ?? []);
    avisar(
      "ok",
      resolucion === "repuesta"
        ? `Marca registrada con su hora original. El aviso del terminal bajará solo en unos minutos.`
        : `Declarada improcedente. No se registró ningún marcaje, y queda el motivo en el historial.`,
    );
    if (m.persona_id === personaId && m.fecha === fecha) void cargarDia();
  }

  const cargarDia = useCallback(async () => {
    if (!personaId) return;
    setCargando(true);
    const supabase = createAdminSupabaseClient();
    const inicio = `${fecha}T00:00:00-05:00`;
    const fin = `${fecha}T23:59:59-05:00`;
    const [{ data: incoh }, { data: mk, error: errMk }, { data: jor, error: errJor }, { data: aud, error: errAud }, { data: turno }, { data: horario }, { data: levT }] = await Promise.all([
      supabase.rpc("fn_dia_incoherente", { p_persona_id: personaId, p_fecha: fecha }),
      supabase.from("marcajes")
        .select("id, tipo, motivo_otro, timestamp_marca, origen, estado_revision, anulada_at, anulada_por, anulada_motivo")
        .eq("persona_id", personaId).gte("timestamp_marca", inicio).lte("timestamp_marca", fin)
        .order("timestamp_marca"),
      supabase.from("jornadas")
        .select("estado, horas_trabajadas, minutos_tarde")
        .eq("persona_id", personaId).eq("fecha", fecha).maybeSingle(),
      // Historial de correcciones de la persona. Columnas planas (sin embeds: el
      // schema cache está trabado). Falla suave: si no llega, no bloquea el día,
      // pero se marca el error para NO mostrar "sin correcciones" en falso.
      supabase.from("correcciones_auditoria")
        .select("id, campo_modificado, valor_anterior, valor_nuevo, corregido_at, motivo, corregido_por")
        .eq("persona_id", personaId).order("corregido_at", { ascending: false }).limit(30),
      // Contra qué se mide la tardanza ese día: el turno puntual manda sobre el
      // horario base (misma prioridad que fn_recalcular_jornada, espejada en
      // jornada-esperada.ts). Fallan suave.
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
    ]);
    if (errMk || errJor) {
      setCargando(false);
      avisar("error", `No se pudo cargar el día: ${(errMk ?? errJor)!.message}`);
      return; // no pisa `marcajes`/`jornada` con datos parciales
    }
    setMarcajes((mk as Marcaje[]) ?? []);
    // Falla suave: si la consulta no llega, no se inventa un sello que no sabemos si existe.
    setDiaIncoherente(incoh === true);
    setJornada((jor as Jornada) ?? null);
    setEsperado(esperadoDelDia(fecha, (turno as TurnoDia) ?? null, (horario as HorarioTramo) ?? null));
    setLevTardanza((levT as { motivo: string; observacion: string | null } | null) ?? null);
    setAuditoriaError(Boolean(errAud));
    setAuditoria(errAud ? [] : ((aud as Auditoria[]) ?? []));
    setHorasEditadas(Object.fromEntries(((mk as Marcaje[]) ?? []).map((m) => [m.id, horaInput(m.timestamp_marca)])));
    setCargado(true);
    setCargando(false);
  }, [personaId, fecha, avisar]);

  // Deep-link: al llegar con ?persona=<id>&fecha=<YYYY-MM-DD> (desde un incidente del
  // dashboard), precarga esa persona y fecha y abre el día listo para corregir.
  useEffect(() => {
    if (personas.length === 0) return;
    const sp = new URLSearchParams(window.location.search);
    const pid = sp.get("persona");
    const f = sp.get("fecha");
    if (pid) {
      setPersonaId(pid);
      if (f) setFecha(f);
      setAutoCargar(true);
    }
  }, [personas]);

  useEffect(() => {
    if (autoCargar && personaId) {
      void cargarDia();
      setAutoCargar(false);
    }
  }, [autoCargar, personaId, cargarDia]);

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
      await cargarDia();
      return;
    }
    setAccion(null);
    setMotivo("");
    setAnularPosteriores({});
    await cargarDia();
    avisar("ok", anuladas > 0
      ? `Corrección guardada y ${anuladas} ${anuladas === 1 ? "marca anulada" : "marcas anuladas"}. Todo queda en la auditoría.`
      : "Corrección guardada y registrada en la auditoría.");
  }

  const personaSel = useMemo(() => personas.find((p) => p.id === personaId), [personas, personaId]);
  // Nombre de quién hizo cada corrección, resuelto desde la lista ya cargada
  // (evita depender de un embed de PostgREST que el schema cache puede no exponer).
  const nombrePorId = useMemo(() => new Map(personas.map((p) => [p.id, `${p.nombres} ${p.apellidos}`])), [personas]);
  const puedeCorregir = puedeOperarEquipo(rol);
  const esSupervisor = rol === "supervisor_sede";

  // Una encargada no puede corregir su propia asistencia ni la de un admin.
  const personasCorregibles = useMemo(() => {
    if (!esSupervisor || !yo) return personas;
    return personas.filter((p) => p.id !== yo.id && !ROLES_DO.includes(p.rol));
  }, [personas, esSupervisor, yo]);

  if (rol !== null && !puedeCorregir) {
    return (
      <div className="flex min-h-screen flex-col">
        <AdminNav />
        <main className="flex flex-1 items-center justify-center p-6">
          <p className="max-w-md text-center text-taupe">
            No tienes permiso para corregir marcajes. Si necesitas un cambio, pídeselo a Felipe o Carlos.
          </p>
        </main>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <h1 className="mb-1 font-serif text-2xl">Corregir marcajes</h1>
        <p className="mb-5 max-w-2xl text-sm text-taupe">
          Ajusta la hora de entrada/salida, agrega un marcaje olvidado o elimina un duplicado.
          Cada cambio pide un motivo y queda registrado (quién, qué y cuándo).
        </p>

        {/* Va ARRIBA de los días por revisar: aquellos son días que existen y
            están desordenados; estas son marcas que NO existen todavía. Si nadie
            las repone, ese día se paga como si la persona no hubiera venido. */}
        {apartadas.length > 0 && (
          <div className="mb-6 max-w-3xl rounded-xl border border-rojo/40 bg-rojo/5 p-4">
            <p className="text-sm font-medium text-tinta">
              {apartadas.length === 1
                ? "1 marca no llegó a registrarse"
                : `${apartadas.length} marcas no llegaron a registrarse`}
            </p>
            <p className="mb-3 mt-1 text-xs leading-relaxed text-taupe">
              El terminal las intentó seis veces y las apartó para no perderlas. La persona sí marcó:
              mientras no se repongan, ese día se paga como si no hubiera venido.
            </p>
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
                  <div className="mt-2 flex flex-wrap gap-2 text-xs">
                    <button
                      onClick={() => void resolverApartada(m, "repuesta")}
                      disabled={resolviendo === m.id}
                      className="rounded border border-tinta/30 px-2 py-1 font-medium hover:bg-sand/50 disabled:opacity-50"
                    >
                      {resolviendo === m.id ? "Registrando…" : "Registrarla con su hora"}
                    </button>
                    <button
                      onClick={() => void resolverApartada(m, "improcedente")}
                      disabled={resolviendo === m.id}
                      className="rounded border border-rojo/30 px-2 py-1 text-rojo hover:bg-rojo/10 disabled:opacity-50"
                    >
                      No corresponde
                    </button>
                  </div>
                </li>
              ))}
            </ul>
          </div>
        )}

        {(() => {
          // Un día de un periodo ya pagado no tiene acción posible (fn_anular_marcaje
          // lo rechaza), así que no entra a este aviso: Felipe pidió que dejara de
          // estorbar la vista. Sigue existiendo en fn_dias_por_revisar por si algún
          // día hace falta un historial, solo no se pinta acá.
          const accionables = porRevisar.filter((d) => !d.periodo_pagado);
          return accionables.length > 0 && (
            <div className="mb-6 max-w-3xl rounded-xl border border-ambar/40 bg-ambar/5 p-4">
              <p className="text-sm font-medium text-tinta">
                {accionables.length === 1
                  ? "1 día quedó con una secuencia imposible"
                  : `${accionables.length} días quedaron con una secuencia imposible`}
              </p>
              <p className="mb-3 mt-1 text-xs leading-relaxed text-taupe">
                Ocurre cuando la terminal pierde señal y una marca llega tarde. No se perdió nada:
                solo hay que ordenar el día. Toca uno para cargarlo.
              </p>
              <ul className="flex flex-col">
                {accionables.map((d) => (
                  <li key={`${d.persona_id}-${d.fecha}`}>
                    <button
                      onClick={() => { setPersonaId(d.persona_id); setFecha(d.fecha); setCargado(false); }}
                      className="w-full rounded-lg px-3 py-2 text-left text-sm transition-colors hover:bg-ambar/10"
                    >
                      <span className="font-medium text-tinta">{d.nombre}</span>
                      <span className="text-taupe"> · {d.sede} · {d.fecha}</span>
                    </button>
                  </li>
                ))}
              </ul>
            </div>
          );
        })()}

        <div className="mb-6 flex flex-wrap items-end gap-4">
          <label className="flex flex-col gap-1 text-sm">
            Persona
            <select value={personaId} onChange={(e) => { setPersonaId(e.target.value); setCargado(false); }} className="min-w-56 rounded-lg border bg-crema px-3 py-2">
              <option value="">Elegir…</option>
              {personasCorregibles.map((p) => <option key={p.id} value={p.id}>{p.nombres} {p.apellidos}</option>)}
            </select>
          </label>
          <label className="flex flex-col gap-1 text-sm">
            Fecha
            <input type="date" value={fecha} onChange={(e) => { setFecha(e.target.value); setCargado(false); }} className="rounded-lg border px-3 py-2" />
          </label>
          <button onClick={cargarDia} disabled={!personaId || cargando} className="rounded-lg bg-tinta px-5 py-2 text-sm font-medium text-crema disabled:opacity-50">
            {cargando ? "Cargando…" : "Ver el día"}
          </button>
        </div>

        {cargado && personaSel && (
          <div className="max-w-3xl">
            {/* Dos avisos distintos, no uno.
                Antes había uno solo, que se mostraba cuando CUALQUIER marca del día
                seguía en 'pendiente_revision'. Eso daba dos fallos: (a) un día ya
                arreglado seguía en rojo, porque el sello es un estado guardado de
                cuando estuvo roto y no una pregunta sobre si sigue roto — y las
                marcas anuladas también contaban; (b) el texto hablaba siempre de
                "secuencia imposible" aunque el motivo real fuera un auto-cierre,
                que es otra cosa. Ahora se pregunta en vivo y cada caso dice lo suyo. */}
            {diaIncoherente && (
              <div className="mb-4 rounded-lg border border-ambar/40 bg-ambar/5 px-4 py-3 text-sm leading-relaxed">
                <strong className="text-tinta">La secuencia de marcas de este día no es posible.</strong>{" "}
                <span className="text-taupe">
                  Por ejemplo, dos salidas seguidas sin retorno entre medio. Suele pasar cuando una
                  marca llega tarde tras un corte de señal. Corrige el tipo o la hora de lo que esté
                  mal, o anula lo que sobre — el aviso desaparece solo en cuanto el día cuadre.
                </span>
              </div>
            )}
            {marcajes.some((m) => m.anulada_at === null && m.origen === "auto_cierre" && m.estado_revision === "pendiente_revision") && (
              <div className="mb-4 rounded-lg border border-ambar/40 bg-ambar/5 px-4 py-3 text-sm leading-relaxed">
                <strong className="text-tinta">Este día lo cerró el sistema.</strong>{" "}
                <span className="text-taupe">
                  Nadie marcó la salida, así que el auto-cierre nocturno puso una hora. Mientras
                  siga sin revisar, ese día no mide salida anticipada ni tiempo adicional. Pulsa
                  <em> Confirmar</em> si esa hora es la buena, o corrígela.
                </span>
              </div>
            )}
            {jornada && (
              <div className="mb-4 flex flex-wrap gap-x-6 gap-y-1 rounded-lg border bg-sand/50 px-4 py-3 text-sm">
                <span>Estado: <strong>{jornada.estado}</strong></span>
                <span>Horas: <strong>{jornada.horas_trabajadas ?? "—"}</strong></span>
                <span className="flex items-center gap-2">
                  Tardanza:{" "}
                  {!jornada.minutos_tarde ? (
                    <strong>—</strong>
                  ) : levTardanza ? (
                    <>
                      <s className="text-taupe">{jornada.minutos_tarde} min</s>
                      <span className="rounded-full bg-verde/15 px-2 py-0.5 text-xs text-verde">levantada · {motivoTardLabel(levTardanza.motivo)}</span>
                      <button onClick={() => void quitarLevantamiento()} className="text-xs text-taupe underline hover:text-tinta">quitar</button>
                    </>
                  ) : (
                    <>
                      <strong className="text-rojo">{jornada.minutos_tarde} min</strong>
                      <button onClick={() => { setLevModal(true); setLevMotivo("fuerza_mayor"); setLevObs(""); }}
                        className="rounded border border-sand px-2 py-0.5 text-xs text-taupe hover:bg-sand/40">Levantar</button>
                    </>
                  )}
                </span>
              </div>
            )}

            {/* De dónde sale la tardanza: la hora esperada de ese día y su origen.
                Si viene de un turno puntual (pisa el horario base), se resalta. */}
            {esperado && (
              <div className="mb-4 rounded-lg border px-4 py-2.5 text-sm">
                {esperado.entrada ? (
                  <>
                    Entrada esperada ese día: <strong>{esperado.entrada}</strong>
                    <span className={`ml-2 rounded-full px-2 py-0.5 text-xs ${esperado.origen === "turno" ? "bg-ambar/15 text-ambar" : "bg-taupe/15 text-taupe"}`}>
                      {textoOrigen(esperado)}
                    </span>
                    {esperado.origen === "turno" && (
                      <span className="ml-2 text-xs text-taupe">— este día tiene un turno propio que manda sobre el horario base. Se cambia en Turnos.</span>
                    )}
                  </>
                ) : (
                  <span className="text-taupe">Ese día no mide tardanza: {textoOrigen(esperado)}.</span>
                )}
              </div>
            )}

            {marcajes.length === 0 ? (
              <p className="mb-4 text-sm text-taupe">No hay marcajes ese día. Puedes agregar uno abajo.</p>
            ) : (
              <div className="mb-4 overflow-x-auto rounded-lg border">
                <table className="w-full text-sm">
                  <thead className="bg-sand/70 text-left text-taupe">
                    <tr>
                      <th className="px-4 py-2 font-normal">Tipo</th>
                      <th className="px-4 py-2 font-normal">Hora</th>
                      <th className="px-4 py-2 font-normal">Origen</th>
                      <th className="px-4 py-2 font-normal">Acciones</th>
                    </tr>
                  </thead>
                  <tbody>
                    {marcajes.map((m) => {
                      const anulada = m.anulada_at !== null;
                      const horaLocal = horasEditadas[m.id] ?? horaInput(m.timestamp_marca);
                      const tipoLocal = tiposEditados[m.id] ?? m.tipo;
                      const cambiada = horaLocal !== horaInput(m.timestamp_marca) || tipoLocal !== m.tipo;
                      const esAutoCierrePendiente = m.origen === "auto_cierre" && m.estado_revision === "pendiente_revision";
                      const opciones = TIPOS_DE_LA_FAMILIA(m.tipo);
                      return (
                        <tr key={m.id} className={`border-t ${anulada ? "opacity-55" : ""}`}>
                          <td className="px-4 py-2">
                            {anulada || opciones.length === 1 ? (
                              <span className={anulada ? "line-through" : undefined}>{TIPO_MARCA_LABELS[m.tipo]}</span>
                            ) : (
                              // Solo tipos de su misma familia: una entrada no puede volverse salida.
                              <select value={tipoLocal}
                                onChange={(e) => setTiposEditados({ ...tiposEditados, [m.id]: e.target.value as TipoMarca })}
                                className="rounded border px-2 py-1">
                                {opciones.map((t) => <option key={t} value={t}>{TIPO_MARCA_LABELS[t]}</option>)}
                              </select>
                            )}
                            {m.origen === "auto_cierre" && <span className="ml-2 rounded bg-rojo/10 px-1.5 py-0.5 text-xs text-rojo">auto-cierre</span>}
                            {m.origen === "admin_correccion" && <span className="ml-2 rounded bg-taupe/15 px-1.5 py-0.5 text-xs text-taupe">manual</span>}
                            {m.origen === "auto_cierre" && m.estado_revision === "revisada" && !anulada && (
                              <span className="ml-2 rounded bg-verde/15 px-1.5 py-0.5 text-xs text-taupe">confirmada</span>
                            )}
                            {anulada && (
                              <p className="mt-1 text-xs text-taupe">Anulada · {m.anulada_motivo}</p>
                            )}
                          </td>
                          <td className="px-4 py-2">
                            {anulada ? (
                              <span className="line-through text-taupe">{horaTextoLima(m.timestamp_marca)}</span>
                            ) : (
                              <input type="time" value={horaLocal}
                                onChange={(e) => setHorasEditadas({ ...horasEditadas, [m.id]: e.target.value })}
                                className="rounded border px-2 py-1" />
                            )}
                          </td>
                          <td className="px-4 py-2 text-taupe">{m.origen}</td>
                          <td className="px-4 py-2">
                            <div className="flex flex-wrap gap-2 text-xs">
                              {anulada ? (
                                <button
                                  onClick={() => { setAccion({ modo: "reactivar", marcaje: m }); setMotivo(""); }}
                                  title="Devolver esta marca al cálculo del día"
                                  className="rounded border px-2 py-1 hover:bg-sand/50">
                                  Reactivar
                                </button>
                              ) : (
                                <>
                                  <button
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
                                    }}
                                    className="rounded border px-2 py-1 hover:bg-sand/50 disabled:opacity-40">
                                    Guardar
                                  </button>
                                  {esAutoCierrePendiente && (
                                    <button
                                      onClick={() => { setAccion({ modo: "confirmar", marcaje: m }); setMotivo(""); }}
                                      title="Esa es su salida final: el día deja de estar pendiente y pasa a medirse entero"
                                      className="rounded border px-2 py-1 hover:bg-sand/50">
                                      Confirmar
                                    </button>
                                  )}
                                  <button
                                    onClick={() => { setAccion({ modo: "anular", marcaje: m }); setMotivo(""); }}
                                    title="La marca deja de contar, pero se queda en el historial con su motivo"
                                    className="rounded border border-rojo/30 px-2 py-1 text-rojo hover:bg-rojo/10">
                                    Anular
                                  </button>
                                </>
                              )}
                            </div>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}

            {/* Agregar marcaje faltante */}
            <div className="rounded-lg border bg-sand/50 p-4">
              <h2 className="mb-3 text-sm font-medium">Agregar un marcaje faltante</h2>
              <div className="flex flex-wrap items-end gap-3">
                <label className="flex flex-col gap-1 text-sm">
                  Tipo
                  <select value={agregarTipo} onChange={(e) => setAgregarTipo(e.target.value as TipoMarca)} className="rounded-lg border bg-crema px-3 py-2">
                    {TIPOS_AGREGABLES.map((t) => <option key={t} value={t}>{TIPO_MARCA_LABELS[t]}</option>)}
                  </select>
                </label>
                <label className="flex flex-col gap-1 text-sm">
                  Hora
                  <input type="time" value={agregarHora} onChange={(e) => setAgregarHora(e.target.value)} className="rounded-lg border px-3 py-2" />
                </label>
                {agregarTipo === "salida_otro" && (
                  <label className="flex flex-col gap-1 text-sm">
                    Motivo de la salida
                    <input value={agregarMotivoOtro} onChange={(e) => setAgregarMotivoOtro(e.target.value)} className="rounded-lg border px-3 py-2" placeholder="ej. trámite banco" />
                  </label>
                )}
                <button
                  onClick={() => { setAccion({ modo: "agregar", tipo: agregarTipo, hora: agregarHora, motivoOtro: agregarMotivoOtro }); setMotivo(""); }}
                  className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema">
                  Agregar
                </button>
              </div>
            </div>

            {/* Historial de correcciones: el motivo de cada cambio, quién y cuándo.
                Es donde se LEE la auditoría que cada corrección va guardando. */}
            <div className="mt-4 overflow-hidden rounded-2xl border border-sand bg-papel">
              <h2 className="border-b bg-sand/50 px-4 py-2 text-sm font-medium">
                Historial de correcciones · {personaSel.nombres} {personaSel.apellidos}
              </h2>
              {auditoriaError ? (
                <p className="px-4 py-4 text-sm text-rojo">
                  No se pudo cargar el historial de correcciones. <button onClick={cargarDia} className="font-medium underline">Reintentar</button>
                </p>
              ) : auditoria.length === 0 ? (
                <p className="px-4 py-4 text-sm text-taupe">Esta persona no tiene correcciones registradas.</p>
              ) : (
                <ul className="divide-y">
                  {auditoria.map((row) => {
                    const { accion, detalle } = describirCambio(row);
                    return (
                      <li key={row.id} className="px-4 py-3 text-sm">
                        <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-0.5">
                          <span className="font-medium">
                            {accion} <span className="font-normal text-taupe">· {detalle}</span>
                          </span>
                          <span className="text-xs text-taupe">
                            {selloLima(row.corregido_at)} · por {nombrePorId.get(row.corregido_por) ?? "otra persona"}
                          </span>
                        </div>
                        <p className="mt-1 text-taupe">“{row.motivo}”</p>
                      </li>
                    );
                  })}
                </ul>
              )}
            </div>
          </div>
        )}

        {/* Modal: levantar tardanza (no cambia la hora) */}
        {levModal && (
          <div className="fixed inset-0 z-20 flex items-center justify-center bg-black/40 p-4" onClick={() => !levGuardando && setLevModal(false)}>
            <div className="w-full max-w-sm rounded-xl border border-sand bg-crema p-6" onClick={(e) => e.stopPropagation()}>
              <h3 className="mb-1 font-serif text-lg">Levantar tardanza</h3>
              <p className="mb-4 text-sm text-taupe">
                Se perdona la tardanza: deja de contar para la escalera disciplinaria y para el umbral del mes.
                <strong> La hora real no se toca</strong> — queda tachada con su motivo.
              </p>
              <label className="mb-3 flex flex-col gap-1 text-sm">
                Motivo
                <select value={levMotivo} onChange={(e) => setLevMotivo(e.target.value)} className="rounded-lg border border-sand bg-crema px-3 py-2">
                  {MOTIVOS_TARD.map((m) => <option key={m.valor} value={m.valor}>{m.label}</option>)}
                </select>
              </label>
              <label className="mb-4 flex flex-col gap-1 text-sm">
                Observación {levMotivo === "otro" ? <span className="text-rojo">(obligatoria)</span> : <span className="text-taupe">(opcional)</span>}
                <textarea value={levObs} onChange={(e) => setLevObs(e.target.value)} rows={2}
                  className="rounded-lg border border-sand bg-crema px-3 py-2" placeholder="ej. paro de transporte" />
              </label>
              <div className="flex justify-end gap-2">
                <button onClick={() => setLevModal(false)} disabled={levGuardando} className="rounded-lg border border-sand px-3 py-2 text-sm">Cancelar</button>
                <button onClick={() => void levantarTardanza()} disabled={levGuardando} className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema disabled:opacity-50">
                  {levGuardando ? "…" : "Levantar"}
                </button>
              </div>
            </div>
          </div>
        )}

        {/* Modal: motivo de la corrección */}
        {accion && (
          <div className="fixed inset-0 z-10 flex items-center justify-center bg-black/40 p-4" onClick={() => !procesando && setAccion(null)}>
            <div className="w-full max-w-md rounded-xl bg-crema p-6 border border-sand" onClick={(e) => e.stopPropagation()}>
              <h3 className="mb-2 font-serif text-lg">
                {accion.modo === "editar" && "Confirmar la corrección"}
                {accion.modo === "anular" && "Anular esta marca"}
                {accion.modo === "reactivar" && "Devolver esta marca al día"}
                {accion.modo === "confirmar" && "Confirmar la salida del auto-cierre"}
                {accion.modo === "agregar" && "Agregar marcaje"}
              </h3>
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
                <div className="mb-4 rounded-lg border border-ambar/40 bg-ambar/5 px-3 py-3 text-sm">
                  <p className="mb-2 text-taupe">
                    Después de esa salida final quedan {accion.posteriores.length}{" "}
                    {accion.posteriores.length === 1 ? "marca" : "marcas"}. Se anularán con el mismo
                    motivo; desmarca la que quieras conservar.
                  </p>
                  {accion.posteriores.map((post) => (
                    <label key={post.id} className="flex items-center gap-2 py-0.5">
                      <input type="checkbox"
                        checked={anularPosteriores[post.id] ?? false}
                        onChange={(e) => setAnularPosteriores({ ...anularPosteriores, [post.id]: e.target.checked })} />
                      <span>
                        {TIPO_MARCA_LABELS[post.tipo]} de las {horaInput(post.timestamp_marca)}
                        {post.origen === "auto_cierre" && " (auto-cierre)"}
                      </span>
                    </label>
                  ))}
                </div>
              )}
              <label className="mb-4 flex flex-col gap-1 text-sm">
                Motivo (obligatorio)
                <textarea value={motivo} onChange={(e) => setMotivo(e.target.value)} rows={2} autoFocus
                  className="rounded-lg border px-3 py-2" placeholder="ej. el reloj del terminal estaba adelantado" />
              </label>
              <div className="flex justify-end gap-3">
                <button onClick={() => setAccion(null)} disabled={procesando} className="rounded-lg border px-4 py-2 text-sm">Cancelar</button>
                <button onClick={ejecutar} disabled={procesando} className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema disabled:opacity-50">
                  {procesando ? "Guardando…" : "Confirmar"}
                </button>
              </div>
            </div>
          </div>
        )}
      </main>
    </div>
  );
}
