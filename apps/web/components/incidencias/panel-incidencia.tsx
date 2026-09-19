"use client";

// El caso abierto de Incidencias (rediseño 2026-09-15). Responde, en este
// orden, lo que alguien necesita para decidir sin salir de la pantalla: qué
// esperaba el sistema, qué ocurrió, por qué salió el aviso, qué se hizo ya
// (visto bueno, justificación) y qué se puede hacer ahora. Todo lo que cambia
// la historia de alguien pide confirmación o motivo; nada se decide solo.

import { useEffect, useState, type ReactNode, type RefObject } from "react";
import Link from "next/link";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { rangoDelDiaLima } from "@cayla-dynamic/shared";
import { Drawer } from "@/components/ui/drawer";
import { Insignia } from "@/components/ui/insignia";
import { Boton } from "@/components/ui/boton";
import { CampoSelect } from "@/components/ui/campo";
import { AreaTexto } from "@/components/ui/area-texto";
import { esperadoDelDia, type HorarioTramo, type TurnoDia } from "@/lib/admin/jornada-esperada";
import { estadoDe, type Incidencia } from "@/lib/admin/incidencias";
import { valorDeCorreccion } from "@/lib/admin/valor-de-correccion";
import {
  IconoIncidencia, REGLA, VISTO_BUENO, enlaceDe, fechaCorta, fechaHoraLima, fechaLarga, horaLima,
} from "./presentacion";

// Los códigos que acepta fn_set_justificacion (0124). La lista verdadera vive en
// esa función; esto solo pinta el desplegable, con los nombres de tipos_ausencia.
const MOTIVOS_JUSTIFICAR = ["permiso_concedido", "cumpleanos", "estudios", "descanso_medico", "otro"] as const;

/** Tipos cuyo aviso describe un día puntual de una persona: tiene marcas que mostrar. */
const DE_UN_DIA = new Set<Incidencia["tipo"]>([
  "auto_cierre", "sin_salida", "sin_retorno_almuerzo", "salida_anticipada",
  "falta_injustificada", "falta_justificada", "patron_tardanzas",
]);

interface Marca {
  id: string; tipo: string; timestamp_marca: string; origen: string | null;
  anulada_at: string | null; anulada_motivo: string | null;
}
interface Correccion {
  id: string; campo_modificado: string; valor_anterior: string | null; valor_nuevo: string | null;
  corregido_at: string; motivo: string | null; corregido_por: string;
}
interface VistoBuenoFila {
  id: string; valor: number | null; nota: string | null; aceptado_por: string; aceptado_at: string;
  anulada_at: string | null; anulada_por: string | null; anulada_motivo: string | null;
}
interface AusenciaDia {
  id: string; tipo: string; fecha_inicio: string; fecha_fin: string; motivo: string | null;
  registrada_por: string; registrada_at: string; aprobada_at: string | null;
  /** Embebido desde tipos_ausencia — para saber si "aprobada_at" fue una
   * decisión real de DO o si el tipo nace aprobado solo (vacaciones, 0442). */
  tipos_ausencia: { requiere_aprobacion: boolean } | null;
}
interface Rastro {
  marcas: Marca[];
  correcciones: Correccion[];
  vistosBuenos: VistoBuenoFila[];
  ausencia: AusenciaDia | null;
  esperado: { entrada: string | null; salida: string | null; trabaja: boolean; origen: string } | null;
  error: string | null;
}

/** El estado de una incidencia, en una insignia. Lo usa también la lista. */
export function EstadoInsignia({ incidencia }: { incidencia: Incidencia }) {
  const estado = estadoDe(incidencia);
  if (estado === "resuelta") {
    return <Insignia variante="positivo">{incidencia.tipo === "falta_justificada" ? "Justificada" : "Revisada"}</Insignia>;
  }
  if (estado === "preventivo") return <Insignia variante="advertencia">Preventivo</Insignia>;
  return <Insignia variante="informativo">{incidencia.aceptacionCaducada ? "Volvió a abrirse" : "Por revisar"}</Insignia>;
}

function Bloque({ titulo, children }: { titulo: string; children: ReactNode }) {
  return (
    <section className="flex flex-col gap-2">
      <h3 className="etiqueta text-taupe">{titulo}</h3>
      {children}
    </section>
  );
}

function diasEntre(desde: string, hasta: string): number {
  return Math.round((Date.parse(`${hasta}T00:00:00Z`) - Date.parse(`${desde}T00:00:00Z`)) / 86_400_000) + 1;
}

export function PanelIncidencia({
  incidencia,
  onCerrar,
  volverElFocoA,
  motivoNoPuedeActuar,
  etiquetaMotivo,
  nombrePorId,
  onCambio,
}: {
  incidencia: Incidencia | null;
  onCerrar: () => void;
  volverElFocoA: RefObject<HTMLElement | null>;
  /** null si quien mira puede actuar sobre este caso; si no, por qué no. */
  motivoNoPuedeActuar: string | null;
  etiquetaMotivo: (motivo: string | null) => string;
  nombrePorId: Map<string, string>;
  /** Recargar la bandeja. `claveNueva`: la clave con que el caso sigue existiendo
   * (una falta justificada cambia de tipo y, por lo tanto, de clave). */
  onCambio: (claveNueva?: string) => Promise<void>;
}) {
  const [rastro, setRastro] = useState<Rastro | null>(null);
  const [nota, setNota] = useState("");
  const [motivoDeshacer, setMotivoDeshacer] = useState("");
  const [deshaciendo, setDeshaciendo] = useState(false);
  const [motivoJustif, setMotivoJustif] = useState<(typeof MOTIVOS_JUSTIFICAR)[number]>("permiso_concedido");
  const [observacion, setObservacion] = useState("");
  const [quitando, setQuitando] = useState(false);
  const [motivoQuitar, setMotivoQuitar] = useState("");
  const [guardando, setGuardando] = useState(false);
  const [errorAccion, setErrorAccion] = useState<string | null>(null);

  const clave = incidencia?.clave ?? null;
  const personaId = incidencia?.personaId ?? null;
  const fecha = incidencia?.fecha ?? null;
  const tipoAceptable = incidencia?.aceptable ?? null;
  const esFaltaJustificada = incidencia?.tipo === "falta_justificada";
  const deUnDia = incidencia ? DE_UN_DIA.has(incidencia.tipo) : false;

  // Reiniciar el formulario y cargar el rastro cada vez que se abre otro caso.
  // Solo depende de la clave: las demás lecturas salen del mismo caso.
  useEffect(() => { void cargarRastro(); }, [clave]); // eslint-disable-line react-hooks/exhaustive-deps

  async function cargarRastro() {
    setRastro(null);
    setNota(""); setMotivoDeshacer(""); setDeshaciendo(false);
    setObservacion(""); setMotivoJustif("permiso_concedido");
    setQuitando(false); setMotivoQuitar(""); setErrorAccion(null);
    if (!personaId || !fecha) return;

    const supabase = createAdminSupabaseClient();
    const { inicio, fin } = rangoDelDiaLima(fecha);
    const [marcas, turno, horario, vistos, ausencia] = await Promise.all([
      deUnDia
        ? supabase.from("marcajes")
            .select("id, tipo, timestamp_marca, origen, anulada_at, anulada_motivo")
            .eq("persona_id", personaId).gte("timestamp_marca", inicio).lte("timestamp_marca", fin)
            .order("timestamp_marca")
        : Promise.resolve({ data: [], error: null }),
      deUnDia
        ? supabase.from("turnos").select("hora_entrada, hora_salida, es_descanso").eq("persona_id", personaId).eq("fecha", fecha).maybeSingle()
        : Promise.resolve({ data: null, error: null }),
      deUnDia
        ? supabase.from("horarios_asignados")
            .select("persona_id, vigente_desde, vigente_hasta, hora_entrada, hora_salida, dias_laborables, horario_por_dia, almuerzo_min_minutos")
            .eq("persona_id", personaId).lte("vigente_desde", fecha).or(`vigente_hasta.is.null,vigente_hasta.gte.${fecha}`)
            .order("vigente_desde", { ascending: false }).limit(1).maybeSingle()
        : Promise.resolve({ data: null, error: null }),
      // Toda la historia del visto bueno, también los deshechos: es el rastro.
      tipoAceptable
        ? supabase.from("incidencias_aceptadas")
            .select("id, valor, nota, aceptado_por, aceptado_at, anulada_at, anulada_por, anulada_motivo")
            .eq("persona_id", personaId).eq("fecha", fecha).eq("tipo", tipoAceptable)
            .order("aceptado_at", { ascending: false })
        : Promise.resolve({ data: [], error: null }),
      esFaltaJustificada
        ? supabase.from("ausencias")
            .select("id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por, registrada_at, aprobada_at, tipos_ausencia(requiere_aprobacion)")
            .eq("persona_id", personaId).is("anulada_at", null)
            .lte("fecha_inicio", fecha).gte("fecha_fin", fecha)
            .limit(1).maybeSingle()
        : Promise.resolve({ data: null, error: null }),
    ]);

    const marcasDia = (marcas.data as Marca[] | null) ?? [];
    // Las correcciones de las marcas de ESE día (la auditoría no guarda fecha).
    const correcciones = marcasDia.length > 0
      ? await supabase.from("correcciones_auditoria")
          .select("id, campo_modificado, valor_anterior, valor_nuevo, corregido_at, motivo, corregido_por")
          .in("marcaje_id", marcasDia.map((m) => m.id))
          .order("corregido_at", { ascending: false })
      : { data: [], error: null };

    const error = marcas.error ?? vistos.error ?? ausencia.error ?? correcciones.error;
    setRastro({
      marcas: marcasDia,
      correcciones: (correcciones.data as Correccion[] | null) ?? [],
      vistosBuenos: (vistos.data as VistoBuenoFila[] | null) ?? [],
      ausencia: (ausencia.data as AusenciaDia | null) ?? null,
      esperado: deUnDia
        ? esperadoDelDia(fecha, (turno.data as TurnoDia | null) ?? null, (horario.data as HorarioTramo | null) ?? null)
        : null,
      error: error ? error.message : null,
    });
  }

  if (!incidencia) {
    return <Drawer abierto={false} onCerrar={onCerrar} volverElFocoA={volverElFocoA}><span /></Drawer>;
  }
  const i = incidencia;
  const estado = estadoDe(i);
  const puedeActuar = motivoNoPuedeActuar === null;
  const enlace = enlaceDe(i);
  const quien = (id: string | null) => (id ? nombrePorId.get(id) ?? "otra persona" : "—");

  async function ejecutar(accion: () => PromiseLike<{ error: { message: string } | null }>, claveNueva?: string) {
    setGuardando(true);
    setErrorAccion(null);
    const { error } = await accion();
    setGuardando(false);
    if (error) { setErrorAccion(error.message); return; }
    await onCambio(claveNueva);
    await cargarRastro();
  }

  const supabase = createAdminSupabaseClient();
  const vistoBueno = i.aceptable ? VISTO_BUENO[i.aceptable] : null;
  const diasAusencia = rastro?.ausencia ? diasEntre(rastro.ausencia.fecha_inicio, rastro.ausencia.fecha_fin) : 0;
  // Mismo candado que fn_anular_ausencia (0442): una vez que DO aprobó un tipo
  // que de verdad exige su aprobación, deshacerlo deja de ser cosa de acá.
  // Sin este chequeo, el botón se mostraba igual y quien lo intentaba se
  // llevaba el error crudo del servidor en vez del mismo aviso que ya da
  // Ausencias — la misma acción resolviéndose de dos formas distintas.
  const ausenciaAprobadaPorDO = !!rastro?.ausencia?.aprobada_at && rastro.ausencia.tipos_ausencia?.requiere_aprobacion === true;
  const ausenciaQuitableAca = !!rastro?.ausencia && diasAusencia === 1 && rastro.ausencia.tipo !== "vacaciones" && !ausenciaAprobadaPorDO;

  return (
    <Drawer abierto onCerrar={onCerrar} bloqueado={guardando} volverElFocoA={volverElFocoA} titulo={i.nombre}>
      <div className="flex flex-col gap-6 text-sm">
        {/* ── Qué es ─────────────────────────────────────────────────── */}
        <div className="flex flex-col gap-3">
          <p className="text-taupe">
            {i.personaId ? `${i.sede} · ` : ""}{fechaLarga(i.fecha)}
          </p>
          <div className="flex items-start gap-3">
            <IconoIncidencia incidencia={i} />
            <div className="flex flex-1 flex-col gap-0.5">
              <span className="font-medium text-tinta">{i.titulo}</span>
              {i.detalle && <span className="text-taupe">{i.detalle}</span>}
            </div>
            <EstadoInsignia incidencia={i} />
          </div>
        </div>

        {i.aceptacionCaducada && (
          <p className="rounded-control bg-ambar/10 px-3 py-2 text-tinta">
            {quien(i.aceptacionCaducada.aceptadoPor)} la había dado por buena con{" "}
            <strong>{i.aceptacionCaducada.valor}</strong> el {fechaHoraLima(i.aceptacionCaducada.aceptadoAt)}. Una
            corrección cambió el número a <strong>{i.valor}</strong>, así que hace falta mirarla otra vez.
          </p>
        )}

        {/* ── Esperado y ocurrido ────────────────────────────────────── */}
        {deUnDia && (
          <Bloque titulo="Qué esperaba y qué ocurrió">
            <div className="grid grid-cols-2 overflow-hidden rounded-control border border-sand tabular-nums">
              <div className="flex flex-col gap-0.5 p-3">
                <span className="text-xs text-taupe">Horario esperado</span>
                <span className="text-base text-tinta">
                  {!rastro ? "…"
                    : !rastro.esperado || rastro.esperado.origen === "sin_horario" ? "Sin horario"
                    : !rastro.esperado.trabaja ? "Descanso"
                    : `${rastro.esperado.entrada ?? "—"} — ${rastro.esperado.salida ?? "—"}`}
                </span>
              </div>
              <div className="flex flex-col gap-0.5 border-l border-sand p-3">
                <span className="text-xs text-taupe">Marcas</span>
                <span className="text-base text-tinta">
                  {i.entrada ? `${horaLima(i.entrada)} → ${i.salida ? horaLima(i.salida) : "sin salida"}` : "Sin marcas"}
                </span>
              </div>
            </div>
          </Bloque>
        )}

        <Bloque titulo="Por qué salió este aviso">
          <p className="rounded-control bg-hueso px-3 py-2.5 leading-relaxed text-tinta">{REGLA[i.tipo]}</p>
        </Bloque>

        {motivoNoPuedeActuar && estado !== "resuelta" && (
          <p className="rounded-control bg-sand/60 px-3 py-2 text-tinta">{motivoNoPuedeActuar}</p>
        )}

        {/* ── Visto bueno ────────────────────────────────────────────── */}
        {i.aceptable && vistoBueno && (
          <Bloque titulo="Visto bueno">
            {i.aceptacion ? (
              <div className="flex flex-col gap-3">
                <p className="text-tinta">
                  <strong>{VISTO_BUENO[i.aceptable].boton}</strong> · {quien(i.aceptacion.aceptadoPor)},{" "}
                  {fechaHoraLima(i.aceptacion.aceptadoAt)}
                  {i.aceptacion.nota && <span className="block text-taupe">«{i.aceptacion.nota}»</span>}
                </p>
                {puedeActuar && !deshaciendo && (
                  <div>
                    <Boton variante="sutil" tamano="sm" onClick={() => setDeshaciendo(true)}>Deshacer visto bueno…</Boton>
                  </div>
                )}
                {puedeActuar && deshaciendo && (
                  <div className="flex flex-col gap-2 rounded-control border border-sand p-3">
                    <p className="text-tinta">El aviso vuelve a la lista. El visto bueno no se borra: queda en el historial como deshecho.</p>
                    <label htmlFor="incidencia-motivo-deshacer" className="text-sm text-taupe">Por qué lo deshaces (obligatorio)</label>
                    <AreaTexto
                      id="incidencia-motivo-deshacer"
                      value={motivoDeshacer}
                      onChange={(e) => setMotivoDeshacer(e.target.value)}
                      rows={2}
                    />
                    <div className="flex justify-end gap-2">
                      <Boton tamano="sm" onClick={() => setDeshaciendo(false)} disabled={guardando}>Cancelar</Boton>
                      <Boton
                        variante="peligro"
                        tamano="sm"
                        cargando={guardando}
                        disabled={motivoDeshacer.trim().length < 4}
                        onClick={() => void ejecutar(() => supabase.rpc("fn_quitar_aceptacion", {
                          p_persona_id: i.personaId!, p_fecha: i.fecha, p_tipo: i.aceptable!, p_motivo: motivoDeshacer.trim(),
                        }))}
                      >
                        Deshacer visto bueno
                      </Boton>
                    </div>
                  </div>
                )}
              </div>
            ) : puedeActuar ? (
              <div className="flex flex-col gap-2">
                <p className="leading-relaxed text-tinta">{vistoBueno.ayuda}</p>
                <label htmlFor="incidencia-nota" className="text-sm text-taupe">Nota (opcional, queda en el historial)</label>
                <AreaTexto
                  id="incidencia-nota"
                  value={nota}
                  onChange={(e) => setNota(e.target.value)}
                  rows={2}
                  placeholder="ej. avisó por WhatsApp que salía antes por cita médica"
                />
              </div>
            ) : null}
          </Bloque>
        )}

        {/* ── Justificación ──────────────────────────────────────────── */}
        {i.tipo === "falta_injustificada" && puedeActuar && (
          <Bloque titulo="Justificar la falta">
            <CampoSelect
              id="incidencia-motivo-justificar"
              etiqueta="Motivo"
              value={motivoJustif}
              onChange={(e) => setMotivoJustif(e.target.value as (typeof MOTIVOS_JUSTIFICAR)[number])}
            >
              {MOTIVOS_JUSTIFICAR.map((m) => <option key={m} value={m}>{etiquetaMotivo(m)}</option>)}
            </CampoSelect>
            {motivoJustif === "descanso_medico" ? (
              <p className="rounded-control bg-sand/60 px-3 py-2 text-tinta">
                El descanso médico <strong>se paga</strong>, así que necesita su documento (profesional o institución,
                colegiatura y fecha) y se registra en{" "}
                <Link href="/admin/ausencias" className="font-medium underline underline-offset-2">Ausencias</Link>.
                Si no hay documento, ahí mismo está «Descanso por salud»: no cuenta como falta, pero no paga.
              </p>
            ) : (
              <>
              <label htmlFor="incidencia-observacion" className="text-sm text-taupe">{motivoJustif === "otro" ? "Observación (obligatoria)" : "Observación (opcional)"}</label>
              <AreaTexto
                id="incidencia-observacion"
                value={observacion}
                onChange={(e) => setObservacion(e.target.value)}
                rows={2}
                placeholder="ej. permiso por trámite"
              />
              </>
            )}
          </Bloque>
        )}

        {esFaltaJustificada && (
          <Bloque titulo="Justificación">
            {!rastro ? (
              <p className="text-taupe">Cargando…</p>
            ) : rastro.ausencia ? (
              <div className="flex flex-col gap-3">
                <p className="text-tinta">
                  <strong>{etiquetaMotivo(rastro.ausencia.tipo)}</strong>
                  {diasAusencia > 1 && <> · del {fechaCorta(rastro.ausencia.fecha_inicio)} al {fechaCorta(rastro.ausencia.fecha_fin)} ({diasAusencia} días)</>}
                  <span className="block text-taupe">
                    Registrada por {quien(rastro.ausencia.registrada_por)}, {fechaHoraLima(rastro.ausencia.registrada_at)}
                    {rastro.ausencia.aprobada_at && " · aprobada por Desarrollo Organizacional"}
                  </span>
                  {rastro.ausencia.motivo && <span className="block text-taupe">«{rastro.ausencia.motivo}»</span>}
                </p>
                {!ausenciaQuitableAca && (
                  <p className="text-taupe">
                    {ausenciaAprobadaPorDO
                      ? "Ya la aprobó Desarrollo Organizacional — pídesela para anularla."
                      : diasAusencia > 1
                      ? `Abarca ${diasAusencia} días: quitarla desde acá anularía los ${diasAusencia}. Se gestiona en Ausencias.`
                      : "Las vacaciones se gestionan en Ausencias."}{" "}
                    <Link href="/admin/ausencias" className="font-medium text-tinta underline underline-offset-2">Ver en Ausencias →</Link>
                  </p>
                )}
                {ausenciaQuitableAca && puedeActuar && !quitando && (
                  <div>
                    <Boton variante="peligro" tamano="sm" onClick={() => setQuitando(true)}>Quitar justificación…</Boton>
                  </div>
                )}
                {ausenciaQuitableAca && puedeActuar && quitando && (
                  <div className="flex flex-col gap-2 rounded-control border border-rojo/30 p-3">
                    <p className="text-tinta">
                      El {fechaCorta(i.fecha)} volverá a contar como <strong>falta injustificada</strong>, y puede
                      entrar a un expediente en Disciplina.
                    </p>
                    <label htmlFor="incidencia-motivo-quitar" className="text-sm text-taupe">Por qué la quitas (obligatorio)</label>
                    <AreaTexto
                      id="incidencia-motivo-quitar"
                      value={motivoQuitar}
                      onChange={(e) => setMotivoQuitar(e.target.value)}
                      rows={2}
                    />
                    <div className="flex justify-end gap-2">
                      <Boton tamano="sm" onClick={() => setQuitando(false)} disabled={guardando}>Cancelar</Boton>
                      <Boton
                        variante="peligro"
                        tamano="sm"
                        cargando={guardando}
                        disabled={motivoQuitar.trim().length < 4}
                        onClick={() => void ejecutar(
                          () => supabase.rpc("fn_anular_ausencia", { p_id: rastro.ausencia!.id, p_motivo: motivoQuitar.trim() }),
                          `falta_injustificada|${i.personaId}|${i.fecha}`,
                        )}
                      >
                        Quitar justificación
                      </Boton>
                    </div>
                  </div>
                )}
              </div>
            ) : (
              // Suspensión y descanso sustitutorio no son ausencias (0101): no se quitan desde acá.
              <p className="text-taupe">
                {i.motivoFalta === "suspension"
                  ? <>Es un día de suspensión disciplinaria: se gestiona en{" "}
                      <Link href="/admin/disciplina" className="font-medium text-tinta underline underline-offset-2">Disciplina</Link>.</>
                  : i.motivoFalta === "descanso_sustitutorio"
                    ? "Es un descanso sustitutorio por feriado trabajado: no es una ausencia y no se quita desde acá."
                    : `${etiquetaMotivo(i.motivoFalta ?? null)}: no es una ausencia registrada, así que no se quita desde acá.`}
              </p>
            )}
          </Bloque>
        )}

        {/* ── Rastro del día ─────────────────────────────────────────── */}
        {i.personaId && (deUnDia || i.aceptable) && (
          <Bloque titulo="Rastro">
            {!rastro ? (
              <p className="text-taupe">Cargando…</p>
            ) : rastro.error ? (
              // No se dice «sin correcciones» si no se pudo comprobar.
              <p className="text-rojo-profundo">No se pudo cargar el rastro de este día: {rastro.error}</p>
            ) : (
              <ul className="flex flex-col gap-1.5 tabular-nums">
                {rastro.marcas.map((m) => (
                  <li key={m.id} className="flex gap-3">
                    <span className="w-12 shrink-0 text-taupe">{horaLima(m.timestamp_marca)}</span>
                    <span className={m.anulada_at ? "text-taupe line-through" : "text-tinta"}>
                      Marca: {m.tipo.replaceAll("_", " ")}{m.origen && m.origen !== "terminal" ? ` · ${m.origen.replaceAll("_", " ")}` : ""}
                    </span>
                    {m.anulada_at && <span className="text-taupe">anulada: {m.anulada_motivo}</span>}
                  </li>
                ))}
                {rastro.correcciones.map((c) => (
                  <li key={c.id} className="flex gap-3">
                    <span className="w-12 shrink-0 text-taupe">{fechaCorta(c.corregido_at.slice(0, 10))}</span>
                    <span className="text-tinta">
                      Corrección de {c.campo_modificado.replaceAll("_", " ")}
                      {c.valor_anterior || c.valor_nuevo ? `: ${valorDeCorreccion(c.valor_anterior)} → ${valorDeCorreccion(c.valor_nuevo)}` : ""}
                      <span className="block text-taupe">{quien(c.corregido_por)}{c.motivo ? ` · «${c.motivo}»` : ""}</span>
                    </span>
                  </li>
                ))}
                {rastro.vistosBuenos.map((v) => (
                  <li key={v.id} className="flex gap-3">
                    <span className="w-12 shrink-0 text-taupe">{fechaCorta(v.aceptado_at.slice(0, 10))}</span>
                    <span className={v.anulada_at ? "text-taupe" : "text-tinta"}>
                      Visto bueno de {quien(v.aceptado_por)}{v.valor !== null ? ` (sobre ${v.valor})` : ""}
                      {v.anulada_at && (
                        <span className="block">Deshecho por {quien(v.anulada_por)}: «{v.anulada_motivo}»</span>
                      )}
                    </span>
                  </li>
                ))}
                {rastro.marcas.length + rastro.correcciones.length + rastro.vistosBuenos.length === 0 && (
                  <li className="text-taupe">{deUnDia ? "Sin marcas, correcciones ni vistos buenos ese día." : "Sin vistos buenos anteriores."}</li>
                )}
              </ul>
            )}
          </Bloque>
        )}

        {errorAccion && (
          <p className="whitespace-pre-line rounded-control bg-rojo/10 px-3 py-2 text-rojo-profundo">{errorAccion}</p>
        )}

        {/* ── Acciones ───────────────────────────────────────────────── */}
        <div className="flex flex-wrap justify-end gap-2 border-t border-sand pt-4">
          {enlace && (
            <Link
              href={enlace.href}
              className="rounded-control border border-sand px-4 py-2 text-tinta transition-colors duration-150 hover:border-taupe/40 hover:bg-sand/50"
            >
              {enlace.etiqueta} →
            </Link>
          )}
          {i.aceptable && vistoBueno && !i.aceptacion && puedeActuar && (
            <Boton
              variante="primario"
              cargando={guardando}
              onClick={() => void ejecutar(() => supabase.rpc("fn_aceptar_incidencia", {
                p_persona_id: i.personaId!, p_fecha: i.fecha, p_tipo: i.aceptable!,
                p_nota: nota.trim() || null, p_valor: i.valor,
              }))}
            >
              {vistoBueno.boton}
            </Boton>
          )}
          {i.tipo === "falta_injustificada" && puedeActuar && (
            <Boton
              variante="primario"
              cargando={guardando}
              disabled={motivoJustif === "descanso_medico" || (motivoJustif === "otro" && observacion.trim().length < 3)}
              onClick={() => void ejecutar(
                () => supabase.rpc("fn_set_justificacion", {
                  p_persona_id: i.personaId!, p_fecha: i.fecha, p_motivo: motivoJustif,
                  p_observacion: observacion.trim() || null,
                }),
                `falta_justificada|${i.personaId}|${i.fecha}`,
              )}
            >
              Justificar
            </Boton>
          )}
        </div>
      </div>
    </Drawer>
  );
}
