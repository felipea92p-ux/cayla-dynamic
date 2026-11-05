"use client";

import { useSyncExternalStore } from "react";
import { alternarTema, cambiarTema, suscribirTema, temaDelDocumento, textosDelBoton } from "@/lib/vidrio-tema";

// El botón del tema, el de Retail: 36 px, sin borde, y muestra a dónde vas. El ícono no lo decide React sino el CSS
// (`.boton-tema` en estilos/vidrio/marco.css), a partir del atributo que el guion ya puso: sale bien desde la primera pintura.
// React solo lleva el estado accesible, y el servidor siempre pinta el claro.
//
// `className` trae el «cuándo se ve», pensado para el botón viejo (`hidden md:inline-flex`). Las dos figuras comparten celda, así que
// aquí siempre es grid: por eso el reemplazo.
export function BotonTema({ className = "inline-grid" }: { className?: string }) {
  const tema = useSyncExternalStore(suscribirTema, temaDelDocumento, () => "claro" as const);
  const { etiqueta, titulo } = textosDelBoton(tema);
  return (
    <button
      type="button"
      onClick={() => cambiarTema(alternarTema(temaDelDocumento()))}
      aria-label={etiqueta}
      aria-pressed={tema === "oscuro"}
      title={titulo}
      className={`boton-tema ${className.replace("inline-flex", "inline-grid")} h-9 w-9 shrink-0 place-items-center rounded-lg text-tinta/65 transition-colors hover:bg-sand/60 hover:text-rojo`}
    >
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" aria-hidden className="tema-luna h-[18px] w-[18px]">
        <path d="M20.5 14.2A8.5 8.5 0 019.8 3.5a8.5 8.5 0 1010.7 10.7z" />
      </svg>
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" aria-hidden className="tema-sol h-[18px] w-[18px]">
        <circle cx="12" cy="12" r="4" />
        <path d="M12 2.5v2M12 19.5v2M4.6 4.6l1.4 1.4M18 18l1.4 1.4M2.5 12h2M19.5 12h2M4.6 19.4L6 18M18 6l1.4-1.4" />
      </svg>
    </button>
  );
}
