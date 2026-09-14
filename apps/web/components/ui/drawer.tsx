// Panel lateral compartido (2026-09-14) — mismo criterio que components/ui/modal.tsx,
// solo que anclado al borde derecho y a toda la altura en vez de centrado. Se
// escribe aparte de Modal (no un `ancho="pantalla-completa-lateral"` sobre el
// mismo componente) porque la forma en que se posiciona —justify-end, h-full,
// borde en vez de esquinas redondeadas en los cuatro lados— es distinta, y
// forzar las dos formas dentro de un solo componente habría dejado un montón
// de props que solo tienen sentido para una de las dos.
//
// Para un formulario largo (alta o edición de una persona, con quince campos):
// mantiene la tabla de fondo visible/con contexto en vez de navegar a otra
// ruta, y no obliga a la pantalla a auto-desplazarse hasta un panel que
// empujaba el contenido hacia abajo — el panel ya está siempre a la vista,
// entero, sin importar dónde estaba el scroll de la tabla.
//
// Mínimo funcional, igual que Modal: cierra con Escape y con clic en el velo,
// devuelve el foco al contenedor al abrir. `bloqueado` evita las dos formas de
// cierre mientras hay un guardado en curso, para no perder una edición a
// medio guardar.

"use client";

import { useEffect, useId, useRef, type ReactNode } from "react";

const ANCHO: Record<"sm" | "md" | "lg", string> = {
  sm: "max-w-sm",
  md: "max-w-md",
  // El formulario de alta/edición de Equipo tiene quince campos a dos
  // columnas (`sm:grid-cols-2`) — "lg" es el que les da aire sin acercarse al
  // ancho de la tabla que queda detrás.
  lg: "max-w-lg",
};

export function Drawer({
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
  ancho?: "sm" | "md" | "lg";
  /** Mientras es true, ni el clic en el velo ni Escape cierran el panel — para
   * no perder una edición a medio guardar (mismo criterio que Modal). */
  bloqueado?: boolean;
  children: ReactNode;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const tituloId = useId();

  // Mismo motivo que en Modal: depende solo de `abierto`, nunca de `onCerrar`
  // (que llega como función nueva en cada render de quien lo usa) — si no,
  // cada tecla escrita en un campo de adentro le robaría el foco al panel.
  useEffect(() => {
    if (!abierto) return;
    ref.current?.focus();
  }, [abierto]);

  useEffect(() => {
    if (!abierto) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape" && !bloqueado) onCerrar();
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [abierto, bloqueado, onCerrar]);

  if (!abierto) return null;

  return (
    <div
      className="fixed inset-0 z-40 flex justify-end bg-black/40"
      onClick={() => {
        if (!bloqueado) onCerrar();
      }}
    >
      <div
        ref={ref}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titulo ? tituloId : undefined}
        aria-label={titulo ? undefined : "Panel"}
        tabIndex={-1}
        // `min-w-0`: sin esto, este div —ítem flex del contenedor de arriba—
        // no se achica por debajo del "mínimo automático" que fija su
        // contenido (el ancho intrínseco del <select> con la opción más larga,
        // "Líder de equipo (encargada)"), y ese mínimo gana aunque sea mayor
        // que la pantalla — en un celular de 375px el panel terminaba
        // desbordando a 388px, cortando media palabra contra el borde. El
        // formulario original nunca lo sufrió porque vivía en flujo normal
        // (un div de bloque, no un ítem flex); ahora que flota en un
        // `flex justify-end`, hereda esta regla de flexbox.
        className={`h-full w-full min-w-0 ${ANCHO[ancho]} overflow-y-auto border-l border-sand bg-papel p-6 outline-none`}
        onClick={(e) => e.stopPropagation()}
      >
        {titulo && (
          <div className="mb-4 flex items-center justify-between gap-3">
            <h2 id={tituloId} className="font-serif text-lg font-medium text-tinta">
              {titulo}
            </h2>
            <button
              type="button"
              onClick={() => {
                if (!bloqueado) onCerrar();
              }}
              aria-label="Cerrar"
              className="rounded-full p-1 text-taupe hover:bg-sand/60 hover:text-tinta"
            >
              ×
            </button>
          </div>
        )}
        {children}
      </div>
    </div>
  );
}
