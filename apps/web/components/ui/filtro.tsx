// Filtro o pestaña de una lista (decisión 10 de docs/adr/0004-diseno-unificado.md).
// Esquina de botón (radio-control, 8 px) y NO píldora: lo que se puede tocar
// tiene forma de botón y lo que solo informa —<Insignia>— tiene forma de
// píldora, así nadie intenta tocar una insignia ni se pregunta si un filtro es
// una etiqueta. Hasta el 2026-10-13 los filtros se dibujaban de las dos formas.
//
// Activo = tinta sólida con texto crema (igual que el botón primario); inactivo
// = papel con borde sand. `aria-pressed` va siempre: es lo que lee el lector de
// pantalla para saber qué filtro está aplicado.
//
// Dos tamaños, con el mismo vocabulario que <Boton> (2026-10-13, tras ver el
// piloto del Dashboard): «md» para los filtros de una lista, que se tocan todo
// el día; «sm» (px-3 py-1 text-xs, lo que esa fila ya usaba) para una fila de
// configuración como «Indicadores», que se toca una vez y no debe pesar más
// que lo que configura.

import type { ButtonHTMLAttributes, ReactNode } from "react";
import { cx } from "./cx";

const TAMANOS = {
  sm: "px-3 py-1 text-xs",
  md: "px-3 py-1.5 text-sm",
} as const;

export function Filtro({
  activo,
  tamano = "md",
  children,
  className,
  ...props
}: {
  activo: boolean;
  tamano?: keyof typeof TAMANOS;
  children: ReactNode;
  className?: string;
} & Omit<ButtonHTMLAttributes<HTMLButtonElement>, "children" | "className" | "type" | "aria-pressed">) {
  return (
    <button
      type="button"
      aria-pressed={activo}
      className={cx(
        "shrink-0 whitespace-nowrap rounded-control border font-medium transition-colors duration-150",
        TAMANOS[tamano],
        activo ? "border-tinta bg-tinta text-crema" : "border-sand bg-papel text-tinta hover:border-taupe",
        className,
      )}
      {...props}
    >
      {children}
    </button>
  );
}
