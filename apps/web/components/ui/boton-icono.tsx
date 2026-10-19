// Botón de un solo ícono (2026-10-19). Nació en el Dashboard: «Ver», «Ocultar» y «Alertas» eran tres
// botones con texto o enlaces subrayados de 16 px junto a avisos de una línea, y pesaban más que lo que
// controlaban. Un ícono lo dice con menos espacio SI su nombre accesible lo explica: por eso `etiqueta`
// es obligatoria —alimenta el `aria-label` y el globo (`title`)— y nunca se omite.
//
// Mismo vocabulario que <Boton variante="secundario">: esquina de botón, borde sand, papel. Dos tamaños:
// «sm» (28 px) para dentro de un aviso o de una tarjeta, «md» (32 px) suelto en una barra.
// `contador` es el número rojo de «hay algo aquí» (como el de las alertas críticas): el color no va solo,
// el número se lee.

import type { ButtonHTMLAttributes, ReactNode } from "react";
import { cx } from "./cx";

const TAMANOS = { sm: "size-7", md: "size-8" } as const;

export function BotonIcono({
  etiqueta,
  icono,
  tamano = "sm",
  contador,
  activo,
  className,
  ...props
}: {
  /** Qué hace, en palabras: «Ocultar alertas». Obligatoria. */
  etiqueta: string;
  icono: ReactNode;
  tamano?: keyof typeof TAMANOS;
  contador?: number;
  /** Para un botón que enciende un filtro («Solo alertas»): pone `aria-pressed` y lo pinta en tinta, igual que <Filtro>. */
  activo?: boolean;
  className?: string;
} & Omit<ButtonHTMLAttributes<HTMLButtonElement>, "children" | "className" | "type" | "aria-label" | "title">) {
  return (
    <button
      type="button"
      aria-label={etiqueta}
      title={etiqueta}
      aria-pressed={activo}
      className={cx(
        "relative inline-flex shrink-0 items-center justify-center rounded-control border transition-colors duration-150 focus-visible:outline-offset-2 [&_svg]:size-4",
        activo ? "border-tinta bg-tinta text-crema" : "border-sand bg-papel text-taupe hover:border-taupe hover:text-tinta",
        TAMANOS[tamano],
        className,
      )}
      {...props}
    >
      {icono}
      {contador !== undefined && contador > 0 && (
        <span className="absolute -right-1.5 -top-1.5 min-w-4 rounded-full bg-rojo px-1 text-center text-[10px] font-semibold leading-4 text-crema">{contador}</span>
      )}
    </button>
  );
}
