"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { Info } from "lucide-react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { hoyLima } from "@cayla-dynamic/shared";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { fechaLargaLima } from "@/lib/admin/planilla/formato";
import { reducirImagen, pesoLegible } from "@/lib/reducir-imagen";
import { subirArchivoConProgreso } from "@/lib/subir-archivo";
import { useToast } from "@/components/toast";
import { Boton } from "@/components/ui/boton";
import { Insignia } from "@/components/ui/insignia";
import { Campo, CampoCasilla, CampoSelect } from "@/components/ui/campo";
import { AreaTexto } from "@/components/ui/area-texto";
import { Cargando } from "@/components/cargando";
import { cx } from "@/components/ui/cx";
import {
  NOMBRE_ACCION, NOMBRE_EVENTO, RESULTADOS_CIERRE, TIPOS_DE_ADJUNTO, accionesDelCaso, etiquetaDeEstado,
  etiquetaDeVia, fechaEnPalabras, rutaDeAdjunto, tituloDeReporte, type MotivoCaso,
} from "@/lib/reportes";

/**
 * La ficha de un caso, para quien lo gestiona (plan, sección 9).
 *
 * ABRIRLA DEJA RASTRO (`fn_reporte_abrir`, 44.13): el aviso de arriba lo dice.
 *
 * LOS BOTONES LOS OFRECE `accionesDelCaso` (lib/reportes.ts), según POR QUÉ
 * esta persona ve el caso —líder, DO, Gerencia, quien investiga—: la líder
 * media y escala pero no cierra convivencia; en el Título X nadie media; sin
 * informe DO no decide. Es la misma tabla de la 0488 vista desde la pantalla.
 * Si la base dice otra cosa, su mensaje se muestra tal cual.
 *
 * UN REPORTE NO ES UNA FALTA. «Enlazar a disciplina» no crea ni sanciona nada:
 * enlaza un expediente que ya se abrió en Disciplina, de una persona involucrada.
 */

type Detalle = {
  codigo: string; tipo: string; via: string; estado: string; urgente: boolean; sede_codigo: string;
  fecha_hecho: string; relato: string; espera: string | null; creado_at: string; cerrado_at: string | null;
  cierre_texto: string | null; cierre_resultado: string | null; mi_papel: string; autora: string | null; gestiona: string | null;
};
type Mensaje = { id: string; texto: string; interno: boolean; creado_at: string; es_mio: boolean; quien: string };
type Plazo = { clave: string; norma: string; descripcion: string; duena: string; vence_at: string; cumplido_at: string | null; anulado_at: string | null; nota: string | null };
type Persona = { persona_id: string; nombre: string; papel: string };
type Evento = { id: string; at: string; tipo: string; quien: string; detalle: Record<string, unknown> };
type Medida = { id: string; para: string; instruccion: string; vigente_hasta: string | null; cumplida_at: string | null; creado_at: string };
type Adjunto = { id: string; storage_path: string; mimetype: string | null; bytes: number | null; interno: boolean; creado_at: string };

const ESPERA: Record<string, string> = {
  que_se_sepa: "que quede registrado", conversar: "conversar", que_cambie: "que cambie algo", que_se_actue: "que se actúe",
};
const LLEVA: Record<string, string> = { lider: "la líder de equipo", do: "Desarrollo Organizacional", gerencia: "la Gerencia General" };
const MANUALES = new Set(["salud", "traslado", "aviso_mtpe", "informe", "aviso_decision", "delito"]);
const VIAS = [
  { valor: "reclamo", texto: "Reclamo o sugerencia · 43-B" },
  { valor: "convivencia", texto: "Convivencia · 43-A" },
  { valor: "titulo_x", texto: "Título X · hostigamiento sexual" },
];

export default function FichaCaso() {
  const { id } = useParams<{ id: string }>();
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const { avisar } = useToast();

  const [motivo, setMotivo] = useState<string | null>(null);
  const [d, setD] = useState<Detalle | null>(null);
  const [hilo, setHilo] = useState<Mensaje[]>([]);
  const [plazos, setPlazos] = useState<Plazo[]>([]);
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [eventos, setEventos] = useState<Evento[]>([]);
  const [medidas, setMedidas] = useState<Medida[]>([]);
  const [adjuntos, setAdjuntos] = useState<Adjunto[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [panel, setPanel] = useState<string | null>(null);
  const [ocupada, setOcupada] = useState(false);
  // El instante contra el que se mide «vencido», fijado al abrir la ficha: el
  // render no puede leer el reloj (react-hooks/purity), y recargar lo renueva.
  const [ahora] = useState(() => Date.now());

  const cargar = useCallback(async () => {
    const [det, h, pl, pe, ev, me, ad] = await Promise.all([
      supabase.rpc("fn_reporte_detalle", { p_reporte: id }),
      supabase.rpc("fn_reporte_hilo", { p_reporte: id }),
      supabase.rpc("fn_reporte_plazos", { p_reporte: id }),
      supabase.rpc("fn_reporte_personas", { p_reporte: id }),
      supabase.rpc("fn_reporte_eventos", { p_reporte: id }),
      supabase.rpc("fn_reporte_medidas", { p_reporte: id }),
      supabase.rpc("fn_reporte_adjuntos", { p_reporte: id }),
    ]);
    if (det.error || !det.data?.[0]) { setError(mensajeDeError(det.error, "abrir este caso")); return; }
    setError(null);
    setD(det.data[0] as Detalle);
    setHilo((h.data ?? []) as Mensaje[]);
    setPlazos((pl.data ?? []) as Plazo[]);
    setPersonas((pe.data ?? []) as Persona[]);
    setEventos((ev.data ?? []) as Evento[]);
    setMedidas((me.data ?? []) as Medida[]);
    setAdjuntos((ad.data ?? []) as Adjunto[]);
  }, [supabase, id]);

  useEffect(() => {
    void (async () => {
      const a = await supabase.rpc("fn_reporte_abrir", { p_reporte: id });
      if (a.error) { setError(mensajeDeError(a.error, "abrir este caso")); return; }
      setMotivo(a.data as string);
      await cargar();
    })();
  }, [supabase, id, cargar]);

  /** Corre una acción de la base, avisa y recarga. Devuelve si salió bien. */
  async function hacer(que: string, llamada: PromiseLike<{ error: { message: string; code?: string } | null }>, ok: string) {
    setOcupada(true);
    const { error: e } = await llamada;
    setOcupada(false);
    if (e) { avisar("error", mensajeDeError(e, que)); return false; }
    avisar("ok", ok);
    setPanel(null);
    await cargar();
    return true;
  }

  if (error) {
    return (
      <main className="flex-1 p-6 text-sm">
        <div className="mx-auto max-w-5xl">
          <p className="rounded-control bg-rojo/10 px-3 py-2 text-rojo-profundo">{error}</p>
          <Link href="/admin/casos" className="mt-4 inline-block underline underline-offset-2">← Casos</Link>
        </div>
      </main>
    );
  }
  if (!d || !motivo) return <main className="flex-1 p-6"><Cargando /></main>;

  if (motivo === "autora") {
    return (
      <main className="flex-1 p-6 text-sm">
        <div className="mx-auto max-w-5xl">
          <p className="text-taupe">Este reporte lo enviaste tú: se sigue desde <Link className="underline" href={`/mio/reportes/${id}`}>Info → Reportes</Link>.</p>
        </div>
      </main>
    );
  }

  const informeRegistrado = plazos.some((p) => p.clave === "informe" && p.cumplido_at && !p.anulado_at);
  const respuestaPendiente = plazos.some((p) => p.clave === "respuesta" && !p.cumplido_at && !p.anulado_at);
  const acc = accionesDelCaso({ motivo: motivo as MotivoCaso, via: d.via, estado: d.estado, gestiona: d.gestiona, informeRegistrado, respuestaPendiente });
  const estado = etiquetaDeEstado(d.estado);
  const involucradas = personas.filter((p) => p.papel === "involucrada");
  const testigos = personas.filter((p) => p.papel === "testigo");
  const lecturas = eventos.filter((e) => e.tipo === "lectura").length;
  const vivos = plazos.filter((p) => !p.anulado_at);

  async function verAdjunto(a: Adjunto) {
    const { data, error: e } = await supabase.storage.from("reportes").createSignedUrl(a.storage_path, 60);
    if (e || !data) { avisar("error", "No se pudo abrir el archivo."); return; }
    window.open(data.signedUrl, "_blank", "noopener");
  }

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6 text-sm text-tinta">
        <div className="mx-auto w-full max-w-5xl">
          <Link href="/admin/casos" className="mb-4 inline-block rounded-control border border-sand px-3 py-1 text-xs text-taupe hover:text-tinta">
            ← Casos
          </Link>
          <div className="mb-2 flex flex-wrap items-end justify-between gap-3">
            <div>
              <p className="etiqueta text-taupe">{etiquetaDeVia(d.via, d.tipo)} · {d.sede_codigo} · <span className="tabular-nums">{d.codigo}</span></p>
              <h1 className="mt-0.5 font-serif text-2xl">{tituloDeReporte(d.tipo, d.via)}</h1>
              <p className="mt-1 text-taupe">
                De {d.autora ?? "—"} (confidencial)
                {involucradas.length > 0 && <> · sobre {involucradas.map((p) => p.nombre).join(", ")}</>}
                {testigos.length > 0 && <> · testigos: {testigos.map((p) => p.nombre).join(", ")}</>}
              </p>
            </div>
            <div className="flex flex-wrap gap-1.5">
              {d.urgente && <Insignia variante="alerta">Urgente</Insignia>}
              <Insignia variante={estado.variante}>{estado.texto}</Insignia>
              {d.gestiona && <Insignia variante="neutral" punto={false}>Lo lleva {LLEVA[d.gestiona] ?? d.gestiona}</Insignia>}
            </div>
          </div>
          <p className="mb-5 flex items-center gap-2 text-xs text-taupe">
            <Info className="size-4" strokeWidth={1.8} aria-hidden />
            Abrir esta ficha queda registrado (44.13){lecturas > 1 ? ` · se abrió ${lecturas} veces` : ""}. Un reporte no es una falta.
          </p>

          <div className="grid items-start gap-4 lg:grid-cols-[minmax(0,1fr)_320px]">
            <div className="grid gap-4">
              <section className="rounded-superficie border border-sand bg-papel p-5">
                <p className="etiqueta mb-1.5 text-taupe">Lo reportado · {fechaLargaLima(d.fecha_hecho + "T12:00:00-05:00")}</p>
                <p className="whitespace-pre-line">{d.relato}</p>
                {d.espera && <p className="mt-2 text-xs text-taupe">Espera: <strong className="font-medium text-tinta">{ESPERA[d.espera] ?? d.espera}</strong></p>}
                {adjuntos.length > 0 && (
                  <ul className="mt-3 flex flex-wrap gap-2 text-xs">
                    {adjuntos.map((a, i) => (
                      <li key={a.id}>
                        <button type="button" className="rounded-pildora bg-sand px-2.5 py-1 hover:text-rojo" onClick={() => void verAdjunto(a)}>
                          {a.mimetype === "application/pdf" ? "PDF" : "Foto"} {i + 1}{a.bytes ? ` · ${pesoLegible(a.bytes)}` : ""}{a.interno ? " · interno" : ""}
                        </button>
                      </li>
                    ))}
                  </ul>
                )}
              </section>

              {d.cierre_texto && (
                <section className="rounded-superficie border border-sand bg-papel p-5">
                  <p className="etiqueta mb-1.5 text-taupe">Cierre · {d.cerrado_at ? fechaLargaLima(d.cerrado_at) : ""}</p>
                  <p className="whitespace-pre-line border-l-[3px] border-verde pl-3.5">{d.cierre_texto}</p>
                  {d.cierre_resultado && (
                    <p className="mt-2 text-xs text-taupe">Resultado: {RESULTADOS_CIERRE.find((r) => r.valor === d.cierre_resultado)?.texto ?? d.cierre_resultado}</p>
                  )}
                </section>
              )}

              <Conversacion hilo={hilo} puedeAvisar={acc.avisarFecha}
                onEnviar={(texto, interno, fecha) => hacer("enviar el mensaje",
                  supabase.rpc("fn_reporte_mensaje", { p_reporte: id, p_texto: texto, p_interno: interno, p_responde_para: fecha }),
                  interno ? "Nota interna guardada." : "Mensaje enviado.")}
                onAdjuntar={async (archivo, interno) => {
                  setOcupada(true);
                  const listo = await reducirImagen(archivo);
                  const ruta = rutaDeAdjunto(id, listo.type || archivo.type);
                  const fallo = ruta ? await subirArchivoConProgreso(supabase, "reportes", ruta, listo, () => {}) : "Ese formato no se puede adjuntar.";
                  setOcupada(false);
                  if (fallo || !ruta) { avisar("error", fallo ?? "No se pudo subir el archivo."); return; }
                  await hacer("adjuntar el archivo", supabase.rpc("fn_reporte_adjuntar", { p_reporte: id, p_path: ruta, p_interno: interno }), "Archivo adjuntado.");
                }}
                ocupada={ocupada} />
            </div>

            <aside className="grid gap-3">
              <section className="rounded-superficie border border-sand bg-papel p-4">
                <p className="etiqueta mb-2 text-taupe">Plazos del Reglamento</p>
                <ul className="grid gap-2">
                  {vivos.map((p) => {
                    const hecho = !!p.cumplido_at;
                    const vencido = !hecho && Date.parse(p.vence_at) < ahora;
                    return (
                      <li key={p.clave} className="grid gap-1">
                        <div className="flex items-start justify-between gap-2">
                          <span>{p.descripcion} <span className="text-xs text-taupe">· {p.norma}</span></span>
                          <Insignia tamano="sm" variante={hecho ? "positivo" : vencido ? "alerta" : "informativo"}>
                            {hecho ? "Hecho" : vencido ? "Vencido" : "Pendiente"}
                          </Insignia>
                        </div>
                        <span className="text-xs text-taupe">
                          {hecho ? `el ${fechaLargaLima(p.cumplido_at!)}${p.nota ? ` · ${p.nota}` : ""}` : `vence el ${fechaEnPalabras(p.vence_at)}`}
                        </span>
                        {!hecho && MANUALES.has(p.clave) && (
                          <PlazoACumplir clave={p.clave} duena={p.duena}
                            onCumplir={(nota) => hacer("registrar el plazo", supabase.rpc("fn_reporte_plazo_cumplir", { p_reporte: id, p_clave: p.clave, p_nota: nota }), "Plazo registrado.")} />
                        )}
                      </li>
                    );
                  })}
                </ul>
              </section>

              <section className="rounded-superficie border border-sand bg-papel p-4">
                <p className="etiqueta mb-2 text-taupe">Acciones</p>
                <div className="flex flex-wrap gap-1.5">
                  {acc.enRevision && <Boton tamano="sm" disabled={ocupada} onClick={() => void hacer("ponerlo en revisión", supabase.rpc("fn_reporte_en_revision", { p_reporte: id }), "En revisión.")}>Poner en revisión</Boton>}
                  {acc.anotar && <Boton tamano="sm" onClick={() => setPanel(panel === "accion" ? null : "accion")}>Registrar acción</Boton>}
                  {acc.escalar && <Boton tamano="sm" onClick={() => setPanel(panel === "escalar" ? null : "escalar")}>Escalar</Boton>}
                  {acc.reclasificar && <Boton tamano="sm" onClick={() => setPanel(panel === "via" ? null : "via")}>Cambiar de vía</Boton>}
                  {acc.medida && <Boton tamano="sm" onClick={() => setPanel(panel === "medida" ? null : "medida")}>Medida de protección</Boton>}
                  {acc.indiciosDelito && <Boton tamano="sm" variante="peligro" onClick={() => setPanel(panel === "delito" ? null : "delito")}>Indicios de delito</Boton>}
                  {acc.derivar && <Boton tamano="sm" onClick={() => setPanel(panel === "derivar" ? null : "derivar")}>Enlazar a disciplina</Boton>}
                  <Boton tamano="sm" variante="primario" disabled={!acc.cerrar} onClick={() => setPanel(panel === "cerrar" ? null : "cerrar")}>Cerrar</Boton>
                </div>
                {acc.porQueNoCierra && d.estado !== "cerrado" && <p className="mt-2 text-xs text-taupe">{acc.porQueNoCierra}</p>}

                {panel === "accion" && (
                  <FormaTexto etiqueta="Qué se hizo" opciones={acc.tiposDeAccion.map((a) => ({ valor: a, texto: NOMBRE_ACCION[a] }))}
                    nota={d.via === "titulo_x" ? "En el Título X no se media ni se reúne a las partes (48.14)." : null}
                    boton="Registrar" ocupada={ocupada}
                    onEnviar={(v, t) => hacer("registrar la acción", supabase.rpc("fn_reporte_anotar_accion", { p_reporte: id, p_accion: v, p_nota: t }), "Registrado.")} />
                )}
                {panel === "escalar" && (
                  <FormaTexto etiqueta={`Por qué se escala a ${d.gestiona === "lider" ? "Desarrollo Organizacional" : "la Gerencia General"}`}
                    boton="Escalar" ocupada={ocupada}
                    onEnviar={(_, t) => hacer("escalar el caso", supabase.rpc("fn_reporte_escalar", { p_reporte: id, p_motivo: t }), "Caso escalado.")} />
                )}
                {panel === "via" && (
                  <FormaTexto etiqueta="Por qué cambia de vía" opciones={VIAS.filter((v) => v.valor !== d.via)}
                    nota={d.via !== "titulo_x" ? "Si pasa al Título X, la líder deja de ver el caso en el acto." : null}
                    boton="Cambiar de vía" ocupada={ocupada}
                    onEnviar={(v, t) => hacer("cambiar la vía", supabase.rpc("fn_reporte_reclasificar", { p_reporte: id, p_via: v, p_motivo: t }), "Vía cambiada.")} />
                )}
                {panel === "medida" && (
                  <FormaMedida reporte={id} ocupada={ocupada}
                    onEnviar={(para, texto, hasta) => hacer("dictar la medida", supabase.rpc("fn_reporte_medida", { p_reporte: id, p_para: para, p_instruccion: texto, p_hasta: hasta }), "Medida encargada a la líder.")} />
                )}
                {panel === "delito" && (
                  <FormaTexto etiqueta="Cuáles son los indicios" boton="Registrar (vence en 24 horas)" ocupada={ocupada}
                    nota="Abre el plazo de 24 horas del 49.4 i): comunicar al Ministerio Público o a la Policía, con conocimiento de la persona afectada."
                    onEnviar={(_, t) => hacer("registrar los indicios", supabase.rpc("fn_reporte_indicios_delito", { p_reporte: id, p_nota: t }), "Plazo de 24 horas abierto.")} />
                )}
                {panel === "derivar" && (
                  <FormaDerivar reporte={id} ocupada={ocupada}
                    onEnviar={(exp) => hacer("enlazar el expediente", supabase.rpc("fn_reporte_derivar", { p_reporte: id, p_expediente: exp }), "Expediente enlazado.")} />
                )}
                {panel === "cerrar" && (
                  <FormaTexto etiqueta="Respuesta escrita para quien reportó" opciones={RESULTADOS_CIERRE} multilinea
                    nota="Es la respuesta escrita que exige el Reglamento. Quien reportó la lee; el resultado, no."
                    boton="Cerrar el caso" ocupada={ocupada}
                    onEnviar={(v, t) => hacer("cerrar el caso", supabase.rpc("fn_reporte_cerrar", { p_reporte: id, p_resultado: v, p_texto: t }), "Caso cerrado.")} />
                )}
              </section>

              {medidas.length > 0 && (
                <section className="rounded-superficie border border-sand bg-papel p-4">
                  <p className="etiqueta mb-2 text-taupe">Medidas</p>
                  <ul className="grid gap-2 text-xs">
                    {medidas.map((m) => (
                      <li key={m.id}>
                        <span className="block text-sm">{m.instruccion}</span>
                        <span className="text-taupe">A {m.para} · {m.cumplida_at ? `cumplida el ${fechaLargaLima(m.cumplida_at)}` : "por cumplir"}</span>
                      </li>
                    ))}
                  </ul>
                </section>
              )}

              <section className="rounded-superficie border border-sand bg-papel p-4">
                <p className="etiqueta mb-2 text-taupe">Qué se hizo</p>
                <ol className="grid gap-2 text-xs">
                  {eventos.filter((e) => e.tipo !== "lectura").map((e) => (
                    <li key={e.id} className="grid grid-cols-[10px_1fr] gap-2">
                      <span className="mt-1.5 size-2 rounded-full bg-taupe" aria-hidden />
                      <span>
                        <span className="text-taupe">{fechaLargaLima(e.at)} · </span>
                        {NOMBRE_EVENTO[e.tipo] ?? e.tipo}
                        {typeof e.detalle.accion === "string" ? `: ${NOMBRE_ACCION[e.detalle.accion] ?? e.detalle.accion}` : ""}
                        {typeof e.detalle.nota === "string" ? ` — «${e.detalle.nota}»` : ""}
                        {typeof e.detalle.motivo === "string" && e.tipo !== "lectura" ? ` — «${e.detalle.motivo}»` : ""}
                        <span className="text-taupe"> · {e.quien}</span>
                      </span>
                    </li>
                  ))}
                </ol>
              </section>
            </aside>
          </div>
        </div>
      </main>
    </div>
  );
}

function Conversacion({ hilo, puedeAvisar, onEnviar, onAdjuntar, ocupada }: {
  hilo: Mensaje[];
  puedeAvisar: boolean;
  onEnviar: (texto: string, interno: boolean, fecha: string | null) => Promise<boolean>;
  onAdjuntar: (archivo: File, interno: boolean) => Promise<void>;
  ocupada: boolean;
}) {
  const [texto, setTexto] = useState("");
  const [interno, setInterno] = useState(false);
  const [avisarFecha, setAvisarFecha] = useState(false);
  // La fecha nace con un valor (regla quinta): dos semanas desde hoy, editable.
  const [fecha, setFecha] = useState(() => {
    const [a, m, dd] = hoyLima().split("-").map(Number);
    return new Date(Date.UTC(a, m - 1, dd + 14)).toISOString().slice(0, 10);
  });
  return (
    <section className="rounded-superficie border border-sand bg-papel p-5">
      <h2 className="mb-3 font-serif text-lg">Conversación</h2>
      <div className="grid gap-3">
        {hilo.length === 0 && <p className="text-taupe">Todavía nadie escribió. La primera respuesta pone el caso en revisión.</p>}
        {hilo.map((m) => (
          <div key={m.id} className={cx(
            "max-w-[92%] rounded-[14px] border px-3.5 py-2.5 sm:max-w-[80%]",
            m.interno ? "border-dashed border-ambar/45 bg-ambar/10" : m.es_mio ? "ml-auto border-sand bg-sand" : "border-sand bg-papel",
          )}>
            <p className="mb-0.5 text-xs text-taupe">
              {m.interno ? "Nota interna · " : ""}{m.quien} · {fechaLargaLima(m.creado_at)}{m.interno ? " — quien reportó no la ve" : ""}
            </p>
            <p className="whitespace-pre-line">{m.texto}</p>
          </div>
        ))}
      </div>
      <div className="mt-4 grid gap-2.5 border-t border-sand pt-4">
        <AreaTexto value={texto} rows={3} onChange={(e) => setTexto(e.target.value)}
          placeholder={interno ? "Nota para quienes gestionan…" : "Escribe a quien reportó…"} />
        <div className="flex flex-wrap items-center gap-x-4 gap-y-2">
          <CampoCasilla etiqueta="Nota interna (quien reportó no la ve)" checked={interno}
            onChange={(e) => { setInterno(e.target.checked); if (e.target.checked) setAvisarFecha(false); }} />
          {puedeAvisar && !interno && (
            <CampoCasilla etiqueta="Avisar la fecha en que responderemos (43-B.2)" checked={avisarFecha}
              onChange={(e) => setAvisarFecha(e.target.checked)} />
          )}
        </div>
        {avisarFecha && (
          <div className="max-w-xs">
            <Campo etiqueta="Responderemos el" type="date" value={fecha} min={hoyLima()} onChange={(e) => setFecha(e.target.value || fecha)} />
          </div>
        )}
        <div className="flex flex-wrap items-center justify-between gap-2">
          <label className="cursor-pointer text-xs text-taupe hover:text-tinta">
            Adjuntar foto o PDF{interno ? " (interno)" : ""}
            <input type="file" accept={TIPOS_DE_ADJUNTO.join(",")} className="sr-only" disabled={ocupada}
              onChange={(e) => { const f = e.target.files?.[0]; e.target.value = ""; if (f) void onAdjuntar(f, interno); }} />
          </label>
          <Boton variante="primario" tamano="sm" disabled={!texto.trim() || ocupada} cargando={ocupada}
            onClick={() => void onEnviar(texto, interno, avisarFecha ? fecha : null).then((ok) => { if (ok) setTexto(""); })}>
            {interno ? "Guardar nota" : "Enviar"}
          </Boton>
        </div>
      </div>
    </section>
  );
}

function FormaTexto({ etiqueta, opciones, nota, boton, multilinea, ocupada, onEnviar }: {
  etiqueta: string;
  opciones?: readonly { valor: string; texto: string }[];
  nota?: string | null;
  boton: string;
  multilinea?: boolean;
  ocupada: boolean;
  onEnviar: (valor: string, texto: string) => Promise<boolean>;
}) {
  const [valor, setValor] = useState(opciones?.[0]?.valor ?? "");
  const [texto, setTexto] = useState("");
  return (
    <div className="mt-3 grid gap-2 border-t border-sand pt-3">
      {opciones && (
        <CampoSelect value={valor} onChange={(e) => setValor(e.target.value)}>
          {opciones.map((o) => <option key={o.valor} value={o.valor}>{o.texto}</option>)}
        </CampoSelect>
      )}
      <AreaTexto etiqueta={etiqueta} value={texto} rows={multilinea ? 4 : 2} onChange={(e) => setTexto(e.target.value)} />
      {nota && <p className="text-xs text-taupe">{nota}</p>}
      <Boton tamano="sm" variante="primario" disabled={texto.trim().length < 3 || ocupada} cargando={ocupada}
        onClick={() => void onEnviar(valor, texto)}>{boton}</Boton>
    </div>
  );
}

function PlazoACumplir({ clave, duena, onCumplir }: { clave: string; duena: string; onCumplir: (nota: string) => Promise<boolean> }) {
  const [abierto, setAbierto] = useState(false);
  const [nota, setNota] = useState("");
  if (!abierto) {
    return (
      <button type="button" className="justify-self-start text-xs underline underline-offset-2 hover:text-rojo" onClick={() => setAbierto(true)}>
        {clave === "informe" ? "Registrar el informe" : "Registrar que se hizo"}
        {duena === "investigadora" ? " (quien investiga)" : ""}
      </button>
    );
  }
  return (
    <div className="grid gap-1.5">
      <AreaTexto value={nota} rows={2} onChange={(e) => setNota(e.target.value)}
        placeholder={clave === "informe" ? "Resumen del informe: hechos, pruebas valoradas y propuesta" : "Qué se hizo y cuándo (48.12)"} />
      <div className="flex gap-1.5">
        <Boton tamano="sm" variante="primario" disabled={nota.trim().length < 3} onClick={() => void onCumplir(nota)}>Registrar</Boton>
        <Boton tamano="sm" variante="sutil" onClick={() => setAbierto(false)}>Cancelar</Boton>
      </div>
    </div>
  );
}

function FormaMedida({ reporte, ocupada, onEnviar }: {
  reporte: string; ocupada: boolean; onEnviar: (para: string, texto: string, hasta: string | null) => Promise<boolean>;
}) {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const [lideres, setLideres] = useState<{ id: string; nombre: string; sede_codigo: string | null }[]>([]);
  const [para, setPara] = useState("");
  const [texto, setTexto] = useState("");
  useEffect(() => {
    void supabase.rpc("fn_reporte_lideres", { p_reporte: reporte }).then(({ data }) => {
      setLideres((data ?? []) as { id: string; nombre: string; sede_codigo: string | null }[]);
    });
  }, [supabase, reporte]);
  return (
    <div className="mt-3 grid gap-2 border-t border-sand pt-3">
      <CampoSelect etiqueta="Líder que la ejecuta" value={para} onChange={(e) => setPara(e.target.value)}>
        <option value="">Elige a la líder</option>
        {lideres.map((l) => <option key={l.id} value={l.id}>{l.nombre}{l.sede_codigo ? ` · ${l.sede_codigo}` : ""}</option>)}
      </CampoSelect>
      <AreaTexto etiqueta="Instrucción (sin los hechos)" value={texto} rows={2} onChange={(e) => setTexto(e.target.value)}
        placeholder="Desde mañana, X pasa al turno tarde hasta nuevo aviso." />
      <p className="text-xs text-taupe">La líder ve solo esta instrucción, no el caso. No escribas aquí lo que pasó ni quién lo reportó.</p>
      <Boton tamano="sm" variante="primario" disabled={!para || texto.trim().length < 3 || ocupada} cargando={ocupada}
        onClick={() => void onEnviar(para, texto, null)}>Encargar la medida</Boton>
    </div>
  );
}

function FormaDerivar({ reporte, ocupada, onEnviar }: { reporte: string; ocupada: boolean; onEnviar: (exp: string) => Promise<boolean> }) {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const [exps, setExps] = useState<{ id: string; persona: string; nivel: string; estado: string; correlativo: string | null }[] | null>(null);
  const [exp, setExp] = useState("");
  useEffect(() => {
    void supabase.rpc("fn_reporte_expedientes", { p_reporte: reporte }).then(({ data }) => {
      setExps((data ?? []) as { id: string; persona: string; nivel: string; estado: string; correlativo: string | null }[]);
    });
  }, [supabase, reporte]);
  return (
    <div className="mt-3 grid gap-2 border-t border-sand pt-3">
      {exps && exps.length === 0 ? (
        <p className="text-xs text-taupe">
          Ninguna persona involucrada tiene un expediente abierto. Si corresponde, ábrelo primero en{" "}
          <Link href="/admin/disciplina" className="underline">Disciplina</Link> y vuelve a enlazarlo aquí.
        </p>
      ) : (
        <>
          <CampoSelect etiqueta="Expediente" value={exp} onChange={(e) => setExp(e.target.value)}>
            <option value="">Elige el expediente</option>
            {(exps ?? []).map((x) => <option key={x.id} value={x.id}>{x.persona} · {x.nivel} · {x.estado}{x.correlativo ? ` · ${x.correlativo}` : ""}</option>)}
          </CampoSelect>
          <p className="text-xs text-taupe">Enlazar no sanciona ni crea nada: el expediente sigue su procedimiento en Disciplina.</p>
          <Boton tamano="sm" variante="primario" disabled={!exp || ocupada} cargando={ocupada} onClick={() => void onEnviar(exp)}>Enlazar</Boton>
        </>
      )}
    </div>
  );
}
