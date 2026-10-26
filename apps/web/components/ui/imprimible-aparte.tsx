"use client";

import { useRef, useState, type ReactNode, type Ref } from "react";
import { createPortal } from "react-dom";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";

/**
 * UN DOCUMENTO QUE SE IMPRIME SOLO, DESDE DENTRO DE UN MODAL (2026-10-17).
 *
 * Los demás documentos del sistema —contrato, memo, boleta interna— tienen su
 * propia página, y «Guardar PDF» imprime esa página. Un documento que vive en
 * un modal no puede hacer eso: el modal está dentro de la pantalla, con su velo,
 * su alto máximo y su propio scroll, y lo que saliera de ahí al papel quedaría
 * recortado a lo que cabe en el modal, encima del tablero de atrás.
 *
 * Por eso esto cuelga una COPIA del documento directo de `<body>`. En pantalla
 * no se ve; al imprimir es lo único que sale (regla `.imprimible-aparte` de
 * `globals.css`). Mientras esté montado —mientras el modal esté abierto—, ⌘P
 * también saca solo el documento, que es lo que se está mirando.
 */
export function ImprimibleAparte({ children, ref }: { children: ReactNode; ref?: Ref<HTMLDivElement> }) {
  if (typeof document === "undefined") return null;
  return createPortal(
    <div ref={ref} className="imprimible-aparte">{children}</div>,
    document.body,
  );
}

/**
 * Lo que necesita quien imprime aparte: la referencia para `ImprimibleAparte`,
 * la acción del botón y si está esperando.
 *
 * Y EL NOMBRE DEL PDF, aquí dentro a propósito: el navegador propone guardar el
 * PDF con el título del documento, y sin fijarlo cualquier constancia saldría
 * como «Dynamic — CAYLA» (ver `use-titulo-documento.ts` y el hook
 * `descarga-sin-nombre.sh`). Así no hay forma de imprimir aparte sin darle
 * nombre. `null` mientras no hay documento.
 */
export function useImprimirAparte(nombreDelPdf: string | null) {
  useTituloDocumento(nombreDelPdf);
  const copia = useRef<HTMLDivElement>(null);
  const [preparando, setPreparando] = useState(false);

  async function imprimir() {
    setPreparando(true);
    try {
      await imprimirCuandoCargue(copia.current);
    } finally {
      setPreparando(false);
    }
  }

  return { copia, preparando, imprimir };
}

/**
 * Espera a que las imágenes del documento terminen de cargar y abre el diálogo
 * de imprimir, donde se elige «Guardar como PDF». Sin la espera, una foto que
 * todavía viene en camino sale como un hueco en blanco en el PDF.
 *
 * Una imagen que falla no frena: se imprime igual (el hueco se ve) en vez de
 * dejar el botón colgado. Y hay un tope de espera por la misma razón.
 */
async function imprimirCuandoCargue(contenedor: HTMLElement | null, esperaMaxMs = 10_000): Promise<void> {
  const imagenes = contenedor ? [...contenedor.querySelectorAll("img")] : [];
  const cargadas = Promise.all(
    imagenes.map((img) =>
      img.complete
        ? Promise.resolve()
        : new Promise<void>((listo) => {
            img.addEventListener("load", () => listo(), { once: true });
            img.addEventListener("error", () => listo(), { once: true });
          }),
    ),
  );
  await Promise.race([cargadas, new Promise<void>((listo) => setTimeout(listo, esperaMaxMs))]);
  window.print();
}
