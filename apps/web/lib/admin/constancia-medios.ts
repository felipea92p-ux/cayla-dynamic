import type { PDFDocumentProxy, RenderTask } from "pdfjs-dist";
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
  if (!cargaPdfjs) {
    cargaPdfjs = import("pdfjs-dist/legacy/build/pdf.mjs")
      .then((m) => {
        m.GlobalWorkerOptions.workerSrc = new URL("pdfjs-dist/legacy/build/pdf.worker.min.mjs", import.meta.url).toString();
        return m;
      })
      // Una carga que falló NO se queda guardada: «Reintentar» tiene que volver a pedir el archivo, no
      // esperar la misma promesa rechazada hasta que alguien recargue la página.
      .catch((e) => { cargaPdfjs = null; throw e; });
  }
  return cargaPdfjs;
}

/**
 * Dónde viven los decodificadores `wasm` de pdf.js (`public/pdfjs/wasm/`, copiados de
 * `node_modules/pdfjs-dist/wasm/`; `tests/pdfjs-wasm.test.ts` vigila que sigan siendo los de la
 * versión instalada). SIN ellos, un PDF escaneado en blanco y negro (JBIG2, CCITT) o con
 * JPEG 2000 sale EN BLANCO, sin ningún error a la vista: justo lo que es una constancia que alguien
 * escaneó en el banco. Medido el 2026-10-16 con un PDF de prueba JPEG 2000: hoja en blanco antes,
 * hoja legible después. Tiene que ser una dirección ABSOLUTA: el worker la resuelve desde su
 * propio archivo, no desde la página.
 */
const wasmUrl = (): string => `${window.location.origin}/pdfjs/wasm/`;

export interface PdfAbierto {
  pdf: PDFDocumentProxy;
  /** Suelta el documento y su worker. Quien abre es quien cierra. */
  cerrar: () => void;
}

/** Abre un PDF desde su URL firmada. En pdf.js 6 quien se destruye es la TAREA de carga, no el documento. */
export async function abrirPdf(url: string): Promise<PdfAbierto> {
  const lib = await pdfjs();
  const tarea = lib.getDocument({ url, wasmUrl: wasmUrl() });
  try {
    const pdf = await tarea.promise;
    return { pdf, cerrar: () => { void tarea.destroy(); } };
  } catch (e) {
    void tarea.destroy();
    throw e;
  }
}

/** Un canvas de iPhone/iPad no pasa de unos 16,7 millones de píxeles: más y la hoja sale en blanco. */
const MAX_PIXELES_DE_CANVAS = 12_000_000;

/** El dibujado que está en marcha en cada canvas: pdf.js no deja dos a la vez sobre el mismo. */
const dibujosEnCurso = new WeakMap<HTMLCanvasElement, RenderTask>();
/** Cuál fue el último pedido de dibujo de cada canvas: el que llegue tarde con un ancho viejo se descarta. */
const pedidos = new WeakMap<HTMLCanvasElement, number>();

/**
 * Dibuja una página en un canvas a un ancho en píxeles CSS. El canvas se hace del
 * tamaño real de la pantalla (ancho × densidad de píxeles, con tope) para que el texto se lea
 * nítido, y se muestra al ancho pedido.
 *
 * Devuelve el alto en píxeles CSS, o `null` si este dibujo quedó obsoleto porque llegó otro
 * pedido para el mismo canvas (cambió el zoom o el ancho a media hoja): el que manda es el último.
 * LANZA si no hay contexto 2D o si pdf.js falla: quien dibuja tiene que poder DECIR que una hoja
 * no se pudo ver, y no dejarla en blanco como si fuera una hoja en blanco.
 */
export async function dibujarPagina(
  pdf: PDFDocumentProxy,
  numero: number,
  canvas: HTMLCanvasElement,
  anchoCss: number,
): Promise<number | null> {
  const mio = (pedidos.get(canvas) ?? 0) + 1;
  pedidos.set(canvas, mio);

  const pagina = await pdf.getPage(numero);
  const base = pagina.getViewport({ scale: 1 });
  // Tope de 2×: más densidad no se nota en una constancia y en un celular gasta memoria de más.
  const densidad = Math.min(window.devicePixelRatio || 1, 2);
  let escala = (anchoCss / base.width) * densidad;
  const area = base.width * escala * base.height * escala;
  if (area > MAX_PIXELES_DE_CANVAS) escala *= Math.sqrt(MAX_PIXELES_DE_CANVAS / area);
  const vista = pagina.getViewport({ scale: escala });
  // El alto en pantalla sale de la proporción de la hoja, no del canvas: si el tope recortó la
  // resolución, la hoja se sigue mostrando entera y al ancho pedido.
  const altoCss = Math.floor((anchoCss * base.height) / base.width);

  // pdf.js lanza «Cannot use the same canvas during multiple render() operations»: se cancela el
  // dibujo anterior y se espera a que suelte el canvas antes de tocar su tamaño (que lo borra).
  const previo = dibujosEnCurso.get(canvas);
  if (previo) {
    previo.cancel();
    await previo.promise.catch(() => {});
  }
  if (pedidos.get(canvas) !== mio) return null;

  canvas.width = Math.floor(vista.width);
  canvas.height = Math.floor(vista.height);
  canvas.style.width = `${anchoCss}px`;
  canvas.style.height = `${altoCss}px`;
  const contexto = canvas.getContext("2d");
  if (!contexto) throw new Error("El navegador no dio un lienzo para dibujar la hoja.");

  const tarea = pagina.render({ canvas, canvasContext: contexto, viewport: vista });
  dibujosEnCurso.set(canvas, tarea);
  try {
    await tarea.promise;
  } catch (e) {
    if ((e as { name?: string })?.name === "RenderingCancelledException") return null;
    throw e;
  } finally {
    if (dibujosEnCurso.get(canvas) === tarea) dibujosEnCurso.delete(canvas);
  }
  return altoCss;
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
