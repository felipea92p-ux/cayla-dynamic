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
