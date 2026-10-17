"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { FileWarning } from "lucide-react";
import type { PDFDocumentProxy } from "pdfjs-dist";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { abrirArchivoFirmado } from "@/lib/abrir-archivo-firmado";
import { abrirPdf, dibujarPagina, esImagen, esPdf, urlFirmada, type PdfAbierto } from "@/lib/admin/constancia-medios";
import type { ArchivoDeEntrega } from "@/lib/admin/educacion-tipos";
import { BUCKET_COMPROBANTES } from "@/lib/educacion";
import { Boton } from "@/components/ui/boton";

/**
 * LOS ARCHIVOS DE UNA CONSTANCIA, UNO DEBAJO DEL OTRO, YA DIBUJADOS.
 *
 * PROMETE: mostrar cada archivo de la constancia —foto o PDF— dentro de la
 *   pantalla, sin pestaña nueva y sin descargar nada. Un PDF de varias hojas se
 *   dibuja hoja por hoja, y las hojas se pintan cuando se acercan a la vista.
 * ASUME: quien lo usa le da un contenedor con scroll y, si quiere zoom, un
 *   número: 1 = ajustado al ancho; 1.5, 2… = más grande, con scroll de lado.
 * NO HACE: no decide a qué archivos se llega (eso es la política del almacén) ni
 *   guarda nada. Si un archivo no se puede dibujar —una foto HEIC que no es de
 *   Safari—, lo dice y deja «Abrir aparte»: es la única salida a otra pestaña.
 *
 * El visor grande y el panel de cada estudio lo comparten: antes cada uno tenía
 * su manera de decir «ábrelo para leerlo», y las dos mandaban al navegador.
 */

/** El ancho que mide un elemento, y se actualiza cuando cambia (la ventana, el panel). */
function useAncho<T extends HTMLElement>(): [React.RefObject<T | null>, number] {
  const ref = useRef<T>(null);
  const [ancho, setAncho] = useState(0);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const medir = () => setAncho(Math.floor(el.clientWidth));
    medir();
    const obs = new ResizeObserver(medir);
    obs.observe(el);
    return () => obs.disconnect();
  }, []);
  return [ref, ancho];
}

export function LienzoArchivos({ archivos, zoom = 1 }: { archivos: ArchivoDeEntrega[]; zoom?: number }) {
  const [ref, ancho] = useAncho<HTMLDivElement>();
  const anchoObjetivo = Math.max(0, Math.round(ancho * zoom));

  if (archivos.length === 0) {
    return <p className="py-10 text-center text-sm text-taupe">Esta constancia no trae archivos.</p>;
  }

  return (
    <div ref={ref} className="flex flex-col gap-5">
      {ancho > 0 && archivos.map((a, i) => (
        <section key={a.id} aria-label={`Archivo ${i + 1} de ${archivos.length}: ${a.nombre}`}>
          {archivos.length > 1 && (
            <p className="mb-1.5 flex items-center justify-between gap-2 text-xs text-taupe">
              <span className="truncate">Archivo {i + 1} de {archivos.length} · {a.nombre}</span>
            </p>
          )}
          {/* Con zoom, la hoja se sale del ancho: este envoltorio es el que se desplaza de lado. */}
          <div className={zoom > 1 ? "overflow-x-auto" : undefined}>
            <HojaArchivo archivo={a} ancho={anchoObjetivo} ajustada={zoom <= 1} />
          </div>
        </section>
      ))}
    </div>
  );
}

function HojaArchivo({ archivo, ancho, ajustada }: { archivo: ArchivoDeEntrega; ancho: number; ajustada: boolean }) {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const [url, setUrl] = useState<string | null | undefined>(undefined);
  const [intento, setIntento] = useState(0);
  const dibujable = esImagen(archivo) || esPdf(archivo);

  useEffect(() => {
    if (!dibujable) return;
    let vivo = true;
    // eslint-disable-next-line react-hooks/set-state-in-effect -- al reintentar se vuelve a «cargando».
    setUrl(undefined);
    void urlFirmada(supabase, archivo.ruta).then((u) => { if (vivo) setUrl(u); });
    return () => { vivo = false; };
  }, [supabase, archivo.ruta, dibujable, intento]);

  // «Abrir aparte» es la salida para lo que no se pueda dibujar: un archivo de otro tipo, o uno que
  // falló. El panel de antes abría en pestaña TODO archivo; que el visor nuevo no pueda mostrar uno
  // no puede dejar a quien revisa sin ninguna forma de verlo.
  const abrirAparte = (
    <Boton tamano="sm" onClick={() => void abrirArchivoFirmado(supabase, BUCKET_COMPROBANTES, archivo.ruta)}>
      Abrir aparte
    </Boton>
  );
  if (!dibujable) {
    return <Aviso>Este tipo de archivo no se puede mostrar aquí.{abrirAparte}</Aviso>;
  }
  if (url === undefined) return <Esqueleto ancho={ancho} />;
  if (url === null) {
    return (
      <Aviso>
        No se pudo cargar el archivo.
        <span className="flex gap-2">
          <Boton tamano="sm" onClick={() => setIntento((n) => n + 1)}>Reintentar</Boton>
          {abrirAparte}
        </span>
      </Aviso>
    );
  }

  if (esImagen(archivo)) {
    return (
      // eslint-disable-next-line @next/next/no-img-element -- imagen de un almacén privado, con URL firmada
      <img
        src={url}
        alt={archivo.nombre || "Constancia"}
        onError={() => setUrl(null)}
        style={{ width: ancho, maxWidth: ajustada ? "100%" : "none" }}
        className="mx-auto block h-auto rounded-control border border-sand bg-papel"
      />
    );
  }
  return <PaginasPdf url={url} ancho={ancho} alFallar={() => setUrl(null)} />;
}

function Aviso({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex flex-col items-center gap-3 rounded-control border border-dashed border-sand bg-papel px-4 py-10 text-center text-sm text-taupe">
      <FileWarning className="size-6" aria-hidden />
      {children}
    </div>
  );
}

function Esqueleto({ ancho }: { ancho: number }) {
  return (
    <div role="status" aria-label="Cargando archivo" style={{ width: ancho, height: Math.round(ancho * 0.7), maxWidth: "100%" }}
      className="pulso-carga mx-auto rounded-control border border-sand bg-sand/60" />
  );
}

// ── PDF: una hoja por canvas, pintada cuando se acerca a la vista ───────────

function PaginasPdf({ url, ancho, alFallar }: { url: string; ancho: number; alFallar: () => void }) {
  const [pdf, setPdf] = useState<PDFDocumentProxy | null>(null);
  const alFallarRef = useRef(alFallar);
  useEffect(() => { alFallarRef.current = alFallar; }, [alFallar]);

  useEffect(() => {
    let vivo = true;
    let abierto: PdfAbierto | null = null;
    abrirPdf(url)
      .then((doc) => {
        if (!vivo) { doc.cerrar(); return; }
        abierto = doc;
        setPdf(doc.pdf);
      })
      .catch(() => { if (vivo) alFallarRef.current(); });
    return () => {
      vivo = false;
      setPdf(null);
      abierto?.cerrar();
    };
  }, [url]);

  if (!pdf) return <Esqueleto ancho={ancho} />;
  return (
    <div className="flex flex-col gap-3">
      {Array.from({ length: pdf.numPages }, (_, i) => (
        <PaginaPdf key={i} pdf={pdf} numero={i + 1} total={pdf.numPages} ancho={ancho} />
      ))}
    </div>
  );
}

function PaginaPdf({ pdf, numero, total, ancho }: { pdf: PDFDocumentProxy; numero: number; total: number; ancho: number }) {
  const caja = useRef<HTMLDivElement>(null);
  const lienzo = useRef<HTMLCanvasElement>(null);
  const [cerca, setCerca] = useState(false);
  const [alto, setAlto] = useState(() => Math.round(ancho * 1.414));
  const [fallo, setFallo] = useState(false);
  const [intento, setIntento] = useState(0);
  const montada = useRef(true);
  useEffect(() => { montada.current = true; return () => { montada.current = false; }; }, []);

  // Se pinta cuando la hoja se acerca a la pantalla, no todas de golpe.
  useEffect(() => {
    const el = caja.current;
    if (!el) return;
    const obs = new IntersectionObserver((e) => { if (e.some((x) => x.isIntersecting)) setCerca(true); }, { rootMargin: "800px 0px" });
    obs.observe(el);
    return () => obs.disconnect();
  }, []);

  const pintar = useCallback(async () => {
    const canvas = lienzo.current;
    if (!canvas || ancho <= 0) return;
    try {
      const alturaCss = await dibujarPagina(pdf, numero, canvas, ancho);
      // null = llegó un pedido más nuevo (otro zoom): el que importa es ese, no este.
      if (alturaCss !== null && montada.current) { setAlto(alturaCss); setFallo(false); }
    } catch {
      // Una hoja que no se pudo dibujar NO se deja en blanco como si fuera una hoja en blanco:
      // quien revisa tiene que enterarse de que le falta ver algo antes de aprobar.
      if (montada.current) setFallo(true);
    }
  }, [pdf, numero, ancho]);

  // Al cambiar el zoom se espera un instante: arrastrar el control no tiene que redibujar en cada paso.
  useEffect(() => {
    if (!cerca) return;
    const t = window.setTimeout(() => void pintar(), 120);
    return () => window.clearTimeout(t);
  }, [cerca, pintar, intento]);

  return (
    <div ref={caja} style={{ width: ancho, minHeight: alto }} className="relative mx-auto max-w-none rounded-control border border-sand bg-papel">
      <canvas ref={lienzo} aria-label={`Hoja ${numero} de ${total}`} role="img" className="block rounded-control" />
      {fallo && (
        <div role="alert" className="absolute inset-0 flex flex-col items-center justify-center gap-3 rounded-control bg-papel px-4 text-center text-sm text-taupe">
          <FileWarning className="size-6" aria-hidden />
          No se pudo dibujar la hoja {numero} de {total}. No la des por vista.
          <Boton tamano="sm" onClick={() => { setFallo(false); setIntento((n) => n + 1); }}>Reintentar</Boton>
        </div>
      )}
    </div>
  );
}
