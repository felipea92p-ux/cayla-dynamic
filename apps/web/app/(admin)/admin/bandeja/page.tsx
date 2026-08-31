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
import { puedeOperarEquipo, puedeVerPlanilla } from "@cayla-dynamic/shared";

interface ItemEducacion {
  id: string;
  persona: string;
  sede: string;
  rango: string;
  dias_para_vencer: number;
  meses_sin_papel: number;
  semaforo: "sin_comprobante" | "vencida" | "por_vencer" | "vigente";
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

// "2026-07-13" → "13/07/2026" — la misma aritmética de string que ya usa el
// resto del panel, sin pasar por Date ni arriesgar un desfase de zona horaria.
function fmtFecha(iso: string): string {
  const [y, m, d] = iso.split("-");
  return `${d}/${m}/${y}`;
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

  const [cargando, setCargando] = useState(true);
  const [educacion, setEducacion] = useState<ItemEducacion[]>([]);
  const [vacaciones, setVacaciones] = useState<ItemVacacion[]>([]);
  const [revisiones, setRevisiones] = useState<ItemRevision[]>([]);
  const [solicitudesVacaciones, setSolicitudesVacaciones] = useState<ItemSolicitudVacacion[]>([]);
  const [respuestas, setRespuestas] = useState<Record<string, string>>({});
  const [motivosRechazo, setMotivosRechazo] = useState<Record<string, string>>({});
  const [atendiendo, setAtendiendo] = useState<string | null>(null);
  const [resolviendo, setResolviendo] = useState<string | null>(null);

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
        supabase.rpc("fn_revisiones_pedidas", { p_solo_pendientes: true }).then(({ data, error }) => {
          if (error) { avisar("error", mensajeDeError(error, "cargar revisiones pedidas")); return; }
          setRevisiones((data as unknown as ItemRevision[]) ?? []);
        }),
      );
    } else {
      setVacaciones([]);
      setRevisiones([]);
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

    await Promise.all(tareas);
    setCargando(false);
  }, [router, puedeEducacion, puedeEquipo, puedeResolverVacaciones, avisar]);

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

  const total = educacion.length + vacaciones.length + revisiones.length + solicitudesVacaciones.length;

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
                          placeholder="En qué quedó (lo va a leer ella)"
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
