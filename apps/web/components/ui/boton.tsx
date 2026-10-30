// El botón primario ("rounded-lg bg-tinta px-4 py-2 text-sm font-medium
// text-crema disabled:opacity-50") aparece copiado, casi idéntico, en más de
// cuarenta sitios de admin — 23 de ellos con esa cadena exacta. Cada copia es
// una oportunidad de que alguien ajuste el tono de rojo en una pantalla y se
// le olvide en las otras 22.

import type { ButtonHTMLAttributes } from "react";
import { cx } from "./cx";

type Variante = "primario" | "secundario" | "peligro" | "sutil" | "enlace";
type Tamano = "sm" | "md" | "lg";

const CHROME: Record<Variante, string> = {
  // El hover y la duración de "bg-tinta" NO se declaran acá: los decide
  // globals.css:131 (fuera de @layer, así que gana sobre cualquier utilidad
  // de Tailwind) — prende en --color-rojo a 180ms. Escribir un
  // hover:bg-* o duration-* acá sería código muerto que nadie vería aplicarse.
  primario: "rounded-control bg-tinta text-crema active:scale-[0.98]",
  secundario:
    "rounded-control border border-borde-control transition-colors duration-150 hover:bg-sand/50 active:scale-[0.98]",
  peligro:
    "rounded-control border border-rojo/30 text-rojo transition-colors duration-150 hover:bg-rojo/10 active:scale-[0.98]",
  // Para acciones de bajo énfasis (marcar/desmarcar, agregar una fila, ver un
  // documento): a diferencia de "secundario" no rellena el fondo al pasar el
  // mouse, solo oscurece el texto.
  sutil:
    "rounded-control border border-sand text-taupe transition-colors duration-150 hover:text-tinta hover:bg-sand/30 active:scale-[0.98]",
  enlace: "underline underline-offset-2 transition-colors duration-150 hover:text-taupe",
};

// La escala sigue lo que el producto ya usaba a mano, no un valor inventado:
// medido en el código escrito antes de este primitivo, "px-3 py-1 text-xs"
// aparece 8 veces ("sm") y "px-5 py-2 text-sm" otras 4 ("lg", tamaño que
// faltaba y obligaba a pasar className a mano). "md" es el tamaño normal.
const TAMANOS: Record<Tamano, string> = {
  sm: "px-3 py-1 text-xs",
  md: "px-4 py-2 text-sm",
  lg: "px-5 py-2 text-sm",
};

export function Boton({
  variante = "secundario",
  tamano = "md",
  cargando = false,
  disabled,
  className,
  children,
  ...props
}: {
  variante?: Variante;
  tamano?: Tamano;
  /** Reemplaza el patrón "Guardando…" de texto por el colibrí de marca
   * aleteando (.colibri .aletea, ya existen en globals.css) — deshabilita el
   * botón mientras dure. No usar en pantallas de apps/web/app/(terminal)/: el
   * kiosco no importa este componente. */
  cargando?: boolean;
} & ButtonHTMLAttributes<HTMLButtonElement>) {
  return (
    <button
      type="button"
      disabled={disabled || cargando}
      className={cx(
        CHROME[variante],
        variante !== "enlace" && TAMANOS[tamano],
        "font-medium disabled:opacity-50",
        className,
      )}
      {...props}
    >
      {cargando && (
        <span className="colibri aletea mr-1.5 inline-block size-3.5 align-[-2px]" aria-hidden />
      )}
      {children}
    </button>
  );
}
