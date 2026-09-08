// Componente compartido de modal (2026-09-06). Antes había 5-8
// reimplementaciones manuales de "fixed inset-0 ... bg-black/40", con z-index
// inconsistente (z-10, z-20, z-40, z-50 conviviendo) y sin nada en común que
// cerrara con Escape o marcara role="dialog". Un solo z-index (z-40) y un
// solo scrim (bg-black/40, no bg-tinta/NN: ese se aclara mal en modo oscuro —
// ver CLAUDE.md) para todos los modales de acá en adelante.
//
// Es un mínimo funcional: cierra con Escape y pone el foco en el contenedor.
// Un atrapado de foco completo (que Tab no se escape del modal) queda como
// mejora pendiente, no bloqueaba los fundamentos.
//
// Retocado 2026-09-07, antes de que se use en la primera pantalla real:
// - `ancho` reemplaza el max-w-md clavado. Medidos los 6 modales escritos a
//   mano que existen hoy: 4 son max-w-sm, 2 son max-w-md — ninguno más
//   ancho. "md" sigue siendo el default para no romper la firma.
// - `titulo`, si llega, ahora SE DIBUJA (antes solo alimentaba aria-label,
//   así que quien lo pasara iba a escribir el encabezado dos veces: una acá
//   sin que se viera, y otra a mano dentro de `children`). El rótulo de
//   accesibilidad pasa a `aria-labelledby` apuntando al propio `<h2>` — una
//   sola fuente de verdad en vez de dos copias del mismo texto.

"use client";

import { useEffect, useId, useRef, type ReactNode } from "react";

// "xl" se agregó con la 0401, para el primer modal que no muestra un formulario
// sino un DOCUMENTO: la foto de un DNI a max-w-lg se ve, pero no se LEE, y ese
// modal existe justamente para mirarlo de cerca. Los cuatro anchos siguen
// siendo una lista corta a propósito — el día que haga falta un quinto, será
// porque hay una razón como esta y no porque cada pantalla eligió el suyo.
const ANCHO: Record<"sm" | "md" | "lg" | "xl", string> = {
  sm: "max-w-sm",
  md: "max-w-md",
  lg: "max-w-lg",
  xl: "max-w-3xl",
};

export function Modal({
  abierto,
  onCerrar,
  titulo,
  ancho = "md",
  children,
}: {
  abierto: boolean;
  onCerrar: () => void;
  titulo?: string;
  /** Ancho del recuadro. La mayoría de los modales de hoy son "sm"; "md" es el
   *  default por compatibilidad. "xl" es para mirar un documento, no un formulario. */
  ancho?: "sm" | "md" | "lg" | "xl";
  children: ReactNode;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const tituloId = useId();

  useEffect(() => {
    if (!abierto) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onCerrar();
    };
    document.addEventListener("keydown", onKey);
    ref.current?.focus();
    return () => document.removeEventListener("keydown", onKey);
  }, [abierto, onCerrar]);

  if (!abierto) return null;

  return (
    <div
      className="fixed inset-0 z-40 flex items-center justify-center bg-black/40 p-4"
      onClick={onCerrar}
    >
      <div
        ref={ref}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titulo ? tituloId : undefined}
        aria-label={titulo ? undefined : "Diálogo"}
        tabIndex={-1}
        className={`max-h-[90vh] w-full ${ANCHO[ancho]} overflow-y-auto rounded-flotante border border-taupe/35 bg-papel p-6 outline-none`}
        onClick={(e) => e.stopPropagation()}
      >
        {titulo && (
          <h2 id={tituloId} className="mb-4 font-serif text-lg font-medium text-tinta">
            {titulo}
          </h2>
        )}
        {children}
      </div>
    </div>
  );
}
