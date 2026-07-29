"use client";

import { useEffect } from "react";

/**
 * Pone el título del documento mientras la pantalla está montada, y lo devuelve
 * a lo que estaba al salir.
 *
 * POR QUÉ EXISTE. El nombre con el que el navegador sugiere guardar un PDF es el
 * título del documento. Sin esto, todo lo que se imprime en el sistema —boletas,
 * memos, fichas, reportes— se guardaba como «Dynamic — CAYLA», que es el título
 * del sitio. Treinta boletas al mes son treinta archivos con el mismo nombre en
 * la misma carpeta, y de ahí a mandarle a alguien el documento de otra persona
 * hay un paso. En un memo de disciplina el error es peor todavía.
 *
 * También arregla el encabezado que el navegador imprime arriba de la hoja,
 * que mostraba «Dynamic — CAYLA» en vez de decir de qué documento se trata.
 *
 * ACEPTA null A PROPÓSITO. Estas pantallas cargan sus datos con un fetch y tienen
 * varios `return` condicionales antes de saber de quién es el documento. Los hooks
 * no pueden ir después de un return, así que se llama arriba con null y el título
 * se pone en cuanto los datos llegan. Sin esto, cada pantalla tendría que
 * repetir un useEffect y buscar sus datos dentro para no romper el orden de hooks.
 *
 * Decidido con Felipe el 2026-07-28, después de ver que todas sus boletas se
 * guardaban con el mismo nombre.
 */
export function useTituloDocumento(titulo: string | null) {
  useEffect(() => {
    if (!titulo) return;
    const anterior = document.title;
    document.title = titulo;
    return () => {
      document.title = anterior;
    };
  }, [titulo]);
}
