/**
 * UNA FOTO DE UN PAPEL NO TIENE POR QUÉ PESAR LO QUE PESA.
 *
 * PROMETE: devuelve la misma imagen con el lado mayor recortado a `maxLado`
 *   píxeles y recomprimida como JPEG, o EL ARCHIVO ORIGINAL si no es una imagen
 *   o si algo sale mal. Nunca lanza y nunca devuelve algo más pesado que lo que
 *   recibió.
 * ASUME: corre en el navegador. No hay `canvas` en el servidor.
 * NO HACE: no sube nada, no recorta contenido, no toca PDFs.
 *
 * ── POR QUÉ EXISTE ──────────────────────────────────────────────────────────
 * El 2026-08-26 no se pudo adjuntar el certificado de un descanso médico: una
 * foto de un papel tomada con el celular de la tienda. El tope del proyecto
 * estaba en 50 MB y el del almacén también, así que el número no era el
 * problema — pero cada tope que se amplía solo mueve el muro más lejos, y quien
 * está registrando una ausencia no puede ponerse a comprimir una foto.
 *
 * Un certificado del Colegio Médico se lee entero con el lado mayor en 2400 px:
 * es más resolución que la que tiene el papel impreso. Lo que sobra son píxeles
 * de la cámara, no información del documento — y esa foto se guarda para que
 * EsSalud reembolse a partir del día 21, no para ampliarla.
 *
 * SE DEVUELVE EL ORIGINAL ANTE CUALQUIER DUDA, y es lo importante. Si el
 * navegador no sabe abrir el formato (un `.HEIC` en Chrome), si el canvas falla,
 * o si el resultado pesa más que la entrada, se sube lo que la persona eligió.
 * Perder el certificado por un intento de ahorrar espacio sería el peor
 * intercambio posible — el mismo criterio con el que la pantalla de Ausencias
 * ya registra la ausencia aunque el archivo no suba.
 */
export async function reducirImagen(
  archivo: File,
  maxLado = 2400,
  calidad = 0.85,
): Promise<File> {
  if (!archivo.type.startsWith("image/")) return archivo;
  if (typeof document === "undefined" || typeof createImageBitmap !== "function") return archivo;

  try {
    const bitmap = await createImageBitmap(archivo);
    const lado = Math.max(bitmap.width, bitmap.height);
    // Ya cabe: no se recomprime. Recomprimir un JPEG que no lo necesita solo
    // le quita calidad al papel sin ganar nada.
    if (lado <= maxLado) { bitmap.close?.(); return archivo; }

    const escala = maxLado / lado;
    const lienzo = document.createElement("canvas");
    lienzo.width = Math.round(bitmap.width * escala);
    lienzo.height = Math.round(bitmap.height * escala);
    const ctx = lienzo.getContext("2d");
    if (!ctx) { bitmap.close?.(); return archivo; }
    ctx.drawImage(bitmap, 0, 0, lienzo.width, lienzo.height);
    bitmap.close?.();

    const blob = await new Promise<Blob | null>((r) => lienzo.toBlob(r, "image/jpeg", calidad));
    if (!blob || blob.size >= archivo.size) return archivo;

    // El nombre cambia de extensión porque el contenido cambió de formato: la
    // ruta del almacén se arma con esa extensión, y un JPEG guardado como .png
    // es un archivo que se abre mal el día que alguien lo descargue.
    const base = archivo.name.replace(/\.[^.]+$/, "");
    return new File([blob], `${base}.jpg`, { type: "image/jpeg", lastModified: archivo.lastModified });
  } catch {
    return archivo;
  }
}

/** «2.4 MB», para decirle a alguien cuánto pesaba lo que no entró. */
export function pesoLegible(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}
