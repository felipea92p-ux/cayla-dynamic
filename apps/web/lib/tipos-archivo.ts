/**
 * QUÉ TIPO DE ARCHIVO ES ESTE PAPEL — el único lugar donde se decide.
 *
 * El navegador no siempre sabe qué acaba de elegir la persona. Un `.HEIC` —el
 * formato en que un iPhone guarda sus fotos desde 2017— llega SIN tipo en
 * Chrome, que no lo reconoce. Y sin tipo, tanto el almacén de archivos como la
 * base lo tratan como un binario cualquiera y lo rechazan:
 *
 *     415 · mime type application/octet-stream is not supported
 *
 * Desde la pantalla eso se ve como «no me deja subir el archivo», sin nada que
 * la persona pueda hacer al respecto: la foto es correcta, el permiso es
 * correcto, y aun así no entra. Medido el 2026-08-06 contra el almacén local:
 * la MISMA foto sube si se declara `image/heic` y se rechaza si va sin tipo.
 *
 * Cuando el navegador no lo dice, la extensión del nombre es el único dato
 * fiable que queda. No se adivina el contenido: solo se traduce lo que el
 * sistema operativo ya afirmó al ponerle nombre al archivo.
 */

/**
 * Los formatos que aceptan los tres buckets y `fn_subir_acta_descanso`.
 *
 * `.heif` se declara como `image/heic` a propósito: son el mismo contenedor
 * (HEIC es HEIF con codec HEVC) y los buckets solo tienen `image/heic` en su
 * lista. Se prefirió traducirlo acá antes que abrir un tipo más en los tres
 * buckets por una variante que casi no aparece — un permiso menos que mantener.
 */
const MIME_POR_EXTENSION: Record<string, string> = {
  pdf: "application/pdf",
  png: "image/png",
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  webp: "image/webp",
  heic: "image/heic",
  heif: "image/heic",
};

const TIPOS_VALIDOS = new Set(Object.values(MIME_POR_EXTENSION));

/** El tipo declarado por el navegador si sirve; si no, el que dice la extensión. */
export function tipoDeArchivo(nombre: string, tipoDeclarado: string): string {
  if (TIPOS_VALIDOS.has(tipoDeclarado)) return tipoDeclarado;
  return MIME_POR_EXTENSION[nombre.split(".").pop()?.toLowerCase() ?? ""] ?? tipoDeclarado;
}

/**
 * El mismo archivo, pero declarando un tipo que el almacén acepte.
 *
 * `slice` y no `new File(...)`: devuelve una vista sobre los mismos bytes en vez
 * de copiarlos. Con un escaneo de 40 MB, copiar sería duplicarlo en memoria del
 * navegador de la sede para no cambiar ni un byte.
 */
export function conTipoDeclarado(archivo: File): Blob {
  const tipo = tipoDeArchivo(archivo.name, archivo.type);
  return tipo === archivo.type ? archivo : archivo.slice(0, archivo.size, tipo);
}

/**
 * Corrige la cabecera de un data URL cuando el navegador no supo dar el tipo.
 *
 * Lo usa Feriados, que guarda el acta como texto en la base en vez de en el
 * almacén. Si la extensión tampoco dice nada, se deja como está: la base es la
 * que decide, y su mensaje es mejor que uno inventado acá.
 */
export function conTipoCorregido(dataurl: string, nombre: string): string {
  const corte = dataurl.indexOf(";base64,");
  if (corte < 0) return dataurl;
  const declarado = dataurl.slice(5, corte);
  const tipo = tipoDeArchivo(nombre, declarado);
  return tipo === declarado ? dataurl : `data:${tipo}${dataurl.slice(corte)}`;
}
