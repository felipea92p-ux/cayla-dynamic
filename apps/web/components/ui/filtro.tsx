// Filtro o pestaña de una lista (decisión 10 de docs/adr/0004-diseno-unificado.md).
// Esquina de botón (radio-control, 8 px) y NO píldora: lo que se puede tocar
// tiene forma de botón y lo que solo informa —<Insignia>— tiene forma de
// píldora, así nadie intenta tocar una insignia ni se pregunta si un filtro es
// una etiqueta. Hasta el 2026-10-13 los filtros se dibujaban de las dos formas.
//
// Activo = tinta sólida con texto crema (igual que el botón primario); inactivo
// = papel con borde sand. `aria-pressed` va siempre: es lo que lee el lector de
// pantalla para saber qué filtro está aplicado.

import type { ButtonHTMLAttributes, ReactNode } from "react";
import { cx } from "./cx";

export function Filtro({
  activo,
  children,
  className,
  ...props
}: {
  activo: boolean;
  children: ReactNode;
  className?: string;
} & Omit<ButtonHTMLAttributes<HTMLButtonElement>, "children" | "className" | "type" | "aria-pressed">) {
  return (
    <button
      type="button"
      aria-pressed={activo}
      className={cx(
        "shrink-0 whitespace-nowrap rounded-control border px-3 py-1.5 text-sm font-medium transition-colors duration-150",
        activo ? "border-tinta bg-tinta text-crema" : "border-sand bg-papel text-tinta hover:border-taupe",
        className,
      )}
      {...props}
    >
      {children}
    </button>
  );
}
