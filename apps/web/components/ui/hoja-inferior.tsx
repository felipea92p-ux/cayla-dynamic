// La hoja que sube desde abajo (2026-10-06, primera pantalla de la revisión de
// celular: filtros del Dashboard). Hermana de Drawer y Modal, no su reemplazo:
//   · Modal  — confirmaciones cortas y texto legal, centrado.
//   · Drawer — un formulario largo, entra por la derecha.
//   · HojaInferior — pocas opciones que se eligen con el pulgar. En un teléfono
//     lo que está abajo es lo que se alcanza sin soltar el aparato, y una caja
//     de filtros de 310 px de alto metida en la página se comía una pantalla
//     entera antes del primer dato.
//
// Reusa los mismos dos hooks que Drawer (`useSalidaAnimada`, `useFocoAtrapado`)
// y no escribe una tercera versión de «animar la salida» ni de «atrapar el
// foco». Cierra con Escape y con un toque en el velo, y devuelve el foco a quien
// la abrió.
//
// Solo existe en pantallas angostas (`sm:hidden`): a partir de 640 px los
// controles que ella aloja ya están a la vista en la página, así que una hoja
// abierta al agrandar la ventana no tiene a qué servir y se esconde sola.

"use client";

import { useId, useRef, type ReactNode } from "react";
import { useSalidaAnimada } from "@/lib/use-salida-animada";
import { useFocoAtrapado } from "@/lib/use-foco-atrapado";

// Tiene que calzar con la duración de `.hoja-sale` en globals.css.
const DURACION_SALIDA_MS = 200;

export function HojaInferior({
  abierto,
  onCerrar,
  titulo,
  accion,
  volverElFocoA,
  children,
}: {
  abierto: boolean;
  onCerrar: () => void;
  titulo: string;
  /** Algo a la derecha del título — «Limpiar», por ejemplo. */
  accion?: ReactNode;
  /** A quién devolverle el foco al cerrar: el botón que abrió la hoja. */
  volverElFocoA: React.RefObject<HTMLElement | null>;
  children: ReactNode;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const tituloId = useId();
  const { montado, saliendo } = useSalidaAnimada(abierto, DURACION_SALIDA_MS);

  useFocoAtrapado({ abierto, onCerrar, caja: ref, volverElFocoA });

  if (!montado) return null;

  return (
    <div
      className={`fixed inset-0 z-40 bg-black/40 sm:hidden ${saliendo ? "velo-sale" : "velo-entra"}`}
      onClick={onCerrar}
    >
      <div
        ref={ref}
        role="dialog"
        aria-modal="true"
        aria-labelledby={tituloId}
        tabIndex={-1}
        className={`absolute inset-x-0 bottom-0 flex max-h-[85vh] flex-col rounded-t-flotante border-t border-taupe/35 bg-papel outline-none ${saliendo ? "hoja-sale" : "hoja-entra"}`}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex shrink-0 items-baseline justify-between gap-3 px-5 pt-4 pb-2">
          <h2 id={tituloId} className="font-serif text-xl font-medium text-tinta">
            {titulo}
          </h2>
          {accion}
        </div>
        {/* El margen inferior respeta la barra de gestos de iOS: sin él, el botón
            de abajo queda pegado a la línea del sistema y se toca mal. */}
        <div className="flex-1 overflow-y-auto px-5 pt-2 pb-[max(1.25rem,env(safe-area-inset-bottom))]">{children}</div>
      </div>
    </div>
  );
}
