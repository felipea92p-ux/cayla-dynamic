/**
 * Generación de CSV para las seis pantallas que exportan.
 *
 * ── POR QUÉ ESTO NO ES SOLO «PONER COMILLAS» ────────────────────────────────
 *
 * Un CSV no tiene tipos. Quien decide qué es cada celda es el programa que lo
 * abre, y aquí ese programa es Excel. Excel adivina, y adivina mal en las tres
 * cosas que a CAYLA le importan:
 *
 *   · «08817189» lo toma por número y PIERDE EL CERO → 8817189. Medido en
 *     producción el 2026-08-10: una persona del equipo tiene el DNI así. Ese
 *     número viaja en el padrón al contador y de ahí al T-Registro.
 *   · una cuenta bancaria de 13-14 dígitos la muestra «1.94191E+13», y un CCI
 *     de 20 dígitos lo TRUNCA a 15 cifras significativas — pérdida real, no
 *     cosmética.
 *   · una celda que empieza por «=», «+», «@» la ejecuta como fórmula. Una
 *     dirección escrita «-Av. Grau 100» sale «#NAME?» y el dato desaparece.
 *
 * Entrecomillar NO protege de lo tercero, y es el error fácil de cometer: Excel
 * quita las comillas del CSV y después evalúa lo que hay dentro. Comprobado.
 *
 * ── LA FORMA QUE SÍ PROTEGE ─────────────────────────────────────────────────
 *
 * Escribir la celda como  ="08817189"  — Excel, Google Sheets y LibreOffice la
 * leen como texto literal: conservan el cero y no ejecutan nada, porque lo de
 * dentro es una cadena. Un solo mecanismo tapa los dos agujeros.
 *
 * Decisión de Felipe (2026-08-10): este archivo lo abren solo Excel o Sheets.
 * Si algún día lo consume un script o se sube a un sistema, esta forma habría
 * que cambiarla por .xlsx — el ="..." se vería literal.
 *
 * ── LO QUE NO SE BLINDA, Y ES DELIBERADO ────────────────────────────────────
 *
 * Un número de verdad se deja en paz, incluso si es negativo. Los descuentos de
 * planilla y provisiones son «-150.00»: blindarlos por empezar en «-» los
 * convertiría en texto y la columna dejaría de poder sumarse en Excel. Se
 * habría arreglado un dato y roto seis pantallas.
 */

/** Un número que Excel puede tratar como número sin estropear nada. */
const NUMERO_DE_VERDAD = /^-?\d+(?:[.,]\d+)?$/;

/**
 * Los arranques que Excel interpreta como fórmula. El «+» va aquí y no en
 * NUMERO_DE_VERDAD a propósito: «+51987654321» es un celular, no un número, y
 * dejarlo pasar le quitaría el prefijo del país.
 */
const ARRANQUE_DE_FORMULA = /^[=+@\t\r-]/;

/** Solo dígitos: candidato a identificador, no a cantidad. */
const SOLO_DIGITOS = /^\d+$/;

/**
 * ¿Excel destrozaría esta celda si la dejáramos al crudo?
 *
 * Se decide por la FORMA del valor y no por el nombre de la columna. Es a
 * propósito: una lista de columnas «que son texto» hay que acordarse de
 * ampliarla cada vez que alguien agrega una exportación, y este repo ya sabe
 * cómo terminan las listas escritas a mano. La forma no se olvida.
 */
function excelLoDestruiria(texto: string): boolean {
  if (texto === "") return false;

  // Un identificador de solo dígitos: peligra si tiene cero adelante (lo
  // pierde) o si es largo (notación científica y, pasando de 15, truncado).
  // Ocho o nueve dígitos sin cero adelante —un DNI normal, un celular— Excel
  // los muestra enteros, así que no se tocan: menos ruido en el archivo.
  if (SOLO_DIGITOS.test(texto)) {
    return texto.startsWith("0") || texto.length >= 12;
  }

  // Un número de verdad se respeta aunque empiece por «-».
  if (NUMERO_DE_VERDAD.test(texto)) return false;

  return ARRANQUE_DE_FORMULA.test(texto);
}

/** Envuelve en la forma que Excel lee como texto literal. */
function comoTextoLiteral(texto: string): string {
  return `="${texto.replace(/"/g, '""')}"`;
}

function escaparCelda(valor: unknown): string {
  const texto = valor === null || valor === undefined ? "" : String(valor);

  if (excelLoDestruiria(texto)) {
    // El ="..." lleva comillas dentro, así que la celda entera se entrecomilla
    // igual que cualquier otra. Excel deshace las dos capas en orden.
    return `"${comoTextoLiteral(texto).replace(/"/g, '""')}"`;
  }

  // El \r va en la lista además del \n. Sin él, una dirección pegada desde
  // Windows parte la fila por la mitad y descuadra el resto del archivo.
  if (/[",\n\r]/.test(texto)) {
    return `"${texto.replace(/"/g, '""')}"`;
  }
  return texto;
}

export function generarCsv(filas: Record<string, unknown>[], columnas: string[]): string {
  const encabezado = columnas.map((c) => escaparCelda(c)).join(",");
  const cuerpo = filas.map((fila) => columnas.map((c) => escaparCelda(fila[c])).join(","));
  return [encabezado, ...cuerpo].join("\n");
}

const BOM_UTF8 = "﻿"; // para que Excel reconozca UTF-8 y no rompa tildes/ñ

export function descargarCsv(nombreArchivo: string, contenido: string) {
  const blob = new Blob([BOM_UTF8 + contenido], { type: "text/csv;charset=utf-8;" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = nombreArchivo;
  a.click();
  URL.revokeObjectURL(url);
}
