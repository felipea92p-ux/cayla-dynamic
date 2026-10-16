import type { PDFDocumentProxy } from "pdfjs-dist";
import type { ClienteCayla } from "@cayla-dynamic/database";
import { BUCKET_COMPROBANTES } from "@/lib/educacion";
import type { ArchivoDeEntrega } from "./educacion-tipos";

/**
 * VER UNA CONSTANCIA SIN DESCARGARLA: enlaces firmados, fotos y PDF dibujados
 * dentro de la pantalla.
 *
 * PROMETE: dar una URL temporal para un archivo del almacén privado de
 *   constancias, y dibujar un PDF página por página en un `<canvas>`, de modo que
 *   se vea igual en una computadora que en un iPhone.
 * ASUME: corre en el navegador, con sesión abierta. Quién puede leer cada
 *   archivo lo decide la política del almacén en la base, no esta función.
 * NO HACE: no descarga nada al disco ni deja un enlace vivo dando vueltas: la
 *   URL dura cinco minutos, como siempre, y se vuelve a pedir cuando caduca.
 *
 * ── POR QUÉ SE DIBUJA EL PDF Y NO SE INCRUSTA ───────────────────────────────
 * Decisión de Felipe (2026-10-16): DO revisa desde computadora Y celular. El
 * visor de PDF incrustado del navegador (`<iframe>`/`<object>`) funciona bien en
 * una Mac, pero Safari de iPhone muestra solo la PRIMERA página de un PDF
 * incrustado: una constancia de dos hojas se vería completa en un lado e
 * incompleta en el otro, y quien revisa no se enteraría. pdf.js dibuja cada
 * página como imagen y se ve igual en todos lados.
 *
 * Se carga la versión `legacy` de pdf.js porque la normal usa funciones del
 * navegador que un iPhone de hace dos años todavía no tiene. Y se carga con
 * `import()` dinámico, la primera vez que hace falta: la pantalla de Educación
 * no paga el peso de pdf.js hasta que alguien abre un PDF.
 *
 * SE ROMPE SI: se sube pdfjs-dist de versión mayor sin probar el worker —el
 * archivo del worker tiene que ser de la MISMA versión que la librería, y por
 * eso se resuelve con `new URL(…, import.meta.url)` desde el mismo paquete— o
 * si alguien alarga el tiempo de la URL firmada «para que no caduque»: el
 * almacén es privado a propósito (ver «Dónde están las constancias»).
 */

const SEGUNDOS_DE_VIDA = 300;
/** Se vuelve a firmar un minuto antes de que caduque, para no entregar una URL que muere en el camino. */
const MARGEN_MS = 60_000;

const guardadas = new Map<string, { url: string; vence: number }>();
const enVuelo = new Map<string, Promise<string | null>>();

/** La URL temporal de un archivo de constancia. Misma ruta, misma URL, mientras no caduque. */
export function urlFirmada(supabase: ClienteCayla, ruta: string): Promise<string | null> {
  const guardada = guardadas.get(ruta);
  if (guardada && guardada.vence > Date.now()) return Promise.resolve(guardada.url);
  const pidiendo = enVuelo.get(ruta);
  if (pidiendo) return pidiendo;

  const p = (async () => {
    const { data } = await supabase.storage.from(BUCKET_COMPROBANTES).createSignedUrl(ruta, SEGUNDOS_DE_VIDA);
    if (!data?.signedUrl) return null;
    guardadas.set(ruta, { url: data.signedUrl, vence: Date.now() + SEGUNDOS_DE_VIDA * 1000 - MARGEN_MS });
    return data.signedUrl;
  })().finally(() => enVuelo.delete(ruta));
  enVuelo.set(ruta, p);
  return p;
}

type Archivo = Pick<ArchivoDeEntrega, "ruta" | "tipo_mime">;

export const esImagen = (a: Archivo): boolean =>
  (a.tipo_mime ?? "").startsWith("image/") ? !/heic|heif/i.test(a.tipo_mime ?? "") : /\.(jpe?g|png|webp|gif)$/i.test(a.ruta);

export const esPdf = (a: Archivo): boolean => a.tipo_mime === "application/pdf" || /\.pdf$/i.test(a.ruta);

// ── pdf.js ───────────────────────────────────────────────────────────────────

type Pdfjs = typeof import("pdfjs-dist");
let cargaPdfjs: Promise<Pdfjs> | null = null;

function pdfjs(): Promise<Pdfjs> {
  cargaPdfjs ??= import("pdfjs-dist/legacy/build/pdf.mjs").then((m) => {
    m.GlobalWorkerOptions.workerSrc = new URL("pdfjs-dist/legacy/build/pdf.worker.min.mjs", import.meta.url).toString();
    return m;
  });
  return cargaPdfjs;
}

export interface PdfAbierto {
  pdf: PDFDocumentProxy;
  /** Suelta el documento y su worker. Quien abre es quien cierra. */
  cerrar: () => void;
}

/** Abre un PDF desde su URL firmada. En pdf.js 6 quien se destruye es la TAREA de carga, no el documento. */
export async function abrirPdf(url: string): Promise<PdfAbierto> {
  const lib = await pdfjs();
  const tarea = lib.getDocument({ url });
  try {
    const pdf = await tarea.promise;
    return { pdf, cerrar: () => { void tarea.destroy(); } };
  } catch (e) {
    void tarea.destroy();
    throw e;
  }
}

/**
 * Dibuja una página en un canvas a un ancho en píxeles CSS. El canvas se hace del
 * tamaño real de la pantalla (ancho × densidad de píxeles) para que el texto se lea
 * nítido, y se muestra al ancho pedido. Devuelve el alto en píxeles CSS.
 */
export async function dibujarPagina(
  pdf: PDFDocumentProxy,
  numero: number,
  canvas: HTMLCanvasElement,
  anchoCss: number,
): Promise<number> {
  const pagina = await pdf.getPage(numero);
  const base = pagina.getViewport({ scale: 1 });
  // Tope de 2×: más densidad no se nota en una constancia y en un celular gasta memoria de más.
  const densidad = Math.min(window.devicePixelRatio || 1, 2);
  const vista = pagina.getViewport({ scale: (anchoCss / base.width) * densidad });
  canvas.width = Math.floor(vista.width);
  canvas.height = Math.floor(vista.height);
  canvas.style.width = `${anchoCss}px`;
  canvas.style.height = `${Math.floor(vista.height / densidad)}px`;
  const contexto = canvas.getContext("2d");
  if (!contexto) return 0;
  await pagina.render({ canvas, canvasContext: contexto, viewport: vista }).promise;
  return Math.floor(vista.height / densidad);
}

// ── Miniaturas ───────────────────────────────────────────────────────────────

const miniaturasDePdf = new Map<string, Promise<string | null>>();

// De a dos: bajar y dibujar la primera hoja de cuarenta PDF a la vez le quita el
// ancho de banda a lo que la persona está mirando.
let activos = 0;
const esperando: (() => void)[] = [];
async function turno<T>(trabajo: () => Promise<T>): Promise<T> {
  if (activos >= 2) await new Promise<void>((seguir) => esperando.push(seguir));
  activos += 1;
  try {
    return await trabajo();
  } finally {
    activos -= 1;
    esperando.shift()?.();
  }
}

/** La primera hoja de un PDF como imagen chica, o null si no se pudo. Se guarda por ruta. */
export function miniaturaDePdf(supabase: ClienteCayla, ruta: string, ancho: number): Promise<string | null> {
  const clave = `${ruta}@${ancho}`;
  const ya = miniaturasDePdf.get(clave);
  if (ya) return ya;
  const p = turno(async () => {
    try {
      const url = await urlFirmada(supabase, ruta);
      if (!url) return null;
      const abierto = await abrirPdf(url);
      try {
        const canvas = document.createElement("canvas");
        await dibujarPagina(abierto.pdf, 1, canvas, ancho);
        return canvas.toDataURL("image/jpeg", 0.72);
      } finally {
        abierto.cerrar();
      }
    } catch {
      return null;
    }
  });
  miniaturasDePdf.set(clave, p);
  // Un fallo no se recuerda: la próxima vez que la casilla se vea se intenta otra vez.
  void p.then((r) => { if (r === null) miniaturasDePdf.delete(clave); });
  return p;
}
