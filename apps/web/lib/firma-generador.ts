/**
 * Genera la imagen de una firma a partir de un nombre escrito, en vez de
 * escanear una firma manuscrita. Sirve para que cualquier colaboradora pueda
 * tener una firma que estampar en su propio contrato sin necesitar cámara ni
 * escáner — algo que `firmas_escaneadas` no cubría porque nació solo para
 * quien firma documentos EN NOMBRE DE LA EMPRESA (ver 0065/0076/0393).
 *
 * El resultado es una data-url PNG en el MISMO formato que ya acepta
 * `fn_set_mi_firma` — a propósito, para poder guardarla tal cual con
 * `supabase.rpc("fn_set_mi_firma", { p_dataurl })` sin ninguna conversión
 * intermedia.
 */

// Mismo ancho al que la pantalla de contratos ya reescala una firma escaneada
// (comentario de la 0076: "una firma real ronda los 20-80 KB" a este ancho).
const ANCHO_PX = 520;
const ALTO_PX = 200;
const TAMANO_FUENTE_INICIAL_PX = 72;
const TAMANO_FUENTE_MINIMO_PX = 24;
const MARGEN_HORIZONTAL_PX = 40;

/**
 * `fontFamily` tiene que ser un nombre YA CARGADO en el documento (el
 * `style.fontFamily` que devuelve `next/font/google`, no un nombre cualquiera
 * de Google Fonts): un canvas no dispara la descarga de una tipografía por sí
 * solo, y dibujar antes de que esté lista se ve con la tipografía por
 * defecto, en silencio, sin ningún error.
 */
export async function generarImagenFirma(nombre: string, fontFamily: string): Promise<string> {
  const texto = nombre.trim();
  if (!texto) throw new Error("Escribe un nombre para generar la firma.");

  const canvas = document.createElement("canvas");
  canvas.width = ANCHO_PX;
  canvas.height = ALTO_PX;
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("Este navegador no puede generar la firma.");

  await document.fonts.load(`${TAMANO_FUENTE_INICIAL_PX}px ${fontFamily}`, texto);

  ctx.clearRect(0, 0, ANCHO_PX, ALTO_PX);
  // La firma se imprime siempre sobre el papel claro del contrato (la clase
  // `.hoja` fuerza esa paleta al imprimir — ver CLAUDE.md), nunca en modo
  // oscuro, así que va en tinta fija y no en el token `--color-tinta`.
  ctx.fillStyle = "#1a1a18";
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";

  let tamano = TAMANO_FUENTE_INICIAL_PX;
  ctx.font = `${tamano}px ${fontFamily}`;
  while (ctx.measureText(texto).width > ANCHO_PX - MARGEN_HORIZONTAL_PX && tamano > TAMANO_FUENTE_MINIMO_PX) {
    tamano -= 2;
    ctx.font = `${tamano}px ${fontFamily}`;
  }

  ctx.fillText(texto, ANCHO_PX / 2, ALTO_PX / 2);
  return canvas.toDataURL("image/png");
}
