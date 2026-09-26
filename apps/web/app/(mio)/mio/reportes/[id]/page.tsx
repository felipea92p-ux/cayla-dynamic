"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useParams, useSearchParams } from "next/navigation";
import { Clock, Paperclip } from "lucide-react";
import { Boton } from "@/components/ui/boton";
import { Insignia } from "@/components/ui/insignia";
import { AreaTexto } from "@/components/ui/area-texto";
import { Cargando } from "@/components/cargando";
import { cx } from "@/components/ui/cx";
import { useToast } from "@/components/toast";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { fechaLargaLima } from "@/lib/admin/planilla/formato";
import { reducirImagen, pesoLegible } from "@/lib/reducir-imagen";
import { subirArchivoConProgreso } from "@/lib/subir-archivo";
import { etiquetaDeEstado, fechaEnPalabras, rutaDeAdjunto, TIPOS_DE_ADJUNTO, tituloDeReporte } from "@/lib/reportes";
import { useMiFicha } from "../usar-mi-ficha";

/**
 * Un reporte, visto por quien lo escribió (docs/plan-reportes.md, sección 6).
 *
 * ABRIRLO DEJA RASTRO (`fn_reporte_abrir`, 0484): así la base sabe qué
 * respuestas ya leyó, y el globito del menú y su Bandeja dejan de avisar.
 *
 * LO QUE NO SE MUESTRA, y es a propósito: el resultado del caso (habla de otra
 * persona), las notas internas, la línea de tiempo y los nombres de quienes lo
 * gestionan. Todo eso ya lo filtra la base: `fn_reporte_detalle`,
 * `fn_reporte_hilo` y `fn_reporte_adjuntos` no se lo devuelven.
 */

type Detalle = {
  codigo: string; tipo: string; via: string; estado: string; urgente: boolean; sede_codigo: string;
  fecha_hecho: string; relato: string; creado_at: string; cerrado_at: string | null;
  cierre_texto: string | null; respuesta_vence_at: string | null; mi_papel: string;
};
type Mensaje = { id: string; texto: string; interno: boolean; creado_at: string; es_mio: boolean; quien: string };
type Adjunto = { id: string; storage_path: string; mimetype: string | null; bytes: number | null; creado_at: string; es_mio: boolean };

const PASOS = ["recibido", "en_revision", "cerrado"] as const;
const NOMBRE_PASO: Record<(typeof PASOS)[number], string> = { recibido: "Recibido", en_revision: "En revisión", cerrado: "Cerrado" };

export default function MiReporte() {
  const { id } = useParams<{ id: string }>();
  const params = useSearchParams();
  const { supabase, ficha } = useMiFicha();
  const { avisar } = useToast();

  const [detalle, setDetalle] = useState<Detalle | null>(null);
  const [hilo, setHilo] = useState<Mensaje[]>([]);
  const [adjuntos, setAdjuntos] = useState<Adjunto[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [texto, setTexto] = useState("");
  const [ocupada, setOcupada] = useState<string | null>(null);

  const cargar = useCallback(async () => {
    const [d, h, a] = await Promise.all([
      supabase.rpc("fn_reporte_detalle", { p_reporte: id }),
      supabase.rpc("fn_reporte_hilo", { p_reporte: id }),
      supabase.rpc("fn_reporte_adjuntos", { p_reporte: id }),
    ]);
    if (d.error || !d.data?.[0]) { setError(mensajeDeError(d.error, "abrir este reporte")); return; }
    setError(null);
    setDetalle(d.data[0] as Detalle);
    setHilo((h.data ?? []) as Mensaje[]);
    setAdjuntos((a.data ?? []) as Adjunto[]);
  }, [supabase, id]);

  useEffect(() => {
    if (ficha.estado !== "ok") return;
    void (async () => {
      // Primero se anota la apertura; después se lee. Si la apertura falla (sin
      // acceso), el detalle lo dirá con su propio mensaje.
      await supabase.rpc("fn_reporte_abrir", { p_reporte: id }).then(() => {}, () => {});
      await cargar();
    })();
  }, [ficha.estado, supabase, id, cargar]);

  async function responder() {
    if (!texto.trim()) return;
    setOcupada("responder");
    const { error: e } = await supabase.rpc("fn_reporte_mensaje", { p_reporte: id, p_texto: texto });
    setOcupada(null);
    if (e) { avisar("error", mensajeDeError(e, "enviar tu respuesta")); return; }
    setTexto("");
    await cargar();
  }

  async function adjuntar(archivo: File) {
    setOcupada("adjuntar");
    const listo = await reducirImagen(archivo);
    const ruta = rutaDeAdjunto(id, listo.type || archivo.type);
    const fallo = ruta ? await subirArchivoConProgreso(supabase, "reportes", ruta, listo, () => {}) : "Ese formato no se puede adjuntar.";
    if (fallo || !ruta) { setOcupada(null); avisar("error", fallo ?? "No se pudo subir el archivo."); return; }
    const { error: e } = await supabase.rpc("fn_reporte_adjuntar", { p_reporte: id, p_path: ruta });
    setOcupada(null);
    if (e) { avisar("error", mensajeDeError(e, "adjuntar el archivo")); return; }
    await cargar();
  }

  async function verAdjunto(a: Adjunto) {
    const { data, error: e } = await supabase.storage.from("reportes").createSignedUrl(a.storage_path, 60);
    if (e || !data) { avisar("error", "No se pudo abrir el archivo. Intenta de nuevo."); return; }
    window.open(data.signedUrl, "_blank", "noopener");
  }

  if (ficha.estado === "error") return <main className="p-8 text-sm text-rojo">{ficha.mensaje}</main>;
  if (error) {
    return (
      <main className="mx-auto max-w-3xl px-5 py-8 text-sm">
        <p className="rounded-control bg-rojo/10 px-3 py-2 text-rojo-profundo">{error}</p>
        <Link href="/mio?tab=reportes" className="mt-4 inline-block underline underline-offset-2">← Tus reportes</Link>
      </main>
    );
  }
  if (!detalle) return <main className="p-8"><Cargando /></main>;

  const estado = etiquetaDeEstado(detalle.estado);
  const indice = PASOS.indexOf(detalle.estado as (typeof PASOS)[number]);
  const cerrado = detalle.estado === "cerrado";
  const noSubieron = params.get("no_subieron");

  return (
    <main className="mx-auto w-full max-w-4xl flex-1 px-5 py-8 text-sm text-tinta">
      <Link href="/mio?tab=reportes" className="mb-4 inline-block rounded-control border border-sand px-3 py-1 text-xs text-taupe hover:text-tinta">
        ← Tus reportes
      </Link>

      {params.get("nuevo") && (
        <p className="mb-4 rounded-control bg-verde/15 px-3 py-2 text-verde">
          Tu reporte se envió. Su código es <strong className="font-medium tabular-nums">{detalle.codigo}</strong>: con él
          puedes referirte al caso sin nombrar a nadie.
        </p>
      )}
      {noSubieron && (
        <p className="mb-4 rounded-control bg-ambar/15 px-3 py-2 text-ambar">
          No se pudo subir: {noSubieron}. Puedes adjuntarlo de nuevo abajo.
        </p>
      )}
      {detalle.mi_papel !== "autora" && (
        <p className="mb-4 rounded-control bg-pizarra/15 px-3 py-2 text-pizarra">
          Este caso lo gestionas tú: aquí lo ves como lo ve quien lo envió.
        </p>
      )}

      <div className="mb-2 flex flex-wrap items-end justify-between gap-3">
        <div>
          <p className="etiqueta text-taupe">
            {tituloDeReporte(detalle.tipo, detalle.via)} · <span className="tabular-nums">{detalle.codigo}</span>
          </p>
          <h1 className="mt-0.5 font-serif text-3xl leading-tight">Enviado el {fechaLargaLima(detalle.creado_at)}</h1>
        </div>
        <div className="flex gap-2">
          {detalle.urgente && <Insignia variante="alerta">Urgente</Insignia>}
          <Insignia variante={estado.variante}>{estado.texto}</Insignia>
        </div>
      </div>

      <ol className="my-2 flex flex-wrap items-center gap-2" aria-label="En qué va">
        {PASOS.map((p, i) => (
          <li key={p} className="flex items-center gap-2">
            {i > 0 && <span className={cx("h-0.5 w-6", i <= indice ? "bg-tinta" : "bg-sand")} aria-hidden />}
            <span className={cx("flex items-center gap-1.5", i <= indice ? "text-tinta" : "text-taupe")}>
              <span className={cx("size-2.5 rounded-full border-2", i <= indice ? "border-tinta bg-tinta" : "border-sand")} aria-hidden />
              {NOMBRE_PASO[p]}
            </span>
          </li>
        ))}
      </ol>

      {!cerrado && detalle.respuesta_vence_at && (
        <div className="my-4 flex items-center gap-2.5 rounded-control bg-hueso px-3.5 py-3">
          <Clock className="size-[18px] shrink-0 text-taupe" strokeWidth={1.8} aria-hidden />
          <span>
            Te responden por escrito a más tardar el{" "}
            <strong className="font-medium">{fechaEnPalabras(detalle.respuesta_vence_at)}</strong>.
          </span>
        </div>
      )}

      {cerrado && detalle.cierre_texto && (
        <div className="my-4 rounded-superficie border border-sand bg-papel p-4">
          <p className="etiqueta mb-1.5 text-taupe">Respuesta · {detalle.cerrado_at ? fechaLargaLima(detalle.cerrado_at) : ""}</p>
          <p className="whitespace-pre-line border-l-[3px] border-verde pl-3.5">{detalle.cierre_texto}</p>
        </div>
      )}

      <div className="mt-4 grid items-start gap-4 md:grid-cols-[minmax(0,1fr)_260px]">
        <section className="rounded-superficie border border-sand bg-papel p-5">
          <h2 className="mb-3 font-serif text-lg">Conversación</h2>
          <div className="grid gap-3">
            <p className="text-center text-xs text-taupe">{fechaLargaLima(detalle.creado_at)} · Recibimos tu reporte</p>
            {hilo.map((m) => (
              <div key={m.id} className={cx(
                "max-w-[92%] rounded-[14px] border px-3.5 py-2.5 sm:max-w-[78%]",
                m.es_mio ? "ml-auto border-sand bg-sand" : "border-sand bg-papel",
              )}>
                <p className="mb-0.5 text-xs text-taupe">{m.quien} · {fechaLargaLima(m.creado_at)}</p>
                <p className="whitespace-pre-line">{m.texto}</p>
              </div>
            ))}
          </div>
          {!cerrado && (
            <div className="mt-4 border-t border-sand pt-4">
              <AreaTexto etiqueta="Responder" value={texto} rows={3} onChange={(e) => setTexto(e.target.value)}
                placeholder="Escribe tu respuesta…" />
              <div className="mt-2.5 flex flex-wrap items-center justify-between gap-2">
                <label className="flex cursor-pointer items-center gap-1.5 text-xs text-taupe hover:text-tinta">
                  <Paperclip className="size-3.5" strokeWidth={1.8} aria-hidden />
                  Adjuntar foto o PDF
                  <input type="file" accept={TIPOS_DE_ADJUNTO.join(",")} className="sr-only" disabled={!!ocupada}
                    onChange={(e) => { const f = e.target.files?.[0]; e.target.value = ""; if (f) void adjuntar(f); }} />
                </label>
                <Boton variante="primario" tamano="sm" cargando={ocupada === "responder"}
                  disabled={!texto.trim() || !!ocupada} onClick={() => void responder()}>
                  Enviar
                </Boton>
              </div>
            </div>
          )}
        </section>

        <aside className="grid gap-3">
          <div className="rounded-superficie border border-sand bg-papel p-4">
            <p className="etiqueta mb-1.5 text-taupe">Lo que contaste</p>
            <p className="whitespace-pre-line">{detalle.relato}</p>
            <p className="mt-2 text-xs text-taupe">{fechaLargaLima(detalle.fecha_hecho + "T12:00:00-05:00")} · {detalle.sede_codigo}</p>
          </div>
          {adjuntos.length > 0 && (
            <div className="rounded-superficie border border-sand bg-papel p-4">
              <p className="etiqueta mb-1.5 text-taupe">Archivos</p>
              <ul className="grid gap-1">
                {adjuntos.map((a, i) => (
                  <li key={a.id}>
                    <button type="button" className="text-left underline underline-offset-2 hover:text-taupe"
                      onClick={() => void verAdjunto(a)}>
                      {a.mimetype === "application/pdf" ? "PDF" : "Foto"} {i + 1}
                      {a.bytes ? <span className="text-xs text-taupe"> · {pesoLegible(a.bytes)}</span> : null}
                    </button>
                  </li>
                ))}
              </ul>
            </div>
          )}
          {ocupada === "adjuntar" && <p className="text-xs text-taupe">Subiendo el archivo…</p>}
        </aside>
      </div>
    </main>
  );
}
