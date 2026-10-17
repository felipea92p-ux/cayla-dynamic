// ============================================================================
// leer-poliza-pdf.ts — sacar el texto de un PDF, en el navegador
// ============================================================================
// QUÉ PROMETE
//   Dado un archivo PDF, devuelve el texto de cada página, en orden, listo para `leerPolizas`
//   (`leer-poliza.ts`). Usa pdf.js con la MISMA carga que ya tiene la app para dibujar constancias
//   (`abrirPdf`: versión `legacy`, worker de la misma versión, decodificadores wasm), así que no
//   agrega una segunda forma de abrir un PDF ni un segundo riesgo de versión.
//
// SE LEE AQUÍ, NO EN EL SERVIDOR
//   El PDF de una póliza lleva documento y fecha de nacimiento del asegurado. Leerlo en el navegador
//   significa que, hasta que DO registre la póliza y suba el archivo, nada de su contenido sale de la
//   computadora de quien lo abrió. Es la razón de que esto no sea una ruta de la API.
//
// QUÉ NO HACE
//   No entiende el texto (eso es `leer-poliza.ts`) ni hace OCR: un PDF que es una foto escaneada no
//   tiene texto que sacar, y la pantalla dice «regístrala a mano». Nunca lanza por un PDF malo: quien
//   llama recibe el motivo, para decírselo a quien lo subió.
// ============================================================================
import { abrirPdf, type PdfAbierto } from "./constancia-medios";

/** Un tope contra un PDF absurdo: las pólizas de seguros rondan las 100 páginas (la de FOLA, 89). */
const MAX_PAGINAS = 400;

/** `truncado`: el PDF tenía más páginas que `MAX_PAGINAS` y solo se leyeron las primeras: se le dice a quien lo subió. */
export type LecturaDePdf = { ok: true; paginas: string[]; truncado: boolean } | { ok: false; motivo: string };

/**
 * El texto de cada página. Los trozos de texto se separan con un espacio, o con un salto donde pdf.js dice
 * que termina el renglón: `leerPolizas` ya cuenta con eso (los espacios de más los limpia ella).
 */
export async function textoDeLasPaginas(archivo: File): Promise<LecturaDePdf> {
  const url = URL.createObjectURL(archivo);
  let abierto: PdfAbierto | null = null;
  try {
    abierto = await abrirPdf(url);
    const total = Math.min(abierto.pdf.numPages, MAX_PAGINAS);
    const paginas: string[] = [];
    for (let i = 1; i <= total; i++) {
      const pagina = await abierto.pdf.getPage(i);
      const contenido = await pagina.getTextContent();
      paginas.push(contenido.items.map((it) => ("str" in it ? it.str + (it.hasEOL ? "\n" : " ") : "")).join(""));
    }
    return { ok: true, paginas, truncado: abierto.pdf.numPages > MAX_PAGINAS };
  } catch (e) {
    // pdf.js nombra el caso que sí se puede explicar: un PDF protegido con clave.
    const nombre = (e as { name?: string } | null)?.name;
    return { ok: false, motivo: nombre === "PasswordException" ? "Tiene clave: ábrelo, guárdalo sin clave y vuelve a elegirlo." : "No se pudo abrir el PDF." };
  } finally {
    abierto?.cerrar();
    URL.revokeObjectURL(url);
  }
}
