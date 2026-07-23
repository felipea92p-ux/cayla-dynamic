"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { TIPO_MARCA_LABELS, TIPOS_MARCA, type TipoMarca } from "@cayla-dynamic/shared";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { AdminNav } from "../nav";

const TZ = "America/Lima";

function fechaHoyLima() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: TZ }).format(new Date());
}
// Día de la semana (0=domingo … 6=sábado) de un ISO — misma clave que horario_por_dia.
function dowDe(iso: string): number {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d)).getUTCDay();
}
// "HH:MM" en hora Lima para el input de tipo time
function horaInput(tsISO: string) {
  return new Intl.DateTimeFormat("en-GB", { timeZone: TZ, hour: "2-digit", minute: "2-digit", hour12: false }).format(new Date(tsISO));
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
  return new Intl.DateTimeFormat("es-PE", { timeZone: TZ, hour: "2-digit", minute: "2-digit", hour12: true }).format(d);
}
// Sello de auditoría: cuándo se hizo el cambio (fecha corta + hora Lima).
function selloLima(iso: string): string {
  const d = new Date(iso);
  if (isNaN(d.getTime())) return iso;
  return new Intl.DateTimeFormat("es-PE", { timeZone: TZ, day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit", hour12: true }).format(d);
}

interface TurnoDia { hora_entrada: string | null; es_descanso: boolean; }
interface HorarioTramo { hora_entrada: string | null; horario_por_dia: Record<string, { e?: string; s?: string; r?: number }> | null; }
// Contra qué hora se mide la tardanza ese día y de dónde sale. Replica la
// prioridad del backend (fn_recalcular_jornada): el turno del día manda; solo si
// no hay turno se cae al horario base. `deTurno` marca el override para resaltarlo.
function calcularEsperado(fecha: string, turno: TurnoDia | null, horario: HorarioTramo | null): { hora: string | null; origen: string; deTurno: boolean } | null {
  if (turno) {
    if (turno.es_descanso) return { hora: null, origen: "descanso (turno del día)", deTurno: true };
    if (turno.hora_entrada) return { hora: turno.hora_entrada.slice(0, 5), origen: "turno del día", deTurno: true };
  }
  if (horario) {
    const hpd = horario.horario_por_dia;
    if (hpd) {
      const d = hpd[String(dowDe(fecha))];
      if (d?.e) return { hora: d.e.slice(0, 5), origen: "horario base", deTurno: false };
      return { hora: null, origen: "descanso (horario base)", deTurno: false };
    }
    if (horario.hora_entrada) return { hora: horario.hora_entrada.slice(0, 5), origen: "horario base", deTurno: false };
  }
  return null; // sin turno ni horario vigente: no hay contra qué medir
}

interface Persona { id: string; nombres: string; apellidos: string; rol: string; sede_base_id: string; }
const ROLES_ADMIN = ["admin", "lider_do"];
interface Marcaje { id: string; tipo: TipoMarca; motivo_otro: string | null; timestamp_marca: string; origen: string; estado_revision: string; }
/** Día que el sistema selló solo, por haber quedado con una secuencia imposible (mig. 0068). */
interface DiaPorRevisar { persona_id: string; nombre: string; sede: string; fecha: string; marcas: number; }
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
  | { modo: "editar"; marcaje: Marcaje; nuevaHora: string }
  | { modo: "eliminar"; marcaje: Marcaje }
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
  const [esperado, setEsperado] = useState<{ hora: string | null; origen: string; deTurno: boolean } | null>(null);
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
  const [mensaje, setMensaje] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);
  // Días sellados por el sistema (secuencia imposible). Sin esta lista el sello
  // sería inútil: nadie va a revisar persona por persona adivinando cuál quedó mal.
  const [porRevisar, setPorRevisar] = useState<DiaPorRevisar[]>([]);

  // edición local de horas por marcaje
  const [horasEditadas, setHorasEditadas] = useState<Record<string, string>>({});
  // acción pendiente de confirmar con motivo
  const [accion, setAccion] = useState<Accion | null>(null);
  const [motivo, setMotivo] = useState("");
  const [procesando, setProcesando] = useState(false);
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
    });
  }, [router]);

  const cargarDia = useCallback(async () => {
    if (!personaId) return;
    setCargando(true);
    setMensaje(null);
    const supabase = createAdminSupabaseClient();
    const inicio = `${fecha}T00:00:00-05:00`;
    const fin = `${fecha}T23:59:59-05:00`;
    const [{ data: mk, error: errMk }, { data: jor, error: errJor }, { data: aud, error: errAud }, { data: turno }, { data: horario }, { data: levT }] = await Promise.all([
      supabase.from("marcajes")
        .select("id, tipo, motivo_otro, timestamp_marca, origen, estado_revision")
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
      // horario base (misma prioridad que fn_recalcular_jornada). Fallan suave.
      supabase.from("turnos").select("hora_entrada, es_descanso").eq("persona_id", personaId).eq("fecha", fecha).maybeSingle(),
      supabase.from("horarios_asignados").select("hora_entrada, horario_por_dia, vigente_desde")
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
    setJornada((jor as Jornada) ?? null);
    setEsperado(calcularEsperado(fecha, turno as TurnoDia | null, horario as HorarioTramo | null));
    setLevTardanza((levT as { motivo: string; observacion: string | null } | null) ?? null);
    setAuditoriaError(Boolean(errAud));
    setAuditoria(errAud ? [] : ((aud as Auditoria[]) ?? []));
    setHorasEditadas(Object.fromEntries(((mk as Marcaje[]) ?? []).map((m) => [m.id, horaInput(m.timestamp_marca)])));
    setCargado(true);
    setCargando(false);
  }, [personaId, fecha]);

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

  function avisar(tipo: "ok" | "error", texto: string) { setMensaje({ tipo, texto }); }

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
      ({ error } = await supabase.rpc("fn_corregir_marcaje", {
        p_marcaje_id: accion.marcaje.id,
        p_nuevo_ts: construirTs(fecha, accion.nuevaHora),
        p_motivo: motivo.trim(),
      }));
    } else if (accion.modo === "eliminar") {
      ({ error } = await supabase.rpc("fn_eliminar_marcaje", {
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
    setProcesando(false);
    if (error) { avisar("error", error.message); return; }
    setAccion(null);
    setMotivo("");
    await cargarDia();
    avisar("ok", "Corrección guardada y registrada en la auditoría.");
  }

  const personaSel = useMemo(() => personas.find((p) => p.id === personaId), [personas, personaId]);
  // Nombre de quién hizo cada corrección, resuelto desde la lista ya cargada
  // (evita depender de un embed de PostgREST que el schema cache puede no exponer).
  const nombrePorId = useMemo(() => new Map(personas.map((p) => [p.id, `${p.nombres} ${p.apellidos}`])), [personas]);
  const puedeCorregir = rol === "admin" || rol === "lider_do" || rol === "supervisor_sede";
  const esSupervisor = rol === "supervisor_sede";

  // Una encargada no puede corregir su propia asistencia ni la de un admin.
  const personasCorregibles = useMemo(() => {
    if (!esSupervisor || !yo) return personas;
    return personas.filter((p) => p.id !== yo.id && !ROLES_ADMIN.includes(p.rol));
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

        {porRevisar.length > 0 && (
          <div className="mb-6 max-w-3xl rounded-xl border border-ambar/40 bg-ambar/5 p-4">
            <p className="text-sm font-medium text-tinta">
              {porRevisar.length === 1
                ? "1 día quedó con una secuencia imposible"
                : `${porRevisar.length} días quedaron con una secuencia imposible`}
            </p>
            <p className="mb-3 mt-1 text-xs leading-relaxed text-taupe">
              Ocurre cuando la terminal pierde señal y una marca llega tarde. No se perdió nada:
              solo hay que ordenar el día. Toca uno para cargarlo.
            </p>
            <ul className="flex flex-col">
              {porRevisar.map((d) => (
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
        )}

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

        {mensaje && (
          <div className={`mb-4 max-w-2xl rounded-lg px-4 py-3 text-sm ${mensaje.tipo === "ok" ? "bg-sand/40 text-tinta" : "bg-rojo/10 text-rojo"}`}>
            {mensaje.texto}
          </div>
        )}

        {cargado && personaSel && (
          <div className="max-w-3xl">
            {marcajes.some((m) => m.estado_revision === "pendiente_revision") && (
              <div className="mb-4 rounded-lg border border-ambar/40 bg-ambar/5 px-4 py-3 text-sm leading-relaxed">
                <strong className="text-tinta">Este día está sellado para revisión.</strong>{" "}
                <span className="text-taupe">
                  La secuencia de marcas no es posible (por ejemplo, dos salidas seguidas sin retorno
                  entre medio). Suele pasar cuando una marca llega tarde tras un corte de señal.
                  Ordénalo y queda resuelto.
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
                {esperado.hora ? (
                  <>
                    Entrada esperada ese día: <strong>{esperado.hora}</strong>
                    <span className={`ml-2 rounded-full px-2 py-0.5 text-xs ${esperado.deTurno ? "bg-ambar/15 text-ambar" : "bg-taupe/15 text-taupe"}`}>
                      {esperado.origen}
                    </span>
                    {esperado.deTurno && (
                      <span className="ml-2 text-xs text-taupe">— este día tiene un turno propio que manda sobre el horario base. Se cambia en Turnos.</span>
                    )}
                  </>
                ) : (
                  <span className="text-taupe">Ese día no mide tardanza: {esperado.origen}.</span>
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
                      const horaLocal = horasEditadas[m.id] ?? horaInput(m.timestamp_marca);
                      const cambiada = horaLocal !== horaInput(m.timestamp_marca);
                      return (
                        <tr key={m.id} className="border-t">
                          <td className="px-4 py-2">
                            {TIPO_MARCA_LABELS[m.tipo]}
                            {m.origen === "auto_cierre" && <span className="ml-2 rounded bg-rojo/10 px-1.5 py-0.5 text-xs text-rojo">auto-cierre</span>}
                            {m.origen === "admin_correccion" && <span className="ml-2 rounded bg-taupe/15 px-1.5 py-0.5 text-xs text-taupe">manual</span>}
                          </td>
                          <td className="px-4 py-2">
                            <input type="time" value={horaLocal}
                              onChange={(e) => setHorasEditadas({ ...horasEditadas, [m.id]: e.target.value })}
                              className="rounded border px-2 py-1" />
                          </td>
                          <td className="px-4 py-2 text-taupe">{m.origen}</td>
                          <td className="px-4 py-2">
                            <div className="flex gap-2 text-xs">
                              <button
                                disabled={!cambiada}
                                onClick={() => { setAccion({ modo: "editar", marcaje: m, nuevaHora: horaLocal }); setMotivo(""); }}
                                className="rounded border px-2 py-1 hover:bg-sand/50 disabled:opacity-40">
                                Guardar hora
                              </button>
                              <button
                                onClick={() => { setAccion({ modo: "eliminar", marcaje: m }); setMotivo(""); }}
                                className="rounded border border-rojo/30 px-2 py-1 text-rojo hover:bg-rojo/10">
                                Eliminar
                              </button>
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
                Se perdona la tardanza (deja de contar y suma al bono de puntualidad).
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
                {accion.modo === "editar" && "Confirmar cambio de hora"}
                {accion.modo === "eliminar" && "Eliminar marcaje"}
                {accion.modo === "agregar" && "Agregar marcaje"}
              </h3>
              <p className="mb-4 text-sm text-taupe">
                {accion.modo === "editar" && `${TIPO_MARCA_LABELS[accion.marcaje.tipo]}: ${horaInput(accion.marcaje.timestamp_marca)} → ${accion.nuevaHora}`}
                {accion.modo === "eliminar" && `${TIPO_MARCA_LABELS[accion.marcaje.tipo]} de las ${horaInput(accion.marcaje.timestamp_marca)}. Esta acción no se puede deshacer.`}
                {accion.modo === "agregar" && `${TIPO_MARCA_LABELS[accion.tipo]} a las ${accion.hora}, para ${personaSel?.nombres} ${personaSel?.apellidos}.`}
              </p>
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
