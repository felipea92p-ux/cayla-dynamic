function escaparCelda(valor: unknown): string {
  const texto = valor === null || valor === undefined ? "" : String(valor);
  if (/[",\n]/.test(texto)) {
    return `"${texto.replace(/"/g, '""')}"`;
  }
  return texto;
}

export function generarCsv(filas: Record<string, unknown>[], columnas: string[]): string {
  const encabezado = columnas.join(",");
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
