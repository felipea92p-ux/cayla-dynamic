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

"use client";

import { useEffect, useId, useRef, type ReactNode } from "react";

const ANCHOS = {
  sm: "max-w-sm",
  md: "max-w-md",
  lg: "max-w-lg",
} as const;

export function Modal({
  abierto,
  onCerrar,
  titulo,
  ancho = "md",
  bloqueado = false,
  children,
}: {
  abierto: boolean;
  onCerrar: () => void;
  titulo?: string;
  /** Ancho del cuadro. Los modales reales del panel se reparten entre los
   * tres: sm para confirmaciones cortas, lg para texto legal/explicativo.
   * Por defecto md, el tamaño intermedio. */
  ancho?: keyof typeof ANCHOS;
  /** Mientras es true, ni el clic en el velo ni Escape cierran el modal —
   * para no perder una edición a medio guardar (ver CLAUDE.md). */
  bloqueado?: boolean;
  children: ReactNode;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const tituloId = useId();

  useEffect(() => {
    if (!abierto) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape" && !bloqueado) onCerrar();
    };
    document.addEventListener("keydown", onKey);
    ref.current?.focus();
    return () => document.removeEventListener("keydown", onKey);
  }, [abierto, bloqueado, onCerrar]);

  if (!abierto) return null;

  return (
    <div
      className="fixed inset-0 z-40 flex items-center justify-center bg-black/40 p-4"
      onClick={() => {
        if (!bloqueado) onCerrar();
      }}
    >
      <div
        ref={ref}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titulo ? tituloId : undefined}
        tabIndex={-1}
        className={`max-h-[90vh] w-full ${ANCHOS[ancho]} overflow-y-auto rounded-flotante border border-taupe/35 bg-papel p-6 outline-none`}
        onClick={(e) => e.stopPropagation()}
      >
        {titulo && (
          <h3 id={tituloId} className="mb-1 font-serif text-lg">
            {titulo}
          </h3>
        )}
        {children}
      </div>
    </div>
  );
}
