"use client";

// ============================================================================
// Ausencias — un solo lugar para «por qué no vino»
// ----------------------------------------------------------------------------
// Absorbe la pantalla de Vacaciones: vacaciones es un tipo de ausencia más, no
// una pantalla aparte. Si fueran dos, tarde o temprano una diría una cosa y la
// otra otra — es el error que este repositorio ya pagó varias veces.
//
// Lo que esta pantalla evita, y es la razón de que exista: hasta la migración
// 0101, un día de permiso concedido se registraba como falta injustificada,
// entraba en el semáforo disciplinario y podía terminar en una carta de
// preaviso de despido por días que la propia empresa concedió.
//
// La regla del pago no la decide esta pantalla: viene del catálogo
// `tipos_ausencia`. Descanso médico y maternidad pagan porque lo manda la ley
// peruana; el resto no paga porque así lo decidió CAYLA.
// ============================================================================

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { AdminNav } from "../nav";
import { Cargando } from "@/components/cargando";
import { useRolActual } from "@/lib/admin/use-rol";

function fmt(iso: string | null | undefined): string {
  if (!iso) return "—";
  const [y, m, d] = iso.split("-");
  if (!y || !m || !d) return iso;
  return `${d}/${m}/${y}`;
}
// Hoy en Lima. Con new Date().toISOString() (UTC) a partir de las 19:00 daría mañana.
function hoyLima(): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Lima", year: "numeric", month: "2-digit", day: "2-digit",
  }).format(new Date());
}
function haceMeses(n: number): string {
  const [y, m, d] = hoyLima().split("-").map(Number);
  return new Date(Date.UTC(y, m - 1 - n, d)).toISOString().slice(0, 10);
}

interface Persona { id: string; nombres: string; apellidos: string }
interface Tipo {
  codigo: string; nombre: string; paga: boolean;
  requiere_documento: boolean; requiere_aprobacion: boolean;
}
interface Ausencia {
  id: string; persona_id: string; nombre: string; sede: string;
  tipo: string; tipo_nombre: string; paga: boolean; requiere_aprobacion: boolean;
  fecha_inicio: string; fecha_fin: string; dias: number; motivo: string | null;
  doc_profesional: string | null; doc_colegiatura: string | null; doc_fecha: string | null;
  aprobada: boolean; registrada_tarde: boolean;
  registrada_por_nombre: string | null; registrada_at: string;
  anulada: boolean; anulada_motivo: string | null;
}
interface Alerta {
  persona_id: string; nombre: string; tipo_nombre: string;
  veces: number; ventana_dias: number; umbral: number;
}

export default function AusenciasPage() {
  const router = useRouter();
  const rol = useRolActual();
  const puedeGestionar = rol === "admin" || rol === "lider_do" || rol === "supervisor_sede";
  const esDO = rol === "admin" || rol === "lider_do";
  const supabase = useMemo(() => createAdminSupabaseClient(), []);

  const [personas, setPersonas] = useState<Persona[]>([]);
  const [tipos, setTipos] = useState<Tipo[]>([]);
  const [lista, setLista] = useState<Ausencia[]>([]);
  const [alertas, setAlertas] = useState<Alerta[]>([]);
  const [cargando, setCargando] = useState(true);
  const [msg, setMsg] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);
  const [guardando, setGuardando] = useState(false);

  // Formulario
  const [personaId, setPersonaId] = useState("");
  const [tipoCod, setTipoCod] = useState("");
  const [inicio, setInicio] = useState(hoyLima());
  const [fin, setFin] = useState(hoyLima());
  const [motivo, setMotivo] = useState("");
  const [docProf, setDocProf] = useState("");
  const [docColeg, setDocColeg] = useState("");
  const [docFecha, setDocFecha] = useState("");

  const [desde, setDesde] = useState(haceMeses(6));
  const [hasta, setHasta] = useState(haceMeses(-6));

  const tipoSel = tipos.find((t) => t.codigo === tipoCod) ?? null;

  const cargar = useCallback(async () => {
    setCargando(true);
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    const [{ data: p, error: eP }, { data: t }, { data: a, error: eA }, { data: al }] = await Promise.all([
      supabase.from("personas").select("id, nombres, apellidos").eq("estado", "activo").order("nombres"),
      supabase.rpc("fn_tipos_ausencia"),
      supabase.rpc("fn_ausencias", { p_desde: desde, p_hasta: hasta }),
      supabase.rpc("fn_ausencias_alerta", {}),
    ]);
    // Si la carga falla no se pisa la lista con datos parciales: mostrar media
    // lista de ausencias es peor que no mostrar ninguna.
    if (eP || eA) {
      setMsg({ tipo: "error", texto: `No se pudieron cargar las ausencias: ${(eP ?? eA)!.message}` });
      setCargando(false);
      return;
    }
    setPersonas((p as Persona[]) ?? []);
    const tt = (t as unknown as Tipo[]) ?? [];
    setTipos(tt);
    setTipoCod((prev) => prev || tt[0]?.codigo || "");
    setLista((a as unknown as Ausencia[]) ?? []);
    setAlertas((al as unknown as Alerta[]) ?? []);
    setCargando(false);
  }, [supabase, router, desde, hasta]);

  useEffect(() => { void cargar(); }, [cargar]);

  async function registrar() {
    if (!personaId) { setMsg({ tipo: "error", texto: "Elige a la persona." }); return; }
    if (!tipoCod) { setMsg({ tipo: "error", texto: "Elige el tipo de ausencia." }); return; }
    if (fin < inicio) { setMsg({ tipo: "error", texto: "La fecha de fin no puede ser anterior a la de inicio." }); return; }
    setGuardando(true);
    setMsg(null);
    const { error } = await supabase.rpc("fn_registrar_ausencia", {
      p_persona_id: personaId,
      p_tipo: tipoCod,
      p_fecha_inicio: inicio,
      p_fecha_fin: fin,
      p_motivo: motivo.trim() || null,
      p_doc_profesional: docProf.trim() || null,
      p_doc_colegiatura: docColeg.trim() || null,
      p_doc_fecha: docFecha || null,
    });
    setGuardando(false);
    if (error) { setMsg({ tipo: "error", texto: error.message }); return; }
    setMotivo(""); setDocProf(""); setDocColeg(""); setDocFecha("");
    await cargar();
    setMsg({
      tipo: "ok",
      texto: tipoSel?.requiere_aprobacion
        ? "Registrada. Como es un tipo que se paga, queda pendiente de aprobación de Desarrollo Organizacional."
        : "Registrada. Esos días dejan de contar como falta injustificada.",
    });
  }

  async function anular(a: Ausencia) {
    const m = window.prompt(
      `Vas a anular «${a.tipo_nombre}» de ${a.nombre} (${fmt(a.fecha_inicio)} → ${fmt(a.fecha_fin)}).\n\n` +
        "No se borra: queda en el historial con el motivo. ¿Por qué se anula?",
    );
    if (m === null) return;
    if (m.trim().length < 4) { setMsg({ tipo: "error", texto: "El motivo es obligatorio (mínimo 4 caracteres)." }); return; }
    setGuardando(true);
    const { error } = await supabase.rpc("fn_anular_ausencia", { p_id: a.id, p_motivo: m.trim() });
    setGuardando(false);
    if (error) { setMsg({ tipo: "error", texto: error.message }); return; }
    await cargar();
    setMsg({ tipo: "ok", texto: "Ausencia anulada. Esos días vuelven a contarse como antes." });
  }

  async function aprobar(a: Ausencia) {
    if (!window.confirm(
      `Aprobar «${a.tipo_nombre}» de ${a.nombre}, ${a.dias} día${a.dias === 1 ? "" : "s"}.\n\n` +
      "Es un tipo que SE PAGA: al aprobarlo, esos días entran en su planilla.",
    )) return;
    setGuardando(true);
    const { error } = await supabase.rpc("fn_aprobar_ausencia", { p_id: a.id });
    setGuardando(false);
    if (error) { setMsg({ tipo: "error", texto: error.message }); return; }
    await cargar();
    setMsg({ tipo: "ok", texto: "Aprobada." });
  }

  if (rol !== null && !puedeGestionar) {
    return (
      <div className="flex min-h-screen flex-col">
        <AdminNav />
        <main className="flex flex-1 items-center justify-center p-6">
          <p className="max-w-md text-center text-taupe">No tienes permiso para gestionar ausencias.</p>
        </main>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <h1 className="mb-1 font-serif text-2xl">Ausencias</h1>
        <p className="mb-4 max-w-3xl text-xs text-taupe">
          Todos los días que alguien no vino, y por qué — vacaciones incluidas. Un día registrado aquí{" "}
          <strong className="font-medium">deja de contar como falta injustificada</strong> y no alimenta el
          expediente disciplinario. En CAYLA ningún permiso se paga, salvo los dos que la ley obliga a pagar:
          descanso médico con documento y maternidad.
        </p>

        {msg && (
          <div className={`mb-4 max-w-3xl rounded-lg px-4 py-3 text-sm ${msg.tipo === "ok" ? "bg-sand/40 text-tinta" : "bg-rojo/10 text-rojo"}`}>
            {msg.texto}
          </div>
        )}

        {alertas.length > 0 && (
          <div className="mb-4 max-w-3xl rounded-lg bg-ambar/15 px-4 py-3 text-sm text-ambar">
            <p className="font-medium">Para mirar, no para sancionar:</p>
            <ul className="mt-1 space-y-0.5 text-xs">
              {alertas.map((a) => (
                <li key={`${a.persona_id}-${a.tipo_nombre}`}>
                  <strong className="font-medium">{a.nombre}</strong> lleva {a.veces} veces «{a.tipo_nombre}»
                  en los últimos {a.ventana_dias} días (el aviso salta a partir de {a.umbral}).
                </li>
              ))}
            </ul>
            <p className="mt-1.5 text-xs opacity-80">
              El sistema cuenta y lo dice. Conversar o no es decisión de una persona, siempre.
            </p>
          </div>
        )}

        {/* Registrar */}
        <div className="mb-6 grid max-w-4xl gap-3 rounded-2xl border border-sand bg-papel p-5 sm:grid-cols-2">
          <label className="flex flex-col gap-1 text-sm">
            Persona
            <select value={personaId} onChange={(e) => setPersonaId(e.target.value)} className="rounded-lg border bg-crema px-3 py-2">
              <option value="">Elegir…</option>
              {personas.map((p) => (<option key={p.id} value={p.id}>{p.nombres} {p.apellidos}</option>))}
            </select>
          </label>
          <label className="flex flex-col gap-1 text-sm">
            Tipo
            <select value={tipoCod} onChange={(e) => setTipoCod(e.target.value)} className="rounded-lg border bg-crema px-3 py-2">
              {tipos.map((t) => (
                <option key={t.codigo} value={t.codigo}>
                  {t.nombre}{t.paga ? " · se paga" : ""}
                </option>
              ))}
            </select>
          </label>
          <label className="flex flex-col gap-1 text-sm">
            Desde
            <input type="date" value={inicio} onChange={(e) => { setInicio(e.target.value); if (fin < e.target.value) setFin(e.target.value); }} className="rounded-lg border px-3 py-2" />
          </label>
          <label className="flex flex-col gap-1 text-sm">
            Hasta
            <input type="date" value={fin} onChange={(e) => setFin(e.target.value)} className="rounded-lg border px-3 py-2" />
          </label>
          <label className="flex flex-col gap-1 text-sm sm:col-span-2">
            Motivo <span className="text-taupe">(lo que se conversó; queda en su historial)</span>
            <input value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="ej. fallecimiento de familiar directo" className="rounded-lg border px-3 py-2" />
          </label>

          {tipoSel?.requiere_documento && (
            <>
              <p className="text-xs text-taupe sm:col-span-2">
                Este tipo <strong className="font-medium">se paga</strong>, así que exige documento. No se guarda el
                papel: se guarda quién lo firmó y con qué colegiatura, que es lo verificable. Si no hay documento,
                regístralo como <strong className="font-medium">Descanso por salud</strong> — no paga, pero tampoco
                cuenta como falta.
              </p>
              <label className="flex flex-col gap-1 text-sm">
                Profesional o institución
                <input value={docProf} onChange={(e) => setDocProf(e.target.value)} placeholder="ej. Dra. Rojas / Clínica San Pablo" className="rounded-lg border px-3 py-2" />
              </label>
              <label className="flex flex-col gap-1 text-sm">
                N.º de colegiatura (CMP) o de CITT
                <input value={docColeg} onChange={(e) => setDocColeg(e.target.value)} placeholder="ej. CMP 12345" className="rounded-lg border px-3 py-2" />
              </label>
              <label className="flex flex-col gap-1 text-sm">
                Fecha de emisión
                <input type="date" value={docFecha} onChange={(e) => setDocFecha(e.target.value)} className="rounded-lg border px-3 py-2" />
              </label>
            </>
          )}

          <div className="flex items-end gap-3 sm:col-span-2">
            <button onClick={registrar} disabled={guardando} className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema disabled:opacity-50">
              {guardando ? "Guardando…" : "Registrar ausencia"}
            </button>
            {tipoSel && (
              <span className="text-xs text-taupe">
                {tipoSel.paga
                  ? "Se paga · lo aprueba Desarrollo Organizacional antes de entrar en planilla."
                  : "No se paga · esos días no se cobran, pero tampoco son falta."}
              </span>
            )}
          </div>
        </div>

        {/* Rango a mostrar */}
        <div className="mb-3 flex flex-wrap items-end gap-3">
          <label className="flex flex-col gap-1 text-xs text-taupe">
            Desde
            <input type="date" value={desde} onChange={(e) => setDesde(e.target.value)} className="rounded-lg border px-3 py-1.5 text-sm text-tinta" />
          </label>
          <label className="flex flex-col gap-1 text-xs text-taupe">
            Hasta
            <input type="date" value={hasta} onChange={(e) => setHasta(e.target.value)} className="rounded-lg border px-3 py-1.5 text-sm text-tinta" />
          </label>
        </div>

        {cargando ? (
          <Cargando texto="Cargando las ausencias…" />
        ) : lista.length === 0 ? (
          <div className="max-w-2xl rounded-lg bg-sand/40 px-4 py-3 text-sm text-taupe">
            No hay ausencias registradas en ese rango de fechas.
          </div>
        ) : (
          <div className="overflow-x-auto rounded-2xl border border-sand">
            <table className="w-full text-sm">
              <thead className="bg-sand/70 text-left text-taupe">
                <tr>
                  <th className="px-4 py-2 font-normal">Persona</th>
                  <th className="px-4 py-2 font-normal">Tipo</th>
                  <th className="px-4 py-2 font-normal">Fechas</th>
                  <th className="px-4 py-2 text-right font-normal">Días</th>
                  <th className="px-4 py-2 font-normal">Estado</th>
                  <th className="px-4 py-2 font-normal">Acciones</th>
                </tr>
              </thead>
              <tbody>
                {lista.map((a) => (
                  <tr key={a.id} className={`border-t bg-papel ${a.anulada ? "text-taupe/60" : ""}`}>
                    <td className="px-4 py-2">
                      <span className={a.anulada ? "line-through" : ""}>{a.nombre}</span>
                      <div className="text-xs text-taupe">{a.sede}</div>
                    </td>
                    <td className="px-4 py-2">
                      {a.tipo_nombre}
                      {a.paga && <span className="ml-1.5 rounded-full bg-sand px-2 py-0.5 text-xs">se paga</span>}
                      {a.motivo && <div className="text-xs text-taupe">{a.motivo}</div>}
                      {a.doc_colegiatura && (
                        <div className="text-xs text-taupe">
                          {a.doc_profesional} · {a.doc_colegiatura} · {fmt(a.doc_fecha)}
                        </div>
                      )}
                    </td>
                    <td className="px-4 py-2 whitespace-nowrap">
                      {fmt(a.fecha_inicio)} → {fmt(a.fecha_fin)}
                      {a.registrada_tarde && !a.anulada && (
                        <div className="text-xs text-ambar">registrada con más de 15 días de retraso</div>
                      )}
                      <div className="text-xs text-taupe">
                        registró {a.registrada_por_nombre ?? "—"}
                      </div>
                    </td>
                    <td className="px-4 py-2 text-right tabular-nums">{a.dias}</td>
                    <td className="px-4 py-2">
                      {a.anulada ? (
                        <>
                          <span className="rounded-full bg-sand px-2 py-0.5 text-xs">anulada</span>
                          <div className="text-xs text-taupe">{a.anulada_motivo}</div>
                        </>
                      ) : a.requiere_aprobacion && !a.aprobada ? (
                        <span className="rounded-full bg-ambar/20 px-2 py-0.5 text-xs text-ambar">
                          pendiente de aprobar
                        </span>
                      ) : (
                        <span className="rounded-full bg-sand px-2 py-0.5 text-xs">vigente</span>
                      )}
                    </td>
                    <td className="px-4 py-2">
                      {!a.anulada && (
                        <div className="flex flex-wrap gap-2 text-xs">
                          {esDO && a.requiere_aprobacion && !a.aprobada && (
                            <button onClick={() => void aprobar(a)} disabled={guardando} className="rounded border px-2 py-1 hover:bg-sand/50 disabled:opacity-50">
                              Aprobar
                            </button>
                          )}
                          <button onClick={() => void anular(a)} disabled={guardando} className="rounded border border-rojo/30 px-2 py-1 text-rojo hover:bg-rojo/10 disabled:opacity-50">
                            Anular
                          </button>
                        </div>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        <p className="mt-4 max-w-3xl text-xs text-taupe">
          Una ausencia no se borra: se anula con motivo y queda en el historial. Y no se puede registrar ni
          anular nada dentro de un periodo de planilla ya pagado — para eso hay que reabrirlo primero, igual
          que con todo lo demás que toca plata.
        </p>
      </main>
    </div>
  );
}
