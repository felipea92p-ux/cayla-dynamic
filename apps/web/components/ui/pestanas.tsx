// Pestañas subrayadas (2026-10-19). La forma que Educación ya usaba escrita a mano: una raya bajo la
// pestaña activa, el resto en taupe. El ADR 0004 dejó esta pieza sin decidir (¿`Filtro` con una segunda
// cara, o una pieza propia?): se resuelve como pieza propia porque lo que cambia entre una pestaña y un
// filtro NO es el dibujo sino lo que hacen —una pestaña cambia DE QUÉ SE HABLA y un filtro cambia QUÉ
// SE VE de lo mismo—, y `aria-current` y `aria-pressed` no son lo mismo para un lector de pantalla.
//
// `aviso` es el número rojo de «hay algo aquí que atender» (el mismo de Educación); el color no va solo,
// el número se lee. En celular las pestañas se deslizan de lado en vez de partirse en dos líneas.

import type { ReactNode } from "react";
import { cx } from "./cx";

export function Pestanas<T extends string>({
  etiqueta,
  pestanas,
  activa,
  alElegir,
  enBarra = false,
  className,
}: {
  /** El nombre del grupo para el lector de pantalla: «Secciones del Dashboard». */
  etiqueta: string;
  pestanas: readonly { clave: T; texto: ReactNode; aviso?: number }[];
  activa: T;
  alElegir: (clave: T) => void;
  /**
   * Las pestañas van DENTRO de una barra con otros controles (Turnos: pestañas a la izquierda, sede y semana a la
   * derecha): la barra pone la línea de abajo y el margen, así que acá no se dibujan. Con la raya y el margen
   * propios, las pestañas quedaban 20 px más arriba que lo que tenían al lado.
   */
  enBarra?: boolean;
  className?: string;
}) {
  return (
    <nav
      aria-label={etiqueta}
      className={cx(
        enBarra ? "flex gap-1 overflow-x-auto [scrollbar-width:none]" : "-mx-4 mb-5 flex gap-1 overflow-x-auto border-b border-sand px-4 sm:mx-0 sm:px-0 [scrollbar-width:none]",
        className,
      )}
    >
      {pestanas.map((p) => (
        <button
          key={p.clave}
          type="button"
          aria-current={activa === p.clave ? "page" : undefined}
          onClick={() => alElegir(p.clave)}
          className={cx(
            "-mb-px flex shrink-0 items-center gap-1.5 border-b-2 px-3 py-2 text-sm transition-colors duration-150",
            activa === p.clave ? "border-tinta font-medium text-tinta" : "border-transparent text-taupe hover:text-tinta",
          )}
        >
          {p.texto}
          {p.aviso !== undefined && p.aviso > 0 && (
            <span className="rounded-full bg-rojo px-1.5 text-[11px] leading-4 text-crema">{p.aviso}</span>
          )}
        </button>
      ))}
    </nav>
  );
}
