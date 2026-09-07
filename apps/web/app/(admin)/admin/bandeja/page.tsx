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
// ============================================================================

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { AdminNav } from "../nav";
import { Cargando, SinDatos } from "@/components/cargando";
import { useToast } from "@/components/toast";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { fechaLima, puedeOperarEquipo, puedeVerPlanilla, puedeVerSaludDeAlertas } from "@cayla-dynamic/shared";

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
}

/** Una propuesta de cambio de perfil por resolver (migración 0396). */
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
}

/** «celular: 987654321, direccion: Av. Uno 123» — genérico a propósito: son
 *  11 campos con formas distintas, y esto solo es para que quien aprueba vea
 *  de un vistazo qué cambia, no para imprimir un documento. */
function resumenValorPerfil(v: Record<string, unknown>): string {
  const entradas = Object.entries(v).filter(([, val]) => val !== null && val !== undefined && val !== "");
  if (entradas.length === 0) return "—";
  return entradas.map(([k, val]) => `${k}: ${typeof val === "boolean" ? (val ? "Sí" : "No") : String(val)}`).join(" · ");
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
  // Igual regla que vacaciones: DO, nunca la encargada de sede — decidido para
  // los 11 campos por igual, no solo los sensibles (ver ADR 0001, DECIDÍ #9).
  const puedeResolverPerfil = puedeVerPlanilla(rol);

  const [cargando, setCargando] = useState(true);
  const [resumenAlertas, setResumenAlertas] = useState<ResumenAlertas | null>(null);
  const [educacion, setEducacion] = useState<ItemEducacion[]>([]);
  const [vacaciones, setVacaciones] = useState<ItemVacacion[]>([]);
  const [sinHorario, setSinHorario] = useState<ItemSinHorario[]>([]);
  const [revisiones, setRevisiones] = useState<ItemRevision[]>([]);
  const [solicitudesVacaciones, setSolicitudesVacaciones] = useState<ItemSolicitudVacacion[]>([]);
  const [solicitudesPerfil, setSolicitudesPerfil] = useState<ItemSolicitudPerfil[]>([]);
  const [respuestas, setRespuestas] = useState<Record<string, string>>({});
  const [motivosRechazo, setMotivosRechazo] = useState<Record<string, string>>({});
  const [motivosPerfil, setMotivosPerfil] = useState<Record<string, string>>({});
  const [atendiendo, setAtendiendo] = useState<string | null>(null);
  const [resolviendo, setResolviendo] = useState<string | null>(null);
  const [resolviendoPerfil, setResolviendoPerfil] = useState<string | null>(null);

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
    } else {
      setVacaciones([]);
      setRevisiones([]);
      setSinHorario([]);
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
  }, [router, puedeEducacion, puedeEquipo, puedeResolverVacaciones, puedeResolverPerfil, puedeSaludAlertas, avisar]);

  // Cargar al montar es el mismo patrón que usa cada pantalla del panel que
  // trae datos de la base (Equipo, Ausencias, Disciplina...); el aviso de acá
  // es el mismo que ya tienen todas ellas sin corregir.
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void cargar(); }, [cargar]);

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
   *  al momento de mirar — nunca se firman los 11 de golpe. */
  async function verDocumentoPerfil(ruta: string) {
    const supabase = createAdminSupabaseClient();
    const { data, error } = await supabase.storage.from("solicitudes-perfil").createSignedUrl(ruta, 300);
    if (error || !data) { avisar("error", "No se pudo abrir el documento."); return; }
    window.open(data.signedUrl, "_blank", "noopener,noreferrer");
  }

  // La tarjeta de avisos por correo solo aparece cuando hay algo que una
  // persona tiene que mirar: lo que se va a reintentar solo no se muestra.
  const alertasConProblema = resumenAlertas
    ? resumenAlertas.atascadas + resumenAlertas.fallidas_definitivas + resumenAlertas.caducadas
    : 0;

  const total = educacion.length + vacaciones.length + revisiones.length + solicitudesVacaciones.length
    + solicitudesPerfil.length + alertasConProblema + sinHorario.length;

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <h1 className="mb-1 font-serif text-2xl">Bandeja</h1>
        <p className="mb-6 max-w-2xl text-sm text-taupe">
          Lo que hoy solo se ve como un número en el menú, junto en un solo lugar.
        </p>

        {cargando ? (
          <Cargando />
        ) : !puedeEducacion && !puedeEquipo ? (
          <div className="max-w-2xl rounded-lg bg-ambar/15 px-4 py-3 text-sm text-ambar">
            Esta pantalla es para quien opera el equipo — encargadas y Desarrollo Organizacional.
          </div>
        ) : total === 0 ? (
          <SinDatos texto="No hay nada pendiente." pista="Cuando algo necesite atención, va a aparecer aquí." />
        ) : (
          <div className="flex max-w-3xl flex-col gap-8">
            {resumenAlertas && alertasConProblema > 0 && (
              <section>
                <h2 className="mb-1 font-serif text-lg">Avisos por correo</h2>
                <p className="mb-3 text-sm text-taupe">
                  El despacho diario de avisos (auto-cierres, contratos y vacaciones por vencer) dejó
                  {" "}{alertasConProblema} aviso{alertasConProblema === 1 ? "" : "s"} que no va{alertasConProblema === 1 ? "" : "n"} a salir solo{alertasConProblema === 1 ? "" : "s"}.
                </p>
                <ul className="space-y-2 text-sm">
                  {resumenAlertas.fallidas_definitivas > 0 && (
                    <li className="rounded-xl border border-rojo p-3">
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
                    <li className="rounded-xl border border-sand p-3">
                      <strong className="text-ambar">
                        {resumenAlertas.atascadas} qued{resumenAlertas.atascadas === 1 ? "ó" : "aron"} a medio despachar
                      </strong>
                      <span className="text-taupe"> hace más de una hora — la ejecución se cortó. </span>
                      Se reintentan solos en el próximo despacho (hasta tres veces); si vuelve a pasar, revisa en Sentry por qué se corta.
                    </li>
                  )}
                  {resumenAlertas.caducadas > 0 && (
                    <li className="rounded-xl border border-sand p-3">
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

            {revisiones.length > 0 && (
              <section>
                <h2 className="mb-1 font-serif text-lg">
                  Tu equipo pidió revisar {revisiones.length} día{revisiones.length === 1 ? "" : "s"}
                </h2>
                <p className="mb-3 text-sm text-taupe">
                  Lo escribieron desde «Lo mío». Corrige el día en Correcciones si hace falta y cierra acá
                  diciendo en qué quedó — esa respuesta la va a leer la persona.
                </p>
                <ul className="space-y-3">
                  {revisiones.map((r) => (
                    <li key={r.id} className="rounded-xl border border-sand p-3 text-sm">
                      <div className="flex flex-wrap items-baseline justify-between gap-2">
                        <span><strong>{r.nombre}</strong> <span className="text-taupe">· {r.sede} · {fmtFecha(r.fecha)}</span></span>
                        <Link href={`/admin/correcciones?persona=${r.persona_id}&fecha=${r.fecha}`}
                          className="text-rojo hover:underline">Abrir ese día en Correcciones →</Link>
                      </div>
                      <p className="mt-1.5">«{r.comentario}»</p>
                      <div className="mt-2 flex flex-wrap items-center gap-2">
                        <input
                          value={respuestas[r.id] ?? ""}
                          onChange={(e) => setRespuestas((x) => ({ ...x, [r.id]: e.target.value }))}
                          placeholder="En qué quedó (lo va a leer la persona)"
                          className="min-w-56 flex-1 rounded-lg border border-sand bg-crema px-3 py-1.5"
                        />
                        <button onClick={() => void marcarAtendida(r.id)} disabled={atendiendo === r.id}
                          className="rounded-lg bg-tinta px-4 py-1.5 font-medium text-crema disabled:opacity-50">
                          {atendiendo === r.id ? "Guardando…" : "Marcar atendida"}
                        </button>
                      </div>
                    </li>
                  ))}
                </ul>
              </section>
            )}

            {solicitudesVacaciones.length > 0 && (
              <section>
                <h2 className="mb-1 font-serif text-lg">
                  {solicitudesVacaciones.length} solicitud{solicitudesVacaciones.length === 1 ? "" : "es"} de vacaciones por resolver
                </h2>
                <p className="mb-3 text-sm text-taupe">
                  Lo pidieron desde «Lo mío». Aprobar crea la ausencia real de una vez; rechazar exige decir por qué —esa respuesta la va a leer la persona.
                </p>
                <ul className="space-y-3">
                  {solicitudesVacaciones.map((s) => (
                    <li key={s.id} className="rounded-xl border border-sand p-3 text-sm">
                      <div className="flex flex-wrap items-baseline justify-between gap-2">
                        <span><strong>{s.nombre}</strong> <span className="text-taupe">· {s.sede} · {rangoSolicitud(s)}</span></span>
                      </div>
                      {s.comentario && <p className="mt-1.5">«{s.comentario}»</p>}
                      <div className="mt-2 flex flex-wrap items-center gap-2">
                        <input
                          value={motivosRechazo[s.id] ?? ""}
                          onChange={(e) => setMotivosRechazo((x) => ({ ...x, [s.id]: e.target.value }))}
                          placeholder="Motivo si rechazas (obligatorio solo para rechazar)"
                          className="min-w-64 flex-1 rounded-lg border border-sand bg-crema px-3 py-1.5"
                        />
                        <button onClick={() => void resolverSolicitud(s.id, true)} disabled={resolviendo === s.id}
                          className="rounded-lg bg-tinta px-4 py-1.5 font-medium text-crema disabled:opacity-50">
                          {resolviendo === s.id ? "Guardando…" : "Aprobar"}
                        </button>
                        <button onClick={() => void resolverSolicitud(s.id, false)} disabled={resolviendo === s.id}
                          className="rounded-lg border border-rojo px-4 py-1.5 font-medium text-rojo disabled:opacity-50">
                          Rechazar
                        </button>
                      </div>
                    </li>
                  ))}
                </ul>
              </section>
            )}

            {solicitudesPerfil.length > 0 && (
              <section>
                <h2 className="mb-1 font-serif text-lg">
                  {solicitudesPerfil.length} solicitud{solicitudesPerfil.length === 1 ? "" : "es"} de cambio de perfil
                </h2>
                <p className="mb-3 text-sm text-taupe">
                  Lo pidieron desde «Lo mío». Aprobar aplica el cambio real de una vez; rechazar exige decir por qué —esa respuesta la va a leer la persona.
                </p>
                <ul className="space-y-3">
                  {solicitudesPerfil.map((s) => (
                    <li key={s.id} className="rounded-xl border border-sand p-3 text-sm">
                      <div className="flex flex-wrap items-baseline justify-between gap-2">
                        <span><strong>{s.nombre}</strong> <span className="text-taupe">· {s.sede} · {s.etiqueta}</span></span>
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
                      <div className="mt-2 flex flex-wrap items-center gap-2">
                        <input
                          value={motivosPerfil[s.id] ?? ""}
                          onChange={(e) => setMotivosPerfil((x) => ({ ...x, [s.id]: e.target.value }))}
                          placeholder="Motivo si rechazas (obligatorio solo para rechazar)"
                          className="min-w-64 flex-1 rounded-lg border border-sand bg-crema px-3 py-1.5"
                        />
                        <button onClick={() => void resolverSolicitudPerfil(s.id, true)} disabled={resolviendoPerfil === s.id}
                          className="rounded-lg bg-tinta px-4 py-1.5 font-medium text-crema disabled:opacity-50">
                          {resolviendoPerfil === s.id ? "Guardando…" : "Aprobar"}
                        </button>
                        <button onClick={() => void resolverSolicitudPerfil(s.id, false)} disabled={resolviendoPerfil === s.id}
                          className="rounded-lg border border-rojo px-4 py-1.5 font-medium text-rojo disabled:opacity-50">
                          Rechazar
                        </button>
                      </div>
                    </li>
                  ))}
                </ul>
              </section>
            )}

            {sinHorario.length > 0 && (
              <section>
                <h2 className="mb-1 font-serif text-lg">
                  {sinHorario.length} persona{sinHorario.length === 1 ? "" : "s"} trabajó sin horario vigente
                </h2>
                <p className="mb-3 max-w-2xl text-xs leading-relaxed text-taupe">
                  Marcaron días que ningún horario suyo cubre. Esos días no miden tardanza, ni
                  salida anticipada, ni tiempo adicional — y si a alguien le cae un descanso médico
                  o una licencia dentro del hueco, se le paga en cero, sin que nada falle. Suele
                  ocurrir cuando se cambia el horario de una tienda y el tramo nuevo empieza unos
                  días después de que terminó el anterior. Quien no lleva horario por su vínculo no
                  aparece acá.
                </p>
                <ul className="space-y-2">
                  {sinHorario.map((h) => (
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

            {vacaciones.length > 0 && (
              <section>
                <h2 className="mb-3 font-serif text-lg">
                  {vacaciones.length} récord{vacaciones.length === 1 ? "" : "s"} de vacaciones vencen pronto
                </h2>
                <ul className="space-y-2">
                  {vacaciones.map((v) => (
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

            {educacion.length > 0 && (
              <section>
                <h2 className="mb-3 font-serif text-lg">
                  {educacion.length} asignación{educacion.length === 1 ? "" : "es"} de educación por atender
                </h2>
                <ul className="space-y-2">
                  {educacion.map((f) => (
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
      </main>
    </div>
  );
}
