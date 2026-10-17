import { strToU8, zipSync } from "fflate";
import type { ClienteCayla } from "@cayla-dynamic/database";
import { urlFirmada } from "./constancia-medios";

/**
 * EL ZIP DE CONSTANCIAS DE UN MES — para quien pide el expediente.
 *
 * PROMETE: juntar en un solo archivo los papeles de las constancias que se le pasan,
 *   con nombres que se entienden sin abrirlos («Sandra Ramírez · Duolingo · 2026-09-30
 *   · 1.jpg») y un índice (`indice.csv`) que dice de quién es cada uno y cómo salió
 *   la revisión. Todo se arma en el navegador: el ZIP nunca pasa por un servidor.
 * ASUME: los archivos se leen con la misma URL temporal de siempre, así que quien
 *   los pide tiene que poder verlos (lo decide el almacén, no esta función).
 * NO HACE: no entrega un ZIP a medias. Si un archivo no se puede traer, se cancela
 *   todo y se dice cuál: un expediente que parece completo y no lo es es peor que
 *   uno que no se armó.
 *
 * No se comprime (nivel 0): una foto JPG y un PDF ya vienen comprimidos, y gastar el
 * procesador de un celular para ahorrar un 2 % no vale la espera.
 *
 * LLEVA DATOS PERSONALES. No se sube a git ni se reenvía (CLAUDE.md).
 */

export interface ArchivoParaZip {
  /** Cómo se llamará dentro del ZIP, ya sin repetidos ni caracteres que un sistema de archivos rechace. */
  nombre: string;
  ruta: string;
}

/** Quita lo que Windows y macOS no dejan en un nombre, conservando acentos y espacios. */
export function nombreLegible(texto: string): string {
  return texto.replace(/[\\/:*?"<>|\u0000-\u001f]/g, "").replace(/\s+/g, " ").trim().slice(0, 120) || "archivo";
}

const EXTENSION_POR_TIPO: Record<string, string> = { "application/pdf": "pdf", "image/jpeg": "jpg", "image/png": "png" };
const EXTENSIONES_CONOCIDAS = new Set(["pdf", "jpg", "jpeg", "png"]);

/**
 * La extensión con que un archivo viaja en el ZIP. Sale del tipo que verificó el almacén (o de la
 * ruta que armó el sistema), NUNCA del nombre que puso quien lo subió: ese nombre llega del navegador
 * de la integrante tal cual, y como el sistema recomprime toda foto a JPG, «IMG_0001.HEIC» es en
 * realidad un .jpg. Quien abra el ZIP en un expediente no debe encontrar un «.exe» o un «.html».
 */
export function extensionDeArchivo(a: { tipo_mime: string | null; ruta: string }): string {
  const porTipo = a.tipo_mime ? EXTENSION_POR_TIPO[a.tipo_mime] : undefined;
  if (porTipo) return porTipo;
  const deLaRuta = a.ruta.match(/\.([A-Za-z0-9]{1,5})$/)?.[1]?.toLowerCase();
  return deLaRuta && EXTENSIONES_CONOCIDAS.has(deLaRuta) ? deLaRuta : "bin";
}

const MAXIMO_DE_NOMBRE = 120;
/** Lugar que se deja para « (NN)», el sufijo que `sinRepetidos` agrega a un nombre repetido. */
const MARGEN_DE_REPETIDO = 6;

/**
 * El nombre de un archivo dentro del ZIP: «Persona - Institución - 2026-09-30 - 1.jpg». Cuando es
 * demasiado largo se recorta «Persona - Institución» y NUNCA la cola —fecha, número y extensión—,
 * que es lo que distingue una constancia de otra: cortado por el final, tres constancias de fechas
 * distintas daban el mismo nombre y perdían hasta la extensión.
 */
export function nombreEnZip(persona: string, institucion: string, fechaPago: string, numero: number, extension: string): string {
  const cola = ` - ${fechaPago} - ${numero}.${extension}`.replace(/[\\/:*?"<>|\u0000-\u001f]/g, "");
  const cabeza = nombreLegible(`${persona} - ${institucion}`).slice(0, MAXIMO_DE_NOMBRE - cola.length - MARGEN_DE_REPETIDO).trimEnd();
  return cabeza + cola;
}

/** Si dos archivos se llamarían igual, el segundo lleva «(2)», el tercero «(3)»… */
export function sinRepetidos(nombres: string[]): string[] {
  const vistos = new Map<string, number>();
  return nombres.map((n) => {
    const clave = n.toLowerCase();
    const veces = (vistos.get(clave) ?? 0) + 1;
    vistos.set(clave, veces);
    if (veces === 1) return n;
    const punto = n.lastIndexOf(".");
    return punto > 0 ? `${n.slice(0, punto)} (${veces})${n.slice(punto)}` : `${n} (${veces})`;
  });
}

export async function armarZip(
  supabase: ClienteCayla,
  archivos: ArchivoParaZip[],
  indiceCsv: string,
  alAvanzar: (hechos: number, total: number) => void,
): Promise<{ ok: true; blob: Blob } | { ok: false; error: string }> {
  const nombres = sinRepetidos(archivos.map((a) => a.nombre));
  const contenido: Record<string, Uint8Array | [Uint8Array, { level: 0 }]> = {};
  let hechos = 0;

  // De a cuatro: más rápido que de uno en uno, sin saturar la conexión de una tienda.
  const cola = archivos.map((a, i) => ({ a, nombre: nombres[i] }));
  let fallo: string | null = null;
  async function trabajador() {
    for (let item = cola.shift(); item && !fallo; item = cola.shift()) {
      try {
        const url = await urlFirmada(supabase, item.a.ruta);
        if (!url) throw new Error("sin enlace");
        const r = await fetch(url);
        if (!r.ok) throw new Error(`error ${r.status}`);
        contenido[item.nombre] = [new Uint8Array(await r.arrayBuffer()), { level: 0 }];
        alAvanzar(++hechos, archivos.length);
      } catch (e) {
        fallo = `«${item.nombre}» no se pudo traer (${e instanceof Error ? e.message : "error desconocido"})`;
      }
    }
  }
  await Promise.all(Array.from({ length: Math.min(4, archivos.length) }, trabajador));
  if (fallo) return { ok: false, error: fallo };

  // El BOM hace que Excel abra el índice en UTF-8 y no estropee los acentos.
  contenido["indice.csv"] = [strToU8("﻿" + indiceCsv), { level: 0 }];
  const bytes = zipSync(contenido);
  return { ok: true, blob: new Blob([bytes as BlobPart], { type: "application/zip" }) };
}

/** Guarda un Blob con el nombre dado, como cualquier descarga. */
export function descargarBlob(nombre: string, blob: Blob): void {
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = nombre;
  document.body.appendChild(a);
  a.click();
  a.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 10_000);
}
