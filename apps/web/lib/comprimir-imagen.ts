/**
 * REDIMENSIONAR Y COMPRIMIR UNA IMAGEN A JPEG, EN EL PROPIO NAVEGADOR.
 *
 * PROMETE: devuelve un JPEG cuyo lado mayor no pasa de `ladoMayorPx`. Nunca
 *   agranda: una imagen ya pequeña sale con su tamaño original.
 * ASUME: corre en el navegador (usa `createImageBitmap` y un `<canvas>`).
 * LANZA: si el navegador no puede decodificar el archivo o no da contexto 2D.
 *
 * ── POR QUÉ ESTÁ ACÁ Y NO COPIADO EN CADA PANTALLA ──────────────────────────
 * Nació dentro de `comprimirFotoPerfil` (0381), para que la grilla del terminal
 * no cargara 20-30 fotos de varios MB tal como salen del celular. La foto del
 * DNI (0401) necesita exactamente lo mismo con otro tamaño, y la alternativa
 * era un segundo canvas idéntico en otro archivo. Este repositorio ya pagó ese
 * precio con «qué le tocaba trabajar ese día», que llegó a tener cuatro copias
 * y una de ellas con un defecto que las otras no tenían.
 *
 * `imageOrientation: "from-image"` corrige la orientación EXIF sola — sin eso,
 * una foto tomada con el celular en vertical se subía girada.
 *
 * `giroGrados` (0, 90, 180 o 270, en sentido de las agujas del reloj) existe
 * para las boletas (0482): una foto de un papel sale de lado a menudo, y DO tiene
 * que poder enderezarla antes de guardarla. Con 0 —el valor por defecto— el
 * camino es EXACTAMENTE el de antes: la foto de perfil y la del DNI no cambian.
 *
 * Y hay un segundo efecto que no es cosmético: la salida SIEMPRE es JPEG. Los
 * buckets tienen lista cerrada de formatos, y `solicitudes-perfil` solo acepta
 * jpeg, png y pdf — un iPhone entrega HEIC, que Safari sí sabe decodificar acá
 * pero el almacén rechazaría con 415. Pasar por el canvas convierte el formato
 * antes de que eso ocurra.
 */
export async function comprimirImagen(
  archivo: File,
  ladoMayorPx: number,
  calidadJpeg: number,
  giroGrados: 0 | 90 | 180 | 270 = 0,
): Promise<Blob> {
  const bitmap = await createImageBitmap(archivo, { imageOrientation: "from-image" });
  // Con un cuarto de vuelta, el ancho y el alto de lo que se dibuja se cruzan.
  const cruzado = giroGrados === 90 || giroGrados === 270;
  const anchoOrigen = cruzado ? bitmap.height : bitmap.width;
  const altoOrigen = cruzado ? bitmap.width : bitmap.height;
  const escala = Math.min(1, ladoMayorPx / Math.max(anchoOrigen, altoOrigen));
  const ancho = Math.round(anchoOrigen * escala);
  const alto = Math.round(altoOrigen * escala);

  const canvas = document.createElement("canvas");
  canvas.width = ancho;
  canvas.height = alto;
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("Este navegador no puede procesar la imagen.");
  if (giroGrados === 0) {
    ctx.drawImage(bitmap, 0, 0, ancho, alto);
  } else {
    ctx.translate(ancho / 2, alto / 2);
    ctx.rotate((giroGrados * Math.PI) / 180);
    ctx.drawImage(bitmap, -(bitmap.width * escala) / 2, -(bitmap.height * escala) / 2, bitmap.width * escala, bitmap.height * escala);
  }
  bitmap.close();

  const blob = await new Promise<Blob | null>((resolve) =>
    canvas.toBlob(resolve, "image/jpeg", calidadJpeg),
  );
  if (!blob) throw new Error("No se pudo comprimir la imagen.");
  return blob;
}
